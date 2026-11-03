package com.galaxyssi.chat

import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Public host/Keystore fixtures only; no model goal, website login or phone Linux browser is invoked. */
@RunWith(AndroidJUnit4::class)
class AgentCollaboratorBrowserIsolationDeviceTest {
    private val app get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun owner(source: Long?) = AgentNativeToolInvocationContext(sessionId = "public-parent", conversationId = "public-group",
        turnId = "public-turn", callerId = "public-browser-isolation", collaborationSourceMessageId = source,
        attributes = mapOf("workspace_id" to "public-files", "task_id" to "public-task"))

    private fun record(context: AgentNativeToolInvocationContext, browser: String): AgentBrowserUserRequest {
        val scope = AgentInteractiveBrowserTools.scope(context)
        return AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, browser), UUID.randomUUID().toString(), scope,
            context.sessionId, context.conversationId, context.turnId, context.callerId,
            context.attributes.getValue("workspace_id"), browser, "public-page", "public-handoff", "returned",
            taskId = "public-task", modelLoopId = "public-loop", collaborationSourceMessageId = context.collaborationSourceMessageId)
    }

    @Test fun membersGetDifferentStableHostCapabilitiesOnTheActualAndroidKeystore() {
        val a = AgentInteractiveBrowserTools.scope(owner(101))
        val b = AgentInteractiveBrowserTools.scope(owner(102))
        val ordinary = AgentInteractiveBrowserTools.scope(owner(null))
        val first = AgentBrowserHostAuthority.token(app, a)
        assertEquals(first, AgentBrowserHostAuthority.token(app, a))
        assertNotEquals(first, AgentBrowserHostAuthority.token(app, b))
        assertNotEquals(first, AgentBrowserHostAuthority.token(app, ordinary))
        assertEquals(64, first.length)
    }

    @Test fun encryptedStoreReloadPreservesTwoMembersUsingTheSameBrowserHandle() {
        val directory = File(app.cacheDir, "public-browser-isolation-${UUID.randomUUID()}")
        try {
            val store = AgentBrowserUserRequestStore(app, directory)
            val a = record(owner(101), "public-browser")
            val b = record(owner(102), "public-browser")
            store.save(a)
            store.save(b)
            val reloaded = AgentBrowserUserRequestStore(app, directory)
            assertEquals(a, reloaded.load(a.key))
            assertEquals(b, reloaded.load(b.key))
            assertFalse(reloaded.load(a.key)!!.sameOwner(owner(102)))
            directory.listFiles().orEmpty().forEach { file ->
                assertFalse(file.readBytes().toString(Charsets.UTF_8).contains("public-parent"))
                assertFalse(file.readBytes().toString(Charsets.UTF_8).contains("collaboration_source"))
            }
        } finally { directory.deleteRecursively() }
    }

    @Test fun returningOneMemberDoesNotChangeTheOtherMembersControlState() {
        val directory = File(app.cacheDir, "public-browser-return-${UUID.randomUUID()}")
        try {
            val store = AgentBrowserUserRequestStore(app, directory)
            val a = record(owner(101), "public-browser").copy(state = "active")
            val b = record(owner(102), "public-browser").copy(state = "active")
            store.save(a)
            store.save(b)
            store.save(a.copy(state = "returned"))
            val reloaded = AgentBrowserUserRequestStore(app, directory)
            assertEquals("returned", reloaded.load(a.key)!!.state)
            assertEquals("active", reloaded.load(b.key)!!.state)
            assertFalse(reloaded.load(b.key)!!.modelObservationCommitted)
        } finally { directory.deleteRecursively() }
    }

    @Test fun sameGenerationCannotRetagAnEncryptedRecordAsAnotherMember() {
        val directory = File(app.cacheDir, "public-browser-retag-${UUID.randomUUID()}")
        try {
            val store = AgentBrowserUserRequestStore(app, directory)
            val original = record(owner(101), "public-browser")
            store.save(original)
            listOf(102L, null).forEach { source ->
                assertThrows(AgentBrowserControlFailure::class.java) {
                    store.save(original.copy(collaborationSourceMessageId = source))
                }
            }
            assertEquals(original, AgentBrowserUserRequestStore(app, directory).load(original.key))
        } finally { directory.deleteRecursively() }
    }

    @Test fun nativeUserControlRequestPersistsHostSourceAndRoutesThroughItsOwnScope() {
        val browser = "public-browser-${UUID.randomUUID()}"
        val context = owner(101).copy(idempotencyKey = "public-handoff-${UUID.randomUUID()}")
        val scope = AgentInteractiveBrowserTools.scope(context)
        val key = AgentBrowserUserRequest.key(scope, browser)
        val captures = mutableListOf<AgentRuntimeExecutionRequest>()
        val control = AgentBrowserUserControl(app, execute = {
            captures += it
            AgentRuntimeExecutionResponse(0,
                """{"ok":true,"result":{"control_owner":"agent","handoff_id":"public-handoff"}}""", "", 1)
        }, enqueue = { error("An unbound member must not wake an ordinary parent Run") })
        val registry = AgentNativeToolRegistry().registerAll(AgentInteractiveBrowserTools.definitions(
            execute = { error("User control must use the host adapter") }, requestUserControl = control::request))
        try {
            val result = registry.invoke(AgentInteractiveBrowserTools.ACT,
                mapOf("operation" to "request_user_control", "session_id" to browser, "page_id" to "public-page"), context)
            assertTrue(result.error?.message, result.isSuccess)
            assertEquals(false, result.output["durable_resume_available"])
            val saved = AgentBrowserUserRequestStore(app).load(key)!!
            assertEquals(101L, saved.collaborationSourceMessageId)
            assertTrue(saved.sameOwner(context))
            assertFalse(saved.sameOwner(owner(102)))
            assertTrue(captures.isNotEmpty())
            captures.forEach {
                assertTrue(it.source.contains(scope))
                assertEquals(AgentWorkspaceScope.id("browser-control:$scope"), it.workspaceId)
            }
        } finally { AtomicFile(File(app.filesDir, "browser-user-requests/$key.enc")).delete() }
    }
}
