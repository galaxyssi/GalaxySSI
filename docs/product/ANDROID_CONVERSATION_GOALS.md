# Android conversation goals

In a regular Agent chat, send an objective such as
`/goal Draft a four-week beginner photography course with an exercise for each week`.
Choose and confirm a model. The app schedules the work on Android; the chat does not have to stay on screen.
Android may defer work, for example while the device is idle or a cloud model is waiting for connectivity.

| Chat command | Effect |
| --- | --- |
| `/goal` or `/goal status` | Inspect the current goal, last checkpoint and outstanding step. |
| `/goal pause` | Stop advancing. Late results from the old run are discarded. |
| `/goal resume [clarification]` | Authorize another six rounds on the same model, using saved work. |
| `/goal stop` | End this goal without erasing its conversation entries. A new goal can then be created. |

One goal can run per conversation. Each authorization permits at most six model calls at the goal-round level,
including a final review before a draft is marked complete. The review checks the deliverable against the
objective; it is not independent factual verification. Results appear in the originating chat.
If a model is unavailable, a response is unusable, or a request was interrupted with an unknown outcome,
the goal stops advancing until the user resumes it. It does not silently switch models or replay an uncertain request.

Goals support text work on a background-capable on-device model or a configured direct cloud API.
The model receives the explicit objective, goal checkpoints, and optional clarification, not the rest of the chat.
It has no tools for browsing, device actions, files, health records or contact messaging.
Paired Desktop agents, group chats, private sessions and scoped Health Assistant conversations are not execution targets.
Goal state is encrypted on the phone; deleting the conversation removes that state. This feature does not enable world-model learning.
