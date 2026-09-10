package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentIdempotentMutationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val input = mapOf("workspace_id" to "mutation-test", "path" to "note.txt",
        "text" to "old-write", "create_parents" to true)
    private val toolId = AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT

    @Test fun actualWorkspaceOverwriteSurvivesReceiptFailureAndDatabaseReopen() {
        val name = "mutation-reopen-${UUID.randomUUID()}"
        val root = File(context.filesDir, name).apply { mkdirs() }
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val backing = EncryptedAgentNativeToolReplayStore(ledger)
            val faulty = object : AgentNativeToolReplayStore by backing {
                override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                    error("Simulated receipt storage failure after actual workspace write")
                }
            }
            val registry = registry(root, faulty)
            assertTrue(registry.lookup(toolId)!!.descriptor.requiresEffectClaim)
            assertFalse(registry.lookup(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT)!!.descriptor.requiresEffectClaim)
            val result = registry.invoke(toolId, input, invocation("before"))
            assertFalse(result.toJson(), result.isSuccess)
            val file = root.walkTopDown().single { it.name == "note.txt" }
            assertEquals("old-write", file.readText())
            file.writeText("newer-user-write")
        } finally { ledger.close() }
        val reopened = AgentRunEventStore(context, "$name.db")
        try {
            val result = registry(root, EncryptedAgentNativeToolReplayStore(reopened))
                .invoke(toolId, input, invocation("after"))
            assertEquals(result.toJson(), "effect_outcome_unknown", result.error?.code)
            assertEquals("newer-user-write", root.walkTopDown().single { it.name == "note.txt" }.readText())
        } finally { reopened.close() }
        // Delete only this successfully verified test's private fixtures.
        context.deleteDatabase("$name.db")
        root.deleteRecursively()
    }

    @Test fun completedWorkspaceOverwriteReplaysItsReceiptWithoutOverwritingNewerText() {
        val name = "mutation-success-${UUID.randomUUID()}"
        val root = File(context.filesDir, name).apply { mkdirs() }
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val registry = registry(root, EncryptedAgentNativeToolReplayStore(ledger))
            assertTrue(registry.invoke(toolId, input, invocation("before")).isSuccess)
            val file = root.walkTopDown().single { it.name == "note.txt" }
            file.writeText("newer-user-write")
            val replay = registry.invoke(toolId, input, invocation("after"))
            assertTrue(replay.toJson(), replay.receipt.replayed)
            assertEquals("newer-user-write", file.readText())
        } finally { ledger.close() }
        context.deleteDatabase("$name.db")
        root.deleteRecursively()
    }

    @Test fun crashAfterActualWorkspaceWriteBeforeReceipt() {
        val name = crashCase()
        val root = File(context.filesDir, name)
        check(!root.exists()) { "Inspect existing crash evidence; never reseed this case" }
        check(root.mkdirs())
        val ledger = AgentRunEventStore(context, "$name.db")
        val backing = EncryptedAgentNativeToolReplayStore(ledger)
        val crashStore = object : AgentNativeToolReplayStore by backing {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                check(result.isSuccess) { result.toJson() }
                val file = root.walkTopDown().single { it.name == "note.txt" }
                check(file.readText() == "old-write")
                File(root, "pid-before.txt").writeText(android.os.Process.myPid().toString())
                android.os.Process.killProcess(android.os.Process.myPid())
                error("The process must die before outcome commit")
            }
        }
        registry(root, crashStore).invoke(toolId, input, invocation("before-crash"))
        fail("Expected test-only process termination")
    }

    @Test fun recoverActualWorkspaceWriteAfterProcessDeath() {
        val name = crashCase()
        val root = File(context.filesDir, name)
        assertTrue("Missing original crash evidence", File(root, "pid-before.txt").exists())
        assertNotEquals(File(root, "pid-before.txt").readText(), android.os.Process.myPid().toString())
        val file = root.walkTopDown().single { it.name == "note.txt" }
        if (!File(root, "verified.txt").exists()) {
            assertEquals("old-write", file.readText())
            file.writeText("newer-user-write")
        }
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val result = registry(root, EncryptedAgentNativeToolReplayStore(ledger))
                .invoke(toolId, input, invocation("after-crash"))
            assertEquals(result.toJson(), "effect_outcome_unknown", result.error?.code)
            assertEquals("newer-user-write", file.readText())
            File(root, "verified.txt").writeText("No replay; original evidence retained")
        } finally { ledger.close() }
    }

    private fun crashCase(): String {
        val id = InstrumentationRegistry.getArguments().getString("mutation_crash_case").orEmpty()
        assumeTrue("Explicit test-only crash case required", id.isNotBlank())
        require(id.matches(Regex("[a-z0-9-]{1,60}")))
        return "mutation-crash-$id"
    }

    private fun registry(root: File, store: AgentNativeToolReplayStore) = AgentPhoneNativeToolCatalog.createRegistry(
        workspaceFileTools = AgentWorkspaceFileTools(root.toPath()),
        actionExecutor = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("Not a UI test")
        },
        screenProvider = { ScreenContext("Test", pageTitle = "Mutation recovery") }, replayStore = store)

    private fun invocation(id: String) = AgentNativeToolInvocationContext(invocationId = id,
        sessionId = "session", conversationId = "conversation", turnId = "turn", idempotencyKey = "overwrite-action",
        grantedPermissions = setOf(AgentPhoneNativeToolCatalog.WORKSPACE_PRIVATE_PERMISSION),
        grantedConsents = setOf(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT))
}
