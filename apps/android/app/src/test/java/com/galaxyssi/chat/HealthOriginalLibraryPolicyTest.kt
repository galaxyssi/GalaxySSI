package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthOriginalLibraryPolicyTest {
    private fun original(name: String = "report.pdf", mime: String = "application/pdf") = HealthOriginal("12345678-1234-1234-1234-123456789abc", "12345678-1234-1234-1234-123456789def", name, mime, 5, "a".repeat(64), 1, "x", "file")
    @Test fun imageAndPdfClassificationUsesActualMimeRatherThanAPrettyFilename() {
        assertEquals(HealthOriginalKind.PDF, HealthOriginalKind.of(original("photo.jpg")))
        assertEquals(HealthOriginalKind.IMAGE, HealthOriginalKind.of(original("report.pdf", "image/jpeg")))
    }
    @Test fun structuredFormatsShareATableFilterAndUnknownFilesRemainOther() {
        for ((name, mime) in listOf("a.csv" to "text/csv", "a.json" to "application/json", "a.xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
            assertEquals(HealthOriginalKind.TABLE, HealthOriginalKind.of(original(name, mime)))
        assertEquals(HealthOriginalKind.OTHER, HealthOriginalKind.of(original("archive.zip", "application/zip")))
    }
    @Test fun calendarFiltersIncludeTheWholeLastDateAcrossDst() {
        val query = HealthLibraryFilter.dates(LocalDate.of(2026, 3, 7), LocalDate.of(2026, 3, 9), ZoneId.of("America/New_York"))
        assertEquals(71 * 3_600_000L, query.until - query.from)
    }
    @Test fun reversedAndEmptyIntervalsAreRejectedNotSilentlySwapped() {
        assertTrue(runCatching { HealthLibraryFilter(from = 5, until = 5) }.isFailure)
        assertTrue(runCatching { HealthLibraryFilter(from = -1) }.isFailure)
        assertTrue(runCatching { HealthLibraryFilter.dates(LocalDate.of(2026, 2, 2), LocalDate.of(2026, 2, 1), ZoneId.of("UTC")) }.isFailure)
    }
    @Test fun entryNamesCannotEscapeTheirOriginalIdDirectory() {
        val entry = HealthOriginalArchiveNames.entry(original("../../C:\\private\n.jpg"))
        assertEquals(3, entry.split('/').size); assertFalse(entry.contains('\\')); assertFalse(entry.contains('\n'))
        assertTrue(entry.startsWith("originals/12345678-1234-1234-1234-123456789abc/"))
    }
    @Test fun blankAndDotNamesHaveSafeFallbacksAndExtensionsAreNotInvented() {
        for (name in listOf("", ".", "..", "  ")) assertTrue(HealthOriginalArchiveNames.entry(original(name)).endsWith("/document"))
        assertTrue(HealthOriginalArchiveNames.entry(original("sample.heif")).endsWith("/sample.heif"))
    }
    @Test fun duplicateNamesRemainDistinctByOriginalIdentity() {
        val first = original(); val second = first.copy(id = "12345678-1234-1234-1234-123456789def")
        assertNotEquals(HealthOriginalArchiveNames.entry(first), HealthOriginalArchiveNames.entry(second))
    }
    @Test fun invalidIdentityDoesNotBecomeAZipPath() {
        assertTrue(runCatching { HealthOriginalArchiveNames.entry(original().copy(id = "../../escape")) }.isFailure)
    }
    @Test fun epochDateInAnEasternTimezoneDoesNotCrashTheDatePicker() {
        val query = HealthLibraryFilter.dates(LocalDate.of(1970, 1, 1), LocalDate.of(1970, 1, 1), ZoneId.of("Asia/Shanghai"))
        assertEquals(0L, query.from); assertTrue(query.until > query.from)
    }
    @Test fun emptyOrStillRunningWorkIsNotMisreportedAsATerminalFailure() {
        assertFalse(HealthOriginalExportScheduler.terminal(emptyList()))
        assertFalse(HealthOriginalExportScheduler.terminal(listOf(androidx.work.WorkInfo.State.RUNNING)))
        assertFalse(HealthOriginalExportScheduler.terminal(listOf(androidx.work.WorkInfo.State.FAILED, androidx.work.WorkInfo.State.ENQUEUED)))
        assertTrue(HealthOriginalExportScheduler.terminal(listOf(androidx.work.WorkInfo.State.FAILED)))
        assertTrue(HealthOriginalExportScheduler.terminal(listOf(androidx.work.WorkInfo.State.CANCELLED)))
    }
    @Test fun longNamesRetainTheirExtensionWithoutSplittingUnicodePairs() {
        val name = "a".repeat(174) + "\ud83d\ude00" + "b".repeat(15) + ".jpeg"
        val entry = HealthOriginalArchiveNames.entry(original(name))
        assertTrue(entry.endsWith(".jpeg")); assertTrue(entry.substringAfterLast('/').length <= 180)
        assertFalse(entry.contains("\ud83d.jpeg")); assertEquals(entry, entry.toByteArray(Charsets.UTF_8).toString(Charsets.UTF_8))
    }
    @Test fun windowsReservedNamesAndPunctuationRemainExtractable() {
        assertTrue(HealthOriginalArchiveNames.entry(original("CON.pdf")).endsWith("/_CON.pdf"))
        assertTrue(HealthOriginalArchiveNames.entry(original("a?b*.pdf")).endsWith("/a_b_.pdf"))
    }
}
