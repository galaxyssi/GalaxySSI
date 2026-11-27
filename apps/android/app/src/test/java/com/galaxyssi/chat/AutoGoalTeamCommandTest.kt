package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AutoGoalTeamCommandTest {
    private fun starts(vararg turns: String) = turns.forEach { turn ->
        assertEquals(turn, AutoGoalTeamCommand.Start(turn), AutoGoalTeamCommand.parse(turn))
    }

    private fun staysInChat(vararg turns: String) = turns.forEach { turn ->
        assertNull(turn, AutoGoalTeamCommand.parse(turn))
    }

    @Test fun slashCommandTakesOneVerbatimObjectiveNotRoleOrCountArguments() {
        val objective = "Compare A and B.\nKeep their assumptions separate."
        assertEquals(AutoGoalTeamCommand.Start(objective), AutoGoalTeamCommand.parse("  /TEAM  $objective  "))
        assertEquals(AutoGoalTeamCommand.Help, AutoGoalTeamCommand.parse("/team"))
        assertEquals(AutoGoalTeamCommand.Help, AutoGoalTeamCommand.parse("/team 帮助"))
        staysInChat("/teams A", "/teamwork A", "/goal have a team review this", "Please explain /team.")
    }

    @Test fun requestsMayFollowTheirObjectivesAndNeedNoExplicitTeamSize() {
        starts(
            "Have a team compare these two arguments and have someone challenge the conclusion.",
            "For this proposal please have multiple agents independently review the assumptions.",
            "Compare A and B. I’d like an independent review of the conclusion.",
            "Could you analyze the alternatives as a team?",
            "关于这个方案，请自动组队比较收益和成本。",
            "方案 A 成本较低。请让多个智能体从不同角度分析这个取舍。",
            "初稿在下面，帮我组个临时团队审阅。"
        )
    }

    @Test fun perspectivesPlusIndependentReviewNeedsNoTeamKeyword() {
        starts("从证据和可行性两个角度分析这个方案，再独立审核结论")
        staysInChat(
            "从证据和可行性两个角度分析这个方案",
            "从两个角度分析，再总结结论。",
            "Analyze the proposal from two perspectives and summarize your conclusion.",
            "Please review this draft.",
            "请独立完成这篇摘要。"
        )
    }

    @Test fun discussionQuotationsNegationAndHealthQuestionsAreNotCommands() {
        staysInChat(
            "What is a multi-agent team and how does it work?",
            "Can you explain how to have a team review a proposal?",
            "An independent review found two issues.",
            "为什么要让多个智能体协作？",
            "多智能体协作有哪些优点？",
            "请解释：什么是独立评审？",
            "Translate “please have a team review the plan” into Chinese.",
            "原文是「请自动组队审核方案」，翻译成英文。",
            "The example is `/team stop`.",
            "Don't use a team. Please review the draft.",
            "请不要组队，也不用安排独立审核。",
            "What do blood pressure numbers mean?",
            "为什么需要定期体检？",
            "帮我看看上次的化验结果。"
        )
    }

    @Test fun stopOnlyWhenTheWholeTurnStopsATeam() {
        listOf("/team STOP", "/team 停止", "Please stop the team run.", "Cancel this temporary team!",
            "停止这次团队协作", "请取消当前的临时团队任务。", "终止多智能体协作").forEach {
            assertEquals(it, AutoGoalTeamCommand.Stop, AutoGoalTeamCommand.parse(it))
        }
        staysInChat("stop", "停止", "Stop the timer.", "How do I stop the team?",
            "Stop the team from changing the draft.", "不要停止团队协作。", "请停止音乐。")
        assertEquals(AutoGoalTeamCommand.Start("stop the leak"), AutoGoalTeamCommand.parse("/team stop the leak"))
    }

    @Test fun refuseOversizeOrRecognizablyPrivateObjectiveRatherThanTruncatingOrEchoingIt() {
        val limit = "x".repeat(4000)
        assertEquals(AutoGoalTeamCommand.Start(limit), AutoGoalTeamCommand.parse("/team $limit"))
        assertEquals(AutoGoalTeamCommand.TooLong, AutoGoalTeamCommand.parse("/team ${limit}x"))
        assertEquals(AutoGoalTeamCommand.TooLong, AutoGoalTeamCommand.parse("Please independently review: $limit"))
        listOf("/team Compare my medical records.", "请让多个智能体分析我的化验结果。",
            "/team Review this: blood pressure 130/85").forEach {
            assertEquals(it, AutoGoalTeamCommand.PrivateObjective, AutoGoalTeamCommand.parse(it))
        }
    }
}
