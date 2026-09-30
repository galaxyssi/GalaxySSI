package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in, read-only diagnosis of one user-selected floating conversation. */
@RunWith(AndroidJUnit4::class)
class ScreenAssistantLiveDiagnosticTest {
    @Test fun configuredProviderCanRouteTheSavedDocument() {
        val id = InstrumentationRegistry.getArguments().getString("screen_diagnostic_conversation").orEmpty()
        assumeTrue(id.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val question = "Summarize this article"
        val goal = ScreenAssistantContentPolicy.pageGoal(question, "Visible page captured")
        val turn = "content-route-regression"
        val screen = ScreenContext(foregroundApp = "fixture.article", pageTitle = "Article")
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { displayQuestion = question })
        try {
            val request = AgentRequest(goal = goal, screen = screen, targets = targets, memories = emptyList(),
                executionTurnId = turn,
                conversationContext = AgentConversationContext(id, "Article", emptyList(), true),
                runtimeContext = AgentRuntimeContextBuilder.build(sessionId = turn, goal = goal, screen = screen,
                    permissionMode = PermissionMode.FULL_ACCESS, highRiskGuard = false, memoryCapture = false,
                    callableTargets = targets, memories = emptyList()))
            val action = RuleBasedAgentPlanner(context).informationQueryAction(request)
            org.junit.Assert.assertNotNull("Configured provider was excluded by attachment instructions", action)
            org.junit.Assert.assertNotEquals(UNAVAILABLE_REASONING_CONNECTOR_ID, action?.parameters?.get("connector_id"))
            println("SCREEN_CONTENT_ROUTE ${action?.parameters?.get("connector_id")}")
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }

    @Test fun inspectSelectedConversation() {
        val args = InstrumentationRegistry.getArguments()
        val id = args.getString("screen_diagnostic_conversation").orEmpty()
        assumeTrue(id.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AgentTranscriptStore(context)
        val conversation = requireNotNull(store.conversation(id))
        val entries = store.page(id, pageSize = 30).entries
        val tasks = entries.map { it.taskId }.filter(String::isNotBlank).distinct()
            .mapNotNull { SQLiteAgentTaskStore(context).find(it) }
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val report = JSONObject()
            .put("title", conversation.title)
            .put("created_by_agent", conversation.createdByAgent)
            .put("selection", AgentModelSelectionSettings.selection(context, id).toString())
            .put("targets", JSONArray(targets.map { target -> JSONObject()
                .put("id", target.id).put("status", target.status.name)
                .put("capabilities", JSONArray(target.capabilities.map { it.name })) }))
            .put("tasks", JSONArray(tasks.takeLast(3).map { task -> JSONObject()
                .put("id", task.taskId).put("phase", task.phase.name)
                .put("target", task.targetTitle).put("result", task.result.take(500))
                .put("requirements", AgentTaskRequirementAnalyzer.analyze(task.goal).toString())
                .put("execution_log", JSONArray(task.executionLog.takeLast(10))) }))
        println("SCREEN_CONTENT_DIAG $report")
    }
}
