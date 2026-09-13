package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryRebootDeviceTest {
    @Test fun incompleteCopyResumesAfterDeviceReboot() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("rebootPhase")
        assumeTrue("Explicit host reboot phase required", phase != null)
        val name = requireNotNull(args.getString("rebootFixture"))
        require(name.matches(Regex("test-primary-reboot-[a-f0-9]{32}\\.db")))
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(phase != "prepare", context.getDatabasePath(name).exists())
        val body = "\u91cd\u542f\u6062\u590d".repeat(KnowledgePrimaryFrameCodec.CHARS * 5) + "\u5b8c"
        val start = System.nanoTime()
        KnowledgePrimaryCompactionFixture(name).use { f ->
            val copy = KnowledgePrimaryCopy(f.parts)
            fun state() = copy.state(requireNotNull(copy.load(f.db)))
            when (phase) {
                "prepare" -> {
                    f.transaction { f.put(1, "\u65e7\u7248"); f.put(1, body) }
                    f.transaction { KnowledgePrimaryCompaction.advance(f.db, f.parts) { } }
                    f.transaction { f.parts.resumeCopy(f.db) { } }
                    assertEquals(16, state().copied); assertEquals(0, state().verified)
                    assertEquals(body, f.parts.read(f.db, f.key(1)))
                }
                "verify" -> {
                    assertEquals(16, state().copied); assertEquals(0, state().verified)
                    val restoredNanos = System.nanoTime() - start
                    assertEquals(body, f.parts.read(f.db, f.key(1)))
                    f.drain(); assertFalse(KnowledgePrimaryCopy.pending(f.db))
                    assertEquals(body, f.parts.read(f.db, f.key(1)))
                    assertEquals(1L, f.number("SELECT count(*) FROM knowledge_primary_partitions"))
                    println("KNOWLEDGE_PRIMARY_REBOOT restored_ns=$restoredNanos copied_before=16 verified_before=0 completed=true")
                }
                else -> error("Unknown primary reboot phase")
            }
        }
    }
}
