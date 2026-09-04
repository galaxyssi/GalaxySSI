#pragma once

#include <string>
#include <vector>

namespace galaxyssi::asr {

struct StabilizedTranscript {
    std::string stable_text;
    std::string unstable_text;
    std::string full_text;
    bool final = false;
};

class TranscriptStabilizer final {
public:
    StabilizedTranscript update(const std::string & hypothesis);
    StabilizedTranscript finalize(const std::string & hypothesis = {});
    void reset() noexcept;

private:
    static std::vector<std::string> utf8_codepoints(const std::string & text);
    static std::size_t common_prefix_count(const std::vector<std::string> & left,
                                           const std::vector<std::string> & right) noexcept;
    static std::string join(const std::vector<std::string> & codepoints,
                            std::size_t first,
                            std::size_t last);

    std::vector<std::string> previous_;
    std::vector<std::string> stable_;
    std::vector<std::string> current_;
};

}  // namespace galaxyssi::asr
