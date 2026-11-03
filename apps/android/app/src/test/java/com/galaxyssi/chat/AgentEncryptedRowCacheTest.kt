package com.galaxyssi.chat

import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class AgentEncryptedRowCacheTest {
    @After fun clearCaches() = RuntimeSensitiveCaches.clearAll()

    @Test fun unchangedCiphertextDecryptsOnlyOnceAcrossRepeatedReads() {
        val cache = AgentEncryptedRowCache()
        var decrypts = 0
        repeat(100) {
            assertEquals("secret", cache.read("database", "task", "cipher") { decrypts++; "secret" })
        }
        assertEquals(1, decrypts)
    }

    @Test fun changedCiphertextWipesOldValueAndDecryptsAgain() {
        val cache = AgentEncryptedRowCache()
        cache.read("database", "task", "old") { "old secret" }
        val old = buffers(cache).single()
        assertEquals("new secret", cache.read("database", "task", "new") { "new secret" })
        assertWiped(old)
    }

    @Test fun authenticationFailureIsNeverCachedOrReplacedWithOldPlaintext() {
        val cache = AgentEncryptedRowCache()
        cache.read("database", "task", "valid") { "secret" }
        val old = buffers(cache).single()
        var decrypts = 0
        repeat(2) { assertNull(cache.read("database", "task", "corrupt") { decrypts++; null }) }
        assertEquals(2, decrypts)
        assertTrue(buffers(cache).isEmpty())
        assertWiped(old)
    }

    @Test fun databaseAndRowIdentityAreBothRequiredEvenForIdenticalCiphertext() {
        val cache = AgentEncryptedRowCache()
        assertEquals("one", cache.read("db", "task", "same") { "one" })
        assertEquals("two", cache.read("other-db", "task", "same") { "two" })
        assertEquals("three", cache.read("db", "other-task", "same") { "three" })
        assertEquals("four", cache.read("db\u0000task", "suffix", "same") { "four" })
        assertEquals("five", cache.read("db", "task\u0000suffix", "same") { "five" })
        assertEquals(5, buffers(cache).size)
    }

    @Test fun expiryDoesNotSlideOnHitsAndSweeperWipesIdleValues() {
        var now = 1L
        val cache = AgentEncryptedRowCache(ttlNanos = 10, clockNanos = { now })
        cache.read("db", "key", "cipher") { "secret" }
        val old = buffers(cache).single()
        now = 10
        assertEquals("secret", cache.read("db", "key", "cipher") { error("Unexpected decrypt") })
        now = 11
        assertFalse(cache.pruneExpired())
        assertWiped(old)
        assertEquals("fresh", cache.read("db", "key", "cipher") { "fresh" })
    }

    @Test fun expiredReadCannotUsePlaintextBeforeSweeperRuns() {
        var now = 0L
        val cache = AgentEncryptedRowCache(ttlNanos = 1, clockNanos = { now })
        cache.read("db", "key", "cipher") { "secret" }
        val old = buffers(cache).single()
        now++
        assertEquals("fresh", cache.read("db", "key", "cipher") { "fresh" })
        assertWiped(old)
    }

    @Test fun capacityEvictsAndWipesLeastRecentlyUsedRow() {
        val cache = AgentEncryptedRowCache(capacity = 2)
        cache.read("db", "first", "cipher") { "first" }
        cache.read("db", "second", "cipher") { "second" }
        val second = buffers(cache).last()
        cache.read("db", "first", "cipher") { error("Unexpected decrypt") }
        cache.read("db", "third", "cipher") { "third" }
        assertEquals(2, buffers(cache).size)
        assertWiped(second)
        assertEquals("first", cache.read("db", "first", "cipher") { error("Unexpected decrypt") })
    }

    @Test fun characterBudgetIncludesBothCiphertextAndPlaintext() {
        val cache = AgentEncryptedRowCache(maxCharacters = 12, maxEntryCharacters = 12)
        cache.read("db", "one", "12345") { "secret" }
        val old = buffers(cache).single()
        cache.read("db", "two", "12345") { "secret" }
        assertEquals(1, buffers(cache).size)
        assertWiped(old)
    }

    @Test fun oversizedRowsAreReturnedButNeverRetained() {
        val cache = AgentEncryptedRowCache(maxEntryCharacters = 8)
        repeat(2) { assertEquals("secret", cache.read("db", "key", "cipher") { "secret" }) }
        assertTrue(buffers(cache).isEmpty())
    }

    @Test fun namespaceAndKeyInvalidationWipeOnlyTheirRows() {
        val cache = AgentEncryptedRowCache()
        cache.read("db", "one", "cipher") { "one" }
        cache.read("db", "two", "cipher") { "two" }
        cache.read("other", "one", "cipher") { "other" }
        val original = buffers(cache)
        cache.invalidate("db", listOf("one"))
        assertWiped(original[0])
        cache.clearStorage("db")
        assertWiped(original[1])
        assertEquals("other", String(original[2]))
        assertEquals("other", cache.read("other", "one", "cipher") { error("Unexpected decrypt") })
    }

    @Test fun runtimeBoundaryWipesPlaintextAndForcesNewDecrypt() {
        val cache = AgentEncryptedRowCache()
        cache.read("db", "key", "cipher") { "secret" }
        val old = buffers(cache).single()
        RuntimeSensitiveCaches.clearAll()
        assertWiped(old)
        assertTrue(buffers(cache).isEmpty())
        assertEquals("fresh", cache.read("db", "key", "cipher") { "fresh" })
    }

    @Test fun runtimeWipeDuringDecryptCannotRepopulateCache() {
        val cache = AgentEncryptedRowCache()
        val started = CountDownLatch(1)
        val resume = CountDownLatch(1)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val read = worker.submit<String?> {
                cache.read("db", "key", "cipher") {
                    started.countDown()
                    check(resume.await(5, TimeUnit.SECONDS))
                    "secret"
                }
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            RuntimeSensitiveCaches.clearAll()
            resume.countDown()
            assertEquals("secret", read.get(5, TimeUnit.SECONDS))
            assertTrue(buffers(cache).isEmpty())
        } finally {
            resume.countDown()
            worker.shutdownNow()
        }
    }

    @Test fun mutationFencesAnOlderReadOrWritePublication() {
        val cache = AgentEncryptedRowCache()
        val oldRevision = cache.invalidate("db", listOf("key"))
        val newRevision = cache.invalidate("db", listOf("key"))
        cache.publish("db", "key", "new cipher", "new", newRevision)
        val current = buffers(cache).single()
        cache.publish("db", "key", "old cipher", "old", oldRevision)
        assertEquals("new", cache.read("db", "key", "new cipher") { error("Unexpected decrypt") })
        assertEquals("new", String(current))
    }

    @Test fun committedPublicationAvoidsReadBackDecryptionButCannotSurviveWipe() {
        val cache = AgentEncryptedRowCache()
        val revision = cache.invalidate("db", listOf("key"))
        cache.publish("db", "key", "cipher", "committed", revision)
        assertEquals("committed", cache.read("db", "key", "cipher") { error("Unexpected decrypt") })
        val old = buffers(cache).single()
        cache.clearSensitive()
        cache.publish("db", "key", "cipher", "committed", revision)
        assertTrue(buffers(cache).isEmpty())
        assertWiped(old)
    }

    private fun buffers(cache: AgentEncryptedRowCache): List<CharArray> {
        val field = AgentEncryptedRowCache::class.java.getDeclaredField("values").apply { isAccessible = true }
        return (field.get(cache) as Map<*, *>).values.map { value ->
            value!!.javaClass.getDeclaredField("plaintext").apply { isAccessible = true }.get(value) as CharArray
        }
    }

    private fun assertWiped(buffer: CharArray) = assertTrue(buffer.all { it == '\u0000' })
}
