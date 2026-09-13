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
class KnowledgePrimaryCopyRecoveryDeviceTest {
    @Test fun copyAndVerificationSurviveRealProcessDeath() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("copyPhase")
        assumeTrue("Explicit host recovery phase required", phase != null)
        val name = requireNotNull(args.getString("copyFixture"))
        require(name.matches(Regex("test-primary-copy-[a-f0-9]{32}\\.db")))
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(phase != "prepare", context.getDatabasePath(name).isFile)
        val body = "\u590d\u5236\u6062\u590d".repeat(KnowledgePrimaryFrameCodec.CHARS * 5) + "\u5b8c"
        fun die(): Nothing {
            FileOutputStream(File(context.cacheDir, "$name.phase")).use { it.write(requireNotNull(phase).toByteArray()); it.fd.sync() }
            Process.killProcess(Process.myPid()); error("Expected process death")
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            fun state() = KnowledgePrimaryCopy(f.parts).state(requireNotNull(KnowledgePrimaryCopy(f.parts).load(f.db)))
            fun advance() = f.transaction { KnowledgePrimaryCompaction.advance(f.db, f.parts) { } }
            when (phase) {
                "prepare" -> { f.transaction { f.put(1, "old"); f.put(1, body) }; advance(); assertEquals(0, state().copied) }
                "before-frames", "before-catalog" -> f.transaction {
                    f.parts.resumeCopy(f.db) { }
                    if (phase == "before-catalog") f.parts.prepareCommit()
                    die()
                }
                "verify-before" -> { assertEquals(0, state().copied); assertEquals(body, f.parts.read(f.db, f.key(1))) }
                "after-copy" -> { advance(); assertEquals(16, state().copied); die() }
                "prepare-verify" -> { assertEquals(16, state().copied); advance(); assertEquals(21, state().copied); assertEquals(0, state().verified) }
                "before-verify-checkpoint" -> f.transaction { f.parts.resumeCopy(f.db) { }; f.parts.prepareCommit(); die() }
                "verify-copy" -> { assertEquals(21, state().copied); assertEquals(0, state().verified); assertEquals(body, f.parts.read(f.db, f.key(1))) }
                "after-verify-checkpoint" -> { advance(); assertEquals(16, state().verified); die() }
                "before-publish" -> f.transaction { assertEquals(1, KnowledgePrimaryCompaction.advance(f.db, f.parts) { }); f.parts.prepareCommit(); die() }
                "verify-not-published" -> { assertEquals(16, state().verified); assertEquals(body, f.parts.read(f.db, f.key(1))) }
                "after-publish" -> { advance(); assertFalse(KnowledgePrimaryCopy.pending(f.db)); die() }
                "verify-published" -> {
                    assertFalse(KnowledgePrimaryCopy.pending(f.db))
                    assertEquals(1L, f.number("SELECT count(*) FROM knowledge_primary_retired"))
                    assertEquals(body, f.parts.read(f.db, f.key(1)))
                    assertEquals(0, f.drain())
                    assertEquals(1, f.root.listFiles()!!.count { it.extension == "sqlite" })
                }
                else -> error("Unknown primary copy recovery phase")
            }
        }
    }
}
