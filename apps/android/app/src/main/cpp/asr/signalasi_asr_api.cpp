#if defined(_WIN32)
#define SIGNALASI_ASR_EXPORT __declspec(dllexport)
#else
#define SIGNALASI_ASR_EXPORT __attribute__((visibility("default")))
#endif

extern "C" SIGNALASI_ASR_EXPORT int signalasi_asr_frontend_abi_version() noexcept {
    return 1;
}

#if defined(__ANDROID__)

#include "streaming_frontend_session.h"

#include <jni.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>

namespace {

using signalasi::asr::AudioFrontendConfig;
using signalasi::asr::FeatureWaitResult;
using signalasi::asr::FeatureWindowMetadata;
using signalasi::asr::LogMelExtractor;
using signalasi::asr::MelFilterBank128;
using signalasi::asr::StreamingFrontendSession;

constexpr jsize kConfigValueCount = 14;

void throw_java(JNIEnv * environment, const char * class_name, const std::string & message) {
    const auto exception_class = environment->FindClass(class_name);
    if (exception_class != nullptr) {
        environment->ThrowNew(exception_class, message.c_str());
    }
}

StreamingFrontendSession * from_handle(JNIEnv * environment, const jlong handle) {
    if (handle == 0) {
        throw_java(environment, "java/lang/IllegalStateException", "Native ASR frontend is closed");
        return nullptr;
    }
    return reinterpret_cast<StreamingFrontendSession *>(static_cast<std::uintptr_t>(handle));
}

std::string to_string(JNIEnv * environment, jstring value) {
    if (value == nullptr) {
        return {};
    }
    const char * characters = environment->GetStringUTFChars(value, nullptr);
    if (characters == nullptr) {
        return {};
    }
    std::string result(characters);
    environment->ReleaseStringUTFChars(value, characters);
    return result;
}

AudioFrontendConfig parse_config(JNIEnv * environment, jintArray values) {
    if (values == nullptr || environment->GetArrayLength(values) != kConfigValueCount) {
        throw std::invalid_argument("Native ASR frontend configuration is invalid");
    }
    std::array<jint, kConfigValueCount> raw{};
    environment->GetIntArrayRegion(values, 0, kConfigValueCount, raw.data());
    if (environment->ExceptionCheck()) {
        throw std::invalid_argument("Native ASR frontend configuration could not be read");
    }

    AudioFrontendConfig config;
    config.input_sample_rate_hz = raw[0];
    config.ring_duration_seconds = raw[1];
    config.vad.speech_start_frames = raw[2];
    config.vad.end_silence_ms = raw[3];
    config.vad.minimum_segment_ms = raw[4];
    config.vad.maximum_segment_ms = raw[5];
    config.vad.pre_roll_ms = raw[6];
    config.vad.post_roll_ms = raw[7];
    config.rolling_window.first_partial_ms = raw[8];
    config.rolling_window.update_interval_ms = raw[9];
    config.rolling_window.active_window_ms = raw[10];
    config.rolling_window.overlap_ms = raw[11];
    config.rolling_window.maximum_window_ms = raw[12];
    config.rolling_window.emit_partials = raw[13] != 0;
    return config;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeCreate(
    JNIEnv * environment,
    jobject,
    jstring mel_filter_path,
    jintArray config_values) {
    try {
        MelFilterBank128 filter_bank;
        std::string error;
        if (!MelFilterBank128::load(to_string(environment, mel_filter_path), &filter_bank, &error)) {
            throw std::invalid_argument(error);
        }
        auto session = std::make_unique<StreamingFrontendSession>(
            parse_config(environment, config_values), std::move(filter_bank));
        return static_cast<jlong>(reinterpret_cast<std::uintptr_t>(session.release()));
    } catch (const std::exception & error) {
        throw_java(environment, "java/lang/IllegalArgumentException", error.what());
        return 0;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeStart(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    const auto session = from_handle(environment, handle);
    return session != nullptr && session->start() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativePushPcm(
    JNIEnv * environment,
    jobject,
    const jlong handle,
    jobject pcm,
    const jint sample_count) {
    const auto session = from_handle(environment, handle);
    if (session == nullptr || pcm == nullptr || sample_count <= 0) {
        return JNI_FALSE;
    }
    const auto capacity = environment->GetDirectBufferCapacity(pcm);
    const auto samples = static_cast<const std::int16_t *>(environment->GetDirectBufferAddress(pcm));
    const auto required_bytes = static_cast<jlong>(sample_count) *
                                static_cast<jlong>(sizeof(std::int16_t));
    if (samples == nullptr || capacity < required_bytes) {
        throw_java(environment, "java/lang/IllegalArgumentException", "PCM input must be a direct PCM16 buffer");
        return JNI_FALSE;
    }
    return session->push_pcm16(samples, static_cast<std::size_t>(sample_count)) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeStop(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    if (const auto session = from_handle(environment, handle); session != nullptr) {
        session->stop();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeCancel(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    if (const auto session = from_handle(environment, handle); session != nullptr) {
        session->cancel();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativePause(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    if (const auto session = from_handle(environment, handle); session != nullptr) {
        session->pause();
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeResume(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    const auto session = from_handle(environment, handle);
    return session != nullptr && session->resume() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeWaitForFeatures(
    JNIEnv * environment,
    jobject,
    const jlong handle,
    jobject output,
    const jint timeout_ms) {
    const auto session = from_handle(environment, handle);
    if (session == nullptr || output == nullptr || timeout_ms < 0) {
        return nullptr;
    }
    const auto capacity = environment->GetDirectBufferCapacity(output);
    auto * destination = static_cast<float *>(environment->GetDirectBufferAddress(output));
    if (destination == nullptr ||
        capacity < static_cast<jlong>(LogMelExtractor::kOutputValues * sizeof(float))) {
        throw_java(environment, "java/lang/IllegalArgumentException", "Log-Mel output buffer is invalid");
        return nullptr;
    }

    FeatureWindowMetadata metadata;
    std::string error;
    const auto result = session->wait_for_features(
        destination,
        static_cast<std::size_t>(capacity) / sizeof(float),
        std::chrono::milliseconds(timeout_ms),
        &metadata,
        &error);
    if (result == FeatureWaitResult::kTimeout || result == FeatureWaitResult::kClosed) {
        return nullptr;
    }
    if (result == FeatureWaitResult::kError) {
        throw_java(environment, "java/lang/IllegalStateException", error);
        return nullptr;
    }

    const std::array<jlong, 5> values{
        static_cast<jlong>(metadata.kind),
        static_cast<jlong>(metadata.start_sample),
        static_cast<jlong>(metadata.end_sample),
        static_cast<jlong>(metadata.segment_start_sample),
        static_cast<jlong>(metadata.end_reason),
    };
    const auto array = environment->NewLongArray(static_cast<jsize>(values.size()));
    if (array != nullptr) {
        environment->SetLongArrayRegion(array, 0, static_cast<jsize>(values.size()), values.data());
    }
    return array;
}

extern "C" JNIEXPORT void JNICALL
Java_com_signalasi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeDestroy(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    const auto session = from_handle(environment, handle);
    if (session == nullptr) {
        return;
    }
    session->close();
    delete session;
}

#endif
