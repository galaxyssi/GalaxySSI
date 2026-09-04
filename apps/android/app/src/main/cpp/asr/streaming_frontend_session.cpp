#include "streaming_frontend_session.h"

#include <algorithm>
#include <cstring>
#include <limits>
#include <utility>

namespace galaxyssi::asr {
namespace {

constexpr std::size_t kNoSlot = std::numeric_limits<std::size_t>::max();

void set_error(std::string * destination, const std::string & message) {
    if (destination != nullptr) {
        *destination = message;
    }
}

}  // namespace

StreamingFrontendSession::StreamingFrontendSession(AudioFrontendConfig config,
                                                   MelFilterBank128 filter_bank)
    : config_(config),
      frontend_(config_, [this](const DecodeWindow & window) { enqueue_window(window); }),
      extractor_(std::move(filter_bank)),
      input_queue_(static_cast<std::size_t>(config_.input_sample_rate_hz) *
                   kInputQueueDurationSeconds) {
    for (auto & slot : window_slots_) {
        slot.samples.resize(LogMelExtractor::kMaximumSamples);
    }
    worker_ = std::thread(&StreamingFrontendSession::worker_loop, this);
}

StreamingFrontendSession::~StreamingFrontendSession() {
    close();
}

bool StreamingFrontendSession::start() noexcept {
    {
        std::lock_guard<std::mutex> input_guard(input_mutex_);
        if (closed_.load() || active_) {
            return false;
        }
        clear_input_locked();
        active_ = true;
        paused_ = false;
        stop_requested_ = false;
        generation_.fetch_add(1);
    }
    {
        std::lock_guard<std::mutex> window_guard(window_mutex_);
        clear_windows_locked();
        final_enqueued_ = false;
        wait_interrupted_ = false;
    }
    {
        std::lock_guard<std::mutex> frontend_guard(frontend_mutex_);
        frontend_.reset();
    }
    input_condition_.notify_all();
    return true;
}

bool StreamingFrontendSession::push_pcm16(const std::int16_t * samples,
                                          const std::size_t sample_count) noexcept {
    if ((samples == nullptr && sample_count != 0) || sample_count > input_queue_.size()) {
        return false;
    }
    {
        std::lock_guard<std::mutex> guard(input_mutex_);
        if (closed_.load() || !active_ || paused_ || stop_requested_ ||
            sample_count > input_queue_.size() - input_count_) {
            return false;
        }
        const auto first = std::min(sample_count, input_queue_.size() - input_write_);
        std::copy(samples, samples + first, input_queue_.begin() + input_write_);
        if (sample_count > first) {
            std::copy(samples + first, samples + sample_count, input_queue_.begin());
        }
        input_write_ = (input_write_ + sample_count) % input_queue_.size();
        input_count_ += sample_count;
    }
    input_condition_.notify_one();
    return true;
}

void StreamingFrontendSession::stop() noexcept {
    {
        std::lock_guard<std::mutex> guard(input_mutex_);
        if (closed_.load() || !active_) {
            return;
        }
        paused_ = false;
        stop_requested_ = true;
    }
    input_condition_.notify_all();
}

void StreamingFrontendSession::cancel() noexcept {
    {
        std::lock_guard<std::mutex> guard(input_mutex_);
        active_ = false;
        paused_ = false;
        stop_requested_ = false;
        generation_.fetch_add(1);
        clear_input_locked();
    }
    {
        std::lock_guard<std::mutex> frontend_guard(frontend_mutex_);
        frontend_.reset();
    }
    {
        std::lock_guard<std::mutex> guard(window_mutex_);
        clear_windows_locked();
        final_enqueued_ = false;
        wait_interrupted_ = true;
    }
    input_condition_.notify_all();
    window_condition_.notify_all();
}

void StreamingFrontendSession::pause() noexcept {
    {
        std::lock_guard<std::mutex> guard(input_mutex_);
        if (closed_.load() || !active_) {
            return;
        }
        paused_ = true;
        generation_.fetch_add(1);
        clear_input_locked();
    }
    {
        std::lock_guard<std::mutex> frontend_guard(frontend_mutex_);
        frontend_.reset();
    }
    {
        std::lock_guard<std::mutex> window_guard(window_mutex_);
        clear_windows_locked();
        final_enqueued_ = false;
    }
}

bool StreamingFrontendSession::resume() noexcept {
    {
        std::lock_guard<std::mutex> guard(input_mutex_);
        if (closed_.load() || !active_ || !paused_) {
            return false;
        }
        paused_ = false;
    }
    input_condition_.notify_all();
    return true;
}

bool StreamingFrontendSession::update_partial_policy(const int update_interval_ms,
                                                     const bool emit_partials) noexcept {
    std::lock_guard<std::mutex> frontend_guard(frontend_mutex_);
    if (closed_.load()) {
        return false;
    }
    return frontend_.update_partial_policy(update_interval_ms, emit_partials);
}

void StreamingFrontendSession::close() noexcept {
    {
        std::lock_guard<std::mutex> guard(input_mutex_);
        if (closed_.load()) {
            return;
        }
        closed_.store(true);
        active_ = false;
        paused_ = false;
        stop_requested_ = false;
        generation_.fetch_add(1);
        clear_input_locked();
    }
    input_condition_.notify_all();
    {
        std::lock_guard<std::mutex> guard(window_mutex_);
        wait_interrupted_ = true;
    }
    window_condition_.notify_all();
    if (worker_.joinable()) {
        worker_.join();
    }
}

FeatureWaitResult StreamingFrontendSession::wait_for_features(
    float * destination,
    const std::size_t destination_count,
    const std::chrono::milliseconds timeout,
    FeatureWindowMetadata * metadata,
    std::string * error_message) noexcept {
    if (destination == nullptr || destination_count < extractor_.output_values() ||
        metadata == nullptr) {
        set_error(error_message, "Feature output buffer is invalid");
        return FeatureWaitResult::kError;
    }

    std::size_t slot_index = kNoSlot;
    {
        std::unique_lock<std::mutex> lock(window_mutex_);
        const bool ready = window_condition_.wait_for(lock, timeout, [this] {
            return closed_.load() || wait_interrupted_ || !pending_windows_.empty();
        });
        if (!ready) {
            return FeatureWaitResult::kTimeout;
        }
        if (pending_windows_.empty()) {
            return FeatureWaitResult::kClosed;
        }
        slot_index = pending_windows_.front();
        pending_windows_.pop_front();
        window_slots_[slot_index].queued = false;
        *metadata = window_slots_[slot_index].metadata;
    }

    auto & slot = window_slots_[slot_index];
    if (metadata->kind == FeatureWindowKind::kNoSpeechFinal) {
        std::lock_guard<std::mutex> guard(window_mutex_);
        release_window_slot_locked(slot_index);
        return FeatureWaitResult::kReady;
    }

    std::string extraction_error;
    const bool extracted = extractor_.compute_pcm16(
        slot.samples.data(), slot.sample_count, &extraction_error);
    if (extracted) {
        std::memcpy(destination,
                    extractor_.output().data(),
                    extractor_.output_values() * sizeof(float));
    }
    {
        std::lock_guard<std::mutex> guard(window_mutex_);
        release_window_slot_locked(slot_index);
    }
    if (!extracted) {
        set_error(error_message, extraction_error);
        return FeatureWaitResult::kError;
    }
    return FeatureWaitResult::kReady;
}

std::size_t StreamingFrontendSession::feature_value_count() const noexcept {
    return extractor_.output_values();
}

void StreamingFrontendSession::worker_loop() noexcept {
    std::array<std::int16_t, 480> chunk{};
    while (true) {
        std::size_t count = 0;
        bool finalize = false;
        std::uint64_t generation = 0;
        {
            std::unique_lock<std::mutex> lock(input_mutex_);
            input_condition_.wait(lock, [this] {
                return closed_.load() ||
                       (active_ && !paused_ && (input_count_ > 0 || stop_requested_));
            });
            if (closed_.load()) {
                return;
            }
            if (input_count_ > 0) {
                generation = generation_.load();
                count = std::min(input_count_, chunk.size());
                const auto first = std::min(count, input_queue_.size() - input_read_);
                std::copy(input_queue_.begin() + input_read_,
                          input_queue_.begin() + input_read_ + first,
                          chunk.begin());
                if (count > first) {
                    std::copy(input_queue_.begin(),
                              input_queue_.begin() + (count - first),
                              chunk.begin() + first);
                }
                input_read_ = (input_read_ + count) % input_queue_.size();
                input_count_ -= count;
            } else if (stop_requested_) {
                generation = generation_.load();
                stop_requested_ = false;
                active_ = false;
                finalize = true;
            }
        }

        if (count > 0) {
            bool accepted = true;
            {
                std::lock_guard<std::mutex> frontend_guard(frontend_mutex_);
                if (generation != generation_.load()) {
                    continue;
                }
                accepted = frontend_.push_pcm16(chunk.data(), count);
            }
            if (!accepted) {
                cancel();
            }
            continue;
        }
        if (finalize) {
            std::lock_guard<std::mutex> frontend_guard(frontend_mutex_);
            if (generation != generation_.load()) {
                continue;
            }
            frontend_.stop();
            bool needs_empty_final = false;
            {
                std::lock_guard<std::mutex> guard(window_mutex_);
                needs_empty_final = !final_enqueued_;
            }
            if (needs_empty_final) {
                enqueue_no_speech_final();
            }
        }
    }
}

void StreamingFrontendSession::enqueue_window(const DecodeWindow & window) noexcept {
    const auto count = window.sample_count();
    if (count == 0 || count > LogMelExtractor::kMaximumSamples) {
        return;
    }

    std::size_t slot_index = kNoSlot;
    {
        std::lock_guard<std::mutex> guard(window_mutex_);
        slot_index = acquire_window_slot_locked(window.final);
        if (slot_index == kNoSlot) {
            return;
        }
        auto & slot = window_slots_[slot_index];
        slot.sample_count = static_cast<std::size_t>(count);
        slot.metadata = FeatureWindowMetadata{
            window.final ? FeatureWindowKind::kFinal : FeatureWindowKind::kPartial,
            window.start_sample,
            window.end_sample,
            window.segment_start_sample,
            window.end_reason,
        };
    }

    auto & slot = window_slots_[slot_index];
    if (!frontend_.snapshot(window, slot.samples.data(), slot.samples.size())) {
        std::lock_guard<std::mutex> guard(window_mutex_);
        release_window_slot_locked(slot_index);
        return;
    }
    {
        std::lock_guard<std::mutex> guard(window_mutex_);
        slot.queued = true;
        pending_windows_.push_back(slot_index);
        if (window.final) {
            final_enqueued_ = true;
        }
    }
    window_condition_.notify_one();
}

void StreamingFrontendSession::enqueue_no_speech_final() noexcept {
    {
        std::lock_guard<std::mutex> guard(window_mutex_);
        const auto slot_index = acquire_window_slot_locked(true);
        if (slot_index == kNoSlot) {
            return;
        }
        auto & slot = window_slots_[slot_index];
        slot.sample_count = 0;
        slot.metadata = FeatureWindowMetadata{
            FeatureWindowKind::kNoSpeechFinal,
            0,
            frontend_.ring_buffer().write_sequence(),
            0,
            VadEndReason::kForced,
        };
        slot.queued = true;
        pending_windows_.push_back(slot_index);
        final_enqueued_ = true;
    }
    window_condition_.notify_one();
}

std::size_t StreamingFrontendSession::acquire_window_slot_locked(const bool final) noexcept {
    if (final) {
        for (auto iterator = pending_windows_.begin(); iterator != pending_windows_.end();) {
            const auto index = *iterator;
            if (window_slots_[index].metadata.kind == FeatureWindowKind::kPartial) {
                release_window_slot_locked(index);
                iterator = pending_windows_.erase(iterator);
            } else {
                ++iterator;
            }
        }
    } else {
        for (const auto index : pending_windows_) {
            auto & slot = window_slots_[index];
            if (slot.metadata.kind == FeatureWindowKind::kPartial) {
                slot.queued = false;
                pending_windows_.erase(std::find(pending_windows_.begin(), pending_windows_.end(), index));
                return index;
            }
        }
    }
    for (std::size_t index = 0; index < window_slots_.size(); ++index) {
        if (!window_slots_[index].occupied) {
            window_slots_[index].occupied = true;
            return index;
        }
    }
    return kNoSlot;
}

void StreamingFrontendSession::release_window_slot_locked(const std::size_t index) noexcept {
    if (index >= window_slots_.size()) {
        return;
    }
    auto & slot = window_slots_[index];
    slot.sample_count = 0;
    slot.metadata = FeatureWindowMetadata{};
    slot.occupied = false;
    slot.queued = false;
}

void StreamingFrontendSession::clear_windows_locked() noexcept {
    while (!pending_windows_.empty()) {
        const auto index = pending_windows_.front();
        pending_windows_.pop_front();
        release_window_slot_locked(index);
    }
}

void StreamingFrontendSession::clear_input_locked() noexcept {
    input_read_ = 0;
    input_write_ = 0;
    input_count_ = 0;
}

}  // namespace galaxyssi::asr
