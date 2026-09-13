# GalaxySSI Watch UI proposal

Status: design only. No watch application, device discovery, pairing, or network
integration has been implemented or tested by this proposal.

## Platform and product scope

- Wear OS devices running Android 13 or later; proposed minimum SDK: 33.
- Start with small round displays, then adapt to larger displays and font scales.
- Use a black screen, GalaxySSI green (#14C66A), rounded controls, and short text.
- Provide at least 48 dp touch targets in the native implementation. The preview
  illustrates navigation and visual hierarchy, not an exact device density.
- Support vertical scrolling, rotary input where available, and system back.
- Preserve safe insets around circular edges and show a native scroll indicator.

## Primary flows

1. Home: connected default device, prominent voice action, recent conversations,
   device connections, and secondary settings access.
2. Voice: display recipient before recording; show listening state, stop and
   cancel actions; review the transcript before sending. Offer system text input
   as an alternative in the native app. Microphone denial must have an actionable
   explanation and settings route.
3. Conversations: recent items first, recipient and unread/running state; concise
   replies, on-demand speech, and voice follow-up. Long replies scroll. Large
   attachments show a summary and a supported handoff action rather than editors.
4. Tasks: show remote execution state, brief progress, completion notification,
   summary, and a confirmed stop request. Distinguish a stop request from a
   remotely acknowledged stop. Do not fabricate percentage progress.
5. Connections: distinguish discovered, unpaired, connecting, paired/available,
   and offline devices. Same Wi-Fi does not establish trust or prove connectivity.
   Pairing uses the existing trust protocol with a watch-friendly enrollment flow;
   a short code in the preview is a proposed UX, not an existing protocol claim.
6. Offline/error: preserve an unsent draft, show delivery state, retry, and switch
   device. Retry must reuse message identity to avoid duplicate execution.
7. Settings: default device, vibration, optional reply speech, pairing, and about.

The interactive preview uses sample messages and simulated transitions. A real
build must derive recipients, task identities, summaries, and all status changes
from the shared conversation model. Phone handoff and local discovery require
capability negotiation or companion work before those actions can be enabled.

## Android reuse boundary

Reuse or extract compatible messaging models, IDs, encryption/trust, link protocol,
delivery state, and conversation persistence. Candidate sources include
`GalaxySSICrypto.kt`, `GalaxySSILinkProtocol.kt`, `GalaxySSIMqttClient.kt`,
`PeerChatTransport.kt`, and the voice state/coordinator classes. These are candidates
for dependency review, not confirmed drop-in watch modules.

The phone currently uses Android Views and MainActivity extension functions; build
a dedicated Wear OS presentation layer rather than copying phone layouts. Extract
business interfaces before deciding which classes can be shared unchanged.

Exclude Linux environments, terminals, local repository/build tools, local LLMs,
llama/QNN/GenieX, model downloads, local heavy ASR/wake-word engines, camera/OCR,
remote desktop video/control, and full file/PDF editors from the watch build.
Remove their build dependencies and permissions, not just their menu entries.
Keep the phone application's capabilities intact.

Prefer deliberate short voice capture with compatible system or remote speech
services. Run heavy work on a trusted phone/desktop or configured remote provider.
Do not assume MQTT routing is local merely because both devices share Wi-Fi.

## Implementation acceptance criteria

- Validate round screen clipping, large text, 48 dp targets, rotary scroll, and back.
- Exercise microphone permission denial, interrupted recording, lost connectivity,
  failed pairing, duplicate retry prevention, and remote stop acknowledgement.
- Default to no always-listening microphone, automatic speech, or always-on screen.
- Add a one-action voice Tile and concise task notification after core flows work.

## References

- https://developer.android.com/design/ui/wear/guides/get-started/design-for-wearables
- https://developer.android.com/docs/quality-guidelines/wear-app-quality
