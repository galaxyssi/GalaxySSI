#include "vad_engine.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace galaxyssi::asr {
namespace {

std::uint64_t milliseconds_to_samples(const int milliseconds, const int sample_rate_hz) {
    return static_cast<std::uint64_t>(milliseconds) * static_cast<std::uint64_t>(sample_rate_hz) / 1'000U;
}

}  // namespace

VoiceActivityDetector::VoiceActivityDetector(VadConfig config) : config_(config) {
    if (config_.sample_rate_hz != 16'000 || config_.frame_duration_ms != 10) {
        throw std::invalid_argument("Whisper VAD requires 16 kHz, 10 ms frames");
    }
    if (config_.speech_start_frames < 3 || config_.speech_start_frames > 5 ||
        config_.end_silence_ms < 350 || config_.end_silence_ms > 500 ||
        config_.minimum_segment_ms < 300 || config_.maximum_segment_ms < 25'000 ||
        config_.maximum_segment_ms > 28'000 || config_.pre_roll_ms < 0 ||
        config_.post_roll_ms < 0) {
        throw std::invalid_argument("Whisper VAD configuration is outside the product envelope");
    }

    frame_samples_ = static_cast<std::size_t>(milliseconds_to_samples(
        config_.frame_duration_ms, config_.sample_rate_hz));
    end_silence_frames_ = static_cast<std::size_t>(
        (config_.end_silence_ms + config_.frame_duration_ms - 1) / config_.frame_duration_ms);
    pre_roll_samples_ = milliseconds_to_samples(config_.pre_roll_ms, config_.sample_rate_hz);
    post_roll_samples_ = milliseconds_to_samples(config_.post_roll_ms, config_.sample_rate_hz);
    minimum_segment_samples_ = milliseconds_to_samples(config_.minimum_segment_ms, config_.sample_rate_hz);
    maximum_segment_samples_ = milliseconds_to_samples(config_.maximum_segment_ms, config_.sample_rate_hz);
}

VadDecision VoiceActivityDetector::process_frame(const std::int16_t * samples,
                                                 const std::size_t sample_count,
                                                 const std::uint64_t frame_start_sample) noexcept {
    VadDecision decision;
    decision.noise_floor_dbfs = noise_floor_dbfs_;
    if (samples == nullptr || sample_count != frame_samples_) {
        return decision;
    }

    const auto frame_end_sample = frame_start_sample + sample_count;
    const auto rms_dbfs = calculate_dbfs(samples, sample_count);
    const auto threshold = std::max(config_.minimum_speech_dbfs,
                                    noise_floor_dbfs_ + config_.signal_to_noise_db);
    const bool frame_contains_speech = rms_dbfs >= threshold;
    decision.rms_dbfs = rms_dbfs;
    decision.frame_contains_speech = frame_contains_speech;

    if (!speech_active_) {
        if (frame_contains_speech) {
            if (consecutive_speech_frames_ == 0) {
                candidate_start_sample_ = frame_start_sample;
            }
            ++consecutive_speech_frames_;
            if (consecutive_speech_frames_ >= config_.speech_start_frames) {
                speech_active_ = true;
                consecutive_silence_frames_ = 0;
                first_voice_sample_ = candidate_start_sample_;
                segment_start_sample_ = candidate_start_sample_ > pre_roll_samples_
                    ? candidate_start_sample_ - pre_roll_samples_
                    : 0;
                last_voice_sample_ = frame_end_sample;
                decision.type = VadEventType::kSpeechStarted;
                decision.segment_start_sample = segment_start_sample_;
                decision.segment_end_sample = frame_end_sample;
                decision.first_voice_sample = first_voice_sample_;
                decision.last_voice_sample = last_voice_sample_;
                decision.noise_floor_dbfs = noise_floor_dbfs_;
                return decision;
            }
        } else {
            consecutive_speech_frames_ = 0;
            update_noise_floor(rms_dbfs);
        }
        decision.noise_floor_dbfs = noise_floor_dbfs_;
        return decision;
    }

    if (frame_contains_speech) {
        last_voice_sample_ = frame_end_sample;
        consecutive_silence_frames_ = 0;
    } else {
        ++consecutive_silence_frames_;
    }

    if (frame_end_sample - segment_start_sample_ >= maximum_segment_samples_) {
        return finish_segment(frame_end_sample, VadEndReason::kMaximumDuration,
                              rms_dbfs, frame_contains_speech);
    }
    if (consecutive_silence_frames_ >= static_cast<int>(end_silence_frames_)) {
        const auto end_with_post_roll = last_voice_sample_ + post_roll_samples_;
        return finish_segment(std::min(frame_end_sample, end_with_post_roll),
                              VadEndReason::kSilence, rms_dbfs, frame_contains_speech);
    }

    decision.type = VadEventType::kSpeechActive;
    decision.segment_start_sample = segment_start_sample_;
    decision.segment_end_sample = frame_end_sample;
    decision.first_voice_sample = first_voice_sample_;
    decision.last_voice_sample = last_voice_sample_;
    decision.noise_floor_dbfs = noise_floor_dbfs_;
    return decision;
}

VadDecision VoiceActivityDetector::force_end(const std::uint64_t current_sample) noexcept {
    if (!speech_active_) {
        return {};
    }
    const auto end_with_post_roll = last_voice_sample_ + post_roll_samples_;
    return finish_segment(std::min(current_sample, end_with_post_roll),
                          VadEndReason::kForced, -120.0F, false);
}

void VoiceActivityDetector::reset() noexcept {
    consecutive_speech_frames_ = 0;
    consecutive_silence_frames_ = 0;
    speech_active_ = false;
    candidate_start_sample_ = 0;
    segment_start_sample_ = 0;
    first_voice_sample_ = 0;
    last_voice_sample_ = 0;
}

bool VoiceActivityDetector::speech_active() const noexcept {
    return speech_active_;
}

std::size_t VoiceActivityDetector::frame_samples() const noexcept {
    return frame_samples_;
}

const VadConfig & VoiceActivityDetector::config() const noexcept {
    return config_;
}

VadDecision VoiceActivityDetector::finish_segment(const std::uint64_t detected_end,
                                                  const VadEndReason reason,
                                                  const float rms_dbfs,
                                                  const bool frame_contains_speech) noexcept {
    VadDecision decision;
    const auto voice_span = last_voice_sample_ > first_voice_sample_
        ? last_voice_sample_ - first_voice_sample_
        : 0;
    decision.segment_accepted = voice_span >= minimum_segment_samples_;
    decision.type = decision.segment_accepted
        ? VadEventType::kSpeechEnded
        : VadEventType::kSegmentDiscarded;
    decision.end_reason = reason;
    decision.frame_contains_speech = frame_contains_speech;
    decision.segment_start_sample = segment_start_sample_;
    decision.segment_end_sample = std::max(segment_start_sample_, detected_end);
    decision.first_voice_sample = first_voice_sample_;
    decision.last_voice_sample = last_voice_sample_;
    decision.rms_dbfs = rms_dbfs;
    decision.noise_floor_dbfs = noise_floor_dbfs_;

    reset();
    return decision;
}

float VoiceActivityDetector::calculate_dbfs(const std::int16_t * samples,
                                            const std::size_t sample_count) const noexcept {
    long double sum_of_squares = 0.0;
    for (std::size_t index = 0; index < sample_count; ++index) {
        const auto value = static_cast<long double>(samples[index]);
        sum_of_squares += value * value;
    }
    const auto rms = std::sqrt(sum_of_squares / static_cast<long double>(sample_count));
    const auto normalized = std::max<long double>(rms / 32768.0L, 1.0e-6L);
    return static_cast<float>(20.0L * std::log10(normalized));
}

void VoiceActivityDetector::update_noise_floor(const float frame_dbfs) noexcept {
    constexpr float kPreviousWeight = 0.95F;
    noise_floor_dbfs_ = std::clamp(
        kPreviousWeight * noise_floor_dbfs_ + (1.0F - kPreviousWeight) * frame_dbfs,
        -90.0F,
        -25.0F);
}

}  // namespace galaxyssi::asr
