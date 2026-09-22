package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchPairingSessionTest {
    @Test fun newRouteReplacesSessionEvenWhenOldDesktopSessionExists() {
        var calls = 0
        assertTrue(WatchPairingSession.confirm(false, true) { replace -> calls++; assertTrue(replace); true })
        assertEquals(1, calls)
    }
    @Test fun repeatedConfirmationDoesNotResetLiveSession() {
        assertTrue(WatchPairingSession.confirm(true, true) { error("Must preserve the ratchet") })
    }
    @Test fun missingSessionBootstrapsAndFailedBootstrapDoesNotConfirmPairing() {
        assertFalse(WatchPairingSession.confirm(false, false) { replace -> assertTrue(replace); false })
        assertTrue(WatchPairingSession.confirm(true, false) { replace -> assertFalse(replace); true })
    }
    @Test fun rescanOfVerifiedDesktopKeepsItsExistingRelationship() {
        assertTrue(WatchPairingSession.canReuse(true, true, "aabb", "AABB", "aabb"))
        assertFalse(WatchPairingSession.canReuse(false, true, "aabb", "aabb", "aabb"))
        assertFalse(WatchPairingSession.canReuse(true, false, "aabb", "aabb", "aabb"))
        assertFalse(WatchPairingSession.canReuse(true, true, "aabb", "different", "aabb"))
        assertFalse(WatchPairingSession.canReuse(true, true, "aabb", "aabb", "different"))
        assertFalse(WatchPairingSession.canReuse(true, true, "", "", ""))
    }
}
