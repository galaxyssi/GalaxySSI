package com.galaxyssi.chat

/** Cheap saved-state admission before constructing an executable Agent. Live admission still runs after the lease. */
internal object AgentConnectorReceiptAdmission {
    fun <T> restoreCandidate(saved: AgentSessionSnapshot?, create: () -> T): T? =
        if (saved == null || saved.phase == AgentPhase.CANCELLED) null else create()

    fun transport(phase: AgentPhase, pending: AgentActionResult?, source: Long, contact: String): Boolean {
        if (source <= 0 || pending == null) return false
        val timeout = phase == AgentPhase.FAILED && !pending.success &&
            pending.metadata["timeout_stage"].orEmpty().isNotBlank()
        if (phase != AgentPhase.WAITING_RESPONSE && !timeout &&
            !AgentTeamParentRecoveryPolicy.acceptsLateResult(phase, pending.metadata, source)) return false
        if (pending.metadata["source_message_id"]?.toLongOrNull() != source) return false
        val expectedContact = pending.metadata["contact_id"].orEmpty()
        return expectedContact.isBlank() || contact.isBlank() || expectedContact == contact
    }

    fun saved(saved: AgentSessionSnapshot, source: Long, contact: String,
        conversation: String, turn: String, task: String): Boolean {
        val pending = saved.lastActionResult
        if (transport(saved.phase, pending, source, contact) && AgentTaskIdentityPolicy.matchesDesktopResponse(
                checkNotNull(pending).metadata, conversation, task, turn)) return true
        // Keep the existing durable dispatch-receipt repair available to the live runtime.
        return saved.phase == AgentPhase.FAILED && pending?.metadata?.get("error_code") == "idempotency_key_conflict"
    }
}
