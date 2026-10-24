package com.galaxyssi.chat

import android.app.Dialog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import android.util.LruCache
import android.view.Gravity
import android.view.View
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Future
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Public news images have bounded, unencrypted caches, separate from private chat attachments. */
internal object AttentionArticleImages {
    private const val MAX_BYTES = 8 * 1024 * 1024L
    private const val DISK_BYTES = 64 * 1024 * 1024L
    private val executor = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(64))
    private val main = Handler(Looper.getMainLooper())
    private val bitmaps = object : LruCache<String, Bitmap>(8 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
        policy = AgentWebPolicy(maxTimeoutMillis = 20_000))
    private val fileLocks = Array(8) { Any() }

    fun load(context: Context, source: String, size: Int, done: (Bitmap?) -> Unit): Future<*>? {
        val key = "$size:$source"
        bitmaps.get(key)?.let { done(it); return null }
        val app = context.applicationContext
        return runCatching { executor.submit {
            val bitmap = runCatching {
                val file = file(app, source)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.path, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 100_000_000)
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / sample > size) sample *= 2
                BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
            }.onFailure { failure ->
                if (BuildConfig.DEBUG) android.util.Log.w("AttentionArticleImages", "Public image loading failed", failure)
            }.getOrNull()
            if (bitmap != null && bitmap.allocationByteCount <= bitmaps.maxSize()) bitmaps.put(key, bitmap)
            main.post { done(bitmap) }
        } }.getOrElse { main.post { done(null) }; null }
    }

    private fun file(context: Context, source: String): File {
        require(AttentionArticleDocumentParser.imageUrl(source, source) != null)
        val hash = MessageDigest.getInstance("SHA-256").digest(source.toByteArray()).joinToString("") { "%02x".format(it) }
        val directory = File(context.cacheDir, "attention-public-images-v1").apply { mkdirs() }
        val file = File(directory, hash)
        return synchronized(fileLocks[(hash.hashCode() and Int.MAX_VALUE) % fileLocks.size]) {
            if (file.isFile && file.length() in 1..MAX_BYTES) {
                file.setLastModified(System.currentTimeMillis())
                return@synchronized file
            }
            val result = web.download(source, MAX_BYTES, 20_000L, AgentNativeToolCancellationToken.NONE) {
                if (Thread.currentThread().isInterrupted) throw InterruptedException()
            }
            try {
                require(result.contentType.startsWith("image/"))
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(result.body, 0, result.body.size, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0)
                val atomic = AtomicFile(file)
                val output = atomic.startWrite()
                try { output.write(result.body); atomic.finishWrite(output) }
                catch (failure: Throwable) { atomic.failWrite(output); throw failure }
                synchronized(this) {
                    val files = directory.listFiles()?.filter { it.name.length == 64 }?.sortedBy(File::lastModified).orEmpty()
                    var total = files.sumOf(File::length)
                    for (old in files) {
                        if (total <= DISK_BYTES) break
                        val size = old.length()
                        if (old != file && old.delete()) total -= size
                    }
                }
                file
            } finally { result.body.fill(0) }
        }
    }
}

internal class AttentionArticleImageView(context: Context, private val image: AttentionArticleBlock,
    private val thumbnail: Boolean = false) : ImageView(context) {
    private var generation = 0
    private var job: Future<*>? = null
    private var requested = false
    private val visible = ViewTreeObserver.OnScrollChangedListener { loadWhenVisible() }

    init {
        contentDescription = image.text.ifBlank { context.getString(R.string.attention_news_image) }
        scaleType = if (thumbnail) ScaleType.CENTER_CROP else ScaleType.FIT_CENTER
        setBackgroundColor(context.getColor(R.color.separator))
        setOnClickListener { fullscreen() }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (thumbnail) { super.onMeasure(widthMeasureSpec, heightMeasureSpec); return }
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val ratio = if (image.width > 0 && image.height > 0) image.height.toDouble() / image.width else 0.625
        val height = (width * ratio.coerceIn(0.3, 1.2)).toInt()
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnScrollChangedListener(visible)
        post(::loadWhenVisible)
    }

    override fun onDetachedFromWindow() {
        generation++; requested = false; job?.cancel(true); job = null
        if (viewTreeObserver.isAlive) viewTreeObserver.removeOnScrollChangedListener(visible)
        setImageDrawable(null)
        super.onDetachedFromWindow()
    }

    private fun loadWhenVisible() {
        if (requested || !isAttachedToWindow || !isShown || !getGlobalVisibleRect(android.graphics.Rect())) return
        requested = true
        val token = ++generation
        job = AttentionArticleImages.load(context, image.url, if (thumbnail) 384 else 1280) { bitmap ->
            if (token == generation && isAttachedToWindow) {
                if (bitmap != null) {
                    setImageBitmap(bitmap)
                    setOnClickListener { fullscreen() }
                } else {
                    setImageResource(R.drawable.ic_conversation_external)
                    setOnClickListener { requested = false; loadWhenVisible() }
                }
            }
        }
    }

    private fun fullscreen() {
        val dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        val imageView = ImageView(context).apply { scaleType = ScaleType.FIT_CENTER; contentDescription = this@AttentionArticleImageView.contentDescription }
        val viewport = GalaxySSIPinchZoomViewport(context).apply { attach(imageView) }
        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            addView(viewport, FrameLayout.LayoutParams(-1, -1))
            addView(ImageButton(context).apply {
                setImageResource(R.drawable.ic_chevron_down)
                rotation = 90f
                imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
                setBackgroundColor(Color.TRANSPARENT)
                contentDescription = context.getString(android.R.string.cancel)
                setOnClickListener { dialog.dismiss() }
            }, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.START))
        }
        dialog.setContentView(root)
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        dialog.show()
        val request = AttentionArticleImages.load(context, image.url, 2048) {
            if (dialog.isShowing && it != null) imageView.setImageBitmap(it)
        }
        dialog.setOnDismissListener { request?.cancel(true); imageView.setImageDrawable(null) }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
