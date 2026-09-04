#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace galaxyssi::asr {

class MelFilterBank128 final {
public:
    static constexpr std::size_t kMelBins = 128;
    static constexpr std::size_t kCompactMelBins = 80;
    static constexpr std::size_t kFftBins = 201;
    static constexpr std::size_t kValueCount = kMelBins * kFftBins;

    MelFilterBank128();
    explicit MelFilterBank128(std::vector<float> values);
    static bool load(const std::string & path,
                     MelFilterBank128 * destination,
                     std::string * error_message = nullptr);

    const float * row(std::size_t mel_bin) const noexcept;
    const std::vector<float> & values() const noexcept;
    std::size_t mel_bins() const noexcept;

private:
    std::size_t mel_bins_ = kMelBins;
    std::vector<float> values_;
};

class LogMelExtractor final {
public:
    static constexpr int kSampleRateHz = 16'000;
    static constexpr std::size_t kMaximumSamples = 480'000;
    static constexpr std::size_t kFftSize = 400;
    static constexpr std::size_t kHopSize = 160;
    static constexpr std::size_t kMelFrames = 3'000;
    static constexpr std::size_t kOutputValues = MelFilterBank128::kMelBins * kMelFrames;

    explicit LogMelExtractor(MelFilterBank128 filter_bank);

    bool compute_pcm16(const std::int16_t * samples,
                       std::size_t sample_count,
                       std::string * error_message = nullptr) noexcept;
    const std::vector<float> & output() const noexcept;
    std::size_t output_values() const noexcept;

private:
    void initialize_tables() noexcept;
    void fft(float * input, int size, float * output) noexcept;
    void dft(const float * input, int size, float * output) const noexcept;

    MelFilterBank128 filter_bank_;
    std::array<float, kFftSize> hann_{};
    std::array<float, kFftSize> cosine_{};
    std::array<float, kFftSize> sine_{};
    std::vector<float> padded_samples_;
    std::array<float, kFftSize * 2> fft_input_{};
    std::array<float, kFftSize * 8> fft_output_{};
    std::array<float, MelFilterBank128::kFftBins> power_spectrum_{};
    std::vector<float> mel_output_;
};

}  // namespace galaxyssi::asr
