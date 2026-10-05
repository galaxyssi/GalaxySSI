package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Base64
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in reads of an already completed dedicated fixture; never creates or reruns model tasks. */
@RunWith(AndroidJUnit4::class)
class CollaborationEvidenceTransportDeviceTest {
    @Test fun completedFixtureEvidenceCrossesRealAuthenticatedTransport(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("remoteEvidenceLiveRead") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixture = JSONObject(String(Base64.getDecoder().decode(args.getString("remoteEvidenceFixture")), Charsets.UTF_8))
        val fields = fixture.getJSONObject("fields")
        val desktop = fixture.getString("desktop")
        val requireInline = args.getString("remoteEvidenceInline") == "true"
        require(CollaborationRemoteEvidenceProtocol.validScope(fields))
        val report = JSONObject().put("task_id", fields.getString("task_id")).put("model_calls", 0)
        val samples = JSONArray()
        val file = File(context.getExternalFilesDir(null), "collaboration-evidence-transport.json")
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        try {
            withTimeout(90_000) {
                while (!GalaxySSIMqttClient.isConnected() || !GalaxySSIMqttClient.isSecureReady()) delay(500)
            }
            val inbox = GalaxySSILinkDeliveryStore.inbox(context)
            val routes = requireNotNull(GalaxySSILinkProtocol.serverLink(context, desktop)).routes
            val usage = inbox.usage(GalaxySSILinkDeliveryStore.peerScope(routes))
            report.put("retained_records_before", usage.retainedRecords).put("pending_records_before", usage.pendingRecords)
                .put("pending_bytes_before", usage.pendingBytes)
            repeat(3) {
                val started = SystemClock.elapsedRealtime()
                val response = AndroidCollaborationRemoteEvidence.query(context, desktop, fields,
                    JSONObject().put("mode", "index").put("after_sequence", 0).apply {
                        if (requireInline) put("inline_page_bytes", CollaborationRemoteEvidenceProtocol.INLINE_PAGE_BYTES)
                    })
                samples.put(JSONObject().put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                    .put("received", response != null).put("status", response?.optString("status"))
                    .put("inline_pages", response?.optJSONArray("inline_pages")?.length()))
                report.put("queries", samples)
                file.writeText(report.toString())
                assertNotNull("Read-only index query must complete without another model call", response)
                assertEquals("ready", response!!.getString("status"))
                assertTrue(CollaborationRemoteEvidenceProtocol.sameScope(fields, response))
                assertEquals(fixture.getInt("expected_entries"), response.getJSONArray("entries").length())
                assertFalse(response.getBoolean("provider_history_complete"))
                if (requireInline) {
                    assertTrue(response.getBoolean("archive_final"))
                    val entries = response.getJSONArray("entries")
                    val pages = response.getJSONArray("inline_pages")
                    assertEquals(fixture.getInt("expected_entries"), pages.length())
                    repeat(pages.length()) { index ->
                        val entry = entries.getJSONObject(index)
                        val page = pages.getJSONObject(index)
                        assertEquals(entry.getString("evidence_id"), page.getString("evidence_id"))
                        val decoded = requireNotNull(AgentResultRecoveryPageCodec.decode(page, 0))
                        decoded.use { CollaborationRemoteEvidenceProtocol.original(it.bytes, fields, entry) }
                    }
                }
            }
            report.put("passed", true)
        } finally {
            file.writeText(report.toString())
            scenario.close()
        }
    }
}
