package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ControlCenterHomeGroupingTest {
    @Test
    fun homeUsesSixStableUserFacingGroups() {
        assertEquals(6, ControlCenterHomeGrouping.orderedGroups.size)
        assertEquals(
            listOf(
                ControlCenterHomeGroup.CONNECTED_DEVICES,
                ControlCenterHomeGroup.MODELS,
                ControlCenterHomeGroup.VOICE_INTERACTION,
                ControlCenterHomeGroup.MEMORY_KNOWLEDGE,
                ControlCenterHomeGroup.SKILLS_TASKS,
                ControlCenterHomeGroup.SECURITY_DATA
            ),
            ControlCenterHomeGrouping.orderedGroups
        )
    }

    @Test
    fun removedProfilePageCannotBeRestored() {
        assertEquals(null, ControlCenterRoute.fromWireValue("profile"))
    }

    @Test
    fun retiredDirectoryRoutesCannotBeRestored() {
        assertEquals(null, ControlCenterRoute.fromWireValue("app_tools"))
        assertEquals(null, ControlCenterRoute.fromWireValue("app_services"))
    }

    @Test
    fun removedSettingsPagesCannotBeRestored() {
        listOf(
            "nodes",
            "tasks",
            "system_status",
            "security",
            "privacy",
            "permissions_audit"
        ).forEach { wireValue ->
            assertEquals(null, ControlCenterRoute.fromWireValue(wireValue))
        }
    }

    @Test
    fun primaryHomeRoutesAppearExactlyOnce() {
        val routes = ControlCenterHomeGrouping.orderedGroups.flatMap(
            ControlCenterHomeGrouping::routes
        )
        val expectedRoutes = setOf(
            ControlCenterRoute.PHONE_CAPABILITIES,
            ControlCenterRoute.SMART_SPACES,
            ControlCenterRoute.RESOURCE_ROUTING,
            ControlCenterRoute.ON_DEVICE_RUNTIME,
            ControlCenterRoute.VOICE,
            ControlCenterRoute.MEMORY,
            ControlCenterRoute.KNOWLEDGE,
            ControlCenterRoute.LEARNING,
            ControlCenterRoute.AGENT_CORE,
            ControlCenterRoute.MCP,
            ControlCenterRoute.SELF_EVOLUTION,
            ControlCenterRoute.DATA_BACKUP,
            ControlCenterRoute.GENERAL
        )

        assertEquals(routes.size, routes.distinct().size)
        assertEquals(expectedRoutes, routes.toSet())
        routes.forEach { route ->
            assertTrue(ControlCenterHomeGrouping.groupFor(route) != null)
        }
    }
}
