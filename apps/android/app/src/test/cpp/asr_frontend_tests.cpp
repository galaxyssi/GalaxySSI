#include "audio_frontend.h"
#include "audio_resampler.h"
#include "audio_ring_buffer.h"
#include "log_mel_extractor.h"
#include "rolling_window.h"
#include "streaming_frontend_session.h"
#include "transcript_stabilizer.h"
#include "vad_engine.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using namespace galaxyssi::asr;
constexpr double kPi = 3.1415926535897932384626433832795;

void require(const bool condition, const std::string & message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

std::vector<std::int16_t> sine_wave(const int sample_rate,
                                    const double frequency,
                                    const double seconds,
                                    const double amplitude = 12'000.0) {
    const auto count = static_cast<std::size_t>(std::llround(sample_rate * seconds));
    std::vector<std::int16_t> result(count);
    for (std::size_t index = 0; index < count; ++index) {
        result[index] = static_cast<std::int16_t>(std::lround(
            amplitude * std::sin(2.0 * kPi * frequency * static_cast<double>(index) / sample_rate)));
    }
    return result;
}

double rms(const std::vector<std::int16_t> & values, const std::size_t skip) {
    long double sum = 0.0;
    std::size_t count = 0;
    for (std::size_t index = std::min(skip, values.size()); index < values.size(); ++index) {
        const auto value = static_cast<long double>(values[index]);
        sum += value * value;
        ++count;
    }
    return count == 0 ? 0.0 : static_cast<double>(std::sqrt(sum / count));
}

std::vector<std::int16_t> resample_in_chunks(const std::vector<std::int16_t> & input,
                                             const std::size_t chunk_size) {
    Pcm16Resampler resampler(48'000);
    std::vector<std::int16_t> output;
    output.reserve(input.size() / 3);
    std::size_t offset = 0;
    while (offset < input.size()) {
        const auto count = std::min(chunk_size, input.size() - offset);
        std::vector<std::int16_t> chunk_output(resampler.maximum_output_samples(count));
        std::size_t produced = 0;
        require(resampler.process(input.data() + offset,
                                  count,
                                  chunk_output.data(),
                                  chunk_output.size(),
                                  &produced),
                "48 kHz resampling failed");
        output.insert(output.end(), chunk_output.begin(), chunk_output.begin() + produced);
        offset += count;
    }
    return output;
}

void test_ring_buffer_wraps_without_stale_reads() {
    AudioRingBuffer ring(8);
    const std::int16_t first[] = {0, 1, 2, 3, 4, 5};
    require(ring.write(first, 6), "Initial ring write failed");
    std::int16_t output[8]{};
    require(ring.read_latest(8, output) == 6, "Initial ring snapshot length is wrong");
    for (int index = 0; index < 6; ++index) {
        require(output[index] == index, "Initial ring snapshot is corrupt");
    }

    const std::int16_t second[] = {6, 7, 8, 9, 10, 11};
    require(ring.write(second, 6), "Wrapped ring write failed");
    std::uint64_t start = 0;
    require(ring.read_latest(8, output, &start) == 8 && start == 4,
            "Wrapped ring snapshot range is wrong");
    for (int index = 0; index < 8; ++index) {
        require(output[index] == index + 4, "Wrapped ring snapshot is corrupt");
    }
    require(!ring.read(0, 1, output), "Overwritten ring data must not be readable");

    const std::int16_t oversized[] = {20, 21, 22, 23, 24, 25, 26, 27, 28, 29};
    require(ring.write(oversized, 10), "Oversized ring write failed");
    require(ring.write_sequence() == 22, "Oversized write lost the absolute sample timeline");
    require(ring.read_latest(8, output, &start) == 8 && start == 14,
            "Oversized ring write retained the wrong sequence range");
    for (int index = 0; index < 8; ++index) {
        require(output[index] == index + 22, "Oversized ring write retained the wrong suffix");
    }
}

void test_resampler_is_chunk_invariant_and_rejects_aliases() {
    const auto one_khz = sine_wave(48'000, 1'000.0, 1.0);
    const auto whole = resample_in_chunks(one_khz, one_khz.size());
    const auto chunked = resample_in_chunks(one_khz, 480);
    require(whole.size() == 16'000 && chunked.size() == whole.size(),
            "48 kHz to 16 kHz sample ratio is wrong");
    require(whole == chunked, "Streaming resampler output depends on input chunking");
    const auto passband_rms = rms(chunked, 256);
    require(passband_rms > 7'500.0 && passband_rms < 9'500.0,
            "Resampler attenuates the speech passband excessively");

    const auto twelve_khz = sine_wave(48'000, 12'000.0, 1.0);
    const auto rejected = resample_in_chunks(twelve_khz, 480);
    require(rms(rejected, 256) < passband_rms * 0.03,
            "Resampler does not suppress frequencies above the 16 kHz Nyquist limit");
}

VadDecision feed_vad_frame(VoiceActivityDetector & vad,
                           const std::vector<std::int16_t> & frame,
                           std::uint64_t & cursor) {
    const auto decision = vad.process_frame(frame.data(), frame.size(), cursor);
    cursor += frame.size();
    return decision;
}

void test_vad_applies_start_end_and_roll_boundaries() {
    VoiceActivityDetector vad;
    const std::vector<std::int16_t> silence(160, 0);
    const auto speech = sine_wave(16'000, 400.0, 0.01, 8'000.0);
    std::uint64_t cursor = 0;
    for (int frame = 0; frame < 20; ++frame) feed_vad_frame(vad, silence, cursor);

    VadDecision started;
    for (int frame = 0; frame < 50; ++frame) {
        const auto decision = feed_vad_frame(vad, speech, cursor);
        if (decision.type == VadEventType::kSpeechStarted) started = decision;
    }
    require(started.type == VadEventType::kSpeechStarted, "VAD did not start after four speech frames");
    require(started.first_voice_sample == 3'200 && started.segment_start_sample == 0,
            "VAD did not preserve the 200 ms pre-roll");

    VadDecision ended;
    for (int frame = 0; frame < 45; ++frame) {
        const auto decision = feed_vad_frame(vad, silence, cursor);
        if (decision.type == VadEventType::kSpeechEnded) ended = decision;
    }
    require(ended.type == VadEventType::kSpeechEnded && ended.segment_accepted,
            "VAD did not finalize an accepted utterance");
    require(ended.end_reason == VadEndReason::kSilence && ended.segment_end_sample == 13'600,
            "VAD did not apply the 150 ms post-roll boundary");
}

void test_vad_discards_short_segments() {
    VoiceActivityDetector vad;
    const std::vector<std::int16_t> silence(160, 0);
    const auto speech = sine_wave(16'000, 400.0, 0.01, 8'000.0);
    std::uint64_t cursor = 0;
    for (int frame = 0; frame < 10; ++frame) feed_vad_frame(vad, speech, cursor);
    VadDecision final;
    for (int frame = 0; frame < 45; ++frame) {
        const auto decision = feed_vad_frame(vad, silence, cursor);
        if (decision.type == VadEventType::kSegmentDiscarded) final = decision;
    }
    require(final.type == VadEventType::kSegmentDiscarded && !final.segment_accepted,
            "VAD accepted speech shorter than 300 ms");
}

void test_vad_enforces_maximum_segment() {
    VadConfig config;
    config.maximum_segment_ms = 25'000;
    VoiceActivityDetector vad(config);
    const auto speech = sine_wave(16'000, 400.0, 0.01, 8'000.0);
    std::uint64_t cursor = 0;
    VadDecision final;
    for (int frame = 0; frame < 2'600; ++frame) {
        const auto decision = feed_vad_frame(vad, speech, cursor);
        if (decision.type == VadEventType::kSpeechEnded) {
            final = decision;
            break;
        }
    }
    require(final.type == VadEventType::kSpeechEnded &&
                final.end_reason == VadEndReason::kMaximumDuration,
            "VAD did not cap a continuous utterance at 25 seconds");
}

void test_rolling_window_emits_partials_and_final() {
    RollingWindowPlanner planner;
    VadDecision start;
    start.type = VadEventType::kSpeechStarted;
    start.segment_start_sample = 0;
    start.first_voice_sample = 3'200;
    require(!planner.on_vad_decision(start).has_value(), "Speech start must not decode immediately");

    VadDecision active;
    active.type = VadEventType::kSpeechActive;
    active.segment_end_sample = 17'600;
    const auto partial = planner.on_vad_decision(active);
    require(partial.has_value() && !partial->final && partial->end_sample == 17'600,
            "First rolling partial was not scheduled at 900 ms");

    VadDecision ended;
    ended.type = VadEventType::kSpeechEnded;
    ended.segment_accepted = true;
    ended.segment_end_sample = 32'000;
    ended.end_reason = VadEndReason::kSilence;
    const auto final = planner.on_vad_decision(ended);
    require(final.has_value() && final->final && final->end_reason == VadEndReason::kSilence,
            "Sentence-end decode was not scheduled");

    planner.on_vad_decision(start);
    ended.segment_end_sample = 400'000;
    const auto long_final = planner.on_vad_decision(ended);
    require(long_final.has_value() && long_final->start_sample == 0 &&
                long_final->sample_count() == 400'000,
            "Final decoding did not retain the complete segment up to 28 seconds");

    RollingWindowConfig saver_config;
    saver_config.emit_partials = false;
    RollingWindowPlanner saver(saver_config);
    saver.on_vad_decision(start);
    require(!saver.on_vad_decision(active).has_value(), "Power saver must suppress partial decoding");
    require(saver.on_vad_decision(ended).has_value(), "Power saver must retain final decoding");
}

void test_rolling_window_updates_partial_policy_without_losing_final() {
    RollingWindowPlanner planner;
    VadDecision start;
    start.type = VadEventType::kSpeechStarted;
    start.segment_start_sample = 0;
    start.first_voice_sample = 0;
    planner.on_vad_decision(start);

    VadDecision active;
    active.type = VadEventType::kSpeechActive;
    active.segment_end_sample = 14'400;
    require(planner.on_vad_decision(active).has_value(), "Initial partial was not emitted");
    require(planner.update_partial_policy(1'200, true), "Runtime interval update was rejected");
    active.segment_end_sample = 32'000;
    require(!planner.on_vad_decision(active).has_value(), "Updated interval was not applied");
    active.segment_end_sample = 33'600;
    require(planner.on_vad_decision(active).has_value(), "Updated interval never emitted a partial");

    require(planner.update_partial_policy(1'200, false), "Final-only policy was rejected");
    active.segment_end_sample = 64'000;
    require(!planner.on_vad_decision(active).has_value(), "Final-only policy emitted a partial");
    VadDecision ended;
    ended.type = VadEventType::kSpeechEnded;
    ended.segment_accepted = true;
    ended.segment_end_sample = 65'600;
    ended.end_reason = VadEndReason::kSilence;
    const auto final = planner.on_vad_decision(ended);
    require(final.has_value() && final->final, "Final-only policy discarded sentence finalization");
    require(!planner.update_partial_policy(499, true), "Invalid runtime interval was accepted");
}

std::vector<float> test_filter_bank() {
    std::vector<float> filters(MelFilterBank128::kValueCount, 0.0F);
    for (std::size_t mel = 0; mel < MelFilterBank128::kMelBins; ++mel) {
        filters[mel * MelFilterBank128::kFftBins + mel] = 1.0F;
    }
    return filters;
}

void test_log_mel_shape_silence_and_frequency_response() {
    LogMelExtractor extractor{MelFilterBank128(test_filter_bank())};
    const std::vector<std::int16_t> silence(4'800, 0);
    std::string error;
    require(extractor.compute_pcm16(silence.data(), silence.size(), &error), error);
    require(extractor.output().size() == LogMelExtractor::kOutputValues,
            "Log-Mel tensor shape is not 128 x 3000");
    for (const auto value : extractor.output()) {
        require(std::abs(value + 1.5F) < 1.0e-5F, "Whisper silence padding is not -1.5");
    }

    const auto tone = sine_wave(16'000, 1'000.0, 1.0, 12'000.0);
    require(extractor.compute_pcm16(tone.data(), tone.size(), &error), error);
    const auto & mel = extractor.output();
    const auto one_khz_bin = 25U;
    require(mel[one_khz_bin * LogMelExtractor::kMelFrames + 20] >
                mel[5U * LogMelExtractor::kMelFrames + 20] + 0.5F,
            "Log-Mel FFT does not preserve the expected 1 kHz energy peak");
}

void test_mel_filter_loader_rejects_wrong_size() {
    const std::string path = "galaxyssi-test-mel-filters.bin";
    {
        std::ofstream stream(path, std::ios::binary);
        const float value = 1.0F;
        stream.write(reinterpret_cast<const char *>(&value), sizeof(value));
    }
    MelFilterBank128 filters;
    std::string error;
    require(!MelFilterBank128::load(path, &filters, &error) && !error.empty(),
            "Mel filter loader accepted a truncated tensor");
    std::remove(path.c_str());
}

void test_transcript_stabilizer_is_utf8_safe() {
    TranscriptStabilizer stabilizer;
    const std::string first = u8"\u4eca\u5929\u4e0b\u5348\u6211\u4eec\u53bb";
    const std::string second = first + u8"\u673a\u573a";
    const std::string third = second + u8"\u63a5\u4eba\U0001f642";
    auto result = stabilizer.update(first);
    require(result.stable_text.empty(), "First hypothesis must remain provisional");
    result = stabilizer.update(second);
    require(result.stable_text == first && result.unstable_text == u8"\u673a\u573a",
            "Two-round Chinese prefix stabilization failed");
    result = stabilizer.update(third);
    require(result.stable_text == second && result.unstable_text == u8"\u63a5\u4eba\U0001f642",
            "UTF-8 tail stabilization failed");
    result = stabilizer.finalize();
    require(result.final && result.stable_text == third &&
                result.unstable_text.empty(),
            "Final transcript was not fully committed");
}

void test_audio_frontend_emits_snapshotable_windows() {
    std::vector<DecodeWindow> windows;
    AudioFrontendConfig config;
    AudioFrontend frontend(config, [&](const DecodeWindow & window) { windows.push_back(window); });
    const std::vector<std::int16_t> silence(160, 0);
    const auto speech = sine_wave(16'000, 400.0, 0.01, 8'000.0);
    for (int frame = 0; frame < 20; ++frame) require(frontend.push_pcm16(silence.data(), silence.size()), "Frontend silence push failed");
    for (int frame = 0; frame < 150; ++frame) require(frontend.push_pcm16(speech.data(), speech.size()), "Frontend speech push failed");
    for (int frame = 0; frame < 45; ++frame) require(frontend.push_pcm16(silence.data(), silence.size()), "Frontend trailing silence push failed");

    require(!windows.empty() && windows.back().final, "Frontend did not emit a final decode window");
    require(std::any_of(windows.begin(), windows.end(), [](const DecodeWindow & value) { return !value.final; }),
            "Frontend did not emit rolling partial windows");
    std::vector<std::int16_t> snapshot(static_cast<std::size_t>(windows.back().sample_count()));
    require(frontend.snapshot(windows.back(), snapshot.data(), snapshot.size()),
            "Frontend final window is not available in the native ring");
}

void test_streaming_session_queues_audio_and_finishes_no_speech() {
    AudioFrontendConfig config;
    StreamingFrontendSession session(config, MelFilterBank128(test_filter_bank()));
    require(session.start(), "Streaming frontend did not start");
    const std::vector<std::int16_t> silence(3'200, 0);
    require(session.push_pcm16(silence.data(), silence.size()), "Streaming frontend rejected PCM");
    session.pause();
    require(!session.push_pcm16(silence.data(), 160), "Paused frontend accepted PCM");
    require(session.resume(), "Streaming frontend did not resume");
    session.stop();

    std::vector<float> features(LogMelExtractor::kOutputValues);
    FeatureWindowMetadata metadata;
    std::string error;
    const auto result = session.wait_for_features(
        features.data(), features.size(), std::chrono::seconds(2), &metadata, &error);
    require(result == FeatureWaitResult::kReady, "Streaming frontend did not finalize: " + error);
    require(metadata.kind == FeatureWindowKind::kNoSpeechFinal,
            "Silence must produce an explicit no-speech final event");
    session.close();
}

void test_streaming_session_has_bounded_input_queue() {
    AudioFrontendConfig config;
    StreamingFrontendSession session(config, MelFilterBank128(test_filter_bank()));
    require(session.start(), "Streaming frontend did not start");
    const std::vector<std::int16_t> oversized(
        static_cast<std::size_t>(config.input_sample_rate_hz) *
            (StreamingFrontendSession::kInputQueueDurationSeconds + 1),
        0);
    require(!session.push_pcm16(oversized.data(), oversized.size()),
            "Streaming frontend accepted audio beyond its fixed queue capacity");
    session.cancel();
    session.close();
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"ring buffer wrap", test_ring_buffer_wraps_without_stale_reads},
        {"resampler quality", test_resampler_is_chunk_invariant_and_rejects_aliases},
        {"VAD boundaries", test_vad_applies_start_end_and_roll_boundaries},
        {"VAD short segment", test_vad_discards_short_segments},
        {"VAD maximum segment", test_vad_enforces_maximum_segment},
        {"rolling windows", test_rolling_window_emits_partials_and_final},
        {"adaptive rolling windows", test_rolling_window_updates_partial_policy_without_losing_final},
        {"Log-Mel", test_log_mel_shape_silence_and_frequency_response},
        {"mel filter validation", test_mel_filter_loader_rejects_wrong_size},
        {"UTF-8 transcript stabilization", test_transcript_stabilizer_is_utf8_safe},
        {"audio frontend", test_audio_frontend_emits_snapshotable_windows},
        {"streaming no-speech final", test_streaming_session_queues_audio_and_finishes_no_speech},
        {"streaming bounded queue", test_streaming_session_has_bounded_input_queue},
    };

    int failures = 0;
    for (const auto & test : tests) {
        try {
            test.second();
            std::cout << "PASS: " << test.first << '\n';
        } catch (const std::exception & error) {
            ++failures;
            std::cerr << "FAIL: " << test.first << ": " << error.what() << '\n';
        }
    }
    std::cout << tests.size() - static_cast<std::size_t>(failures) << '/' << tests.size()
              << " native ASR tests passed\n";
    return failures == 0 ? 0 : 1;
}
