package com.galaxyssi.chat

import android.os.Build
import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePayloadCompactionRecoveryDeviceTest {
    @Test fun hostDrivenRecovery() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("compaction_phase")
        assumeTrue("Explicit host recovery phase required", phase != null)
        assertEquals("SM-T575", Build.MODEL)
        val name = requireNotNull(args.getString("compaction_fixture"))
        require(name.matches(Regex("test-knowledge-payload-[a-f0-9-]{36}\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val path = context.getDatabasePath(name)
        if (phase == "prepare") assertFalse(path.exists()) else assertTrue(path.isFile)
        val marker = File(context.cacheDir, "$name.compaction-phase")
        KnowledgePayloadTestFixture(name).use { f ->
            fun row(id: Int) = KnowledgePayloadCompactionFixture.row(f, "payload-$id")
            fun mark(value: String, reference: String) = FileOutputStream(marker).use {
                it.write(JSONObject().put("phase", value).put("reference", reference).toString().toByteArray()); it.fd.sync()
            }
            fun saved(expected: String): String = JSONObject(marker.readText()).run {
                assertEquals(expected, getString("phase")); getString("reference")
            }
            fun die(value: String, reference: String): Nothing {
                mark(value, reference); Process.killProcess(Process.myPid()); error("Intentional death did not occur")
            }
            fun verify(id: Int) = assertTrue("Recovered payload differs", f.item(id) == f.store.findByIds(setOf("payload-$id")).single())
            when (phase) {
                "prepare" -> {
                    KnowledgePayloadCompactionFixture.fragmented(f)
                    mark("prepared", row(7).value)
                }
                "before-commit" -> {
                    val reference = saved("prepared"); val old = row(7)
                    assertEquals(reference, old.value)
                    val oldFile = KnowledgePayloadCompactionFixture.path(f, old)
                    f.db.payloads.leases.tryReclaim {
                        KnowledgeSqlite(path.absolutePath).use { sql ->
                            sql.execSQL("PRAGMA foreign_keys=ON"); sql.execSQL("PRAGMA recursive_triggers=ON")
                            sql.beginTransaction()
                            f.db.payloads.reclaim(sql)
                            sql.rawQuery("SELECT reference FROM knowledge_payloads WHERE item_key=?", arrayOf(old.key)).use {
                                assertTrue(it.moveToFirst()); assertNotEquals(reference, it.getString(0))
                            }
                            assertTrue("Old segment was deleted before commit", oldFile.isFile)
                            die("before-commit", reference)
                        }
                    }
                    error("Exclusive fixture access was unavailable")
                }
                "verify-rollback" -> {
                    val reference = saved("before-commit")
                    assertEquals(reference, row(7).value); verify(7); KnowledgePayloadUsageDeviceTest.exact(f)
                    mark("rollback-verified", reference)
                }
                "after-commit" -> {
                    val reference = saved("rollback-verified")
                    f.db.reclaimPayloads()
                    assertNotEquals(reference, row(7).value)
                    die("after-commit", reference)
                }
                "verify-commit" -> {
                    val reference = saved("after-commit")
                    assertNotEquals(reference, row(7).value); verify(7)
                    assertTrue(KnowledgePayloadCompactionFixture.finish(f) > 0)
                    KnowledgePayloadUsageDeviceTest.exact(f); mark("commit-verified", row(7).value)
                }
                "prepare-copy" -> {
                    saved("commit-verified"); KnowledgePayloadCompactionFixture.large(f)
                    mark("copy-prepared", row(99).value)
                }
                "during-copy" -> {
                    val reference = saved("copy-prepared")
                    var attempts = 0
                    while (f.db.payloads.catalog.copyJob() == null) { assertTrue(++attempts < 16); f.db.reclaimPayloads() }
                    f.db.reclaimPayloads()
                    val state = KnowledgePayloadCopy(f.db.payloads).decode(requireNotNull(f.db.payloads.catalog.copyJob()))
                    assertTrue(state.copiedBytes > 0); assertFalse(state.complete)
                    assertEquals(reference, row(99).value)
                    die("during-copy", reference)
                }
                "verify-copy" -> {
                    val reference = saved("during-copy")
                    assertEquals(reference, row(99).value)
                    assertNotNull(f.db.payloads.catalog.copyJob())
                    assertTrue(KnowledgePayloadCompactionFixture.finish(f) > 0)
                    assertNotEquals(reference, row(99).value); verify(99); verify(7)
                    KnowledgePayloadUsageDeviceTest.exact(f); mark("copy-verified", row(99).value)
                }
                else -> error("Unknown compaction recovery phase")
            }
        }
    }
}
