package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Synthetic persistence checks only: no activity, network, model or user conversation is opened. */
@RunWith(AndroidJUnit4::class)
class CollaborationModelCallLedgerDeviceTest {
    @Test fun encryptedReopenPreservesFinishedAndUnfinishedCallsWithoutCrossRunLeakage() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val database = AgentEncryptedDatabase(context, "model-accounting-test-${UUID.randomUUID()}")
        fun rows() = object : CollaborationWorkspaceRows {
            override fun read(key: String) = database.readString(key, "").takeIf(String::isNotBlank)
            override fun commit(values: Map<String, String>) = database.mutateStrings(values)
            override fun page(prefix: String, after: String, limit: Int) = database.keysAfter(prefix, after, limit)
        }
        val access = CollaborationWorkspaceAccess("synthetic-group", "synthetic-run", "turn", 1, "review", "member")
        try {
            val ledger = CollaborationModelCallLedger(rows())
            fun record(finish: Boolean) {
                val request = ModelStreamRequest("synthetic:r0", ModelStreamProvider.OPENAI_COMPATIBLE,
                    "https://example.invalid", emptyMap(), """{"model":"synthetic-not-a-real-provider"}""")
                val accounting = ModelCallAccounting(request, ledger.sink(access))
                accounting.begin()
                if (finish) {
                    accounting.observe("""{"model":"synthetic","usage":{"prompt_tokens":10,"completion_tokens":2,"prompt_cache_hit_tokens":4}}""")
                    accounting.observe("[DONE]")
                    accounting.event(ModelStreamEvent.Completed(request.requestId, "stop", 1))
                    accounting.finish()
                }
            }
            record(true)
            record(false)
            val reopened = CollaborationModelCallLedger(rows())
            val page = reopened.page(access.groupId, access.runId).first
            assertEquals(2, page.size)
            assertEquals(12L, page.single { it.getString("status") == "completed" }.getJSONObject("usage").getLong("total_tokens"))
            assertFalse(page.single { it.getString("status") == "started" }.getBoolean("tokens_complete"))
            assertTrue(page.all { it.isNull("cost_micros") })
            assertTrue(reopened.page(access.groupId, "another-run").first.isEmpty())
        } finally { database.clear() }
    }
}
