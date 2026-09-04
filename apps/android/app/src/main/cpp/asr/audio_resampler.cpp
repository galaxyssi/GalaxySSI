#include "audio_resampler.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace galaxyssi::asr {
namespace {

constexpr double kPi = 3.1415926535897932384626433832795;
constexpr double kCutoffHz = 7'200.0;

double sinc(const double value) noexcept {
    if (std::abs(value) < 1.0e-12) {
        return 1.0;
    }
    return std::sin(kPi * value) / (kPi * value);
}

}  // namespace

Pcm16Resampler::Pcm16Resampler(const int input_sample_rate_hz)
    : input_sample_rate_hz_(input_sample_rate_hz) {
    if (input_sample_rate_hz_ != kOutputSampleRateHz &&
        input_sample_rate_hz_ != kSupportedHighRateHz) {
        throw std::invalid_argument("Local ASR accepts only 16 kHz or 48 kHz PCM");
    }
    initialize_filter();
}

bool Pcm16Resampler::process(const std::int16_t * input,
                             const std::size_t input_count,
                             std::int16_t * output,
                             const std::size_t output_capacity,
                             std::size_t * output_count) noexcept {
    if (output_count == nullptr) {
        return false;
    }
    *output_count = 0;
    if (input_count == 0) {
        return true;
    }
    if (input == nullptr || output == nullptr || output_capacity < maximum_output_samples(input_count)) {
        return false;
    }

    if (input_sample_rate_hz_ == kOutputSampleRateHz) {
        std::copy(input, input + input_count, output);
        *output_count = input_count;
        return true;
    }

    std::size_t produced = 0;
    for (std::size_t index = 0; index < input_count; ++index) {
        history_head_ = (history_head_ + 1) % kFilterTaps;
        history_[history_head_] = static_cast<float>(input[index]);
        ++decimation_phase_;
        if (decimation_phase_ == 3) {
            decimation_phase_ = 0;
            output[produced++] = filtered_sample();
        }
    }
    *output_count = produced;
    return true;
}

std::size_t Pcm16Resampler::maximum_output_samples(const std::size_t input_count) const noexcept {
    if (input_sample_rate_hz_ == kOutputSampleRateHz) {
        return input_count;
    }
    return (input_count + static_cast<std::size_t>(decimation_phase_)) / 3U;
}

int Pcm16Resampler::input_sample_rate_hz() const noexcept {
    return input_sample_rate_hz_;
}

std::size_t Pcm16Resampler::group_delay_input_samples() const noexcept {
    return input_sample_rate_hz_ == kOutputSampleRateHz ? 0U : (kFilterTaps - 1U) / 2U;
}

void Pcm16Resampler::reset() noexcept {
    history_.fill(0.0F);
    history_head_ = 0;
    decimation_phase_ = 0;
}

void Pcm16Resampler::initialize_filter() {
    if (input_sample_rate_hz_ == kOutputSampleRateHz) {
        coefficients_[0] = 1.0F;
        return;
    }

    const auto normalized_cutoff = kCutoffHz / static_cast<double>(input_sample_rate_hz_);
    const auto center = static_cast<double>(kFilterTaps - 1U) / 2.0;
    double sum = 0.0;
    for (std::size_t index = 0; index < kFilterTaps; ++index) {
        const auto position = static_cast<double>(index) - center;
        const auto phase = 2.0 * kPi * static_cast<double>(index) /
                           static_cast<double>(kFilterTaps - 1U);
        const auto blackman = 0.42 - 0.5 * std::cos(phase) + 0.08 * std::cos(2.0 * phase);
        const auto coefficient = 2.0 * normalized_cutoff * sinc(2.0 * normalized_cutoff * position) * blackman;
        coefficients_[index] = static_cast<float>(coefficient);
        sum += coefficient;
    }
    if (std::abs(sum) < std::numeric_limits<double>::epsilon()) {
        throw std::runtime_error("ASR resampler filter normalization failed");
    }
    for (auto & coefficient : coefficients_) {
        coefficient = static_cast<float>(static_cast<double>(coefficient) / sum);
    }
}

std::int16_t Pcm16Resampler::filtered_sample() const noexcept {
    double value = 0.0;
    for (std::size_t tap = 0; tap < kFilterTaps; ++tap) {
        const auto history_index = (history_head_ + kFilterTaps - tap) % kFilterTaps;
        value += static_cast<double>(history_[history_index]) * coefficients_[tap];
    }
    value = std::round(value);
    value = std::max<double>(std::numeric_limits<std::int16_t>::min(),
                             std::min<double>(std::numeric_limits<std::int16_t>::max(), value));
    return static_cast<std::int16_t>(value);
}

}  // namespace galaxyssi::asr
