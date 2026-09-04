#include "transcript_stabilizer.h"

#include <algorithm>

namespace galaxyssi::asr {

StabilizedTranscript TranscriptStabilizer::update(const std::string & hypothesis) {
    current_ = utf8_codepoints(hypothesis);
    if (previous_.empty()) {
        previous_ = current_;
        return {"", join(current_, 0, current_.size()), join(current_, 0, current_.size()), false};
    }

    // A stable prefix is only promoted after it appears in two consecutive
    // decoding rounds. If Whisper revises an already stable suffix, retract to
    // the last valid UTF-8 codepoint rather than emitting malformed text.
    const auto current_stable_prefix = common_prefix_count(stable_, current_);
    if (current_stable_prefix < stable_.size()) {
        stable_.resize(current_stable_prefix);
    }
    const auto two_round_prefix = common_prefix_count(previous_, current_);
    if (two_round_prefix > stable_.size()) {
        stable_.assign(current_.begin(), current_.begin() + static_cast<std::ptrdiff_t>(two_round_prefix));
    }

    previous_ = current_;
    return {
        join(stable_, 0, stable_.size()),
        join(current_, stable_.size(), current_.size()),
        join(current_, 0, current_.size()),
        false,
    };
}

StabilizedTranscript TranscriptStabilizer::finalize(const std::string & hypothesis) {
    if (!hypothesis.empty()) {
        current_ = utf8_codepoints(hypothesis);
    }
    stable_ = current_;
    const auto text = join(current_, 0, current_.size());
    return {text, "", text, true};
}

void TranscriptStabilizer::reset() noexcept {
    previous_.clear();
    stable_.clear();
    current_.clear();
}

std::vector<std::string> TranscriptStabilizer::utf8_codepoints(const std::string & text) {
    std::vector<std::string> result;
    result.reserve(text.size());
    std::size_t offset = 0;
    while (offset < text.size()) {
        const auto lead = static_cast<unsigned char>(text[offset]);
        std::size_t length = 1;
        if ((lead & 0xE0U) == 0xC0U) {
            length = 2;
        } else if ((lead & 0xF0U) == 0xE0U) {
            length = 3;
        } else if ((lead & 0xF8U) == 0xF0U) {
            length = 4;
        }

        if (offset + length > text.size()) {
            length = 1;
        } else {
            for (std::size_t continuation = 1; continuation < length; ++continuation) {
                const auto value = static_cast<unsigned char>(text[offset + continuation]);
                if ((value & 0xC0U) != 0x80U) {
                    length = 1;
                    break;
                }
            }
        }
        result.emplace_back(text.substr(offset, length));
        offset += length;
    }
    return result;
}

std::size_t TranscriptStabilizer::common_prefix_count(const std::vector<std::string> & left,
                                                      const std::vector<std::string> & right) noexcept {
    const auto maximum = std::min(left.size(), right.size());
    std::size_t count = 0;
    while (count < maximum && left[count] == right[count]) {
        ++count;
    }
    return count;
}

std::string TranscriptStabilizer::join(const std::vector<std::string> & codepoints,
                                       const std::size_t first,
                                       const std::size_t last) {
    std::string result;
    for (std::size_t index = first; index < std::min(last, codepoints.size()); ++index) {
        result += codepoints[index];
    }
    return result;
}

}  // namespace galaxyssi::asr
