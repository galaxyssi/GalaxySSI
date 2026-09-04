#pragma once

#include "vad_engine.h"

#include <cstdint>
#include <optional>

namespace galaxyssi::asr {

struct RollingWindowConfig {
    int sample_rate_hz = 16'000;
    int first_partial_ms = 900;
    int update_interval_ms = 900;
    int active_window_ms = 10'000;
    int overlap_ms = 2'000;
    int maximum_window_ms = 28'000;
    bool emit_partials = true;
};

struct DecodeWindow {
    std::uint64_t start_sample = 0;
    std::uint64_t end_sample = 0;
    std::uint64_t segment_start_sample = 0;
    bool final = false;
    VadEndReason end_reason = VadEndReason::kNone;

    std::uint64_t sample_count() const noexcept {
        return end_sample > start_sample ? end_sample - start_sample : 0;
    }
};

class RollingWindowPlanner final {
public:
    explicit RollingWindowPlanner(RollingWindowConfig config = {});

    std::optional<DecodeWindow> on_vad_decision(const VadDecision & decision) noexcept;
    bool update_partial_policy(int update_interval_ms, bool emit_partials) noexcept;
    void reset() noexcept;
    const RollingWindowConfig & config() const noexcept;

private:
    DecodeWindow make_window(std::uint64_t end_sample,
                             bool final,
                             VadEndReason end_reason) const noexcept;

    RollingWindowConfig config_;
    std::uint64_t first_partial_samples_ = 0;
    std::uint64_t update_interval_samples_ = 0;
    std::uint64_t active_window_samples_ = 0;
    std::uint64_t overlap_samples_ = 0;
    std::uint64_t maximum_window_samples_ = 0;
    bool active_ = false;
    std::uint64_t segment_start_sample_ = 0;
    std::uint64_t first_voice_sample_ = 0;
    std::uint64_t next_partial_sample_ = 0;
    std::uint64_t last_decode_end_sample_ = 0;
    std::uint64_t last_activity_sample_ = 0;
};

}  // namespace galaxyssi::asr
