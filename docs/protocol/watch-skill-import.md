# Watch Skill import over Wi-Fi setup

Skill transfer uses the existing foreground Wi-Fi TLS setup session and its
certificate-bound six-digit comparison on both devices. It does not change the
model configuration or desktop pairing. The phone's document picker supplies the
package; Import Skill on the watch always opens this receiver, avoiding Wear OS document-picker stubs.

All messages retain `type: configure`. Supported `kind` values:

- `skill_begin`: `size` (1 to 16 MiB), `sha256` (64 lowercase hex characters).
  This clears any incomplete transfer and acknowledges `status: uploading`,
  `next_index: 0`.
- `skill_chunk`: zero-based `index`, `data` (base64 of at most 16 KiB). Chunks must
  arrive in order and cannot exceed the declared total length. Acknowledgments
  contain `status: uploading` and the next expected index. Each frame remains
  below the setup protocol's 32 KiB limit.
- `skill_finish`: verifies total length, SHA-256, package integrity, supported
  Skill ID and configuration. The watch asks for installation approval, with a
  60-second timeout. Only approval while the receiver is still foreground commits
  the installation. `saved` acknowledges installation; `cancelled`, `invalid`,
  or `save_failed` must not be displayed as success on the phone.

This version supports door-access packages. Exiting or restarting the watch
receiver clears incomplete transfers. Rejection or invalid packages do not
replace an installed Skill. A successful transfer closes the setup session and
opens Skill management. The phone does not install the transferred package on
itself. Opening the phone's document picker temporarily retains the authenticated
connection, subject to the receiver's existing bounded lifetime.
