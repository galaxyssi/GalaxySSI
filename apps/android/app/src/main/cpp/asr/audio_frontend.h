#pragma once

#include "audio_resampler.h"
#include "audio_ring_buffer.h"
#include "rolling_window.h"
#include "vad_engine.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>

namespace galaxyssi::asr {

struct AudioFrontendConfig {
    int input_sample_rate_hz = 16'000;
    int ring_duration_seconds = 35;
    VadConfig vad{};
    RollingWindowConfig rolling_window{};
};

class AudioFrontend final {
public:
    using DecodeWindowCallback = std::function<void(const DecodeWindow &)>;

    explicit AudioFrontend(AudioFrontendConfig config,
                           DecodeWindowCallback callback = {});

    bool push_pcm16(const std::int16_t * samples, std::size_t sample_count) noexcept;
    void stop() noexcept;
    void reset() noexcept;
    bool update_partial_policy(int update_interval_ms, bool emit_partials) noexcept;
    void set_callback(DecodeWindowCallback callback);

    bool snapshot(const DecodeWindow & window,
                  std::int16_t * destination,
                  std::size_t destination_capacity) const noexcept;
    const AudioRingBuffer & ring_buffer() const noexcept;

private:
    void consume_resampled(const std::int16_t * samples, std::size_t sample_count) noexcept;
    void process_frame() noexcept;

    AudioFrontendConfig config_;
    Pcm16Resampler resampler_;
    AudioRingBuffer ring_buffer_;
    VoiceActivityDetector vad_;
    RollingWindowPlanner rolling_window_;
    DecodeWindowCallback callback_;
    std::array<std::int16_t, 160> frame_{};
    std::size_t frame_fill_ = 0;
    std::array<std::int16_t, 160> resampled_chunk_{};
};

}  // namespace galaxyssi::asr
