package com.galaxyssi.watch

import android.content.Context
import android.graphics.*
import android.view.*
import android.widget.*
import okhttp3.Cache
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.*

internal object WatchMapProjection {
    fun point(lat: Double, lon: Double, zoom: Int): Pair<Double, Double> {
        require(lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0 && zoom in 2..18)
        val size = 256.0 * (1 shl zoom)
        val radians = Math.toRadians(lat.coerceIn(-85.05112878, 85.05112878))
        return (lon + 180) / 360 * size to (1 - ln(tan(radians) + 1 / cos(radians)) / Math.PI) / 2 * size
    }
}

/** Coordinates use the zoom-zero world (256 pixels); gestures preserve the point under the fingers. */
internal class WatchMapViewport(lat: Double, lon: Double) {
    var zoom = 16.0
        private set
    var x = WatchMapProjection.point(lat, lon, 2).first / 4
        private set
    var y = WatchMapProjection.point(lat, lon, 2).second / 4
        private set
    val scale get() = 2.0.pow(zoom)
    fun pan(dx: Double, dy: Double) { x -= dx / scale; y -= dy / scale; constrain() }
    fun centerOn(lat: Double, lon: Double, offsetX: Double = 0.0, offsetY: Double = 0.0) {
        val point = WatchMapProjection.point(lat, lon, 2)
        x = point.first / 4 - offsetX / scale
        y = point.second / 4 - offsetY / scale
        constrain()
    }
    fun scaleBy(factor: Double, focusX: Double, focusY: Double) {
        if (!factor.isFinite() || factor <= 0) return
        val oldScale = scale
        zoom = (zoom + ln(factor) / ln(2.0)).coerceIn(2.0, 18.0)
        x += focusX / oldScale - focusX / scale
        y += focusY / oldScale - focusY / scale
        constrain()
    }
    private fun constrain() { x = ((x % 256) + 256) % 256; y = y.coerceIn(0.0, 256.0) }
}

/** Fetches only tiles in a visible viewport. No tracking, prefetch or offline downloads. */
internal class WatchLocationMap(context: Context, private val fix: WatchLocationFix) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val viewport = WatchMapViewport(fix.latitude, fix.longitude)
    private var lastX = 0f
    private var lastY = 0f
    private var downX = 0f
    private var downY = 0f
    private var horizontalDrag = false
    private var usedMultiplePointers = false
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val arrowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val arrowPath = Path()
    private val controlBounds = Rect()
    private var pressedArrow = -1
    private var repeatingArrow = false
    private var panAnimation: android.animation.ValueAnimator? = null
    private val repeatPan = object : Runnable {
        override fun run() {
            if (pressedArrow !in 0..3 || !isShown || !hasWindowFocus()) return
            repeatingArrow = true
            moveArrow(pressedArrow, 0.012)
            postDelayed(this, 32)
        }
    }
    private fun updateControlBounds() {
        if (!getLocalVisibleRect(controlBounds) || !controlBounds.intersect(0, 0, width, mapHeight())) controlBounds.setEmpty()
    }
    private fun arrowX(direction: Int) = when (direction) {
        1 -> controlBounds.right - 8 * density
        3 -> controlBounds.left + 8 * density
        4 -> controlBounds.right - 20 * density
        else -> controlBounds.exactCenterX()
    }
    private fun arrowY(direction: Int) = when (direction) {
        0 -> controlBounds.top + 8 * density
        2 -> controlBounds.bottom - 8 * density
        4 -> controlBounds.bottom - 20 * density
        else -> controlBounds.exactCenterY()
    }
    private fun arrowAt(x: Float, y: Float): Int {
        if (controlBounds.height() < 48 * density || !controlBounds.contains(x.toInt(), y.toInt())) return -1
        return (0..4).filter { abs(x - arrowX(it)) <= 20 * density && abs(y - arrowY(it)) <= 20 * density }
            .minByOrNull { (x - arrowX(it)).pow(2) + (y - arrowY(it)).pow(2) } ?: -1
    }
    private fun recenter() {
        panAnimation?.cancel()
        viewport.centerOn(fix.latitude, fix.longitude,
            (controlBounds.exactCenterX() - width / 2f).toDouble(),
            (controlBounds.exactCenterY() - mapHeight() / 2f).toDouble())
        invalidate()
    }
    private fun moveArrow(direction: Int, fraction: Double) {
        val dx = when (direction) { 1 -> -width * fraction; 3 -> width * fraction; else -> 0.0 }
        val dy = when (direction) { 0 -> mapHeight() * fraction; 2 -> -mapHeight() * fraction; else -> 0.0 }
        viewport.pan(dx, dy); invalidate()
    }
    private fun animateArrow(direction: Int) {
        panAnimation?.cancel()
        var previous = 0.0
        panAnimation = android.animation.ValueAnimator.ofFloat(0f, 0.25f).apply {
            duration = 200
            addUpdateListener {
                val fraction = (it.animatedValue as Float).toDouble()
                moveArrow(direction, fraction - previous); previous = fraction
            }
            start()
        }
    }
    private fun releaseArrow() {
        removeCallbacks(repeatPan); pressedArrow = -1; repeatingArrow = false; invalidate()
    }
    override fun performClick(): Boolean { super.performClick(); return true }
    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            viewport.scaleBy(detector.scaleFactor.toDouble(), (detector.focusX - width / 2f).toDouble(), (detector.focusY - mapHeight() / 2f).toDouble())
            invalidate()
            return true
        }
    }).apply { isQuickScaleEnabled = false; isStylusScaleEnabled = false }
    private fun mapHeight() = (height - ((if (tileHost().contains("openstreetmap.fr/")) 24 else 14) * density).toInt()).coerceAtLeast(1)
    override fun onTouchEvent(event: MotionEvent): Boolean {
        updateControlBounds()
        val indices = (0 until event.pointerCount).filter { event.actionMasked != MotionEvent.ACTION_POINTER_UP || it != event.actionIndex }
        val focusX = indices.map { event.getX(it) }.average().toFloat()
        val focusY = indices.map { event.getY(it) }.average().toFloat()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                panAnimation?.cancel(); releaseArrow()
                downX = focusX; downY = focusY
                pressedArrow = arrowAt(focusX, focusY)
                if (pressedArrow in 0..3) postDelayed(repeatPan, ViewConfiguration.getLongPressTimeout().toLong())
                invalidate()
                horizontalDrag = false; usedMultiplePointers = false
                parent?.requestDisallowInterceptTouchEvent(false)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                releaseArrow()
                usedMultiplePointers = true
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                if (abs(focusX - downX) > touchSlop || abs(focusY - downY) > touchSlop) releaseArrow()
                if (event.pointerCount >= 2) {
                    viewport.pan((focusX - lastX).toDouble(), (focusY - lastY).toDouble())
                    invalidate()
                } else if (!usedMultiplePointers) {
                    if (!horizontalDrag && abs(focusX - downX) > touchSlop && abs(focusX - downX) > abs(focusY - downY)) {
                        horizontalDrag = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                    }
                    // Vertical one-finger movement belongs to the conversation ScrollView.
                    if (horizontalDrag) {
                        viewport.pan((focusX - lastX).toDouble(), 0.0)
                        invalidate()
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                if (pressedArrow >= 0 && !repeatingArrow) {
                    if (pressedArrow == 4) recenter() else animateArrow(pressedArrow)
                    performClick()
                }
                releaseArrow(); parent?.requestDisallowInterceptTouchEvent(false)
            }
            MotionEvent.ACTION_CANCEL -> { releaseArrow(); parent?.requestDisallowInterceptTouchEvent(false) }
        }
        scaleDetector.onTouchEvent(event)
        lastX = focusX; lastY = focusY
        return true
    }
    private val scrollListener = ViewTreeObserver.OnScrollChangedListener { invalidate() }
    private val pending = mutableMapOf<String, okhttp3.Call>()
    private val failed = mutableSetOf<String>()
    private var generation = 0
    private val density = resources.displayMetrics.density
    init { contentDescription = context.getString(R.string.location_map); setBackgroundColor(Color.rgb(28, 34, 35)); isClickable = true }
    private fun client(): OkHttpClient = synchronized(Companion) {
        http ?: OkHttpClient.Builder().cache(Cache(File(context.cacheDir, "osm-tiles"), 12L * 1024 * 1024))
            .connectTimeout(8, TimeUnit.SECONDS).readTimeout(8, TimeUnit.SECONDS).callTimeout(12, TimeUnit.SECONDS)
            .addNetworkInterceptor { chain ->
                val response = chain.proceed(chain.request())
                if (response.header("Cache-Control") == null && response.header("Expires") == null)
                    response.newBuilder().header("Cache-Control", "public, max-age=604800").build() else response
            }.build().also { http = it }
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return
        val host = tileHost()
        val frenchTiles = host.contains("openstreetmap.fr/")
        val mapHeight = mapHeight()
        val zoom = floor(viewport.zoom).toInt()
        val tileSize = 256 * 2.0.pow(viewport.zoom - zoom)
        val left = viewport.x * viewport.scale - width / 2.0
        val top = viewport.y * viewport.scale - mapHeight / 2.0
        val count = 1 shl zoom
        val visible = Rect()
        val canLoad = isAttachedToWindow && isShown && getGlobalVisibleRect(visible)
        val needed = mutableSetOf<String>()
        canvas.save(); canvas.clipRect(0, 0, width, mapHeight)
        for (x in floor(left / tileSize).toInt()..floor((left + width - 1) / tileSize).toInt()) {
            for (y in floor(top / tileSize).toInt()..floor((top + mapHeight - 1) / tileSize).toInt()) {
                if (y !in 0 until count) continue
                val wrappedX = ((x % count) + count) % count
                val key = "$host/$zoom/$wrappedX/$y.png"
                needed.add(key)
                val destination = RectF((x * tileSize - left).toFloat(), (y * tileSize - top).toFloat(), ((x + 1) * tileSize - left).toFloat(), ((y + 1) * tileSize - top).toFloat())
                val bitmap = bitmaps.get(key)
                if (bitmap != null) canvas.drawBitmap(bitmap, null, destination, paint)
                else {
                    // Keep a cached lower-resolution tile visible while the next zoom level arrives.
                    for (levels in 1..minOf(4, zoom - 2)) {
                        val divisor = 1 shl levels
                        val parent = bitmaps.get("$host/${zoom - levels}/${wrappedX / divisor}/${y / divisor}.png") ?: continue
                        val size = 256 / divisor
                        val source = Rect((wrappedX % divisor) * size, (y % divisor) * size, (wrappedX % divisor + 1) * size, (y % divisor + 1) * size)
                        canvas.drawBitmap(parent, source, destination, paint)
                        break
                    }
                }
            }
        }
        pending.keys.filter { it !in needed }.forEach { pending.remove(it)?.cancel() }
        failed.retainAll(needed)
        if (canLoad) needed.filter { bitmaps.get(it) == null && it !in pending && it !in failed }.forEach { load(it) }
        val point = WatchMapProjection.point(fix.latitude, fix.longitude, 2)
        val dx = ((point.first / 4 - viewport.x + 384) % 256) - 128
        val markerX = (width / 2.0 + dx * viewport.scale).toFloat()
        val markerY = (mapHeight / 2.0 + (point.second / 4 - viewport.y) * viewport.scale).toFloat()
        paint.color = Color.WHITE; canvas.drawCircle(markerX, markerY, 6 * density, paint)
        paint.color = Color.rgb(0, 154, 218); canvas.drawCircle(markerX, markerY, 4 * density, paint)
        drawArrows(canvas)
        canvas.restore()
        paint.color = Color.BLACK; canvas.drawRect(0f, mapHeight.toFloat(), width.toFloat(), height.toFloat(), paint)
        paint.color = Color.LTGRAY; paint.textSize = 8 * density; paint.textAlign = Paint.Align.CENTER
        canvas.drawText("© OpenStreetMap contributors", width / 2f, height - (if (frenchTiles) 14 else 3) * density, paint)
        if (frenchTiles) canvas.drawText("Style: HOT · Tiles: OSM France", width / 2f, height - 3 * density, paint)
    }
    private fun drawArrows(canvas: Canvas) {
        updateControlBounds()
        if (controlBounds.height() < 48 * density) return
        arrowPaint.strokeWidth = 1.8f * density
        arrowPaint.setShadowLayer(density, 0f, 0f, Color.argb(170, 255, 255, 255))
        for (direction in 0..3) {
            arrowPaint.color = Color.argb(if (pressedArrow == direction) 255 else 210, 52, 62, 70)
            canvas.save()
            canvas.translate(arrowX(direction), arrowY(direction))
            canvas.rotate(direction * 90f)
            arrowPath.rewind()
            arrowPath.moveTo(-5 * density, 2.5f * density)
            arrowPath.lineTo(0f, -2.5f * density)
            arrowPath.lineTo(5 * density, 2.5f * density)
            canvas.drawPath(arrowPath, arrowPaint)
            canvas.restore()
        }
        // A small target ring returns the saved location to the visible center without changing zoom.
        arrowPaint.color = Color.argb(if (pressedArrow == 4) 255 else 210, 52, 62, 70)
        canvas.drawCircle(arrowX(4), arrowY(4), 7 * density, arrowPaint)
        canvas.drawCircle(arrowX(4), arrowY(4), 2 * density, arrowPaint)
    }
    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) { releaseArrow(); panAnimation?.cancel() }
    }
    private fun tileHost() = context.getSharedPreferences("watch-location", Context.MODE_PRIVATE)
        .getString("tile_base", "https://tile.openstreetmap.org")!!.trimEnd('/')
    private fun load(key: String) {
        if (!key.startsWith("https://")) { failed.add(key); return }
        val request = Request.Builder().url(key)
            .header("User-Agent", "GalaxySSI-Watch/0.2.29 (+https://github.com/galaxyssi/GalaxySSI)").build()
        val call = client().newCall(request); pending[key] = call
        val revision = generation
        workers.execute {
            var responseCode = 0
            val bitmap = runCatching { call.execute().use { response ->
                responseCode = response.code
                check(response.isSuccessful)
                val body = requireNotNull(response.body)
                val bytes = body.byteStream().use { it.readNBytes(600_001) }
                require(bytes.size <= 600_000)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                require(bounds.outWidth == 256 && bounds.outHeight == 256)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } }.onFailure { if (!call.isCanceled()) android.util.Log.w("WatchLocation", "tile_failed type=${it.javaClass.simpleName} status=$responseCode") }.getOrNull()
            post {
                // Completed tiles also refresh other cards and the enlarged map.
                if (bitmap != null) {
                    bitmaps.put(key, bitmap)
                    attachedViews.toList().forEach { it.invalidate() }
                }
                if (generation != revision) return@post
                if (pending[key] !== call) return@post
                pending.remove(key)
                if (bitmap == null && !call.isCanceled()) failed.add(key)
                invalidate()
            }
        }
    }
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        attachedViews.add(this)
        failed.clear()
        viewTreeObserver.addOnScrollChangedListener(scrollListener)
        invalidate()
    }
    override fun onDetachedFromWindow() {
        releaseArrow(); panAnimation?.cancel()
        viewTreeObserver.removeOnScrollChangedListener(scrollListener)
        attachedViews.remove(this)
        generation++; pending.values.forEach { it.cancel() }; pending.clear(); super.onDetachedFromWindow()
    }
    companion object {
        // Provider-qualified keys prevent mixing tiles from different map services.
        private val bitmaps = object : android.util.LruCache<String, Bitmap>(4 * 1024 * 1024) {
            override fun sizeOf(key: String, value: Bitmap) = value.byteCount
        }
        private val attachedViews = java.util.Collections.newSetFromMap(java.util.WeakHashMap<WatchLocationMap, Boolean>())
        private val workers = Executors.newFixedThreadPool(2)
        private var http: OkHttpClient? = null
        fun card(context: Context, fix: WatchLocationFix): View = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(WatchLocationMap(context, fix), LinearLayout.LayoutParams(-1, (140 * resources.displayMetrics.density).toInt()))
        }
    }
}
