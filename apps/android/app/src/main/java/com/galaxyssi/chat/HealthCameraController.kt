package com.galaxyssi.chat

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Size
import android.view.Surface
import android.view.TextureView

/** Rear camera only, visible foreground preview, and exactly one photo per explicit shutter press. */
internal class HealthCameraController(
    private val activity: Activity,
    val texture: TextureView,
    private val onReady: (Boolean, Boolean) -> Unit,
    private val onPhoto: (String, ByteArray) -> Unit,
    private val onFailure: (String?) -> Unit
) {
    private val thread = HandlerThread("health-camera").apply { start() }
    private val io = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(CameraManager::class.java)
    @Volatile private var generation = 0
    private var active = false
    private var disposed = false
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var surface: Surface? = null
    private var request: CaptureRequest.Builder? = null
    private var sensor = 90
    private var autoFocus = false
    private var flash = false
    private var torch = false
    private var pending: String? = null
    private var exposing = false
    private var previewSize = Size(640, 480)
    private var displayRotation = 0
    var frames = 0L
        private set
    init {
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) { if (active) open() }
            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) { if (active) transform() }
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) { if (active) frames++ }
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean { stop(); return true }
        }
    }
    fun start() {
        if (disposed || active) return
        active = true; frames = 0
        if (texture.isAvailable) open()
    }
    fun stop() {
        if (disposed) return
        active = false; generation++; frames = 0
        onReady(false, false)
        io.post { closeCamera() }
    }
    fun dispose() {
        if (disposed) return
        stop(); disposed = true
        io.post { closeCamera(); thread.quitSafely() }
    }
    private fun open() {
        if (!active || disposed || !texture.isAvailable) return
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) { onFailure(null); return }
        val token = ++generation
        val target = texture.surfaceTexture ?: return
        displayRotation = (texture.display?.rotation ?: Surface.ROTATION_0) * 90
        io.post { openCamera(token, target) }
        main.postDelayed({ if (active && generation == token && frames == 0L) { stop(); onFailure(null) } }, 8_000)
    }
    @SuppressLint("MissingPermission")
    private fun openCamera(token: Int, target: SurfaceTexture) {
        if (token != generation) return
        closeCamera()
        try {
            val id = manager.cameraIdList.firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
                ?: error("Rear camera unavailable")
            val info = manager.getCameraCharacteristics(id)
            val config = requireNotNull(info.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP))
            val jpeg = config.getOutputSizes(ImageFormat.JPEG).maxByOrNull { it.width.toLong() * it.height } ?: error("No JPEG stream")
            previewSize = config.getOutputSizes(SurfaceTexture::class.java).filter { maxOf(it.width, it.height) <= 1280 }
                .minWithOrNull(compareBy<Size> { kotlin.math.abs(it.width.toDouble() / it.height - jpeg.width.toDouble() / jpeg.height) }
                    .thenByDescending { it.width.toLong() * it.height }) ?: config.getOutputSizes(SurfaceTexture::class.java).minBy { it.width.toLong() * it.height }
            sensor = info.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            flash = info.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            val modes = info.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
            val focus = when { CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE in modes -> CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                CaptureRequest.CONTROL_AF_MODE_AUTO in modes -> CaptureRequest.CONTROL_AF_MODE_AUTO; else -> CaptureRequest.CONTROL_AF_MODE_OFF }
            autoFocus = focus != CaptureRequest.CONTROL_AF_MODE_OFF
            target.setDefaultBufferSize(previewSize.width, previewSize.height)
            val preview = Surface(target).also { surface = it }
            val images = ImageReader.newInstance(jpeg.width, jpeg.height, ImageFormat.JPEG, 2).also { reader = it }
            images.setOnImageAvailableListener({ source ->
                val image = runCatching { source.acquireNextImage() }.getOrNull() ?: return@setOnImageAvailableListener
                val ticket = pending
                if (token != generation || ticket == null) { image.close(); return@setOnImageAvailableListener }
                pending = null; exposing = false
                try {
                    val bytes = image.use { frame -> frame.planes[0].buffer.let { data -> ByteArray(data.remaining()).also(data::get) } }
                    try { onPhoto(ticket, bytes) } catch (failure: Throwable) { bytes.fill(0); throw failure }
                    resumePreview()
                } catch (_: Throwable) { main.post { onFailure(ticket) }; fail(token) }
            }, io)
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    if (generation != token) { camera.close(); return }
                    device = camera
                    try {
                        request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(preview); set(CaptureRequest.CONTROL_AF_MODE, focus); set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                        }
                        camera.createCaptureSession(listOf(preview, images.surface), object : CameraCaptureSession.StateCallback() {
                            override fun onConfigured(value: CameraCaptureSession) {
                                if (generation != token) { value.close(); return }
                                session = value; resumePreview()
                                main.post { if (active && token == generation) { transform(); onReady(true, flash) } }
                            }
                            override fun onConfigureFailed(value: CameraCaptureSession) { value.close(); fail(token) }
                        }, io)
                    } catch (_: Exception) { fail(token) }
                }
                override fun onDisconnected(camera: CameraDevice) { camera.close(); fail(token) }
                override fun onError(camera: CameraDevice, error: Int) { camera.close(); fail(token) }
            }, io)
        } catch (_: Exception) { fail(token) }
    }
    fun capture(id: String) {
        if (!active || disposed) { onFailure(id); return }
        val token = generation
        io.post {
            if (token != generation || pending != null || session == null) { main.post { onFailure(id) }; return@post }
            pending = id; exposing = false
            try {
                if (autoFocus) {
                    val builder = requireNotNull(request); builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START)
                    session!!.capture(builder.build(), object : CameraCaptureSession.CaptureCallback() {
                        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
                            val state = result.get(CaptureResult.CONTROL_AF_STATE)
                            if (state == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED || state == CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED) expose(token, id)
                        }
                    }, io)
                } else expose(token, id)
                io.postDelayed({ expose(token, id) }, 1_800)
                io.postDelayed({ if (generation == token && pending == id) fail(token) }, 8_000)
            } catch (_: Exception) { fail(token) }
        }
    }
    private fun expose(token: Int, id: String) {
        if (generation != token || pending != id || exposing) return
        exposing = true
        try {
            val capture = requireNotNull(device).createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                addTarget(requireNotNull(reader).surface)
                set(CaptureRequest.CONTROL_AF_MODE, request?.get(CaptureRequest.CONTROL_AF_MODE) ?: CaptureRequest.CONTROL_AF_MODE_OFF)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.FLASH_MODE, if (torch) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF)
                set(CaptureRequest.JPEG_ORIENTATION, (sensor - displayRotation + 360) % 360)
                set(CaptureRequest.JPEG_QUALITY, 95.toByte())
            }
            session!!.capture(capture.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureFailed(session: CameraCaptureSession, request: CaptureRequest, failure: CaptureFailure) { fail(token) }
            }, io)
        } catch (_: Exception) { fail(token) }
    }
    fun toggleTorch(enabled: Boolean) { io.post { if (flash) { torch = enabled; resumePreview() } } }
    private fun resumePreview() {
        try {
            val builder = request ?: return
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
            builder.set(CaptureRequest.FLASH_MODE, if (torch) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF)
            session?.setRepeatingRequest(builder.build(), null, io)
        } catch (_: Exception) { fail(generation) }
    }
    private fun transform() {
        if (texture.width <= 0 || texture.height <= 0) return
        val w = texture.width.toFloat(); val h = texture.height.toFloat()
        val relative = (sensor - (texture.display?.rotation ?: 0) * 90 + 360) % 360
        val bounds = RectF(0f, 0f, previewSize.width.toFloat(), previewSize.height.toFloat())
        val rotate = Matrix().apply { setRotate(relative.toFloat()) }; rotate.mapRect(bounds)
        val scale = minOf(w / bounds.width(), h / bounds.height())
        texture.setTransform(Matrix().apply {
            setScale(previewSize.width / w, previewSize.height / h); postRotate(relative.toFloat())
            postTranslate(-bounds.left, -bounds.top); postScale(scale, scale)
            postTranslate((w - bounds.width() * scale) / 2, (h - bounds.height() * scale) / 2)
        })
    }
    private fun fail(token: Int) {
        if (generation != token) return
        val id = pending; pending = null
        closeCamera()
        main.post {
            if (generation == token) { generation++; active = false; onReady(false, false); if (id == null) onFailure(null) }
            // A stale surface callback may not reopen the UI, but its persisted capture still needs an outcome.
            if (id != null) onFailure(id)
        }
    }
    private fun closeCamera() {
        val id = pending; pending = null; exposing = false
        runCatching { session?.close() }; session = null
        runCatching { device?.close() }; device = null
        runCatching { reader?.close() }; reader = null
        surface?.release(); surface = null; request = null; torch = false
        if (id != null) main.post { onFailure(id) }
    }
}
