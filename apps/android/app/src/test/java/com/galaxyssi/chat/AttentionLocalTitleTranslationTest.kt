package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AttentionLocalTitleTranslationTest {
    private val english = "Model 2.1 released with 20% lower latency"
    private val chinese = "Model 2.1 \u53d1\u5e03\uff0c\u5ef6\u8fdf\u964d\u4f4e 20%"
    private class Fake : AttentionTitleTranslator {
        var ready = true
        var closed = false
        val seen = mutableListOf<String>()
        var generate: suspend (String) -> String = { "\u65b0\u529f\u80fd\u53d1\u5e03" }
        override suspend fun isReady() = ready
        override suspend fun translate(title: String): String { seen += title; return generate(title) }
        override fun close() { closed = true }
    }
    private class Fixture {
        val cache = mutableMapOf<String, String>()
        val fake = Fake()
        var created = 0
        var downloads = 0
        fun pipeline(batch: Long = 12_000, title: Long = 3_000) = AttentionLocalTitleTranslation(
            { created++; fake }, { cache[it].orEmpty() }, { original, text -> cache[original] = text },
            { downloads++ }, batch, title)
    }

    @Test fun cachedTitlesNeverCreateATranslatorOrDownload() = runBlocking {
        val f = Fixture().apply { cache[english] = chinese }
        assertTrue(f.pipeline().translate(mapOf("a" to english)).remaining.isEmpty())
        assertEquals(0, f.created)
        assertEquals(0, f.downloads)
        assertEquals(chinese, f.cache[english])
    }

    @Test fun emptyBatchDoesNotInitializeTheSdk() = runBlocking {
        val f = Fixture()
        assertEquals(0, f.pipeline().translate(emptyMap()).translated)
        assertEquals(0, f.created)
    }

    @Test fun missingModelRequestsDownloadAndImmediatelyReturnsFallback() = runBlocking {
        val f = Fixture().apply { fake.ready = false }
        val titles = mapOf("a" to english, "b" to "New feature")
        val result = f.pipeline().translate(titles)
        assertEquals(titles, result.remaining)
        assertEquals("model_pending", result.reason)
        assertEquals(1, f.downloads)
        assertTrue(f.fake.seen.isEmpty())
        assertTrue(f.fake.closed)
    }

    @Test fun validLocalTranslationDoesNotNeedModelFallback() = runBlocking {
        val f = Fixture().apply { fake.generate = { chinese } }
        val result = f.pipeline().translate(mapOf("a" to english))
        assertTrue(result.remaining.isEmpty())
        assertEquals(1, result.translated)
        assertEquals(chinese, f.cache[english])
        assertEquals(0, f.downloads)
        assertTrue(f.fake.closed)
    }

    @Test fun onlyInvalidResultsArePassedToFallback() = runBlocking {
        val f = Fixture().apply { fake.generate = { if (it == english) chinese else it } }
        val result = f.pipeline().translate(mapOf("a" to english, "b" to "Rhino MCP"))
        assertEquals(mapOf("b" to "Rhino MCP"), result.remaining)
        assertEquals("missing_chinese_text", result.reason)
        assertEquals(1, result.translated)
        assertEquals(1, f.cache.size)
    }

    @Test fun changedVersionsAndNumbersAreNotCached() = runBlocking {
        val f = Fixture().apply { fake.generate = { chinese.replace("2.1", "2.2") } }
        val result = f.pipeline().translate(mapOf("a" to english))
        assertEquals("numbers_not_preserved", result.reason)
        assertEquals(mapOf("a" to english), result.remaining)
        assertTrue(f.cache.isEmpty())
    }

    @Test fun markupOrEmptyResultsFallBack() = runBlocking {
        for (invalid in listOf("", "**$chinese**", "$chinese https://example.org", "$chinese\nmore")) {
            val f = Fixture().apply { fake.generate = { invalid } }
            assertEquals(1, f.pipeline().translate(mapOf("a" to english)).remaining.size)
            assertTrue(f.cache.isEmpty())
        }
    }

    @Test fun engineFailureRetainsAlreadySavedProgress() = runBlocking {
        val f = Fixture().apply { fake.generate = { if (it == english) chinese else error("engine") } }
        val result = f.pipeline().translate(mapOf("a" to english, "b" to "New feature"))
        assertEquals(mapOf("b" to "New feature"), result.remaining)
        assertEquals(1, result.translated)
        assertEquals(chinese, f.cache[english])
        assertTrue(f.fake.closed)
    }

    @Test fun unavailableSdkIsAFallbackNotAnAgentFailure() = runBlocking {
        val pipeline = AttentionLocalTitleTranslation({ error("sdk") }, { "" }, { _, _ -> fail() }, { fail() })
        assertEquals(mapOf("a" to english), pipeline.translate(mapOf("a" to english)).remaining)
    }

    @Test fun cancellationIsNotSwallowedIntoCloudFallback() = runBlocking {
        val f = Fixture().apply { fake.generate = { throw CancellationException("stopped") } }
        try { f.pipeline().translate(mapOf("a" to english)); fail("Cancellation must propagate") }
        catch (_: CancellationException) { assertTrue(f.fake.closed) }
        assertTrue(f.cache.isEmpty())
    }

    @Test fun perTitleTimeoutAllowsNextTitleAndClosesTheEngine() = runBlocking {
        val f = Fixture().apply { fake.generate = { if (it == english) delay(10_000); "\u65b0\u529f\u80fd" } }
        val result = f.pipeline(title = 50).translate(mapOf("a" to english, "b" to "New feature"))
        assertEquals(mapOf("a" to english), result.remaining)
        assertEquals(1, result.translated)
        assertTrue(f.fake.closed)
    }

    @Test fun batchTimeoutRetainsRemainingTitlesAndClosesTheEngine() = runBlocking {
        val f = Fixture().apply { fake.generate = { delay(10_000); chinese } }
        val result = f.pipeline(batch = 50, title = 5_000).translate(mapOf("a" to english))
        assertEquals("timeout", result.reason)
        assertEquals(mapOf("a" to english), result.remaining)
        assertTrue(f.fake.closed)
    }

    @Test fun knownCachedTranslationsAreNotOverwrittenByLocalModel() = runBlocking {
        val f = Fixture().apply { cache[english] = chinese }
        val result = f.pipeline().translate(mapOf("cached" to english, "new" to "New feature"))
        assertTrue(result.remaining.isEmpty())
        assertEquals(listOf("New feature"), f.fake.seen)
        assertEquals(chinese, f.cache[english])
    }
}
