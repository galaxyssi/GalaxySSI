#include "rolling_window.h"

#include <algorithm>
#include <stdexcept>

namespace galaxyssi::asr {
namespace {

std::uint64_t to_samples(const int milliseconds, const int sample_rate_hz) {
    return static_cast<std::uint64_t>(milliseconds) * static_cast<std::uint64_t>(sample_rate_hz) / 1'000U;
}

}  // namespace

RollingWindowPlanner::RollingWindowPlanner(RollingWindowConfig config) : config_(config) {
    if (config_.sample_rate_hz != 16'000 || config_.first_partial_ms < 800 ||
        config_.first_partial_ms > 2'000 || config_.update_interval_ms < 500 ||
        config_.update_interval_ms > 2'000 || config_.active_window_ms < 6'000 ||
        config_.active_window_ms > 12'000 || config_.overlap_ms < 1'000 ||
        config_.overlap_ms > 3'000 || config_.maximum_window_ms < 25'000 ||
        config_.maximum_window_ms > 28'000) {
        throw std::invalid_argument("Rolling Whisper window configuration is outside the product envelope");
    }

    first_partial_samples_ = to_samples(config_.first_partial_ms, config_.sample_rate_hz);
    update_interval_samples_ = to_samples(config_.update_interval_ms, config_.sample_rate_hz);
    active_window_samples_ = to_samples(config_.active_window_ms, config_.sample_rate_hz);
    overlap_samples_ = to_samples(config_.overlap_ms, config_.sample_rate_hz);
    maximum_window_samples_ = to_samples(config_.maximum_window_ms, config_.sample_rate_hz);
}

std::optional<DecodeWindow> RollingWindowPlanner::on_vad_decision(const VadDecision & decision) noexcept {
    if (decision.type == VadEventType::kSpeechStarted) {
        active_ = true;
        segment_start_sample_ = decision.segment_start_sample;
        first_voice_sample_ = decision.first_voice_sample;
        last_activity_sample_ = decision.first_voice_sample;
        next_partial_sample_ = first_voice_sample_ + first_partial_samples_;
        last_decode_end_sample_ = 0;
        return std::nullopt;
    }

    if (decision.type == VadEventType::kSpeechEnded ||
        decision.type == VadEventType::kSegmentDiscarded) {
        const bool accepted = active_ && decision.segment_accepted &&
                              decision.segment_end_sample > segment_start_sample_;
        const auto final_window = accepted
            ? std::optional<DecodeWindow>(make_window(
                decision.segment_end_sample, true, decision.end_reason))
            : std::nullopt;
        reset();
        return final_window;
    }

    if (!active_ || !config_.emit_partials || decision.type != VadEventType::kSpeechActive ||
        decision.segment_end_sample < next_partial_sample_) {
        if (active_ && decision.type == VadEventType::kSpeechActive) {
            last_activity_sample_ = std::max(last_activity_sample_, decision.segment_end_sample);
        }
        return std::nullopt;
    }

    last_activity_sample_ = std::max(last_activity_sample_, decision.segment_end_sample);
    while (next_partial_sample_ <= decision.segment_end_sample) {
        next_partial_sample_ += update_interval_samples_;
    }
    if (decision.segment_end_sample == last_decode_end_sample_) {
        return std::nullopt;
    }
    last_decode_end_sample_ = decision.segment_end_sample;
    return make_window(decision.segment_end_sample, false, VadEndReason::kNone);
}

bool RollingWindowPlanner::update_partial_policy(const int update_interval_ms,
                                                 const bool emit_partials) noexcept {
    if (update_interval_ms < 500 || update_interval_ms > 2'000) {
        return false;
    }
    config_.update_interval_ms = update_interval_ms;
    config_.emit_partials = emit_partials;
    update_interval_samples_ = to_samples(update_interval_ms, config_.sample_rate_hz);
    if (active_) {
        const auto anchor = std::max(last_activity_sample_, last_decode_end_sample_);
        next_partial_sample_ = anchor + update_interval_samples_;
    }
    return true;
}

void RollingWindowPlanner::reset() noexcept {
    active_ = false;
    segment_start_sample_ = 0;
    first_voice_sample_ = 0;
    next_partial_sample_ = 0;
    last_decode_end_sample_ = 0;
    last_activity_sample_ = 0;
}

const RollingWindowConfig & RollingWindowPlanner::config() const noexcept {
    return config_;
}

DecodeWindow RollingWindowPlanner::make_window(const std::uint64_t end_sample,
                                               const bool final,
                                               const VadEndReason end_reason) const noexcept {
    const auto maximum_start = end_sample > maximum_window_samples_
        ? end_sample - maximum_window_samples_
        : 0;
    if (final) {
        return DecodeWindow{
            std::max(segment_start_sample_, maximum_start),
            end_sample,
            segment_start_sample_,
            true,
            end_reason,
        };
    }
    const auto active_start = end_sample > active_window_samples_
        ? end_sample - active_window_samples_
        : 0;
    const auto overlap_start = active_start > overlap_samples_
        ? active_start - overlap_samples_
        : 0;
    const auto start = std::max(segment_start_sample_, std::max(maximum_start, overlap_start));
    return DecodeWindow{start, end_sample, segment_start_sample_, final, end_reason};
}

}  // namespace galaxyssi::asr
