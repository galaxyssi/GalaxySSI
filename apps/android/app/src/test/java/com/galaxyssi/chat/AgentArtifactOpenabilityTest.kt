package com.galaxyssi.chat

import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AgentArtifactOpenabilityTest {
    @get:Rule val temporary = TemporaryFolder()
    private val inspector = AgentArtifactOpenability()
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes())
        .joinToString("") { "%02x".format(it) }
    private fun inspect(file: File) = inspector.inspect(file, digest(file))
    private fun zip(name: String, entries: Map<String, String>): File = temporary.newFile(name).also { file ->
        ZipOutputStream(file.outputStream()).use { output -> entries.forEach { (path, text) ->
            output.putNextEntry(ZipEntry(path)); output.write(text.toByteArray()); output.closeEntry()
        } }
    }

    @Test fun actualTextReadIsBoundToItsContentHash() {
        val file = temporary.newFile("report.txt").apply { writeText("verified result") }
        val result = inspect(file)
        assertEquals("verified", result["status"])
        assertEquals("utf8_text_read", result["scope"])
        assertEquals(digest(file), result["sha256"])
        assertEquals("unverified", inspector.inspect(file, "a".repeat(64))["status"])
        file.writeBytes(byteArrayOf(0xc3.toByte(), 0x28))
        assertEquals("unverified", inspect(file)["status"])
    }

    @Test fun archiveMustOpenAndReadItsActualEntries() {
        val file = zip("project.zip", mapOf("report.txt" to "result", "src/main.py" to "print(1)"))
        assertEquals("verified", inspect(file)["status"])
        assertEquals("unverified", inspector.inspect(file, digest(file), maximumExpandedBytes = 1)["status"])
        val unsafe = zip("unsafe.zip", mapOf("../escape" to "payload"))
        assertEquals("unverified", inspect(unsafe)["status"])
        file.writeBytes(file.readBytes().dropLast(30).toByteArray())
        assertEquals("unverified", inspect(file)["status"])
    }

    @Test fun completeSmallTextCanBeReviewedFromTheHashBoundReceipt() {
        val text = "\uFEFFitem,quantity,total\n\u7b14,4,20\n\uD83D\uDD0D,1,0\n"
        val file = temporary.newFile("review.csv").apply { writeText(text) }
        val result = inspect(file)
        val details = result["details"] as Map<*, *>
        assertEquals("verified", result["status"])
        assertEquals(digest(file), result["sha256"])
        assertEquals(true, details["text_complete"])
        assertEquals(text, details["text"])
        assertEquals(text.length.toLong(), details["characters_read"])
    }

    @Test fun largeTextStillFullyValidatesButNeverReturnsAPartialReview() {
        val file = temporary.newFile("large.txt")
        val limit = AgentArtifactOpenability.MAX_REVIEW_TEXT_CHARACTERS
        file.writeText("x".repeat(limit))
        assertEquals(true, (inspect(file)["details"] as Map<*, *>)["text_complete"])
        file.appendText("\uD83D\uDD0D")
        val result = inspect(file)
        val details = result["details"] as Map<*, *>
        assertEquals("verified", result["status"])
        assertEquals((limit + 2).toLong(), details["characters_read"])
        assertEquals(false, details["text_complete"])
        assertFalse(details.containsKey("text"))
        file.appendBytes(byteArrayOf(0xc3.toByte(), 0x28))
        assertEquals("unverified", inspect(file)["status"])
    }

    @Test fun emptyTextIsCompleteButInvalidBytesOrHashNeverExposeReviewEvidence() {
        val file = temporary.newFile("empty.txt")
        assertEquals("", (inspect(file)["details"] as Map<*, *>)["text"])
        assertFalse(inspector.inspect(file, "a".repeat(64)).containsKey("details"))
        file.writeBytes(byteArrayOf(0xc3.toByte(), 0x28))
        assertFalse(inspect(file).containsKey("details"))
    }

    @Test fun officeExtensionAloneDoesNotProveDocumentOpenability() {
        val empty = zip("invalid.docx", mapOf("readme.txt" to "not a Word document"))
        assertEquals("unverified", inspect(empty)["status"])
        val entries = mapOf(
            "[Content_Types].xml" to """<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>""",
            "_rels/.rels" to """<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>""",
            "word/document.xml" to """<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Result</w:t></w:r></w:p></w:body></w:document>""")
        val valid = zip("report.docx", entries)
        assertEquals("verified", inspect(valid)["status"])
        val malformed = zip("malformed.docx", entries + ("word/document.xml" to "<broken"))
        assertEquals("unverified", inspect(malformed)["status"])
        val entity = zip("entity.docx", entries + ("word/document.xml" to """<!DOCTYPE document [<!ENTITY ext SYSTEM "file:///private">]><document>&ext;</document>"""))
        assertEquals("unverified", inspect(entity)["status"])
    }
}
