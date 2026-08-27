#include <jni.h>
#include <android/log.h>
#include <sys/auxv.h>
#if defined(__aarch64__) && __has_include(<asm/hwcap.h>)
#include <asm/hwcap.h>
#endif

#include <algorithm>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "ggml-backend.h"
#include "llama.h"

namespace {
constexpr const char * LOG_TAG = "SignalASILlama";
constexpr int32_t BATCH_SIZE = 512;

std::mutex runtime_mutex;
llama_model * loaded_model = nullptr;
llama_context * loaded_context = nullptr;
std::string loaded_model_path;
bool backend_initialized = false;

void log_error(const std::string & message) {
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s", message.c_str());
}

void throw_illegal_state(JNIEnv * env, const std::string & message) {
    log_error(message);
    jclass type = env->FindClass("java/lang/IllegalStateException");
    if (type != nullptr) env->ThrowNew(type, message.c_str());
}

jstring utf8_string(JNIEnv * env, const std::string & value) {
    jclass string_class = env->FindClass("java/lang/String");
    jmethodID constructor = string_class == nullptr ? nullptr : env->GetMethodID(
        string_class,
        "<init>",
        "([BLjava/lang/String;)V"
    );
    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(value.size()));
    jstring encoding = env->NewStringUTF("UTF-8");
    if (constructor == nullptr || bytes == nullptr || encoding == nullptr) {
        return env->NewStringUTF(value.c_str());
    }
    env->SetByteArrayRegion(
        bytes,
        0,
        static_cast<jsize>(value.size()),
        reinterpret_cast<const jbyte *>(value.data())
    );
    return static_cast<jstring>(env->NewObject(string_class, constructor, bytes, encoding));
}

std::string java_string(JNIEnv * env, jstring value) {
    if (value == nullptr) return {};
    const char * chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
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

std::string formatted_prompt(const std::string & system_prompt, const std::string & user_prompt) {
    const char * chat_template = llama_model_chat_template(loaded_model, nullptr);
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

std::vector<llama_token> tokenize_prompt(const std::string & prompt) {
    const llama_vocab * vocab = llama_model_get_vocab(loaded_model);
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

void decode_prompt(const std::vector<llama_token> & tokens) {
    const int32_t batch_size = static_cast<int32_t>(llama_n_batch(loaded_context));
    for (size_t offset = 0; offset < tokens.size(); offset += batch_size) {
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
            throw std::runtime_error("llama.cpp failed while processing the prompt: " +
                                     std::to_string(result));
        }
    }
}

std::string token_piece(llama_token token) {
    const llama_vocab * vocab = llama_model_get_vocab(loaded_model);
    std::vector<char> buffer(256);
    int32_t length = llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, true);
    if (length < 0) {
        buffer.resize(static_cast<size_t>(-length));
        length = llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, true);
    }
    if (length < 0) throw std::runtime_error("llama.cpp could not decode a generated token");
    return std::string(buffer.data(), static_cast<size_t>(length));
}

std::string backend_names() {
    std::ostringstream result;
    for (size_t index = 0; index < ggml_backend_reg_count(); ++index) {
        const ggml_backend_reg_t registration = ggml_backend_reg_get(index);
        if (registration == nullptr) continue;
        if (result.tellp() > 0) result << ", ";
        result << ggml_backend_reg_name(registration);
    }
    return result.str();
}
}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeInitialize(
    JNIEnv * env,
    jobject,
    jstring native_library_directory
) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (backend_initialized) return;
    const std::string directory = java_string(env, native_library_directory);
    if (directory.empty()) {
        throw_illegal_state(env, "Android native library directory is unavailable");
        return;
    }
    llama_log_set([](enum ggml_log_level level, const char * text, void *) {
        const int priority = level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR :
            level == GGML_LOG_LEVEL_WARN ? ANDROID_LOG_WARN : ANDROID_LOG_INFO;
        __android_log_write(priority, LOG_TAG, text);
    }, nullptr);
    // GGUF models use the llama-runtime module's pinned CPU/KleidiAI backend. The APK also
    // contains newer GGML libraries used by independent QNN runtimes; loading those through
    // this registry can pass the API-version check while exposing an incompatible device ABI.
    // Keep the runtimes isolated instead of scanning every native library in the APK.
    llama_backend_init();
    backend_initialized = true;
    __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "Loaded backends: %s", backend_names().c_str());
}

extern "C" JNIEXPORT jint JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeLoadModel(
    JNIEnv * env,
    jobject,
    jstring model_path_value,
    jint context_tokens,
    jint threads
) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (!backend_initialized) return 1;
    const std::string model_path = java_string(env, model_path_value);
    const uint32_t context_size = static_cast<uint32_t>(std::clamp<int>(context_tokens, 512, 32768));
    const int32_t thread_count = std::clamp<int>(threads, 1, 16);
    if (loaded_model != nullptr && loaded_context != nullptr && loaded_model_path == model_path &&
        llama_n_ctx(loaded_context) == context_size) {
        return 0;
    }
    unload_locked();
    llama_model_params model_params = llama_model_default_params();
    loaded_model = llama_model_load_from_file(model_path.c_str(), model_params);
    if (loaded_model == nullptr) return 2;
    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = context_size;
    context_params.n_batch = std::min<uint32_t>(BATCH_SIZE, context_size);
    context_params.n_ubatch = std::min<uint32_t>(BATCH_SIZE, context_size);
    context_params.n_threads = thread_count;
    context_params.n_threads_batch = thread_count;
    context_params.no_perf = true;
    loaded_context = llama_init_from_model(loaded_model, context_params);
    if (loaded_context == nullptr) {
        unload_locked();
        return 3;
    }
    loaded_model_path = model_path;
    return 0;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeGenerate(
    JNIEnv * env,
    jobject,
    jstring system_prompt_value,
    jstring user_prompt_value,
    jint maximum_tokens,
    jfloat temperature
) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (loaded_model == nullptr || loaded_context == nullptr) {
        throw_illegal_state(env, "No verified local model is loaded");
        return utf8_string(env, "");
    }
    try {
        llama_memory_clear(llama_get_memory(loaded_context), false);
        const std::string prompt = formatted_prompt(
            java_string(env, system_prompt_value),
            java_string(env, user_prompt_value)
        );
        const std::vector<llama_token> prompt_tokens = tokenize_prompt(prompt);
        const int32_t generation_limit = std::clamp<int>(maximum_tokens, 1, 2048);
        const int32_t context_size = static_cast<int32_t>(llama_n_ctx(loaded_context));
        if (static_cast<int32_t>(prompt_tokens.size()) + generation_limit + 8 > context_size) {
            throw std::runtime_error("Compiled prompt exceeds the local model context window");
        }
        decode_prompt(prompt_tokens);

        llama_sampler * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
        if (temperature <= 0.01f) {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05f, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
        }
        std::string response;
        const llama_vocab * vocab = llama_model_get_vocab(loaded_model);
        for (int32_t generated = 0; generated < generation_limit; ++generated) {
            llama_token token = llama_sampler_sample(sampler, loaded_context, -1);
            if (llama_vocab_is_eog(vocab, token)) break;
            response += token_piece(token);
            llama_batch batch = llama_batch_get_one(&token, 1);
            const int32_t decode_result = llama_decode(loaded_context, batch);
            if (decode_result != 0) {
                llama_sampler_free(sampler);
                throw std::runtime_error("llama.cpp failed while generating: " +
                                         std::to_string(decode_result));
            }
        }
        llama_sampler_free(sampler);
        return utf8_string(env, response);
    } catch (const std::exception & error) {
        throw_illegal_state(env, error.what());
        return utf8_string(env, "");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeUnload(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    unload_locked();
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeSystemInfo(JNIEnv * env, jobject) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    return utf8_string(env, backend_initialized ? llama_print_system_info() : "");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeBackendInfo(JNIEnv * env, jobject) {
    std::lock_guard<std::mutex> guard(runtime_mutex);
    return utf8_string(env, backend_names());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_signalasi_llama_SignalASILlamaRuntime_nativeOsExposesSme(JNIEnv *, jobject) {
#if defined(__aarch64__) && defined(HWCAP2_SME)
    return (getauxval(AT_HWCAP2) & HWCAP2_SME) != 0 ? JNI_TRUE : JNI_FALSE;
#else
    return JNI_FALSE;
#endif
}
