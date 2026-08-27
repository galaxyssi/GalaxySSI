#include "SignalASILlamaRuntime.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "ggml-backend.h"
#include "llama.h"

namespace {
constexpr int32_t kBatchSize = 512;

std::mutex runtime_mutex;
llama_model *loaded_model = nullptr;
llama_context *loaded_context = nullptr;
std::string loaded_model_path;
std::string last_error;
bool backend_initialized = false;

void set_error(const std::string &message) {
    last_error = message;
}

char *copy_string(const std::string &value) {
    char *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result == nullptr) return nullptr;
    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

std::string c_string(const char *value) {
    return value == nullptr ? std::string() : std::string(value);
}

void unload_locked() {
    if (loaded_context != nullptr) {
        llama_free(loaded_context);
        loaded_context = nullptr;
    }
    if (loaded_model != nullptr) {
        llama_model_free(loaded_model);
        loaded_model = nullptr;
    }
    loaded_model_path.clear();
}

std::string backend_names_locked() {
    std::ostringstream result;
    for (size_t index = 0; index < ggml_backend_reg_count(); ++index) {
        const ggml_backend_reg_t registration = ggml_backend_reg_get(index);
        if (registration == nullptr) continue;
        if (result.tellp() > 0) result << ", ";
        result << ggml_backend_reg_name(registration);
    }
    return result.str();
}

bool has_incompatible_backend_locked() {
    std::string names = backend_names_locked();
    std::transform(names.begin(), names.end(), names.begin(), [](unsigned char value) {
        return static_cast<char>(std::tolower(value));
    });
    for (const char *forbidden : {"qnn", "hexagon", "htp", "genie"}) {
        if (names.find(forbidden) != std::string::npos) return true;
    }
    return false;
}

std::string formatted_prompt_locked(const std::string &system_prompt, const std::string &user_prompt) {
    const char *chat_template = llama_model_chat_template(loaded_model, nullptr);
    if (chat_template == nullptr) {
        return system_prompt + "\n\nUser: " + user_prompt + "\nAssistant:";
    }
    std::vector<llama_chat_message> messages;
    if (!system_prompt.empty()) messages.push_back({"system", system_prompt.c_str()});
    messages.push_back({"user", user_prompt.c_str()});
    int32_t length = llama_chat_apply_template(
        chat_template,
        messages.data(),
        messages.size(),
        true,
        nullptr,
        0
    );
    if (length < 0) throw std::runtime_error("The GGUF chat template could not format the prompt");
    std::vector<char> buffer(static_cast<size_t>(length) + 1U, '\0');
    length = llama_chat_apply_template(
        chat_template,
        messages.data(),
        messages.size(),
        true,
        buffer.data(),
        static_cast<int32_t>(buffer.size())
    );
    if (length < 0) throw std::runtime_error("The GGUF chat template could not format the prompt");
    return std::string(buffer.data(), static_cast<size_t>(length));
}

std::vector<llama_token> tokenize_prompt_locked(const std::string &prompt) {
    const llama_vocab *vocab = llama_model_get_vocab(loaded_model);
    int32_t count = llama_tokenize(
        vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        nullptr,
        0,
        true,
        true
    );
    if (count == INT32_MIN) throw std::runtime_error("Prompt token count overflowed");
    if (count < 0) count = -count;
    std::vector<llama_token> tokens(static_cast<size_t>(count));
    const int32_t written = llama_tokenize(
        vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        true,
        true
    );
    if (written < 0) throw std::runtime_error("Prompt tokenization failed");
    tokens.resize(static_cast<size_t>(written));
    return tokens;
}

void decode_prompt_locked(const std::vector<llama_token> &tokens) {
    const int32_t batch_size = static_cast<int32_t>(llama_n_batch(loaded_context));
    for (size_t offset = 0; offset < tokens.size(); offset += static_cast<size_t>(batch_size)) {
        const int32_t count = std::min<int32_t>(
            batch_size,
            static_cast<int32_t>(tokens.size() - offset)
        );
        llama_batch batch = llama_batch_get_one(
            const_cast<llama_token *>(tokens.data() + offset),
            count
        );
        const int32_t result = llama_decode(loaded_context, batch);
        if (result != 0) {
            throw std::runtime_error(
                "llama.cpp failed while processing the prompt: " + std::to_string(result)
            );
        }
    }
}

std::string token_piece_locked(llama_token token) {
    const llama_vocab *vocab = llama_model_get_vocab(loaded_model);
    std::vector<char> buffer(256);
    int32_t length = llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, true);
    if (length < 0) {
        buffer.resize(static_cast<size_t>(-length));
        length = llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, true);
    }
    if (length < 0) throw std::runtime_error("llama.cpp could not decode a generated token");
    return std::string(buffer.data(), static_cast<size_t>(length));
}
}  // namespace

extern "C" int32_t signalasi_llama_initialize(void) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (backend_initialized) return 0;
    try {
        llama_backend_init();
        if (has_incompatible_backend_locked()) {
            set_error("The iOS GGUF runtime rejected an incompatible accelerator backend");
            llama_backend_free();
            return 2;
        }
        backend_initialized = true;
        last_error.clear();
        return 0;
    } catch (const std::exception &error) {
        set_error(error.what());
        return 1;
    }
}

extern "C" int32_t signalasi_llama_load_model(
    const char *model_path_value,
    int32_t context_tokens,
    int32_t threads
) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (!backend_initialized) {
        set_error("The llama.cpp backend is not initialized");
        return 1;
    }
    const std::string model_path = c_string(model_path_value);
    if (model_path.empty()) {
        set_error("The local model path is empty");
        return 1;
    }
    const uint32_t context_size = static_cast<uint32_t>(std::clamp<int>(context_tokens, 512, 32768));
    const int32_t thread_count = std::clamp<int>(threads, 1, 16);
    if (loaded_model != nullptr && loaded_context != nullptr && loaded_model_path == model_path &&
        llama_n_ctx(loaded_context) == context_size) {
        return 0;
    }
    unload_locked();
    llama_model_params model_params = llama_model_default_params();
    loaded_model = llama_model_load_from_file(model_path.c_str(), model_params);
    if (loaded_model == nullptr) {
        set_error("llama.cpp could not load the selected GGUF model");
        return 2;
    }
    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = context_size;
    context_params.n_batch = std::min<uint32_t>(kBatchSize, context_size);
    context_params.n_ubatch = std::min<uint32_t>(kBatchSize, context_size);
    context_params.n_threads = thread_count;
    context_params.n_threads_batch = thread_count;
    context_params.no_perf = true;
    loaded_context = llama_init_from_model(loaded_model, context_params);
    if (loaded_context == nullptr) {
        unload_locked();
        set_error("llama.cpp could not create a context for the selected GGUF model");
        return 3;
    }
    loaded_model_path = model_path;
    last_error.clear();
    return 0;
}

extern "C" char *signalasi_llama_generate(
    const char *system_prompt_value,
    const char *user_prompt_value,
    int32_t maximum_tokens,
    float temperature
) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (loaded_model == nullptr || loaded_context == nullptr) {
        set_error("No verified local model is loaded");
        return copy_string("");
    }
    llama_sampler *sampler = nullptr;
    try {
        llama_memory_clear(llama_get_memory(loaded_context), false);
        const std::string prompt = formatted_prompt_locked(
            c_string(system_prompt_value),
            c_string(user_prompt_value)
        );
        const std::vector<llama_token> prompt_tokens = tokenize_prompt_locked(prompt);
        const int32_t generation_limit = std::clamp<int>(maximum_tokens, 1, 4096);
        const int32_t context_size = static_cast<int32_t>(llama_n_ctx(loaded_context));
        if (static_cast<int32_t>(prompt_tokens.size()) + generation_limit + 8 > context_size) {
            throw std::runtime_error("Compiled prompt exceeds the local model context window");
        }
        decode_prompt_locked(prompt_tokens);

        sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
        if (sampler == nullptr) throw std::runtime_error("llama.cpp could not create a sampler");
        if (temperature <= 0.01f) {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05f, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(std::clamp(temperature, 0.0f, 2.0f)));
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
        }
        std::string response;
        const llama_vocab *vocab = llama_model_get_vocab(loaded_model);
        for (int32_t generated = 0; generated < generation_limit; ++generated) {
            llama_token token = llama_sampler_sample(sampler, loaded_context, -1);
            if (llama_vocab_is_eog(vocab, token)) break;
            response += token_piece_locked(token);
            llama_batch batch = llama_batch_get_one(&token, 1);
            const int32_t decode_result = llama_decode(loaded_context, batch);
            if (decode_result != 0) {
                llama_sampler_free(sampler);
                sampler = nullptr;
                throw std::runtime_error(
                    "llama.cpp failed while generating: " + std::to_string(decode_result)
                );
            }
        }
        llama_sampler_free(sampler);
        sampler = nullptr;
        last_error.clear();
        return copy_string(response);
    } catch (const std::exception &error) {
        if (sampler != nullptr) llama_sampler_free(sampler);
        set_error(error.what());
        return copy_string("");
    }
}

extern "C" void signalasi_llama_free_string(char *value) {
    std::free(value);
}

extern "C" void signalasi_llama_unload(void) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    unload_locked();
}

extern "C" const char *signalasi_llama_backend_info(void) {
    static thread_local std::string value;
    std::lock_guard<std::mutex> guard(runtime_mutex);
    value = backend_names_locked();
    return value.c_str();
}

extern "C" const char *signalasi_llama_system_info(void) {
    static thread_local std::string value;
    std::lock_guard<std::mutex> guard(runtime_mutex);
    value = backend_initialized ? llama_print_system_info() : "";
    return value.c_str();
}

extern "C" const char *signalasi_llama_last_error(void) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    return last_error.c_str();
}

extern "C" int32_t signalasi_llama_os_exposes_sme(void) {
#if defined(__aarch64__) && defined(__ARM_FEATURE_SME)
    return 1;
#else
    return 0;
#endif
}
