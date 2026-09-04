# Task Intent Classification

GalaxySSI classifies every request into one canonical intent before planning.
Intent describes the user's goal; it is separate from execution complexity,
risk, provider selection, and the Agent loop phase.

## Canonical intents

| Protocol value | Meaning |
| --- | --- |
| `chat` | General conversation or a request with no stronger execution signal |
| `code` | Source code, builds, tests, repositories, or software delivery |
| `phone_control` | Actions and state on the current mobile device |
| `desktop_control` | Actions and state on a paired Desktop |
| `research` | Current information, web search, evidence gathering, or comparison |
| `file` | Reading, transforming, extracting, or producing file content |
| `memory` | Personal memory, preferences, knowledge, recall, or forgetting |
| `automation` | Scheduled, recurring, event-triggered, or monitored work |

Android and Desktop use the same stable protocol values. The classifier is a
fast local first pass so routing does not require a network call. The selected
Agent or model may refine the plan, but it must preserve the intent in the
durable execution snapshot and task policy.

## Classification behavior

- Explicit intent signals outrank generic chat.
- Attachments make `file` the baseline, while an explicit request such as
  building code can still win.
- Recurrence and trigger language outranks an individual device action. For
  example, turning on a light once is control; doing it every day is automation.
- Unknown requests remain `chat`; the classifier does not invent a goal.
- Confidence and matched signals are diagnostic evidence, not authorization.

Risk assessment, confirmation, routing, budgets, and permissions remain
independent decisions after classification.
