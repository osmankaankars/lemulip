/*
 * D22: a single owned native sampling target. No application, input, recording,
 * permission, or settings APIs are used. The ready receipt is published from
 * the named frame that subsequently waits for cooperative stdin EOF.
 */

#if !defined(__APPLE__)
#error "NativeSamplerCalibration requires native macOS"
#endif
#ifndef D22_SOURCE_SHA256
#error "Compile with the exact D22_SOURCE_SHA256 source-file digest"
#endif

#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <mach/machine.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <poll.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define D22_SAFETY_SECONDS 15
#define D22_RECEIPT_BYTES 32768U
#define D22_EXECUTABLE_BYTES (16U * 1024U * 1024U)
#define D22_EXPECTED_FRAME "lemulip_d22_wait_for_release"

static const char compiled_source_sha256[] = D22_SOURCE_SHA256;

struct native_clock {
    uint64_t absolute_before, absolute_after;
    uint64_t continuous_before, continuous_after;
    uint64_t wall_ns;
    double uptime;
};

struct output_path {
    int directory;
    char name[NAME_MAX + 1];
    char pending[NAME_MAX + 1];
};

struct arguments {
    const char *ready, *completion, *nonce, *executable, *sha256, *uuid;
    const char *architecture, *source_sha256, *commit, *tree;
};

struct identity {
    pid_t pid, ppid, pgid;
    uid_t euid;
    char executable[PATH_MAX], sha256[65], uuid[37], boot_uuid[37];
    const char *architecture;
    int translation_rc, translation_errno, translation_value;
};

struct context {
    struct arguments args;
    struct identity identity;
    struct output_path ready, completion;
    mach_timebase_info_data_t timebase;
    struct native_clock start, readiness;
    size_t ready_bytes;
    char ready_sha256[65];
};

struct json_buffer {
    char bytes[D22_RECEIPT_BYTES];
    size_t length;
    bool valid;
};

static int fail(const char *message) {
    int saved = errno;
    (void)fprintf(stderr, "NativeSamplerCalibration: %s (errno=%d)\n", message, saved);
    return -1;
}

static bool hexadecimal(const char *value, size_t count) {
    if (value == NULL || strlen(value) != count) return false;
    for (size_t index = 0; index < count; ++index) {
        char ch = value[index];
        if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'))) return false;
    }
    return true;
}

static bool canonical_uuid(const char *value) {
    if (value == NULL || strlen(value) != 36) return false;
    for (size_t index = 0; index < 36; ++index) {
        char ch = value[index];
        if (index == 8 || index == 13 || index == 18 || index == 23) {
            if (ch != '-') return false;
        } else if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') ||
                     (ch >= 'A' && ch <= 'F'))) return false;
    }
    return true;
}

static void uuid_text(const uint8_t bytes[16], char result[37]) {
    (void)snprintf(result, 37,
                   "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                   (unsigned)bytes[0], (unsigned)bytes[1], (unsigned)bytes[2], (unsigned)bytes[3],
                   (unsigned)bytes[4], (unsigned)bytes[5], (unsigned)bytes[6], (unsigned)bytes[7],
                   (unsigned)bytes[8], (unsigned)bytes[9], (unsigned)bytes[10], (unsigned)bytes[11],
                   (unsigned)bytes[12], (unsigned)bytes[13], (unsigned)bytes[14], (unsigned)bytes[15]);
}

static int parse_arguments(int argc, char **argv, struct arguments *args) {
    struct { const char *name; const char **value; } options[] = {
        {"--ready", &args->ready}, {"--completion", &args->completion},
        {"--nonce", &args->nonce}, {"--expected-executable", &args->executable},
        {"--expected-sha256", &args->sha256}, {"--expected-uuid", &args->uuid},
        {"--expected-architecture", &args->architecture}, {"--source-sha256", &args->source_sha256},
        {"--experiment-commit", &args->commit}, {"--experiment-tree", &args->tree}
    };
    size_t count = sizeof(options) / sizeof(options[0]);
    if (argc != 1 + (int)(2 * count)) return fail("Require each of the ten fixed argument/value pairs");
    for (int index = 1; index < argc; index += 2) {
        bool found = false;
        for (size_t option = 0; option < count; ++option) {
            if (strcmp(argv[index], options[option].name) != 0) continue;
            if (*options[option].value != NULL) return fail("A fixed argument was repeated");
            *options[option].value = argv[index + 1];
            found = true;
            break;
        }
        if (!found) return fail("An unknown argument was supplied");
    }
    if (!canonical_uuid(args->nonce) || !canonical_uuid(args->uuid) ||
        !hexadecimal(args->sha256, 64) || !hexadecimal(args->source_sha256, 64) ||
        !hexadecimal(compiled_source_sha256, 64) || !hexadecimal(args->commit, 40) ||
        !hexadecimal(args->tree, 40) || strcmp(args->source_sha256, compiled_source_sha256) != 0)
        return fail("Malformed or mismatched declared source/build identities");
    if (strcmp(args->architecture, "arm64") != 0 && strcmp(args->architecture, "x86_64") != 0)
        return fail("Unsupported expected native architecture");
    if (strcmp(args->ready, args->completion) == 0) return fail("Ready and completion paths must differ");
    return 0;
}

static int prepare_output(const char *path, struct output_path *output) {
    char parent[PATH_MAX], canonical[PATH_MAX];
    if (path == NULL || path[0] != '/' || strlen(path) >= sizeof(parent))
        return fail("Receipt path must be a bounded absolute path");
    const char *slash = strrchr(path, '/');
    size_t parent_length = (size_t)(slash - path);
    const char *name = slash + 1;
    if (parent_length == 0 || name[0] == '\0' || strcmp(name, ".") == 0 || strcmp(name, "..") == 0 ||
        strlen(name) + strlen(".pending") > NAME_MAX)
        return fail("Receipt path needs an existing canonical parent and a simple filename");
    memcpy(parent, path, parent_length);
    parent[parent_length] = '\0';
    if (realpath(parent, canonical) == NULL || strcmp(parent, canonical) != 0)
        return fail("Receipt parent is not an existing canonical directory");
    output->directory = open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (output->directory < 0) return fail("Could not open the receipt directory");
    (void)snprintf(output->name, sizeof(output->name), "%s", name);
    (void)snprintf(output->pending, sizeof(output->pending), "%s.pending", name);
    struct stat info;
    if (fstatat(output->directory, output->name, &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT)
        return fail("Refusing an existing or inaccessible receipt path");
    if (fstatat(output->directory, output->pending, &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT)
        return fail("Refusing an existing or inaccessible pending receipt");
    return 0;
}

static void digest_hex(const uint8_t bytes[CC_SHA256_DIGEST_LENGTH], char result[65]) {
    static const char digits[] = "0123456789abcdef";
    for (size_t index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
        result[2 * index] = digits[bytes[index] >> 4];
        result[2 * index + 1] = digits[bytes[index] & 15];
    }
    result[64] = '\0';
}

/* Bounded hashing uses the public CommonCrypto SHA-256 declarations. */
static int memory_sha256(const void *bytes, size_t count, char result[65]) {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    if (count > UINT32_MAX || CC_SHA256(bytes, (CC_LONG)count, digest) == NULL)
        return fail("Could not hash the bounded receipt");
    digest_hex(digest, result);
    return 0;
}

static int file_sha256(const char *path, char result[65]) {
    int descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) return fail("Could not open the observed executable");
    struct stat before, after;
    CC_SHA256_CTX hash;
    uint8_t buffer[16384], digest[CC_SHA256_DIGEST_LENGTH];
    size_t total = 0;
    int status = -1;
    if (fstat(descriptor, &before) != 0 || !S_ISREG(before.st_mode) || before.st_size <= 0 ||
        before.st_size > (off_t)D22_EXECUTABLE_BYTES || CC_SHA256_Init(&hash) != 1) goto finished;
    while (total <= D22_EXECUTABLE_BYTES) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) goto finished;
        if (count == 0) break;
        total += (size_t)count;
        if (total > D22_EXECUTABLE_BYTES || CC_SHA256_Update(&hash, buffer, (CC_LONG)count) != 1) goto finished;
    }
    if (fstat(descriptor, &after) != 0 || total != (size_t)before.st_size ||
        before.st_dev != after.st_dev || before.st_ino != after.st_ino || before.st_size != after.st_size ||
        before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec || before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec ||
        before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec ||
        CC_SHA256_Final(digest, &hash) != 1) goto finished;
    digest_hex(digest, result);
    status = 0;
finished:
    if (close(descriptor) != 0) status = -1;
    return status == 0 ? 0 : fail("Executable hashing failed its bounded unchanged-file checks");
}

static int loaded_image(struct identity *identity) {
    const char *loaded_path = _dyld_get_image_name(0);
    const struct mach_header *header = _dyld_get_image_header(0);
    if (loaded_path == NULL || loaded_path[0] != '/' || realpath(loaded_path, identity->executable) == NULL ||
        header == NULL || header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE ||
        header->ncmds == 0 || header->ncmds > 4096 || header->sizeofcmds > D22_EXECUTABLE_BYTES)
        return fail("Main loaded image identity is unavailable or unsupported");
#if defined(__arm64__) || defined(__aarch64__)
    identity->architecture = "arm64";
    if (header->cputype != CPU_TYPE_ARM64) return fail("Main image CPU differs from the compiled architecture");
#elif defined(__x86_64__)
    identity->architecture = "x86_64";
    if (header->cputype != CPU_TYPE_X86_64) return fail("Main image CPU differs from the compiled architecture");
#else
#error "Unsupported native architecture"
#endif
    const uint8_t *cursor = (const uint8_t *)header + sizeof(struct mach_header_64);
    size_t remaining = header->sizeofcmds;
    unsigned uuid_count = 0;
    for (uint32_t index = 0; index < header->ncmds; ++index) {
        if (remaining < sizeof(struct load_command)) return fail("Truncated main-image load-command table");
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > remaining || command->cmdsize % 8 != 0)
            return fail("Malformed main-image load-command extent");
        if (command->cmd == LC_UUID) {
            if (command->cmdsize != sizeof(struct uuid_command) || ++uuid_count != 1)
                return fail("Main image must contain exactly one well-formed UUID command");
            uuid_text(((const struct uuid_command *)command)->uuid, identity->uuid);
        }
        cursor += command->cmdsize;
        remaining -= command->cmdsize;
    }
    if (remaining != 0 || uuid_count != 1) return fail("Main-image UUID/load-command coverage is incomplete");
    return 0;
}

static int inspect_identity(struct context *context, struct identity *identity) {
    memset(identity, 0, sizeof(*identity));
    identity->pid = getpid();
    identity->ppid = getppid();
    identity->pgid = getpgrp();
    identity->euid = geteuid();
    if (identity->pid <= 1 || identity->ppid <= 1 || identity->pgid != identity->pid)
        return fail("Target must be a direct owned session/group leader");
    if (loaded_image(identity) != 0 || strcmp(identity->executable, context->args.executable) != 0 ||
        strcmp(identity->architecture, context->args.architecture) != 0 ||
        strcasecmp(identity->uuid, context->args.uuid) != 0 ||
        file_sha256(identity->executable, identity->sha256) != 0 ||
        strcmp(identity->sha256, context->args.sha256) != 0)
        return fail("Observed native image does not match the supplied build identities");
    int translated = -1;
    size_t length = sizeof(translated);
    errno = 0;
    identity->translation_rc = sysctlbyname("sysctl.proc_translated", &translated, &length, NULL, 0);
    identity->translation_errno = errno;
    identity->translation_value = translated;
    if (!((identity->translation_rc == 0 && identity->translation_errno == 0 && length == sizeof(translated) && translated == 0) ||
          (identity->translation_rc == -1 && identity->translation_errno == ENOENT)))
        return fail("Native execution could not be established");
    char boot[128] = {0};
    length = sizeof(boot);
    if (sysctlbyname("kern.bootsessionuuid", boot, &length, NULL, 0) != 0 || length < 37 || length > sizeof(boot) ||
        memchr(boot, '\0', length) == NULL || !canonical_uuid(boot))
        return fail("Boot-session identity is unavailable");
    (void)snprintf(identity->boot_uuid, sizeof(identity->boot_uuid), "%s", boot);
    for (size_t index = 0; index < 36; ++index) {
        char ch = identity->boot_uuid[index];
        if (ch >= 'a' && ch <= 'f') identity->boot_uuid[index] = (char)(ch - 'a' + 'A');
    }
    return 0;
}

static double ticks_seconds(const struct context *context, uint64_t ticks) {
    return ((double)ticks * context->timebase.numer / context->timebase.denom) / 1000000000.0;
}

static int capture_clock(const struct context *context, struct native_clock *clock) {
    struct timespec wall;
    clock->absolute_before = mach_absolute_time();
    clock->continuous_before = mach_continuous_time();
    int result = clock_gettime(CLOCK_REALTIME, &wall);
    clock->continuous_after = mach_continuous_time();
    clock->absolute_after = mach_absolute_time();
    if (result != 0 || wall.tv_sec < 0 || wall.tv_nsec < 0 || wall.tv_nsec >= 1000000000 ||
        (uint64_t)wall.tv_sec > (UINT64_MAX - (uint64_t)wall.tv_nsec) / UINT64_C(1000000000) ||
        clock->absolute_before > clock->absolute_after || clock->continuous_before > clock->continuous_after)
        return fail("Native clock sampling failed");
    clock->wall_ns = (uint64_t)wall.tv_sec * UINT64_C(1000000000) + (uint64_t)wall.tv_nsec;
    clock->uptime = ticks_seconds(context, clock->absolute_before);
    return 0;
}

static void append_format(struct json_buffer *json, const char *format, ...) {
    if (!json->valid) return;
    va_list arguments;
    va_start(arguments, format);
    int count = vsnprintf(json->bytes + json->length, sizeof(json->bytes) - json->length, format, arguments);
    va_end(arguments);
    if (count < 0 || (size_t)count >= sizeof(json->bytes) - json->length) json->valid = false;
    else json->length += (size_t)count;
}

static void append_string(struct json_buffer *json, const char *value) {
    append_format(json, "\"");
    for (const unsigned char *cursor = (const unsigned char *)value; *cursor != 0; ++cursor) {
        if (*cursor == '\\' || *cursor == '"') append_format(json, "\\%c", (int)*cursor);
        else if (*cursor < 0x20) append_format(json, "\\u%04x", (unsigned)*cursor);
        else append_format(json, "%c", (int)*cursor);
    }
    append_format(json, "\"");
}

static void string_field(struct json_buffer *json, const char *name, const char *value) {
    append_format(json, ",\n  \"%s\": ", name);
    append_string(json, value);
}

static void clock_field(struct json_buffer *json, const char *name, const struct native_clock *clock) {
    append_format(json, ",\n  \"%s\": {\"machAbsoluteBefore\": %" PRIu64 ", \"machAbsoluteAfter\": %" PRIu64
                  ", \"machContinuousBefore\": %" PRIu64 ", \"machContinuousAfter\": %" PRIu64
                  ", \"systemUptime\": %.9f, \"wallTimeUnixNS\": %" PRIu64 "}",
                  name, clock->absolute_before, clock->absolute_after, clock->continuous_before,
                  clock->continuous_after, clock->uptime, clock->wall_ns);
}

static void common_json(struct context *context, struct json_buffer *json, const char *kind) {
    memset(json, 0, sizeof(*json));
    json->valid = true;
    append_format(json, "{\n  \"schema\": 1");
    string_field(json, "kind", kind);
    append_format(json, ",\n  \"pid\": %ld, \"ppid\": %ld, \"pgid\": %ld, \"euid\": %lu",
                  (long)context->identity.pid, (long)context->identity.ppid, (long)context->identity.pgid,
                  (unsigned long)context->identity.euid);
    string_field(json, "executablePath", context->identity.executable);
    string_field(json, "executableSHA256", context->identity.sha256);
    string_field(json, "machOUUID", context->identity.uuid);
    string_field(json, "architecture", context->identity.architecture);
    string_field(json, "nonce", context->args.nonce);
    string_field(json, "sourceSHA256", compiled_source_sha256);
    string_field(json, "experimentCommit", context->args.commit);
    string_field(json, "experimentTree", context->args.tree);
    string_field(json, "expectedFrame", D22_EXPECTED_FRAME);
    string_field(json, "bootUUID", context->identity.boot_uuid);
    append_format(json, ",\n  \"identityValidated\": true, \"nativeInputExecuted\": false, \"settingsChanged\": false,"
                  "\n  \"applicationLaunchRequested\": false, \"recordingRequested\": false,"
                  "\n  \"safetyTimeoutSeconds\": %d, \"machTimebaseNumer\": %u, \"machTimebaseDenom\": %u,"
                  "\n  \"translationProbe\": {\"returnCode\": %d, \"errno\": %d, \"value\": ",
                  D22_SAFETY_SECONDS, context->timebase.numer, context->timebase.denom,
                  context->identity.translation_rc, context->identity.translation_errno);
    if (context->identity.translation_rc == 0) append_format(json, "%d", context->identity.translation_value);
    else append_format(json, "null");
    append_format(json, "}");
    clock_field(json, "nativeStartClock", &context->start);
    clock_field(json, "readinessClock", &context->readiness);
}

static int publish_json(struct output_path *path, const struct json_buffer *json) {
    if (!json->valid || json->length == 0 || json->length >= D22_RECEIPT_BYTES)
        return fail("Receipt exceeded its bounded JSON buffer");
    int descriptor = openat(path->directory, path->pending,
                            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR);
    if (descriptor < 0) return fail("Could not exclusively create the pending receipt");
    size_t written = 0;
    while (written < json->length) {
        ssize_t count = write(descriptor, json->bytes + written, json->length - written);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            (void)close(descriptor);
            return fail("Could not write the complete receipt");
        }
        written += (size_t)count;
    }
    int sync_result = fsync(descriptor);
    int close_result = close(descriptor);
    if (sync_result != 0 || close_result != 0) return fail("Could not synchronize and close the receipt");
    if (linkat(path->directory, path->pending, path->directory, path->name, 0) != 0)
        return fail("Could not exclusively publish the completed receipt");
    if (unlinkat(path->directory, path->pending, 0) != 0)
        return fail("Could not remove the published pending link");
    return 0;
}

/* This externally visible frame deliberately contains both publication and
 * blocking. It is built without inlining, sibling-call optimization or frame
 * pointer omission. No tail call can replace it: completion follows the wait. */
__attribute__((noinline, used, visibility("default")))
int lemulip_d22_wait_for_release(struct context *context) {
    struct json_buffer json;
    if (capture_clock(context, &context->readiness) != 0) return 2;
    common_json(context, &json, "d22-sampler-calibration-ready");
    append_format(&json, ",\n  \"expectedFrameEntered\": true, \"receivedInputBytes\": 0\n}\n");
    if (!json.valid || memory_sha256(json.bytes, json.length, context->ready_sha256) != 0 ||
        publish_json(&context->ready, &json) != 0) return 2;
    context->ready_bytes = json.length;

    const char *reason = "wait-error";
    bool eof = false, timed_out = false;
    size_t received = 0;
    for (;;) {
        uint64_t now = mach_continuous_time();
        if (now < context->start.continuous_before) break;
        double remaining = D22_SAFETY_SECONDS - ticks_seconds(context, now - context->start.continuous_before);
        if (remaining <= 0) {
            reason = "safety-timeout";
            timed_out = true;
            break;
        }
        int milliseconds = (int)(remaining * 1000.0) + 1;
        struct pollfd input = {.fd = STDIN_FILENO, .events = POLLIN | POLLHUP, .revents = 0};
        int result = poll(&input, 1, milliseconds);
        if (result < 0 && errno == EINTR) continue;
        if (result < 0 || (result > 0 && (input.revents & (POLLERR | POLLNVAL)) != 0)) break;
        if (result == 0) continue;
        if ((input.revents & (POLLIN | POLLHUP)) != 0) {
            unsigned char byte;
            ssize_t count = read(STDIN_FILENO, &byte, 1);
            if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
            if (count == 0) {
                eof = true;
                reason = "stdin-eof";
            } else if (count > 0) {
                received = (size_t)count;
                reason = "unexpected-input";
            }
            break;
        }
    }

    struct native_clock release, completion;
    if (capture_clock(context, &release) != 0) return 2;
    struct identity final_identity;
    bool identity_matches = inspect_identity(context, &final_identity) == 0 &&
        final_identity.pid == context->identity.pid && final_identity.ppid == context->identity.ppid &&
        final_identity.pgid == context->identity.pgid && final_identity.euid == context->identity.euid &&
        strcmp(final_identity.boot_uuid, context->identity.boot_uuid) == 0;
    if (!identity_matches) reason = "identity-error";
    int exit_code = eof && identity_matches ? 0 : 2;
    if (capture_clock(context, &completion) != 0) return 2;
    common_json(context, &json, "d22-sampler-calibration-complete");
    string_field(&json, "reason", reason);
    string_field(&json, "readyReceiptSHA256", context->ready_sha256);
    append_format(&json, ",\n  \"readyReceiptBytes\": %zu, \"cooperativeEOFObserved\": %s,"
                  "\n  \"safetyTimeoutExpired\": %s, \"receivedInputBytes\": %zu,"
                  "\n  \"finalIdentityMatches\": %s, \"exitCode\": %d, \"elapsedSeconds\": %.9f",
                  context->ready_bytes, eof ? "true" : "false", timed_out ? "true" : "false", received,
                  identity_matches ? "true" : "false", exit_code,
                  ticks_seconds(context, completion.continuous_after - context->start.continuous_before));
    clock_field(&json, "releaseClock", &release);
    clock_field(&json, "completionClock", &completion);
    append_format(&json, "\n}\n");
    if (publish_json(&context->completion, &json) != 0) return 2;
    return exit_code;
}

int main(int argc, char **argv) {
    struct context context;
    memset(&context, 0, sizeof(context));
    context.ready.directory = context.completion.directory = -1;
    if (mach_timebase_info(&context.timebase) != KERN_SUCCESS || context.timebase.numer == 0 ||
        context.timebase.denom == 0 || capture_clock(&context, &context.start) != 0) return 2;
    int status = 2;
    if (parse_arguments(argc, argv, &context.args) != 0) goto finished;
    struct stat input;
    if (fstat(STDIN_FILENO, &input) != 0 || !S_ISFIFO(input.st_mode)) {
        (void)fail("Cooperative release requires a parent-owned stdin pipe");
        goto finished;
    }
    int input_flags = fcntl(STDIN_FILENO, F_GETFL);
    if (input_flags < 0 || fcntl(STDIN_FILENO, F_SETFL, input_flags | O_NONBLOCK) != 0) {
        (void)fail("Could not bound cooperative stdin reads");
        goto finished;
    }
    if (inspect_identity(&context, &context.identity) != 0 ||
        prepare_output(context.args.ready, &context.ready) != 0 ||
        prepare_output(context.args.completion, &context.completion) != 0) goto finished;
    status = lemulip_d22_wait_for_release(&context);
finished:
    if (context.ready.directory >= 0 && close(context.ready.directory) != 0) status = 2;
    if (context.completion.directory >= 0 && close(context.completion.directory) != 0) status = 2;
    return status;
}
