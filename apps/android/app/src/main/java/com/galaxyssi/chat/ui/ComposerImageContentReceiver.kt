package com.galaxyssi.chat.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.net.Uri
import android.os.Bundle
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.core.view.ContentInfoCompat
import androidx.core.view.ViewCompat
import androidx.core.view.inputmethod.EditorInfoCompat
import androidx.core.view.inputmethod.InputConnectionCompat
import androidx.core.widget.TextViewOnReceiveContentListener
import java.util.concurrent.atomic.AtomicBoolean

/** Clipboard and IME images use the same asynchronous, owner-bound import as the picker. */
internal class ComposerImageContentReceiver(
    private val input: ParagraphSelectingEditText,
    private val accept: (List<Uri>, () -> Unit) -> Boolean
) {
    init {
        ViewCompat.setOnReceiveContentListener(input, arrayOf("image/*")) { _, payload -> receive(payload) }
    }

    fun paste(id: Int): Boolean {
        if (id != android.R.id.paste && id != android.R.id.pasteAsPlainText) return false
        val clip = runCatching { input.context.getSystemService(ClipboardManager::class.java).primaryClip }.getOrNull() ?: return false
        if (!hasImages(clip)) return false
        val payload = ContentInfoCompat.Builder(clip, ContentInfoCompat.SOURCE_CLIPBOARD)
            .setFlags(if (id == android.R.id.pasteAsPlainText) ContentInfoCompat.FLAG_CONVERT_TO_PLAIN_TEXT else 0).build()
        return receive(payload) == null
    }

    internal fun receive(payload: ContentInfoCompat): ContentInfoCompat? {
        if (!hasImages(payload.clip)) return payload
        val parts = payload.partition { localUri(it.uri) }
        val clip = parts.first?.clip ?: return payload
        val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }.distinct()
        if (!runCatching { accept(uris) {} }.getOrDefault(false)) return payload
        // Preserve mixed clipboard text and its insertion selection, never paste content:// as text.
        parts.second?.let { TextViewOnReceiveContentListener().onReceiveContent(input, it) }
        return null
    }

    fun wrap(connection: InputConnection, info: EditorInfo): InputConnection {
        EditorInfoCompat.setContentMimeTypes(info, arrayOf("image/*"))
        return InputConnectionCompat.createWrapper(connection, info) { content, flags, _: Bundle? ->
            if (!content.description.hasMimeType("image/*") || !localUri(content.contentUri)) return@createWrapper false
            val granted = flags and InputConnectionCompat.INPUT_CONTENT_GRANT_READ_URI_PERMISSION != 0
            if (granted && runCatching { content.requestPermission() }.isFailure) return@createWrapper false
            val released = AtomicBoolean()
            val release = { if (granted && released.compareAndSet(false, true)) runCatching { content.releasePermission() }; Unit }
            val accepted = runCatching { accept(listOf(content.contentUri), release) }.getOrDefault(false)
            if (!accepted) release()
            accepted
        }
    }

    private fun hasImages(clip: ClipData): Boolean =
        (clip.description.hasMimeType("image/*") || clip.description.hasMimeType("text/uri-list")) &&
            (0 until clip.itemCount).any { localUri(clip.getItemAt(it).uri) }

    private fun localUri(uri: Uri?) = uri?.scheme in setOf("content", "file")
}
