package com.galaxyssi.chat

import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal object HealthXlsxFixtures {
    fun serial(date1904: Boolean = false): Long = ChronoUnit.DAYS.between(if (date1904) LocalDate.of(1904, 1, 1) else LocalDate.of(1899, 12, 30), LocalDate.of(2026, 9, 1))
    fun text(address: String, value: String) = "<c r=\"$address\" t=\"inlineStr\"><is><t>$value</t></is></c>"
    fun number(address: String, value: String) = "<c r=\"$address\"><v>$value</v></c>"
    fun formula(address: String, value: String?, expression: String = "100+24") = "<c r=\"$address\"><f>$expression</f>${value?.let { "<v>$it</v>" }.orEmpty()}</c>"
    fun headers(row: Int = 1) = "<row r=\"$row\">" + listOf("time", "systolic", "diastolic", "unit").mapIndexed { i, name -> text("${'A' + i}$row", name) }.joinToString("") + "</row>"
    fun reading(row: Int = 2, date1904: Boolean = false, value: String = "124", formula: Boolean = false, cached: Boolean = true) =
        "<row r=\"$row\">" + number("A$row", "${serial(date1904)}.5") +
            (if (formula) HealthXlsxFixtures.formula("B$row", if (cached) value else null) else number("B$row", value)) +
            number("C$row", "82") + text("D$row", "mmHg") + "</row>"
    fun workbook(date1904: Boolean = false, sheets: List<Pair<String, String>> = listOf("Home" to (headers() + reading(date1904 = date1904))),
                 extras: Map<String, String> = emptyMap(), writer: ((ZipOutputStream) -> Unit)? = null, sharedStrings: String? = null): ByteArray {
        val ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        val relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        val parts = linkedMapOf(
            "[Content_Types].xml" to "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
                "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>" +
                "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" +
                (if (sharedStrings == null) "" else "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>") +
                sheets.indices.joinToString("") { "<Override PartName=\"/xl/worksheets/sheet${it + 1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" } + "</Types>",
            "_rels/.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"root\" Type=\"$relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
            "xl/workbook.xml" to "<workbook xmlns=\"$ns\" xmlns:r=\"$relationships\"><workbookPr date1904=\"${if (date1904) 1 else 0}\"/><sheets>" +
                sheets.mapIndexed { i, sheet -> "<sheet name=\"${sheet.first}\" sheetId=\"${i + 1}\" r:id=\"sheet${i + 1}\"/>" }.joinToString("") + "</sheets></workbook>",
            "xl/_rels/workbook.xml.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                "<Relationship Id=\"styles\" Type=\"$relationships/styles\" Target=\"styles.xml\"/>" +
                (if (sharedStrings == null) "" else "<Relationship Id=\"strings\" Type=\"$relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>") +
                sheets.indices.joinToString("") { "<Relationship Id=\"sheet${it + 1}\" Type=\"$relationships/worksheet\" Target=\"worksheets/sheet${it + 1}.xml\"/>" } + "</Relationships>",
            "xl/styles.xml" to "<styleSheet xmlns=\"$ns\"><fonts count=\"1\"><font/></fonts><fills count=\"1\"><fill/></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\"/></cellStyleXfs><cellXfs count=\"1\"><xf numFmtId=\"0\"/></cellXfs></styleSheet>"
        )
        sheets.forEachIndexed { i, sheet -> parts["xl/worksheets/sheet${i + 1}.xml"] = "<worksheet xmlns=\"$ns\"><sheetData>${sheet.second}</sheetData></worksheet>" }
        sharedStrings?.let { parts["xl/sharedStrings.xml"] = it }; parts.putAll(extras)
        return ByteArrayOutputStream().use { bytes ->
            ZipOutputStream(bytes).use { zip ->
                parts.forEach { (name, text) -> zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry() }
                writer?.invoke(zip)
            }
            bytes.toByteArray()
        }
    }
}
