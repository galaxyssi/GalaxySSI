package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentInteractiveProgressPolicyTest {
    @Test
    fun simpleChatKeepsTheDirectAnswerSurfaceUnchanged() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "你好",
            plan = null,
            phase = AgentPhase.COMPLETED,
            processTexts = listOf("正在生成回复"),
            completed = true
        )

        assertFalse(presentation.visible)
    }

    @Test
    fun structuredComplexPlanShowsTheCurrentStepAndCounter() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "实现 Android 功能并运行测试",
            plan = plan(
                action("inspect", "检查现有实现", AgentActionStatus.COMPLETED),
                action("implement", "实现规划进度 UI", AgentActionStatus.RUNNING),
                action("test", "运行 Android 测试", AgentActionStatus.PROPOSED)
            ),
            phase = AgentPhase.EXECUTING,
            processTexts = listOf("已经完成项目结构检查"),
            completed = false
        )

        assertTrue(presentation.visible)
        assertEquals("2/3", presentation.counter)
        assertEquals("实现规划进度 UI", presentation.summary)
        assertEquals(1, presentation.completedSteps)
        assertTrue(presentation.running)
    }

    @Test
    fun complexTaskDoesNotInventStepsBeforeTheModelPlanArrives() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "实现 Android 功能并运行测试",
            plan = null,
            phase = AgentPhase.PLANNING,
            processTexts = emptyList(),
            completed = false
        )

        assertFalse(presentation.visible)
    }

    @Test
    fun multilineModelPlanBecomesIndividualProgressSteps() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "深入分析这个复杂方案并给出验证结果",
            plan = null,
            phase = AgentPhase.PLANNING,
            processTexts = listOf(
                "1. 确认需求\n2. 对比实现\n3. 验证结论"
            ),
            completed = false
        )

        assertTrue(presentation.visible)
        assertEquals(listOf("确认需求", "对比实现", "验证结论"), presentation.steps.map { it.text })
        assertEquals("1/3", presentation.counter)
    }

    @Test
    fun completedNarrationReportsHistoryWithoutInventingVerifiedSteps() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "研究最新 Agent 方案并比较多个来源",
            plan = null,
            phase = AgentPhase.COMPLETED,
            processTexts = listOf("确定范围", "核对来源", "完成验证"),
            completed = true
        )

        assertTrue(presentation.visible)
        assertEquals("3/3", presentation.counter)
        assertEquals(0, presentation.completedSteps)
        assertTrue(presentation.steps.all { it.state == AgentInteractiveProgressStepState.RECORDED })
        assertEquals(AgentInteractiveProgressStatus.COMPLETED, presentation.status)
        assertFalse(presentation.running)
    }

    @Test
    fun oneStepSupervisedProjectStillExposesItsDurablePlan() {
        val supervised = plan(
            action("execute", "在手机上执行并验证", AgentActionStatus.WAITING_RESPONSE)
        ).copy(plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE)

        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "执行这个任务",
            plan = supervised,
            phase = AgentPhase.WAITING_RESPONSE,
            processTexts = emptyList(),
            completed = false
        )

        assertTrue(presentation.visible)
        assertEquals("1/1", presentation.counter)
    }

    @Test
    fun internalSingleConnectorIsShownWithoutInventingFiveUserFacingStages() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "实现 Android 功能并运行测试",
            plan = plan(
                action("delegate", "Ask Codex Agent", AgentActionStatus.WAITING_RESPONSE)
            ),
            phase = AgentPhase.WAITING_RESPONSE,
            processTexts = emptyList(),
            completed = false
        )

        assertEquals("1/1", presentation.counter)
        assertEquals(1, presentation.steps.size)
    }

    @Test
    fun rollingReplanKeepsCompletedBatchesAndMarksRecoveredFailure() {
        val previous = listOf(
            action("inspect", "检查项目结构", AgentActionStatus.COMPLETED),
            action("r2-1-build", "运行第一次构建", AgentActionStatus.FAILED)
        )
        val current = listOf(
            action("r3-1-repair", "修复构建配置", AgentActionStatus.COMPLETED),
            action("r3-2-test", "重新运行测试", AgentActionStatus.RUNNING),
            action("r3-3-publish", "提交发布结果", AgentActionStatus.PROPOSED)
        )
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "持续改进项目直到发布完成",
            plan = plan(*current.toTypedArray()).copy(
                revision = 3,
                replanCount = 2,
                actionHistory = previous,
                checkpoints = listOf(
                    AgentExecutionCheckpoint(
                        id = "checkpoint-inspect",
                        actionId = "inspect",
                        planRevision = 1,
                        foregroundApp = "GalaxySSI",
                        activityName = "MainActivity",
                        pageTitle = "Agent",
                        screenDigest = "verified"
                    )
                )
            ),
            phase = AgentPhase.EXECUTING,
            processTexts = listOf("构建失败，已改用兼容配置"),
            completed = false
        )

        assertEquals(listOf(1, 2, 3), presentation.batches.map { it.planRevision })
        assertEquals(5, presentation.steps.size)
        assertEquals(
            AgentInteractiveProgressStepState.SUPERSEDED,
            presentation.steps.first { it.actionId == "r2-1-build" }.state
        )
        assertEquals("2/3", presentation.counter)
        assertEquals(3, presentation.planRevision)
        assertEquals("重新运行测试", presentation.summary)
    }

    @Test
    fun repeatedDescriptionsInDifferentPlanRevisionsRemainVisible() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "持续验证项目",
            plan = plan(
                action("r2-1-test", "运行测试", AgentActionStatus.RUNNING)
            ).copy(
                revision = 2,
                actionHistory = listOf(
                    action("initial-test", "运行测试", AgentActionStatus.COMPLETED)
                )
            ),
            phase = AgentPhase.EXECUTING,
            processTexts = emptyList(),
            completed = false
        )

        assertEquals(2, presentation.steps.size)
        assertEquals(listOf(1, 2), presentation.batches.map { it.planRevision })
    }

    @Test
    fun completedTaskStopsStaleRunningStepsWithoutClaimingTheirSuccess() {
        val presentation = projectPhase(AgentPhase.COMPLETED)
        assertEquals(AgentInteractiveProgressStatus.COMPLETED, presentation.status)
        assertFalse(presentation.running)
        assertEquals(1, presentation.completedSteps)
        assertEquals(AgentInteractiveProgressStepState.RECORDED, presentation.steps[1].state)
        assertEquals(AgentInteractiveProgressStepState.NOT_EXECUTED, presentation.steps[2].state)
    }

    @Test
    fun pausedTaskStopsAnimationAndRetainsResumeAction() {
        val presentation = projectPhase(AgentPhase.PAUSED)
        assertEquals(AgentInteractiveProgressStatus.PAUSED, presentation.status)
        assertFalse(presentation.running)
        assertEquals(AgentInteractiveProgressStepState.PAUSED, presentation.steps[1].state)
        assertTrue(AgentExecutionLoopTimelineAction.RESUME in
            AgentExecutionLoopTimelinePolicy.actionsForPhase(AgentPhase.PAUSED))
    }

    @Test
    fun waitingForConfirmationIsNotActiveExecution() {
        val presentation = projectPhase(AgentPhase.WAITING_CONFIRMATION)
        assertEquals(AgentInteractiveProgressStatus.WAITING_CONFIRMATION, presentation.status)
        assertFalse(presentation.running)
        assertEquals(AgentInteractiveProgressStepState.WAITING, presentation.steps[1].state)
    }

    @Test
    fun waitingForResponseRemainsLiveButIsNotLabeledActiveWork() {
        val presentation = projectPhase(AgentPhase.WAITING_RESPONSE)
        assertEquals(AgentInteractiveProgressStatus.WAITING_RESPONSE, presentation.status)
        assertTrue(presentation.running)
        assertEquals(AgentInteractiveProgressStepState.WAITING, presentation.steps[1].state)
        assertEquals("2/3", presentation.counter)
    }

    @Test
    fun failedTaskDoesNotConvertStaleRunningActionIntoSuccess() {
        val presentation = projectPhase(AgentPhase.FAILED, completed = true)
        assertEquals(AgentInteractiveProgressStatus.FAILED, presentation.status)
        assertFalse(presentation.running)
        assertEquals(AgentInteractiveProgressStepState.STOPPED, presentation.steps[1].state)
        assertEquals(1, presentation.completedSteps)
    }

    @Test
    fun cancelledTaskIsNotDisplayedAsCompleted() {
        val presentation = projectPhase(AgentPhase.CANCELLED, completed = true)
        assertEquals(AgentInteractiveProgressStatus.CANCELLED, presentation.status)
        assertFalse(presentation.running)
        assertEquals(AgentInteractiveProgressStepState.STOPPED, presentation.steps[1].state)
    }

    @Test
    fun blockedTaskRetainsReplanningWithoutActiveAnimation() {
        val presentation = projectPhase(AgentPhase.BLOCKED, completed = true)
        assertEquals(AgentInteractiveProgressStatus.BLOCKED, presentation.status)
        assertFalse(presentation.running)
        assertEquals(AgentInteractiveProgressStepState.WAITING, presentation.steps[1].state)
        assertTrue(AgentExecutionLoopTimelineAction.REPLAN in
            AgentExecutionLoopTimelinePolicy.actionsForPhase(AgentPhase.BLOCKED))
    }

    @Test
    fun activeRuntimeOverridesAnOlderCompletionTimestamp() {
        for (phase in listOf(AgentPhase.PLANNING, AgentPhase.EXECUTING, AgentPhase.OBSERVING, AgentPhase.VERIFYING)) {
            val presentation = projectPhase(phase, completed = true)
            assertEquals(AgentInteractiveProgressStatus.RUNNING, presentation.status)
            assertTrue(presentation.running)
            assertEquals(AgentInteractiveProgressStepState.ACTIVE, presentation.steps[1].state)
        }
    }

    @Test
    fun missingRuntimeUsesCompletionHintWithoutInventingOngoingExecution() {
        assertEquals(AgentInteractiveProgressStatus.COMPLETED, projectPhase(null, completed = true).status)
        val unknown = projectPhase(null)
        assertEquals(AgentInteractiveProgressStatus.UNKNOWN, unknown.status)
        assertFalse(unknown.running)
        assertEquals(AgentInteractiveProgressStepState.RECORDED, unknown.steps[1].state)
    }

    @Test
    fun staleCachedWaitingCannotRestartAnAlreadyFinishedHistoryRow() {
        val presentation = projectFallback(AgentPhase.WAITING_RESPONSE)
        assertEquals(AgentInteractiveProgressStatus.COMPLETED, presentation.status)
        assertFalse(presentation.running)
    }

    @Test
    fun cachedTerminalAndPausedStatesAreNotReplacedByGenericCompletion() {
        for (phase in listOf(AgentPhase.FAILED, AgentPhase.CANCELLED, AgentPhase.PAUSED, AgentPhase.BLOCKED)) {
            assertEquals(AgentInteractiveProgressStatus.from(phase, false), projectFallback(phase).status)
        }
    }

    @Test
    fun liveRuntimeStillOverridesCompletedHistoryAndCachedFailure() {
        val presentation = projectFallback(AgentPhase.FAILED, AgentPhase.EXECUTING)
        assertEquals(AgentInteractiveProgressStatus.RUNNING, presentation.status)
        assertTrue(presentation.running)
    }

    private fun projectFallback(fallback: AgentPhase, livePhase: AgentPhase? = null) =
        AgentInteractiveProgressPolicy.project(
            goal = "Inspect and verify",
            plan = plan(
                action("read", "Read", AgentActionStatus.COMPLETED),
                action("verify", "Verify", AgentActionStatus.WAITING_RESPONSE)
            ),
            phase = livePhase,
            processTexts = emptyList(),
            completed = true,
            fallbackPhase = fallback
        )

    @Test
    fun retiredRunningActionCannotRemainActiveOrSupplyTheSummary() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "Continue validation",
            plan = plan(action("r2-current", "Current verification", AgentActionStatus.RUNNING)).copy(
                revision = 2,
                actionHistory = listOf(action("r1-old", "Obsolete work", AgentActionStatus.RUNNING)),
                plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
            ),
            phase = AgentPhase.VERIFYING,
            processTexts = emptyList(),
            completed = false
        )
        assertEquals(AgentInteractiveProgressStepState.SUPERSEDED, presentation.steps[0].state)
        assertEquals("Current verification", presentation.summary)
    }

    @Test
    fun terminalNarrationCannotProveTheDeclaredPlanWasExecuted() {
        for (phase in listOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED)) {
            val presentation = AgentInteractiveProgressPolicy.project(
                goal = "Implement and verify a feature",
                plan = null,
                phase = phase,
                processTexts = listOf("1. Inspect\n2. Implement\n3. Verify"),
                completed = true
            )
            assertFalse(presentation.running)
            assertEquals(0, presentation.completedSteps)
            assertTrue(presentation.steps.none { it.state == AgentInteractiveProgressStepState.ACTIVE })
            assertEquals(AgentInteractiveProgressStepState.NOT_EXECUTED, presentation.steps.last().state)
        }
    }

    @Test
    fun identicalSnapshotsRestoreTheSamePresentationWithoutWallClockState() {
        val before = projectPhase(AgentPhase.COMPLETED)
        val restored = projectPhase(AgentPhase.COMPLETED)
        assertEquals(before, restored)
        assertFalse(restored.running)
    }

    private fun projectPhase(phase: AgentPhase?, completed: Boolean = false) =
        AgentInteractiveProgressPolicy.project(
            goal = "Inspect, act and verify",
            plan = plan(
                action("observed", "Read current state", AgentActionStatus.COMPLETED),
                action("current", "Verify result", AgentActionStatus.RUNNING),
                action("pending", "Prepare evidence", AgentActionStatus.PROPOSED)
            ),
            phase = phase,
            processTexts = emptyList(),
            completed = completed
        )

    private fun plan(vararg actions: AgentAction) = AgentPlan(
        goal = "goal",
        screen = ScreenContext(foregroundApp = "", pageTitle = ""),
        steps = emptyList(),
        actions = actions.toList(),
        confirmationRequired = false
    )

    private fun action(
        id: String,
        description: String,
        status: AgentActionStatus
    ) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = "galaxyssi-mobile",
        risk = AgentRisk.LOW,
        status = status,
        description = description,
        requiresConfirmation = false
    )
}
