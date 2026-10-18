#define _GNU_SOURCE
#include "FreewheelArchive.h"
#include <archive.h>
#include <archive_entry.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
#define FW_MAX_ENTRIES 10000
#define FW_MAX_DIRECTORIES 20000
#define FW_MAX_BYTES ((uint64_t)2 * 1024 * 1024 * 1024)
#define FW_MAX_PATH 4096
#define FW_MAX_DEPTH 64

static int fail(char *error, size_t capacity, const char *message) {
    if (capacity && error) snprintf(error, capacity, "%s", message ? message : "Archive operation failed.");
    return -1;
}

static int archive_fail(struct archive *archive, char *error, size_t capacity, const char *fallback) {
    const char *message = archive_error_string(archive);
    return fail(error, capacity, message ? message : fallback);
}

/* Normalize harmless leading ./ components, but never accept traversal or Windows paths. */
static int safe_path(const char *input, char output[FW_MAX_PATH]) {
    if (!input || !*input || input[0] == '/' || strlen(input) >= FW_MAX_PATH || strchr(input, '\\') || strchr(input, ':')) return -1;
    size_t used = 0;
    unsigned depth = 0;
    const char *cursor = input;
    while (*cursor) {
        const char *end = strchr(cursor, '/');
        size_t length = end ? (size_t)(end - cursor) : strlen(cursor);
        if (length == 2 && cursor[0] == '.' && cursor[1] == '.') return -1;
        if (length && !(length == 1 && cursor[0] == '.')) {
            if (++depth > FW_MAX_DEPTH || used + length + 2 >= FW_MAX_PATH) return -1;
            if (used) output[used++] = '/';
            memcpy(output + used, cursor, length); used += length;
        }
        if (!end) break;
        cursor = end + 1;
    }
    output[used] = '\0';
    return used ? 0 : 1;
}

/* Opens each component relative to an already-open private root. O_NOFOLLOW applies at every level. */
static int open_parent(int root, const char *path, char **leaf, char **storage, unsigned *directories,
                       char *error, size_t error_capacity) {
    char *copy = strdup(path);
    if (!copy) return fail(error, error_capacity, "Not enough memory to process archive paths.");
    int parent = dup(root);
    if (parent < 0) { free(copy); return fail(error, error_capacity, "Could not open archive output folder."); }
    char *cursor = copy;
    char *slash;
    while ((slash = strchr(cursor, '/'))) {
        *slash = '\0';
        if (mkdirat(parent, cursor, 0700) == 0) {
            if (++*directories > FW_MAX_DIRECTORIES) {
                close(parent); free(copy); return fail(error, error_capacity, "Archive contains too many folders.");
            }
        } else if (errno != EEXIST) {
            close(parent); free(copy); return fail(error, error_capacity, "Could not create an archive folder.");
        }
        int next = openat(parent, cursor, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        close(parent);
        if (next < 0) { free(copy); return fail(error, error_capacity, "Archive path crosses a link or non-folder entry."); }
        parent = next; cursor = slash + 1;
    }
    *leaf = cursor; *storage = copy;
    return parent;
}

int fw_archive_extract(const char *input_path, const char *output_directory,
                       const char *raw_filename, int allow_raw,
                       char *error, size_t error_capacity, fw_cancel_callback cancelled, void *context) {
    if (error && error_capacity) error[0] = '\0';
    int root = open(output_directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root < 0) return fail(error, error_capacity, "Could not open the private extraction folder.");
    int input = open(input_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (input < 0) { close(root); return fail(error, error_capacity, "Could not open the archive."); }
    struct stat input_info;
    if (fstat(input, &input_info) || !S_ISREG(input_info.st_mode)) {
        close(input); close(root); return fail(error, error_capacity, "The archive must be a regular file.");
    }
    struct archive *reader = archive_read_new();
    if (!reader) { close(input); close(root); return fail(error, error_capacity, "Could not allocate an archive reader."); }
    /* Built-in filters only: libarchive must never spawn an external decompressor. */
    archive_read_support_filter_none(reader);
    const char *extension = strrchr(input_path, '.');
    int filter_status = ARCHIVE_OK;
    if (extension && (!strcasecmp(extension, ".gz") || !strcasecmp(extension, ".tgz"))) filter_status = archive_read_support_filter_gzip(reader);
    else if (extension && !strcasecmp(extension, ".bz2")) filter_status = archive_read_support_filter_bzip2(reader);
    else if (extension && !strcasecmp(extension, ".xz")) filter_status = archive_read_support_filter_xz(reader);
    if (filter_status != ARCHIVE_OK) {
        archive_read_free(reader); close(input); close(root);
        return fail(error, error_capacity, "This compression filter is not built into the system archive library.");
    }
    archive_read_support_format_all(reader);
    if (allow_raw) archive_read_support_format_raw(reader);
    int result = 0;
    if (archive_read_open_fd(reader, input, 65536) != ARCHIVE_OK) {
        result = archive_fail(reader, error, error_capacity, "Could not read the archive."); goto cleanup;
    }
    unsigned entries = 0, directories = 0;
    uint64_t declared_total = 0, actual_total = 0;
    struct archive_entry *entry;
    int status;
    while ((status = archive_read_next_header(reader, &entry)) == ARCHIVE_OK) {
        if (cancelled && cancelled(context)) { result = fail(error, error_capacity, "Operation cancelled."); break; }
        if (++entries > FW_MAX_ENTRIES) { result = fail(error, error_capacity, "Archive exceeds the 10,000-entry safety limit."); break; }
        if (archive_entry_is_encrypted(entry) == 1) { result = fail(error, error_capacity, "Encrypted archives are not supported."); break; }
        int raw = (archive_format(reader) & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_RAW;
        if (raw && (!allow_raw || archive_filter_code(reader, 0) == ARCHIVE_FILTER_NONE)) {
            result = fail(error, error_capacity, "This file is not a supported compressed archive."); break;
        }
        const char *original_name = raw ? raw_filename : archive_entry_pathname(entry);
        char path[FW_MAX_PATH];
        int path_status = safe_path(original_name, path);
        mode_t kind = archive_entry_filetype(entry);
        if (archive_entry_symlink(entry) || archive_entry_hardlink(entry) || (kind != AE_IFREG && kind != AE_IFDIR)) {
            result = fail(error, error_capacity, "Archive contains a link, device, or other unsafe file type."); break;
        }
        if (path_status < 0) { result = fail(error, error_capacity, "Archive contains an absolute, traversing, or unsafe path."); break; }
        if (path_status == 1) {
            if (kind == AE_IFDIR) { archive_read_data_skip(reader); continue; }
            result = fail(error, error_capacity, "Archive contains an empty filename."); break;
        }
        la_int64_t declared = archive_entry_size(entry);
        if (declared < 0 || (uint64_t)declared > FW_MAX_BYTES || declared_total > FW_MAX_BYTES - (uint64_t)declared) {
            result = fail(error, error_capacity, "Archive exceeds the 2 GiB extraction limit."); break;
        }
        declared_total += (uint64_t)declared;
        char *leaf = NULL, *storage = NULL;
        int parent = open_parent(root, path, &leaf, &storage, &directories, error, error_capacity);
        if (parent < 0) { result = -1; break; }
        if (kind == AE_IFDIR) {
            if (mkdirat(parent, leaf, 0700) == 0) {
                if (++directories > FW_MAX_DIRECTORIES) result = fail(error, error_capacity, "Archive contains too many folders.");
            } else if (errno != EEXIST) result = fail(error, error_capacity, "Could not create an archive folder.");
            int directory = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (directory < 0) result = fail(error, error_capacity, "Archive folder conflicts with another entry.");
            else close(directory);
            archive_read_data_skip(reader);
        } else {
            int output = openat(parent, leaf, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
            if (output < 0) result = fail(error, error_capacity, "Archive contains a duplicate filename or an unsafe output path.");
            else {
                char buffer[65536];
                la_ssize_t count;
                while ((count = archive_read_data(reader, buffer, sizeof(buffer))) > 0) {
                    if (cancelled && cancelled(context)) { result = fail(error, error_capacity, "Operation cancelled."); break; }
                    if (actual_total > FW_MAX_BYTES - (uint64_t)count) {
                        result = fail(error, error_capacity, "Archive exceeds the 2 GiB extraction limit."); break;
                    }
                    actual_total += (uint64_t)count;
                    size_t offset = 0;
                    while (offset < (size_t)count) {
                        ssize_t written = write(output, buffer + offset, (size_t)count - offset);
                        if (written < 0 && errno == EINTR) continue;
                        if (written <= 0) { result = fail(error, error_capacity, "Could not write an extracted file. Check available disk space."); break; }
                        offset += (size_t)written;
                    }
                    if (result) break;
                }
                if (count < 0 && !result) result = archive_fail(reader, error, error_capacity, "Archive data is damaged.");
                if (close(output) && !result) result = fail(error, error_capacity, "Could not finish writing an extracted file.");
            }
        }
        close(parent); free(storage);
        if (result) break;
    }
    if (!result && status != ARCHIVE_EOF) result = archive_fail(reader, error, error_capacity, "Archive headers are damaged or unsupported.");
    if (!result && entries == 0) result = fail(error, error_capacity, "The archive contains no entries.");
cleanup:
    archive_read_close(reader); archive_read_free(reader); close(input); close(root);
    return result;
}

struct write_context {
    struct archive *writer;
    unsigned entries;
    uint64_t total;
    char *error;
    size_t error_capacity;
    fw_cancel_callback cancelled;
    void *cancellation_context;
};

static int add_entry(struct write_context *context, int parent, const char *source_name, const char *entry_name, unsigned depth) {
    if (context->cancelled && context->cancelled(context->cancellation_context)) return fail(context->error, context->error_capacity, "Operation cancelled.");
    if (depth > FW_MAX_DEPTH || ++context->entries > FW_MAX_ENTRIES)
        return fail(context->error, context->error_capacity, "Archive exceeds the folder-depth or 10,000-entry limit.");
    char normalized[FW_MAX_PATH];
    if (safe_path(entry_name, normalized) != 0)
        return fail(context->error, context->error_capacity, "An input filename cannot be represented safely in an archive.");
    int input = openat(parent, source_name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (input < 0) return fail(context->error, context->error_capacity, "Could not open an archive input, or an input is a symbolic link.");
    struct stat info;
    if (fstat(input, &info) || (!S_ISREG(info.st_mode) && !S_ISDIR(info.st_mode))) {
        close(input); return fail(context->error, context->error_capacity, "Archive inputs must be regular files and folders; links and devices are not included.");
    }
    if (info.st_size < 0 || (S_ISREG(info.st_mode) && ((uint64_t)info.st_size > FW_MAX_BYTES || context->total > FW_MAX_BYTES - (uint64_t)info.st_size))) {
        close(input); return fail(context->error, context->error_capacity, "Archive inputs exceed the 2 GiB limit.");
    }
    struct archive_entry *entry = archive_entry_new();
    if (!entry) { close(input); return fail(context->error, context->error_capacity, "Could not allocate an archive entry."); }
    archive_entry_set_pathname(entry, normalized);
    archive_entry_set_filetype(entry, S_ISDIR(info.st_mode) ? AE_IFDIR : AE_IFREG);
    archive_entry_set_perm(entry, info.st_mode & 0777);
    archive_entry_set_uid(entry, 0); archive_entry_set_gid(entry, 0);
    archive_entry_set_mtime(entry, info.st_mtime, 0);
    archive_entry_set_size(entry, S_ISREG(info.st_mode) ? info.st_size : 0);
    int result = 0;
    if (archive_write_header(context->writer, entry) != ARCHIVE_OK) result = archive_fail(context->writer, context->error, context->error_capacity, "Could not write an archive entry.");
    archive_entry_free(entry);
    if (!result && S_ISREG(info.st_mode)) {
        char buffer[65536];
        ssize_t count;
        uint64_t file_total = 0;
        while ((count = read(input, buffer, sizeof(buffer))) != 0) {
            if (context->cancelled && context->cancelled(context->cancellation_context)) { result = fail(context->error, context->error_capacity, "Operation cancelled."); break; }
            if (count < 0 && errno == EINTR) continue;
            if (count < 0) { result = fail(context->error, context->error_capacity, "Could not read an archive input."); break; }
            if (context->total > FW_MAX_BYTES - (uint64_t)count || file_total + (uint64_t)count > (uint64_t)info.st_size) {
                result = fail(context->error, context->error_capacity, "An archive input grew while it was being read, or exceeded the size limit."); break;
            }
            context->total += (uint64_t)count; file_total += (uint64_t)count;
            size_t offset = 0;
            while (offset < (size_t)count) {
                la_ssize_t written = archive_write_data(context->writer, buffer + offset, (size_t)count - offset);
                if (written <= 0) { result = archive_fail(context->writer, context->error, context->error_capacity, "Could not write compressed data."); break; }
                offset += (size_t)written;
            }
            if (result) break;
        }
        if (!result && file_total != (uint64_t)info.st_size) result = fail(context->error, context->error_capacity, "An archive input changed while it was being read.");
    } else if (!result && S_ISDIR(info.st_mode)) {
        int directory_fd = dup(input);
        DIR *directory = directory_fd < 0 ? NULL : fdopendir(directory_fd);
        if (!directory) {
            if (directory_fd >= 0) close(directory_fd);
            result = fail(context->error, context->error_capacity, "Could not enumerate an input folder.");
        } else {
            struct dirent *child;
            errno = 0;
            while ((child = readdir(directory))) {
                if (!strcmp(child->d_name, ".") || !strcmp(child->d_name, "..")) continue;
                char nested[FW_MAX_PATH];
                int length = snprintf(nested, sizeof(nested), "%s/%s", normalized, child->d_name);
                if (length < 0 || (size_t)length >= sizeof(nested)) { result = fail(context->error, context->error_capacity, "An input path is too long."); break; }
                result = add_entry(context, input, child->d_name, nested, depth + 1);
                if (result) break;
                errno = 0;
            }
            if (!result && errno) result = fail(context->error, context->error_capacity, "Could not completely enumerate an input folder.");
            closedir(directory);
        }
    }
    close(input);
    return result;
}

int fw_archive_create(const char *const *input_paths, const char *const *entry_names,
                      size_t input_count, const char *output_path, int format,
                      char *error, size_t error_capacity, fw_cancel_callback cancelled, void *cancellation_context) {
    if (error && error_capacity) error[0] = '\0';
    if (!input_count || input_count > FW_MAX_ENTRIES) return fail(error, error_capacity, "Select between 1 and 10,000 archive inputs.");
    if (format == FW_ARCHIVE_GZIP && input_count != 1) return fail(error, error_capacity, "Gzip accepts one regular file at a time.");
    struct archive *writer = archive_write_new();
    if (!writer) return fail(error, error_capacity, "Could not allocate an archive writer.");
    int result = 0, output = -1, status = ARCHIVE_FATAL;
    if (format == FW_ARCHIVE_ZIP) {
        status = archive_write_set_format_zip(writer);
        if (status == ARCHIVE_OK) status = archive_write_set_options(writer, "zip:compression=deflate");
    } else if (format == FW_ARCHIVE_TAR) status = archive_write_set_format_pax_restricted(writer);
    else if (format == FW_ARCHIVE_GZIP) {
        status = archive_write_set_format_raw(writer);
        if (status == ARCHIVE_OK) status = archive_write_add_filter_gzip(writer);
    }
    if (status != ARCHIVE_OK) { result = archive_fail(writer, error, error_capacity, "This archive format is unavailable."); goto cleanup; }
    output = open(output_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (output < 0) { result = fail(error, error_capacity, "Could not create a new archive without replacing an existing file."); goto cleanup; }
    if (archive_write_open_fd(writer, output) != ARCHIVE_OK) { result = archive_fail(writer, error, error_capacity, "Could not initialize archive output."); goto cleanup; }
    struct write_context context = { writer, 0, 0, error, error_capacity, cancelled, cancellation_context };
    for (size_t i = 0; i < input_count; i++) {
        result = add_entry(&context, AT_FDCWD, input_paths[i], entry_names[i], 0);
        if (result) break;
    }
cleanup:
    if (archive_write_close(writer) != ARCHIVE_OK && !result) result = archive_fail(writer, error, error_capacity, "Could not finish the archive.");
    archive_write_free(writer);
    if (output >= 0) {
        if (close(output) && !result) result = fail(error, error_capacity, "Could not save the archive.");
        if (result) unlink(output_path);
    }
    return result;
}
