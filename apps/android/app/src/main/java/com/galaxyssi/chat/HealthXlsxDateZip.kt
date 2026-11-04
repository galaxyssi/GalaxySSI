package com.galaxyssi.chat

import com.fasterxml.aalto.stax.EventFactoryImpl
import com.fasterxml.aalto.stax.InputFactoryImpl
import com.fasterxml.aalto.stax.OutputFactoryImpl
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.channels.SeekableByteChannel
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import javax.xml.namespace.QName
import javax.xml.stream.XMLInputFactory
import javax.xml.stream.XMLStreamException
import javax.xml.stream.events.Attribute
import javax.xml.stream.events.StartElement
import javax.xml.stream.events.XMLEvent
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipFile

internal class HealthXlsxDateZip(channel: SeekableByteChannel, private val cancelled: () -> Unit) : ZipFile(channel) {
    var dateSheets: Set<String> = emptySet()

    override fun getInputStream(entry: ZipArchiveEntry): InputStream? {
        val original = super.getInputStream(entry) ?: return null
        if (entry.name !in dateSheets) return original
        return try {
            HealthXlsxDateStream(original, cancelled)
        } catch (failure: XMLStreamException) {
            runCatching { original.close() }
            throw HealthImportFailure("xlsx_xml").apply { initCause(failure) }
        }
    }

    companion object {
        const val INVALID_DATE_CACHE = "#VALUE!"

        fun worksheetNamespace(value: String?) = value == "http://schemas.openxmlformats.org/spreadsheetml/2006/main" ||
            value == "http://purl.oclc.org/ooxml/spreadsheetml/main"
    }
}

/** Adapt verified worksheet XML for FastExcel without modifying or materializing the original workbook. */
private class HealthXlsxDateStream(private val source: InputStream, private val cancelled: () -> Unit) : InputStream() {
    private class Buffer : ByteArrayOutputStream(8192) {
        fun byteAt(index: Int) = buf[index].toInt() and 0xff
        fun copyTo(index: Int, target: ByteArray, offset: Int, length: Int) = buf.copyInto(target, offset, index, index + length)
        fun clear() { buf.fill(0, 0, count); reset() }
    }

    private val buffer = Buffer()
    private val events = EventFactoryImpl()
    private val writer = OutputFactoryImpl().createXMLEventWriter(buffer, "UTF-8")
    private val reader = InputFactoryImpl().apply {
        setProperty(XMLInputFactory.SUPPORT_DTD, false)
        setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false)
    }.createXMLEventReader(source)
    private val path = ArrayList<QName>(8)
    private val type = QName("t")
    private var position = 0
    private var closed = false

    private fun fill(): Boolean {
        check(!closed)
        if (position < buffer.size()) return true
        buffer.clear()
        position = 0
        try {
            while (buffer.size() == 0 && reader.hasNext()) {
                var count = 0
                while (count++ < 128 && reader.hasNext() && buffer.size() < 8192) {
                    cancelled()
                    copyEvent(reader.nextEvent())
                }
                writer.flush()
            }
        } catch (failure: XMLStreamException) {
            throw HealthImportFailure("xlsx_xml").apply { initCause(failure) }
        }
        return buffer.size() > 0
    }

    private fun copyEvent(event: XMLEvent) {
        when {
            event.isStartDocument -> writer.add(events.createStartDocument("UTF-8", "1.0"))
            event.isStartElement -> {
                val start = event.asStartElement()
                val name = start.name
                if (name.localPart == "c" && path.size == 3 && path[0].localPart == "worksheet" &&
                    path[1].localPart == "sheetData" && path[2].localPart == "row" &&
                    HealthXlsxDateZip.worksheetNamespace(name.namespaceURI) && path.all { it.namespaceURI == name.namespaceURI } &&
                    start.getAttributeByName(type)?.value == "d"
                ) {
                    copyDate(start)
                } else {
                    path.add(name)
                    writer.add(event)
                }
            }
            event.isEndElement -> { path.removeAt(path.lastIndex); writer.add(event) }
            else -> writer.add(event)
        }
    }

    private fun copyDate(start: StartElement) {
        val cell = ArrayList<XMLEvent>()
        val value = StringBuilder()
        var depth = 1
        var valueStart = -1
        var valueEnd = -1
        var chars = 0
        while (depth > 0) {
            cancelled()
            if (cell.size >= 256 || !reader.hasNext()) throw HealthImportFailure("table_cell")
            val event = reader.nextEvent()
            cell += event
            when {
                event.isStartElement -> {
                    depth++
                    val name = event.asStartElement().name
                    if (valueStart >= 0 && valueEnd < 0) throw HealthImportFailure("xlsx_xml")
                    if (depth == 2 && name.localPart == "v") {
                        if (valueStart >= 0 || name.namespaceURI != start.name.namespaceURI) throw HealthImportFailure("xlsx_xml")
                        valueStart = cell.lastIndex
                    }
                }
                event.isEndElement -> {
                    if (depth == 2 && valueStart >= 0 && valueEnd < 0) valueEnd = cell.lastIndex
                    depth--
                }
                event.isCharacters -> {
                    val data = event.asCharacters().data
                    chars += data.length
                    if (chars > 65_536) throw HealthImportFailure("table_cell")
                    if (valueStart >= 0 && valueEnd < 0 && value.length <= 128) value.append(data, 0, minOf(data.length, 129 - value.length))
                }
            }
        }
        val raw = value.toString()
        val supported = raw.isEmpty() || raw.length <= 128 && isIsoDate(raw)
        val attributes = start.attributes.asSequence().map { it as Attribute }.map { attribute ->
            if (attribute.name == type) events.createAttribute(type, if (supported) "str" else "e") else attribute
        }.toList()
        writer.add(events.createStartElement(start.name, attributes.iterator(), start.namespaces))
        cell.forEachIndexed { index, event ->
            if (supported || index <= valueStart || index >= valueEnd) writer.add(event)
            if (!supported && index == valueStart) writer.add(events.createCharacters(HealthXlsxDateZip.INVALID_DATE_CACHE))
        }
    }

    private fun isIsoDate(value: String): Boolean = runCatching {
        if ('T' in value || 't' in value) {
            runCatching { OffsetDateTime.parse(value) }.getOrElse { LocalDateTime.parse(value) }
        } else {
            DateTimeFormatter.ISO_DATE.parse(value, LocalDate::from)
        }
    }.isSuccess

    override fun read(): Int = if (fill()) buffer.byteAt(position++) else -1

    override fun read(target: ByteArray, offset: Int, length: Int): Int {
        if (offset < 0 || length < 0 || offset > target.size - length) throw IndexOutOfBoundsException()
        if (length == 0) return 0
        if (!fill()) return -1
        val count = minOf(length, buffer.size() - position)
        buffer.copyTo(position, target, offset, count)
        position += count
        return count
    }

    override fun close() {
        if (closed) return
        closed = true
        try {
            runCatching { reader.close() }
            runCatching { writer.close() }
            source.close()
        } finally { buffer.clear() }
    }
}
