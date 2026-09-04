#include "GalaxySSIWhisperRuntime.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <memory>
#include <mutex>
#include <new>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "whisper.h"

namespace {

constexpr int32_t kSampleRateHz = 16'000;
constexpr int32_t kMaximumPcmSamples = kSampleRateHz * 60 * 10;

struct TimingValue {
    double sample_ms = 0.0;
    double encode_ms = 0.0;
    double decode_ms = 0.0;
    double total_ms = 0.0;
    int64_t audio_ms = 0;
    double rtf = 0.0;
};

struct SegmentValue {
    int64_t start_ms = 0;
    int64_t end_ms = 0;
    std::string text;
    float average_log_probability = 0.0f;
    float no_speech_probability = 0.0f;
};

struct RuntimeRecord {
    int64_t handle = 0;
    whisper_context *context = nullptr;
    int thread_count = 1;
    std::string model_path;
    std::atomic<bool> closing{false};
    std::mutex decode_mutex;

    ~RuntimeRecord() {
        if (context != nullptr) {
            whisper_free(context);
            context = nullptr;
        }
    }
};

struct SessionRecord {
    int64_t handle = 0;
    std::shared_ptr<RuntimeRecord> runtime;
    whisper_state *state = nullptr;
    std::string language = "auto";
    std::string prompt;
    bool translate = false;
    bool no_context = true;
    bool single_segment = false;
    int max_tokens = 0;
    std::atomic<bool> abort_requested{false};
    std::atomic<bool> closing{false};
    std::mutex timings_mutex;
    TimingValue timings;

    ~SessionRecord() {
        if (state != nullptr && runtime != nullptr) {
            std::lock_guard<std::mutex> lock(runtime->decode_mutex);
            whisper_free_state(state);
            state = nullptr;
        }
    }
};

std::mutex registry_mutex;
std::unordered_map<int64_t, std::shared_ptr<RuntimeRecord>> runtimes;
std::unordered_map<int64_t, std::shared_ptr<SessionRecord>> sessions;
std::atomic<int64_t> next_handle{1};

int64_t allocate_handle() {
    int64_t value = next_handle.fetch_add(1, std::memory_order_relaxed);
    if (value <= 0) {
        next_handle.store(2, std::memory_order_relaxed);
        value = 1;
    }
    return value;
}

std::shared_ptr<RuntimeRecord> find_runtime(int64_t handle) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    const auto found = runtimes.find(handle);
    return found == runtimes.end() ? nullptr : found->second;
}

std::shared_ptr<SessionRecord> find_session(int64_t handle) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    const auto found = sessions.find(handle);
    return found == sessions.end() ? nullptr : found->second;
}

bool abort_callback(void *user_data) {
    auto *session = static_cast<SessionRecord *>(user_data);
    return session == nullptr || session->abort_requested.load(std::memory_order_relaxed) ||
           session->closing.load(std::memory_order_relaxed) ||
           session->runtime->closing.load(std::memory_order_relaxed);
}

std::string c_string(const char *value, size_t maximum_length) {
    if (value == nullptr) return {};
    std::string result(value);
    if (result.size() > maximum_length) result.resize(maximum_length);
    return result;
}

std::string json_string(const std::string &value) {
    std::ostringstream result;
    result << '"';
    for (const unsigned char character : value) {
        switch (character) {
            case '"': result << "\\\""; break;
            case '\\': result << "\\\\"; break;
            case '\b': result << "\\b"; break;
            case '\f': result << "\\f"; break;
            case '\n': result << "\\n"; break;
            case '\r': result << "\\r"; break;
            case '\t': result << "\\t"; break;
            default:
                if (character < 0x20) {
                    result << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                           << static_cast<int>(character) << std::dec << std::setfill(' ');
                } else {
                    result << static_cast<char>(character);
                }
        }
    }
    result << '"';
    return result.str();
}

std::string json_number(double value) {
    if (!std::isfinite(value)) return "0";
    std::ostringstream result;
    result << std::setprecision(9) << value;
    return result.str();
}

std::string timings_json(const TimingValue &timings) {
    std::ostringstream result;
    result << "{\"sample_ms\":" << json_number(timings.sample_ms)
           << ",\"encode_ms\":" << json_number(timings.encode_ms)
           << ",\"decode_ms\":" << json_number(timings.decode_ms)
           << ",\"total_ms\":" << json_number(timings.total_ms)
           << ",\"audio_ms\":" << timings.audio_ms
           << ",\"rtf\":" << json_number(timings.rtf) << '}';
    return result.str();
}

std::string result_json(
        int code,
        const std::vector<SegmentValue> &segments,
        const std::string &language,
        const TimingValue &timings,
        bool aborted,
        const std::string &message) {
    std::ostringstream result;
    result << "{\"code\":" << code << ",\"segments\":[";
    for (size_t index = 0; index < segments.size(); ++index) {
        if (index > 0) result << ',';
        const SegmentValue &segment = segments[index];
        result << "{\"start_ms\":" << segment.start_ms
               << ",\"end_ms\":" << segment.end_ms
               << ",\"text\":" << json_string(segment.text)
               << ",\"average_log_probability\":"
               << json_number(segment.average_log_probability)
               << ",\"no_speech_probability\":"
               << json_number(segment.no_speech_probability) << '}';
    }
    result << "],\"detected_language\":"
           << (language.empty() ? "null" : json_string(language))
           << ",\"timings\":" << timings_json(timings)
           << ",\"aborted\":" << (aborted ? "true" : "false")
           << ",\"message\":"
           << (message.empty() ? "null" : json_string(message)) << '}';
    return result.str();
}

char *copy_string(const std::string &value) {
    char *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result == nullptr) return nullptr;
    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

char *failure_json(int code, const char *message, bool aborted = false) {
    return copy_string(result_json(code, {}, {}, {}, aborted, message == nullptr ? "" : message));
}

}  // namespace

extern "C" int64_t galaxyssi_whisper_create_runtime(
        const char *model_path,
        int32_t thread_count,
        int32_t use_gpu) {
    if (use_gpu != 0) return 0;
    whisper_context *context = nullptr;
    try {
        const std::string path = c_string(model_path, 4096);
        if (path.empty()) return 0;
        whisper_context_params params = whisper_context_default_params();
        params.use_gpu = false;
        context = whisper_init_from_file_with_params_no_state(path.c_str(), params);
        if (context == nullptr) return 0;
        auto runtime = std::make_shared<RuntimeRecord>();
        runtime->handle = allocate_handle();
        runtime->context = context;
        context = nullptr;
        runtime->thread_count = std::clamp(static_cast<int>(thread_count), 1, 16);
        runtime->model_path = path;
        std::lock_guard<std::mutex> lock(registry_mutex);
        runtimes.emplace(runtime->handle, runtime);
        return runtime->handle;
    } catch (...) {
        if (context != nullptr) whisper_free(context);
        return 0;
    }
}

extern "C" int64_t galaxyssi_whisper_create_session(
        int64_t runtime_handle,
        const char *language,
        int32_t translate,
        int32_t no_context,
        int32_t single_segment,
        int32_t max_tokens,
        const char *prompt) {
    auto runtime = find_runtime(runtime_handle);
    if (runtime == nullptr || runtime->closing.load(std::memory_order_relaxed)) return 0;
    whisper_state *state = nullptr;
    try {
        {
            std::lock_guard<std::mutex> decode_lock(runtime->decode_mutex);
            if (runtime->closing.load(std::memory_order_relaxed)) return 0;
            state = whisper_init_state(runtime->context);
        }
        if (state == nullptr) return 0;
        auto session = std::make_shared<SessionRecord>();
        session->handle = allocate_handle();
        session->runtime = runtime;
        session->state = state;
        state = nullptr;
        session->language = c_string(language, 16);
        if (session->language.empty()) session->language = "auto";
        session->prompt = c_string(prompt, 1024);
        session->translate = translate != 0;
        session->no_context = no_context != 0;
        session->single_segment = single_segment != 0;
        session->max_tokens = std::clamp(static_cast<int>(max_tokens), 0, 4096);
        std::lock_guard<std::mutex> lock(registry_mutex);
        if (runtime->closing.load(std::memory_order_relaxed) || runtimes.count(runtime_handle) == 0) {
            return 0;
        }
        sessions.emplace(session->handle, session);
        return session->handle;
    } catch (...) {
        if (state != nullptr) whisper_free_state(state);
        return 0;
    }
}

extern "C" char *galaxyssi_whisper_decode_json(
        int64_t session_handle,
        const int16_t *pcm,
        int32_t length) {
    auto session = find_session(session_handle);
    if (session == nullptr || session->closing.load(std::memory_order_relaxed)) {
        return failure_json(2, "Whisper session handle is invalid");
    }
    if (pcm == nullptr || length <= 0 || length > kMaximumPcmSamples) {
        return failure_json(6, "PCM16 input is invalid");
    }

    try {
        std::vector<float> samples(static_cast<size_t>(length));
        std::transform(pcm, pcm + length, samples.begin(), [](int16_t value) {
            return static_cast<float>(value) / 32768.0f;
        });
        std::vector<SegmentValue> segments;
        std::string detected_language;
        TimingValue timing;
        int result_code = 0;
        std::string result_message;
        bool aborted = false;
        const auto started = std::chrono::steady_clock::now();
        {
            std::lock_guard<std::mutex> decode_lock(session->runtime->decode_mutex);
            if (session->abort_requested.load(std::memory_order_relaxed) ||
                session->closing.load(std::memory_order_relaxed) ||
                session->runtime->closing.load(std::memory_order_relaxed)) {
                return failure_json(1, "Whisper decode was cancelled", true);
            }
            whisper_reset_timings_from_state(session->state);
            whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            params.print_realtime = false;
            params.print_progress = false;
            params.print_timestamps = false;
            params.print_special = false;
            params.translate = session->translate;
            params.language = session->language.c_str();
            params.n_threads = session->runtime->thread_count;
            params.offset_ms = 0;
            params.no_context = session->no_context;
            params.single_segment = session->single_segment;
            params.max_tokens = session->max_tokens;
            params.suppress_blank = true;
            params.suppress_nst = true;
            params.temperature = 0.0f;
            params.initial_prompt = session->prompt.empty() ? nullptr : session->prompt.c_str();
            params.abort_callback = abort_callback;
            params.abort_callback_user_data = session.get();

            const int native_result = whisper_full_with_state(
                session->runtime->context,
                session->state,
                params,
                samples.data(),
                static_cast<int>(samples.size())
            );
            aborted = session->abort_requested.load(std::memory_order_relaxed) ||
                      session->closing.load(std::memory_order_relaxed) ||
                      session->runtime->closing.load(std::memory_order_relaxed);
            if (native_result != 0) {
                result_code = aborted ? 1 : 7;
                result_message = aborted ? "Whisper decode was cancelled" : "whisper_full_with_state failed";
            } else {
                const int language_id = whisper_full_lang_id_from_state(session->state);
                if (language_id >= 0) {
                    const char *language_name = whisper_lang_str(language_id);
                    if (language_name != nullptr) detected_language = language_name;
                }
                const int segment_count = whisper_full_n_segments_from_state(session->state);
                segments.reserve(static_cast<size_t>(std::max(segment_count, 0)));
                for (int segment_index = 0; segment_index < segment_count; ++segment_index) {
                    SegmentValue value;
                    value.start_ms = whisper_full_get_segment_t0_from_state(session->state, segment_index) * 10;
                    value.end_ms = whisper_full_get_segment_t1_from_state(session->state, segment_index) * 10;
                    const char *text = whisper_full_get_segment_text_from_state(session->state, segment_index);
                    if (text != nullptr) value.text = text;
                    value.no_speech_probability = whisper_full_get_segment_no_speech_prob_from_state(
                        session->state,
                        segment_index
                    );
                    const int token_count = whisper_full_n_tokens_from_state(session->state, segment_index);
                    if (token_count > 0) {
                        double log_probability = 0.0;
                        for (int token_index = 0; token_index < token_count; ++token_index) {
                            log_probability += whisper_full_get_token_data_from_state(
                                session->state,
                                segment_index,
                                token_index
                            ).plog;
                        }
                        value.average_log_probability = static_cast<float>(log_probability / token_count);
                    }
                    segments.push_back(std::move(value));
                }
            }

            whisper_timings native_timings{};
            whisper_get_timings_from_state(session->state, &native_timings);
            timing.sample_ms = native_timings.sample_ms;
            timing.encode_ms = native_timings.encode_ms;
            timing.decode_ms = native_timings.decode_ms;
        }
        const auto finished = std::chrono::steady_clock::now();
        timing.total_ms = std::chrono::duration<double, std::milli>(finished - started).count();
        timing.audio_ms = static_cast<int64_t>(length) * 1000 / kSampleRateHz;
        timing.rtf = timing.audio_ms > 0 ? timing.total_ms / timing.audio_ms : 0.0;
        {
            std::lock_guard<std::mutex> timings_lock(session->timings_mutex);
            session->timings = timing;
        }
        return copy_string(result_json(result_code, segments, detected_language, timing, aborted, result_message));
    } catch (const std::bad_alloc &) {
        return failure_json(8, "Whisper decode ran out of memory");
    } catch (...) {
        return failure_json(9, "Whisper native decode failed unexpectedly");
    }
}

extern "C" char *galaxyssi_whisper_timings_json(int64_t session_handle) {
    const auto session = find_session(session_handle);
    if (session == nullptr) return copy_string(timings_json({}));
    std::lock_guard<std::mutex> lock(session->timings_mutex);
    return copy_string(timings_json(session->timings));
}

extern "C" void galaxyssi_whisper_request_abort(int64_t session_handle) {
    const auto session = find_session(session_handle);
    if (session != nullptr) session->abort_requested.store(true, std::memory_order_relaxed);
}

extern "C" void galaxyssi_whisper_destroy_session(int64_t session_handle) {
    std::shared_ptr<SessionRecord> removed;
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        const auto found = sessions.find(session_handle);
        if (found == sessions.end()) return;
        removed = found->second;
        removed->closing.store(true, std::memory_order_relaxed);
        removed->abort_requested.store(true, std::memory_order_relaxed);
        sessions.erase(found);
    }
}

extern "C" void galaxyssi_whisper_destroy_runtime(int64_t runtime_handle) {
    std::shared_ptr<RuntimeRecord> removed_runtime;
    std::vector<std::shared_ptr<SessionRecord>> removed_sessions;
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        const auto found = runtimes.find(runtime_handle);
        if (found == runtimes.end()) return;
        removed_runtime = found->second;
        removed_runtime->closing.store(true, std::memory_order_relaxed);
        runtimes.erase(found);
        for (auto iterator = sessions.begin(); iterator != sessions.end();) {
            if (iterator->second->runtime.get() == removed_runtime.get()) {
                iterator->second->closing.store(true, std::memory_order_relaxed);
                iterator->second->abort_requested.store(true, std::memory_order_relaxed);
                removed_sessions.push_back(iterator->second);
                iterator = sessions.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }
}

extern "C" int32_t galaxyssi_whisper_active_runtime_count(void) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    return static_cast<int32_t>(runtimes.size());
}

extern "C" int32_t galaxyssi_whisper_active_session_count(void) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    return static_cast<int32_t>(sessions.size());
}

extern "C" void galaxyssi_whisper_free_string(char *value) {
    std::free(value);
}
