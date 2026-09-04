package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentGoalSegmentationPolicyTest {
    @Test
    fun multilinePromptAndSemicolonRemainOneGoal() {
        val goal = """
            给离线手机智能体写标题和副标题。
            回复必须包含指定标记；不要解释标记用途。
            内容还必须包含“离线”或“手机”。
        """.trimIndent()

        assertEquals(listOf(goal), AgentGoalSegmentationPolicy.split(goal))
    }

    @Test
    fun explicitEnglishSequenceCreatesOrderedGoals() {
        assertEquals(
            listOf("Read the current battery", "report the result"),
            AgentGoalSegmentationPolicy.split(
                "Read the current battery and then report the result"
            )
        )
    }

    @Test
    fun explicitChineseSequenceCreatesOrderedGoals() {
        assertEquals(
            listOf("读取当前电量", "把结果告诉我", "记录到任务里"),
            AgentGoalSegmentationPolicy.split(
                "读取当前电量，然后把结果告诉我，接着记录到任务里"
            )
        )
    }
}
