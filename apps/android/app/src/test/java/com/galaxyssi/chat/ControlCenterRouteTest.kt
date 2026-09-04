package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ControlCenterRouteTest {
    @Test
    fun availableRoutesRoundTripAndUnavailableRoutesStayRejected() {
        ControlCenterRoute.entries.filter(ControlCenterRoute::isAvailable).forEach { route ->
            assertEquals(route, ControlCenterRoute.fromWireValue(route.wireValue))
            assertEquals(route, ControlCenterRoute.fromWireValue("  ${route.wireValue.uppercase()}  "))
        }
        ControlCenterRoute.entries.filterNot(ControlCenterRoute::isAvailable).forEach { route ->
            assertNull(ControlCenterRoute.fromWireValue(route.wireValue))
        }
    }

    @Test
    fun unknownRouteIsRejected() {
        assertNull(ControlCenterRoute.fromWireValue("not-a-control-center-route"))
    }
}
