package com.galaxyssi.glasses

import android.content.ContentValues
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/** CameraX keeps the preview and silent video inside GalaxySSI, so the ASR microphone remains active. */
internal class GlassesCamera(
    private val activity: ComponentActivity,
    private val previewView: PreviewView,
    private val report: (String) -> Unit,
    private val onWifiQr: (String) -> Unit
) : AutoCloseable {
    private var provider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var closed = false
    private var startingRecording = false
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private var analysis: ImageAnalysis? = null
    private var scanning = false

    val isRecording: Boolean get() = recording != null

    fun open() {
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            if (closed || activity.isDestroyed) return@addListener
            runCatching {
                val cameraProvider = future.get()
                val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                val photo = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
                val recorder = Recorder.Builder().setQualitySelector(
                    QualitySelector.fromOrderedList(listOf(Quality.HD, Quality.SD),
                        FallbackStrategy.lowerQualityOrHigherThan(Quality.SD))
                ).build()
                val video = VideoCapture.withOutput(recorder)
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(activity, CameraSelector.DEFAULT_BACK_CAMERA, preview, photo, video)
                provider = cameraProvider
                imageCapture = photo
                videoCapture = video
                report(activity.getString(R.string.glasses_copy_camera_ready_say_take_photo_or_start_video))
            }.onFailure { report(activity.getString(R.string.glasses_copy_cannot_start_camera, it.message)) }
        }, ContextCompat.getMainExecutor(activity))
    }

    fun takePhoto() {
        if (scanning) { report(activity.getString(R.string.glasses_copy_finish_scanning_the_wi_fi_code_first)); return }
        if (isRecording) { report(activity.getString(R.string.glasses_copy_stop_recording_before_taking_a_photo)); return }
        val capture = imageCapture ?: run { report(activity.getString(R.string.glasses_copy_camera_not_ready)); return }
        val name = "GalaxySSI_${stamp()}.jpg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "DCIM/GalaxySSI")
        }
        val output = ImageCapture.OutputFileOptions.Builder(
            activity.contentResolver, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values
        ).build()
        capture.takePicture(output, ContextCompat.getMainExecutor(activity), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: ImageCapture.OutputFileResults) { if (!closed) report(activity.getString(R.string.glasses_copy_photo_saved, name)) }
            override fun onError(error: ImageCaptureException) { if (!closed) report(activity.getString(R.string.glasses_copy_photo_failed, error.message)) }
        })
    }

    fun startVideo() {
        if (scanning) { report(activity.getString(R.string.glasses_copy_finish_scanning_the_wi_fi_code_first)); return }
        if (recording != null || startingRecording) { report(activity.getString(R.string.glasses_copy_recording)); return }
        val capture = videoCapture ?: run { report(activity.getString(R.string.glasses_copy_camera_not_ready)); return }
        val name = "GalaxySSI_${stamp()}.mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "DCIM/GalaxySSI")
        }
        val output = MediaStoreOutputOptions.Builder(
            activity.contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        ).setContentValues(values).build()
        startingRecording = true
        try {
            // Do not call withAudioEnabled(): the microphone stays with offline speech recognition.
            recording = capture.output.prepareRecording(activity, output).start(ContextCompat.getMainExecutor(activity)) { event ->
                when (event) {
                    is VideoRecordEvent.Start -> { startingRecording = false; report(activity.getString(R.string.glasses_copy_recording_say_stop_video)) }
                    is VideoRecordEvent.Finalize -> {
                        startingRecording = false
                        recording = null
                        if (event.hasError()) report(activity.getString(R.string.glasses_copy_recording_failed, event.error))
                        else if (!closed) report(activity.getString(R.string.glasses_copy_video_saved, name))
                    }
                }
            }
        } catch (error: Exception) {
            startingRecording = false
            report(activity.getString(R.string.glasses_copy_cannot_start_recording, error.message))
        }
    }

    fun stopVideo() {
        val current = recording ?: run { report(activity.getString(R.string.glasses_copy_no_recording_in_progress)); return }
        current.stop()
        report(activity.getString(R.string.glasses_copy_saving_video))
    }

    fun scanWifi() {
        if (isRecording) { report(activity.getString(R.string.glasses_copy_stop_recording_before_scanning_the_wi_fi_code)); return }
        val cameraProvider = provider ?: run { report(activity.getString(R.string.glasses_copy_camera_not_ready)); return }
        if (scanning) { report(activity.getString(R.string.glasses_copy_scanning_wi_fi_code)); return }
        scanning = true
        val analyzer = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
        analysis = analyzer
        val reader = MultiFormatReader().apply {
            setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE)))
        }
        analyzer.setAnalyzer(analysisExecutor) { frame ->
            try {
                if (!scanning) return@setAnalyzer
                val raw = decodeQr(frame, reader) ?: return@setAnalyzer
                // Ignore other QR codes; only the phone-generated provisioning format is accepted.
                if (runCatching { WifiQrProvisioning.parse(raw) }.isFailure) return@setAnalyzer
                scanning = false
                activity.runOnUiThread {
                    if (!closed) { onWifiQr(raw); stopWifiScan() }
                }
            } finally { frame.close() }
        }
        runCatching {
            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(activity, CameraSelector.DEFAULT_BACK_CAMERA,
                Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }, analyzer)
            report(activity.getString(R.string.glasses_copy_look_at_the_galaxyssi_wi_fi_qr_code))
        }.onFailure { scanning = false; analyzer.clearAnalyzer(); report(activity.getString(R.string.glasses_copy_cannot_scan_wi_fi_code, it.message)); open() }
    }

    private fun stopWifiScan() {
        scanning = false
        analysis?.clearAnalyzer()
        analysis = null
        open()
    }

    private fun decodeQr(frame: ImageProxy, reader: MultiFormatReader): String? {
        val plane = frame.planes.firstOrNull() ?: return null
        val width = frame.width
        val height = frame.height
        val bytes = ByteArray(width * height)
        val buffer = plane.buffer
        val stride = plane.rowStride
        for (y in 0 until height) {
            buffer.position(y * stride)
            buffer.get(bytes, y * width, width)
        }
        val source = PlanarYUVLuminanceSource(bytes, width, height, 0, 0, width, height, false)
        fun attempt(value: com.google.zxing.LuminanceSource): String? = runCatching {
            reader.decodeWithState(BinaryBitmap(HybridBinarizer(value))).text
        }.getOrNull().also { reader.reset() }
        return attempt(source) ?: if (source.isRotateSupported) attempt(source.rotateCounterClockwise()) else null
    }

    override fun close() {
        closed = true
        scanning = false
        analysis?.clearAnalyzer()
        analysis = null
        recording?.stop()
        recording = null
        provider?.unbindAll()
        provider = null
        imageCapture = null
        videoCapture = null
        analysisExecutor.shutdownNow()
    }

    private fun stamp(): String = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
}
