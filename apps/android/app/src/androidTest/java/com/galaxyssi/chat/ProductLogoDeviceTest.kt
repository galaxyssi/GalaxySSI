package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.roundToInt

@RunWith(AndroidJUnit4::class)
class ProductLogoDeviceTest {
    @Test fun homeUsesSettingsArtworkWithoutChangingSizeOrAction() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val logo = activity.agentBrandLogo
                activity.applyAgentBrandLogoTextScale()
                val sizeDp = (AGENT_BRAND_LOGO_BASE_DP * activity.resources.configuration.fontScale)
                    .roundToInt().coerceIn(AGENT_BRAND_LOGO_MIN_DP, AGENT_BRAND_LOGO_MAX_DP)
                assertEquals(activity.dp(sizeDp), logo.layoutParams.width)
                assertEquals(activity.dp(sizeDp), logo.layoutParams.height)
                assertTrue(logo.hasOnClickListeners())
                assertEquals(activity.getString(R.string.conversation_window_open), logo.contentDescription)
                assertFalse(logo.drawable is AdaptiveIconDrawable)
                val hero = activity.buildControlCenterHomePage().hero!!
                assertEquals(R.drawable.galaxyssi_mark_large, hero.iconRes)
                assertTrue(render(logo.drawable).sameAs(render(activity.getDrawable(hero.iconRes)!!)))
            }
        }
    }

    @Test fun notificationApplicationIconUsesSettingsArtworkWithoutChangingLauncherIcon() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        assertEquals(R.drawable.galaxyssi_mark_large, context.applicationInfo.icon)
        val launcher = context.packageManager.getActivityInfo(
            android.content.ComponentName(context, StartupActivity::class.java), 0)
        assertEquals(R.mipmap.ic_launcher, launcher.icon)
        val notification = Notification.Builder(context, "logo_test")
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle("Logo test")
            .setContentText("Preview")
            .build()
        assertNull(notification.getLargeIcon())
        assertEquals(R.drawable.ic_tab_chat_filled, notification.smallIcon.resId)
        assertEquals("Logo test", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Preview", notification.extras.getString(Notification.EXTRA_TEXT))
    }

    @Test fun notificationPreviewCanRenderProductLogo() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = "galaxyssi_logo_verification"
        val id = 0x534C4F
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        manager.createNotificationChannel(NotificationChannel(channel, "Logo verification",
            NotificationManager.IMPORTANCE_HIGH))
        try {
            manager.notify(id, Notification.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_tab_chat_filled)
                .setContentTitle("GalaxySSI")
                .setContentText("Product logo verification")
                .build())
            val deadline = android.os.SystemClock.elapsedRealtime() + 5000
            var posted = manager.activeNotifications.firstOrNull { it.id == id }
            while (posted == null && android.os.SystemClock.elapsedRealtime() < deadline) {
                android.os.SystemClock.sleep(50)
                posted = manager.activeNotifications.firstOrNull { it.id == id }
            }
            assertNotNull("System must publish the preview notification", posted)
            assertNull(posted!!.notification.getLargeIcon())
            automation.executeShellCommand("cmd statusbar expand-notifications").close()
            android.os.SystemClock.sleep(1000)
            val screenshot = automation.takeScreenshot()
            assertNotNull(screenshot)
            java.io.File(context.getExternalFilesDir(null), "product-notification-logo.png")
                .outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG, 100, it) }
            screenshot.recycle()
        } finally {
            manager.cancel(id)
            manager.deleteNotificationChannel(channel)
            automation.executeShellCommand("cmd statusbar collapse").close()
        }
    }

    private fun render(drawable: Drawable): Bitmap =
        Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888).also {
            val previousBounds = android.graphics.Rect(drawable.bounds)
            drawable.setBounds(0, 0, 64, 64)
            drawable.draw(Canvas(it))
            drawable.bounds = previousBounds
        }
}
