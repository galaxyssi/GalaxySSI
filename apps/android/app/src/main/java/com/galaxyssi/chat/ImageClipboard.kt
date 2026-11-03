package com.galaxyssi.chat

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.View
import android.webkit.MimeTypeMap
import android.widget.PopupMenu
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

internal data class ClipboardImageSource(val name: String, val mimeType: String, val open: () -> InputStream) {
    companion object {
        fun fromUri(context: Context, uri: Uri, name: String, mimeType: String): ClipboardImageSource {
            require(uri.scheme in setOf("content", "file")) { "Image source is unavailable" }
            val source = ChatImagePreviewSource.resolve(context, uri, name, mimeType, 0)
            return ClipboardImageSource(source.name, source.mimeType) {
                context.contentResolver.openInputStream(uri) ?: error("Image source is unavailable")
            }
        }

        fun fromBlock(context: Context, block: AgentRichBlock): ClipboardImageSource {
            if (block.dataB64.isNotBlank()) return ClipboardImageSource(block.title,
                block.mimeType.ifBlank { "image/png" }) {
                val bytes = Base64.decode(block.dataB64, Base64.DEFAULT)
                object : ByteArrayInputStream(bytes) { override fun close() { bytes.fill(0); super.close() } }
            }
            val resolved = AgentDesktopArtifactStore.resolveBlock(context, block)
            val uri = if (AgentMarkdownImages.isWebSource(resolved.uri))
                Uri.fromFile(AgentMarkdownImageStore.load(context, resolved.uri)) else Uri.parse(resolved.uri)
            return fromUri(context, uri, block.title, resolved.mimeType.ifBlank { block.mimeType })
        }
    }
}

/** Clipboard images are MIME-tagged content, never filename/path text or re-encoded thumbnails. */
internal object ImageClipboard {
    private const val ROOT = "clipboard-images"
    private val worker = Executors.newSingleThreadExecutor { Thread(it, "galaxyssi-image-copy").apply { isDaemon = true } }
    private val main = Handler(Looper.getMainLooper())
    private val published = AtomicReference<Uri?>()

    fun showCopyMenu(activity: Activity, anchor: View, source: (Context) -> ClipboardImageSource) {
        PopupMenu(activity, anchor).apply {
            menu.add(0, 1, 0, R.string.common_copy)
            setOnMenuItemClickListener { copy(activity, source); true }
            show()
        }
    }

    fun copy(activity: Activity, source: (Context) -> ClipboardImageSource) {
        val owner = WeakReference(activity)
        val app = activity.applicationContext
        worker.execute {
            val result = runCatching { snapshot(app, source(app)) }
            main.post {
                val screen = owner.get()?.takeUnless { it.isFinishing || it.isDestroyed }
                if (screen == null) {
                    result.getOrNull()?.let { discard(app, it) }
                    return@post
                }
                val copied = result.fold(onSuccess = { uri -> runCatching {
                    publish(app, uri)
                    published.set(uri)
                    worker.execute { runCatching { prune(app) } }
                }.isSuccess }, onFailure = { false })
                if (!copied) result.getOrNull()?.let { discard(app, it) }
                Toast.makeText(screen, if (copied) R.string.toast_copied else R.string.rich_output_load_failed,
                    Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun discard(context: Context, uri: Uri) {
        worker.execute { runCatching { context.contentResolver.delete(uri, null, null) } }
    }

    internal fun snapshot(context: Context, source: ClipboardImageSource): Uri {
        require(source.mimeType.startsWith("image/") && source.mimeType != "image/*") { "Clipboard content is not an image" }
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(source.mimeType.substringBefore(';'))
            ?: source.name.substringAfterLast('.', "").lowercase().takeIf { it.matches(Regex("[a-z0-9]{1,12}")) }
            ?: error("Image format is unavailable")
        val root = File(context.cacheDir, ROOT)
        val file = source.open().use { ComposerAttachmentImport.copyToPrivate(it, root, Long.MAX_VALUE, extension) }
        try {
            check(file.length() > 0L) { "Image source is empty" }
            val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
            return uri
        } catch (failure: Exception) { file.delete(); throw failure }
    }

    private fun prune(context: Context) {
        val root = File(context.cacheDir, ROOT)
        val files = root.walkTopDown().filter { it.isFile && !it.name.endsWith(".part") }
            .sortedByDescending(File::lastModified).toList()
        val current = published.get()
        files.drop(2).forEach { file ->
            if (FileProvider.getUriForFile(context, context.packageName + ".files", file) != current) file.delete()
        }
    }

    internal fun publish(context: Context, uri: Uri) {
        val clip = ClipData.newUri(context.contentResolver, "GalaxySSI image", uri)
        check(clip.description.hasMimeType("image/*")) { "Image clipboard type is unavailable" }
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }
}
