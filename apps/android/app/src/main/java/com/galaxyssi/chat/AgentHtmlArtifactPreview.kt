package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors

/** Preview only managed, delivered files. Rendering never grants HTML access to their source URI. */
internal object AgentHtmlArtifactPreview {
    const val MAX_BYTES = 512 * 1024

    fun supports(block: AgentRichBlock): Boolean {
        if (block.type != AgentRichBlockType.FILE) return false
        val mime = block.mimeType.substringBefore(';').trim().lowercase(Locale.ROOT)
        return mime == "text/html" || (mime in setOf("", "application/octet-stream") &&
            block.title.substringAfterLast('.').lowercase(Locale.ROOT) in setOf("html", "htm"))
    }

    fun load(context: Context, block: AgentRichBlock): String {
        require(supports(block))
        val payload = block.actions.firstOrNull { it.verb in setOf("preview_runtime_artifact", "save_runtime_artifact") }
            ?.let { AgentRuntimeArtifactActionPayload.decode(it.value) }
        val bytes = if (block.metadata["runtime_artifact"] == "true") {
            requireNotNull(payload)
            require(payload.sizeBytes in 1..MAX_BYTES.toLong())
            val file = AgentRuntimeArtifactUi.resolve(context, payload).getOrThrow()
            file.inputStream().use(::readBounded)
        } else {
            val uri = Uri.parse(block.uri)
            require(uri.scheme == "content" && uri.authority in setOf(
                "${context.packageName}.local-attachments", "${context.packageName}.files"
            )) { "HTML has not been delivered to private attachment storage" }
            requireNotNull(context.contentResolver.openInputStream(uri)).use(::readBounded)
        }
        try {
            val expected = block.metadata["sha256"].orEmpty().ifBlank { payload?.sha256.orEmpty() }
            if (expected.isNotBlank()) {
                val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                require(actual.equals(expected, ignoreCase = true)) { "HTML artifact integrity check failed" }
            }
            return bytes.toString(Charsets.UTF_8)
        } finally { bytes.fill(0) }
    }

    internal fun readBounded(input: InputStream): ByteArray {
        val buffer = ByteArray(8192)
        val output = object : ByteArrayOutputStream() { fun wipe() { buf.fill(0); reset() } }
        try {
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= MAX_BYTES) { "HTML is too large for an inline preview" }
                output.write(buffer, 0, count)
            }
            require(output.size() > 0) { "HTML artifact is empty" }
            return output.toByteArray()
        } finally { buffer.fill(0); output.wipe() }
    }
}

/** Release script execution and decoded content when recycled, hidden, or backgrounded. */
internal class AgentHtmlArtifactView(
    private val activity: Activity,
    private val block: AgentRichBlock,
    attachment: View?,
    private val render: (String) -> View
) : LinearLayout(activity) {
    private val preview = LinearLayout(activity).apply { orientation = VERTICAL }
    private var generation = 0
    private var started = false

    init {
        orientation = VERTICAL
        addView(preview, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        if (attachment != null) addView(attachment)
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); startPreview() }

    override fun onDetachedFromWindow() { releasePreview(); super.onDetachedFromWindow() }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility == VISIBLE) startPreview() else releasePreview()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        if (isVisible) startPreview() else releasePreview()
    }

    private fun startPreview() {
        if (started || !isAttachedToWindow || !isShown || windowVisibility != VISIBLE) return
        started = true
        val token = ++generation
        preview.addView(TextView(activity).apply { setText(R.string.rich_output_loading) })
        val context = activity.applicationContext
        EXECUTOR.execute {
            val result = runCatching {
                if (block.type == AgentRichBlockType.HTML) {
                    require(AgentVisualOutputContract.htmlIssue(block.text) == null) { "Invalid inline HTML" }
                    block.text
                } else AgentHtmlArtifactPreview.load(context, block)
            }
            activity.runOnUiThread {
                if (token != generation || !isAttachedToWindow || activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                preview.removeAllViews()
                val view = result.mapCatching(render).getOrElse {
                    TextView(activity).apply { setText(R.string.rich_output_load_failed) }
                }
                preview.addView(view)
            }
        }
    }

    private fun releasePreview() {
        ++generation
        started = false
        val webViews = collectWebViews(preview)
        preview.removeAllViews()
        webViews.forEach {
            AgentRichPlaybackCoordinator.detach(it)
            it.stopLoading()
            (it.parent as? ViewGroup)?.removeView(it)
            it.destroy()
        }
    }

    private fun collectWebViews(view: View): List<WebView> = when (view) {
        is WebView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { collectWebViews(view.getChildAt(it)) }
        else -> emptyList()
    }

    private companion object {
        val EXECUTOR = Executors.newFixedThreadPool(2) { Thread(it, "galaxyssi-html-preview").apply { isDaemon = true } }
    }
}
