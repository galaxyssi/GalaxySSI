#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "whisper.h"

namespace {

constexpr const char *TAG = "GalaxySSIWhisperV2";
constexpr int SAMPLE_RATE_HZ = 16000;
constexpr int MAX_PCM_SAMPLES = SAMPLE_RATE_HZ * 60 * 10;

enum NativeCode {
    CODE_OK = 0,
    CODE_ABORTED = 1,
    CODE_INVALID_HANDLE = 2,
    CODE_MODEL_NOT_LOADED = 3,
    CODE_MODEL_CORRUPTED = 4,
    CODE_UNSUPPORTED_MODEL = 5,
    CODE_INVALID_PCM = 6,
    CODE_DECODE_FAILED = 7,
    CODE_OUT_OF_MEMORY = 8,
    CODE_NATIVE_INTERNAL_ERROR = 9,
    CODE_TIMEOUT = 10,
};

struct TimingValue {
    double sample_ms = 0.0;
    double encode_ms = 0.0;
    double decode_ms = 0.0;
    double total_ms = 0.0;
    int64_t audio_ms = 0;
    double rtf = 0.0;
};

struct SegmentValue {
    int64_t start_ms = 0;
    int64_t end_ms = 0;
    std::string text;
    float average_log_prob = NAN;
    float no_speech_probability = NAN;
};

struct RuntimeRecord {
    jlong handle = 0;
    whisper_context *context = nullptr;
    int thread_count = 1;
    std::string model_path;
    std::atomic<bool> closing{false};
    std::mutex decode_mutex;

    ~RuntimeRecord() {
        if (context != nullptr) {
            whisper_free(context);
            context = nullptr;
        }
    }
};

struct SessionRecord {
    jlong handle = 0;
    std::shared_ptr<RuntimeRecord> runtime;
    whisper_state *state = nullptr;
    std::string language = "zh";
    std::string prompt;
    bool translate = false;
    bool no_context = true;
    bool single_segment = false;
    int max_tokens = 0;
    std::atomic<bool> abort_requested{false};
    std::atomic<bool> closing{false};
    std::mutex timings_mutex;
    TimingValue timings;

    ~SessionRecord() {
        if (state != nullptr) {
            std::lock_guard<std::mutex> lock(runtime->decode_mutex);
            whisper_free_state(state);
            state = nullptr;
        }
    }
};

std::mutex registry_mutex;
std::unordered_map<jlong, std::shared_ptr<RuntimeRecord>> runtimes;
std::unordered_map<jlong, std::shared_ptr<SessionRecord>> sessions;
std::atomic<jlong> next_handle{1};

jlong allocate_handle() {
    jlong value = next_handle.fetch_add(1, std::memory_order_relaxed);
    if (value <= 0) {
        next_handle.store(2, std::memory_order_relaxed);
        value = 1;
    }
    return value;
}

std::shared_ptr<RuntimeRecord> find_runtime(jlong handle) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    const auto found = runtimes.find(handle);
    return found == runtimes.end() ? nullptr : found->second;
}

std::shared_ptr<SessionRecord> find_session(jlong handle) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    const auto found = sessions.find(handle);
    return found == sessions.end() ? nullptr : found->second;
}

bool abort_callback(void *user_data) {
    auto *session = static_cast<SessionRecord *>(user_data);
    return session == nullptr || session->abort_requested.load(std::memory_order_relaxed) ||
           session->closing.load(std::memory_order_relaxed) ||
           session->runtime->closing.load(std::memory_order_relaxed);
}

jstring new_utf8_string(JNIEnv *env, const std::string &value) {
    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(value.size()));
    if (bytes == nullptr) return nullptr;
    if (!value.empty()) {
        env->SetByteArrayRegion(
                bytes,
                0,
                static_cast<jsize>(value.size()),
                reinterpret_cast<const jbyte *>(value.data()));
    }
    jclass string_class = env->FindClass("java/lang/String");
    jmethodID constructor = env->GetMethodID(string_class, "<init>", "([BLjava/lang/String;)V");
    jstring charset = env->NewStringUTF("UTF-8");
    auto result = static_cast<jstring>(env->NewObject(string_class, constructor, bytes, charset));
    env->DeleteLocalRef(charset);
    env->DeleteLocalRef(string_class);
    env->DeleteLocalRef(bytes);
    return result;
}

jobject new_timings(JNIEnv *env, const TimingValue &timings) {
    jclass type = env->FindClass("com/galaxyssi/chat/voice/asr/local/NativeWhisperTimings");
    if (type == nullptr) return nullptr;
    jmethodID constructor = env->GetMethodID(type, "<init>", "(DDDDJD)V");
    jobject result = env->NewObject(
            type,
            constructor,
            timings.sample_ms,
            timings.encode_ms,
            timings.decode_ms,
            timings.total_ms,
            static_cast<jlong>(timings.audio_ms),
            timings.rtf);
    env->DeleteLocalRef(type);
    return result;
}

jobject new_result(
        JNIEnv *env,
        int code,
        const std::vector<SegmentValue> &segments,
        const std::string &language,
        const TimingValue &timings,
        bool aborted,
        const std::string &message) {
    jclass segment_type = env->FindClass("com/galaxyssi/chat/voice/asr/local/NativeWhisperSegment");
    if (segment_type == nullptr) return nullptr;
    jmethodID segment_constructor = env->GetMethodID(segment_type, "<init>", "(JJLjava/lang/String;FF)V");
    jobjectArray segment_array = env->NewObjectArray(
            static_cast<jsize>(segments.size()), segment_type, nullptr);
    for (jsize index = 0; index < static_cast<jsize>(segments.size()); ++index) {
        const auto &segment = segments[static_cast<size_t>(index)];
        jstring text = new_utf8_string(env, segment.text);
        jobject value = env->NewObject(
                segment_type,
                segment_constructor,
                static_cast<jlong>(segment.start_ms),
                static_cast<jlong>(segment.end_ms),
                text,
                static_cast<jfloat>(segment.average_log_prob),
                static_cast<jfloat>(segment.no_speech_probability));
        env->SetObjectArrayElement(segment_array, index, value);
        env->DeleteLocalRef(value);
        env->DeleteLocalRef(text);
    }

    jobject timing_value = new_timings(env, timings);
    jstring language_value = language.empty() ? nullptr : new_utf8_string(env, language);
    jstring message_value = message.empty() ? nullptr : new_utf8_string(env, message);
    jclass result_type = env->FindClass("com/galaxyssi/chat/voice/asr/local/NativeWhisperResult");
    jmethodID result_constructor = env->GetMethodID(
            result_type,
            "<init>",
            "(I[Lcom/galaxyssi/chat/voice/asr/local/NativeWhisperSegment;Ljava/lang/String;Lcom/galaxyssi/chat/voice/asr/local/NativeWhisperTimings;ZLjava/lang/String;)V");
    jobject result = env->NewObject(
            result_type,
            result_constructor,
            static_cast<jint>(code),
            segment_array,
            language_value,
            timing_value,
            static_cast<jboolean>(aborted),
            message_value);

    env->DeleteLocalRef(result_type);
    if (message_value != nullptr) env->DeleteLocalRef(message_value);
    if (language_value != nullptr) env->DeleteLocalRef(language_value);
    env->DeleteLocalRef(timing_value);
    env->DeleteLocalRef(segment_array);
    env->DeleteLocalRef(segment_type);
    return result;
}

jobject error_result(JNIEnv *env, int code, const char *message, bool aborted = false) {
    return new_result(env, code, {}, "", {}, aborted, message == nullptr ? "" : message);
}

void throw_out_of_memory(JNIEnv *env, const char *message) {
    jclass exception_class = env->FindClass("java/lang/OutOfMemoryError");
    if (exception_class != nullptr) env->ThrowNew(exception_class, message);
}

std::string get_string(JNIEnv *env, jstring value, size_t max_length) {
    if (value == nullptr) return {};
    const char *characters = env->GetStringUTFChars(value, nullptr);
    if (characters == nullptr) return {};
    std::string result(characters);
    env->ReleaseStringUTFChars(value, characters);
    if (result.size() > max_length) result.resize(max_length);
    return result;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeCreateRuntime(
        JNIEnv *env,
        jobject,
        jstring model_path,
        jint thread_count,
        jboolean use_gpu) {
    if (model_path == nullptr || use_gpu == JNI_TRUE) return 0;
    try {
        const std::string path = get_string(env, model_path, 4096);
        if (path.empty()) return 0;
        // The CPU runtime is statically linked. Scanning the APK native-library
        // directory here can load device-specific backends such as Qualcomm
        // Hexagon on incompatible ARM64 devices before capability checks run.
        whisper_context_params params = whisper_context_default_params();
        params.use_gpu = false;
        whisper_context *context = whisper_init_from_file_with_params_no_state(path.c_str(), params);
        if (context == nullptr) return 0;
        auto runtime = std::make_shared<RuntimeRecord>();
        runtime->handle = allocate_handle();
        runtime->context = context;
        runtime->thread_count = std::clamp(static_cast<int>(thread_count), 1, 16);
        runtime->model_path = path;
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            runtimes.emplace(runtime->handle, runtime);
        }
        return runtime->handle;
    } catch (const std::bad_alloc &) {
        throw_out_of_memory(env, "Whisper model requires more available memory");
        return 0;
    } catch (...) {
        return 0;
    }
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeCreateSession(
        JNIEnv *env,
        jobject,
        jlong runtime_handle,
        jstring language,
        jboolean translate,
        jboolean no_context,
        jboolean single_segment,
        jint max_tokens,
        jstring prompt) {
    auto runtime = find_runtime(runtime_handle);
    if (runtime == nullptr || runtime->closing.load(std::memory_order_relaxed)) return 0;
    try {
        whisper_state *state = nullptr;
        {
            std::lock_guard<std::mutex> decode_lock(runtime->decode_mutex);
            if (runtime->closing.load(std::memory_order_relaxed)) return 0;
            state = whisper_init_state(runtime->context);
        }
        if (state == nullptr) return 0;
        auto session = std::make_shared<SessionRecord>();
        session->handle = allocate_handle();
        session->runtime = runtime;
        session->state = state;
        session->language = get_string(env, language, 16);
        if (session->language.empty()) session->language = "auto";
        session->prompt = get_string(env, prompt, 4096);
        session->translate = translate == JNI_TRUE;
        session->no_context = no_context == JNI_TRUE;
        session->single_segment = single_segment == JNI_TRUE;
        session->max_tokens = std::clamp(static_cast<int>(max_tokens), 0, 4096);
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            if (runtime->closing.load(std::memory_order_relaxed) || runtimes.count(runtime_handle) == 0) {
                return 0;
            }
            sessions.emplace(session->handle, session);
        }
        return session->handle;
    } catch (const std::bad_alloc &) {
        throw_out_of_memory(env, "Whisper session requires more available memory");
        return 0;
    } catch (...) {
        return 0;
    }
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeDecodePcm16(
        JNIEnv *env,
        jobject,
        jlong session_handle,
        jshortArray pcm,
        jint offset,
        jint length) {
    auto session = find_session(session_handle);
    if (session == nullptr || session->closing.load(std::memory_order_relaxed)) {
        return error_result(env, CODE_INVALID_HANDLE, "Whisper session handle is invalid");
    }
    if (pcm == nullptr || offset < 0 || length <= 0 || length > MAX_PCM_SAMPLES) {
        return error_result(env, CODE_INVALID_PCM, "PCM16 input is invalid");
    }
    const jsize array_length = env->GetArrayLength(pcm);
    if (static_cast<int64_t>(offset) + static_cast<int64_t>(length) > array_length) {
        return error_result(env, CODE_INVALID_PCM, "PCM16 range exceeds its array");
    }

    try {
        std::vector<jshort> pcm16(static_cast<size_t>(length));
        env->GetShortArrayRegion(pcm, offset, length, pcm16.data());
        if (env->ExceptionCheck()) return nullptr;
        std::vector<float> samples(static_cast<size_t>(length));
        std::transform(pcm16.begin(), pcm16.end(), samples.begin(), [](jshort value) {
            return static_cast<float>(value) / 32768.0f;
        });

        std::vector<SegmentValue> segments;
        std::string detected_language;
        TimingValue timing;
        int result_code = CODE_OK;
        std::string result_message;
        bool aborted = false;
        const auto started = std::chrono::steady_clock::now();
        {
            std::lock_guard<std::mutex> decode_lock(session->runtime->decode_mutex);
            if (session->abort_requested.load(std::memory_order_relaxed) ||
                session->closing.load(std::memory_order_relaxed) ||
                session->runtime->closing.load(std::memory_order_relaxed)) {
                return error_result(env, CODE_ABORTED, "Whisper decode was cancelled", true);
            }
            whisper_reset_timings_from_state(session->state);
            whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            params.print_realtime = false;
            params.print_progress = false;
            params.print_timestamps = false;
            params.print_special = false;
            params.translate = session->translate;
            params.language = session->language.c_str();
            params.n_threads = session->runtime->thread_count;
            params.offset_ms = 0;
            params.no_context = session->no_context;
            params.single_segment = session->single_segment;
            params.max_tokens = session->max_tokens;
            params.suppress_blank = true;
            params.suppress_nst = true;
            params.temperature = 0.0f;
            params.initial_prompt = session->prompt.empty() ? nullptr : session->prompt.c_str();
            params.abort_callback = abort_callback;
            params.abort_callback_user_data = session.get();

            const int native_result = whisper_full_with_state(
                    session->runtime->context,
                    session->state,
                    params,
                    samples.data(),
                    static_cast<int>(samples.size()));
            aborted = session->abort_requested.load(std::memory_order_relaxed) ||
                      session->closing.load(std::memory_order_relaxed) ||
                      session->runtime->closing.load(std::memory_order_relaxed);
            if (native_result != 0) {
                result_code = aborted ? CODE_ABORTED : CODE_DECODE_FAILED;
                result_message = aborted ? "Whisper decode was cancelled" : "whisper_full_with_state failed";
            } else {
                const int language_id = whisper_full_lang_id_from_state(session->state);
                if (language_id >= 0) {
                    const char *language_name = whisper_lang_str(language_id);
                    if (language_name != nullptr) detected_language = language_name;
                }
                const int segment_count = whisper_full_n_segments_from_state(session->state);
                segments.reserve(static_cast<size_t>(std::max(segment_count, 0)));
                for (int segment_index = 0; segment_index < segment_count; ++segment_index) {
                    SegmentValue value;
                    value.start_ms = whisper_full_get_segment_t0_from_state(session->state, segment_index) * 10;
                    value.end_ms = whisper_full_get_segment_t1_from_state(session->state, segment_index) * 10;
                    const char *text = whisper_full_get_segment_text_from_state(session->state, segment_index);
                    if (text != nullptr) value.text = text;
                    value.no_speech_probability = whisper_full_get_segment_no_speech_prob_from_state(
                            session->state, segment_index);
                    const int token_count = whisper_full_n_tokens_from_state(session->state, segment_index);
                    if (token_count > 0) {
                        double log_prob = 0.0;
                        for (int token_index = 0; token_index < token_count; ++token_index) {
                            log_prob += whisper_full_get_token_data_from_state(
                                    session->state, segment_index, token_index).plog;
                        }
                        value.average_log_prob = static_cast<float>(log_prob / token_count);
                    }
                    segments.push_back(std::move(value));
                }
            }

            whisper_timings native_timings{};
            whisper_get_timings_from_state(session->state, &native_timings);
            timing.sample_ms = native_timings.sample_ms;
            timing.encode_ms = native_timings.encode_ms;
            timing.decode_ms = native_timings.decode_ms;
        }
        const auto finished = std::chrono::steady_clock::now();
        timing.total_ms = std::chrono::duration<double, std::milli>(finished - started).count();
        timing.audio_ms = static_cast<int64_t>(length) * 1000 / SAMPLE_RATE_HZ;
        timing.rtf = timing.audio_ms > 0 ? timing.total_ms / timing.audio_ms : 0.0;
        {
            std::lock_guard<std::mutex> timings_lock(session->timings_mutex);
            session->timings = timing;
        }
        return new_result(
                env,
                result_code,
                segments,
                detected_language,
                timing,
                aborted,
                result_message);
    } catch (const std::bad_alloc &) {
        return error_result(env, CODE_OUT_OF_MEMORY, "Whisper decode ran out of memory");
    } catch (...) {
        return error_result(env, CODE_NATIVE_INTERNAL_ERROR, "Whisper native decode failed unexpectedly");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeRequestAbort(
        JNIEnv *, jobject, jlong session_handle) {
    auto session = find_session(session_handle);
    if (session != nullptr) session->abort_requested.store(true, std::memory_order_relaxed);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeGetTimings(
        JNIEnv *env, jobject, jlong session_handle) {
    auto session = find_session(session_handle);
    if (session == nullptr) return new_timings(env, {});
    std::lock_guard<std::mutex> lock(session->timings_mutex);
    return new_timings(env, session->timings);
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeDestroySession(
        JNIEnv *, jobject, jlong session_handle) {
    std::shared_ptr<SessionRecord> removed;
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        const auto found = sessions.find(session_handle);
        if (found == sessions.end()) return;
        removed = found->second;
        removed->closing.store(true, std::memory_order_relaxed);
        removed->abort_requested.store(true, std::memory_order_relaxed);
        sessions.erase(found);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeDestroyRuntime(
        JNIEnv *, jobject, jlong runtime_handle) {
    std::shared_ptr<RuntimeRecord> removed_runtime;
    std::vector<std::shared_ptr<SessionRecord>> removed_sessions;
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        const auto found = runtimes.find(runtime_handle);
        if (found == runtimes.end()) return;
        removed_runtime = found->second;
        removed_runtime->closing.store(true, std::memory_order_relaxed);
        runtimes.erase(found);
        for (auto iterator = sessions.begin(); iterator != sessions.end();) {
            if (iterator->second->runtime.get() == removed_runtime.get()) {
                iterator->second->closing.store(true, std::memory_order_relaxed);
                iterator->second->abort_requested.store(true, std::memory_order_relaxed);
                removed_sessions.push_back(iterator->second);
                iterator = sessions.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }
}

extern "C" JNIEXPORT jint JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeActiveRuntimeCount(
        JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    return static_cast<jint>(runtimes.size());
}

extern "C" JNIEXPORT jint JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperNativeBridge_nativeActiveSessionCount(
        JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    return static_cast<jint>(sessions.size());
}
