package com.galaxyssi.watch

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import android.view.View
import android.widget.ImageView
import com.galaxyssi.chat.AgentBoundedWebService
import com.galaxyssi.chat.AgentNativeToolCancellationSource
import com.galaxyssi.chat.AgentPinnedOkHttpWebTransport
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Image
import org.commonmark.node.Text
import org.commonmark.parser.Parser
import java.util.concurrent.Executors

/** Show discovered web images using the same public-address policy as Android web tools. */
internal object WatchReplyImages {
    private val workers = Executors.newFixedThreadPool(2)
    private val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport())
    private val cache = object : LruCache<String, Bitmap>(2_000_000) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    fun views(context: Context, markdown: String): List<ImageView> {
        val images = linkedMapOf<String, String>()
        WatchRichReply.blocks(markdown).filter { it.type == com.galaxyssi.chat.AgentRichBlockType.IMAGE }
            .filter { it.uri.startsWith("https://") }.take(3).forEach { images[it.uri] = it.title }
        Parser.builder().build().parse(markdown).accept(object : AbstractVisitor() {
            override fun visit(image: Image) {
                if (!image.destination.startsWith("https://") || images.size >= 3) return
                val alt = StringBuilder()
                image.accept(object : AbstractVisitor() { override fun visit(text: Text) { alt.append(text.literal) } })
                images[image.destination] = alt.toString()
            }
        })
        return images.map { (url, alt) -> object : ImageView(context) {
            private var source: AgentNativeToolCancellationSource? = null
            init { contentDescription = alt; scaleType = ScaleType.FIT_CENTER; adjustViewBounds = true }
            override fun onAttachedToWindow() {
                super.onAttachedToWindow()
                cache.get(url)?.let { setImageBitmap(it); return }
                val cancellation = AgentNativeToolCancellationSource(); source = cancellation
                workers.execute {
                    val bitmap = runCatching {
                        val bytes = web.download(url, maxBytes = 1_500_000, timeoutMillis = 12_000,
                            cancellationToken = cancellation.token).body
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                        require(bounds.outWidth > 0 && bounds.outHeight > 0)
                        var sample = 1
                        while (bounds.outWidth / sample > 600 || bounds.outHeight / sample > 600) sample *= 2
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
                    }.getOrNull()
                    if (bitmap != null) cache.put(url, bitmap)
                    post {
                        if (source !== cancellation || cancellation.token.isCancellationRequested) return@post
                        if (bitmap != null) setImageBitmap(bitmap) else visibility = View.GONE
                    }
                }
            }
            override fun onDetachedFromWindow() { source?.cancel(); source = null; super.onDetachedFromWindow() }
        } }
    }
}
