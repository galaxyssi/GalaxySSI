package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCameraUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun launch() = ActivityScenario.launch<HealthCameraActivity>(Intent(instrumentation.targetContext, HealthCameraActivity::class.java)
        .putExtra("capture_camera", false))
    @Test fun collectionPageOffersRealActionsWithoutStartingTheCameraOrShowingBottomTabs() {
        launch().use { scenario ->
            awaitPage(scenario)
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup
                assertEquals(7, root.childCount)
                val texture = descendants(root).filterIsInstance<TextureView>().single()
                assertEquals(View.GONE, (texture.parent as View).visibility)
                val all = descendants(root).filterIsInstance<TextView>().map { it.text.toString() }
                assertTrue(activity.getString(R.string.health_photo_start_recognition) in all)
                assertTrue(activity.getString(R.string.health_manual) in all)
                assertTrue(activity.getString(R.string.health_choose_images) in all)
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try { File(instrumentation.targetContext.getExternalFilesDir(null), "health-camera-draft-ui.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                } } finally { bitmap.recycle() }
            }
        }
    }
    @Test fun backgroundClearsPhotoViewsAndRecreationKeepsTheSameFilesOnlyMode() {
        launch().use { scenario ->
            awaitPage(scenario)
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup
                assertEquals(0, (root.getChildAt(3) as ViewGroup).childCount)
                assertEquals("", (root.getChildAt(6) as TextView).text.toString())
            }
            scenario.moveToState(Lifecycle.State.RESUMED); awaitPage(scenario)
            scenario.recreate(); awaitPage(scenario)
            scenario.onActivity { activity -> assertEquals(View.GONE, (descendants(activity.window.decorView).filterIsInstance<TextureView>().single().parent as View).visibility) }
        }
    }

    @Test fun preparedReportOffersTheSuggestedCropBeforeRecognitionWithoutStartingTheCamera() {
        val context = instrumentation.targetContext
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val batch = HealthPhotoBatch(UUID.randomUUID().toString(), "report", System.currentTimeMillis())
        val job = HealthImportJob(UUID.randomUUID().toString(), "content://fixture/report", System.currentTimeMillis(),
            mode = "report", name = "synthetic-report.png", mime = "image/png", captureBatch = batch.id)
        val bytes = syntheticHealthPaper()
        try {
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
                store.createCaptureBatch(batch)
                store.addCaptureJob(batch.id, job)
                val original = store.importOriginal(job.id, bytes.inputStream(), job.name, job.mime, "file")
                store.updateJob(job.id) { it.copy(originalId = original.id) }
                assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context).run(store, job.id, prepareCapture = true))
                val expected = requireNotNull(store.capturePage(job.id)?.quality?.suggestedCrop)
                assertTrue(expected.left in 155..195 && expected.top in 85..120)
                assertArrayEquals(bytes, store.input(original).use { it.readBytes() })
                val intent = Intent(context, HealthCameraActivity::class.java).putExtra("capture_camera", false)
                    .putExtra("capture_batch", batch.id).putExtra("health_camera_test_id", names.fixture)
                ActivityScenario.launch<HealthCameraActivity>(intent).use { scenario ->
                    awaitPage(scenario)
                    scenario.onActivity { activity ->
                        val views = descendants(activity.window.decorView)
                        assertEquals(View.GONE, (views.filterIsInstance<TextureView>().single().parent as View).visibility)
                        assertTrue(views.filterIsInstance<TextView>().any { it.text == activity.getString(R.string.health_photo_edges_found) })
                        assertTrue(views.any { it.contentDescription == activity.getString(R.string.health_photo_suggested_crop) && it.isEnabled })
                    }
                    val deadline = SystemClock.elapsedRealtime() + 10_000
                    var previewReady = false
                    do {
                        scenario.onActivity { activity ->
                            previewReady = descendants(activity.window.decorView).filterIsInstance<ImageView>()
                                .any { it.contentDescription == original.name && it.drawable != null }
                        }
                        if (!previewReady) SystemClock.sleep(50)
                    } while (!previewReady && SystemClock.elapsedRealtime() < deadline)
                    assertTrue(previewReady)
                    instrumentation.waitForIdleSync()
                    instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                        try { File(context.getExternalFilesDir(null), "health-report-paper-edges.png").outputStream().use {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                        } } finally { bitmap.recycle() }
                    }
                }
                assertNull(store.page(job.id, 1))
                assertFalse(store.captureBatch(batch.id)!!.submitted)
                assertEquals(expected, store.capturePage(job.id)?.quality?.suggestedCrop)
            }
        } finally { bytes.fill(0); clearHealthOverviewFixture(context, names) }
    }
    @Test fun manualFallbackReallyOpensTheNativeEditor() {
        val scenario = ActivityScenario.launch<HealthCenterActivity>(Intent(instrumentation.targetContext, HealthCenterActivity::class.java).putExtra("health_manual", true))
        scenario.use {
            val deadline = SystemClock.elapsedRealtime() + 10_000
            var ready = false
            do { it.onActivity { activity -> ready = descendants(activity.body).any { view -> view.tag == "health-field-systolic" } }
                if (!ready) SystemClock.sleep(50)
            } while (!ready && SystemClock.elapsedRealtime() < deadline)
            assertTrue(ready)
        }
    }
    private fun awaitPage(scenario: ActivityScenario<HealthCameraActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        do {
            var ready = false
            scenario.onActivity { activity -> ready = descendants(activity.window.decorView).filterIsInstance<TextView>()
                .any { it.text.toString() == activity.getString(R.string.health_photo_start_recognition) } }
            if (ready) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Native page collection did not load")
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}

internal fun syntheticHealthPaper(): ByteArray {
    val bitmap = Bitmap.createBitmap(900, 1200, Bitmap.Config.ARGB_8888)
    try {
        bitmap.eraseColor(0xff384448.toInt())
        val canvas = Canvas(bitmap)
        val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        canvas.drawRect(160f, 134f, 716f, 1050f, pen)
        pen.color = Color.BLACK
        pen.textSize = 35f
        for (y in 285..920 step 96) canvas.drawText("Glucose 5.4 mmol/L", 240f, y.toFloat(), pen)
        return ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray() }
    } finally { bitmap.recycle() }
}
