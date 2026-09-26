#include <jni.h>
#include <whisper.h>
#include <android/log.h>

#include <algorithm>
#include <chrono>
#include <string>
#include <vector>

namespace {

void throw_error(JNIEnv *env, const char *message) {
    jclass type = env->FindClass("java/lang/IllegalStateException");
    if (type != nullptr) env->ThrowNew(type, message);
}

bool timed_out(void *user_data) {
    const auto *deadline = static_cast<std::chrono::steady_clock::time_point *>(user_data);
    return std::chrono::steady_clock::now() >= *deadline;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_galaxyssi_glasses_WhisperTinyNative_nativeLoad(
        JNIEnv *env, jobject, jstring model_path) {
    if (model_path == nullptr) return 0;
    const char *path = env->GetStringUTFChars(model_path, nullptr);
    if (path == nullptr) return 0;
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = false;
    whisper_context *context = whisper_init_from_file_with_params(path, params);
    env->ReleaseStringUTFChars(model_path, path);
    return reinterpret_cast<jlong>(context);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_galaxyssi_glasses_WhisperTinyNative_nativeTranscribe(
        JNIEnv *env, jobject, jlong handle, jshortArray pcm, jint threads) {
    auto *context = reinterpret_cast<whisper_context *>(handle);
    if (context == nullptr || pcm == nullptr) {
        throw_error(env, "Whisper Tiny is not loaded");
        return nullptr;
    }
    const jsize count = env->GetArrayLength(pcm);
    if (count < 1600 || count > 30 * WHISPER_SAMPLE_RATE) {
        throw_error(env, "Whisper audio length must be between 0.1 and 30 seconds");
        return nullptr;
    }
    std::vector<jshort> shorts(static_cast<size_t>(count));
    env->GetShortArrayRegion(pcm, 0, count, shorts.data());
    if (env->ExceptionCheck()) return nullptr;
    std::vector<float> samples(static_cast<size_t>(count));
    for (jsize i = 0; i < count; ++i) samples[i] = shorts[i] / 32768.0f;

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = threads;
    params.language = "zh";
    params.translate = false;
    params.no_context = true;
    params.single_segment = true;
    params.suppress_blank = true;
    params.suppress_nst = true;
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.max_tokens = 48;
    params.greedy.best_of = 1;
    params.temperature_inc = 0.0f;
    params.no_speech_thold = 1.0f;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(30);
    params.abort_callback = timed_out;
    params.abort_callback_user_data = &deadline;
    // The default 30-second encoder window is prohibitive on VENUS ARMv7.
    // Keep a small margin for the actual utterance instead of encoding 30 seconds of padding.
    const int audio_frames = (count + 319) / 320;
    params.audio_ctx = std::min(whisper_n_audio_ctx(context),
                                std::max(128, ((audio_frames + 64 + 31) / 32) * 32));
    if (whisper_full(context, params, samples.data(), count) != 0) {
        throw_error(env, timed_out(&deadline) ? "Whisper Tiny decode timed out" : "Whisper Tiny decode failed");
        return nullptr;
    }
    std::string text;
    const int segments = whisper_full_n_segments(context);
    int tokens = 0;
    for (int i = 0; i < segments; ++i) {
        tokens += whisper_full_n_tokens(context, i);
        const char *part = whisper_full_get_segment_text(context, i);
        if (part != nullptr) text += part;
    }
    __android_log_print(ANDROID_LOG_DEBUG, "GalaxySpeech", "Whisper segments=%d tokens=%d", segments, tokens);
    return env->NewStringUTF(text.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_glasses_WhisperTinyNative_nativeFree(
        JNIEnv *, jobject, jlong handle) {
    auto *context = reinterpret_cast<whisper_context *>(handle);
    if (context != nullptr) whisper_free(context);
}
