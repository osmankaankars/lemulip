// D18 observes naturally occurring startup calls in owned diagnostic processes.
// Link this file as a dylib; dyld does not collect __interpose tuples from an
// executable. No DYLD environment variable, debugger, or AppKit instrumentation
// is required. This is a positive-only probe, not complete activation coverage.

#define _DARWIN_C_SOURCE 1

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <uuid/uuid.h>

#define PROBE_RECORD_CAPACITY 128U
#define PROBE_FRAME_CAPACITY 48U
#define PROBE_JSON_CAPACITY (8U * 1024U * 1024U)
#define PROBE_UUID_CAPACITY 37U
#define PROBE_NO_RECORD UINT32_MAX

#if defined(__arm64__)
#define PROBE_ARCHITECTURE "arm64"
#elif defined(__x86_64__)
#define PROBE_ARCHITECTURE "x86_64"
#else
#error "NativeActivationEntryProbe supports only native arm64 and x86_64."
#endif

typedef enum {
    ProbeSetFront = 1,
    ProbeSetFrontWithOptions = 2
} ProbeFunction;

typedef struct {
    uint64_t call_id;
    pid_t pid;
    uint64_t thread_id;
    int thread_id_error;
    ProbeFunction function;
    bool has_psn;
    uint32_t psn_high;
    uint32_t psn_low;
    uint32_t options;
    unsigned int nesting_depth;
    uint64_t entry_absolute;
    uint64_t entry_continuous;
    uint64_t pre_original_absolute;
    uint64_t pre_original_continuous;
    uint64_t after_original_absolute;
    uint64_t after_original_continuous;
    int entry_errno;
    int result_errno;
    int32_t result;
    bool completed;
    unsigned int frame_count;
    void *frames[PROBE_FRAME_CAPACITY];
} ProbeCall;

typedef struct {
    uint64_t total_calls;
    uint64_t recorded_calls;
    uint64_t completed_calls;
    uint64_t dropped_calls;
    uint64_t nested_calls;
    uint64_t overflow_calls;
    uint64_t before_ready_calls;
    uint64_t after_capture_closed_calls;
    uint64_t active_calls;
} ProbeCounts;

typedef struct {
    uint32_t index;
    bool counted;
} ProbeToken;

typedef struct {
    char *bytes;
    size_t length;
    size_t capacity;
    bool failed;
} ProbeJSON;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic pid_t g_owner_pid;
static _Thread_local unsigned int g_nesting_depth;
static ProbeCall g_calls[PROBE_RECORD_CAPACITY];
static ProbeCall g_snapshot[PROBE_RECORD_CAPACITY];
static ProbeCounts g_counts;
static ProbeCounts g_snapshot_counts;
static bool g_capture_enabled;
static bool g_capture_closed;
static bool g_flush_started;
static bool g_initialized;
static bool g_warmup_completed;
static const char *g_initialization_error;
static char g_output_path[PATH_MAX];
static char g_pending_path[PATH_MAX];
static char g_executable_path[PATH_MAX];
static char g_executable_uuid[PROBE_UUID_CAPACITY];
static char g_library_path[PATH_MAX];
static char g_library_uuid[PROBE_UUID_CAPACITY];
static uintptr_t g_library_base;
static char g_boot_uuid[PROBE_UUID_CAPACITY];
static mach_timebase_info_data_t g_timebase;
static uint64_t g_constructor_absolute;
static uint64_t g_constructor_continuous;
static uint64_t g_ready_absolute;
static uint64_t g_ready_continuous;
static uint64_t g_flush_absolute;
static uint64_t g_flush_continuous;
static char g_json_bytes[PROBE_JSON_CAPACITY];

static void probe_flush(void);
static void probe_initialize(void) __attribute__((constructor));

// Apple SDK declarations are the ABI authority. In particular, OSErr is a
// signed 16-bit result, while OSStatus is a signed 32-bit result.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static OSErr probe_set_front_process(const ProcessSerialNumber *process)
    __attribute__((noinline));
static OSStatus probe_set_front_process_with_options(
    const ProcessSerialNumber *process, OptionBits options)
    __attribute__((noinline));

_Static_assert(sizeof(OSErr) == 2, "Unexpected SDK OSErr width");
_Static_assert(sizeof(OSStatus) == 4, "Unexpected SDK OSStatus width");
_Static_assert(sizeof(OptionBits) == 4, "Unexpected SDK OptionBits width");
_Static_assert(sizeof(((ProcessSerialNumber *)0)->highLongOfPSN) == 4,
               "Unexpected SDK PSN high-word width");
_Static_assert(sizeof(((ProcessSerialNumber *)0)->lowLongOfPSN) == 4,
               "Unexpected SDK PSN low-word width");
_Static_assert(__builtin_types_compatible_p(
                   __typeof__(&probe_set_front_process),
                   __typeof__(&SetFrontProcess)),
               "SetFrontProcess SDK signature changed");
_Static_assert(__builtin_types_compatible_p(
                   __typeof__(&probe_set_front_process_with_options),
                   __typeof__(&SetFrontProcessWithOptions)),
               "SetFrontProcessWithOptions SDK signature changed");

// The SDK does not ship dyld-interposing.h. Use the two-pointer section ABI
// published in Apple's dyld source instead of depending on that helper macro.
typedef struct {
    const void *replacement;
    const void *replacee;
} ProbeInterposeEntry;
_Static_assert(sizeof(ProbeInterposeEntry) == 2 * sizeof(void *),
               "Unexpected dyld interpose-entry layout");

__attribute__((used, section("__DATA,__interpose,interposing")))
static const ProbeInterposeEntry g_interpose_entries[2] = {
    {(const void *)(unsigned long)&probe_set_front_process,
     (const void *)(unsigned long)&SetFrontProcess},
    {(const void *)(unsigned long)&probe_set_front_process_with_options,
     (const void *)(unsigned long)&SetFrontProcessWithOptions}
};

// No lock is held across stack collection or the original activation call.
// Raw addresses are collected here; dladdr and all output happen at atexit.
static ProbeToken probe_begin(ProbeFunction function,
                             const ProcessSerialNumber *process,
                             OptionBits options, int entry_errno)
{
    ProbeToken token = {PROBE_NO_RECORD, false};
    ProbeCall call = {0};
    call.entry_absolute = mach_absolute_time();
    call.entry_continuous = mach_continuous_time();
    call.pid = getpid();
    const pid_t owner = atomic_load_explicit(&g_owner_pid, memory_order_acquire);
    // A forked child must not inherit its parent's output identity or mutex use.
    if (owner != 0 && call.pid != owner)
        return token;

    ++g_nesting_depth;
    token.counted = true;
    call.nesting_depth = g_nesting_depth;
    call.function = function;
    call.entry_errno = entry_errno;
    call.has_psn = process != NULL;
    if (process != NULL) {
        call.psn_high = process->highLongOfPSN;
        call.psn_low = process->lowLongOfPSN;
    }
    call.options = options;

    pthread_mutex_lock(&g_lock);
    call.call_id = ++g_counts.total_calls;
    ++g_counts.active_calls;
    if (call.nesting_depth > 1)
        ++g_counts.nested_calls;
    if (g_capture_closed) {
        ++g_counts.after_capture_closed_calls;
        ++g_counts.dropped_calls;
    } else if (!g_capture_enabled) {
        ++g_counts.before_ready_calls;
        ++g_counts.dropped_calls;
    } else if (g_counts.recorded_calls == PROBE_RECORD_CAPACITY) {
        ++g_counts.overflow_calls;
        ++g_counts.dropped_calls;
    } else {
        token.index = (uint32_t)g_counts.recorded_calls++;
        g_calls[token.index] = call;
    }
    pthread_mutex_unlock(&g_lock);

    if (token.index != PROBE_NO_RECORD) {
        call.thread_id_error = pthread_threadid_np(NULL, &call.thread_id);
        if (call.thread_id_error != 0)
            call.thread_id = 0;
        const int frame_count = backtrace(call.frames, PROBE_FRAME_CAPACITY);
        if (frame_count > 0)
            call.frame_count = (unsigned int)frame_count;
        call.pre_original_absolute = mach_absolute_time();
        call.pre_original_continuous = mach_continuous_time();
        pthread_mutex_lock(&g_lock);
        // Preserve the frozen shutdown snapshot if another thread exits while
        // this call is still preparing to forward. Its record stays incomplete.
        if (!g_capture_closed)
            g_calls[token.index] = call;
        pthread_mutex_unlock(&g_lock);
    }
    return token;
}

static void probe_finish(ProbeToken token, int32_t result, int result_errno,
                         uint64_t after_continuous, uint64_t after_absolute)
{
    if (!token.counted)
        return;
    pthread_mutex_lock(&g_lock);
    --g_counts.active_calls;
    if (token.index != PROBE_NO_RECORD && !g_capture_closed) {
        ProbeCall *call = &g_calls[token.index];
        call->result = result;
        call->result_errno = result_errno;
        call->after_original_continuous = after_continuous;
        call->after_original_absolute = after_absolute;
        call->completed = true;
        ++g_counts.completed_calls;
    }
    pthread_mutex_unlock(&g_lock);
    --g_nesting_depth;
}

static OSErr probe_set_front_process(const ProcessSerialNumber *process)
{
    const int entry_errno = errno;
    const ProbeToken token = probe_begin(ProbeSetFront, process, 0, entry_errno);
    errno = entry_errno;
    // Calls from the interposing dylib bind to the original implementation.
    const OSErr result = SetFrontProcess(process);
    const int result_errno = errno;
    const uint64_t after_continuous = mach_continuous_time();
    const uint64_t after_absolute = mach_absolute_time();
    probe_finish(token, (int32_t)result, result_errno,
                 after_continuous, after_absolute);
    errno = result_errno;
    return result;
}

static OSStatus probe_set_front_process_with_options(
    const ProcessSerialNumber *process, OptionBits options)
{
    const int entry_errno = errno;
    const ProbeToken token = probe_begin(ProbeSetFrontWithOptions, process,
                                         options, entry_errno);
    errno = entry_errno;
    const OSStatus result = SetFrontProcessWithOptions(process, options);
    const int result_errno = errno;
    const uint64_t after_continuous = mach_continuous_time();
    const uint64_t after_absolute = mach_absolute_time();
    probe_finish(token, (int32_t)result, result_errno,
                 after_continuous, after_absolute);
    errno = result_errno;
    return result;
}
#pragma clang diagnostic pop

static bool probe_copy_path(char destination[PATH_MAX], const char *source)
{
    if (source == NULL || source[0] != '/')
        return false;
    const size_t length = strnlen(source, PATH_MAX);
    if (length < 2 || length >= PATH_MAX)
        return false;
    memcpy(destination, source, length + 1);
    return true;
}

static bool probe_image_uuid(const void *base,
                             char value[PROBE_UUID_CAPACITY])
{
    value[0] = '\0';
    if (base == NULL)
        return false;
    const struct mach_header *header = base;
    size_t header_size;
    if (header->magic == MH_MAGIC_64)
        header_size = sizeof(struct mach_header_64);
    else if (header->magic == MH_MAGIC)
        header_size = sizeof(struct mach_header);
    else
        return false;
    if (header->ncmds > 4096 || header->sizeofcmds > 4U * 1024U * 1024U)
        return false;
    const uint8_t *cursor = (const uint8_t *)base + header_size;
    size_t remaining = header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (remaining < sizeof(struct load_command))
            return false;
        const struct load_command *command = (const void *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > remaining)
            return false;
        if (command->cmd == LC_UUID) {
            if (command->cmdsize < sizeof(struct uuid_command))
                return false;
            const struct uuid_command *uuid_command = (const void *)cursor;
            uuid_unparse_upper(uuid_command->uuid, value);
            return true;
        }
        cursor += command->cmdsize;
        remaining -= command->cmdsize;
    }
    return false;
}

static void probe_set_initialization_error(const char *error)
{
    if (g_initialization_error == NULL)
        g_initialization_error = error;
}

static void probe_initialize(void)
{
    const int saved_errno = errno;
    g_constructor_absolute = mach_absolute_time();
    g_constructor_continuous = mach_continuous_time();
    atomic_store_explicit(&g_owner_pid, getpid(), memory_order_release);

    // This is the only environment variable consumed by the probe.
    if (!probe_copy_path(g_output_path,
                         getenv("LEMULIP_ACTIVATION_PROBE_OUTPUT")))
        probe_set_initialization_error("invalid-output-path");
    else {
        const int pending_length = snprintf(g_pending_path, sizeof(g_pending_path),
                                              "%s.pending", g_output_path);
        if (pending_length < 0 || (size_t)pending_length >= sizeof(g_pending_path)) {
            g_pending_path[0] = '\0';
            probe_set_initialization_error("output-path-too-long-for-pending");
        }
    }

    char executable[PATH_MAX];
    char resolved[PATH_MAX];
    uint32_t executable_size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &executable_size) != 0 ||
        realpath(executable, resolved) == NULL ||
        !probe_copy_path(g_executable_path, resolved))
        probe_set_initialization_error("executable-path-unavailable");
    if (!probe_image_uuid(_dyld_get_image_header(0), g_executable_uuid))
        probe_set_initialization_error("executable-uuid-unavailable");

    Dl_info library = {0};
    if (dladdr((const void *)&probe_initialize, &library) == 0 ||
        library.dli_fbase == NULL || library.dli_fname == NULL ||
        realpath(library.dli_fname, resolved) == NULL ||
        !probe_copy_path(g_library_path, resolved)) {
        probe_set_initialization_error("library-path-unavailable");
    } else {
        g_library_base = (uintptr_t)library.dli_fbase;
        if (!probe_image_uuid(library.dli_fbase, g_library_uuid))
            probe_set_initialization_error("library-uuid-unavailable");
    }

    char boot[128] = {0};
    size_t boot_size = sizeof(boot);
    uuid_t boot_value;
    if (sysctlbyname("kern.bootsessionuuid", boot, &boot_size, NULL, 0) != 0 ||
        boot_size != PROBE_UUID_CAPACITY || boot[36] != '\0' ||
        strnlen(boot, sizeof(boot)) != 36 || uuid_parse(boot, boot_value) != 0)
        probe_set_initialization_error("boot-uuid-unavailable");
    else
        uuid_unparse_upper(boot_value, g_boot_uuid);
    if (mach_timebase_info(&g_timebase) != KERN_SUCCESS ||
        g_timebase.numer == 0 || g_timebase.denom == 0)
        probe_set_initialization_error("mach-timebase-unavailable");

    // Warm the raw unwinder/TID path once without invoking activation APIs.
    void *warmup_frames[PROBE_FRAME_CAPACITY];
    uint64_t warmup_thread = 0;
    g_warmup_completed = backtrace(warmup_frames, PROBE_FRAME_CAPACITY) > 0 &&
        pthread_threadid_np(NULL, &warmup_thread) == 0 && warmup_thread != 0;
    (void)g_nesting_depth;
    if (!g_warmup_completed)
        probe_set_initialization_error("stack-warmup-failed");
    if (atexit(probe_flush) != 0) {
        probe_set_initialization_error("atexit-registration-failed");
        fprintf(stderr, "NativeActivationEntryProbe: atexit-registration-failed\n");
    }

    pthread_mutex_lock(&g_lock);
    g_ready_absolute = mach_absolute_time();
    g_ready_continuous = mach_continuous_time();
    g_initialized = g_initialization_error == NULL;
    g_capture_enabled = g_initialized;
    pthread_mutex_unlock(&g_lock);
    errno = saved_errno;
}

static void probe_json_append(ProbeJSON *json, const char *format, ...)
    __attribute__((format(printf, 2, 3)));

static void probe_json_append(ProbeJSON *json, const char *format, ...)
{
    if (json->failed)
        return;
    va_list args;
    va_start(args, format);
    const int length = vsnprintf(json->bytes + json->length,
                                  json->capacity - json->length, format, args);
    va_end(args);
    if (length < 0 || (size_t)length >= json->capacity - json->length) {
        json->failed = true;
        return;
    }
    json->length += (size_t)length;
}

static void probe_json_string(ProbeJSON *json, const char *value)
{
    if (value == NULL) {
        probe_json_append(json, "null");
        return;
    }
    probe_json_append(json, "\"");
    for (const unsigned char *p = (const unsigned char *)value;
         *p != 0 && !json->failed; ++p) {
        if (*p == '"' || *p == '\\')
            probe_json_append(json, "\\%c", *p);
        else if (*p < 0x20)
            probe_json_append(json, "\\u%04x", (unsigned int)*p);
        else
            probe_json_append(json, "%c", *p);
    }
    probe_json_append(json, "\"");
}

static void probe_json_optional_string(ProbeJSON *json, const char *value)
{
    probe_json_string(json, value != NULL && value[0] != '\0' ? value : NULL);
}

static void probe_json_optional_ticks(ProbeJSON *json, uint64_t ticks)
{
    if (ticks != 0)
        probe_json_append(json, "%" PRIu64, ticks);
    else
        probe_json_append(json, "null");
}

static void probe_json_frame(ProbeJSON *json, const void *address)
{
    Dl_info image = {0};
    const bool found = dladdr(address, &image) != 0 && image.dli_fbase != NULL;
    char image_uuid[PROBE_UUID_CAPACITY] = {0};
    if (found)
        (void)probe_image_uuid(image.dli_fbase, image_uuid);
    probe_json_append(json, "{\"address\":\"0x%" PRIxPTR "\",\"imagePath\":",
                        (uintptr_t)address);
    probe_json_optional_string(json, found ? image.dli_fname : NULL);
    probe_json_append(json, ",\"imageUUID\":");
    probe_json_optional_string(json, image_uuid);
    if (found && (uintptr_t)address >= (uintptr_t)image.dli_fbase) {
        probe_json_append(json,
            ",\"imageBase\":\"0x%" PRIxPTR "\",\"imageOffset\":\"0x%" PRIxPTR "\"",
            (uintptr_t)image.dli_fbase,
            (uintptr_t)address - (uintptr_t)image.dli_fbase);
    } else {
        probe_json_append(json, ",\"imageBase\":null,\"imageOffset\":null");
    }
    probe_json_append(json, ",\"symbol\":");
    probe_json_optional_string(json, found ? image.dli_sname : NULL);
    if (found && image.dli_saddr != NULL)
        probe_json_append(json, ",\"symbolAddress\":\"0x%" PRIxPTR "\"}",
                            (uintptr_t)image.dli_saddr);
    else
        probe_json_append(json, ",\"symbolAddress\":null}");
}

static void probe_json_call(ProbeJSON *json, const ProbeCall *call)
{
    const bool with_options = call->function == ProbeSetFrontWithOptions;
    probe_json_append(json,
        "{\"callID\":%" PRIu64 ",\"pid\":%jd,\"threadID\":%" PRIu64
        ",\"threadIDError\":%d,\"function\":\"%s\",\"returnType\":\"%s\","
        "\"resultBits\":%u,\"targetPSN\":",
        call->call_id, (intmax_t)call->pid, call->thread_id, call->thread_id_error,
        with_options ? "SetFrontProcessWithOptions" : "SetFrontProcess",
        with_options ? "OSStatus" : "OSErr", with_options ? 32U : 16U);
    if (call->has_psn)
        probe_json_append(json, "{\"high\":%" PRIu32 ",\"low\":%" PRIu32 "}",
                            call->psn_high, call->psn_low);
    else
        probe_json_append(json, "null");
    probe_json_append(json, ",\"options\":");
    if (with_options)
        probe_json_append(json, "%" PRIu32, call->options);
    else
        probe_json_append(json, "null");
    probe_json_append(json,
        ",\"nestingDepth\":%u,\"entryMachAbsolute\":%" PRIu64
        ",\"entryMachContinuous\":%" PRIu64 ",\"preOriginalMachAbsolute\":",
        call->nesting_depth, call->entry_absolute, call->entry_continuous);
    probe_json_optional_ticks(json, call->pre_original_absolute);
    probe_json_append(json, ",\"preOriginalMachContinuous\":");
    probe_json_optional_ticks(json, call->pre_original_continuous);
    probe_json_append(json, ",\"afterOriginalMachAbsolute\":");
    probe_json_optional_ticks(json, call->after_original_absolute);
    probe_json_append(json, ",\"afterOriginalMachContinuous\":");
    probe_json_optional_ticks(json, call->after_original_continuous);
    probe_json_append(json, ",\"completed\":%s,\"result\":",
                        call->completed ? "true" : "false");
    if (call->completed)
        probe_json_append(json, "%" PRId32, call->result);
    else
        probe_json_append(json, "null");
    probe_json_append(json, ",\"entryErrno\":%d,\"resultErrno\":", call->entry_errno);
    if (call->completed)
        probe_json_append(json, "%d", call->result_errno);
    else
        probe_json_append(json, "null");
    probe_json_append(json, ",\"frameCount\":%u,\"stackMayBeTruncated\":%s,\"frames\":[",
                        call->frame_count,
                        call->frame_count == PROBE_FRAME_CAPACITY ? "true" : "false");
    for (unsigned int i = 0; i < call->frame_count; ++i) {
        if (i != 0)
            probe_json_append(json, ",");
        probe_json_frame(json, call->frames[i]);
    }
    probe_json_append(json, "]}");
}

static void probe_json_receipt(ProbeJSON *json)
{
    const ProbeCounts *counts = &g_snapshot_counts;
    probe_json_append(json,
        "{\"schemaVersion\":1,\"probe\":\"NativeActivationEntryProbe\","
        "\"scope\":\"startup-calibration-only\",\"architecture\":\"%s\","
        "\"pid\":%jd,\"executablePath\":",
        PROBE_ARCHITECTURE,
        (intmax_t)atomic_load_explicit(&g_owner_pid, memory_order_acquire));
    probe_json_optional_string(json, g_executable_path);
    probe_json_append(json, ",\"executableImageUUID\":");
    probe_json_optional_string(json, g_executable_uuid);
    probe_json_append(json, ",\"library\":{\"path\":");
    probe_json_optional_string(json, g_library_path);
    probe_json_append(json, ",\"imageUUID\":");
    probe_json_optional_string(json, g_library_uuid);
    if (g_library_base != 0)
        probe_json_append(json, ",\"imageBase\":\"0x%" PRIxPTR "\"}", g_library_base);
    else
        probe_json_append(json, ",\"imageBase\":null}");
    probe_json_append(json, ",\"bootUUID\":");
    probe_json_optional_string(json, g_boot_uuid);
    probe_json_append(json,
        ",\"machTimebaseNumer\":%" PRIu32 ",\"machTimebaseDenom\":%" PRIu32
        ",\"constructorMachAbsolute\":%" PRIu64 ",\"constructorMachContinuous\":%" PRIu64
        ",\"readyMachAbsolute\":%" PRIu64 ",\"readyMachContinuous\":%" PRIu64
        ",\"flushMachAbsolute\":%" PRIu64 ",\"flushMachContinuous\":%" PRIu64
        ",\"initialized\":%s,\"initializationError\":",
        g_timebase.numer, g_timebase.denom,
        g_constructor_absolute, g_constructor_continuous,
        g_ready_absolute, g_ready_continuous,
        g_flush_absolute, g_flush_continuous,
        g_initialized ? "true" : "false");
    probe_json_string(json, g_initialization_error);
    probe_json_append(json,
        ",\"warmupCompleted\":%s,\"atexitInvoked\":true,\"captureClosed\":true,"
        "\"countsAsOf\":\"capture-close\",\"recordCapacity\":%u,\"frameCapacity\":%u,"
        "\"clockReadOrder\":{\"entry\":[\"absolute\",\"continuous\"],"
        "\"preOriginal\":[\"absolute\",\"continuous\"],"
        "\"afterOriginal\":[\"continuous\",\"absolute\"]},"
        "\"counts\":{\"totalCalls\":%" PRIu64 ",\"recordedCalls\":%" PRIu64
        ",\"completedCalls\":%" PRIu64 ",\"droppedCalls\":%" PRIu64
        ",\"incompleteCalls\":%" PRIu64 ",\"nestedCalls\":%" PRIu64
        ",\"overflowCalls\":%" PRIu64 ",\"beforeReadyCalls\":%" PRIu64
        ",\"afterCaptureClosedCalls\":%" PRIu64 ",\"activeCallsAtFlush\":%" PRIu64 "},\"calls\":[",
        g_warmup_completed ? "true" : "false", PROBE_RECORD_CAPACITY, PROBE_FRAME_CAPACITY,
        counts->total_calls, counts->recorded_calls, counts->completed_calls,
        counts->dropped_calls, counts->recorded_calls - counts->completed_calls,
        counts->nested_calls, counts->overflow_calls, counts->before_ready_calls,
        counts->after_capture_closed_calls, counts->active_calls);
    for (uint64_t i = 0; i < counts->recorded_calls; ++i) {
        if (i != 0)
            probe_json_append(json, ",");
        probe_json_call(json, &g_snapshot[i]);
    }
    probe_json_append(json, "]}\n");
}

static bool probe_write_all(int fd, const char *bytes, size_t length)
{
    size_t written = 0;
    while (written < length) {
        const ssize_t result = write(fd, bytes + written, length - written);
        if (result < 0 && errno == EINTR)
            continue;
        if (result <= 0)
            return false;
        written += (size_t)result;
    }
    return true;
}

static void probe_flush(void)
{
    const int saved_errno = errno;
    if (getpid() != atomic_load_explicit(&g_owner_pid, memory_order_acquire))
        return;
    pthread_mutex_lock(&g_lock);
    if (g_flush_started) {
        pthread_mutex_unlock(&g_lock);
        errno = saved_errno;
        return;
    }
    g_flush_started = true;
    g_capture_closed = true;
    g_capture_enabled = false;
    g_flush_absolute = mach_absolute_time();
    g_flush_continuous = mach_continuous_time();
    g_snapshot_counts = g_counts;
    memcpy(g_snapshot, g_calls, sizeof(g_snapshot));
    pthread_mutex_unlock(&g_lock);

    if (g_output_path[0] == '\0' || g_pending_path[0] == '\0') {
        fprintf(stderr, "NativeActivationEntryProbe: invalid-output-path\n");
        errno = saved_errno;
        return;
    }
    ProbeJSON json = {g_json_bytes, 0, sizeof(g_json_bytes), false};
    probe_json_receipt(&json);
    if (json.failed) {
        fprintf(stderr, "NativeActivationEntryProbe: receipt-size-limit\n");
        errno = saved_errno;
        return;
    }

    // Create the pending receipt only at clean atexit. Publish the final name
    // only after write AND close succeed, so a valid-looking JSON file cannot
    // hide an I/O failure from a launcher that cannot collect this process's
    // stderr. Existing final or pending paths are never overwritten.
    const int fd = open(g_pending_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                        S_IRUSR | S_IWUSR);
    if (fd < 0) {
        fprintf(stderr, "NativeActivationEntryProbe: receipt-open-failed errno=%d\n", errno);
        errno = saved_errno;
        return;
    }
    const bool written = probe_write_all(fd, json.bytes, json.length);
    const int write_errno = written ? 0 : errno;
    const int close_result = close(fd);
    if (!written) {
        fprintf(stderr, "NativeActivationEntryProbe: receipt-write-failed errno=%d\n", write_errno);
    } else if (close_result != 0) {
        fprintf(stderr, "NativeActivationEntryProbe: receipt-close-failed errno=%d\n", errno);
    } else if (link(g_pending_path, g_output_path) != 0) {
        // link creates an exclusive final name and cannot replace or follow an
        // existing file or symlink at that name. Keep failed pending evidence.
        fprintf(stderr, "NativeActivationEntryProbe: receipt-publish-failed errno=%d\n", errno);
    } else {
        // Remove only the extra name for this successfully published receipt.
        // If removal fails, the completed final receipt remains valid.
        (void)unlink(g_pending_path);
    }
    // On any write/close/publish failure retain pending evidence; there is no
    // new final receipt. Native process exit must still be checked separately.
    errno = saved_errno;
}
