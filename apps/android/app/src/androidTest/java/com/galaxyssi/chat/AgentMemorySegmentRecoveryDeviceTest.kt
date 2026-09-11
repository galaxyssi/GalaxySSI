package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

/** Host runs each phase in a fresh instrumentation process; intentional deaths are not passes. */
@RunWith(AndroidJUnit4::class)
class AgentMemorySegmentRecoveryDeviceTest {
    private fun value(version: String) = "synthetic-$version \u65ad\u7535\u6062\u590d\u6d4b\u8bd5 ".repeat(900).trim()

    @Test fun hostDrivenRecovery() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("segment_phase")
        org.junit.Assume.assumeTrue("Host must select a recovery phase", phase != null)
        val id = requireNotNull(args.getString("segment_fixture"))
        require(id.startsWith("segments-recovery-"))
        val f = MemoryDeletionDeviceFixture(id)
        val db = f.store.database
        val key = AgentPersonalMemoryRows.key("recovery-memory")
        val marker = File(f.context.cacheDir, "phase.txt")
        fun checkpoint(text: String) = FileOutputStream(marker).use { it.write(text.toByteArray()); it.fd.sync() }
        fun die(text: String): Nothing {
            checkpoint(text)
            Process.killProcess(Process.myPid())
            error("Intentional process termination did not occur")
        }
        when (phase) {
            "prepare" -> {
                assertFalse("Recovery fixture must be new", db.contains(key))
                db.writeString(key, value("original"))
                checkpoint("prepared")
            }
            "before-commit" -> {
                assertEquals(value("original"), db.readString(key, ""))
                db.mutateStrings(mapOf(key to value("uncommitted")), onMutation = { _, changed, _ ->
                    if (changed == key) die("before-commit")
                })
                fail("Commit unexpectedly returned")
            }
            "verify-rollback" -> {
                assertEquals("before-commit", marker.readText())
                assertEquals(value("original"), db.readString(key, ""))
                val result = db.maintainMemorySegments(32, 32)
                assertTrue("Uncommitted segment must be reclaimed", result.removed > 0)
                assertEquals(value("original"), db.readString(key, ""))
                checkpoint("rollback-verified")
            }
            "after-commit" -> {
                assertEquals("rollback-verified", marker.readText())
                db.writeString(key, value("committed"))
                die("after-commit")
            }
            "verify-commit" -> {
                assertEquals("after-commit", marker.readText())
                assertEquals(value("committed"), db.readString(key, ""))
                repeat(3) { db.maintainMemorySegments(32, 32) }
                assertEquals(value("committed"), db.readString(key, ""))
                checkpoint("commit-verified")
            }
            "cleanup" -> {
                assertEquals("commit-verified", marker.readText())
                f.clear()
                repeat(3) { db.maintainMemorySegments(32, 32) }
                assertFalse(db.contains(key))
                checkpoint("cleaned")
            }
            else -> error("Unknown recovery test phase: $phase")
        }
    }
}
