# Unpairing and local history

On Android and Desktop 0.19.5 or later, the existing authenticated unpair messages revoke transport, trust and remote control without deleting local chat history. Local history deletion is a separate user action and is not sent over the wire. A peer running older software applies its own deletion behavior, so update both endpoints before unpairing to retain both copies.

On Android, disconnected contacts are excluded from routing. An archived contact is restored only after pairing with its recorded full fingerprint. Desktop retains an encrypted local mapping of retired routes to an identity derived from both endpoints' full fingerprints. The local renderer may display those routes with a newly paired chat, but only the active route can send messages. Display names do not establish identity.
