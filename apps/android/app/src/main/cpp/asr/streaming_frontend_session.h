#pragma once

#include "audio_frontend.h"
#include "log_mel_extractor.h"

#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace galaxyssi::asr {

enum class FeatureWindowKind : std::int64_t {
    kPartial = 1,
    kFinal = 2,
    kNoSpeechFinal = 3,
};

struct FeatureWindowMetadata {
    FeatureWindowKind kind = FeatureWindowKind::kPartial;
    std::uint64_t start_sample = 0;
    std::uint64_t end_sample = 0;
    std::uint64_t segment_start_sample = 0;
    VadEndReason end_reason = VadEndReason::kNone;
};

enum class FeatureWaitResult {
    kReady,
    kTimeout,
    kClosed,
    kError,
};

class StreamingFrontendSession final {
public:
    static constexpr std::size_t kWindowSlotCount = 3;
    static constexpr int kInputQueueDurationSeconds = 2;

    StreamingFrontendSession(AudioFrontendConfig config, MelFilterBank128 filter_bank);
    ~StreamingFrontendSession();

    StreamingFrontendSession(const StreamingFrontendSession &) = delete;
    StreamingFrontendSession & operator=(const StreamingFrontendSession &) = delete;

    bool start() noexcept;
    bool push_pcm16(const std::int16_t * samples, std::size_t sample_count) noexcept;
    void stop() noexcept;
    void cancel() noexcept;
    void pause() noexcept;
    bool resume() noexcept;
    bool update_partial_policy(int update_interval_ms, bool emit_partials) noexcept;
    void close() noexcept;

    FeatureWaitResult wait_for_features(float * destination,
                                        std::size_t destination_count,
                                        std::chrono::milliseconds timeout,
                                        FeatureWindowMetadata * metadata,
                                        std::string * error_message = nullptr) noexcept;
    std::size_t feature_value_count() const noexcept;

private:
    struct WindowSlot {
        std::vector<std::int16_t> samples;
        std::size_t sample_count = 0;
        FeatureWindowMetadata metadata{};
        bool occupied = false;
        bool queued = false;
    };

    void worker_loop() noexcept;
    void enqueue_window(const DecodeWindow & window) noexcept;
    void enqueue_no_speech_final() noexcept;
    std::size_t acquire_window_slot_locked(bool final) noexcept;
    void release_window_slot_locked(std::size_t index) noexcept;
    void clear_windows_locked() noexcept;
    void clear_input_locked() noexcept;

    AudioFrontendConfig config_;
    AudioFrontend frontend_;
    LogMelExtractor extractor_;
    std::mutex frontend_mutex_;

    std::vector<std::int16_t> input_queue_;
    std::size_t input_read_ = 0;
    std::size_t input_write_ = 0;
    std::size_t input_count_ = 0;
    std::mutex input_mutex_;
    std::condition_variable input_condition_;
    bool active_ = false;
    bool paused_ = false;
    bool stop_requested_ = false;
    std::atomic<bool> closed_{false};
    std::atomic<std::uint64_t> generation_{0};
    std::thread worker_;

    std::array<WindowSlot, kWindowSlotCount> window_slots_{};
    std::deque<std::size_t> pending_windows_;
    std::mutex window_mutex_;
    std::condition_variable window_condition_;
    bool final_enqueued_ = false;
    bool wait_interrupted_ = false;
};

}  // namespace galaxyssi::asr
