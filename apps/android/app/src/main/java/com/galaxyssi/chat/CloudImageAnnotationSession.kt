package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.AtomicFile
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/** Per-request inputs and output cards; nothing is shared between cloud conversations. */
internal class CloudImageAnnotationSession(
    private val context: Context,
    private val images: List<CloudImagePayload>,
    private val sessionId: String = UUID.randomUUID().toString()
) {
    private val completed = linkedMapOf<Int, AgentRichBlock>()
    private val rendered = mutableMapOf<String, AgentRichBlock>()

    fun execute(
        name: String, arguments: JSONObject,
        token: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
        checkpoint: () -> Unit = {}
    ): String {
        if (name != CloudImageAnnotationPlan.TOOL) {
            return CloudWebGrounding.executeTool(context, name, arguments, token, checkpoint)
        }
        return try {
            checkpoint()
            val plan = CloudImageAnnotationPlan.parse(arguments, images.size)
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
            while (!renderSlot.tryAcquire(100, TimeUnit.MILLISECONDS)) {
                if (token.isCancellationRequested) throw AgentNativeToolCancelledException()
                checkpoint()
                check(System.nanoTime() < deadline) { "Image renderer is busy; retry later" }
            }
            val block = try {
                if (token.isCancellationRequested) throw AgentNativeToolCancelledException()
                checkpoint()
                render(plan, images[plan.imageIndex], arguments.toString(), checkpoint)
            } finally { renderSlot.release() }
            checkpoint()
            synchronized(this) {
                completed[plan.imageIndex] = block
                rendered["${plan.imageIndex}:${block.metadata["sha256"]}"] = block
            }
            JSONObject().put("status", "completed").put("tool", name)
                .put("image_index", plan.imageIndex).put("mark_count", plan.marks.size)
                .put("image_sha256", block.metadata["sha256"])
                .put("image_saved", true).put("presentation", "App will append the verified image card; do not create image links.")
                .toString()
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException || error is AgentNativeToolCancelledException) throw error
            JSONObject().put("status", "failed").put("tool", name).put("image_saved", false)
                .put("error", error.message.orEmpty().take(240))
                .put("next_action", "Correct invalid coordinates or image index and retry. If the image is unreadable, ask for a clearer image. Never claim image creation succeeded.")
                .toString()
        }
    }

    @Synchronized fun artifactSuffix(): String {
        if (completed.isEmpty()) return ""
        val unique = completed.toSortedMap().values.toList().asReversed()
            .distinctBy { it.metadata["annotation_source_sha256"].orEmpty().ifBlank { it.id } }.asReversed()
        return "\n\n```galaxyssi-rich\n" + AgentRichContentCodec.encode(unique) + "\n```"
    }

    fun appendTo(text: String): String = text + artifactSuffix()

    /** Cached calls must select their own output, not leave a later revision selected. */
    @Synchronized fun selectResult(encoded: String) {
        if (rendered.isEmpty() || !encoded.contains("\"image_saved\"")) return
        val result = runCatching { JSONObject(encoded) }.getOrNull() ?: return
        if (result.optString("tool") != CloudImageAnnotationPlan.TOOL || !result.optBoolean("image_saved")) return
        val index = result.optInt("image_index", -1)
        rendered["$index:${result.optString("image_sha256")}"]?.let { completed[index] = it }
    }

    private fun render(plan: CloudImageAnnotationPlan, image: CloudImagePayload, arguments: String,
        checkpoint: () -> Unit): AgentRichBlock {
        val source = image.sourceUri.takeIf(String::isNotBlank)?.let {
            AgentImagePipeline.loadPreview(context, Uri.parse(it), 2_000, 2_000)
        } ?: File.createTempFile("annotation-input-", ".image", context.cacheDir).let { temporary ->
            try {
                temporary.writeBytes(image.bytes)
                AgentImagePipeline.loadPreview(context, Uri.fromFile(temporary), 2_000, 2_000)
            } finally { temporary.delete() }
        }
            ?: error("Input image could not be decoded")
        try {
            require(source.width.toLong() * source.height <= 8_000_000L) { "Input image is too large to annotate" }
            val output = CloudImageAnnotationDrawing.render(source, plan, checkpoint)
            try {
                val id = digest((sessionId + "\u0000" + plan.imageIndex + "\u0000" + arguments).toByteArray())
                val file = File(root(context), "$id.png")
                val atomic = AtomicFile(file)
                val stream = atomic.startWrite()
                try {
                    check(output.compress(Bitmap.CompressFormat.PNG, 100, stream)) { "Image encoding failed" }
                    checkpoint()
                    atomic.finishWrite(stream)
                } catch (error: Throwable) { atomic.failWrite(stream); throw error }
                if (file.length() !in 1..12L * 1024L * 1024L) {
                    atomic.delete()
                    error("Annotated image exceeded the image limit")
                }
                val sha = file.inputStream().use { input ->
                    val hash = MessageDigest.getInstance("SHA-256")
                    val buffer = ByteArray(16 * 1024)
                    while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
                    hash.digest().joinToString("") { "%02x".format(it) }
                }
                return AgentRichBlock(id = "annotation-$id", type = AgentRichBlockType.IMAGE,
                    title = "\u6279\u6ce8\u56fe\u7247 ${plan.imageIndex + 1}", mimeType = "image/png",
                    uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file).toString(),
                    metadata = mapOf(LOCAL to "true", "annotation_id" to id, "sha256" to sha,
                        "annotation_source_sha256" to digest(image.bytes),
                        "size_bytes" to file.length().toString()))
            } finally { output.recycle() }
        } finally { source.recycle() }
    }

    companion object {
        const val LOCAL = "local_image_annotation"
        private val renderSlot = Semaphore(1, true)
        private fun root(context: Context) = File(context.filesDir, "agent-rich-output/image-annotations").apply { mkdirs() }
        private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        fun isLocalImage(block: AgentRichBlock) = block.metadata[LOCAL] == "true"

        fun save(context: Context, block: AgentRichBlock): Result<String> = runCatching {
            require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { "System Downloads requires Android 10 or newer" }
            val id = block.metadata["annotation_id"].orEmpty()
            require(id.matches(Regex("[a-f0-9]{64}")) && isLocalImage(block))
            val file = File(root(context), "$id.png")
            require(file.isFile && file.length() == block.metadata["size_bytes"]?.toLongOrNull()) { "Image is missing" }
            require(file.length() <= 12L * 1024L * 1024L && digest(file.readBytes()) == block.metadata["sha256"]) {
                "Image integrity check failed"
            }
            val name = "\u6279\u6ce8\u56fe\u7247-${id.take(8)}.png"
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "image/png")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/GalaxySSI")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val target = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("Cannot create download")
            try {
                resolver.openOutputStream(target)?.use { output -> file.inputStream().use { it.copyTo(output) } }
                    ?: error("Cannot write download")
                resolver.update(target, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
            } catch (error: Throwable) { resolver.delete(target, null, null); throw error }
            "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI/$name"
        }
    }
}
