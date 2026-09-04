#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int64_t galaxyssi_whisper_create_runtime(const char *model_path, int32_t thread_count, int32_t use_gpu);
int64_t galaxyssi_whisper_create_session(
    int64_t runtime_handle,
    const char *language,
    int32_t translate,
    int32_t no_context,
    int32_t single_segment,
    int32_t max_tokens,
    const char *prompt
);
char *galaxyssi_whisper_decode_json(int64_t session_handle, const int16_t *pcm, int32_t length);
char *galaxyssi_whisper_timings_json(int64_t session_handle);
void galaxyssi_whisper_request_abort(int64_t session_handle);
void galaxyssi_whisper_destroy_session(int64_t session_handle);
void galaxyssi_whisper_destroy_runtime(int64_t runtime_handle);
int32_t galaxyssi_whisper_active_runtime_count(void);
int32_t galaxyssi_whisper_active_session_count(void);
void galaxyssi_whisper_free_string(char *value);

#ifdef __cplusplus
}
#endif
