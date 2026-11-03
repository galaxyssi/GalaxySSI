package com.galaxyssi.chat

import android.content.Intent
import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageButton
import androidx.core.view.doOnLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Empty public surface only; never exports a real browser page or credentials. */
@RunWith(AndroidJUnit4::class)
class AgentBrowserUserSurfaceDeviceTest {
    @Test fun returnedNotificationClosesWithoutReopeningTheBrowser() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val application = context.applicationContext as Application
        val scope = AgentNativeJsonCodec.sha256(mapOf("public-returned-fixture" to UUID.randomUUID().toString()))
        val key = AgentBrowserUserRequest.key(scope, "public-returned-browser")
        val record = AgentBrowserUserRequest(key, UUID.randomUUID().toString(), scope, "public-session", "public-conversation",
            "public-turn", "public-caller", "public-workspace", "public-returned-browser", "public-page",
            "public-handoff", "returned", taskId = "public-task", modelLoopId = "public-loop")
        val store = AgentBrowserUserRequestStore(context)
        val closed = CountDownLatch(1)
        val observer = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityDestroyed(activity: Activity) {
                if (activity is AgentBrowserUserControlActivity &&
                    activity.intent.getStringExtra(AgentBrowserUserControl.EXTRA_KEY) == key) closed.countDown()
            }
            override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
        }
        application.registerActivityLifecycleCallbacks(observer)
        try {
            store.save(record)
            val intent = Intent(context, AgentBrowserUserControlActivity::class.java)
                .putExtra(AgentBrowserUserControl.EXTRA_KEY, key)
                .putExtra(AgentBrowserUserControl.EXTRA_GENERATION, record.generation)
            ActivityScenario.launch<AgentBrowserUserControlActivity>(intent).use {
                assertTrue("Returned control was treated as a live browser request", closed.await(10, TimeUnit.SECONDS))
                assertEquals(record, store.current(key, record.generation))
            }
        } finally {
            application.unregisterActivityLifecycleCallbacks(observer)
            android.util.AtomicFile(File(context.filesDir, "browser-user-requests/$key.enc")).delete()
        }
    }

    @Test fun staleRequestShowsAResponsiveProtectedSurfaceWithBoundedControls() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val ready = CountDownLatch(1)
        var failure: Throwable? = null
        val intent = Intent(context, AgentBrowserUserControlActivity::class.java)
            .putExtra(AgentBrowserUserControl.EXTRA_KEY, "0".repeat(64))
            .putExtra(AgentBrowserUserControl.EXTRA_GENERATION, "public-missing-request")
        ActivityScenario.launch<AgentBrowserUserControlActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                activity.findViewById<View>(android.R.id.content).doOnLayout { root ->
                    try {
                        assertTrue(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
                        assertTrue(root.width > 0 && root.height > 0)
                        val buttons = descendants(root).filterIsInstance<ImageButton>()
                        assertEquals(4, buttons.size)
                        buttons.forEach { button ->
                            assertFalse(button.contentDescription.isNullOrBlank())
                            val bounds = android.graphics.Rect()
                            button.getDrawingRect(bounds)
                            (root as ViewGroup).offsetDescendantRectToMyCoords(button, bounds)
                            assertTrue(bounds.left >= 0 && bounds.right <= root.width)
                            assertTrue(bounds.top >= 0 && bounds.bottom <= root.height)
                        }
                        val image = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
                        try {
                            root.draw(Canvas(image))
                            File(context.getExternalFilesDir(null), "public-browser-handoff-layout.png")
                                .outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
                        } finally { image.recycle() }
                    } catch (error: Throwable) { failure = error }
                    finally { ready.countDown() }
                }
            }
            assertTrue("The browser surface did not lay out", ready.await(20, TimeUnit.SECONDS))
            failure?.let { throw it }
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) {
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
    } else emptyList()
}
