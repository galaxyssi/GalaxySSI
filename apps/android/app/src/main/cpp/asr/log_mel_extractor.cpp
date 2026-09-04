#include "log_mel_extractor.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <limits>
#include <stdexcept>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

namespace galaxyssi::asr {
namespace {

constexpr double kPi = 3.1415926535897932384626433832795;
constexpr float kMinimumMelEnergy = 1.0e-10F;

void set_error(std::string * destination, const std::string & message) {
    if (destination != nullptr) {
        *destination = message;
    }
}

bool is_little_endian() noexcept {
    const std::uint16_t value = 1;
    return *reinterpret_cast<const std::uint8_t *>(&value) == 1;
}

void apply_hann_window(const float * samples,
                       const float * hann,
                       float * destination,
                       const std::size_t count) noexcept {
    std::size_t index = 0;
#if defined(__aarch64__)
    for (; index + 8U <= count; index += 8U) {
        const auto samples_low = vld1q_f32(samples + index);
        const auto samples_high = vld1q_f32(samples + index + 4U);
        const auto hann_low = vld1q_f32(hann + index);
        const auto hann_high = vld1q_f32(hann + index + 4U);
        vst1q_f32(destination + index, vmulq_f32(samples_low, hann_low));
        vst1q_f32(destination + index + 4U, vmulq_f32(samples_high, hann_high));
    }
#endif
    for (; index < count; ++index) {
        destination[index] = samples[index] * hann[index];
    }
}

void compute_power_spectrum(const float * interleaved_fft,
                            float * destination,
                            const std::size_t count) noexcept {
    std::size_t index = 0;
#if defined(__aarch64__)
    for (; index + 4U <= count; index += 4U) {
        const auto complex = vld2q_f32(interleaved_fft + 2U * index);
        const auto power = vfmaq_f32(
            vmulq_f32(complex.val[0], complex.val[0]),
            complex.val[1],
            complex.val[1]);
        vst1q_f32(destination + index, power);
    }
#endif
    for (; index < count; ++index) {
        const auto real = interleaved_fft[2U * index];
        const auto imaginary = interleaved_fft[2U * index + 1U];
        destination[index] = real * real + imaginary * imaginary;
    }
}

double mel_dot_product(const float * power,
                       const float * filters,
                       const std::size_t count) noexcept {
    std::size_t index = 0;
#if defined(__aarch64__)
    auto accumulator_low = vdupq_n_f64(0.0);
    auto accumulator_high = vdupq_n_f64(0.0);
    for (; index + 4U <= count; index += 4U) {
        const auto power_values = vld1q_f32(power + index);
        const auto filter_values = vld1q_f32(filters + index);
        accumulator_low = vfmaq_f64(
            accumulator_low,
            vcvt_f64_f32(vget_low_f32(power_values)),
            vcvt_f64_f32(vget_low_f32(filter_values)));
        accumulator_high = vfmaq_f64(
            accumulator_high,
            vcvt_high_f64_f32(power_values),
            vcvt_high_f64_f32(filter_values));
    }
    double result = vaddvq_f64(vaddq_f64(accumulator_low, accumulator_high));
#else
    double result = 0.0;
#endif
    for (; index < count; ++index) {
        result += static_cast<double>(power[index]) * static_cast<double>(filters[index]);
    }
    return result;
}

}  // namespace

MelFilterBank128::MelFilterBank128() : values_(kValueCount, 0.0F) {}

MelFilterBank128::MelFilterBank128(std::vector<float> values) : values_(std::move(values)) {
    if (values_.size() != kValueCount &&
        values_.size() != kCompactMelBins * kFftBins) {
        throw std::invalid_argument("Whisper mel filter bank must contain 80 or 128 x 201 values");
    }
    mel_bins_ = values_.size() / kFftBins;
    for (const auto value : values_) {
        if (!std::isfinite(value) || value < 0.0F) {
            throw std::invalid_argument("Whisper mel filter bank contains an invalid value");
        }
    }
}

bool MelFilterBank128::load(const std::string & path,
                            MelFilterBank128 * destination,
                            std::string * error_message) {
    if (destination == nullptr) {
        set_error(error_message, "Mel filter destination is null");
        return false;
    }
    if (!is_little_endian()) {
        set_error(error_message, "Whisper mel filters require a little-endian target");
        return false;
    }

    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        set_error(error_message, "Could not open mel_filters.bin");
        return false;
    }
    const auto bytes = stream.tellg();
    const auto large_bytes = static_cast<std::streamsize>(kValueCount * sizeof(float));
    const auto compact_bytes = static_cast<std::streamsize>(kCompactMelBins * kFftBins * sizeof(float));
    if (bytes != large_bytes && bytes != compact_bytes) {
        set_error(error_message, "mel_filters.bin has an unexpected size");
        return false;
    }
    stream.seekg(0, std::ios::beg);
    std::vector<float> values(static_cast<std::size_t>(bytes) / sizeof(float));
    if (!stream.read(reinterpret_cast<char *>(values.data()), bytes)) {
        set_error(error_message, "Could not read mel_filters.bin");
        return false;
    }
    try {
        *destination = MelFilterBank128(std::move(values));
        return true;
    } catch (const std::exception & error) {
        set_error(error_message, error.what());
        return false;
    }
}

const float * MelFilterBank128::row(const std::size_t mel_bin) const noexcept {
    return mel_bin < mel_bins_ ? values_.data() + mel_bin * kFftBins : nullptr;
}

const std::vector<float> & MelFilterBank128::values() const noexcept {
    return values_;
}

std::size_t MelFilterBank128::mel_bins() const noexcept {
    return mel_bins_;
}

LogMelExtractor::LogMelExtractor(MelFilterBank128 filter_bank)
    : filter_bank_(std::move(filter_bank)),
      padded_samples_(kMaximumSamples + kFftSize, 0.0F),
      mel_output_(filter_bank_.mel_bins() * kMelFrames, -1.5F) {
    initialize_tables();
}

bool LogMelExtractor::compute_pcm16(const std::int16_t * samples,
                                    const std::size_t sample_count,
                                    std::string * error_message) noexcept {
    if (samples == nullptr && sample_count != 0) {
        set_error(error_message, "PCM input is null");
        return false;
    }
    if (sample_count > kMaximumSamples) {
        set_error(error_message, "PCM input exceeds the 30 second Whisper window");
        return false;
    }

    std::fill(padded_samples_.begin(), padded_samples_.end(), 0.0F);
    constexpr std::size_t center_padding = kFftSize / 2;
    for (std::size_t index = 0; index < sample_count; ++index) {
        padded_samples_[center_padding + index] = static_cast<float>(samples[index]) / 32768.0F;
    }
    if (sample_count > 1) {
        for (std::size_t index = 0; index < center_padding; ++index) {
            const auto reflected = std::min(sample_count - 1, center_padding - index);
            padded_samples_[index] = static_cast<float>(samples[reflected]) / 32768.0F;
        }
    }

    float maximum_log_energy = -std::numeric_limits<float>::infinity();
    for (std::size_t frame = 0; frame < kMelFrames; ++frame) {
        std::fill(fft_input_.begin(), fft_input_.end(), 0.0F);
        const auto frame_offset = frame * kHopSize;
        apply_hann_window(
            padded_samples_.data() + frame_offset,
            hann_.data(),
            fft_input_.data(),
            kFftSize);
        fft(fft_input_.data(), static_cast<int>(kFftSize), fft_output_.data());

        compute_power_spectrum(
            fft_output_.data(),
            power_spectrum_.data(),
            MelFilterBank128::kFftBins);

        for (std::size_t mel = 0; mel < filter_bank_.mel_bins(); ++mel) {
            const auto * filters = filter_bank_.row(mel);
            const auto energy = mel_dot_product(
                power_spectrum_.data(),
                filters,
                MelFilterBank128::kFftBins);
            const auto log_energy = static_cast<float>(
                std::log10(std::max<double>(energy, kMinimumMelEnergy)));
            mel_output_[mel * kMelFrames + frame] = log_energy;
            maximum_log_energy = std::max(maximum_log_energy, log_energy);
        }
    }

    const auto clamp_floor = maximum_log_energy - 8.0F;
    for (auto & value : mel_output_) {
        value = (std::max(value, clamp_floor) + 4.0F) / 4.0F;
        if (!std::isfinite(value)) {
            set_error(error_message, "Log-Mel extraction produced a non-finite value");
            return false;
        }
    }
    return true;
}

const std::vector<float> & LogMelExtractor::output() const noexcept {
    return mel_output_;
}

std::size_t LogMelExtractor::output_values() const noexcept {
    return mel_output_.size();
}

void LogMelExtractor::initialize_tables() noexcept {
    for (std::size_t index = 0; index < kFftSize; ++index) {
        const auto angle = 2.0 * kPi * static_cast<double>(index) / static_cast<double>(kFftSize);
        hann_[index] = static_cast<float>(0.5 * (1.0 - std::cos(angle)));
        cosine_[index] = static_cast<float>(std::cos(angle));
        sine_[index] = static_cast<float>(std::sin(angle));
    }
}

void LogMelExtractor::fft(float * input, const int size, float * output) noexcept {
    if (size == 1) {
        output[0] = input[0];
        output[1] = 0.0F;
        return;
    }

    const int half_size = size / 2;
    if (size - half_size * 2 == 1) {
        dft(input, size, output);
        return;
    }

    float * even = input + size;
    for (int index = 0; index < half_size; ++index) {
        even[index] = input[2 * index];
    }
    float * even_fft = output + 2 * size;
    fft(even, half_size, even_fft);

    float * odd = even;
    for (int index = 0; index < half_size; ++index) {
        odd[index] = input[2 * index + 1];
    }
    float * odd_fft = even_fft + size;
    fft(odd, half_size, odd_fft);

    const int table_step = static_cast<int>(kFftSize) / size;
    for (int index = 0; index < half_size; ++index) {
        const int table_index = index * table_step;
        const auto real = cosine_[table_index];
        const auto imaginary = -sine_[table_index];
        const auto odd_real = odd_fft[2 * index];
        const auto odd_imaginary = odd_fft[2 * index + 1];

        output[2 * index] = even_fft[2 * index] + real * odd_real - imaginary * odd_imaginary;
        output[2 * index + 1] = even_fft[2 * index + 1] + real * odd_imaginary + imaginary * odd_real;
        output[2 * (index + half_size)] =
            even_fft[2 * index] - real * odd_real + imaginary * odd_imaginary;
        output[2 * (index + half_size) + 1] =
            even_fft[2 * index + 1] - real * odd_imaginary - imaginary * odd_real;
    }
}

void LogMelExtractor::dft(const float * input, const int size, float * output) const noexcept {
    const int table_step = static_cast<int>(kFftSize) / size;
    for (int frequency = 0; frequency < size; ++frequency) {
        float real = 0.0F;
        float imaginary = 0.0F;
        for (int sample = 0; sample < size; ++sample) {
            const int table_index = (frequency * sample * table_step) % static_cast<int>(kFftSize);
            real += input[sample] * cosine_[table_index];
            imaginary -= input[sample] * sine_[table_index];
        }
        output[2 * frequency] = real;
        output[2 * frequency + 1] = imaginary;
    }
}

}  // namespace galaxyssi::asr
