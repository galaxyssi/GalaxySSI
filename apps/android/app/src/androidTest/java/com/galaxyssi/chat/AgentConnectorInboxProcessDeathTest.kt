package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConnectorInboxProcessDeathTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private fun id(): String {
        val id = InstrumentationRegistry.getArguments().getString("inboxRecoveryId").orEmpty()
        assumeTrue("Separate persist/force-stop/recover phases require an explicit isolated ID", id.matches(Regex("inbox-test-[a-z0-9-]{1,60}")))
        return id
    }
    private fun reply(number: Long) = AgentConnectorResponse(number, "test-provider", "\u8fdb\u7a0b\u6062\u590d-$number",
        "process-conversation", "turn-$number", "task-$number", receivedAtMillis = number)

    @Test fun persistBeforeProcessDeath() {
        val id = id()
        AgentConnectorResponseInbox(context, "$id.db", "$id-prefs").use { inbox ->
            for (number in 1L..129) {
                inbox.append(reply(number))
                if (number % 17 == 0L) inbox.acknowledge(reply(number))
            }
            assertTrue(inbox.contains(reply(129)))
            assertFalse(inbox.contains(reply(17)))
        }
    }

    @Test fun recoverAfterProcessDeath() {
        val id = id()
        try {
            AgentConnectorResponseInbox(context, "$id.db", "$id-prefs").use { inbox ->
                val end = inbox.highWatermark()
                var cursor = 0L
                val restored = mutableListOf<AgentConnectorResponse>()
                while (cursor < end) {
                    val page = inbox.page(cursor, end)
                    assertTrue(page.nextSequence > cursor)
                    assertEquals(0, page.unreadableCount)
                    restored += page.responses
                    cursor = page.nextSequence
                }
                assertEquals((1L..129).filter { it % 17 != 0L }.map(::reply), restored)
                assertFalse(inbox.append(reply(17)))
                restored.forEach { inbox.acknowledge(it) }
                assertEquals(0L, inbox.highWatermark())
            }
        } finally {
            context.deleteDatabase("$id.db")
            context.getSharedPreferences("$id-prefs", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }
}
