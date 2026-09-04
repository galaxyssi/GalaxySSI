package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopPairingLifecycleTest {
    @Test
    fun matchesDeviceAndAgentContactsOwnedByOneDesktop() {
        val desktopId = "desktop-t14"

        assertTrue(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", desktopId).put("desktop_id", desktopId),
            desktopId
        ))
        assertTrue(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "$desktopId:codex").put("desktop_id", desktopId),
            desktopId
        ))
        assertTrue(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "codex-t14").put("parent_contact", desktopId),
            desktopId
        ))
    }

    @Test
    fun preservesContactsOwnedByAnotherDesktopOrCloudProvider() {
        val desktopId = "desktop-t14"

        assertFalse(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "desktop-office:codex").put("desktop_id", "desktop-office"),
            desktopId
        ))
        assertFalse(DesktopPairingLifecycle.belongsToDesktop(
            JSONObject().put("id", "deepseek").put("delivery_mode", "cloud_api"),
            desktopId
        ))
    }
}
