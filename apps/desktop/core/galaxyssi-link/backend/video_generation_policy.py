"""One programmatic video route, independent of AI/provider wording."""
import re

_CREATE = re.compile(r"\b(generate|create|make|render|produce)\b|\u751f\u6210|\u5236\u4f5c|\u505a", re.I)
_VIDEO = re.compile(r"\b(videos?|films?|clips?|animation|commercial)\b|\u89c6\u9891|\u8996\u983b|\u5f71\u7247|\u77ed\u7247|\u52a8\u753b|\u5e7f\u544a\u7247", re.I)
_DISCUSS = re.compile(r"\b(explain|compare|difference|how|whether|develop|implement)\b|\u533a\u522b|\u4ec0\u4e48\u662f|\u5982\u4f55|\u600e\u4e48|\u600e\u6837|\u5206\u6790|\u4ecb\u7ecd|\u539f\u7406|\u80fd\u4e0d\u80fd|\u53ef\u4e0d\u53ef\u4ee5|\u5f00\u53d1|\u96c6\u6210", re.I)
_NEGATE = re.compile(r"\b(don't|do not|never|without|not)\b|\u4e0d\u8981|\u4e0d\u7528|\u522b|\u65e0\u9700|\u4e0d\u9700|\u6682\u4e0d", re.I)
_TEXT_ONLY = re.compile(
    r"(?:\u53ea|\u5148)(?:\u8981|\u9700\u8981|\u5199|\u7ed9|\u505a|\u8bbe\u8ba1).{0,12}(?:\u5206\u955c|\u63d0\u793a\u8bcd|\u811a\u672c|\u65b9\u6848)|"
    r"\b(?:only|just)\b.{0,25}\b(?:storyboard|prompt|script|plan)\b|"
    r"(?:\u4e0d\u8981|\u522b|\u6682\u4e0d|\u4e0d\u9700\u8981)(?:\u771f\u6b63|\u5b9e\u9645)?(?:\u751f\u6210|\u6e32\u67d3)|"
    r"\b(?:do not|don't|without)\s+(?:actually\s+)?(?:generate|render)", re.I)

# Match requested output modality, not discussion of an existing video.
_VIDEO_EXPLAINER = re.compile(
    r"^\s*(?:\u8bf7|\u5e2e\u6211|\u7ed9\u6211)?\s*(?:\u7528|\u901a\u8fc7|\u4ee5)?"
    r"(?:\u4e00\u4e2a|\u4e00\u6bb5)?(?:\u89c6\u9891|\u52a8\u753b|\u77ed\u7247)"
    r"(?:\u7684)?(?:\u65b9\u5f0f|\u5f62\u5f0f)?(?:\u6765)?"
    r"(?:\u4ecb\u7ecd|\u8bb2\u89e3|\u89e3\u91ca|\u6f14\u793a|\u5c55\u793a|\u8bf4\u660e)|"
    r"^\s*(?:please\s+)?(?:explain|introduce|demonstrate|show)\b.+"
    r"\b(?:with|using|through|as|in)\s+(?:an?\s+)?(?:video|animation|animated\s+video)\b|"
    r"^\s*(?:\u8bf7)?(?:\u7ed9\u6211|\u6765|\u6211\u8981|\u6211\u60f3\u8981)"
    r"(?:\u4e00)?(?:\u4e2a|\u6bb5).{0,100}(?:\u89c6\u9891|\u52a8\u753b|\u77ed\u7247)\s*$",
    re.I)
_EXPLAINER_DISCUSSION = re.compile(
    r"\u662f\u4ec0\u4e48|\u4ec0\u4e48\u610f\u601d|\u600e\u4e48|\u5982\u4f55|"
    r"\u662f\u5426|\u80fd\u4e0d\u80fd|\u53ef\u4e0d\u53ef\u4ee5|"
    r"\u811a\u672c|\u5206\u955c|\u63d0\u793a\u8bcd|\u5c01\u9762|\u7f29\u7565\u56fe|"
    r"[\u5417\u4e48?\uff1f]\s*$|\b(?:script|storyboard|prompt|thumbnail|existing|attached)\b",
    re.I)

VIDEO_NARRATION_VOICE = "zh-CN-XiaoxiaoNeural"
VIDEO_VOICE_CONTRACT = (
    "For any video narration, including Chinese, English and mixed-language videos, use only "
    "Microsoft Edge TTS zh-CN-XiaoxiaoNeural. Preserve the requested spoken language; do not translate "
    "English into Chinese just to select the voice. Never substitute Yunxi, Aria, Windows System.Speech "
    "or another voice. If Xiaoxiao is unavailable, report failure instead of silently changing voice. "
    "Reuse host-prepared narration clips whenever provided."
)


def video_creation_requested(prompt: str) -> bool:
    text = re.sub(r'```[\s\S]*?```|`[^`\n]*`|\u201c[^\u201d]*\u201d|"[^"\n]*"', "", str(prompt or ""))
    if (_TEXT_ONLY.search(text)
            or re.search(r"^\s*(?:can|could|does|is)\b|(?:\u80fd|\u53ef\u4ee5).{0,40}(?:\u751f\u6210|\u5236\u4f5c).*?[\u5417\u4e48?\uff1f]", text, re.I)
            or re.search(r"^\s*(?:I|we)\s+(?:made|created|generated)|\u6211(?:\u4e4b\u524d|\u6628\u5929|\u5df2\u7ecf).{0,10}(?:\u751f\u6210|\u5236\u4f5c)", text, re.I)):
        return False
    for clause in re.split(r"[\n.!?;\u3002\uff01\uff1f\uff1b]|\bbut\b|\u4f46\u662f", text, flags=re.I):
        if _VIDEO_EXPLAINER.search(clause) and not _EXPLAINER_DISCUSSION.search(text):
            return True
        action, video = _CREATE.search(clause), _VIDEO.search(clause)
        if not action or not video:
            continue
        discussion, negation = _DISCUSS.search(clause), _NEGATE.search(clause)
        if discussion and discussion.start() < action.start():
            continue
        if negation and negation.start() < max(action.end(), video.end()):
            continue
        if re.search(r"(?:\u89c6\u9891|\u52a8\u753b)(?:\u7684)?(?:\u63d0\u793a\u8bcd|\u5206\u955c|\u811a\u672c|\u7f29\u7565\u56fe|\u5c01\u9762)|"
                     r"\b(?:video|animation)\s+(?:prompt|storyboard|script|thumbnail|cover)\b|"
                     r"\u751f\u6210\u89c6\u9891\u7684\u539f\u7406|\u600e\u4e48\u505a|\u600e\u6837\u505a", clause, re.I):
            continue
        return True
    return False


VIDEO_PLANNING_CONTRACT = """Plan a programmatically rendered video, not a native video-model job.
Use Python/Pillow/NumPy or existing local animation tools plus FFmpeg, as in a coding-agent video workflow.
All subjects use this same route, regardless of the words AI, LTX or other provider names.
Never call cloud video services, download model weights, or claim photorealistic native generation.
For realistic people/actions, propose a clearly labelled stylized animation; if that cannot meet an
explicit mandatory requirement, return needs_clarification instead of misrepresenting the result.
Return ONLY JSON: {summary, duration_seconds, audio_mode, scenes:[{start,end,description,narration}]}.
duration_seconds: integer 2..120, default 32. Honor an explicit requested duration; do not shorten silently.
scenes: 1..16 contiguous scenes covering the whole duration. summary: <=500 characters.
audio_mode: none, narration, music, or unspecified. Explicit spoken voiceover/Chinese speech requires
narration; do not silently replace it with silence or music. For narration, supply concise verbatim
speech for EVERY scene in its narration field (<=400 characters each), short enough to fit its slot
at an intelligible pace with small leading/trailing pauses. Otherwise omit narration.
For binary numbers, write spoken digits individually (Chinese: \u4e00\u96f6; English: one zero for 10),
not a decimal reading such as ten. Spell mathematical symbols out for the TTS voice.
Use the user's language. For science, distinguish simplified illustrations from factual claims and
identify checks needed. Desktop prepares narration through its existing Microsoft Edge TTS service:
Use narration by default for explanatory/educational videos, unless silence or music-only was requested.
Do not discover or launch TTS yourself; provide the spoken text.
The host measures and supplies clips before rendering.
If the request is unsupported, return {needs_clarification: reason}. Do not create files at this stage.
""" + "\n" + VIDEO_VOICE_CONTRACT
