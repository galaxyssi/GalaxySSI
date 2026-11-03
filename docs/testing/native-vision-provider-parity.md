# Native vision across providers

This extends the orientation-evidence work in PR #3626. It does not change
provider selection, MQTT attachment compression, or the phone execution boundary.

## Input contract

- Preserve source bytes, image order, current-task scope, and the requested model.
- For one still image, optionally add the existing bounded four-orientation sheet.
  It is labeled as views of the same source, not additional user photos. Multiple
  images and animated inputs do not receive a sheet.
- Inspect native pixels and reading direction before transcribing connected
  handwriting, equations, tables, or diagrams. Express uncertainty rather than
  inventing missing symbols or product identities. No OCR substitution is added.
- An image-only request should be inspected before asking what to do. Non-image
  files with no discernible task can still receive a clarification question.
- A missing, corrupt, or unsupported image is an input error, not an invitation
  to answer from its filename. Original task images survive recovery and context
  overflow retries. Text-only requests do not create an image workspace.

## Transports

| Route | Image contract |
| --- | --- |
| Android OpenAI-compatible, including DeepSeek | `image_url` blocks; existing per-request vision-model selection retained |
| Android Anthropic | Base64 image source blocks |
| Android Gemini | Inline image data parts |
| Desktop OpenAI-compatible cloud/local API | Native image URL blocks on the current user turn, retained through tool rounds |
| Desktop Ollama fallback | `/api/chat` with native `images`, never a stringified image block in `/api/generate` |
| Desktop ACP | Inline image blocks only when the agent advertises image capability |
| Claude CLI | Stream-JSON user message with native image blocks; parse only the final result |
| Hermes CLI | Leading image attachment plus `--image`; preserve query and model options |
| Gemini CLI | Workspace-local `@file` image references |
| Codex CLI fallback | Repeated `--image` arguments; the existing app-server path remains unchanged |
| Unknown/custom or persistent text-only JSONL transport | Explicit unsupported-image error; use an image-capable ACP adapter |

ACP capability rejection occurs before submitting a prompt, so a known native
CLI fallback is safe. After submission, execution errors must not trigger a
second untracked invocation. Temporary CLI evidence is removed on success and
failure. Model, permission, session, and execution-location options are preserved.

The current Hermes single-query CLI accepts two image inputs. One source plus its
reference sheet fits; more than two source images require an image-capable ACP
adapter. The selected underlying model must also support vision. Transport
support alone is not a guarantee of recognition accuracy or provider availability.

## Android prompt handling

Streaming and non-streaming cloud vision use the same compact visual policy.
Explicit Agent Loop contracts and language preferences are preserved; generic
research instructions are not appended to image requests. Web and annotation
tools remain available when the model needs them. Text-only evidence policy is
unchanged. Long custom contracts are not re-truncated to the default 4,000-character
limit during non-streaming vision fallback.

## Regression commands

From `apps/desktop/core/galaxyssi-link/backend`:

```text
python -m unittest test_agent_vision test_agent_vision_gateway test_vision_orientation test_agent_cli_execution test_desktop_agent_adapters test_cloud_web_tool_routing test_acp_runtime test_response_policy test_task_workspace test_agent_context_compaction test_agent_invocation_profiles
```

Android targeted tests include `CloudVisionPromptPolicyTest`,
`AgentDirectVisionPolicyTest`, `AgentVisionInitialPromptTest`, and
`CodexStyleResponsePolicyTest`. `NativeVisionRequestDeviceTest` checks native
payloads for all three API styles and the non-streaming fallback, including long
custom execution contracts. `NativeVisionLiveDeviceTest` is explicitly opt-in and
uses only an authorized image with an already configured DeepSeek contact.

Do not report simulated provider transports as live model recognition tests.
Claude and Gemini CLIs are not installed on this validation host. The live Hermes
probe with the authorized sideways handwriting photo timed out after 90 seconds;
semantic acceptance for that provider remains unverified.

## Validation on 2026-10-25

- Desktop backend: 127 targeted tests passed, including actual subprocess
  transport fixtures for ACP and Claude stream-JSON.
- Desktop frontend/packaging checks: 95 tests and the structure check passed.
  The first concurrent run hit the existing 30-second structure-gate timeout;
  the isolated gate and then the complete command passed without changing it.
- Android: debug APK and instrumentation APK built successfully; 24 targeted
  JVM tests passed. Version: `0.1.6.14` / `1390`.
- Desktop version: `0.1.6.2`.
- S26U disconnected from ADB before the live DeepSeek/device probe. The updated
  device tests are compiled but have not run on the phone in this change.
- No user photo, credentials, or private conversation content is committed.
