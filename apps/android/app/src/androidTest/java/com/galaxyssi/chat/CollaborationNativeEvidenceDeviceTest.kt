package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Only app-private fixture files and isolated collaboration groups; no live providers or physical controls. */
@RunWith(AndroidJUnit4::class)
class CollaborationNativeEvidenceDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private fun access(group: String) = CollaborationWorkspaceAccess(group, "root", "turn", 1, "native-node", "author")
    private fun createGroup(group: String) {
        val groups = CollaborationGroupStore(context)
        require(groups.load(group) == null)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("author", "Turing", "fixture", "Fixture")), coordinatorId = "author") }
        CollaborationEvidenceLedger(context).bind(901, access(group))
    }
    private fun registry() = AgentPhoneNativeToolCatalog.defaultRegistry(context,
        { ScreenContext(foregroundApp = "", pageTitle = "") }).subset { it.id.startsWith("galaxyssi.workspace.") }
    private fun invoke(registry: AgentNativeToolRegistry, group: String, tool: String,
                       input: AgentNativeJsonObject, invocationId: String = UUID.randomUUID().toString()): AgentNativeToolResult {
        val descriptor = registry.lookup(tool)!!.descriptor
        return registry.invoke(tool, input, AgentNativeToolInvocationContext(invocationId = invocationId,
            sessionId = group, conversationId = group, turnId = "turn", collaborationSourceMessageId = 901,
            idempotencyKey = invocationId,
            grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
            grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
            attributes = mapOf("workspace_id" to group, "task_id" to group)))
    }
    private fun prepareFile(registry: AgentNativeToolRegistry, group: String) {
        val init = invoke(registry, group, AgentPhoneNativeToolCatalog.WORKSPACE_INITIALIZE, mapOf("workspace_id" to group))
        assertTrue(init.toJson(), init.isSuccess)
        val create = invoke(registry, group, AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
            mapOf("workspace_id" to group, "path" to "evidence.txt", "text" to "Original native evidence"))
        assertTrue(create.toJson(), create.isSuccess)
    }
    private fun cleanup(group: String) {
        val ledger = CollaborationEvidenceLedger(context)
        val effectRuns = linkedSetOf<String>()
        var cursor = ""
        do {
            val page = ledger.browse(access(group), cursor)
            page.first.forEach { ref ->
                val raw = ledger.read(access(group), ref.getString("evidence_id"))!!.getString("output_json")
                val result = JSONObject(raw).toNativeToolResult()!!
                result.receipt.idempotencyKey?.let { key ->
                    effectRuns.add(EncryptedAgentNativeToolReplayStore.runId(AgentNativeToolReplayKey(
                        result.provenance.toolId, result.provenance.toolVersion, key,
                        AgentNativeEffectScope(sessionId = group, conversationId = group, taskId = group,
                            turnId = "turn", collaborationSourceMessageId = 901))))
                }
            }
            cursor = page.second.orEmpty()
        } while (cursor.isNotBlank())
        AgentRunEventStore(context).removeRuns(effectRuns)
        CollaborationGroupStore(context).remove(group)
        val root = File(context.filesDir, "agent-native-workspaces").canonicalFile
        val fixture = File(root, group).canonicalFile
        require(group.startsWith("native-evidence-") && fixture.parentFile == root)
        fixture.deleteRecursively()
    }

    @Test fun realFileToolUsesDefaultRegistryAndReopensExactObservation() {
        val group = "native-evidence-${UUID.randomUUID()}"
        createGroup(group)
        try {
            val registry = registry()
            prepareFile(registry, group)
            val read = invoke(registry, group, AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                mapOf("workspace_id" to group, "path" to "evidence.txt"))
            assertTrue(read.toJson(), read.isSuccess)
            val ref = read.collaborationObservation!!.receipt!!
            val ledger = CollaborationEvidenceLedger(context)
            val saved = ledger.read(access(group), ref["evidence_id"] as String, ref["sha256"] as String)!!
            assertEquals("android_native_tool", saved.getString("origin"))
            assertEquals("Original native evidence", JSONObject(saved.getString("output_json")).getJSONObject("output").getString("text"))
            assertNull(ledger.read(access(group).copy(nodeId = "other", personId = "other"), ref["evidence_id"] as String))
            val replay = invoke(registry, group, AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                mapOf("workspace_id" to group, "path" to "evidence.txt"), read.receipt.invocationId)
            assertTrue(replay.isSuccess)
            assertNotNull(replay.collaborationObservation!!.receipt)
            cleanup(group)
            assertNull(ledger.read(access(group), ref["evidence_id"] as String))
        } finally { cleanup(group) }
    }

    @Test fun processCheckpointPhase() {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("nativeEvidencePhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val token = arguments.getString("nativeEvidenceToken").orEmpty()
        require(token.matches(Regex("[a-z0-9-]{1,80}")))
        val group = "native-evidence-process-$token"
        val database = AgentEncryptedDatabase(context, "native_evidence_fixture_$token")
        val checkpoint = AgentModelLoopCheckpoint(object : AgentModelLoopRecords {
            override fun read(operation: String) = database.readString(operation, "").takeIf(String::isNotBlank)
            override fun write(operation: String, json: String) = database.writeString(operation, json)
        })
        val request = AgentModelToolLoopRequest(group, group, "turn", group, group,
            listOf(AgentModelMessage.user("Native checkpoint fixture")), loopId = group, collaborationSourceMessageId = 901)
        checkpoint.initial(request, "fixture-manifest")
        val tool = AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT
        val input = mapOf("workspace_id" to group, "path" to "evidence.txt")
        val invocation = checkpoint.invocation(1, AgentModelToolCall("read", tool, input), "1.0.0", 1, null) { "fixture-read" }
        if (phase == "seed") {
            createGroup(group)
            val registry = registry()
            prepareFile(registry, group)
            val result = invoke(registry, group, tool, input, invocation.id)
            assertTrue(result.toJson(), result.isSuccess)
            assertNotNull(result.collaborationObservation!!.receipt)
            checkpoint.result(invocation, result, 1)
        } else try {
            assertTrue(checkpoint.restored)
            val restored = invocation.result!!
            assertEquals("Original native evidence", restored.output["text"])
            val ref = restored.collaborationObservation!!.receipt!!
            val ledger = CollaborationEvidenceLedger(context)
            assertEquals(access(group), ledger.binding(901, group, "turn"))
            assertNotNull(ledger.read(access(group), ref["evidence_id"] as String, ref["sha256"] as String))
            assertEquals(3, ledger.browse(access(group)).first.size)
        } finally { cleanup(group); database.clear() }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("native_evidence_phase", phase)
            putString("fixture_pid", android.os.Process.myPid().toString())
        })
    }
}
