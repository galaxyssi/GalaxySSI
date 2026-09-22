package com.galaxyssi.watch

/** Match Android handlePairingConfirmation: a new route replaces the previous Signal session;
 * duplicate confirmations never reset a live session. */
internal object WatchPairingSession {
    fun canReuse(paired: Boolean, hasSession: Boolean, savedFingerprint: String,
                 trustedFingerprint: String, scannedFingerprint: String): Boolean =
        paired && hasSession && savedFingerprint.isNotBlank() &&
            savedFingerprint.equals(trustedFingerprint, ignoreCase = true) &&
            savedFingerprint.equals(scannedFingerprint, ignoreCase = true)

    fun confirm(paired: Boolean, hasSession: Boolean, bootstrap: (replaceExisting: Boolean) -> Boolean): Boolean =
        if (!paired || !hasSession) bootstrap(!paired) else true
}
