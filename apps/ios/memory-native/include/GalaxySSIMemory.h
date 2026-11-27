#ifndef GALAXYSSI_MEMORY_H
#define GALAXYSSI_MEMORY_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { GS_MEMORY_ABI_VERSION = 1, GS_MEMORY_OK = 0, GS_MEMORY_ERROR = 1, GS_MEMORY_PANIC = 2 };
enum { GS_MEMORY_CHECKPOINT_CAPACITY = 208, GS_MEMORY_MAX_MATCHES = 256,
       GS_MEMORY_MAX_REPLAY_CHUNKS = 64, GS_MEMORY_MAX_DIMENSIONS = 8192 };

typedef struct {
    uint32_t abi_version;
    uint32_t dimensions;
    uint32_t shards;
    uint64_t cache_bytes;
    uint8_t key[32];
    uint8_t identity[32];
    uint8_t epoch[16];
} GSMemoryOpenConfig;

#ifdef __cplusplus
static_assert(sizeof(GSMemoryOpenConfig) == 104, "Unexpected native configuration layout");
#else
_Static_assert(sizeof(GSMemoryOpenConfig) == 104, "Unexpected native configuration layout");
#endif

/* Buffers are caller-owned, aligned, valid for the call, and non-overlapping.
 * Zero keys/configuration, vector inputs and output buffers after consumption.
 * Capacity/length units are bytes except float/u64 array counts (elements).
 * A null root with zero length reopens; a dimensions-sized root creates.
 * Paths are absolute UTF-8 bytes without a terminating NUL, at most 4096 bytes.
 * An error/panic is not a promise of rollback: reopen and reconcile checkpoints.
 * Do not pass borrowed Swift storage across asynchronous tasks.
 */
int32_t gs_memory_open(const uint8_t *path, size_t path_length, const GSMemoryOpenConfig *config,
                       const float *root, size_t root_length, int64_t *handle);
int32_t gs_memory_checkpoint(int64_t handle, uint8_t *bytes, size_t capacity, size_t *written);
int32_t gs_memory_begin(int64_t handle, const uint8_t *event, size_t event_length, uint8_t skip,
                        uint8_t *bytes, size_t capacity, size_t *written);
int32_t gs_memory_append(int64_t handle, const uint8_t *event, size_t event_length,
                         const uint64_t *metadata, size_t metadata_length,
                         const float *values, size_t values_length,
                         uint8_t *bytes, size_t capacity, size_t *written);
/* Output requires at least 8 + count * 104 bytes. Checkpoint output requires 208.
 * Records use GSE1/GSC1/GSM1/GSN1 with little-endian numbers, as on Android.
 * Metadata contains ordinal/startUTF16/endUTF16 triplets for 1..64 chunks.
 */
int32_t gs_memory_search(int64_t handle, const float *query, size_t query_length,
                         uint32_t count, uint32_t breadth,
                         uint8_t *bytes, size_t capacity, size_t *written);
int32_t gs_memory_node_count(int64_t handle, uint64_t *count);
/* Query is read-only. Migration is explicit background work, one 1..256-record
 * transaction per call. complete is a caller-owned byte (0 or 1), cleared before
 * validation; it is meaningful only on GS_MEMORY_OK. Failures require retry or
 * reopen, not a destructive rebuild. Both use the same cancellable owner. */
int32_t gs_memory_records_partitioned(int64_t handle, uint8_t *complete);
int32_t gs_memory_migrate_records(int64_t handle, uint32_t limit, uint8_t *complete);
/* Cancel/close do not wait for the per-engine mutex. Closed handles cannot be reused.
 * An active call retains its owner, sees cancellation and releases it on exit.
 */
int32_t gs_memory_cancel(int64_t handle);
int32_t gs_memory_close(int64_t handle);

#ifdef __cplusplus
}
#endif
#endif
