# App-selected paired Desktop collaboration pilot

`AgentRemotePilotProtocolTests.testOptInAppSelectedRemotePilot` is a Debug,
physical-device XCTest. It uses the running App's paired Desktop Codex contact
and legacy MQTT connection. It does not add a provider or change the active
conversation, global defaults, or model picker. Select a specific model and
reasoning effort for that contact in an existing conversation before running it.

Use the frozen Android `galaxyssi.remote-collaboration-pilot.v1` JSON format.
Keep prompts, results and reference answers outside Git. In the hosted test
environment, set:

| Variable | Value |
| --- | --- |
| `GALAXYSSI_REMOTE_PILOT_RUN` | `1` after obtaining fresh authorization |
| `GALAXYSSI_REMOTE_PILOT_DEVICE_MODEL` | Authorized iPhone hardware identifier |
| `GALAXYSSI_REMOTE_PILOT_TOOLS` | `production_tools_not_isolated` |
| `GALAXYSSI_REMOTE_PILOT_PLAN` | Absolute path to the JSON readable by the App |
| `GALAXYSSI_REMOTE_PILOT_SHA256` | Lowercase SHA-256 of the original bytes |
| `GALAXYSSI_REMOTE_PILOT_SELECTION_CONVERSATION` | Conversation containing the saved selection |
| `GALAXYSSI_REMOTE_PILOT_MAX_DISPATCHES` | Independently authorized phone-side dispatch cap |

Each slot reserves three sequential sends: draft, review and revision. Each pair
uses identical source material, model, effort and assignments. Only the review
identity differs. The phone-side cap is not a provider request, tool, token or
cost cap. Production tools and Desktop/provider context are not isolated. The
report does not assert actually served model, billing, or equal-cost evidence.

Results are written under App Support at
`XCTest-AppSelectedRemotePilot/<pilot_id>/`. Keep the original report and
do not reuse a reserved pilot ID. The fixture journals exact identities and
prepared prompt digests before sending, and archives successful final text and
its digest before removing the fixture conversation. If authenticated remote
owners cannot be confirmed terminal, the fixture retains its scope and blocks
subsequent slots. A stop record is evidence of intent, not remote completion:
after an interruption inspect the retained owners before another live pilot.
This does not erase Desktop or provider-side records.

Run the other methods of `AgentRemotePilotProtocolTests` for local protocol and
synthetic scheduler coverage. They do not dispatch remote work.
