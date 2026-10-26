package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentSessionRootStorageDeviceTest {
    @Test fun checkpointCostDoesNotRewriteFourteenMegabytesOfUnrelatedHistory() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "session-rows-benchmark-${UUID.randomUUID()}"
        val legacy = AgentEncryptedPreferences(context, name)
        val database = AgentEncryptedDatabase(context, name)
        try {
            legacy.writeString("unrelated-history", "x".repeat(10 * 1024 * 1024))
            val store = AgentSessionRootStorage(context, name, name)
            store.writeString("task:benchmark", "warmup")
            fun sample(write: (String) -> Unit): List<Long> = (1..8).map { index ->
                val started = android.os.SystemClock.elapsedRealtimeNanos()
                write("checkpoint-$index")
                (android.os.SystemClock.elapsedRealtimeNanos() - started) / 1_000_000
            }.sorted()
            val before = sample { legacy.writeString("task:benchmark", it) }
            val after = sample { store.writeString("task:benchmark", it) }
            assertEquals("checkpoint-8", AgentSessionRootStorage(context, name, name).readString("task:benchmark", ""))
            android.util.Log.i("GalaxySSILatency", "checkpoint_benchmark legacy_median_ms=${before[4]} " +
                "row_median_ms=${after[4]} legacy_max_ms=${before.last()} row_max_ms=${after.last()}")
            assertTrue("Row writes must be faster than rewriting unrelated history", after[4] < before[4])
        } finally {
            database.clear()
            legacy.clear()
        }
    }

    @Test fun lazyRowsPreserveLegacyAndDeletionAcrossReopen() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "session-rows-test-${UUID.randomUUID()}"
        val legacy = AgentEncryptedPreferences(context, name)
        val database = AgentEncryptedDatabase(context, name)
        try {
            legacy.writeString("task:one", "old checkpoint")
            legacy.writeString("task:two", "unrelated checkpoint")
            val original = context.getSharedPreferences(name, Context.MODE_PRIVATE).all.toMap()
            val store = AgentSessionRootStorage(context, name, name)
            assertEquals("old checkpoint", store.readString("task:one", ""))
            store.writeString("task:one", "new checkpoint")
            store.writeString("connector-response-index:test", "task:one")
            assertEquals(original, context.getSharedPreferences(name, Context.MODE_PRIVATE).all)
            val reopened = AgentSessionRootStorage(context, name, name)
            assertEquals("new checkpoint", reopened.readString("task:one", ""))
            assertEquals("unrelated checkpoint", reopened.readString("task:two", ""))
            assertEquals("task:one", reopened.readString("connector-response-index:test", ""))
            assertTrue(reopened.encodedValueLength("task:one") > "new checkpoint".length)
            reopened.remove("task:one")
            reopened.remove("task:two")
            val deleted = AgentSessionRootStorage(context, name, name)
            assertEquals("missing", deleted.readString("task:one", "missing"))
            assertEquals("missing", deleted.readString("task:two", "missing"))
            assertEquals(0, deleted.encodedValueLength("task:one"))
            assertFalse("task:one" in deleted.keys())
            assertFalse("task:two" in deleted.keys())
            deleted.writeString("task:one", "recreated checkpoint")
            assertEquals("recreated checkpoint", deleted.readString("task:one", ""))
            assertTrue("task:one" in deleted.keys())
            assertEquals(original, context.getSharedPreferences(name, Context.MODE_PRIVATE).all)
        } finally {
            database.clear()
            legacy.clear()
        }
    }
}
