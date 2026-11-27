# Model-Authored Final Editor (Android #4651)

Baseline: Android PR #4651, merge `972c34624411ba48f410ce849bcf2356c253653c`.
This increment adds the model-authored review assignment, not the later bounded
writer handback/recheck policy.

An explicit independent-final-review objective selects one structured planning
prompt on every model route. In that single plan the model supplies contributors,
synthesis instructions and a separate nonblank `final_review` brief. The host
does not invent that assignment. It validates and represents the brief as one
independent terminal reviewer, consuming one of the ten existing role slots.

At most nine contributors may accompany a dedicated brief. Plain strings are
independent WORK assignments only in this explicit-review mode with a final
brief. Typed WORK/REVIEW/CRITIC contributors preserve their own earlier numeric
dependencies. The dedicated reviewer receives the actual synthesized draft,
original objective and attributable public objections, with no contributor listed
as its implicit parent. It can revise or withhold under the existing audit parser.

The canonical loopback wire recognizes the exact new prompt. Strict opt-in schema
describes the three fields and string/typed contributor alternatives; ordinary
local servers still have no schema assumption. Remote and GGUF paths use the same
new explicit-review prompt and host decoder, without changing provider selection.

Valid older numbered final-review plans remain accepted in soft mode. Missing,
null or blank final briefs cannot grant string assignments or manufacture a
reviewer; named legacy pre-synthesis review does not become final approval.
Without an explicit final-review objective, ordinary planning remains unchanged.
All plans retain duplicate/type/graph/control-character preflight and the same
10-role, three-parallel, 12-call limits. Missing-review errors retain their
specific receipt through the request boundary.

Eight synthetic XCTest methods are authored for model brief fidelity, independent
allocation, typed contributor graphs, missing/invalid review, slot limits, legacy
compatibility, schema selection, actual findings-to-writer and draft-to-editor
handoffs, and the 12-call ceiling. They are not executed. Focused JS source
contracts and iOS structure checks are used, not Swift/native builds, live models,
simulator/device or scientific acceptance, full checks, CI monitoring or IPA
generation. A validated plan is not a completed task or experimental evidence.
