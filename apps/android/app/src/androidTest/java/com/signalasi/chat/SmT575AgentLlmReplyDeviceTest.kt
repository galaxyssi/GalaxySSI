package com.signalasi.chat

import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SmT575AgentLlmReplyDeviceTest {
    @Test
    fun reportsAvailableRealAgentTargets() {
        requireSmT575()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
        val callableTargets = targets.filter { target ->
            target.status == AgentConnectorStatus.AVAILABLE &&
                target.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                AgentCapability.CHAT in target.capabilities
        }
        val report = JSONObject()
            .put("device_model", Build.MODEL)
            .put("device_name", Build.DEVICE)
            .put("target_count", targets.size)
            .put("callable_target_count", callableTargets.size)
            .put("targets", JSONArray().apply {
                targets.forEach { target ->
                    put(JSONObject()
                        .put("id", target.id)
                        .put("title", target.title)
                        .put("kind", target.kind.name)
                        .put("status", target.status.name)
                        .put("adapter_type", target.adapterType)
                        .put("failure_domain", target.failureDomain)
                        .put("capabilities", JSONArray(target.capabilities.map(AgentCapability::name))))
                }
            })
        val reportDirectory = File(context.filesDir, REPORT_DIRECTORY)
        check(reportDirectory.mkdirs() || reportDirectory.isDirectory)
        File(reportDirectory, TARGET_REPORT_FILE).writeText(report.toString(2))
        Log.i(LOG_TAG, "agent_targets ${report}")
        assertTrue("SM-T575 has no available chat Agent/model target: $report", callableTargets.isNotEmpty())
    }

    @Test
    fun receivesOneRealCodexReply() {
        requireSmT575()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        val marker = "SM_T575_LLM_SMOKE_OK"
        val goal = """
            This is a real SignalASI Agent transport acceptance case on SM-T575.
            Do not use tools and do not modify any file. Determine the next letter after Q in the English alphabet.
            Reply with exactly one line: $marker | R
        """.trimIndent()
        lateinit var conversation: AgentConversation
        lateinit var turnId: String
        lateinit var target: AgentCallableTarget
        val startedAt = SystemClock.elapsedRealtime()
        instrumentation.runOnMainSync {
            target = requireCodexDesktopTarget(activity)
            activity.agentTranscriptStore.conversations(includeArchived = true)
                .filter { it.title == SMOKE_CONVERSATION_TITLE }
                .forEach { previous ->
                    activity.agentTranscriptStore.deleteConversation(previous.id)
                }
            conversation = activity.agentTranscriptStore.createConversation(
                SMOKE_CONVERSATION_TITLE,
                privateMode = true
            )
            turnId = "sm-t575-llm-smoke-${System.currentTimeMillis()}"
            check(activity.agentTranscriptStore.append(
                role = AgentTranscriptRole.USER,
                text = goal,
                dedupeKey = "$turnId:user",
                conversationId = conversation.id,
                turnId = turnId,
                taskId = turnId
            ))
            activity.continueAgentGoalSubmission(
                goal = goal,
                conversationId = conversation.id,
                turnId = turnId,
                forcedAction = connectorAction(target, goal, turnId),
                originalGoal = goal,
                executionModeOverride = AgentTaskExecutionMode.AUTO_COMPLETE
            )
        }

        val store = AgentTranscriptStore(instrumentation.targetContext)
        val response = waitForAssistantReply(store, turnId, marker, SMOKE_TIMEOUT_MILLIS)
        val entries = store.entriesForTurn(turnId)
        val run = AgentRunRecorder(instrumentation.targetContext).activeRun(conversation.id)
        val report = JSONObject()
            .put("device_model", Build.MODEL)
            .put("device_name", Build.DEVICE)
            .put("target_id", target.id)
            .put("target_title", target.title)
            .put("turn_id", turnId)
            .put("conversation_id", conversation.id)
            .put("latency_ms", SystemClock.elapsedRealtime() - startedAt)
            .put("response", response.text)
            .put("response_dedupe_key", response.dedupeKey)
            .put("process_entry_count", entries.count { it.role == AgentTranscriptRole.PROCESS })
            .put("run_id", run?.runId.orEmpty())
            .put("run_status", run?.status?.name.orEmpty())
            .put("execution_resource_id", run?.executionResourceId.orEmpty())
        val reportDirectory = File(instrumentation.targetContext.filesDir, REPORT_DIRECTORY)
        check(reportDirectory.mkdirs() || reportDirectory.isDirectory)
        File(reportDirectory, SMOKE_REPORT_FILE).writeText(report.toString(2))
        Log.i(LOG_TAG, "agent_smoke $report")

        assertTrue("Real Codex response did not preserve the marker: ${response.text}", marker in response.text)
        assertTrue("Real Codex response did not return the expected answer: ${response.text}",
            Regex("(?:^|\\s|[|])R(?:$|\\s)").containsMatchIn(response.text))
        assertTrue("The response was produced by a local fast path",
            entries.none { it.dedupeKey.startsWith("fast-local:") })
        assertTrue("No connector lifecycle entry was persisted for the real reply",
            entries.any { entry ->
                entry.role == AgentTranscriptRole.PROCESS &&
                    (entry.dedupeKey.startsWith("connector-event:") ||
                        entry.dedupeKey.startsWith("execution-loop:"))
            })
        instrumentation.runOnMainSync { activity.finish() }
    }

    @Test
    fun receives100RealCodexReplies() {
        requireSmT575()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        val target = requireCodexDesktopTarget(activity)
        val cases = realLlmCases()
        val store = activity.agentTranscriptStore
        val conversations = linkedMapOf<Int, AgentConversation>()
        val results = linkedMapOf<Int, RealLlmCaseResult>()
        var invocationCount = 0
        val suiteStartedAtElapsed = SystemClock.elapsedRealtime()
        val suiteStartedAtMillis = System.currentTimeMillis()

        instrumentation.runOnMainSync {
            val previous = store.conversations(includeArchived = true)
                .filter { it.title.startsWith(ACCEPTANCE_CONVERSATION_PREFIX) }
            check(store.deleteConversations(previous) == previous.size) {
                "Could not clear ${previous.size} previous real LLM acceptance conversations"
            }
        }

        cases.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batchCases ->
            var pending = batchCases
            for (attempt in 1..MAX_ATTEMPTS) {
                if (pending.isEmpty()) break
                val executions = mutableListOf<RealLlmCaseExecution>()
                instrumentation.runOnMainSync {
                    pending.forEach { testCase ->
                        val conversation = conversations.getOrPut(testCase.index) {
                            store.createConversation(
                                "$ACCEPTANCE_CONVERSATION_PREFIX" +
                                    "${testCase.index.toString().padStart(3, '0')} · ${testCase.category}",
                                privateMode = true
                            )
                        }
                        val turnId = "sm-t575-llm-${testCase.index.toString().padStart(3, '0')}-" +
                            "a$attempt-${System.currentTimeMillis()}"
                        val prompt = promptFor(testCase)
                        check(!AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(prompt)) {
                            "Case ${testCase.index} was incorrectly classified as a supervised project"
                        }
                        check(store.append(
                            role = AgentTranscriptRole.USER,
                            text = prompt,
                            dedupeKey = "$turnId:user",
                            conversationId = conversation.id,
                            turnId = turnId,
                            taskId = turnId
                        ))
                        val execution = RealLlmCaseExecution(
                            testCase = testCase,
                            conversationId = conversation.id,
                            turnId = turnId,
                            attempt = attempt,
                            startedAtElapsed = SystemClock.elapsedRealtime()
                        )
                        executions += execution
                        activity.continueAgentGoalSubmission(
                            goal = prompt,
                            conversationId = conversation.id,
                            turnId = turnId,
                            forcedAction = connectorAction(target, prompt, turnId),
                            originalGoal = prompt,
                            executionModeOverride = AgentTaskExecutionMode.AUTO_COMPLETE
                        )
                    }
                }
                invocationCount += executions.size
                val attemptResults = waitForBatch(
                    context = instrumentation.targetContext,
                    store = store,
                    target = target,
                    executions = executions,
                    timeoutMillis = BATCH_TIMEOUT_MILLIS
                )
                attemptResults.forEach { result -> results[result.testCase.index] = result }
                pending = attemptResults.filterNot(RealLlmCaseResult::passed).map(RealLlmCaseResult::testCase)
                if (pending.isNotEmpty()) {
                    Log.w(
                        LOG_TAG,
                        "batch_retry batch=${batchIndex + 1} attempt=$attempt " +
                            "pending=${pending.joinToString { it.index.toString() }}"
                    )
                }
            }
            val report = buildSuiteReport(
                target = target,
                cases = cases,
                results = results.values.toList(),
                invocationCount = invocationCount,
                suiteStartedAtMillis = suiteStartedAtMillis,
                elapsedMillis = SystemClock.elapsedRealtime() - suiteStartedAtElapsed,
                complete = results.size == cases.size
            )
            writeReport(instrumentation.targetContext, SUITE_REPORT_FILE, report)
            Log.i(
                LOG_TAG,
                "suite_progress batch=${batchIndex + 1}/${cases.size / BATCH_SIZE} " +
                    "passed=${results.values.count(RealLlmCaseResult::passed)}/${results.size} " +
                    "invocations=$invocationCount"
            )
        }

        val finalResults = results.values.sortedBy { it.testCase.index }
        val finalReport = buildSuiteReport(
            target = target,
            cases = cases,
            results = finalResults,
            invocationCount = invocationCount,
            suiteStartedAtMillis = suiteStartedAtMillis,
            elapsedMillis = SystemClock.elapsedRealtime() - suiteStartedAtElapsed,
            complete = true
        )
        writeReport(instrumentation.targetContext, SUITE_REPORT_FILE, finalReport)
        Log.i(LOG_TAG, "suite_complete ${finalReport}")

        val persistedConversations = store.conversations(includeArchived = true)
            .filter { it.title.startsWith(ACCEPTANCE_CONVERSATION_PREFIX) }
        assertEquals(EXPECTED_CASE_COUNT, cases.size)
        assertEquals(EXPECTED_CASE_COUNT, finalResults.size)
        assertEquals(EXPECTED_CASE_COUNT, finalResults.count(RealLlmCaseResult::passed))
        assertEquals(EXPECTED_CASE_COUNT, persistedConversations.size)
        assertTrue(persistedConversations.all(AgentConversation::privateMode))
        assertEquals(EXPECTED_CASE_COUNT, persistedConversations.map(AgentConversation::title).distinct().size)
        instrumentation.runOnMainSync { activity.finish() }
    }

    private fun requireCodexDesktopTarget(context: android.content.Context): AgentCallableTarget =
        AppStoreAgentConnectorRegistry(context).availableTargets().firstOrNull { target ->
            target.status == AgentConnectorStatus.AVAILABLE &&
                target.kind == AgentConnectorKind.AGENT &&
                target.id.endsWith(":codex")
        } ?: error("The explicit Codex Desktop target is not available")

    private fun connectorAction(target: AgentCallableTarget, goal: String, turnId: String) = AgentAction(
        id = "sm-t575-real-llm-$turnId",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = target.title,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Run a real SM-T575 Agent/LLM acceptance case with ${target.title}",
        parameters = mapOf("connector_id" to target.id, "prompt" to goal),
        requiresConfirmation = false
    )

    private fun waitForAssistantReply(
        store: AgentTranscriptStore,
        turnId: String,
        marker: String,
        timeoutMillis: Long
    ): AgentTranscriptEntry {
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        var latestAssistant: AgentTranscriptEntry? = null
        while (SystemClock.elapsedRealtime() < deadline) {
            val entries = store.entriesForTurn(turnId)
            latestAssistant = entries.lastOrNull { entry ->
                entry.role == AgentTranscriptRole.ASSISTANT &&
                    !entry.dedupeKey.startsWith("approval:") &&
                    !entry.dedupeKey.startsWith("remote-approval:")
            }
            if (latestAssistant != null && marker in latestAssistant.text) return latestAssistant
            SystemClock.sleep(REPLY_POLL_MILLIS)
        }
        error("Timed out waiting for real Agent/LLM reply; latest=${latestAssistant?.text.orEmpty()}")
    }

    private fun waitForBatch(
        context: android.content.Context,
        store: AgentTranscriptStore,
        target: AgentCallableTarget,
        executions: List<RealLlmCaseExecution>,
        timeoutMillis: Long
    ): List<RealLlmCaseResult> {
        val pending = executions.associateByTo(linkedMapOf(), RealLlmCaseExecution::turnId)
        val results = linkedMapOf<String, RealLlmCaseResult>()
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        while (pending.isNotEmpty() && SystemClock.elapsedRealtime() < deadline) {
            val iterator = pending.iterator()
            while (iterator.hasNext()) {
                val (turnId, execution) = iterator.next()
                val entries = store.entriesForTurn(turnId)
                val assistant = entries.lastOrNull { entry ->
                    entry.role == AgentTranscriptRole.ASSISTANT &&
                        !entry.dedupeKey.startsWith("approval:") &&
                        !entry.dedupeKey.startsWith("remote-approval:")
                } ?: continue
                val run = AgentRunRecorder(context).activeRun(execution.conversationId)
                if (run?.status == AgentRecordedRunStatus.RUNNING) continue
                results[turnId] = evaluateResult(execution, target, entries, assistant, run)
                iterator.remove()
            }
            if (pending.isNotEmpty()) SystemClock.sleep(REPLY_POLL_MILLIS)
        }
        pending.forEach { (turnId, execution) ->
            val entries = store.entriesForTurn(turnId)
            val assistant = entries.lastOrNull { it.role == AgentTranscriptRole.ASSISTANT }
            val run = AgentRunRecorder(context).activeRun(execution.conversationId)
            results[turnId] = if (assistant == null) {
                RealLlmCaseResult(
                    testCase = execution.testCase,
                    conversationId = execution.conversationId,
                    turnId = turnId,
                    attempt = execution.attempt,
                    latencyMillis = SystemClock.elapsedRealtime() - execution.startedAtElapsed,
                    response = "",
                    responseDedupeKey = "",
                    runId = run?.runId.orEmpty(),
                    runStatus = run?.status?.name.orEmpty(),
                    executionResourceId = run?.executionResourceId.orEmpty(),
                    processEntryCount = entries.count { it.role == AgentTranscriptRole.PROCESS },
                    passed = false,
                    failure = "timeout_without_assistant_reply"
                )
            } else {
                val evaluated = evaluateResult(execution, target, entries, assistant, run)
                evaluated.copy(failure = "timeout_before_terminal_run:${evaluated.failure}")
            }
        }
        return executions.map { execution -> checkNotNull(results[execution.turnId]) }
    }

    private fun evaluateResult(
        execution: RealLlmCaseExecution,
        target: AgentCallableTarget,
        entries: List<AgentTranscriptEntry>,
        assistant: AgentTranscriptEntry,
        run: AgentRecordedRun?
    ): RealLlmCaseResult {
        val expectedLine = "${execution.testCase.marker} | ${execution.testCase.expected}"
        val exactAnswer = assistant.text.trim() == expectedLine
        val finalResponse = assistant.dedupeKey.startsWith("assistant-final:")
        val noFastLocal = entries.none { it.dedupeKey.startsWith("fast-local:") }
        val connectorEvidence = entries.any { entry ->
            entry.role == AgentTranscriptRole.PROCESS &&
                (entry.dedupeKey.startsWith("connector-event:") ||
                    entry.dedupeKey.startsWith("execution-loop:"))
        }
        val completedRun = run?.status == AgentRecordedRunStatus.COMPLETED
        val exactResource = run?.executionResourceId == target.id
        val failures = buildList {
            if (!exactAnswer) add("answer_mismatch")
            if (!finalResponse) add("not_final_response")
            if (!noFastLocal) add("fast_local_path")
            if (!connectorEvidence) add("missing_connector_evidence")
            if (!completedRun) add("run_not_completed:${run?.status?.name.orEmpty()}")
            if (!exactResource) add("wrong_execution_resource:${run?.executionResourceId.orEmpty()}")
        }
        return RealLlmCaseResult(
            testCase = execution.testCase,
            conversationId = execution.conversationId,
            turnId = execution.turnId,
            attempt = execution.attempt,
            latencyMillis = SystemClock.elapsedRealtime() - execution.startedAtElapsed,
            response = assistant.text,
            responseDedupeKey = assistant.dedupeKey,
            runId = run?.runId.orEmpty(),
            runStatus = run?.status?.name.orEmpty(),
            executionResourceId = run?.executionResourceId.orEmpty(),
            processEntryCount = entries.count { it.role == AgentTranscriptRole.PROCESS },
            passed = failures.isEmpty(),
            failure = failures.joinToString(",")
        )
    }

    private fun realLlmCases(): List<RealLlmCase> = buildList {
        for (position in 1..20) {
            val left = 20 + position
            val right = 2 + position % 9
            val (expression, expected) = when (position % 3) {
                0 -> "$left + $right" to (left + right).toString()
                1 -> "$left - $right" to (left - right).toString()
                else -> "$left * $right" to (left * right).toString()
            }
            add(realLlmCase(size + 1, "Arithmetic", "Compute $expression as an integer.", expected))
        }
        for (position in 1..20) {
            val source = "AGENT${position.toString().padStart(2, '0')}Q"
            add(realLlmCase(
                size + 1,
                "String",
                "Reverse the exact ASCII string $source character by character.",
                source.reversed()
            ))
        }
        for (position in 1..20) {
            val number = 101 + position * 7
            add(realLlmCase(
                size + 1,
                "Classification",
                "Classify the integer $number using exactly EVEN or ODD.",
                if (number % 2 == 0) "EVEN" else "ODD"
            ))
        }
        for (position in 1..20) {
            val digits = listOf(
                (position * 7 + 3) % 10,
                (position * 5 + 1) % 10,
                (position * 3 + 8) % 10,
                (position * 9 + 2) % 10
            )
            add(realLlmCase(
                size + 1,
                "Formatting",
                "Sort these four digits from smallest to largest and concatenate them with no separators: " +
                    digits.joinToString(", "),
                digits.sorted().joinToString("")
            ))
        }
        for (position in 1..20) {
            val first = 3 + position
            val step = 2 + position % 5
            val values = List(4) { offset -> first + offset * step }
            add(realLlmCase(
                size + 1,
                "Reasoning",
                "Continue this arithmetic sequence by one term: ${values.joinToString(", ")}.",
                (values.last() + step).toString()
            ))
        }
    }.also { cases ->
        check(cases.size == EXPECTED_CASE_COUNT)
        check(cases.map(RealLlmCase::marker).distinct().size == EXPECTED_CASE_COUNT)
    }

    private fun realLlmCase(index: Int, category: String, instruction: String, expected: String) =
        RealLlmCase(
            index = index,
            category = category,
            instruction = instruction,
            expected = expected,
            marker = "SMT575_LLM_${index.toString().padStart(3, '0')}_OK"
        )

    private fun promptFor(testCase: RealLlmCase): String = """
        SignalASI SM-T575 language-model response check ${testCase.index} of $EXPECTED_CASE_COUNT.
        Question: ${testCase.instruction}
        Return exactly one line in this format: ${testCase.marker} | ANSWER
        Replace ANSWER with the result. Add nothing else.
    """.trimIndent()

    private fun buildSuiteReport(
        target: AgentCallableTarget,
        cases: List<RealLlmCase>,
        results: List<RealLlmCaseResult>,
        invocationCount: Int,
        suiteStartedAtMillis: Long,
        elapsedMillis: Long,
        complete: Boolean
    ): JSONObject {
        val ordered = results.sortedBy { it.testCase.index }
        return JSONObject()
            .put("device_model", Build.MODEL)
            .put("device_name", Build.DEVICE)
            .put("app_version_name", BuildConfig.VERSION_NAME)
            .put("app_version_code", BuildConfig.VERSION_CODE)
            .put("target_id", target.id)
            .put("target_title", target.title)
            .put("target_adapter_type", target.adapterType)
            .put("expected_case_count", cases.size)
            .put("result_count", ordered.size)
            .put("passed_count", ordered.count(RealLlmCaseResult::passed))
            .put("failed_count", ordered.count { !it.passed })
            .put("verified_real_reply_count", ordered.count(RealLlmCaseResult::passed))
            .put("invocation_count", invocationCount)
            .put("batch_size", BATCH_SIZE)
            .put("maximum_attempts", MAX_ATTEMPTS)
            .put("started_at_millis", suiteStartedAtMillis)
            .put("elapsed_ms", elapsedMillis)
            .put("complete", complete)
            .put("records", JSONArray().apply {
                ordered.forEach { result ->
                    put(JSONObject()
                        .put("index", result.testCase.index)
                        .put("category", result.testCase.category)
                        .put("marker", result.testCase.marker)
                        .put("expected", result.testCase.expected)
                        .put("conversation_id", result.conversationId)
                        .put("turn_id", result.turnId)
                        .put("attempt", result.attempt)
                        .put("latency_ms", result.latencyMillis)
                        .put("response", result.response.take(MAX_REPORT_RESPONSE_CHARACTERS))
                        .put("response_dedupe_key", result.responseDedupeKey)
                        .put("run_id", result.runId)
                        .put("run_status", result.runStatus)
                        .put("execution_resource_id", result.executionResourceId)
                        .put("process_entry_count", result.processEntryCount)
                        .put("passed", result.passed)
                        .put("failure", result.failure))
                }
            })
    }

    private fun writeReport(context: android.content.Context, filename: String, report: JSONObject) {
        val reportDirectory = File(context.filesDir, REPORT_DIRECTORY)
        check(reportDirectory.mkdirs() || reportDirectory.isDirectory)
        File(reportDirectory, filename).writeText(report.toString(2))
    }

    private data class RealLlmCase(
        val index: Int,
        val category: String,
        val instruction: String,
        val expected: String,
        val marker: String
    )

    private data class RealLlmCaseExecution(
        val testCase: RealLlmCase,
        val conversationId: String,
        val turnId: String,
        val attempt: Int,
        val startedAtElapsed: Long
    )

    private data class RealLlmCaseResult(
        val testCase: RealLlmCase,
        val conversationId: String,
        val turnId: String,
        val attempt: Int,
        val latencyMillis: Long,
        val response: String,
        val responseDedupeKey: String,
        val runId: String,
        val runStatus: String,
        val executionResourceId: String,
        val processEntryCount: Int,
        val passed: Boolean,
        val failure: String
    )

    private fun requireSmT575() {
        val normalizedModel = Build.MODEL.replace('_', '-').uppercase()
        check(normalizedModel == "SM-T575" && Build.DEVICE.equals("gtactive3", ignoreCase = true)) {
            "This real Agent/LLM reply suite may run only on SM-T575; " +
                "actual model=${Build.MODEL}, device=${Build.DEVICE}"
        }
    }

    private companion object {
        const val LOG_TAG = "SmT575AgentLlmTest"
        const val REPORT_DIRECTORY = "acceptance-reports"
        const val TARGET_REPORT_FILE = "sm-t575-agent-targets.json"
        const val SMOKE_REPORT_FILE = "sm-t575-agent-smoke.json"
        const val SMOKE_CONVERSATION_TITLE = "LLM Agent Acceptance 000 · Smoke"
        const val SUITE_REPORT_FILE = "sm-t575-agent-llm-100.json"
        const val ACCEPTANCE_CONVERSATION_PREFIX = "LLM Agent Acceptance "
        const val EXPECTED_CASE_COUNT = 100
        const val BATCH_SIZE = 5
        const val MAX_ATTEMPTS = 2
        const val SMOKE_TIMEOUT_MILLIS = 10L * 60L * 1_000L
        const val BATCH_TIMEOUT_MILLIS = 5L * 60L * 1_000L
        const val REPLY_POLL_MILLIS = 500L
        const val MAX_REPORT_RESPONSE_CHARACTERS = 2_000
    }
}
