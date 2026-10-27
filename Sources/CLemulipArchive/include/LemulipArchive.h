#ifndef LEMULIP_ARCHIVE_H
#define LEMULIP_ARCHIVE_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* All paths are local filesystem paths. No archive entry is ever passed to a shell. */
enum FWArchiveFormat { LEMULIP_ARCHIVE_ZIP = 1, LEMULIP_ARCHIVE_TAR = 2, LEMULIP_ARCHIVE_GZIP = 3 };
typedef int (*lemulip_cancel_callback)(void *context);
int lemulip_archive_extract(const char *input_path, const char *output_directory,
                       const char *raw_filename, int allow_raw,
                       char *error, size_t error_capacity, lemulip_cancel_callback cancelled, void *context);
/* For checksum-verified engine packages only. Listed symlinks are omitted,
   never created or followed; all other extraction safeguards remain enabled. */
int lemulip_archive_extract_package(const char *input_path, const char *output_directory,
                       const char *const *ignored_links, size_t ignored_count,
                       char *error, size_t error_capacity, lemulip_cancel_callback cancelled, void *context);
int lemulip_archive_create(const char *const *input_paths, const char *const *entry_names,
                      size_t input_count, const char *output_path, int format,
                      char *error, size_t error_capacity, lemulip_cancel_callback cancelled, void *context);

#ifdef __cplusplus
}
#endif
#endif
