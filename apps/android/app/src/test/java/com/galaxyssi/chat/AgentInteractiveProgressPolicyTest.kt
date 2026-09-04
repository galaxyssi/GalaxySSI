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
    fun completedNarrationPlanReportsTheFinalStep() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "研究最新 Agent 方案并比较多个来源",
            plan = null,
            phase = AgentPhase.COMPLETED,
            processTexts = listOf("确定范围", "核对来源", "完成验证"),
            completed = true
        )

        assertTrue(presentation.visible)
        assertEquals("3/3", presentation.counter)
        assertEquals(3, presentation.completedSteps)
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
