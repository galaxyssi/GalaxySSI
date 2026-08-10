package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ControlCenterHomeGroupingTest {
    @Test
    fun homeUsesSevenStableUserFacingGroups() {
        assertEquals(7, ControlCenterHomeGrouping.orderedGroups.size)
        assertEquals(
            listOf(
                ControlCenterHomeGroup.IDENTITY,
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
    fun primaryHomeRoutesAppearExactlyOnce() {
        val routes = ControlCenterHomeGrouping.orderedGroups.flatMap(
            ControlCenterHomeGrouping::routes
        )
        val expectedRoutes = setOf(
            ControlCenterRoute.PROFILE,
            ControlCenterRoute.NODES,
            ControlCenterRoute.PHONE_CAPABILITIES,
            ControlCenterRoute.SMART_SPACES,
            ControlCenterRoute.RESOURCE_ROUTING,
            ControlCenterRoute.ON_DEVICE_RUNTIME,
            ControlCenterRoute.VOICE,
            ControlCenterRoute.APP_TOOLS,
            ControlCenterRoute.APP_SERVICES,
            ControlCenterRoute.MEMORY,
            ControlCenterRoute.KNOWLEDGE,
            ControlCenterRoute.LEARNING,
            ControlCenterRoute.AGENT_CORE,
            ControlCenterRoute.TASKS,
            ControlCenterRoute.MCP,
            ControlCenterRoute.SELF_EVOLUTION,
            ControlCenterRoute.SYSTEM_STATUS,
            ControlCenterRoute.SECURITY,
            ControlCenterRoute.PRIVACY,
            ControlCenterRoute.PERMISSIONS_AUDIT,
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
