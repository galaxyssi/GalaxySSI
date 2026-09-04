#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace galaxyssi::asr {

class Pcm16Resampler final {
public:
    static constexpr int kOutputSampleRateHz = 16'000;
    static constexpr int kSupportedHighRateHz = 48'000;
    static constexpr std::size_t kFilterTaps = 127;

    explicit Pcm16Resampler(int input_sample_rate_hz);

    bool process(const std::int16_t * input,
                 std::size_t input_count,
                 std::int16_t * output,
                 std::size_t output_capacity,
                 std::size_t * output_count) noexcept;
    std::size_t maximum_output_samples(std::size_t input_count) const noexcept;
    int input_sample_rate_hz() const noexcept;
    std::size_t group_delay_input_samples() const noexcept;
    void reset() noexcept;

private:
    void initialize_filter();
    std::int16_t filtered_sample() const noexcept;

    int input_sample_rate_hz_;
    std::array<float, kFilterTaps> coefficients_{};
    std::array<float, kFilterTaps> history_{};
    std::size_t history_head_ = 0;
    int decimation_phase_ = 0;
};

}  // namespace galaxyssi::asr
