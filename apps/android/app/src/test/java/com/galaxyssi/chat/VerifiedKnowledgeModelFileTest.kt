package com.galaxyssi.chat

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.CancellationException

class VerifiedKnowledgeModelFileTest {
    @get:Rule val folder = TemporaryFolder()
    private val bytes = "verified-model-bytes".toByteArray()
    private val hash get() = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun target() = File(folder.root, "model.gguf")
    private fun artifact() = VerifiedKnowledgeModelFile(target(), bytes.size.toLong(), hash)
    private fun response(body: ByteArray) = MockResponse().setBody(Buffer().write(body))
    @Test fun importsOnlyVerifiedBytesAndPreservesExistingModelOnFailure() {
        val model = artifact()
        model.importFile(bytes.inputStream())
        assertArrayEquals(bytes, target().readBytes())
        assertThrows(IOException::class.java) { model.importFile(ByteArray(bytes.size).inputStream()) }
        assertArrayEquals(bytes, target().readBytes())
        assertEquals(listOf("model.gguf"), folder.root.list()!!.toList())
    }
    @Test fun oversizedAndIncompleteImportsNeverReplaceAnInstalledModel() {
        val model = artifact()
        model.importFile(bytes.inputStream())
        assertThrows(IOException::class.java) { model.importFile((bytes + byteArrayOf(1)).inputStream()) }
        assertThrows(IOException::class.java) { model.importFile(bytes.take(3).toByteArray().inputStream()) }
        assertArrayEquals(bytes, target().readBytes())
    }
    @Test fun resumesAcrossSourcesFromExactlyThePersistedOffset() {
        MockWebServer().use { server ->
            server.enqueue(response(bytes.copyOfRange(0, 5)))
            server.enqueue(response(bytes.copyOfRange(5, bytes.size)).setResponseCode(206)
                .setHeader("Content-Range", "bytes 5-${bytes.lastIndex}/${bytes.size}"))
            server.start()
            artifact().download(listOf(server.url("/first").toString(), server.url("/mirror").toString()))
            assertArrayEquals(bytes, target().readBytes())
            assertNull(server.takeRequest().getHeader("Range"))
            assertEquals("bytes=5-", server.takeRequest().getHeader("Range"))
        }
    }
    @Test fun rangeIgnoredByServerRestartsWithoutDuplicatingThePrefix() {
        File(folder.root, "model.gguf.part").writeBytes(bytes.copyOfRange(0, 5))
        MockWebServer().use { server ->
            server.enqueue(response(bytes)); server.start()
            artifact().download(listOf(server.url("/model").toString()))
            assertArrayEquals(bytes, target().readBytes())
        }
    }
    @Test fun invalidRangeFallsBackWithoutAppendingWrongBytes() {
        File(folder.root, "model.gguf.part").writeBytes(bytes.copyOfRange(0, 5))
        MockWebServer().use { server ->
            server.enqueue(response(bytes).setResponseCode(206).setHeader("Content-Range", "bytes 2-3/99"))
            server.enqueue(response(bytes)); server.start()
            artifact().download(List(2) { server.url("/model").toString() })
            assertArrayEquals(bytes, target().readBytes())
        }
    }
    @Test fun checksumMismatchDiscardsOnlyThePartialAndTriesAnotherSource() {
        artifact().importFile(bytes.inputStream())
        MockWebServer().use { server ->
            server.enqueue(response(ByteArray(bytes.size)))
            server.enqueue(response(bytes)); server.start()
            artifact().download(List(2) { server.url("/model").toString() })
            assertArrayEquals(bytes, target().readBytes())
            assertFalse(File(folder.root, "model.gguf.part").exists())
        }
    }
    @Test fun cancellationPreservesResumableBytesButDoesNotActivateThem() {
        MockWebServer().use { server ->
            server.enqueue(response(bytes)); server.start()
            var cancelled = false
            assertThrows(CancellationException::class.java) {
                artifact().download(listOf(server.url("/model").toString()), { cancelled }) { if (it > 0) cancelled = true }
            }
            assertFalse(target().exists())
            assertEquals(bytes.size.toLong(), artifact().partialBytes())
            artifact().download(listOf(server.url("/model").toString()))
            assertArrayEquals(bytes, target().readBytes())
            assertEquals(1, server.requestCount)
        }
    }
    @Test fun httpErrorDoesNotDamageAnExistingInstallation() {
        artifact().importFile(bytes.inputStream())
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(403)); server.start()
            assertThrows(KnowledgeModelDownloadRejected::class.java) { artifact().download(listOf(server.url("/model").toString())) }
            assertArrayEquals(bytes, target().readBytes())
        }
    }
    @Test fun temporaryHttpFailuresAreRetryableButBadChecksumsAreNot() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(503))
            server.enqueue(response(ByteArray(bytes.size)))
            server.start()
            val temporary = assertThrows(IOException::class.java) { artifact().download(listOf(server.url("/model").toString())) }
            assertFalse(temporary is KnowledgeModelDownloadRejected)
            assertThrows(KnowledgeModelDownloadRejected::class.java) { artifact().download(listOf(server.url("/model").toString())) }
            assertFalse(target().exists())
        }
    }
}
