package com.galaxyssi.chat

import java.io.InputStream
import java.time.LocalDate
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ComposerAttachmentImportTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `copy is independent from original and preserves exact bytes`() {
        val source = temporary.newFile("original").apply { writeBytes(ByteArray(150_003) { it.toByte() }) }
        val expected = source.readBytes()
        val retained = source.inputStream().use {
            ComposerAttachmentImport.copyToPrivate(it, temporary.root, Long.MAX_VALUE, "jpg", LocalDate.of(2026, 10, 10))
        }
        assertEquals("composer-attachments-v1/imported/2026/10", retained.parentFile!!.relativeTo(temporary.root).invariantSeparatorsPath)
        assertTrue(source.delete())
        assertArrayEquals(expected, retained.readBytes())
    }

    @Test fun `unknown length streaming copies empty and large inputs`() {
        for (size in listOf(0, 1, 65536, 65537, 300_001)) {
            val bytes = ByteArray(size) { (it * 7).toByte() }
            val file = ComposerAttachmentImport.copyToPrivate(bytes.inputStream(), temporary.root, size.toLong())
            assertArrayEquals(bytes, file.readBytes())
        }
    }

    @Test fun `size violations never leave a partial attachment`() {
        assertTrue(runCatching {
            ComposerAttachmentImport.copyToPrivate(ByteArray(65537).inputStream(), temporary.root, 65536L)
        }.isFailure)
        assertFalse(temporary.root.walkTopDown().any { it.isFile })
    }

    @Test fun `read failures clean staging files`() {
        val broken = object : InputStream() { override fun read(): Int = error("Provider disconnected") }
        assertTrue(runCatching { ComposerAttachmentImport.copyToPrivate(broken, temporary.root, Long.MAX_VALUE) }.isFailure)
        assertFalse(temporary.root.walkTopDown().any { it.isFile })
    }

    @Test fun `same file name and date never overwrite another attachment`() {
        val files = (1..20).map {
            ComposerAttachmentImport.copyToPrivate(byteArrayOf(it.toByte()).inputStream(), temporary.root, 1, "pdf")
        }
        assertEquals(20, files.map { it.name }.distinct().size)
        files.forEachIndexed { index, file -> assertEquals(index + 1, file.inputStream().use { it.read() }) }
    }
}
