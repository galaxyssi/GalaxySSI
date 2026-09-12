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
class KnowledgePrimaryCompactionRecoveryDeviceTest {
    @Test fun realProcessDeathKeepsPublishedBodiesAndResumesCompaction() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("compactionPhase")
        assumeTrue("Explicit host recovery phase required", phase != null)
        val name = requireNotNull(args.getString("compactionFixture"))
        require(name.matches(Regex("test-primary-compact-[a-f0-9]{32}\\.db")))
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(phase != "prepare", context.getDatabasePath(name).isFile)
        fun die(): Nothing {
            FileOutputStream(File(context.cacheDir, "$name.phase")).use { it.write(requireNotNull(phase).toByteArray()); it.fd.sync() }
            Process.killProcess(Process.myPid()); error("Expected process death")
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            when (phase) {
                "prepare" -> f.seed()
                "before-frames", "before-catalog" -> f.transaction {
                    assertEquals(8, KnowledgePrimaryCompaction.advance(f.db, f.parts) { })
                    if (phase == "before-catalog") f.parts.prepareCommit()
                    die()
                }
                "after-catalog" -> {
                    f.transaction { assertEquals(8, KnowledgePrimaryCompaction.advance(f.db, f.parts) { }) }
                    die()
                }
                "verify-before" -> { f.verify(); assertEquals(1L, f.number("SELECT count(*) FROM knowledge_primary_partitions")) }
                "verify-after" -> {
                    f.verify()
                    assertEquals(1L, f.number("SELECT count(*) FROM knowledge_primary_compaction WHERE source<>''"))
                    assertEquals(8, f.drain()); f.verify()
                }
                else -> error("Unknown compaction phase")
            }
        }
    }
}
