package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID

class DesktopHistoryPairingDeviceTest {
    @Test fun revocationRepairAndExplicitLocalDeletionAreSeparate() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assumeTrue("Use an isolated debug application ID", context.packageName.endsWith(".pairingqa"))
        AppStore.ensureInitialized(context)
        val fingerprint = UUID.randomUUID().toString().replace("-", "").repeat(2)
        val qr = requireNotNull(GalaxySSILinkProtocol.normalizePairingQr(JSONObject()
            .put("t", "o2").put("n", "Fixture desktop").put("k", "fixture-key").put("h", fingerprint)
            .put("c", System.currentTimeMillis() / 1000L).put("x", GalaxySSILinkProtocol.newLinkSecret())
            .put("e", GalaxySSILinkProtocol.newLinkSecret()).put("a", 0)))
        val id = qr.getString("desktop_id")
        val device = JSONObject().put("desktop_id", id).put("desktop_fingerprint", fingerprint)
        fun pair(): String {
            val fresh = GalaxySSILinkProtocol.ensureServerLink(context, qr)
            GalaxySSILinkProtocol.markPaired(context, id)
            assertTrue(AppStore.updateDesktopDeviceContact(context, device))
            return fresh.routes.clientRouteId
        }
        val first = pair()
        val other = "fixture-" + UUID.randomUUID()
        ChatHistoryStore.appendOutgoing(context, id, "keep after unpair")
        ChatHistoryStore.appendOutgoing(context, other, "unrelated")
        try {
            DesktopPairingLifecycle.remove(context, id)
            assertNull(GalaxySSILinkProtocol.serverLink(context, id))
            assertTrue(DesktopPairingLifecycle.isHistoryOnly(AppStore.contactById(context, id)))
            assertEquals(1, ChatHistoryStore.readContact(context, id).length())
            assertNotEquals(first, pair())
            assertFalse(DesktopPairingLifecycle.isHistoryOnly(AppStore.contactById(context, id)))
            assertEquals(1, ChatHistoryStore.readContact(context, id).length())
            assertFalse(AppStore.clearPairedDesktopLocalHistory(context, id, "not-the-paired-device"))
            assertTrue(AppStore.clearPairedDesktopLocalHistory(context, id, fingerprint))
            assertEquals(0, ChatHistoryStore.readContact(context, id).length())
            assertEquals(1, ChatHistoryStore.readContact(context, other).length())
            assertTrue(GalaxySSILinkProtocol.serverLink(context, id)?.paired == true)
        } finally {
            DesktopPairingLifecycle.remove(context, id)
            ChatHistoryStore.deleteContact(context, other)
        }
    }
}
