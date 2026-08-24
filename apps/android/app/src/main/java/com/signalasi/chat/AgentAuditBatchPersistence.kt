package com.signalasi.chat

internal data class AgentAuditRecord(
    val event: AgentAuditEvent,
    val detail: String
)

internal object AgentAuditBatchPersistence {
    fun append(
        auditTrail: MutableList<AgentAuditEntry>,
        records: Collection<AgentAuditRecord>,
        maxItems: Int,
        timestampMillis: () -> Long = System::currentTimeMillis
    ) {
        require(maxItems > 0) { "maxItems must be positive" }
        records.forEach { record ->
            auditTrail.add(
                AgentAuditEntry(
                    event = record.event,
                    detail = record.detail,
                    timestampMillis = timestampMillis()
                )
            )
        }
        val overflow = auditTrail.size - maxItems
        if (overflow > 0) {
            auditTrail.subList(0, overflow).clear()
        }
    }

    fun appendAndPersist(
        auditTrail: MutableList<AgentAuditEntry>,
        records: Collection<AgentAuditRecord>,
        maxItems: Int,
        timestampMillis: () -> Long = System::currentTimeMillis,
        persist: () -> Unit
    ) {
        if (records.isEmpty()) return
        append(auditTrail, records, maxItems, timestampMillis)
        persist()
    }
}
