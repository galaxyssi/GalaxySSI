package com.galaxyssi.chat

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.apache.commons.compress.archivers.zip.ZipFile
import org.apache.commons.compress.utils.SeekableInMemoryByteChannel
import org.junit.Assert.*
import org.junit.Test

class HealthXlsxWorkbookFactoryTest {
    private fun bytes(): ByteArray {
        val rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        val parts = mapOf(
            "[Content_Types].xml" to "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/></Types>",
            "xl/workbook.xml" to "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"$rel\"><workbookPr date1904=\"1\"/><sheets><sheet name=\"Home\" sheetId=\"1\" r:id=\"sheet\"/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"sheet\" Target=\"worksheets/sheet1.xml\" Type=\"$rel/worksheet\"/></Relationships>",
            "xl/worksheets/sheet1.xml" to "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"
        )
        return ByteArrayOutputStream().use { output ->
            ZipOutputStream(output).use { zip -> parts.forEach { (name, value) -> zip.putNextEntry(ZipEntry(name)); zip.write(value.toByteArray()); zip.closeEntry() } }
            output.toByteArray()
        }
    }
    @Test fun pinnedConstructorsAcceptASeekableZipPackageWithoutFileOrInputStreamFallback() {
        val channel = SeekableInMemoryByteChannel(bytes())
        ZipFile(channel).use { zip -> HealthXlsxWorkbookFactory.open(zip).use { book ->
            assertTrue(book.isDate1904); assertEquals("Home", book.firstSheet.name)
            book.firstSheet.openStream().use { assertEquals(0L, it.count()) }
            assertTrue(channel.isOpen)
        } }
        assertFalse(channel.isOpen)
    }
    @Test fun failedPackageConstructionStillAllowsItsOwnerToCloseTheChannel() {
        val channel = SeekableInMemoryByteChannel(ByteArrayOutputStream().use { output -> ZipOutputStream(output).close(); output.toByteArray() })
        assertTrue(runCatching { ZipFile(channel).use { HealthXlsxWorkbookFactory.open(it).close() } }.isFailure)
        assertFalse(channel.isOpen)
    }
}
