package com.galaxyssi.watch

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.widget.Button
import android.view.View
import android.view.ViewGroup
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.AgentEncryptedDatabase
import org.junit.Assert.*
import org.junit.Test

class WatchNotificationTest {
    private fun awaitCondition(condition: () -> Boolean) {
        val deadline = android.os.SystemClock.elapsedRealtime() + 5000
        while (!condition() && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
        assertTrue(condition())
    }
    private fun views(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()

    @Test fun visibleConversationUpdatesWithoutResultNotification() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_WAKEUP").use {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(it).use { stream -> stream.readBytes() }
        }
        val context = instrumentation.targetContext.applicationContext
        val repo = (context as WatchApplication).repository
        val task = WatchTask.create("notification-test", "test-route", "test-agent", "Notification display test")
            .copy(state = TaskState.COMPLETED, reply = "Visible reply")
        val other = task.copy(id = java.util.UUID.randomUUID().toString(), conversationId = "other-conversation")
        val manager = context.getSystemService(NotificationManager::class.java)
        repo.store.save(task)
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .putExtra("task_id", task.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        try {
            instrumentation.runOnMainSync { activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
            awaitCondition { repo.conversationVisibility.isViewing(task) }
            instrumentation.runOnMainSync {
                assertTrue(repo.conversationVisibility.isViewing(task))
                WatchNotifications.completed(context, task)
                assertFalse(manager.activeNotifications.any { it.id == task.id.hashCode() })
                assertFalse(repo.conversationVisibility.isViewing(other))
                if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    WatchNotifications.completed(context, other)
                }
            }
            if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                awaitCondition { manager.activeNotifications.any { it.id == other.id.hashCode() } }
            }
            instrumentation.runOnMainSync {
                views(activity.window.decorView).filterIsInstance<Button>()
                    .first { it.text.toString() == activity.getString(R.string.back) }.performClick()
                assertFalse(repo.conversationVisibility.isViewing(task))
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
            manager.cancel(task.id.hashCode()); manager.cancel(other.id.hashCode())
            AgentEncryptedDatabase(context, "watch_tasks").remove(task.id)
        }
    }
}
