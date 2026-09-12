package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeCryptoProfileDeviceTest {
    private fun profile(label: String, count: Int = 100, action: (Int) -> Unit) {
        val samples = LongArray(count)
        repeat(count) { i -> val start = System.nanoTime(); action(i); samples[i] = System.nanoTime() - start }
        samples.sort()
        println("KNOWLEDGE_CRYPTO_PROFILE phase=$label samples=$count sum_ns=${samples.sum()} " +
            "p50_ns=${samples[count / 2 - 1]} p95_ns=${samples[count * 95 / 100 - 1]} p99_ns=${samples[count * 99 / 100 - 1]}")
    }

    @Test fun hardwareAndWrappedAesHaveTheSameAuthenticatedPlaintext() = KnowledgeSourceReplaceFixture().use { f ->
        val text = "\u52a0\u5bc6\u77e5\u8bc6\u6b63\u6587".repeat(160)
        val aad = "${f.name}:profile".toByteArray()
        val wrapped = AgentRowStorageCipher(f.context, "profile:${f.name}")
        wrapped.preload()
        var hardware = AgentStorageCipher.encrypt(text, aad)
        var row = wrapped.encrypt(text, aad)
        profile("hardware_aes_encrypt") { hardware = AgentStorageCipher.encrypt(text, aad) }
        profile("wrapped_aes_encrypt") { row = wrapped.encrypt(text, aad) }
        profile("hardware_aes_decrypt") { assertEquals(text, AgentStorageCipher.decrypt(hardware, aad)) }
        profile("wrapped_aes_decrypt") { assertEquals(text, wrapped.decrypt(row, aad)) }
        assertNull(wrapped.decrypt(row, "wrong".toByteArray()))
        assertEquals(text, wrapped.decrypt(hardware, aad))
    }

    @Test fun canonicalOperationsExposeTheirActualHardwareCost() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(0).copy(content = "\u79c1\u5bc6\u8bb0\u5fc6".repeat(100))
        f.store.upsert(item)
        val key = f.db.key("id", item.id)
        profile("index_hmac_repeated") { assertEquals(key, f.db.key("id", item.id)) }
        profile("index_hmac_distinct") { assertEquals(64, f.db.key("id", "profile-$it").length) }
        f.db.access { sql ->
            profile("index_hmac_operation_repeated") { assertEquals(key, f.db.key("id", item.id)) }
            profile("canonical_header_read") { assertNotNull(f.db.readHeader(sql, key)) }
            profile("canonical_full_read") { assertEquals(item, f.db.read(sql, key)) }
        }
        f.db.transaction { sql -> profile("canonical_write") { f.db.write(sql, item.copy(id = "write-$it")) } }
        assertEquals(101L, f.store.stats().itemCount)
    }

    @Test fun retainedTenThousandBodyFixtureRemainsReadable() {
        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        val name = androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        org.junit.Assume.assumeTrue("Explicit retained synthetic fixture required", name != null)
        requireNotNull(name)
        require(name.matches(Regex("test-knowledge-source-replace-[a-f0-9-]+\\.db")))
        check(context.getDatabasePath(name).isFile) { "The retained source scale fixture is required" }
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        try {
            assertEquals(10_001L, db.access(db::stats).itemCount)
            val keys = db.access { sql -> db.keys(sql, limit = 100) }
            db.access { sql -> profile("retained_scale_full_read") { i -> assertNotNull(db.read(sql, keys[i])) } }
        } finally { AgentKnowledgeDatabase.release(context, name) }
        println("KNOWLEDGE_CRYPTO_RETAINED_FIXTURE $name")
    }
}
