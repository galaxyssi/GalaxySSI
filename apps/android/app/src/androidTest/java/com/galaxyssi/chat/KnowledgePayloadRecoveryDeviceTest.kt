package com.galaxyssi.chat

import android.os.Build
import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Host verifies durable phase markers and starts a fresh process after each intentional death. */
@RunWith(AndroidJUnit4::class)
class KnowledgePayloadRecoveryDeviceTest {
    @Test fun hostDrivenRecovery() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("payload_phase")
        assumeTrue("Explicit host recovery phase required", phase != null)
        assertEquals("SM-T575", Build.MODEL)
        val name = requireNotNull(args.getString("payload_fixture"))
        require(name.matches(Regex("test-payload-recovery-[a-f0-9]{32}\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val path = context.getDatabasePath(name)
        if (phase == "prepare") assertFalse(path.exists()) else assertTrue(path.isFile)
        val legacy = "legacy-$name"
        val store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        val db = AgentKnowledgeDatabase.shared(context, name, legacy)
        val marker = File(context.cacheDir, "$name.phase")
        fun mark(value: String) = FileOutputStream(marker).use { it.write(value.toByteArray()); it.fd.sync() }
        fun item(version: String) = AgentKnowledgeItem(id = "payload-recovery", kind = AgentKnowledgeKind.NOTE,
            title = "\u6062\u590d\u6d4b\u8bd5", summary = version, source = "\u672c\u5730\u6062\u590d",
            content = ("\u77e5\u8bc6\u6b63\u6587 $version ").repeat(3000).trim(), updatedAtMillis = 123)
        fun current() = store.findByIds(setOf("payload-recovery")).single()
        fun verify(version: String) { assertTrue("Recovered payload differs from $version", item(version) == current()) }
        fun die(value: String): Nothing {
            mark(value)
            Process.killProcess(Process.myPid())
            error("Intentional process death did not occur")
        }
        try {
            when (phase) {
                "prepare" -> { store.upsert(item("original")); mark("prepared") }
                "before-commit" -> {
                    assertEquals("prepared", marker.readText()); verify("original")
                    db.transaction { sql -> db.write(sql, item("uncommitted")); die("before-commit") }
                }
                "verify-rollback" -> {
                    assertEquals("before-commit", marker.readText()); verify("original")
                    val reclaimed = requireNotNull(db.reclaimPayloads())
                    assertTrue("Uncommitted bytes must be reclaimable", reclaimed.bytes > 0)
                    verify("original"); mark("rollback-verified")
                }
                "after-commit" -> {
                    assertEquals("rollback-verified", marker.readText())
                    store.upsert(item("committed")); die("after-commit")
                }
                "verify-commit" -> {
                    assertEquals("after-commit", marker.readText()); verify("committed")
                    repeat(4) { assertNotNull(db.reclaimPayloads()) }
                    verify("committed"); mark("commit-verified")
                }
                "during-snapshot" -> {
                    assertEquals("commit-verified", marker.readText())
                    val snapshot = db.backupSnapshot()
                    db.transaction { it.delete("knowledge_items", null, null) }
                    assertNull(db.reclaimPayloads())
                    assertTrue("Snapshot lost its committed body", listOf(item("committed")) == snapshot.items().toList())
                    die("during-snapshot")
                }
                "verify-snapshot-release" -> {
                    assertEquals("during-snapshot", marker.readText()); assertEquals(0L, store.stats().itemCount)
                    assertTrue(requireNotNull(db.reclaimPayloads()).bytes > 0)
                    store.upsert(item("retained")); verify("retained")
                    mark("snapshot-release-verified")
                }
                else -> error("Unknown payload recovery phase")
            }
        } finally { store.close() }
    }
}
