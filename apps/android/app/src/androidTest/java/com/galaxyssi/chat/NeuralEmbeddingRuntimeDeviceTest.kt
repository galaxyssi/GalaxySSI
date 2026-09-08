package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.llama.GalaxySSIEmbeddingRuntime
import com.galaxyssi.llama.GalaxySSILlamaRuntime
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NeuralEmbeddingRuntimeDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun model(): File {
        val model = File(context.getExternalFilesDir(null), "embedding-test/bge-small-zh-v1.5-q8_0.gguf")
        assumeTrue("Install the pinned external embedding test model", model.isFile)
        val digest = MessageDigest.getInstance("SHA-256")
        model.inputStream().use { stream ->
            val buffer = ByteArray(65536)
            try {
                while (true) { val count = stream.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
            } finally { buffer.fill(0) }
        }
        assertEquals("5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039",
            digest.digest().joinToString("") { "%02x".format(it) })
        return model
    }

    private fun cosine(a: FloatArray, b: FloatArray): Double = a.indices.sumOf { a[it].toDouble() * b[it] }

    @Test fun chineseParaphrasesRankAboveUnrelatedPassagesWithRealNeuralVectors() {
        val model = model()
        val loadStart = SystemClock.elapsedRealtime()
        GalaxySSIEmbeddingRuntime.open(context, model).use { runtime ->
            val loadMs = SystemClock.elapsedRealtime() - loadStart
            // Distinct meanings, including low lexical overlap; no fake embeddings or network inference.
            val passages = listOf(
                "\u624b\u673a\u4e22\u5931\u540e\u53ef\u4ee5\u901a\u8fc7\u5b9a\u4f4d\u529f\u80fd\u67e5\u627e\u8bbe\u5907",
                "\u4fee\u6539\u767b\u5f55\u5bc6\u7801\u9700\u8981\u5728\u8d26\u53f7\u5b89\u5168\u9875\u9762\u8fdb\u884c",
                "\u6570\u636e\u5e93\u5efa\u7acb\u7d22\u5f15\u53ef\u4ee5\u52a0\u5feb\u67e5\u8be2\u901f\u5ea6",
                "\u5c06\u7167\u7247\u5907\u4efd\u5230\u7535\u8111\u53ef\u4ee5\u907f\u514d\u56fe\u7247\u4e22\u5931",
                "\u5916\u51fa\u65c5\u884c\u524d\u5e94\u5173\u6ce8\u76ee\u7684\u5730\u7684\u964d\u96e8\u548c\u6c14\u6e29",
                "\u76d1\u542c\u7f51\u7edc\u6062\u590d\u4e8b\u4ef6\u540e\u7ee7\u7eed\u672a\u5b8c\u6210\u7684\u6587\u4ef6\u4f20\u8f93"
            )
            val queries = listOf(
                "\u6211\u7684\u7535\u8bdd\u627e\u4e0d\u5230\u4e86\u600e\u4e48\u529e",
                "\u600e\u6837\u66f4\u6362\u8d26\u6237\u53e3\u4ee4",
                "\u600e\u6837\u8ba9SQL\u68c0\u7d22\u66f4\u5feb",
                "\u5982\u4f55\u9632\u6b62\u76f8\u518c\u5185\u5bb9\u6c38\u4e45\u6d88\u5931",
                "\u51fa\u6e38\u8981\u4e0d\u8981\u5e26\u4f1e\u548c\u539a\u8863\u670d",
                "\u65ad\u7f51\u4ee5\u540e\u4e0b\u8f7d\u4efb\u52a1\u600e\u4e48\u7eed\u4f20"
            )
            val vectors = passages.map(runtime::embed)
            val times = mutableListOf<Long>()
            try {
                queries.forEachIndexed { expected, query ->
                    val started = SystemClock.elapsedRealtime()
                    val vector = runtime.embed(query)
                    times += SystemClock.elapsedRealtime() - started
                    try {
                        assertEquals(512, vector.size)
                        assertTrue(vector.all { it.isFinite() })
                        assertEquals(1.0, sqrt(cosine(vector, vector)), 0.0001)
                        val scores = vectors.map { cosine(vector, it) }
                        assertEquals("Query $expected scores=$scores", expected, scores.indices.maxBy { scores[it] })
                    } finally { vector.fill(0f) }
                }
                println("NEURAL_EMBEDDING model=bge-small-zh-v1.5-q8_0 load_ms=$loadMs query_ms=$times recall_at_1=6/6")
                val repeated = LongArray(100) { index ->
                    val started = SystemClock.elapsedRealtime()
                    runtime.embed(queries[index % queries.size]).fill(0f)
                    SystemClock.elapsedRealtime() - started
                }.sorted()
                println("NEURAL_EMBEDDING_HOT samples=100 p50_ms=${repeated[49]} p95_ms=${repeated[94]} " +
                    "p99_ms=${repeated[98]} process_pss_kib=${android.os.Debug.getPss()}")
                assertTrue("Short-query embedding P95 exceeds 500 ms", repeated[94] < 500)
            } finally { vectors.forEach { it.fill(0f) } }
        }
    }

    @Test fun independentInstancesAndChatUnloadCannotInvalidateEachOther() {
        val model = model()
        GalaxySSIEmbeddingRuntime.open(context, model).use { first ->
            val expected = first.embed("\u5de5\u4f5c\u533a\u6062\u590d")
            try {
                GalaxySSIEmbeddingRuntime.open(context, model).use { second ->
                    GalaxySSILlamaRuntime.unload()
                    val actual = second.embed("\u5de5\u4f5c\u533a\u6062\u590d")
                    try { assertArrayEquals(expected, actual, 0.00001f) } finally { actual.fill(0f) }
                }
                val remaining = first.embed("\u5de5\u4f5c\u533a\u6062\u590d")
                try { assertArrayEquals(expected, remaining, 0.00001f) } finally { remaining.fill(0f) }
            } finally { expected.fill(0f) }
        }
    }

    @Test fun rejectsInvalidInputWithoutPoisoningNextRequestAndClosesIdempotently() {
        val runtime = GalaxySSIEmbeddingRuntime.open(context, model())
        try {
            assertThrows(IllegalArgumentException::class.java) { runtime.embed("   ") }
            assertThrows(IllegalStateException::class.java) { runtime.embed("\u6570\u636e\u5e93".repeat(700)) }
            val emoji = runtime.embed("\u6d4b\u8bd5\uD83D\uDE80\u0000\u9644\u4ef6")
            try { assertEquals(512, emoji.size) } finally { emoji.fill(0f) }
        } finally { runtime.close(); runtime.close() }
        assertThrows(IllegalStateException::class.java) { runtime.embed("closed") }
        GalaxySSIEmbeddingRuntime.open(context, model()).use { it.embed("\u91cd\u65b0\u6253\u5f00").fill(0f) }
    }

    @Test fun concurrentCloseAndInferenceCannotUseFreedNativeState() {
        val runtime = GalaxySSIEmbeddingRuntime.open(context, model())
        val pool = Executors.newFixedThreadPool(2)
        try {
            val calls = (1..12).map {
                pool.submit(Callable {
                    try { runtime.embed("\u4e92\u65a5\u8bbf\u95ee").fill(0f) }
                    catch (error: IllegalStateException) { assertEquals("Embedding runtime is closed", error.message) }
                })
            }
            pool.submit { runtime.close() }.get(30, TimeUnit.SECONDS)
            calls.forEach { it.get(30, TimeUnit.SECONDS) }
        } finally { pool.shutdownNow(); runtime.close() }
    }

    @Test fun uiThreadAndMissingModelFailBeforeLoadingNativeState() {
        val model = model()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertThrows(IllegalStateException::class.java) { GalaxySSIEmbeddingRuntime.open(context, model) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            GalaxySSIEmbeddingRuntime.open(context, File(context.cacheDir, "missing-embedding-${System.nanoTime()}"))
        }
        assertThrows(IllegalArgumentException::class.java) { GalaxySSIEmbeddingRuntime.open(context, model, threads = 0) }
        assertThrows(IllegalStateException::class.java) { GalaxySSIEmbeddingRuntime.open(context, model, contextTokens = 1024) }
        val corrupt = File.createTempFile("invalid-embedding-", ".gguf", context.cacheDir)
        try {
            corrupt.writeBytes(byteArrayOf(0, 1, 2, 3))
            assertThrows(IllegalStateException::class.java) { GalaxySSIEmbeddingRuntime.open(context, corrupt) }
        } finally { corrupt.delete() }
        GalaxySSIEmbeddingRuntime.open(context, model).use { it.embed("\u5931\u8d25\u540e\u6062\u590d").fill(0f) }
    }
}
