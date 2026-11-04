package com.galaxyssi.chat

import android.view.TextureView
import androidx.test.core.app.ActivityScenario
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

/** Exercises close/error ordering without opening a camera or acquiring an image. */
class HealthCameraCallbackDeviceTest {
    @Test fun captureFailureMustStillBeReportedWhenThePageStopsBeforeItsCallbackRuns() {
        ActivityScenario.launch(HealthCenterActivity::class.java).use { scenario ->
            val id = UUID.randomUUID().toString(); val result = mutableListOf<String?>(); val delivered = CountDownLatch(1)
            lateinit var controller: HealthCameraController
            try {
                scenario.onActivity { activity ->
                    controller = HealthCameraController(activity, TextureView(activity), { _, _ -> }, { _, bytes -> bytes.fill(0) }, { value ->
                        synchronized(result) { result += value }; if (value == id) delivered.countDown()
                    })
                    HealthCameraController::class.java.getDeclaredField("pending").apply { isAccessible = true }.set(controller, id)
                    HealthCameraController::class.java.getDeclaredMethod("fail", Int::class.javaPrimitiveType).apply { isAccessible = true }.invoke(controller, 0)
                    controller.stop()
                }
                assertTrue("Stopped photo must not remain indefinitely in COPYING", delivered.await(5, TimeUnit.SECONDS))
                assertEquals(listOf(id), synchronized(result) { result.filterNotNull() })
            } finally { scenario.onActivity { controller.dispose() } }
        }
    }
    @Test fun closingAPendingCaptureReportsOneFailureAndDisposalIsIdempotent() {
        ActivityScenario.launch(HealthCenterActivity::class.java).use { scenario ->
            val id = UUID.randomUUID().toString(); val delivered = CountDownLatch(1)
            val ids = mutableListOf<String?>(); lateinit var controller: HealthCameraController
            try {
                scenario.onActivity { activity ->
                    controller = HealthCameraController(activity, TextureView(activity), { _, _ -> }, { _, bytes -> bytes.fill(0) }, {
                        synchronized(ids) { ids += it }; if (it == id) delivered.countDown()
                    })
                    HealthCameraController::class.java.getDeclaredField("pending").apply { isAccessible = true }.set(controller, id)
                    controller.stop()
                }
                assertTrue(delivered.await(5, TimeUnit.SECONDS))
                assertEquals(listOf(id), synchronized(ids) { ids.filterNotNull() })
            } finally { scenario.onActivity { controller.dispose(); controller.dispose() } }
        }
    }
}
