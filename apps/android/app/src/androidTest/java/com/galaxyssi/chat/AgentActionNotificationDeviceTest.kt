package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationManager
import android.app.NotificationChannel
import android.os.SystemClock
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.absoluteValue

@RunWith(AndroidJUnit4::class)
class AgentActionNotificationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val manager get() = context.getSystemService(NotificationManager::class.java)

    private fun action(name: String) = AgentAction(
        id = "notification-device-test-$name",
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = "Notification test only",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PROPOSED,
        description = "No tool is executed"
    )

    private fun id(action: AgentAction) = 52_000 + (action.id.hashCode() % 10_000).absoluteValue

    private fun awaitNotifications(predicate: (Array<StatusBarNotification>) -> Boolean): Array<StatusBarNotification> {
        val deadline = SystemClock.elapsedRealtime() + 4_000L
        while (true) {
            val notifications = manager.activeNotifications
            if (predicate(notifications) || SystemClock.elapsedRealtime() >= deadline) return notifications
            Thread.sleep(20)
        }
    }

    @Test fun runningOperationDoesNotPublishNotification() {
        assumeTrue(manager.areNotificationsEnabled())
        val action = action("silent")
        try {
            val delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    assertTrue(manager.activeNotifications.none { it.id == id(action) })
                    return AgentActionResult(action.id, true, "Completed")
                }
            }
            NotifyingAgentActionExecutor(context, delegate).execute(action, ScreenContext("test", pageTitle = "test"))
            assertTrue(manager.activeNotifications.none { it.id == id(action) })
        } finally { manager.cancel(id(action)) }
    }

    @Test fun successfulOperationRemovesItsNotification() {
        assumeTrue(manager.areNotificationsEnabled())
        val action = action("success")
        val center = AgentActionNotificationCenter(context)
        try {
            manager.createNotificationChannel(NotificationChannel("notification_device_test", "Test", NotificationManager.IMPORTANCE_LOW))
            manager.notify(id(action), Notification.Builder(context, "notification_device_test")
                .setSmallIcon(R.drawable.ic_tab_chat_filled).setContentTitle("Test only").build())
            assertTrue(awaitNotifications { list -> list.any { it.id == id(action) } }.any { it.id == id(action) })
            center.showResult(action, AgentActionResult(action.id, true, "Completed"))
            assertTrue(awaitNotifications { list -> list.none { it.id == id(action) } }.none { it.id == id(action) })
        } finally { manager.cancel(id(action)) }
    }

    @Test fun failedOperationKeepsItsFailureNotification() {
        assumeTrue(manager.areNotificationsEnabled())
        val action = action("failure")
        try {
            AgentActionNotificationCenter(context).showResult(action, AgentActionResult(action.id, false, "Test failure"))
            val notification = awaitNotifications { list -> list.any { it.id == id(action) } }
                .single { it.id == id(action) }.notification
            assertEquals(Notification.CATEGORY_ERROR, notification.category)
        } finally { manager.cancel(id(action)) }
    }
}
