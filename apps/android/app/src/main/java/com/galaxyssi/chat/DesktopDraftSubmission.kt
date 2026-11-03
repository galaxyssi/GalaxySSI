package com.galaxyssi.chat

/** Tracks receipts without retaining a second plaintext copy of the draft. */
internal class DesktopDraftSubmission {
    private var revision = 0L
    private var submittedRevision = 0L
    var pendingId: String? = null
        private set

    fun edited() { revision++ }

    fun begin(id: String): Boolean {
        if (pendingId != null) return false
        pendingId = id
        submittedRevision = revision
        return true
    }

    fun complete(id: String, succeeded: Boolean): Boolean {
        if (pendingId != id) return false
        pendingId = null
        return succeeded && revision == submittedRevision
    }

    fun cancel() { pendingId = null }
}
