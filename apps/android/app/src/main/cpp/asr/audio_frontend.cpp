#include "audio_frontend.h"

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace galaxyssi::asr {

AudioFrontend::AudioFrontend(AudioFrontendConfig config, DecodeWindowCallback callback)
    : config_(config),
      resampler_(config.input_sample_rate_hz),
      ring_buffer_(static_cast<std::size_t>(Pcm16Resampler::kOutputSampleRateHz) *
                   static_cast<std::size_t>(config.ring_duration_seconds)),
      vad_(config.vad),
      rolling_window_(config.rolling_window),
      callback_(std::move(callback)) {
    if (config_.ring_duration_seconds < 30 || config_.ring_duration_seconds > 35) {
        throw std::invalid_argument("Native ASR ring must retain 30 to 35 seconds");
    }
    if (vad_.frame_samples() != frame_.size()) {
        throw std::invalid_argument("Native ASR frontend requires 160-sample VAD frames");
    }
}

bool AudioFrontend::push_pcm16(const std::int16_t * samples,
                               const std::size_t sample_count) noexcept {
    if (samples == nullptr && sample_count != 0) {
        return false;
    }

    const std::size_t maximum_input_chunk = config_.input_sample_rate_hz == 48'000 ? 480U : 160U;
    std::size_t consumed = 0;
    while (consumed < sample_count) {
        const auto chunk = std::min(maximum_input_chunk, sample_count - consumed);
        std::size_t output_count = 0;
        if (!resampler_.process(samples + consumed,
                                chunk,
                                resampled_chunk_.data(),
                                resampled_chunk_.size(),
                                &output_count)) {
            return false;
        }
        consume_resampled(resampled_chunk_.data(), output_count);
        consumed += chunk;
    }
    return true;
}

void AudioFrontend::stop() noexcept {
    const auto decision = vad_.force_end(ring_buffer_.write_sequence());
    const auto window = rolling_window_.on_vad_decision(decision);
    if (window.has_value() && callback_) {
        callback_(*window);
    }
}

void AudioFrontend::reset() noexcept {
    frame_.fill(0);
    frame_fill_ = 0;
    resampler_.reset();
    ring_buffer_.clear();
    vad_.reset();
    rolling_window_.reset();
}

bool AudioFrontend::update_partial_policy(const int update_interval_ms,
                                          const bool emit_partials) noexcept {
    return rolling_window_.update_partial_policy(update_interval_ms, emit_partials);
}

void AudioFrontend::set_callback(DecodeWindowCallback callback) {
    callback_ = std::move(callback);
}

bool AudioFrontend::snapshot(const DecodeWindow & window,
                             std::int16_t * destination,
                             const std::size_t destination_capacity) const noexcept {
    const auto count = window.sample_count();
    if (count == 0 || count > destination_capacity) {
        return false;
    }
    return ring_buffer_.read(window.start_sample,
                             static_cast<std::size_t>(count),
                             destination);
}

const AudioRingBuffer & AudioFrontend::ring_buffer() const noexcept {
    return ring_buffer_;
}

void AudioFrontend::consume_resampled(const std::int16_t * samples,
                                      const std::size_t sample_count) noexcept {
    std::size_t consumed = 0;
    while (consumed < sample_count) {
        const auto copied = std::min(frame_.size() - frame_fill_, sample_count - consumed);
        std::copy(samples + consumed, samples + consumed + copied, frame_.begin() + frame_fill_);
        frame_fill_ += copied;
        consumed += copied;
        if (frame_fill_ == frame_.size()) {
            process_frame();
            frame_fill_ = 0;
        }
    }
}

void AudioFrontend::process_frame() noexcept {
    const auto frame_start = ring_buffer_.write_sequence();
    if (!ring_buffer_.write(frame_.data(), frame_.size())) {
        return;
    }
    const auto decision = vad_.process_frame(frame_.data(), frame_.size(), frame_start);
    const auto window = rolling_window_.on_vad_decision(decision);
    if (window.has_value() && callback_) {
        callback_(*window);
    }
}

}  // namespace galaxyssi::asr
