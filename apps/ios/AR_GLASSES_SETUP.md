# AR glasses provisioning from iPhone

Open My Agent, Connected devices, Configure AR glasses. Start phone setup
on the glasses and enter the IPv4 address and port displayed by the
glasses. Both devices must be on the same Wi-Fi. Confirm the certificate-
bound six-digit code on both devices, then explicitly choose and transfer
an existing Cloud Agent model. The key is read only for the transfer and
never displayed or written to a new file on the phone.

Manual IP is the current glasses protocol's fallback and works without
Bonjour service registration. The current glasses advertisement,
`_galaxyssi-glasses._tcp`, exceeds the DNS-SD service-name length limit
in [RFC 6763 section 7.2](https://www.rfc-editor.org/rfc/rfc6763.html#section-7.2).
Reliable discovery requires a compatible advertisement on the glasses;
this iOS-only change does not modify the glasses app.

The client accepts no credential transfer before both confirmations and
does not reuse the bootstrap socket or trust decision for provider calls.
A cancelled, interrupted or expired session must be restarted. A lost
save acknowledgment is not treated as success and the key is not retried.
The protocol tests use fixed synthetic bytes, not physical glasses.
