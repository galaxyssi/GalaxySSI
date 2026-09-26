package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationManager
import android.os.SystemClock
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    @Test fun runningOperationIsSilent() {
        assumeTrue(manager.areNotificationsEnabled())
        val action = action("silent")
        try {
            AgentActionNotificationCenter(context).showRunning(action)
            val notification = awaitNotifications { list -> list.any { it.id == id(action) } }
                .single { it.id == id(action) }.notification
            assertNull(notification.sound)
            assertNull(notification.vibrate)
            assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        } finally { manager.cancel(id(action)) }
    }

    @Test fun successfulOperationRemovesItsNotification() {
        assumeTrue(manager.areNotificationsEnabled())
        val action = action("success")
        val center = AgentActionNotificationCenter(context)
        try {
            center.showRunning(action)
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
