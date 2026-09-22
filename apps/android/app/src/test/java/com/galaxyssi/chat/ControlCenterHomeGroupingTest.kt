package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ControlCenterHomeGroupingTest {
    @Test fun homeHasTwoGroupsAndNineUniqueDestinations() {
        assertEquals(listOf(ControlCenterHomeGroup.COMMON, ControlCenterHomeGroup.SETTINGS),
            ControlCenterHomeGrouping.orderedGroups)
        val routes = ControlCenterHomeGrouping.orderedGroups.flatMap(ControlCenterHomeGrouping::routes)
        assertEquals(9, routes.size)
        assertEquals(routes.size, routes.distinct().size)
        assertEquals(listOf(ControlCenterRoute.MODEL_HUB, ControlCenterRoute.DEVICE_HUB,
            ControlCenterRoute.VOICE, ControlCenterRoute.MEMORY_HUB, ControlCenterRoute.PROACTIVE_HUB,
            ControlCenterRoute.SKILLS_HUB, ControlCenterRoute.SAFETY_HUB, ControlCenterRoute.GENERAL,
            ControlCenterRoute.ADVANCED), routes)
        routes.forEach { assertNotNull(ControlCenterHomeGrouping.groupFor(it)); assertTrue(it.isAvailable) }
    }
    @Test fun downloadAndRuntimeDestinationsRemainAvailableOffHome() {
        listOf(ControlCenterRoute.ON_DEVICE_RUNTIME, ControlCenterRoute.SOFTWARE_CENTER,
            ControlCenterRoute.VOICE, ControlCenterRoute.RESOURCE_ROUTING).forEach {
            assertEquals(it, ControlCenterRoute.fromWireValue(it.wireValue))
        }
        assertNull(ControlCenterHomeGrouping.groupFor(ControlCenterRoute.ON_DEVICE_RUNTIME))
    }
    @Test fun retiredRoutesAreNotResurrected() {
        listOf("profile", "app_tools", "app_services", "nodes", "tasks", "system_status",
            "security", "privacy", "permissions_audit").forEach {
            assertNull(ControlCenterRoute.fromWireValue(it))
        }
    }
    @Test fun advancedSectionsAreOptInToCollapse() {
        assertFalse(ControlCenterSectionSpec("Models", emptyList()).collapsed)
        assertTrue(ControlCenterSectionSpec("Advanced", emptyList(), collapsed = true).collapsed)
    }
}
