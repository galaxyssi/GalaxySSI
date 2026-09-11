package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Measures real retained-source components; does not weaken authentication to meet a timing target. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePageProfileDeviceTest {
    @Test fun separateIndexedSeekHeaderCipherAndIdentityChecks() {
        val name = InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained encrypted fixture required", name != null)
        val fixtureName = requireNotNull(name)
        val before = KnowledgeSourceMigrationTestSupport.fingerprint(fixtureName)
        KnowledgeBackupTestFixture(fixtureName).apply { retain = true; observe = false }.use { f ->
            KnowledgeSourceMigrationTestSupport.awaitReady(f)
            val output = File(requireNotNull(f.context.getExternalFilesDir("knowledge-source-directory-test")), f.name)
            val rows = f.db.access { db ->
                db.rawQuery(KnowledgeSourceDirectory.BROWSE_SQL, arrayOf(Long.MIN_VALUE.toString(), "", "50")).use { c ->
                    buildList { while (c.moveToNext()) add(c.getString(3)) }
                }
            }
            assertEquals(50, rows.size)
            val headers = f.db.access { db -> rows.map { key ->
                db.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use { c ->
                    check(c.moveToFirst()); key to c.getString(0)
                }
            } }
            File(output, "profile-ms.csv").bufferedWriter().use { csv ->
                csv.write("pass,component,rows,elapsed_ms\n")
                fun measure(pass: Int, label: String, action: () -> Unit) {
                    val at = System.nanoTime(); action()
                    val ms = (System.nanoTime() - at) / 1_000_000.0
                    csv.write("$pass,$label,50,$ms\n")
                    println("KNOWLEDGE_SOURCE_PROFILE pass=$pass component=$label rows=50 elapsed_ms=$ms")
                }
                repeat(5) { pass ->
                    measure(pass, "index_seek") { f.db.access { db ->
                        db.rawQuery(KnowledgeSourceDirectory.BROWSE_SQL, arrayOf(Long.MIN_VALUE.toString(), "", "50")).use { c ->
                            var count = 0; while (c.moveToNext()) { c.getString(0); c.getLong(1); c.getLong(2); c.getString(3); count++ }
                            assertEquals(50, count)
                        }
                    } }
                    measure(pass, "header_aead_only") { headers.forEach { (key, value) ->
                        val decoded = requireNotNull(AgentStorageCipher.decrypt(value, "${f.name}:$key:header".toByteArray()))
                        assertTrue(JSONObject(decoded).has("source_preview"))
                    } }
                    measure(pass, "identity_hmac_only") {
                        repeat(50) { assertEquals(64, f.db.key("id", "backup-${it + 1}").length) }
                    }
                    measure(pass, "authenticated_summaries") { f.db.access { db ->
                        rows.forEach { assertNotNull(f.db.readSourceMetadata(db, it)) }
                    } }
                    measure(pass, "complete_page") { assertEquals(50, f.store.sourcePage().groups.size) }
                }
            }
            assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(fixtureName))
            assertEquals(0L, f.db.decryptedItemReads)
        }
    }
}
