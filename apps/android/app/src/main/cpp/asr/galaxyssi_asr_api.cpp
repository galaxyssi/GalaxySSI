#if defined(_WIN32)
#define GALAXYSSI_ASR_EXPORT __declspec(dllexport)
#else
#define GALAXYSSI_ASR_EXPORT __attribute__((visibility("default")))
#endif

extern "C" GALAXYSSI_ASR_EXPORT int galaxyssi_asr_frontend_abi_version() noexcept {
    return 1;
}

#if defined(__ANDROID__)

#include "streaming_frontend_session.h"
#include "audio_resampler.h"

#include <jni.h>

#include <array>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>

namespace {

using galaxyssi::asr::AudioFrontendConfig;
using galaxyssi::asr::FeatureWaitResult;
using galaxyssi::asr::FeatureWindowMetadata;
using galaxyssi::asr::LogMelExtractor;
using galaxyssi::asr::MelFilterBank128;
using galaxyssi::asr::Pcm16Resampler;
using galaxyssi::asr::StreamingFrontendSession;

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

Pcm16Resampler * resampler_from_handle(JNIEnv * environment, const jlong handle) {
    if (handle == 0) {
        throw_java(environment, "java/lang/IllegalStateException", "Native ASR resampler is closed");
        return nullptr;
    }
    return reinterpret_cast<Pcm16Resampler *>(static_cast<std::uintptr_t>(handle));
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
Java_com_galaxyssi_chat_voice_audio_NativePcm16ResamplerBridge_nativeCreate(
    JNIEnv * environment,
    jobject,
    const jint input_sample_rate_hz) {
    try {
        auto resampler = std::make_unique<Pcm16Resampler>(input_sample_rate_hz);
        return static_cast<jlong>(reinterpret_cast<std::uintptr_t>(resampler.release()));
    } catch (const std::exception & error) {
        throw_java(environment, "java/lang/IllegalArgumentException", error.what());
        return 0;
    }
}

extern "C" JNIEXPORT jint JNICALL
Java_com_galaxyssi_chat_voice_audio_NativePcm16ResamplerBridge_nativeProcess(
    JNIEnv * environment,
    jobject,
    const jlong handle,
    jobject input,
    const jint input_sample_count,
    jobject output,
    const jint output_capacity_samples) {
    const auto resampler = resampler_from_handle(environment, handle);
    if (resampler == nullptr || input == nullptr || output == nullptr ||
        input_sample_count <= 0 || output_capacity_samples <= 0) {
        return -1;
    }
    const auto input_capacity = environment->GetDirectBufferCapacity(input);
    const auto output_capacity = environment->GetDirectBufferCapacity(output);
    const auto * input_samples = static_cast<const std::int16_t *>(
        environment->GetDirectBufferAddress(input));
    auto * output_samples = static_cast<std::int16_t *>(
        environment->GetDirectBufferAddress(output));
    const auto input_bytes = static_cast<jlong>(input_sample_count) *
                             static_cast<jlong>(sizeof(std::int16_t));
    const auto output_bytes = static_cast<jlong>(output_capacity_samples) *
                              static_cast<jlong>(sizeof(std::int16_t));
    if (input_samples == nullptr || output_samples == nullptr ||
        input_capacity < input_bytes || output_capacity < output_bytes) {
        throw_java(environment,
                   "java/lang/IllegalArgumentException",
                   "ASR resampler buffers must be direct PCM16 buffers");
        return -1;
    }
    std::size_t produced = 0;
    if (!resampler->process(
            input_samples,
            static_cast<std::size_t>(input_sample_count),
            output_samples,
            static_cast<std::size_t>(output_capacity_samples),
            &produced)) {
        throw_java(environment, "java/lang/IllegalStateException", "Native ASR resampling failed");
        return -1;
    }
    if (produced > static_cast<std::size_t>(output_capacity_samples)) {
        throw_java(environment,
                   "java/lang/IllegalStateException",
                   "Native ASR resampler exceeded the output buffer capacity");
        return -1;
    }
    return static_cast<jint>(produced);
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_audio_NativePcm16ResamplerBridge_nativeDestroy(
    JNIEnv *,
    jobject,
    const jlong handle) {
    if (handle == 0) return;
    delete reinterpret_cast<Pcm16Resampler *>(static_cast<std::uintptr_t>(handle));
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeCreate(
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
Java_com_galaxyssi_chat_voice_asr_local_CompactWhisperQnnFeatureExtractor_nativeExtract(
    JNIEnv * environment,
    jobject,
    jstring mel_filter_path,
    jobject pcm,
    const jint sample_count,
    jobject output) {
    try {
        if (pcm == nullptr || output == nullptr || sample_count <= 0) {
            throw std::invalid_argument("Compact QNN Whisper PCM input is invalid");
        }
        const auto pcm_capacity = environment->GetDirectBufferCapacity(pcm);
        const auto * samples = static_cast<const std::int16_t *>(environment->GetDirectBufferAddress(pcm));
        const auto output_capacity = environment->GetDirectBufferCapacity(output);
        auto * destination = static_cast<float *>(environment->GetDirectBufferAddress(output));
        if (samples == nullptr || destination == nullptr ||
            pcm_capacity < static_cast<jlong>(sample_count) * sizeof(std::int16_t)) {
            throw std::invalid_argument("Compact QNN Whisper requires direct buffers");
        }
        MelFilterBank128 filter_bank;
        std::string error;
        if (!MelFilterBank128::load(to_string(environment, mel_filter_path), &filter_bank, &error)) {
            throw std::invalid_argument(error);
        }
        LogMelExtractor extractor(std::move(filter_bank));
        if (output_capacity < static_cast<jlong>(extractor.output_values() * sizeof(float))) {
            throw std::invalid_argument("Compact QNN Whisper feature output is too small");
        }
        if (!extractor.compute_pcm16(samples, static_cast<std::size_t>(sample_count), &error)) {
            throw std::invalid_argument(error);
        }
        std::memcpy(destination, extractor.output().data(), extractor.output_values() * sizeof(float));
        return JNI_TRUE;
    } catch (const std::exception & error) {
        throw_java(environment, "java/lang/IllegalArgumentException", error.what());
        return JNI_FALSE;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeStart(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    const auto session = from_handle(environment, handle);
    return session != nullptr && session->start() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativePushPcm(
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
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeStop(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    if (const auto session = from_handle(environment, handle); session != nullptr) {
        session->stop();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeCancel(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    if (const auto session = from_handle(environment, handle); session != nullptr) {
        session->cancel();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativePause(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    if (const auto session = from_handle(environment, handle); session != nullptr) {
        session->pause();
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeResume(
    JNIEnv * environment,
    jobject,
    const jlong handle) {
    const auto session = from_handle(environment, handle);
    return session != nullptr && session->resume() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeUpdatePartialPolicy(
    JNIEnv * environment,
    jobject,
    const jlong handle,
    const jint update_interval_ms,
    const jboolean emit_partials) {
    const auto session = from_handle(environment, handle);
    if (session != nullptr &&
        !session->update_partial_policy(update_interval_ms, emit_partials == JNI_TRUE)) {
        throw_java(environment,
                   "java/lang/IllegalArgumentException",
                   "Native ASR partial policy is invalid");
    }
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeWaitForFeatures(
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
        capacity < static_cast<jlong>(session->feature_value_count() * sizeof(float))) {
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
Java_com_galaxyssi_chat_voice_asr_local_WhisperQnnNativeFrontendBridge_nativeDestroy(
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
