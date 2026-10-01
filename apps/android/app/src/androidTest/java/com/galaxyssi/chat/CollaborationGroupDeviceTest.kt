package com.galaxyssi.chat

import android.app.UiAutomation
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationGroupDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val automation get() = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)

    @Test fun groupPageKeepsMemberSearchAfterCompletionAndSeparatesTheOrdinaryPage() = withConversation { scenario, activity, id ->
        val members = listOf(CollaborationMember(name = "Turing", agentId = "fixture", providerLabel = "Codex", role = "Coordinator"),
            CollaborationMember(name = "Curie", agentId = "fixture", providerLabel = "Codex", role = "Reviewer"))
        CollaborationGroupStore(context).update(id) { it.copy(members = members, coordinatorId = members[0].id) }
        val run = "page-test-$id"
        val task = "page-task-$id"
        val turn = "page-turn-$id"
        val transcript = AgentTranscriptStore(context)
        members.forEachIndexed { index, member ->
            val definition = AgentTeamMember(agentId = member.agentId, instanceId = member.id,
                deliveryMode = if (index == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                role = member.role, context = mapOf("collaboration_group_id" to id,
                    "collaboration_name" to member.name, "collaboration_provider" to member.providerLabel))
            val request = AgentRunRequest(id, turn, task, runId = "$run:$index", parentRunId = run,
                goal = "Verify member attribution", idempotencyKey = "$run:$index")
            CollaborationProgressStore.register(context, AgentTeamMemberExecutionContext(definition, request,
                AgentSubagentContextHandoff("", emptyList(), 0, 100, false), 1, AgentSubagentProvenance()))
            val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}")
            val trace = AgentResearchTrace(queries = listOf("query-${member.name}"), sources = listOf(
                AgentResearchTrace.Source("https://example.com/${member.name}", "Source ${member.name}")))
            val payload = org.json.JSONObject().put("research_trace", trace.toJson())
                .put("progress_event", org.json.JSONObject().put("event_id", "search-$index").put("code", "web_search")
                    .put("kind", "tool").put("status", "running").put("detail", "query-${member.name}").put("updated_at", 2L))
            assertFalse(CollaborationProgressStore.remote(context, source, id, "wrong-turn", payload))
            repeat(3) { assertTrue(CollaborationProgressStore.remote(context, source, id, turn, payload)) }
            val metadata = CollaborationTranscriptMetadata(member.id, member.name, "Codex", member.role,
                AgentSubagentStatus.RUNNING, run, primary = index == 0)
            transcript.upsert(AgentTranscriptRole.PROCESS, member.role, dedupeKey = "member:$index:status",
                conversationId = id, taskId = task, turnId = turn, timestampMillis = 1L, collaborationJson = metadata.encode())
            assertEquals(listOf("query-${member.name}"), AgentResearchTraceStore.read(context, id, metadata.traceTurnId).queries)
        }
        assertEquals(2, transcript.list(id).count { CollaborationTranscriptMetadata.decode(it.collaborationJson)?.activity == true })
        assertFalse(AgentResearchTraceStore.read(context, id, turn).visible)
        transcript.append(AgentTranscriptRole.PROCESS, "Unattributed old search and global timer",
            dedupeKey = "ordinary-process", conversationId = id, turnId = turn, taskId = task)
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("independent group page") {
            var visible = false
            scenario.onActivity { visible = it.findViewById<View>(R.id.collaborationOutputList).visibility == View.VISIBLE &&
                it.findViewById<View>(R.id.agentOutputList).visibility == View.GONE }
            visible && windowTexts().any { it.contains("query-Curie") }
        }
        assertFalse(windowTexts().any { it.contains("Unattributed old search") })
        screenshot("collaboration-attributed-search.png")
        members.forEachIndexed { index, member ->
            val metadata = CollaborationTranscriptMetadata(member.id, member.name, "Codex", member.role,
                AgentSubagentStatus.SUCCEEDED, run, primary = index == 0)
            transcript.upsert(AgentTranscriptRole.PROCESS, member.role, dedupeKey = "member:$index:status", conversationId = id,
                turnId = turn, taskId = task, timestampMillis = 1L, collaborationJson = metadata.encode())
            transcript.upsert(AgentTranscriptRole.PROCESS, "${member.name}: verified result", dedupeKey = "member:$index:result",
                conversationId = id, turnId = turn, taskId = task, timestampMillis = 3L, collaborationJson = metadata.copy(result = true).encode())
        }
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("result rows") { windowTexts().contains("Curie: verified result") }
        assertFalse(windowTexts().contains(context.getString(R.string.collaboration_completed)))
        clickTextStarting(context.getString(R.string.collaboration_view_process))
        waitUntil("retained search history") { windowTexts().any { it.contains("query-") } }
        screenshot("collaboration-result-history.png")
        scenario.recreate()
        ready(scenario)
        assertEquals(2, AgentTranscriptStore(context).list(id).count { CollaborationTranscriptMetadata.decode(it.collaborationJson)?.activity == true })
        scenario.onActivity {
            it.selectConversationOutputPage(false)
            assertEquals(View.VISIBLE, it.findViewById<View>(R.id.agentOutputList).visibility)
            assertEquals(View.GONE, it.findViewById<View>(R.id.collaborationOutputList).visibility)
            assertSame(it.singleAgentTranscriptAdapter, it.agentOutputList.adapter)
            it.selectConversationOutputPage(true)
            assertSame(it.collaborationTranscriptAdapter, it.agentOutputList.adapter)
        }
    }

    @Test fun rosterPickerSettingsAndHistoryUseTheExistingConversation() = withConversation { scenario, activity, id ->
        val members = listOf(CollaborationMember(name = "Turing", agentId = "fixture:codex", providerLabel = "Codex",
            role = "Coordinator"), CollaborationMember(name = "Curie", agentId = "fixture:deepseek", providerLabel = "DeepSeek",
            role = "Independent review", independentReview = true))
        val store = CollaborationGroupStore(context)
        val saved = store.update(id) { it.copy(members = members, coordinatorId = members.first().id) }
        assertEquals(saved, store.load(id))
        scenario.onActivity {
            it.refreshCollaborationStrip()
            assertEquals("active=${it.agentTranscriptStore.activeConversation().id}, rendered=${it.agentRenderedConversationId}, fixture=$id",
                View.VISIBLE, it.findViewById<View>(R.id.collaborationMemberStrip).visibility)
            it.agentGoalInput.requestFocus()
            it.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                .showSoftInput(it.agentGoalInput, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
            it.agentGoalInput.setText("@")
            it.agentGoalInput.setSelection(1)
            it.maybeShowAgentMentionPicker(it.agentGoalInput.text)
        }
        waitUntil("member picker") { windowTexts().contains("Turing  AI") }
        screenshot("collaboration-members.png")
        assertTrue(windowTexts().any { it.contains("Curie") })
        clickTextStarting(context.getString(R.string.collaboration_settings))
        waitUntil("member manager") { windowTexts().contains(context.getString(R.string.collaboration_add)) }
        clickTextStarting("Turing")
        waitUntil("member settings") { windowTexts().contains(context.getString(R.string.collaboration_independent)) }
        screenshot("collaboration-settings.png")
        clickTextStarting(context.getString(R.string.collaboration_done))
        waitUntil("saved member settings") { store.load(id)?.revision == saved.revision + 1 }
        waitUntil("settings closed after save") { !windowTexts().contains(context.getString(R.string.collaboration_independent)) }
        scenario.onActivity { it.agentGoalInput.setText("") }
        val metadata = CollaborationTranscriptMetadata(members[0].id, "Turing", "Codex", "Coordinator",
            AgentSubagentStatus.RUNNING, "fixture-run")
        activity.agentTranscriptStore.upsert(AgentTranscriptRole.PROCESS, "Check the test evidence",
            dedupeKey = "collaboration:fixture:status", conversationId = id, collaborationJson = metadata.encode())
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("member progress row") { windowTexts().contains(context.getString(R.string.collaboration_running)) }
        screenshot("collaboration-progress.png")
        scenario.recreate()
        ready(scenario)
        assertEquals(saved.copy(revision = saved.revision + 1), store.load(id))
    }

    @Test fun realCodexAndDeepSeekDeliverSeparateMemberResults() {
        assumeTrue("Real model calls require explicit invocation", InstrumentationRegistry.getArguments()
            .getString("collaborationReal") == "true")
        withConversation { scenario, _, id ->
            val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
                .filter { it.status == AgentConnectorStatus.AVAILABLE }
            val codex = requireNotNull(targets.firstOrNull { it.id.contains("codex", true) && ':' in it.id }) { "Paired Codex unavailable" }
            val deepseek = requireNotNull(targets.firstOrNull { it.title.contains("deepseek", true) || it.id.contains("deepseek", true) }) { "DeepSeek unavailable" }
            val members = listOf(CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title,
                role = "Coordinate and combine the verified result"),
                CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title,
                    role = "Independently check the arithmetic", independentReview = true))
            CollaborationGroupStore(context).update(id) { it.copy(members = members, coordinatorId = members.first().id) }
            scenario.onActivity {
                it.refreshCollaborationStrip()
                it.agentGoalInput.setText("协作验收：请两位成员分别按职责核对 17 × 23 的结果，每位在回复开头写自己的成员名字，协调员汇总为一句中文。无需联网，不调用手机操作工具。")
                it.submitAgentGoal()
            }
            val runtime = GlobalSuperAgentRuntime.get(context)
            var snapshot: AgentTeamExecutionSnapshot? = null
            waitUntil("real collaboration completion", 360_000) {
                snapshot = runtime.agentTeamSnapshots().firstOrNull { it.conversationId == id }
                snapshot?.state?.isTerminal == true
            }
            val result = requireNotNull(snapshot)
            val report = "state=${result.state}\n" + result.members.joinToString("\n") {
                "${it.displayName}: ${it.status}, chars=${it.output.length}, error=${it.errorMessage.take(200)}"
            }
            File(context.getExternalFilesDir(null), "collaboration-real-result.txt").writeText(report)
            assertEquals(report, AgentTeamExecutionState.SUCCEEDED, result.state)
            assertEquals(2, result.members.size)
            assertTrue(report, result.members.all { it.status == AgentSubagentStatus.SUCCEEDED && it.output.contains("391") })
            assertTrue("Each real model must receive its own member identity", result.members.all {
                it.output.contains(it.displayName, ignoreCase = true)
            })
            val transcript = AgentTranscriptStore(context).list(id)
            assertEquals(2, transcript.count { CollaborationTranscriptMetadata.decode(it.collaborationJson)?.result == true })
            waitUntil("canonical final answer", 30_000) {
                AgentTranscriptStore(context).list(id).any { it.role == AgentTranscriptRole.ASSISTANT && it.text.contains("391") }
            }
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            screenshot("collaboration-real-result.png")
        }
    }

    @Test fun realResearchResolvesMissingDetailsAndKeepsMemberEvidence() {
        assumeTrue("Real research requires explicit invocation", InstrumentationRegistry.getArguments()
            .getString("collaborationResearch") == "true")
        withConversation { scenario, _, id ->
            val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
                .filter { it.status == AgentConnectorStatus.AVAILABLE }
            val codex = requireNotNull(targets.firstOrNull { it.id.contains("codex", true) && ':' in it.id })
            val deepseek = requireNotNull(targets.firstOrNull { it.title.contains("deepseek", true) || it.id.contains("deepseek", true) })
            val members = listOf(CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title,
                role = "Coordinator: decide reversible defaults and verify the actionable plan"),
                CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title,
                    role = "Researcher: read the official Kotlin coroutine cancellation documentation"))
            CollaborationGroupStore(context).update(id) { it.copy(members = members, coordinatorId = members[0].id) }
            scenario.onActivity {
                it.refreshCollaborationStrip()
                it.agentGoalInput.setText("协作验收：为一个业务类型尚未确定的 Android App 制定长任务取消方案。请研究 Kotlin 官方协程取消文档，提供两条准确规则及官方来源链接。缺少业务细节时选择可撤销的合理假设直接推进，不要停下来反问。协调员给出简洁方案和两个验收用例。只研究，不修改设备、不操作其他应用。")
                it.submitAgentGoal()
            }
            var snapshot: AgentTeamExecutionSnapshot? = null
            val runtime = GlobalSuperAgentRuntime.get(context)
            waitUntil("real research completion", 360_000) {
                snapshot = runtime.agentTeamSnapshots().firstOrNull { it.conversationId == id }
                snapshot?.state?.isTerminal == true
            }
            val result = requireNotNull(snapshot)
            val rows = AgentTranscriptStore(context).list(id)
            val activity = rows.mapNotNull { CollaborationTranscriptMetadata.decode(it.collaborationJson) }
                .filter { it.activity }
            val researcher = result.members.single { it.displayName == "Curie" }
            val report = "state=${result.state}\nactivities=${activity.size}\n" + result.members.joinToString("\n\n") {
                "${it.displayName}: ${it.status}\n${it.output}\n${it.errorMessage}"
            }
            File(context.getExternalFilesDir(null), "collaboration-real-research.txt").writeText(report)
            assertEquals(report, AgentTeamExecutionState.SUCCEEDED, result.state)
            assertTrue(report, researcher.output.contains("kotlinlang.org"))
            assertTrue("Research activity must belong to Curie", activity.any { it.memberId == members[1].id })
            val trace = AgentResearchTraceStore.read(context, id, "collaboration:${result.supervisorRunId}:${members[1].id}")
            assertTrue("Search evidence must persist under the member", trace.visible)
            val turn = rows.first { it.taskId == result.taskId && it.turnId.isNotBlank() }.turnId
            assertFalse("No shared global search trace", AgentResearchTraceStore.read(context, id, turn).visible)
            assertTrue(report, result.members.single { it.displayName == "Turing" }.output.length > 100)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            screenshot("collaboration-real-research.png")
        }
    }

    @Test fun realResearchRunsCrossReviewAndValidatesTwoAlternatives() {
        assumeTrue("Deep research requires explicit invocation", InstrumentationRegistry.getArguments()
            .getString("collaborationDeep") == "true")
        withConversation { scenario, _, id ->
            val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
                .filter { it.status == AgentConnectorStatus.AVAILABLE }
            val codex = requireNotNull(targets.firstOrNull { it.id.contains("codex", true) && ':' in it.id })
            val deepseek = requireNotNull(targets.firstOrNull { it.title.contains("deepseek", true) || it.id.contains("deepseek", true) })
            val members = listOf(
                CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title, role = "Coordinator"),
                CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title, role = "Researcher"),
                CollaborationMember(name = "Hopper", agentId = deepseek.id, providerLabel = deepseek.title, role = "Independent reviewer"))
            CollaborationGroupStore(context).update(id) {
                it.copy(members = members, coordinatorId = members[0].id, workflow = CollaborationWorkflow.RESEARCH)
            }
            scenario.onActivity {
                it.refreshCollaborationStrip()
                it.agentGoalInput.setText("协作验收：把数字 1、2、3、4、5、6、7、8 分到两个小组，每组数字之和均为18，每个数字恰好使用一次。请独立提出、交叉挑战并保留两种不同的分组方案 C1/C2，同时核对约束。每个阶段只写关键结论，最终给出两方案、核对结果及差异。纯数学任务，不联网、不操作手机或外部应用，不得假称运行了工具。")
                it.submitAgentGoal()
            }
            var snapshot: AgentTeamExecutionSnapshot? = null
            val runtime = GlobalSuperAgentRuntime.get(context)
            waitUntil("deep research graph creation", 45_000) {
                runtime.agentTeamSnapshots().any { it.conversationId == id }
            }
            var lastProgress = ""
            waitUntil("real multi-stage research completion", 600_000) {
                snapshot = runtime.agentTeamSnapshots().firstOrNull { it.conversationId == id }
                val progress = snapshot?.let { state -> "state=${state.state}\n" +
                    state.members.joinToString("\n") { "${it.displayName}/${it.researchStage}: ${it.status}" } }.orEmpty()
                if (progress != lastProgress) {
                    File(context.getExternalFilesDir(null), "collaboration-deep-progress.txt").writeText(progress)
                    lastProgress = progress
                }
                snapshot?.state?.isTerminal == true
            }
            val result = requireNotNull(snapshot)
            val report = "state=${result.state}\n" + result.members.joinToString("\n\n") {
                "${it.displayName}/${it.researchStage}: ${it.status}\n${it.output}\n${it.errorMessage}"
            }
            File(context.getExternalFilesDir(null), "collaboration-deep-research.txt").writeText(report)
            assertEquals(report, AgentTeamExecutionState.SUCCEEDED, result.state)
            assertEquals(14, result.members.size)
            assertEquals(3, result.members.map { it.personId }.distinct().size)
            assertEquals(2, result.members.count { it.researchStage == "VERIFY" })
            assertEquals(2, result.members.count { it.researchStage == "RECHECK" })
            val combined = result.members.single { it.researchStage == "COMBINE" }
            val artifact = requireNotNull(CollaborationResearchArtifact.decode(combined.output)) { combined.output }
            assertTrue(combined.output, artifact.getJSONArray("candidates").length() >= 2)
            val final = result.members.single { it.researchStage == "DELIVER" }.output
            assertTrue(final, final.contains("C1") && final.contains("C2") && final.contains("18"))
            assertFalse(final, final.contains(CollaborationResearchArtifact.FORMAT))
            val archived = CollaborationResearchArchive(context, id).browse()
            assertEquals(28, archived.total)
            waitUntil("canonical deep research answer", 30_000) {
                AgentTranscriptStore(context).list(id).any { it.role == AgentTranscriptRole.ASSISTANT && it.text.contains("18") }
            }
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            screenshot("collaboration-deep-research.png")
        }
    }

    private fun withConversation(block: (ActivityScenario<MainActivity>, MainActivity, String) -> Unit) {
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val reference = AtomicReference<MainActivity>()
        var id = ""
        var previous = ""
        try {
            ready(scenario)
            scenario.onActivity {
                reference.set(it)
                it.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation()
                id = it.agentTranscriptStore.activeConversation().id
            }
            reference.get().agentTranscriptStore.append(AgentTranscriptRole.PROCESS, "Collaboration acceptance fixture",
                dedupeKey = "collaboration-created:$id", conversationId = id)
            reference.get().agentTranscriptStore.renameConversation(id, "Collaboration acceptance")
            block(scenario, reference.get(), id)
        } catch (error: Throwable) {
            screenshot("collaboration-failure.png")
            File(context.getExternalFilesDir(null), "collaboration-failure.txt").writeText(
                error.toString() + "\n" + windowTexts().joinToString("\n"))
            throw error
        } finally {
            if (id.isNotBlank()) {
                val runtime = GlobalSuperAgentRuntime.get(context)
                runtime.agentTeamSnapshots().filter { it.conversationId == id && !it.state.isTerminal }
                    .forEach { runtime.cancelAgentTeam(it.supervisorRunId) }
                reference.get()?.agentTranscriptStore?.deleteConversation(id)
            }
            if (previous.isNotBlank()) reference.get()?.agentTranscriptStore?.switchConversation(previous)
            scenario.close()
        }
    }

    private fun ready(scenario: ActivityScenario<MainActivity>) = waitUntil("activity ready", 60_000) {
        var ready = false
        scenario.onActivity { ready = !it.initialAgentHydrationPending &&
            it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE &&
            it.conversationWindow.conversationId.isNotBlank() }
        ready
    }

    private fun waitUntil(label: String, timeout: Long = 15_000, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(200)
        }
        fail("Timed out: $label")
    }

    private fun windowTexts(): List<String> = buildList {
        fun visit(node: android.view.accessibility.AccessibilityNodeInfo?) {
            if (node == null || node.packageName?.toString() != context.packageName) return
            node.text?.toString()?.let(::add)
            repeat(node.childCount) { visit(node.getChild(it)) }
        }
        automation.windows.forEach { visit(it.root) }
        visit(automation.rootInActiveWindow)
    }

    private fun clickTextStarting(prefix: String) {
        fun visit(node: android.view.accessibility.AccessibilityNodeInfo?): Boolean {
            if (node == null || node.packageName?.toString() != context.packageName) return false
            if (node.text?.toString()?.startsWith(prefix) == true) {
                var candidate: android.view.accessibility.AccessibilityNodeInfo? = node
                repeat(4) {
                    if (candidate?.isClickable == true) return candidate!!.performAction(
                        android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
                    candidate = candidate?.parent
                }
            }
            return (0 until node.childCount).any { visit(node.getChild(it)) }
        }
        assertTrue("No clickable member $prefix", automation.windows.any { visit(it.root) } || visit(automation.rootInActiveWindow))
    }

    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        SystemClock.sleep(600)
        automation.takeScreenshot()?.let { bitmap ->
            try { File(context.getExternalFilesDir(null), name).outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            } } finally { bitmap.recycle() }
        }
    }
}
