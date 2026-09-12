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

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryRecoveryDeviceTest {
    @Test fun hostDrivenPublicationRecovery() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("primaryPhase")
        assumeTrue("Explicit process death phase required", phase != null)
        val name = requireNotNull(args.getString("primaryFixture"))
        require(name.matches(Regex("test-primary-recovery-[a-f0-9]{32}\\.db")))
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val path = context.getDatabasePath(name)
        if (phase == "prepare") assertFalse(path.exists()) else assertTrue(path.isFile)
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
        val owner = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        fun item(value: String) = AgentKnowledgeItem(id = "primary-recovery", kind = AgentKnowledgeKind.NOTE,
            title = "Recovery", summary = value, content = value, source = "fixture", updatedAtMillis = 123)
        fun die(value: String): Nothing {
            FileOutputStream(File(context.cacheDir, "$name.phase")).use { it.write(value.toByteArray()); it.fd.sync() }
            Process.killProcess(Process.myPid()); error("Process death did not occur")
        }
        try {
            when (phase) {
                "prepare" -> store.upsert(item("before"))
                "before-frames" -> owner.transaction { owner.write(it, item("uncommitted")); die("before-frames") }
                "before-catalog" -> owner.transaction {
                    owner.write(it, item("unpublished")); owner.primary.prepareCommit(); die("before-catalog")
                }
                "after-catalog" -> { store.upsert(item("after")); die("after-catalog") }
                "verify-before" -> assertEquals(listOf(item("before")), store.list(8))
                "verify-after" -> assertEquals(listOf(item("after")), store.list(8))
                else -> error("Unknown primary recovery phase")
            }
        } finally { store.close() }
    }
}
