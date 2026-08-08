#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t signalasi_llama_initialize(void);
int32_t signalasi_llama_load_model(const char *model_path, int32_t context_tokens, int32_t threads);
char *signalasi_llama_generate(
    const char *system_prompt,
    const char *user_prompt,
    int32_t maximum_tokens,
    float temperature
);
void signalasi_llama_free_string(char *value);
void signalasi_llama_unload(void);
const char *signalasi_llama_backend_info(void);
const char *signalasi_llama_system_info(void);
const char *signalasi_llama_last_error(void);
int32_t signalasi_llama_os_exposes_sme(void);

#ifdef __cplusplus
}
#endif
