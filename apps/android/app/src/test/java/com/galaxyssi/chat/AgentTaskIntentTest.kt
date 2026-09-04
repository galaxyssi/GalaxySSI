package com.galaxyssi.chat

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
    fun frequencyDescriptionsDoNotBecomeAutomationTasks() {
        val goals = listOf(
            "\u4e3a\u6bcf\u5929\u53ea\u6709\u4e8c\u5341\u5206\u949f\u7684\u4eba\u5236\u5b9a\u4e00\u5468\u7684\u82f1\u8bed\u542c\u529b\u7ec3\u4e60\u8ba1\u5212\uff0c\u8981\u6c42\u53ef\u6267\u884c\u3002",
            "\u6bcf\u5929\u4e00\u676f\u5496\u5561\u662f\u5426\u8fc7\u91cf\uff1f",
            "Compare studying every day with studying every week.",
            "\u6bcf\u5929\u8fd0\u884c\u4e00\u6b21\u6a21\u578b\u4f1a\u8017\u591a\u5c11\u7535\uff1f"
        )

        goals.forEach { goal ->
            assertEquals(goal, AgentTaskIntent.CHAT, AgentTaskIntentClassifier.classify(goal).intent)
            assertFalse(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun frequencyCombinedWithAnActionStillCreatesAutomation() {
        val goals = listOf(
            "Run this health check every hour",
            "\u6bcf\u5929\u76d1\u63a7\u8fd9\u4e2a\u670d\u52a1",
            "\u6bcf\u5468\u5907\u4efd\u8fd9\u4e2a\u6587\u4ef6\u5939"
        )

        goals.forEach { goal ->
            assertEquals(goal, AgentTaskIntent.AUTOMATION, AgentTaskIntentClassifier.classify(goal).intent)
        }
    }

    @Test
    fun automationConceptsDoNotBecomeExecutionRequests() {
        val goals = listOf(
            "\u5217\u51fa\u4e00\u6b21\u79fb\u52a8\u5e94\u7528\u53d1\u5e03\u7684\u6700\u5c0f\u56de\u6eda\u6d41\u7a0b\uff0c\u5305\u542b\u89e6\u53d1\u6761\u4ef6\u548c\u9a8c\u8bc1\u3002",
            "\u89e3\u91ca\u8fd9\u4e2a\u5de5\u4f5c\u6d41\u7684\u89e6\u53d1\u6761\u4ef6",
            "\u6bd4\u8f83\u4e24\u79cd\u5b9a\u65f6\u7b56\u7565",
            "What trigger conditions should a rollback workflow use?",
            "\u81ea\u52a8\u5316\u7684\u4f18\u52bf\u4e0e\u9650\u5236",
            "Cron syntax reference"
        )

        goals.forEach { goal ->
            assertEquals(goal, AgentTaskIntent.CHAT, AgentTaskIntentClassifier.classify(goal).intent)
            assertFalse(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun explicitAutomationCommandsStillCreateAutomation() {
        val goals = listOf(
            "Create a workflow that sends a message when this happens",
            "Remind me to stretch",
            "\u8bbe\u7f6e\u4e00\u4e2a\u89e6\u53d1\u5668\uff0c\u6536\u5230\u6d88\u606f\u65f6\u6267\u884c\u5907\u4efd",
            "\u5b9a\u65f6\u5907\u4efd\u8fd9\u4e2a\u6587\u4ef6\u5939"
        )

        goals.forEach { goal ->
            assertEquals(goal, AgentTaskIntent.AUTOMATION, AgentTaskIntentClassifier.classify(goal).intent)
        }
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
        val result = AgentTaskIntentClassifier.classify("在这部手机上打开微信")

        assertEquals(
            AgentTaskIntent.PHONE_CONTROL,
            result.intent
        )
        assertTrue("phone-control-action" in result.matchedSignals)
        assertTrue(
            AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(
                "在这部手机上打开微信"
            )
        )
    }

    @Test
    fun phoneContextInAdviceDoesNotStartPhoneExecution() {
        val goals = listOf(
            "手机只剩10%电量但还要传重要文件，给出兼顾完成任务和省电的计划。",
            "比较低电量时 Wi-Fi 和蓝牙传文件的优缺点。",
            "解释手机电量与电池寿命的关系。",
            "Give me a plan for transferring a file when the phone battery is low.",
            "Describe how battery saver affects file transfers."
        )

        goals.forEach { goal ->
            assertFalse(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
    }

    @Test
    fun explicitPhoneStateAndControlRequestsStillExecute() {
        val goals = listOf(
            "读取当前电量",
            "打开手机手电筒",
            "Check battery saver status",
            "What is the battery level?",
            "Turn down the phone volume"
        )

        goals.forEach { goal ->
            val result = AgentTaskIntentClassifier.classify(goal)
            assertEquals(goal, AgentTaskIntent.PHONE_CONTROL, result.intent)
            assertTrue(goal, "phone-control-action" in result.matchedSignals)
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
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
