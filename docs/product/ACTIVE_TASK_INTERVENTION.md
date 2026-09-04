# Active Task Intervention

GalaxySSI treats a message sent while an Agent task is running as one of three
operations:

| Disposition | Meaning | Runtime behavior |
| --- | --- | --- |
| `independent` | The user started unrelated work | Start an isolated Run |
| `steer` | The user changed the goal or added a constraint | Update the active Run when the provider supports live steering |
| `interrupt` | The user explicitly stopped the active task | Cancel the provider Run and invalidate pending approvals |

Independent work is the default. GalaxySSI only intervenes when the message is
an explicit correction, continuation, goal change, reference to the active
work, or standalone stop command. A new attachment is independent unless its
text explicitly refers to the active task.

## Provider behavior

- Codex uses the App Server `turn/steer` operation and keeps the same provider
  Thread and Turn.
- Providers without live steering cancel the old Run, preserve its original
  request, append the latest instruction with higher priority, and start a
  replacement Run.
- Phone-native tasks, cloud API tasks, and local-model tasks use the same
  replacement behavior.
- An explicit interrupt never becomes a model prompt.

Every intervention keeps the client route, conversation, task, and turn
identity boundaries. Durable task records expose:

- `task_disposition`
- `intervention_kind`
- `merged_into_task_id` for native steering and interrupts
- `supersedes_task_id` for replacement Runs

Changing or interrupting a task clears its pending approval. A result returned
after cancellation cannot publish a second final response because the old task
is already terminal.

## User-visible behavior

The original user message remains in the conversation. GalaxySSI does not add
boilerplate such as "requirement appended." The Run Timeline records the
intervention, while the final responder remains the active or replacement
Agent. A standalone stop command ends the old timeline without launching a new
model request.
