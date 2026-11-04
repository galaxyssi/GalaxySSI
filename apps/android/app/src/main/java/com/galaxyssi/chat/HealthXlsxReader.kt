package com.galaxyssi.chat

import android.util.Xml
import java.io.InputStream
import java.io.OutputStream
import java.math.BigDecimal
import java.util.zip.CRC32
import org.apache.commons.compress.archivers.zip.ZipFile
import org.dhatim.fastexcel.reader.Cell
import org.dhatim.fastexcel.reader.CellType
import org.dhatim.fastexcel.reader.ReadableWorkbook
import org.dhatim.fastexcel.reader.ReadingOptions
import org.xmlpull.v1.XmlPullParser

/** Seekable authenticated decryption feeds ZIP directly; no plaintext XLSX scratch file is created. */
internal object HealthXlsxReader {
    private const val MAX_METADATA = 4L * 1024 * 1024
    private const val MAX_ENTRIES = 10_000
    private const val MAX_ROWS = 1_048_576
    private const val MAX_COLUMNS = 256
    private val discard = object : OutputStream() { override fun write(value: Int) = Unit; override fun write(bytes: ByteArray, offset: Int, count: Int) = Unit }

    private fun <T> workbook(originals: HealthOriginalStore, original: HealthOriginal, cancelled: () -> Unit, block: (ReadableWorkbook) -> T): T {
        if (original.size > HealthTableParser.MAX_BYTES) throw HealthImportFailure("table_size")
        originals.copyVerified(original, discard, cancelled)
        return originals.readChannel(original).use { channel ->
            try { ZipFile(channel).use { zip ->
                preflight(zip, cancelled)
                HealthXlsxWorkbookFactory.open(zip).use(block)
            } } catch (failure: java.lang.reflect.InvocationTargetException) {
                val cause = failure.targetException
                if (cause is Error) throw cause
                throw HealthImportFailure("xlsx_format")
            } catch (failure: HealthImportFailure) { throw failure }
            catch (_: org.dhatim.fastexcel.reader.ExcelReaderException) { throw HealthImportFailure("xlsx_format") }
            catch (_: java.util.zip.ZipException) { throw HealthImportFailure("xlsx_format") }
            catch (_: java.io.IOException) { throw HealthImportFailure("xlsx_format") }
        }
    }
    fun inspect(originals: HealthOriginalStore, original: HealthOriginal, cancelled: () -> Unit = {}): Pair<List<HealthXlsxSheet>, Boolean> =
        workbook(originals, original, cancelled) { book ->
            sheets(book) to book.isDate1904
        }

    private fun sheets(book: ReadableWorkbook): List<HealthXlsxSheet> = book.sheets.use {
        it.iterator().asSequence().map { sheet -> HealthXlsxSheet(sheet.index, sheet.name, sheet.visibility.name) }.toList()
    }.also { sheets ->
        if (sheets.isEmpty() || sheets.size > 256 || sheets.any { it.name.isBlank() || it.name.length > 200 }) throw HealthImportFailure("xlsx_sheets")
    }

    fun preview(originals: HealthOriginalStore, original: HealthOriginal, sheetIndex: Int?,
                cancelled: () -> Unit): HealthStructuredSample = workbook(originals, original, cancelled) { book ->
        val sheets = sheets(book)
        val selected = sheetIndex ?: sheets.first().index
        val sheet = book.getSheet(selected).orElseThrow { HealthImportFailure("xlsx_sheet") }
        sheet.openStream().use { stream ->
            val rows = ArrayList<HealthStructuredRow>(HealthStructuredPreview.ROWS)
            val iterator = stream.iterator()
            var clipped = false
            while (rows.size < HealthStructuredPreview.ROWS) {
                cancelled()
                val row = try { if (!iterator.hasNext()) break; iterator.next() }
                    catch (_: IllegalStateException) { throw HealthImportFailure("xlsx_cell_type") }
                if (row.cellCount > HealthStructuredPreview.COLUMNS) clipped = true
                val values = (0 until minOf(row.cellCount, HealthStructuredPreview.COLUMNS)).map { index ->
                    val cell = row.getOptionalCell(index).orElse(null)
                    val raw = if (cell == null) "" else cell.formula?.let { "=$it" } ?: cell.text
                    HealthStructuredPreview.cell(raw)
                }
                rows += HealthStructuredRow(row.rowNum.toLong(), values)
            }
            cancelled()
            HealthStructuredSample(rows, iterator.hasNext(), clipped, sheets, selected)
        }
    }

    fun rows(originals: HealthOriginalStore, original: HealthOriginal, batch: HealthTableBatch,
             cancelled: () -> Unit = {}, emit: (HealthTableRow) -> Unit): List<String> = workbook(originals, original, cancelled) { book ->
        check(original.id == batch.originalId && original.sha256 == batch.sha256 && book.isDate1904 == batch.date1904)
        val sheet = book.getSheet(batch.sheetIndex).orElseThrow { HealthImportFailure("xlsx_sheet") }
        check(batch.sheets.singleOrNull { it.index == sheet.index }?.name == sheet.name)
        sheet.openStream().use { stream ->
            val iterator = stream.iterator(); var headers: List<String>? = null; var ordinal = 0L
            while (true) {
                cancelled()
                val row = try { if (!iterator.hasNext()) break; iterator.next() }
                    catch (_: IllegalStateException) { throw HealthImportFailure("xlsx_cell_type") }
                if (row.rowNum < batch.headerRow) continue
                if (row.cellCount > MAX_COLUMNS) throw HealthImportFailure("table_columns")
                if (headers == null) {
                    if (row.rowNum != batch.headerRow || row.cellCount == 0) throw HealthImportFailure("xlsx_headers")
                    headers = (0 until row.cellCount).map { index ->
                        val cell = row.getOptionalCell(index).orElse(null)
                        if (cell?.type != CellType.STRING && !(cell?.type == CellType.FORMULA && cell.formula == null && cell.value is String)) throw HealthImportFailure("xlsx_headers")
                        cell.text.trim()
                    }
                    if (headers.any { it.isBlank() || it.length > 200 } || headers.distinct().size != headers.size) throw HealthImportFailure("table_headers")
                    continue
                }
                val names = headers
                val cells = linkedMapOf<String, String>(); val formulas = linkedMapOf<String, String>()
                val numbers = linkedMapOf<String, String>(); val dates = linkedMapOf<String, String>(); val addresses = linkedMapOf<String, String>()
                val errors = linkedSetOf<String>(); var chars = 0
                names.forEachIndexed { index, name ->
                    val cell = row.getOptionalCell(index).orElse(null)
                    val raw = cell?.let { if (it.type in listOf(CellType.STRING, CellType.BOOLEAN) || it.value is Boolean) it.text else it.rawValue.orEmpty() }.orEmpty()
                    if (raw.length > 16_384) throw HealthImportFailure("table_cell")
                    cells[name] = raw
                    cell?.let {
                        addresses[name] = it.address.toString()
                        if (it.type == CellType.ERROR) errors += name
                        if (it.formula != null) formulas[name] = it.formula.ifBlank { "(shared or array formula)" }
                        if (it.type in listOf(CellType.NUMBER, CellType.FORMULA) && it.value is BigDecimal) {
                            val decimal = raw.toBigDecimalOrNull()
                            if (decimal != null && decimal.precision() <= 20 && decimal.scale() in -20..20) {
                                numbers[name] = decimal.stripTrailingZeros().toPlainString()
                                date(it, decimal, book.isDate1904)?.let { value -> dates[name] = value }
                            }
                        }
                    }
                    chars += name.length + raw.length + formulas[name].orEmpty().length
                }
                if (chars > 65_536 || formulas.values.any { it.length > 16_384 }) throw HealthImportFailure("table_row")
                val extra = (names.size until row.cellCount).any { row.getCellText(it).isNotBlank() }
                emit(HealthTableRow(++ordinal, cells, if (extra) "columns" else "", row.rowNum.toLong(), formulas, numbers, dates, errors, addresses))
            }
            headers ?: throw HealthImportFailure("xlsx_headers")
        }
    }
    private fun date(cell: Cell, value: BigDecimal, date1904: Boolean): String? {
        if (value < BigDecimal.ZERO || value > BigDecimal("2958465.99999") || !date1904 && value >= BigDecimal(60) && value < BigDecimal(61)) return null
        return runCatching { cell.asDate()?.toString() }.getOrNull()
    }

    /** Verify bounded expansion, CRC and XML structure before the spreadsheet library creates cell lists/SSTs. */
    private fun preflight(zip: ZipFile, cancelled: () -> Unit) {
        var expanded = 0L
        try {
            val seen = hashSetOf<String>(); val entries = zip.entries
            while (entries.hasMoreElements()) {
                cancelled(); val entry = entries.nextElement(); val name = entry.name
                if (!seen.add(name) || seen.size > MAX_ENTRIES || name.startsWith('/') || name.split('/').any { it == ".." } || '\\' in name) throw HealthImportFailure("xlsx_package")
                if (name.endsWith("vbaProject.bin", true)) throw HealthImportFailure("xlsx_macro")
                if (entry.isDirectory) continue
                var read = 0L; val crc = CRC32()
                val input = zip.getInputStream(entry)
                val bounded = object : InputStream() {
                    override fun read(): Int = input.read().also { if (it >= 0) { crc.update(it); count(1) } }
                    override fun read(buffer: ByteArray, off: Int, len: Int): Int = input.read(buffer, off, len).also { if (it > 0) { crc.update(buffer, off, it); count(it) } }
                    private fun count(count: Int) {
                        cancelled(); read += count; expanded += count
                        if (read > HealthTableParser.MAX_BYTES || expanded > HealthTableParser.MAX_BYTES) throw HealthImportFailure("xlsx_expansion")
                    }
                    override fun close() = input.close()
                }
                bounded.use { source ->
                    if (name.endsWith(".xml", true) || name.endsWith(".rels", true)) {
                        val parser = Xml.newPullParser().apply { setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true); setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false); setInput(source, null) }
                        var sheet = false; var row = 0; var lastRow = 0; var column = 0
                        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                            cancelled()
                            if (parser.eventType == XmlPullParser.DOCDECL) throw HealthImportFailure("xlsx_xml")
                            if (parser.eventType == XmlPullParser.START_TAG) {
                                if (parser.name == "worksheet") sheet = true
                                if (parser.name == "Override" && parser.getAttributeValue(null, "ContentType").orEmpty().contains("macroEnabled", true)) throw HealthImportFailure("xlsx_macro")
                                if (sheet && parser.name == "row") {
                                    row = parser.getAttributeValue(null, "r")?.toIntOrNull() ?: lastRow + 1
                                    if (row !in 1..MAX_ROWS || row <= lastRow) throw HealthImportFailure("xlsx_address")
                                    lastRow = row; column = 0
                                }
                                if (sheet && parser.name == "c") {
                                    val address = parser.getAttributeValue(null, "r")
                                    val next = if (address == null) column + 1 else address(address, row)
                                    if (next <= column || next > MAX_COLUMNS) throw HealthImportFailure("table_columns")
                                    column = next
                                }
                            }
                            if (!sheet && read > MAX_METADATA) throw HealthImportFailure("xlsx_metadata")
                            if (parser.eventType in listOf(XmlPullParser.TEXT, XmlPullParser.CDSECT) && parser.text.length > 65_536) throw HealthImportFailure("table_cell")
                            parser.nextToken()
                        }
                        if (!sheet && read > MAX_METADATA) throw HealthImportFailure("xlsx_metadata")
                    }
                    val buffer = ByteArray(16 * 1024)
                    try { while (source.read(buffer) >= 0) Unit } finally { buffer.fill(0) }
                }
                if (entry.crc != crc.value || entry.size != read) throw HealthImportFailure("xlsx_package")
            }
        } catch (failure: HealthImportFailure) { throw failure }
        catch (_: java.util.zip.ZipException) { throw HealthImportFailure("xlsx_format") }
        catch (_: org.xmlpull.v1.XmlPullParserException) { throw HealthImportFailure("xlsx_xml") }
    }
    private fun address(value: String, row: Int): Int {
        val letters = value.takeWhile { it in 'A'..'Z' }
        if (letters.isEmpty() || letters.length > 3 || value.drop(letters.length).toIntOrNull() != row) throw HealthImportFailure("xlsx_address")
        val column = letters.fold(0) { result, letter -> result * 26 + (letter - 'A' + 1) }
        if (column > MAX_COLUMNS) throw HealthImportFailure("table_columns")
        return column
    }
}

/** fastexcel 0.20.2 has File/InputStream entry points only. This pinned bridge supplies its ZIP package directly. */
internal object HealthXlsxWorkbookFactory {
    private val packageClass by lazy { Class.forName("org.dhatim.fastexcel.reader.OPCPackage") }
    private val packageConstructor by lazy { packageClass.getDeclaredConstructor(ZipFile::class.java, Boolean::class.javaPrimitiveType).apply { isAccessible = true } }
    private val workbookConstructor by lazy { ReadableWorkbook::class.java.getDeclaredConstructor(packageClass, ReadingOptions::class.java).apply { isAccessible = true } }
    fun open(zip: ZipFile): ReadableWorkbook {
        val pkg = packageConstructor.newInstance(zip, false)
        return try { workbookConstructor.newInstance(pkg, ReadingOptions(false, true)) }
        catch (failure: Throwable) { runCatching { (pkg as AutoCloseable).close() }; throw failure }
    }
}
