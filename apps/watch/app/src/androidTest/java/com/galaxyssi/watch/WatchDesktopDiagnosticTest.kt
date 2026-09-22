package com.galaxyssi.watch

import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.AgentEncryptedDatabase
import com.galaxyssi.chat.GalaxySSILinkProtocol
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Explicit read-only diagnostic: no message contents, ciphertext, keys, or new sends. */
class WatchDesktopDiagnosticTest {
    @Test fun inspectPendingDesktopDelivery() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("desktop_diagnostic") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val links = GalaxySSILinkProtocol.allServerLinks(context)
        println("DESKTOP links=${links.size} paired=${links.count { it.paired }}")
        AgentEncryptedDatabase(context, "watch_peer_outbox").entries().forEach { (id, raw) ->
            val entry = JSONObject(raw)
            val link = links.firstOrNull { it.desktopId == entry.optString("peer") } ?: return@forEach
            val envelope = entry.getJSONObject("envelope")
            val payload = envelope.getJSONObject("payload")
            val wire = JSONObject(entry.getString("wire"))
            println("DESKTOP_PENDING id=$id paired=${link.paired} " +
                "routeMatch=${payload.optString("client_route_id") == link.routes.clientRouteId} " +
                "kind=${payload.optString("type")} signalType=${wire.optString("signal_type")} " +
                "ageSeconds=${(System.currentTimeMillis() - envelope.optLong("sent_at")) / 1000}")
        }
    }
}
