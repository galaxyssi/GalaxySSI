#include "audio_ring_buffer.h"

#include <algorithm>
#include <stdexcept>

namespace galaxyssi::asr {

AudioRingBuffer::AudioRingBuffer(const std::size_t capacity_samples)
    : capacity_(capacity_samples),
      samples_(capacity_samples == 0 ? nullptr : new std::atomic<std::int16_t>[capacity_samples]) {
    if (capacity_ == 0) {
        throw std::invalid_argument("Audio ring capacity must be positive");
    }
    for (std::size_t index = 0; index < capacity_; ++index) {
        samples_[index].store(0, std::memory_order_relaxed);
    }
}

bool AudioRingBuffer::write(const std::int16_t * samples, std::size_t sample_count) noexcept {
    if (samples == nullptr || sample_count == 0) {
        return false;
    }

    const auto original_count = sample_count;
    std::size_t skipped = 0;
    // A write larger than the ring can only preserve its newest suffix, but
    // its monotonic sequence still advances over every received sample.
    if (sample_count > capacity_) {
        skipped = sample_count - capacity_;
        samples += skipped;
        sample_count = capacity_;
    }

    const auto first_sequence = write_sequence_.load(std::memory_order_relaxed);
    for (std::size_t offset = 0; offset < sample_count; ++offset) {
        samples_[(first_sequence + skipped + offset) % capacity_].store(samples[offset], std::memory_order_relaxed);
    }
    write_sequence_.store(first_sequence + original_count, std::memory_order_release);
    return true;
}

bool AudioRingBuffer::read(const std::uint64_t start_sequence,
                           const std::size_t sample_count,
                           std::int16_t * destination) const noexcept {
    if (destination == nullptr || sample_count > capacity_) {
        return false;
    }
    if (sample_count == 0) {
        return true;
    }

    const auto committed_before = write_sequence_.load(std::memory_order_acquire);
    if (start_sequence > committed_before || sample_count > committed_before - start_sequence) {
        return false;
    }
    if (committed_before - start_sequence > capacity_) {
        return false;
    }

    for (std::size_t offset = 0; offset < sample_count; ++offset) {
        destination[offset] = samples_[(start_sequence + offset) % capacity_].load(std::memory_order_relaxed);
    }

    // Newer writes are harmless until they wrap onto the requested range.
    const auto committed_after = write_sequence_.load(std::memory_order_acquire);
    return committed_after >= start_sequence + sample_count &&
           committed_after - start_sequence <= capacity_;
}

std::size_t AudioRingBuffer::read_latest(const std::size_t maximum_samples,
                                         std::int16_t * destination,
                                         std::uint64_t * start_sequence) const noexcept {
    if (destination == nullptr || maximum_samples == 0) {
        return 0;
    }

    for (int attempt = 0; attempt < 4; ++attempt) {
        const auto committed = write_sequence_.load(std::memory_order_acquire);
        const auto count = static_cast<std::size_t>(std::min<std::uint64_t>(
            std::min<std::uint64_t>(committed, capacity_), maximum_samples));
        const auto first = committed - count;
        if (read(first, count, destination)) {
            if (start_sequence != nullptr) {
                *start_sequence = first;
            }
            return count;
        }
    }
    return 0;
}

std::uint64_t AudioRingBuffer::write_sequence() const noexcept {
    return write_sequence_.load(std::memory_order_acquire);
}

std::size_t AudioRingBuffer::available_samples() const noexcept {
    return static_cast<std::size_t>(std::min<std::uint64_t>(write_sequence(), capacity_));
}

std::size_t AudioRingBuffer::capacity_samples() const noexcept {
    return capacity_;
}

void AudioRingBuffer::clear() noexcept {
    for (std::size_t index = 0; index < capacity_; ++index) {
        samples_[index].store(0, std::memory_order_relaxed);
    }
    write_sequence_.store(0, std::memory_order_release);
}

}  // namespace galaxyssi::asr
