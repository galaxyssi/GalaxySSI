package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.zip.ZipEntry
import org.junit.Assert.*
import org.junit.Test

class HealthXlsxReaderDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(bytes: ByteArray = HealthXlsxFixtures.workbook(), test: (HealthOriginalStore, HealthOriginal, HealthTableStore, String) -> Unit) {
        val token = id(); val originalDb = "health-xlsx-original-$token.db"; val recordDb = "health-xlsx-record-$token.db"
        val root = File(context.cacheDir, "health-xlsx-original-$token")
        try { HealthOriginalStore(context, originalDb, root).use { originals ->
            val original = originals.importOriginal(id(), bytes.inputStream(), "readings.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "file")
            HealthTableStore(context, recordDb).use { tables -> test(originals, original, tables, recordDb) }
            assertTrue(root.walkTopDown().filter(File::isFile).all { it.extension == "ghealth" })
        } } finally { context.deleteDatabase(originalDb); context.deleteDatabase(recordDb); root.deleteRecursively(); bytes.fill(0) }
    }
    private fun catalog(originals: HealthOriginalStore, original: HealthOriginal, tables: HealthTableStore): HealthTableBatch =
        HealthTableImport.stage(originals, original, id(), tables)
    private fun load(originals: HealthOriginalStore, original: HealthOriginal, tables: HealthTableStore, batch: HealthTableBatch,
                     sheet: Int = 0, header: Int = 1): HealthTableBatch {
        tables.configureSheet(batch.id, batch.mappingRevision, sheet, header, true)
        val reading = tables.batch(batch.id)!!; HealthXlsxImport.stage(originals, original, reading, tables)
        return tables.batch(batch.id)!!
    }
    private fun complete(tables: HealthTableStore, id: String) { while (tables.step(id)) Unit }
    private fun validate(tables: HealthTableStore, batch: HealthTableBatch, cache: Boolean = false): HealthTableBatch {
        tables.mapping(batch.id, batch.mappingRevision, batch.mapping.copy(date = HealthTableDate.EXCEL, zone = "UTC", allowFormulaCache = cache), true)
        complete(tables, batch.id); return tables.batch(batch.id)!!
    }
    private fun failure(bytes: ByteArray, expected: String) = fixture(bytes) { originals, original, tables, name ->
        val error = runCatching { catalog(originals, original, tables) }.exceptionOrNull()
        assertTrue(error.toString(), error is HealthImportFailure); assertEquals(expected, (error as HealthImportFailure).code)
        assertTrue(originals.present(original)); HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun actualFastExcelReaderUsesTheAuthenticatedSeekableChannelWithoutAPlaintextFile() = fixture { originals, original, tables, name ->
        val info = catalog(originals, original, tables)
        assertEquals(HealthTableState.SHEET_SELECTION, info.state); assertEquals("Home", info.sheets.single().name)
        val loaded = load(originals, original, tables, info)
        assertEquals(HealthTableState.MAPPING, loaded.state); assertEquals(1L, loaded.rows)
        val row = tables.page(info.id).single().row
        assertEquals("124", row.cells["systolic"]); assertEquals("2026-09-01T12:00", row.excelDates["time"])
        assertEquals("B2", row.addresses["systolic"])
        HealthRecordStore(context, name).use { assertEquals(0L, it.count()) }
    }
    @Test fun bothExcelDateSystemsDecodeToTheActualSameModernTimestamp() {
        for (epoch in listOf(false, true)) fixture(HealthXlsxFixtures.workbook(date1904 = epoch)) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            assertEquals(epoch, loaded.date1904)
            val confirmed = validate(tables, loaded)
            val draft = HealthTablePolicy.evaluate(confirmed, tables.page(loaded.id).single().row).draft!!
            assertEquals(Instant.parse("2026-09-01T12:00:00Z").toEpochMilli(), draft.measuredAt)
            assertTrue(draft.evidence!!.rawText.contains("Excel epoch: ${if (epoch) 1904 else 1900}"))
        }
    }
    @Test fun selectedSheetAndNonfirstHeaderRetainPhysicalRowAddresses() {
        val data = HealthXlsxFixtures.text("A1", "Report title")
        val sheets = listOf("Home" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading()),
            "Lab" to ("<row r=\"1\">$data</row>" + HealthXlsxFixtures.headers(3) + HealthXlsxFixtures.reading(42)))
        fixture(HealthXlsxFixtures.workbook(sheets = sheets)) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables), 1, 3)
            val confirmed = validate(tables, loaded)
            val row = tables.page(loaded.id).single().row
            assertEquals(1L, row.number); assertEquals(42L, row.sourceRow)
            val evidence = HealthTablePolicy.evaluate(confirmed, row).draft!!.evidence!!
            assertEquals("Lab", evidence.tableSheet); assertEquals(2, evidence.page); assertEquals(42L, evidence.tableRow)
        }
    }
    @Test fun formulaCacheNeedsConsentAndItsOriginalExpressionRemainsTraceable() = fixture(
        HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading(formula = true))))) { originals, original, tables, name ->
        val loaded = load(originals, original, tables, catalog(originals, original, tables))
        val checked = validate(tables, loaded)
        assertEquals(1L, tables.counts(loaded.id)[HealthTableRowState.INVALID]); assertEquals("formula_ack", tables.page(loaded.id).single().issue)
        val allowed = validate(tables, checked, true)
        assertEquals(1L, tables.counts(loaded.id)[HealthTableRowState.VALID])
        tables.confirmSave(loaded.id, allowed.mappingRevision); complete(tables, loaded.id)
        HealthRecordStore(context, name).use { records ->
            val record = records.page().records.single(); assertEquals("124", record.draft.values["systolic"])
            assertTrue(record.draft.evidence!!.rawText.contains("B2")); assertTrue(record.draft.evidence!!.rawText.contains("=100+24"))
        }
    }
    @Test fun missingFormulaCacheStaysMissingInsteadOfBeingCalculatedOrFilledWithZero() = fixture(
        HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading(formula = true, cached = false))))) { originals, original, tables, _ ->
        val loaded = load(originals, original, tables, catalog(originals, original, tables))
        validate(tables, loaded, true)
        assertEquals(1L, tables.counts(loaded.id)[HealthTableRowState.MISSING]); assertEquals("formula_cache", tables.page(loaded.id).single().issue)
    }
    @Test fun numericExponentsAreNormalizedWithoutChangingTheirSourceText() = fixture(
        HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading(value = "1.24E2"))))) { originals, original, tables, _ ->
        val loaded = load(originals, original, tables, catalog(originals, original, tables))
        val row = tables.page(loaded.id).single().row
        assertEquals("1.24E2", row.cells["systolic"]); assertEquals("124", row.numbers["systolic"])
        assertEquals("124", HealthTablePolicy.evaluate(validate(tables, loaded), row).draft!!.values["systolic"])
    }
    @Test fun stringsThatLookLikeFormulasAreNeverExecuted() {
        val body = "<row r=\"2\">" + HealthXlsxFixtures.number("A2", "${HealthXlsxFixtures.serial()}.5") +
            HealthXlsxFixtures.text("B2", "=100+24") + HealthXlsxFixtures.number("C2", "82") + HealthXlsxFixtures.text("D2", "mmHg") + "</row>"
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + body)))) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables)); validate(tables, loaded, true)
            assertEquals("number", tables.page(loaded.id).single().issue)
        }
    }
    @Test fun fictitiousExcelLeapDayIsNotSilentlyRewrittenAsMarchFirst() {
        val body = "<row r=\"2\">" + HealthXlsxFixtures.number("A2", "60.5") + HealthXlsxFixtures.number("B2", "124") +
            HealthXlsxFixtures.number("C2", "82") + HealthXlsxFixtures.text("D2", "mmHg") + "</row>"
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + body)))) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            val row = tables.page(loaded.id).single().row
            assertEquals("60.5", row.cells["time"]); assertNull(row.excelDates["time"])
            assertNull(HealthTablePolicy.evaluate(validate(tables, loaded), row).draft)
        }
    }
    @Test fun sharedStringTableUsesRealColumnNamesAndValues() {
        val ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        val strings = "<sst xmlns=\"$ns\" count=\"5\" uniqueCount=\"5\">" + listOf("time", "systolic", "diastolic", "unit", "mmHg").joinToString("") { "<si><t>$it</t></si>" } + "</sst>"
        val header = "<row r=\"1\">" + (0..3).joinToString("") { "<c r=\"${'A' + it}1\" t=\"s\"><v>$it</v></c>" } + "</row>"
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (header + HealthXlsxFixtures.reading())), sharedStrings = strings)) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            assertEquals(listOf("time", "systolic", "diastolic", "unit"), loaded.headers)
        }
    }
    @Test fun sourceRowsOnDifferentSheetsDoNotCollideAndReimportsRemainIdempotent() = fixture(
        HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading()),
            "Lab" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading(value = "130"))))) { originals, original, tables, name ->
        for (sheet in listOf(0, 1, 0)) {
            val ready = validate(tables, load(originals, original, tables, catalog(originals, original, tables), sheet))
            tables.confirmSave(ready.id, ready.mappingRevision); complete(tables, ready.id)
        }
        HealthRecordStore(context, name).use { records ->
            assertEquals(2L, records.count()); assertEquals(setOf("Home", "Lab"), records.page().records.map { it.draft.evidence!!.tableSheet }.toSet())
        }
    }
    @Test fun changingSheetCannotEraseConfirmedBatchOwnership() = fixture { originals, original, tables, _ ->
        val ready = validate(tables, load(originals, original, tables, catalog(originals, original, tables)))
        tables.confirmSave(ready.id, ready.mappingRevision); complete(tables, ready.id)
        assertTrue(runCatching { tables.configureSheet(ready.id, ready.mappingRevision, 0, 1) }.isFailure)
        tables.undo(ready.id); complete(tables, ready.id); assertEquals(1L, tables.counts(ready.id)[HealthTableRowState.UNDONE])
    }
    @Test fun interruptedReadingResumesOnlyUncommittedRows() {
        val body = HealthXlsxFixtures.headers() + (2..86).joinToString("") { HealthXlsxFixtures.reading(it, value = (100 + it).toString()) }
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("Home" to body))) { originals, original, tables, _ ->
            val info = catalog(originals, original, tables)
            tables.configureSheet(info.id, info.mappingRevision, 0, 1, true)
            var chunks = 0
            assertTrue(runCatching { HealthXlsxImport.stage(originals, original, tables.batch(info.id)!!, tables,
                progress = { if (++chunks == 1) throw CancellationException() }) }.isFailure)
            assertEquals(30L, tables.batch(info.id)!!.rows)
            HealthXlsxImport.stage(originals, original, tables.batch(info.id)!!, tables)
            assertEquals(85L, tables.batch(info.id)!!.rows); assertEquals(HealthTableState.MAPPING, tables.batch(info.id)!!.state)
        }
    }
    @Test fun cancelledAndReconfiguredReadRejectsLateRowsFromTheOldSheet() = fixture { originals, original, tables, _ ->
        val info = catalog(originals, original, tables)
        tables.configureSheet(info.id, info.mappingRevision, 0, 1, true)
        val reading = tables.batch(info.id)!!; tables.cancelReading(reading.id, reading.mappingRevision)
        assertTrue(runCatching { HealthXlsxImport.stage(originals, original, reading, tables) }.isFailure)
        assertEquals(HealthTableState.SHEET_SELECTION, tables.batch(info.id)!!.state); assertTrue(tables.page(info.id).isEmpty())
    }
    @Test fun expandedArchiveBudgetPreventsZipBombsBeforeReadingTheWorkbook() {
        val bytes = HealthXlsxFixtures.workbook(writer = { zip ->
            zip.putNextEntry(ZipEntry("padding.bin")); val buffer = ByteArray(64 * 1024)
            repeat(1025) { zip.write(buffer) }; zip.closeEntry()
        })
        failure(bytes, "xlsx_expansion")
    }
    @Test fun metadataSizeIsBoundedBeforeBuildingTheSharedStringsTable() {
        val xml = "<root>" + (1..1100).joinToString("") { "<t>${"x".repeat(4096)}</t>" } + "</root>"
        failure(HealthXlsxFixtures.workbook(extras = mapOf("xl/metadata.xml" to xml)), "xlsx_metadata")
    }
    @Test fun externalEntityDeclarationsAreRejectedWithoutLoadingExternalContent() =
        failure(HealthXlsxFixtures.workbook(extras = mapOf("xl/unsafe.xml" to "<!DOCTYPE r [<!ENTITY x SYSTEM 'file:///nonexistent-private-file'>]><r>&x;</r>")), "xlsx_xml")
    @Test fun macroAndTraversalPartsAreNotExecutedOrExtracted() {
        failure(HealthXlsxFixtures.workbook(extras = mapOf("xl/vbaProject.bin" to "unused")), "xlsx_macro")
        failure(HealthXlsxFixtures.workbook(extras = mapOf("../outside.xml" to "<r/>")), "xlsx_package")
    }
    @Test fun forgedCellRowsAndHugeColumnsCannotRedirectSourceEvidence() {
        val forged = "<row r=\"2\">${HealthXlsxFixtures.number("A99", "124")}</row>"
        failure(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + forged))), "xlsx_address")
        val wide = "<row r=\"2\">${HealthXlsxFixtures.number("XFD2", "124")}</row>"
        failure(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + wide))), "table_columns")
    }
    @Test fun malformedOrEncryptedContainersRemainOriginalsNotInventedMeasurements() = failure("not a zip workbook".toByteArray(), "xlsx_format")
    @Test fun numericHeaderRowRequiresChoosingTheActualTextHeaderInsteadOfDroppingAReading() = fixture(
        HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.reading(1) + HealthXlsxFixtures.headers(3) + HealthXlsxFixtures.reading(4))))) { originals, original, tables, _ ->
        val info = catalog(originals, original, tables)
        assertTrue(runCatching { load(originals, original, tables, info) }.isFailure)
        val failed = tables.batch(info.id)!!; tables.cancelReading(failed.id, failed.mappingRevision)
        assertEquals(1L, load(originals, original, tables, tables.batch(info.id)!!, header = 3).rows)
    }
    @Test fun booleanFormulaCacheCannotBecomeANumericMeasurement() {
        val body = "<row r=\"2\">" + HealthXlsxFixtures.number("A2", "${HealthXlsxFixtures.serial()}.5") +
            "<c r=\"B2\" t=\"b\"><f>1=1</f><v>1</v></c>" + HealthXlsxFixtures.number("C2", "82") + HealthXlsxFixtures.text("D2", "mmHg") + "</row>"
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + body)))) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            val row = tables.page(loaded.id).single().row
            assertEquals("true", row.cells["systolic"]); assertNull(row.numbers["systolic"])
            validate(tables, loaded, true); assertEquals("number", tables.page(loaded.id).single().issue)
        }
    }
    private fun isoReading(row: Int, value: String, formula: String? = null, systolic: String = HealthXlsxFixtures.number("B$row", "124")) =
        "<row r=\"$row\"><c r=\"A$row\" t=\"d\">${formula?.let { "<f>$it</f>" }.orEmpty()}<v>$value</v></c>" +
            systolic + HealthXlsxFixtures.number("C$row", "82") + HealthXlsxFixtures.text("D$row", "mmHg") + "</row>"

    private fun isoWorkbook(body: String) = HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + body)))

    @Test fun isoTypedDateCanBePreviewedMappedAndSavedWithoutRewritingTheEncryptedOriginal() {
        val raw = "2026-09-01T12:34:56.789+08:00"
        val bytes = isoWorkbook(isoReading(2, raw))
        fixture(bytes) { originals, original, tables, name ->
            assertEquals(raw, HealthXlsxReader.preview(originals, original, null) {}.rows.last().cells.first())
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            val row = tables.page(loaded.id).single().row
            assertEquals(raw, row.cells["time"]); assertEquals("A2", row.addresses["time"])
            assertTrue(row.formulas.isEmpty()); assertFalse(row.numbers.containsKey("time"))
            tables.mapping(loaded.id, loaded.mappingRevision, loaded.mapping.copy(zone = "UTC"), true)
            complete(tables, loaded.id)
            val ready = tables.batch(loaded.id)!!
            assertEquals(1L, tables.counts(loaded.id)[HealthTableRowState.VALID])
            tables.confirmSave(loaded.id, ready.mappingRevision)
            complete(tables, loaded.id)
            HealthRecordStore(context, name).use { records ->
                val draft = records.page().records.single().draft
                assertEquals(Instant.parse("2026-09-01T04:34:56.789Z").toEpochMilli(), draft.measuredAt)
                val evidence = draft.evidence!!.rawText
                assertTrue(evidence.contains(raw))
                assertFalse(evidence.contains("Excel epoch"))
            }
            ByteArrayOutputStream().use { output ->
                originals.copyVerified(original, output)
                assertArrayEquals(bytes, output.toByteArray())
            }
        }
    }

    @Test fun isoLocalDatesRespectZoneAndDateOnlyNeedsExplicitTime() = fixture(isoWorkbook(
        isoReading(2, "2026-09-01T08:30") + isoReading(3, "2026-09-01") + isoReading(4, "2026-11-01T01:30") +
            isoReading(5, "2026-11-01T01:30:00-04:00") + isoReading(6, "2026-09-01+08:00") +
            isoReading(7, "2026-03-08T02:30")
    )) { originals, original, tables, _ ->
        val loaded = load(originals, original, tables, catalog(originals, original, tables))
        val rows = tables.page(loaded.id).associate { it.row.sourceRow.toInt() to it.row }
        val mapping = loaded.mapping.copy(zone = "America/New_York")
        fun checkRow(row: Int, dateOnly: String = "") = HealthTablePolicy.evaluate(
            loaded.copy(mapping = mapping.copy(dateOnlyTime = dateOnly)), rows.getValue(row))
        assertEquals(Instant.parse("2026-09-01T12:30:00Z").toEpochMilli(), checkRow(2).draft!!.measuredAt)
        assertEquals("time", checkRow(3).issue)
        assertEquals(Instant.parse("2026-09-01T12:30:00Z").toEpochMilli(), checkRow(3, "08:30").draft!!.measuredAt)
        assertEquals("time", checkRow(4).issue)
        assertEquals(Instant.parse("2026-11-01T05:30:00Z").toEpochMilli(), checkRow(5).draft!!.measuredAt)
        assertEquals(Instant.parse("2026-09-01T00:30:00Z").toEpochMilli(), checkRow(6, "08:30").draft!!.measuredAt)
        assertEquals("time", checkRow(7).issue)
    }

    @Test fun malformedIsoTypedValuesCannotBecomeNumbersAndDateFormulaCacheRequiresConsent() = fixture(isoWorkbook(
        isoReading(2, "2026-09-01T12:00:00Z", systolic = "<c r=\"B2\" t=\"d\"><v>124</v></c>") +
            isoReading(3, "2026-09-01T12:00:00Z", formula = "A2") + isoReading(4, "") +
            isoReading(5, "2026-02-30") +
            isoReading(6, "2026-09-01T12:00:00Z", systolic = "<c r=\"B6\" t=\"d\"><f>B2</f><v>124</v></c>")
    )) { originals, original, tables, _ ->
        val loaded = load(originals, original, tables, catalog(originals, original, tables))
        val rows = tables.page(loaded.id).associate { it.row.sourceRow.toInt() to it.row }
        val invalid = rows.getValue(2)
        assertTrue("systolic" in invalid.errors)
        assertNull(invalid.numbers["systolic"])
        assertEquals(HealthTableRowState.INVALID, HealthTablePolicy.evaluate(loaded, invalid).state)
        val cached = rows.getValue(3)
        assertEquals("A2", cached.formulas["time"])
        assertEquals("formula_ack", HealthTablePolicy.evaluate(loaded, cached).issue)
        assertEquals(HealthTableRowState.VALID, HealthTablePolicy.evaluate(
            loaded.copy(mapping = loaded.mapping.copy(allowFormulaCache = true)), cached).state)
        assertEquals(HealthTableRowState.MISSING, HealthTablePolicy.evaluate(loaded, rows.getValue(4)).state)
        assertTrue("time" in rows.getValue(5).errors)
        assertEquals("excel_error", HealthTablePolicy.evaluate(
            loaded.copy(mapping = loaded.mapping.copy(allowFormulaCache = true)), rows.getValue(6)).issue)
    }
    @Test fun chineseWorksheetAndHeaderNamesUseTheSameMappingWithoutEnglishOnlyShortcuts() {
        val headers = "<row r=\"1\">" + listOf("日期", "高压", "低压", "单位").mapIndexed { index, name -> HealthXlsxFixtures.text("${'A' + index}1", name) }.joinToString("") + "</row>"
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("家庭测量" to (headers + HealthXlsxFixtures.reading())))) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            assertEquals("高压", loaded.mapping.columns["systolic"]); assertEquals("单位", loaded.mapping.unitColumn)
            val draft = HealthTablePolicy.evaluate(validate(tables, loaded), tables.page(loaded.id).single().row).draft!!
            assertEquals("家庭测量", draft.evidence?.tableSheet); assertEquals("124", draft.values["systolic"])
        }
    }
    @Test fun textTimestampCellsWithoutADeclaredFormulaAreNotInventedFormulaCaches() {
        val body = "<row r=\"2\"><c r=\"A2\" t=\"str\"><v>2026-09-01T12:00:00Z</v></c>" +
            HealthXlsxFixtures.number("B2", "124") + HealthXlsxFixtures.number("C2", "82") + HealthXlsxFixtures.text("D2", "mmHg") + "</row>"
        fixture(HealthXlsxFixtures.workbook(sheets = listOf("Home" to (HealthXlsxFixtures.headers() + body)))) { originals, original, tables, _ ->
            val loaded = load(originals, original, tables, catalog(originals, original, tables))
            val row = tables.page(loaded.id).single().row
            assertTrue(row.formulas.isEmpty()); assertEquals(HealthTableRowState.VALID, HealthTablePolicy.evaluate(loaded.copy(mapping = loaded.mapping.copy(zone = "UTC")), row).state)
        }
    }
}
