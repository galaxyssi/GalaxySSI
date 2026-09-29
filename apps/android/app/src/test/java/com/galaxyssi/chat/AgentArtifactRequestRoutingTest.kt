package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentArtifactRequestRoutingTest {
    @Test fun deliverablesWithNegativeCodeMentionsDoNotStartPhoneDevelopment() {
        val requests = listOf(
            "生成可编辑的 DOCX 门店手册。数据：{\"项目\":\"甲\",\"数量\":11}。不能只给本机路径、代码或制作方法。",
            "生成 XLSX 和 PNG 预览，使用公式，不要只返回代码。",
            "在原图上批改，只交付图片，不能只给本机路径或代码。",
            "Create a DOCX report. Do not return code or a local path.",
            "Generate a PPTX file, don't just give Python code."
        )
        requests.forEach { goal ->
            assertFalse(goal, AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime(goal))
            assertFalse(goal, AgentCapability.TASK_EXECUTION in AgentTaskRequirementAnalyzer.analyze(goal).capabilities)
            assertFalse(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
    }

    @Test fun affirmativeCodeInstructionsAfterAConstraintStillExecute() {
        val requests = listOf(
            "不要只给路径，编写并运行 Python 脚本。",
            "Do not write a report; create and run Python code.",
            "Create an Android project and run unit tests",
            "编译这个项目"
        )
        requests.forEach { goal ->
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
    }

    @Test fun quotedBusinessFieldDoesNotBecomeProjectScope() {
        assertEquals(AgentPhoneDevelopmentMode.NONE,
            AgentPhoneDevelopmentPolicy.mode("生成报表，数据是{\"项目\":\"甲\"}"))
        assertTrue(AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime("创建项目并编译 APK"))
    }

    @Test fun exclusionsDoNotSuppressLaterPositiveOccurrences() {
        assertFalse(AgentCodeKeywordPolicy.contains("不要只给本机路径、代码或制作方法", "代码"))
        assertTrue(AgentCodeKeywordPolicy.contains("不要输出代码。运行代码来验证结果", "代码"))
        assertTrue(AgentCodeKeywordPolicy.contains("not only write code but also run tests", "code"))
    }
}
