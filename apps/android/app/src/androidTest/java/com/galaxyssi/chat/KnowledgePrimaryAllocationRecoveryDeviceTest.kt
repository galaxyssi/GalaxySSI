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
class KnowledgePrimaryAllocationRecoveryDeviceTest {
    @Test fun allocationIntentSurvivesRealProcessDeath() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("allocationPhase")
        assumeTrue("Explicit host recovery phase required", phase != null)
        val name = requireNotNull(args.getString("allocationFixture"))
        require(name.matches(Regex("test-primary-alloc-[a-f0-9]{32}\\.db")))
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun die(): Nothing {
            FileOutputStream(File(context.cacheDir, "$name.phase")).use { it.write(requireNotNull(phase).toByteArray()); it.fd.sync() }
            Process.killProcess(Process.myPid()); error("Expected process death")
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            fun pending() = KnowledgeSqlite(f.root.absolutePath + ".allocations.sqlite").use { db ->
                db.rawQuery("SELECT count(*) FROM pending", null).use { check(it.moveToFirst()); it.getLong(0) }
            }
            when (phase) {
                "intent-only" -> { f.parts.allocations.remember("b".repeat(32)); die() }
                "verify-empty" -> { assertTrue(pending() > 0); f.drain(); assertEquals(0L, pending()); assertEquals(0L, f.number("SELECT count(*) FROM knowledge_items")) }
                "before-catalog" -> f.transaction { f.put(1, "\u672a\u53d1\u5e03\u6b63\u6587"); f.parts.prepareCommit(); die() }
                "after-unlink" -> {
                    assertEquals(0L, f.number("SELECT count(*) FROM knowledge_items"))
                    assertTrue(pending() > 0)
                    f.parts.allocations.replay({ false }, { error("Unexpected reference") }, { f.parts.removeRetired(it); die() }, { })
                    error("Expected orphan intent")
                }
                "after-catalog" -> { f.transaction { f.put(1, "\u5df2\u63d0\u4ea4\u6b63\u6587") }; die() }
                "verify-committed" -> {
                    assertTrue(pending() > 0); f.drain(); assertEquals(0L, pending())
                    assertEquals("\u5df2\u63d0\u4ea4\u6b63\u6587", f.parts.read(f.db, f.key(1)))
                    assertEquals(1, f.root.listFiles()!!.count { it.extension == "sqlite" })
                }
                else -> error("Unknown allocation recovery phase")
            }
        }
    }
}
