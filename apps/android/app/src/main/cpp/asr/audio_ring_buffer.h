#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>

namespace galaxyssi::asr {

static_assert(std::atomic<std::int16_t>::is_always_lock_free,
              "The realtime audio ring requires lock-free 16-bit atomics");

// Single-producer ring buffer. Samples are atomic so feature extraction can
// take a bounded snapshot while AudioRecord continues writing newer frames.
class AudioRingBuffer final {
public:
    explicit AudioRingBuffer(std::size_t capacity_samples);

    AudioRingBuffer(const AudioRingBuffer &) = delete;
    AudioRingBuffer & operator=(const AudioRingBuffer &) = delete;

    bool write(const std::int16_t * samples, std::size_t sample_count) noexcept;
    bool read(std::uint64_t start_sequence,
              std::size_t sample_count,
              std::int16_t * destination) const noexcept;
    std::size_t read_latest(std::size_t maximum_samples,
                            std::int16_t * destination,
                            std::uint64_t * start_sequence = nullptr) const noexcept;

    std::uint64_t write_sequence() const noexcept;
    std::size_t available_samples() const noexcept;
    std::size_t capacity_samples() const noexcept;
    void clear() noexcept;

private:
    const std::size_t capacity_;
    std::unique_ptr<std::atomic<std::int16_t>[]> samples_;
    alignas(64) std::atomic<std::uint64_t> write_sequence_{0};
};

}  // namespace galaxyssi::asr
