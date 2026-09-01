package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskIntentTest {
    @Test
    fun classifiesTheEightCanonicalTaskIntents() {
        val cases = listOf(
            "Hello, how are you?" to AgentTaskIntent.CHAT,
            "Build an Android app and run unit tests" to AgentTaskIntent.CODE,
            "Turn on the flashlight on my phone" to AgentTaskIntent.PHONE_CONTROL,
            "Open the browser on my computer" to AgentTaskIntent.DESKTOP_CONTROL,
            "Research today's AI news and cite sources" to AgentTaskIntent.RESEARCH,
            "Extract text from this PDF" to AgentTaskIntent.FILE,
            "Remember that I prefer concise replies" to AgentTaskIntent.MEMORY,
            "Run this health check every hour" to AgentTaskIntent.AUTOMATION
        )

        cases.forEach { (goal, expected) ->
            val result = AgentTaskIntentClassifier.classify(goal)
            assertEquals(goal, expected, result.intent)
            assertTrue(goal, result.confidence >= 55)
        }
    }

    @Test
    fun anAttachmentIsAFileTaskWithoutExtraText() {
        val result = AgentTaskIntentClassifier.classify("", hasAttachments = true)

        assertEquals(AgentTaskIntent.FILE, result.intent)
        assertTrue("attachment" in result.matchedSignals)
    }

    @Test
    fun desktopLocationAtTheEndStillSelectsDesktopControl() {
        assertEquals(
            AgentTaskIntent.DESKTOP_CONTROL,
            AgentTaskIntentClassifier.classify("Open WeChat on desktop").intent
        )
    }

    @Test
    fun imageUnderstandingDoesNotBecomeAProjectExecutionTask() {
        val goals = listOf(
            "Describe the image precisely.",
            "\u8be6\u7ec6\u63cf\u8ff0\u8fd9\u5f20\u56fe\u7247",
            "\u6279\u6539\u8fd9\u5f20\u4f5c\u4e1a"
        )

        goals.forEach { goal ->
            assertEquals(AgentTaskIntent.FILE, AgentTaskIntentClassifier.classify(goal, true).intent)
            assertTrue(
                goal,
                !AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal, true)
            )
        }
    }

    @Test
    fun classifiesAConcretePathMutationAsAFileExecutionTask() {
        val result = AgentTaskIntentClassifier.classify(
            "Create docs/model_reasoning_probe.txt, read it back, and verify it"
        )

        assertEquals(AgentTaskIntent.FILE, result.intent)
        assertTrue("file-path-operation" in result.matchedSignals)
    }

    @Test
    fun recognizesThisPhoneAsAnExplicitPhoneExecutionContext() {
        val result = AgentTaskIntentClassifier.classify(
            "On this phone, create docs/probe.txt and verify it"
        )

        assertEquals(AgentTaskIntent.FILE, result.intent)
        assertTrue(result.matchedSignals.isNotEmpty())
    }

    @Test
    fun classifiesChineseTaskIntentsWithoutChangingTheProtocolValues() {
        val cases = listOf(
            "\u4f60\u597d" to AgentTaskIntent.CHAT,
            "\u7f16\u8bd1\u8fd9\u4e2a\u9879\u76ee" to AgentTaskIntent.CODE,
            "\u6253\u5f00\u624b\u673a\u624b\u7535\u7b52" to AgentTaskIntent.PHONE_CONTROL,
            "\u63a7\u5236\u7535\u8111\u6253\u5f00\u6d4f\u89c8\u5668" to
                AgentTaskIntent.DESKTOP_CONTROL,
            "\u641c\u7d22\u4eca\u5929\u7684\u65b0\u95fb" to AgentTaskIntent.RESEARCH,
            "\u63d0\u53d6\u8fd9\u4e2a PDF \u6587\u4ef6\u7684\u6587\u5b57" to
                AgentTaskIntent.FILE,
            "\u8bb0\u4f4f\u6211\u7684\u504f\u597d" to AgentTaskIntent.MEMORY,
            "\u6bcf\u5929\u76d1\u63a7\u8fd9\u4e2a\u670d\u52a1" to AgentTaskIntent.AUTOMATION
        )

        cases.forEach { (goal, expected) ->
            assertEquals(expected, AgentTaskIntentClassifier.classify(goal).intent)
        }
    }

    @Test
    fun automationWinsOverTheIndividualPhoneAction() {
        val result = AgentTaskIntentClassifier.classify(
            "Turn on the phone flashlight every day at 8"
        )

        assertEquals(AgentTaskIntent.AUTOMATION, result.intent)
    }

    @Test
    fun genericOpenAppDoesNotInventAPhoneExecutionLocation() {
        val result = AgentTaskIntentClassifier.classify(
            "Open the app and show me its status"
        )

        assertEquals(AgentTaskIntent.CHAT, result.intent)
    }

    @Test
    fun mentioningAPhoneTopicDoesNotBecomePhoneControl() {
        val goal = """
            给“离线也能工作的手机智能体”写一个不超过十二个汉字的标题和一句副标题。
            回复中必须原样包含标记 SMG-004。
        """.trimIndent()

        assertEquals(AgentTaskIntent.CHAT, AgentTaskIntentClassifier.classify(goal).intent)
        assertFalse(AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
    }

    @Test
    fun reasoningAboutLocalModelExecutionDoesNotControlThePhone() {
        val goal = """
            已知所有离线模型都在本机运行，模型A是离线模型。
            给出能否推出模型A在本机运行及理由。
        """.trimIndent()

        assertEquals(AgentTaskIntent.CHAT, AgentTaskIntentClassifier.classify(goal).intent)
        assertFalse(AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
    }

    @Test
    fun explicitPhoneAppLaunchStillSelectsPhoneControl() {
        assertEquals(
            AgentTaskIntent.PHONE_CONTROL,
            AgentTaskIntentClassifier.classify("在这部手机上打开微信").intent
        )
    }

    @Test
    fun executionSnapshotPersistsIntent() {
        val profile = AgentExecutionProfile.forGoal(
            "Control the browser on my computer"
        )
        val loop = AgentExecutionLoop.create { 1_000L }
        val started = loop.start("desktop-control", AgentExecutionLoopBudget(), profile)

        val restored = AgentExecutionLoopJsonCodec.decode(
            AgentExecutionLoopJsonCodec.encode(started.snapshot)
        )

        assertEquals(AgentTaskIntent.DESKTOP_CONTROL, restored?.taskIntent)
        assertEquals(started.snapshot.taskIntentConfidence, restored?.taskIntentConfidence)
        assertEquals(started.snapshot.taskIntentSignals, restored?.taskIntentSignals)
    }
}
