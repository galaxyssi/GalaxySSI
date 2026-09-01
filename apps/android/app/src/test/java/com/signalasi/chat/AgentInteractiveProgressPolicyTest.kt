package com.signalasi.chat

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
    fun complexTaskShowsImmediateFiveStepAcknowledgementBeforeThePlanArrives() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "实现 Android 功能并运行测试",
            plan = null,
            phase = AgentPhase.PLANNING,
            processTexts = emptyList(),
            completed = false,
            fallbackSteps = listOf("确认任务", "制定计划", "执行", "验证", "完成")
        )

        assertTrue(presentation.visible)
        assertEquals("1/5", presentation.counter)
        assertEquals("确认任务", presentation.summary)
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
    fun internalSingleConnectorDoesNotReplaceTheFiveUserFacingStages() {
        val presentation = AgentInteractiveProgressPolicy.project(
            goal = "实现 Android 功能并运行测试",
            plan = plan(
                action("delegate", "Ask Codex Agent", AgentActionStatus.WAITING_RESPONSE)
            ),
            phase = AgentPhase.WAITING_RESPONSE,
            processTexts = emptyList(),
            completed = false,
            fallbackSteps = listOf("确认任务", "制定计划", "执行", "验证", "完成")
        )

        assertEquals("1/5", presentation.counter)
        assertEquals(5, presentation.steps.size)
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
        target = "signalasi-mobile",
        risk = AgentRisk.LOW,
        status = status,
        description = description,
        requiresConfirmation = false
    )
}
