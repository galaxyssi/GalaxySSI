package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DesktopRemoteDisplayDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun titleDeviceIconAndToolbarMatchTheCenteredLayout() {
        val intent = Intent(context, DesktopRemoteControlActivity::class.java)
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID, "test-unpaired-layout")
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_NAME, "Test computer")
        ActivityScenario.launch<DesktopRemoteControlActivity>(intent).use { scenario ->
            val deadline = System.currentTimeMillis() + 5000
            var laidOut = false
            while (!laidOut && System.currentTimeMillis() < deadline) {
                scenario.onActivity { laidOut = it.window.decorView.width > 0 }
                if (!laidOut) Thread.sleep(50)
            }
            assertTrue(laidOut)
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                val title = descendant(root) { it is TextView && it.text == activity.getString(R.string.desktop_control_title) } as TextView
                assertEquals(Gravity.CENTER, title.gravity)
                val location = IntArray(2).also(title::getLocationOnScreen)
                assertEquals(root.width / 2f, location[0] + title.width / 2f, 1f)

                val name = descendant(root) { it is TextView && it.isShown && it.text == "Test computer" }!!
                val device = (name.parent.parent as ViewGroup).getChildAt(0) as ImageView
                assertNotNull(device.imageTintList)
                val pixels = Bitmap.createBitmap(device.width, device.height, Bitmap.Config.ARGB_8888)
                device.draw(Canvas(pixels))
                var darkPixels = 0
                for (x in 0 until pixels.width) for (y in 0 until pixels.height) {
                    val color = pixels.getPixel(x, y)
                    if (Color.alpha(color) > 200 && Color.red(color) < 100 && Color.green(color) < 100 && Color.blue(color) < 100) darkPixels++
                }
                pixels.recycle()
                assertTrue("Computer icon disappears on a white background", darkPixels > 20)

                for (description in listOf(R.string.desktop_control_surface_refresh_action, R.string.desktop_remote_fullscreen)) {
                    val command = descendant(root) { it.isShown && it.contentDescription == activity.getString(description) } as ViewGroup
                    val icon = command.getChildAt(0) as ImageView
                    val caption = command.getChildAt(1) as TextView
                    assertEquals(Gravity.CENTER, caption.gravity)
                    assertEquals(command.width / 2f, icon.left + icon.width / 2f, 1f)
                    assertEquals(command.width / 2f, caption.left + caption.width / 2f, 1f)
                    assertTrue(caption.top >= icon.bottom)
                    assertTrue(caption.bottom <= command.height)
                }
            }
        }
    }

    @Test fun fullscreenBackAndRecreationPreserveTheControlSurface() {
        val intent = Intent(context, DesktopRemoteControlActivity::class.java)
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID, "test-unpaired-display")
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_NAME, "Test computer")
        ActivityScenario.launch<DesktopRemoteControlActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                assertNotNull(descendant(root) { it is DesktopRemoteScreenView })
                assertNull(descendant(root) { it.isShown && it.contentDescription == activity.getString(R.string.desktop_remote_keyboard) })
                descendant(root) { it.isShown && it.contentDescription == activity.getString(R.string.desktop_remote_fullscreen) }!!.performClick()
            }
            awaitLandscape(scenario)
            scenario.recreate()
            awaitLandscape(scenario)
            scenario.onActivity { activity ->
                assertNotNull(descendant(activity.window.decorView) { it is DesktopRemoteScreenView })
                @Suppress("DEPRECATION")
                activity.onBackPressed()
                assertFalse(activity.isFinishing)
            }
        }
    }

    @Test fun optInLiveDisplayForVisualAndKeyboardValidation() {
        val args = InstrumentationRegistry.getArguments()
        val id = args.getString("desktop_control_live_id").orEmpty()
        assumeTrue("Live UI validation is opt-in", id.isNotBlank())
        assertNotNull(GalaxySSILinkProtocol.serverLink(context, id))
        val intent = Intent(context, DesktopRemoteControlActivity::class.java)
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID, id)
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_NAME, "DESKTOP-T14")
        ActivityScenario.launch<DesktopRemoteControlActivity>(intent).use {
            val deadline = System.currentTimeMillis() + 45_000
            while (DesktopRemoteControl.snapshot(context, id).screenshot == null && System.currentTimeMillis() < deadline) Thread.sleep(100)
            val state = DesktopRemoteControl.snapshot(context, id)
            assertNotNull("Remote display: connected=${GalaxySSIMqttClient.isConnected()} " +
                "authorized=${state.authorized} stream=${state.streamActive} " +
                "status=${state.lastActionStatus} summary=${state.lastActionSummary} " +
                "sessionRemainingMs=${(state.currentAuthorization?.desktopSessionExpiresAt ?: 0L) - System.currentTimeMillis()}", state.screenshot)
            InstrumentationRegistry.getInstrumentation().sendStatus(2, android.os.Bundle().apply {
                putString("stream", "Verified remote frame: bytes=${state.screenshot!!.jpegBytes.size}\n")
            })
            Thread.sleep((args.getString("desktop_control_ui_seconds")?.toLongOrNull() ?: 10L).coerceIn(1, 600) * 1000)
            if (args.getString("desktop_control_require_new_session") == "true") {
                val recovered = DesktopRemoteControl.snapshot(context, id)
                assertNotEquals("Desktop session was not renewed after restart", state.currentAuthorization?.desktopSessionId,
                    recovered.currentAuthorization?.desktopSessionId)
                assertTrue("No new frame after Desktop restart: status=${recovered.lastActionStatus} " +
                    "code=${recovered.lastActionErrorCode} stream=${recovered.streamActive}",
                    (recovered.screenshot?.capturedAt ?: 0L) > state.screenshot!!.capturedAt)
                assertTrue("Screenshot stream did not recover", recovered.streamActive)
            }
        }
    }

    private fun awaitLandscape(scenario: ActivityScenario<DesktopRemoteControlActivity>) {
        val deadline = System.currentTimeMillis() + 5000
        var landscape = false
        while (!landscape && System.currentTimeMillis() < deadline) {
            scenario.onActivity { landscape = it.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE }
            if (!landscape) Thread.sleep(100)
        }
        assertTrue("Fullscreen did not rotate", landscape)
    }

    private fun descendant(view: View, predicate: (View) -> Boolean): View? {
        if (predicate(view)) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            descendant(view.getChildAt(index), predicate)?.let { return it }
        }
        return null
    }
}
