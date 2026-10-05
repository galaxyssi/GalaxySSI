package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Read-only protocol fixtures only. No broker, model, contact messages or physical tools. */
@RunWith(AndroidJUnit4::class)
class CollaborationRemoteEvidenceDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private fun access(group: String) = CollaborationWorkspaceAccess(group, "root", "turn", 1, "node", "author")
    private fun fields(group: String) = JSONObject().apply { AgentResultRecoveryClient.FIELDS.forEach { put(it, it) } }
        .put("agent_id", "codex").put("source_message_id", "456").put("conversation_id", group)
        .put("turn_id", "turn").put("execution_generation", 2)
    private fun create(group: String) {
        CollaborationGroupStore(context).update(group) { it.copy(members = listOf(
            CollaborationMember("author", "Turing", "fixture", "Fixture")), coordinatorId = "author") }
        CollaborationEvidenceLedger(context).bind(456, access(group))
    }

    @Test fun actualDesktopArchiveContract(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        org.junit.Assume.assumeTrue(args.getString("remoteEvidenceDesktopFixture") == "1")
        val file = java.io.File(context.filesDir, "remote-evidence-desktop-fixture.json")
        val fixture = JSONObject(file.readText())
        val fields = fixture.getJSONObject("fields")
        val group = fields.getString("conversation_id")
        require(group.matches(Regex("remote-evidence-cross-language-[a-f0-9]{32}")))
        require(CollaborationGroupStore(context).load(group) == null)
        create(group)
        try {
            val ledger = CollaborationEvidenceLedger(context)
            ledger.bind(fields.getString("source_message_id").toLong(), access(group))
            val store = CollaborationRemoteEvidenceStore(context)
            val key = store.create("fixture-desktop", fields, access(group))
            val client = CollaborationRemoteEvidenceClient()
            assertTrue(CollaborationRemoteEvidenceImporter(store, ledger).run(key, { true }) { desktop, identity, selection ->
                client.query(desktop, identity, selection) { request ->
                    val source = if (selection.getString("mode") == "index") {
                        fixture.getJSONObject(if (selection.getLong("after_sequence") == 0L) "index" else "empty_index")
                    } else fixture.getJSONArray("pages").let { pages ->
                        (0 until pages.length()).map { pages.getJSONObject(it) }.single {
                            it.getString("evidence_id") == selection.getString("evidence_id") &&
                                it.getInt("page_index") == selection.getInt("page_index")
                        }
                    }
                    client.receive(JSONObject(source.toString()).put("request_id", request.getString("request_id")), desktop)
                }
            })
            val references = ledger.browse(access(group)).first
            assertEquals(2, references.size)
            assertEquals(setOf("failed", "returned"), references.map { it.getString("status") }.toSet())
            references.forEach { reference ->
                val output = JSONObject(ledger.read(access(group), reference.getString("evidence_id"))!!.getString("output_json"))
                assertEquals(output.getString("remote_sha256"), AgentResultRecoveryClient.sha256(output.getString("original_json").toByteArray(Charsets.UTF_8)))
                assertEquals(48000, JSONObject(output.getString("original_json")).getJSONObject("observation").getJSONObject("item")
                    .getString("aggregatedOutput").toByteArray().size)
            }
        } finally { CollaborationGroupStore(context).remove(group); file.delete() }
    }
    private class Fixture(private val fields: JSONObject, repeats: Int = 3000) {
        val body = JSONObject(fields.toString()).put("contract", CollaborationRemoteEvidenceProtocol.CONTRACT)
            .put("trust", CollaborationRemoteEvidenceProtocol.TRUST).put("coverage", "provider_payload_as_received")
            .put("observation", JSONObject().put("provider", "codex").put("thread_id", "provider-thread")
                .put("turn_id", "provider-turn").put("item", JSONObject().put("id", "fixture-item")
                    .put("type", "commandExecution").put("exitCode", 0).put("aggregatedOutput", "Fixture original \u8bc1\u636e. ".repeat(repeats))))
            .toString().toByteArray()
        val descriptor = JSONObject().put("evidence_id", AgentNativeJsonCodec.sha256("fixture-item"))
            .put("sha256", AgentResultRecoveryClient.sha256(body)).put("sequence", 1)
            .put("total_bytes", body.size).put("page_count", (body.size + 16383) / 16384)
            .put("item_type", "commandExecution").put("outcome", "returned").put("recorded_at", 123456L)
            .put("trust", CollaborationRemoteEvidenceProtocol.TRUST).put("coverage", "provider_payload_as_received")
        val requested = mutableListOf<Int>()
        fun reply(selection: JSONObject): JSONObject {
            val reply = JSONObject(fields.toString()).put("type", "agent_task_evidence").put("contract", CollaborationRemoteEvidenceProtocol.CONTRACT)
                .put("mode", selection.getString("mode")).put("status", "ready").put("request_id", selection.optString("request_id"))
            if (selection.getString("mode") == "index") return reply
                .put("entries", JSONArray().apply { if (selection.getLong("after_sequence") == 0L) put(descriptor) })
                .put("next_sequence", 1).put("has_more", false).put("provider_history_complete", false)
                .put("coverage", "observed_completed_items_only")
            val page = selection.getInt("page_index")
            requested.add(page)
            descriptor.keys().forEach { reply.put(it, descriptor.get(it)) }
            val bytes = body.copyOfRange(page * 16384, minOf(body.size, (page + 1) * 16384))
            return reply.put("page_index", page).put("data_b64", Base64.getEncoder().encodeToString(bytes))
                .put("page_sha256", AgentResultRecoveryClient.sha256(bytes))
        }
    }

    @Test fun inlineSmallOriginalPersistsWithoutASecondQuery(): Unit = runBlocking {
        val group = "remote-evidence-inline-${UUID.randomUUID()}"
        create(group)
        try {
            val identity = fields(group)
            val fixture = Fixture(identity, repeats = 4)
            val store = CollaborationRemoteEvidenceStore(context)
            val ledger = CollaborationEvidenceLedger(context)
            val key = store.create("fixture-desktop", identity, access(group))
            var queries = 0
            assertTrue(CollaborationRemoteEvidenceImporter(store, ledger).run(key, { true }) { _, _, selection ->
                queries++
                assertEquals("index", selection.getString("mode"))
                assertEquals(0L, selection.getLong("after_sequence"))
                assertEquals(16_384L, selection.getLong("inline_page_bytes"))
                fixture.reply(selection).put("archive_final", true).put("inline_pages", JSONArray().put(
                    fixture.reply(JSONObject().put("mode", "page").put("page_index", 0))))
            })
            assertEquals(1, queries)
            val reopened = CollaborationEvidenceLedger(context)
            val ref = reopened.browse(access(group)).first.single()
            val original = JSONObject(reopened.read(access(group), ref.getString("evidence_id"))!!.getString("output_json"))
            assertEquals(String(fixture.body, Charsets.UTF_8), original.getString("original_json"))
            val saved = CollaborationRemoteEvidenceStore(context).read(key)!!
            assertEquals("imported", saved.getString("status"))
            assertFalse(saved.getBoolean("provider_history_complete"))
        } finally { CollaborationGroupStore(context).remove(group) }
    }

    @Test fun encryptedPagesResumeAndBecomeExactWorkspaceEvidence(): Unit = runBlocking {
        val group = "remote-evidence-fixture-${UUID.randomUUID()}"
        create(group)
        try {
            val scope = fields(group); val fixture = Fixture(scope)
            val store = CollaborationRemoteEvidenceStore(context)
            val key = store.create("fixture-desktop", scope, access(group))
            val ledger = CollaborationEvidenceLedger(context)
            val client = CollaborationRemoteEvidenceClient()
            assertFalse(CollaborationRemoteEvidenceImporter(store, ledger).run(key, { true }) { desktop, identity, selection ->
                if (selection.optInt("page_index", -1) == 1) null
                else client.query(desktop, identity, selection) { client.receive(fixture.reply(it), desktop) }
            })
            assertTrue(ledger.browse(access(group)).first.isEmpty())
            assertTrue(CollaborationRemoteEvidenceImporter(CollaborationRemoteEvidenceStore(context), CollaborationEvidenceLedger(context))
                .run(key, { true }) { desktop, identity, selection ->
                    client.query(desktop, identity, selection) { client.receive(fixture.reply(it), desktop) }
                })
            assertEquals(1, fixture.requested.count { it == 0 })
            val ref = ledger.browse(access(group)).first.single()
            val saved = ledger.read(access(group), ref.getString("evidence_id"), ref.getString("sha256"))!!
            assertEquals(String(fixture.body, Charsets.UTF_8), JSONObject(saved.getString("output_json")).getString("original_json"))
            val artifact = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture only")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
                .put("workspace", JSONArray().put(JSONObject().put("id", "remote-result").put("kind", "evidence")
                    .put("title", "Imported provider output").put("body", JSONObject().put("content", "Not semantic proof"))
                    .put("observations", JSONArray().put(ref)))).toString()
            val published = CollaborationResearchWorkspace(context).publish(access(group), artifact)
            assertEquals("recorded", published.getString("status"))
            val objectId = published.getJSONArray("revisions").getJSONObject(0).getString("object_id")
            val reopened = CollaborationResearchWorkspace(context).read(access(group), objectId, 1)!!
            assertEquals("desktop_codex_tool", reopened.getJSONArray("host_observations").getJSONObject(0).getString("origin"))
            assertTrue(store.states(group, 456).all { it.getString("status") == "imported" })
        } finally { CollaborationGroupStore(context).remove(group) }
        assertTrue(CollaborationRemoteEvidenceStore(context).states(group, 456).isEmpty())
    }

    @Test fun processCheckpointPhase(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("remoteEvidencePhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val token = args.getString("remoteEvidenceToken").orEmpty()
        require(token.matches(Regex("[a-z0-9-]{1,80}")))
        val group = "remote-evidence-process-$token"
        val fixture = Fixture(fields(group))
        if (phase == "seed") create(group)
        val store = CollaborationRemoteEvidenceStore(context)
        val ledger = CollaborationEvidenceLedger(context)
        val key = store.create("fixture-desktop", fields(group), access(group))
        if (phase == "seed") {
            assertFalse(CollaborationRemoteEvidenceImporter(store, ledger).run(key, { true }) { _, _, selection ->
                if (selection.optInt("page_index", -1) == 1) null else fixture.reply(selection)
            })
            assertNotNull(store.read(key)!!.optJSONObject("active"))
        } else try {
            assertTrue(CollaborationRemoteEvidenceImporter(store, ledger).run(key, { true }) { _, _, selection ->
                check(selection.optInt("page_index", -1) != 0) { "Saved page must not be requested again" }
                fixture.reply(selection)
            })
            val reference = ledger.browse(access(group)).first.single()
            val original = JSONObject(ledger.read(access(group), reference.getString("evidence_id"))!!.getString("output_json"))
            assertEquals(String(fixture.body, Charsets.UTF_8), original.getString("original_json"))
        } finally { CollaborationGroupStore(context).remove(group) }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("remote_evidence_phase", phase); putString("fixture_pid", android.os.Process.myPid().toString())
        })
    }
}
