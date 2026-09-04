# Task Clarification Policy

GalaxySSI asks a question only when execution is missing a required subject,
target, outcome, or automation definition. Model confidence alone never triggers
clarification.

## Decisions

- `execute`: continue directly through the Agent execution loop.
- `ask_locally`: return one short, typed question without starting an Agent.
- `ask_with_model`: let the selected model phrase one attachment-aware question
  without inspecting or returning the attached content.

## Context Rules

- Clear chat, questions, and low-risk device actions execute immediately.
- Referential follow-ups such as `continue`, `try again`, and `use this` reuse
  the active conversation context.
- A vague request in a new conversation asks one question.
- A vague request with usable conversation context continues from that context.
- An attachment without an actionable request remains model-authored so the
  question can reflect the file type while avoiding premature inspection.
- Risk approval remains separate. A clear high-risk action is planned first and
  then enters the existing approval policy.

Android and Desktop share the same decision modes, question types, English and
Simplified Chinese vectors, and execution semantics.
