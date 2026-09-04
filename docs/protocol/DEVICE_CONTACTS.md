# Device Contacts and Opaque Relationships

GalaxySSI represents a paired phone or Desktop as a device contact. A device
contact is separate from the Agent contacts advertised by a Desktop.

## Identity and Local State

- Installation identity: long-lived Signal identity-key fingerprint.
- Device metadata: local model, host, profile, and user-facing display name.
- Relationship secret: independently derived for exactly two identities.
- Local route record ID: random 128-bit identifier used only in local storage.
- Conversation, turn, task, and transfer IDs: encrypted application identifiers.

Display names and hardware metadata never authorize access. Trust is bound to the
verified cryptographic identity and relationship secret.

## Many-to-Many Topology

One Desktop may pair with many phones, one phone may pair with many Desktops, and
one phone may pair directly with many phones. Every pair has a separate secret
and separate rotating directional mailboxes. Public MQTT traffic does not expose
whether either endpoint is a phone, Desktop, app, server, client, or Agent.

Revoking one relationship cannot revoke, rename, or rotate another relationship.

## User Interface

- Desktop Mobile Gateway owns QR creation, paired-device names, access grants,
  recent activity, and revocation.
- Android Contacts owns Desktop and phone device contacts, New Friends approval,
  rename, trust details, and removal.
- Desktop child Agents remain independent contacts. Selecting an Agent sends an
  encrypted application message through its parent Desktop relationship.
- Direct cloud providers remain mobile resources and require no device contact.

## Phone Friend Flow

1. A phone displays a signed, ten-minute, one-time QR offer.
2. Another phone scans it and creates a pending New Friends entry.
3. Both peers derive the relationship without exchanging the derived secret.
4. The QR owner receives a pending request and the QR session binds to that identity.
5. Ordinary communication remains disabled until the request is approved.
6. Removing the contact destroys the active relationship. A new scan is required.

## Rotation and Hard Cut

Mailbox topics rotate every six hours while identity trust remains stable.
Re-pairing creates fresh relationship material. Unsupported protocol registries
are discarded; no old topic, route, contact transport field, or pairing record is
migrated into the v2 relationship store.
