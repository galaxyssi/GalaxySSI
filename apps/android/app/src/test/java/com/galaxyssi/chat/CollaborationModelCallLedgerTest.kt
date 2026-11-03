package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationModelCallLedgerTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter {
            it.startsWith(prefix) && it > after
        }.sorted().take(limit)
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "person")
    private fun receipt(ledger: CollaborationModelCallLedger, target: CollaborationWorkspaceAccess = access,
                        complete: Boolean = true) {
        val request = ModelStreamRequest("same-logical-round", ModelStreamProvider.OPENAI_COMPATIBLE,
            "https://example.invalid", emptyMap(), """{"model":"model"}""")
        val audit = ModelCallAccounting(request, ledger.sink(target))
        audit.begin()
        if (complete) {
            audit.observe("""{"model":"model","usage":{"prompt_tokens":3,"completion_tokens":2}}""")
            audit.observe("[DONE]")
            audit.event(ModelStreamEvent.Completed(request.requestId, "stop", 1))
            audit.finish()
        }
    }

    @Test fun receiptsSurviveReopenAndSeparateGroupsRunsAndRetries() {
        val rows = Rows()
        val ledger = CollaborationModelCallLedger(rows)
        receipt(ledger)
        receipt(ledger, complete = false)
        receipt(ledger, access.copy(groupId = "other"))
        receipt(ledger, access.copy(runId = "other-run"))
        val reopened = CollaborationModelCallLedger(rows).page("group", "run").first
        assertEquals(2, reopened.size)
        assertEquals(setOf("started", "completed"), reopened.map { it.getString("status") }.toSet())
        assertEquals(2, reopened.map { it.getString("call_id") }.distinct().size)
        assertTrue(reopened.all { it.getString("person_id") == "person" })
        assertFalse(reopened.single { it.getString("status") == "started" }.getBoolean("tokens_complete"))
    }

    @Test fun finalReceiptIsImmutableAndIdentityCannotMigrateToAnotherMember() {
        val rows = Rows()
        val ledger = CollaborationModelCallLedger(rows)
        receipt(ledger)
        val saved = ledger.page("group", "run").first.single()
        // Settlement replay is idempotent, but neither values nor authorship may change.
        ledger.sink(access).write(saved)
        assertThrows(IllegalStateException::class.java) {
            ledger.sink(access).write(JSONObject(saved.toString()).put("status", "failed"))
        }
        assertThrows(IllegalStateException::class.java) { ledger.sink(access.copy(personId = "other")).write(saved) }
    }

    @Test fun pagingRetainsEveryCallWithoutReturningAdmissionDuplicates() {
        val ledger = CollaborationModelCallLedger(Rows())
        repeat(205) { receipt(ledger, complete = it % 3 != 0) }
        val all = mutableListOf<JSONObject>()
        var cursor = ""
        do {
            val page = ledger.page("group", "run", cursor)
            all += page.first
            cursor = page.second.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(205, all.size)
        assertEquals(205, all.map { it.getString("call_id") }.distinct().size)
    }

    @Test fun revokedAccessCannotAdmitOrRecreateDeletedResearch() {
        val rows = Rows()
        val ledger = CollaborationModelCallLedger(rows) { false }
        assertThrows(IllegalStateException::class.java) { receipt(ledger) }
        assertTrue(rows.values.isEmpty())
    }
}
