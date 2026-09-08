package com.galaxyssi.chat

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.math.max

/** A user-visible, foreground-only camera. Frames are persisted only on a voice turn. */
internal class AgentVoiceCameraPreview(
    private val activity: MainActivity,
    private val onActiveChanged: (Boolean) -> Unit,
    private val onFailure: () -> Unit
) {
    val view = FrameLayout(activity).apply { setBackgroundColor(Color.BLACK); visibility = View.GONE; clipChildren = true }
    val texture = TextureView(activity)
    val close = button(R.drawable.ic_agent_progress_close, R.string.voice_call_camera_close)
    val flip = button(android.R.drawable.ic_menu_rotate, R.string.voice_call_camera_flip)
    private val status = TextView(activity).apply {
        textSize = 12f
        setTextColor(Color.WHITE)
        setBackgroundColor(0x88000000.toInt())
        setPadding(activity.dp(10), activity.dp(6), activity.dp(10), activity.dp(6))
    }
    private val main = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(CameraManager::class.java)
    private val displays = activity.getSystemService(DisplayManager::class.java)
    private var device: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var surface: Surface? = null
    private var characteristics: CameraCharacteristics? = null
    private var bufferSize = Size(640, 480)
    private var opening = false
    private var generation = 0L
    private var lensFacing = CameraCharacteristics.LENS_FACING_BACK
    var active = false
        private set
    var frames = 0L
        private set
    val ready: Boolean get() = active && captureSession != null && frames > 0L && texture.isAvailable
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
        override fun onDisplayChanged(displayId: Int) { if (active) transform() }
    }

    init {
        view.addView(texture, FrameLayout.LayoutParams(-1, -1))
        view.addView(status, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.START).apply {
            topMargin = activity.dp(8); marginStart = activity.dp(8)
        })
        view.addView(close, FrameLayout.LayoutParams(activity.dp(48), activity.dp(48), Gravity.TOP or Gravity.END))
        view.addView(flip, FrameLayout.LayoutParams(activity.dp(48), activity.dp(48), Gravity.BOTTOM or Gravity.END))
        close.setOnClickListener { stop() }
        flip.setOnClickListener {
            if (active) {
                lensFacing = if (lensFacing == CameraCharacteristics.LENS_FACING_BACK) CameraCharacteristics.LENS_FACING_FRONT
                    else CameraCharacteristics.LENS_FACING_BACK
                closeCamera()
                frames = 0
                generation++
                open()
            }
        }
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) { open() }
            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) { transform() }
            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean { generation++; closeCamera(); return true }
            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {
                if (active) {
                    frames++
                    if (frames == 1L) status.setText(R.string.voice_call_camera_active)
                }
            }
        }
    }

    fun start() {
        if (active) return
        active = true
        frames = 0
        generation++
        view.visibility = View.VISIBLE
        status.setText(R.string.voice_call_camera_starting)
        displays.registerDisplayListener(displayListener, main)
        onActiveChanged(true)
        if (texture.isAvailable) open()
    }

    fun stop() {
        active = false
        generation++
        frames = 0
        closeCamera()
        displays.unregisterDisplayListener(displayListener)
        view.visibility = View.GONE
        onActiveChanged(false)
    }

    @SuppressLint("MissingPermission")
    private fun open() {
        if (!active || opening || device != null || !texture.isAvailable) return
        val token = generation
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) { fail(token); return }
        try {
            val cameras = manager.cameraIdList.map { it to manager.getCameraCharacteristics(it) }
            val selected = cameras.firstOrNull { it.second.get(CameraCharacteristics.LENS_FACING) == lensFacing }
                ?: cameras.firstOrNull() ?: error("No camera")
            characteristics = selected.second
            flip.visibility = if (cameras.map { it.second.get(CameraCharacteristics.LENS_FACING) }.distinct().size > 1) View.VISIBLE else View.GONE
            val sizes = selected.second.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(SurfaceTexture::class.java).orEmpty()
            bufferSize = sizes.filter { max(it.width, it.height) <= 1280 }
                .maxByOrNull { it.width.toLong() * it.height }
                ?: sizes.minByOrNull { it.width.toLong() * it.height } ?: error("No preview size")
            texture.surfaceTexture?.setDefaultBufferSize(bufferSize.width, bufferSize.height)
            transform()
            opening = true
            status.setText(R.string.voice_call_camera_starting)
            main.postDelayed({ if (active && generation == token && !ready) fail(token) }, 8_000L)
            manager.openCamera(selected.first, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    if (!active || token != generation) { camera.close(); return }
                    opening = false
                    device = camera
                    createSession(camera, token)
                }
                override fun onDisconnected(camera: CameraDevice) { camera.close(); fail(token) }
                override fun onError(camera: CameraDevice, error: Int) { camera.close(); fail(token) }
            }, main)
        } catch (_: Exception) { fail(token) }
    }

    private fun createSession(camera: CameraDevice, token: Long) {
        try {
            val target = Surface(texture.surfaceTexture ?: error("Preview detached")).also { surface = it }
            camera.createCaptureSession(listOf(target), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (!active || generation != token || device !== camera) { session.close(); return }
                    captureSession = session
                    try {
                        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(target)
                            val modes = characteristics?.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
                            if (modes.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)) {
                                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                            }
                        }
                        session.setRepeatingRequest(request.build(), null, main)
                    } catch (_: Exception) { fail(token) }
                }
                override fun onConfigureFailed(session: CameraCaptureSession) { session.close(); fail(token) }
            }, main)
        } catch (_: Exception) { fail(token) }
    }

    private fun transform() {
        val camera = characteristics ?: return
        val width = texture.width.toFloat()
        val height = texture.height.toFloat()
        if (width <= 0 || height <= 0) return
        val rotation = (texture.display?.rotation ?: Surface.ROTATION_0) * 90
        val sensor = camera.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val sign = if (camera.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT) 1 else -1
        val swapped = (sensor - rotation * sign + 360) % 180 != 0
        val sourceSwapped = if (sensor == 0) !swapped else swapped
        val scaleX = width / if (sourceSwapped) bufferSize.height else bufferSize.width
        val scaleY = height / if (sourceSwapped) bufferSize.width else bufferSize.height
        val fill = max(scaleX, scaleY)
        texture.setTransform(Matrix().apply {
            if (swapped) setScale(fill / scaleX, fill / scaleY, width / 2, height / 2)
            else setScale(height / width * fill / scaleY, width / height * fill / scaleX, width / 2, height / 2)
            postRotate(-rotation.toFloat(), width / 2, height / 2)
        })
    }

    suspend fun captureFrame(): File = withContext(Dispatchers.Main.immediate) {
        check(ready) { "Camera is not ready" }
        val token = generation
        val scale = (1280f / max(texture.width, texture.height)).coerceAtMost(1f)
        val bitmap = checkNotNull(texture.getBitmap((texture.width * scale).toInt(), (texture.height * scale).toInt()))
        val file = File(activity.cacheDir, "voice-camera-capture/${UUID.randomUUID()}.jpg")
        try {
            withContext(Dispatchers.IO) {
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
                file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it)) }
            }
            ensureActive()
            check(active && generation == token) { "Camera closed before the frame was ready" }
            file
        } catch (error: Throwable) {
            file.delete()
            throw error
        } finally { bitmap.recycle() }
    }

    private fun closeCamera() {
        opening = false
        runCatching { captureSession?.close() }
        captureSession = null
        runCatching { device?.close() }
        device = null
        surface?.release()
        surface = null
    }

    private fun fail(token: Long) {
        if (!active || generation != token) return
        stop()
        onFailure()
    }

    private fun button(icon: Int, label: Int) = ImageButton(activity).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(Color.WHITE)
        setBackgroundColor(0x66000000)
        setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        contentDescription = activity.getString(label)
        tooltipText = contentDescription
    }
}
