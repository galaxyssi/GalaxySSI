package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.contentstream.operator.Operator
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.io.RandomAccessRead
import com.tom_roush.pdfbox.io.ScratchFile
import com.tom_roush.pdfbox.pdfparser.PDFParser
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.rendering.PDFRenderer
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.io.Writer
import java.nio.ByteBuffer
import java.nio.channels.SeekableByteChannel
import java.util.concurrent.CancellationException
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/** Probes only visible text with usable page coordinates. The source remains encrypted on disk. */
internal class HealthPdfTextReader private constructor(private val document: PDDocument, private val cancelled: () -> Unit) : Closeable {
    val pageCount get() = document.numberOfPages
    val canExtract get() = document.currentAccessPermission.canExtractContent()
    private val renderer by lazy { PDFRenderer(document).apply { isSubsamplingAllowed = true } }

    fun page(index: Int): HealthOcrPage? = probe {
        cancelled()
        PageText(document.getPage(index), cancelled).extract(index + 1)
    }

    override fun close() = document.close()

    fun render(index: Int, maxEdge: Int, maxPixels: Int): Bitmap {
        cancelled()
        val crop = document.getPage(index).cropBox
        val width = crop.width.toDouble()
        val height = crop.height.toDouble()
        if (!width.isFinite() || !height.isFinite() || width <= 0 || height <= 0) throw HealthImportFailure("pdf_unsupported")
        val scale = minOf(3.0, maxEdge / maxOf(width, height), kotlin.math.sqrt(maxPixels / (width * height)))
        return renderer.renderImage(index, scale.toFloat())
    }

    companion object {
        fun open(context: Context, store: HealthOriginalStore, original: HealthOriginal, cancelled: () -> Unit): HealthPdfTextReader? = probe {
            openDocument(context, store, original, null, cancelled)
        }

        fun openProtected(context: Context, store: HealthOriginalStore, original: HealthOriginal,
                          password: CharArray, cancelled: () -> Unit): HealthPdfTextReader = try {
            openDocument(context, store, original, password, cancelled)
        } catch (_: InvalidPasswordException) {
            throw HealthImportFailure("pdf_password_wrong")
        } finally { password.fill('\u0000') }

        private fun openDocument(context: Context, store: HealthOriginalStore, original: HealthOriginal,
                                 password: CharArray?, cancelled: () -> Unit): HealthPdfTextReader {
            cancelled()
            PDFBoxResourceLoader.init(context.applicationContext)
            val source = EncryptedPdfInput(store.readChannel(original), original.size, cancelled)
            var scratch: ScratchFile? = null
            try {
                val memory = ScratchFile(MemoryUsageSetting.setupMainMemoryOnly(16L * 1024 * 1024))
                scratch = memory
                val parser = PDFParser(source, password?.concatToString().orEmpty(), memory).apply { isLenient = false }
                parser.parse()
                return HealthPdfTextReader(parser.pdDocument, cancelled)
            } catch (failure: Throwable) {
                runCatching { source.close() }
                runCatching { scratch?.close() }
                throw failure
            }
        }

        private inline fun <T> probe(block: () -> T): T? = try { block() }
        catch (cancel: CancellationException) { throw cancel }
        catch (_: InvalidPasswordException) { throw HealthImportFailure("pdf_password") }
        catch (_: IOException) { null }
        catch (_: RuntimeException) { null }
    }
}

private class EncryptedPdfInput(
    private val channel: SeekableByteChannel,
    private val size: Long,
    private val cancelled: () -> Unit
) : RandomAccessRead {
    private val buffer = ByteArray(16 * 1024)
    private var position = 0L
    private var start = -1L
    private var count = 0
    private var refills = 0

    private fun ensure(): Boolean {
        if (isClosed()) throw IOException("Closed PDF source")
        if (position >= size) return false
        if (position >= start && position - start < count) return true
        if (++refills % 64 == 0) cancelled()
        start = position
        channel.position(start)
        count = channel.read(ByteBuffer.wrap(buffer, 0, minOf(buffer.size.toLong(), size - start).toInt()))
        if (count <= 0) throw EOFException("Truncated PDF source")
        return true
    }

    override fun read(): Int = if (!ensure()) -1 else buffer[(position++ - start).toInt()].toInt() and 0xff
    override fun read(target: ByteArray): Int = read(target, 0, target.size)
    override fun read(target: ByteArray, offset: Int, length: Int): Int {
        require(offset >= 0 && length >= 0 && offset <= target.size - length)
        if (length == 0) return 0
        if (!ensure()) return -1
        val index = (position - start).toInt()
        val copied = minOf(length, count - index)
        buffer.copyInto(target, offset, index, index + copied)
        position += copied
        return copied
    }
    override fun getPosition() = position
    override fun seek(offset: Long) {
        if (offset < 0) throw IOException("Invalid PDF offset")
        position = offset
    }
    override fun length() = size
    override fun isClosed() = !channel.isOpen
    override fun peek(): Int = if (ensure()) buffer[(position - start).toInt()].toInt() and 0xff else -1
    override fun rewind(bytes: Int) = seek(position - bytes)
    override fun readFully(length: Int): ByteArray {
        if (length < 0 || length > 16 * 1024 * 1024 || length > size - position) throw EOFException("Invalid PDF span")
        return ByteArray(length).also { target ->
            var offset = 0
            while (offset < length) {
                val read = read(target, offset, length - offset)
                if (read < 0) throw EOFException("Truncated PDF span")
                offset += read
            }
        }
    }
    override fun isEOF() = position >= size
    override fun available() = (size - position).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
    override fun close() { try { channel.close() } finally { buffer.fill(0) } }
}

private class PageText(private val page: PDPage, private val cancelled: () -> Unit) : PDFTextStripper() {
    private val crop = page.cropBox
    private val rotation = page.rotation
    private val width = if (rotation == 90 || rotation == 270) crop.height else crop.width
    private val height = if (rotation == 90 || rotation == 270) crop.width else crop.height
    private val lines = mutableListOf<HealthOcrLine>()
    private val line = StringBuilder()
    private val bounds = RectF()
    private var rasterArea = 0.0
    private var operators = 0
    private var glyphs = 0
    private var unmapped = false

    init {
        startPage = 0
        sortByPosition = true
        setShouldSeparateByBeads(false)
        output = object : Writer() {
            override fun write(cbuf: CharArray, off: Int, len: Int) = Unit
            override fun flush() = Unit
            override fun close() = Unit
        }
    }

    fun extract(number: Int): HealthOcrPage? {
        if (!width.isFinite() || !height.isFinite() || width <= 0 || height <= 0) return null
        processPage(page)
        finishLine()
        if (unmapped || rasterArea >= crop.width.toDouble() * crop.height * .30 ||
            lines.none { row -> row.text.count(Char::isLetterOrDigit) >= 3 }) return null
        return HealthOcrPage(number, ceil(width).toInt(), ceil(height).toInt(), lines, recognition = HealthRecognition.PDF_TEXT)
    }

    override fun processOperator(operator: Operator, operands: MutableList<COSBase>) {
        if (++operators % 256 == 0) cancelled()
        if (operators > 250_000) throw IllegalStateException("PDF page operator budget exceeded")
        if (operator.name == "BI" || operator.name == "Do" &&
            (operands.firstOrNull() as? COSName)?.let { resources?.getXObject(it) is PDImageXObject } == true) {
            val transform = graphicsState.currentTransformationMatrix
            rasterArea += abs(transform.scaleX.toDouble() * transform.scaleY - transform.shearX.toDouble() * transform.shearY)
        }
        super.processOperator(operator, operands)
    }

    override fun processTextPosition(text: TextPosition) {
        if (++glyphs > 50_000) throw IllegalStateException("PDF page text budget exceeded")
        val state = graphicsState
        val rendering = state.textState.renderingMode
        if (rendering.isFill && state.nonStrokeAlphaConstant > 0 || rendering.isStroke && state.alphaConstant > 0)
            super.processTextPosition(text)
    }

    override fun writeString(text: String, positions: MutableList<TextPosition>) {
        line.append(text)
        if (text.any { it == '\ufffd' || Character.getType(it) == Character.PRIVATE_USE.toInt() }) unmapped = true
        for (position in positions) {
            if (position.unicode.isNullOrBlank()) continue
            val box = glyphBox(position)
            if (box == null) unmapped = true else bounds.union(box)
        }
    }

    override fun writeWordSeparator() { line.append(' ') }
    override fun writeLineSeparator() = finishLine()
    override fun writeParagraphSeparator() = finishLine()

    private fun finishLine() {
        val value = line.toString().trim()
        if (value.isNotEmpty()) {
            val box = listOf(floor(bounds.left * 1000f / width).toInt(), floor(bounds.top * 1000f / height).toInt(),
                ceil(bounds.right * 1000f / width).toInt(), ceil(bounds.bottom * 1000f / height).toInt())
                .map { it.coerceIn(0, 1000) }
            if (box[0] >= box[2] || box[1] >= box[3]) unmapped = true else lines += HealthOcrLine(value, box)
        }
        line.setLength(0); bounds.setEmpty()
    }

    private fun glyphBox(position: TextPosition): RectF? {
        if (position.dir != 0f) return null
        val x = position.xDirAdj
        val baseline = position.yDirAdj
        val glyphWidth = position.widthDirAdj
        val glyphHeight = position.heightDir
        if (!x.isFinite() || !baseline.isFinite() || !glyphWidth.isFinite() || !glyphHeight.isFinite() ||
            glyphWidth <= 0f || glyphHeight <= 0f) return null
        val top = baseline - glyphHeight * 1.25f
        val right = x + glyphWidth
        val bottom = baseline + glyphHeight * .35f
        val box = when (rotation) {
            90 -> RectF(crop.height - bottom, x, crop.height - top, right)
            180 -> RectF(crop.width - right, crop.height - bottom, crop.width - x, crop.height - top)
            270 -> RectF(top, crop.width - right, bottom, crop.width - x)
            else -> RectF(x, top, right, bottom)
        }
        return box.takeIf { it.intersect(0f, 0f, width, height) }
    }
}
