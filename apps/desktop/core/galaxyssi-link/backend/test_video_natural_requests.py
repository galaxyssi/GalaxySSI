import pytest

from agent_execution_harness import AgentTaskKind, execution_contract, execution_policy_for
from video_generation_policy import VIDEO_VOICE_CONTRACT, VIDEO_PLANNING_CONTRACT, video_creation_requested
from video_quality import NARRATION_RENDER_CONTRACT


@pytest.mark.parametrize("text", [
    "\u89c6\u9891\u4ecb\u7ecdRAG\u539f\u7406",
    "\u8bf7\u7528\u89c6\u9891\u4ecb\u7ecdRAG\u539f\u7406",
    "\u7528\u52a8\u753b\u8bb2\u89e3\u82af\u7247\u5de5\u4f5c\u539f\u7406",
    "\u5e2e\u6211\u7528\u4e00\u6bb5\u89c6\u9891\u89e3\u91ca\u4e8c\u8fdb\u5236",
    "\u4ee5\u52a8\u753b\u7684\u5f62\u5f0f\u6765\u6f14\u793a\u6392\u5e8f",
    "\u901a\u8fc7\u89c6\u9891\u5c55\u793aCPU\u6267\u884c\u6307\u4ee4",
    "\u89c6\u9891\u4ecb\u7ecdRAG\uff0c\u4e0d\u8981\u914d\u97f3",
    "\u7ed9\u6211\u4e00\u4e2aRAG\u539f\u7406\u8bb2\u89e3\u89c6\u9891",
    "\u6765\u4e00\u6bb5\u82af\u7247\u5de5\u4f5c\u52a8\u753b",
    "\u6211\u60f3\u8981\u4e00\u4e2a\u4ea7\u54c1\u5c55\u793a\u77ed\u7247",
    "Explain RAG in a video",
    "Please explain binary addition using an animation.",
    "Introduce retrieval augmented generation as an animated video",
    "Demonstrate sorting with a video",
])
def test_natural_video_requests_select_host_pipeline(text):
    assert video_creation_requested(text)
    policy = execution_policy_for(text)
    assert policy.task_kind == AgentTaskKind.ARTIFACT
    assert policy.requires_artifact


@pytest.mark.parametrize("text", [
    "\u4ecb\u7ecd\u8fd9\u4e2a\u89c6\u9891\u7684\u5185\u5bb9",
    "\u8fd9\u4e2a\u89c6\u9891\u4ecb\u7ecd\u4e86RAG\u539f\u7406",
    "\u4e0d\u8981\u7528\u89c6\u9891\u4ecb\u7ecdRAG",
    "\u8bf7\u522b\u7528\u52a8\u753b\u8bb2\u89e3",
    "\u7528\u89c6\u9891\u4ecb\u7ecdRAG\u53ef\u4ee5\u5417\uff1f",
    "\u89c6\u9891\u4ecb\u7ecd\u662f\u4ec0\u4e48",
    "\u89c6\u9891\u4ecb\u7ecdRAG\u7684\u811a\u672c",
    "\u53ea\u5199\u5206\u955c\uff0c\u7528\u89c6\u9891\u4ecb\u7ecdRAG",
    "\u5982\u4f55\u7528\u89c6\u9891\u4ecb\u7ecdRAG",
    "Explain this video",
    "How do I explain RAG in a video?",
    "Don't explain RAG using a video",
    "Only write a script to explain RAG in a video",
    "Explain what happened in an existing video",
    'The example says "Explain RAG in a video"',
])
def test_existing_videos_questions_and_text_only_requests_are_not_rendered(text):
    assert not video_creation_requested(text)


def test_fallback_and_planner_share_video_voice_policy():
    # A missed media intent still reaches the ordinary execution contract.
    assert VIDEO_VOICE_CONTRACT in execution_contract(execution_policy_for("Explain RAG"))
    assert VIDEO_VOICE_CONTRACT in VIDEO_PLANNING_CONTRACT
    assert "zh-CN-XiaoxiaoNeural" in NARRATION_RENDER_CONTRACT
    assert "Check installed Windows" not in NARRATION_RENDER_CONTRACT
