#pragma once

#include <cstddef>
#include <cstdint>

namespace galaxyssi::asr {

enum class VadEventType {
    kNone,
    kSpeechStarted,
    kSpeechActive,
    kSpeechEnded,
    kSegmentDiscarded,
};

enum class VadEndReason {
    kNone,
    kSilence,
    kMaximumDuration,
    kForced,
};

struct VadConfig {
    int sample_rate_hz = 16'000;
    int frame_duration_ms = 10;
    int speech_start_frames = 4;
    int end_silence_ms = 450;
    int minimum_segment_ms = 300;
    int maximum_segment_ms = 28'000;
    int pre_roll_ms = 200;
    int post_roll_ms = 150;
    float minimum_speech_dbfs = -48.0F;
    float signal_to_noise_db = 9.0F;
};

struct VadDecision {
    VadEventType type = VadEventType::kNone;
    VadEndReason end_reason = VadEndReason::kNone;
    bool frame_contains_speech = false;
    bool segment_accepted = false;
    std::uint64_t segment_start_sample = 0;
    std::uint64_t segment_end_sample = 0;
    std::uint64_t first_voice_sample = 0;
    std::uint64_t last_voice_sample = 0;
    float rms_dbfs = -120.0F;
    float noise_floor_dbfs = -60.0F;
};

class VoiceActivityDetector final {
public:
    explicit VoiceActivityDetector(VadConfig config = {});

    VadDecision process_frame(const std::int16_t * samples,
                              std::size_t sample_count,
                              std::uint64_t frame_start_sample) noexcept;
    VadDecision force_end(std::uint64_t current_sample) noexcept;
    void reset() noexcept;

    bool speech_active() const noexcept;
    std::size_t frame_samples() const noexcept;
    const VadConfig & config() const noexcept;

private:
    VadDecision finish_segment(std::uint64_t detected_end,
                               VadEndReason reason,
                               float rms_dbfs,
                               bool frame_contains_speech) noexcept;
    float calculate_dbfs(const std::int16_t * samples, std::size_t sample_count) const noexcept;
    void update_noise_floor(float frame_dbfs) noexcept;

    VadConfig config_;
    std::size_t frame_samples_ = 160;
    std::size_t end_silence_frames_ = 45;
    std::uint64_t pre_roll_samples_ = 3'200;
    std::uint64_t post_roll_samples_ = 2'400;
    std::uint64_t minimum_segment_samples_ = 4'800;
    std::uint64_t maximum_segment_samples_ = 448'000;
    float noise_floor_dbfs_ = -60.0F;
    int consecutive_speech_frames_ = 0;
    int consecutive_silence_frames_ = 0;
    bool speech_active_ = false;
    std::uint64_t candidate_start_sample_ = 0;
    std::uint64_t segment_start_sample_ = 0;
    std::uint64_t first_voice_sample_ = 0;
    std::uint64_t last_voice_sample_ = 0;
};

}  // namespace galaxyssi::asr
