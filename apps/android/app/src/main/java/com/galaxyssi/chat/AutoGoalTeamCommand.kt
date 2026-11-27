package com.galaxyssi.chat

internal sealed interface AutoGoalTeamCommand {
    data class Start(val objective: String) : AutoGoalTeamCommand
    data object Stop : AutoGoalTeamCommand
    data object Help : AutoGoalTeamCommand
    data object TooLong : AutoGoalTeamCommand
    data object PrivateObjective : AutoGoalTeamCommand

    companion object {
        private const val LIMIT = 4000
        private val slash = Regex("""^/team(?:\s+([\s\S]*))?$""", RegexOption.IGNORE_CASE)
        private val stopEn = Regex("""(?i)(?:(?:could|can|would|will) you )?(?:please )?(?:stop|cancel|end) (?:the |this |my |our |current )*(?:(?:temporary |agent |auto )?team(?: run| task| collaboration)?|multi-agent run)(?: please)?[.!?]*""")
        private val stopZh = Regex("""(?:请|麻烦)?(?:帮我)?(?:停止|取消|结束|终止)(?:这次|本次|当前|这个)?(?:的)?(?:(?:临时|自动|智能体|多智能体)?(?:团队|小组|组队)(?:协作|合作|任务|运行)?|多智能体协作)(?:吧)?[。！!]*""")

        // Inspect speech acts, not topic keywords. Quoted instructions are evidence, not consent.
        private val quoted = Regex("""(?s)```.*?(?:```|$)|`[^`]*(?:`|$)|"[^"]*(?:"|$)|“[^”]*(?:”|$)|「[^」]*(?:」|$)|‘[^’]*(?:’|$)|(?<!\w)'[^'\n]+'(?!\w)""")
        private val separator = Regex("""[,，。.!！？?;；\n]+""")
        private val noDelegation = Regex(
            """(?i)\b(?:do not|don't|don’t|not to|never|without|no need to|no)\s+(?:(?:do|use|using|form|forming|ask|asking|have|having|need|want|get|an?|the|any|to)\s+){0,4}(?:team|agents?|multiple agents|multi-agent|delegat\w*|independent(?:ly)?)\b""" +
                """|(?:不要|不用|无需|不必|别|禁止|不需要)(?:再|你|让|用|请|找|安排|进行|自动|临时|多个|几个|一个|任何){0,5}(?:组队|组建|组织|团队|小组|智能体|多智能体|独立|分工)"""
        )
        private val meta = Regex(
            """(?i)^(?:(?:please |can you |could you )?(?:explain|translate|define|describe|tell me (?:about|how|what|why))\b|(?:what|why|how|when|where|should|does|is it|do (?:i|we))\b)""" +
                """|(?:什么是|是什么意思|是什么|有什么|有哪些|怎么样|好不好|有用吗|如何|怎么|为什么|能否介绍|请问|^(?:请|帮我)?(?:解释|介绍|翻译|举例))"""
        )
        private const val TEAM_EN = """(?:a |an |the )?(?:(?:temporary|agent|small|multi-agent) )?team\b"""
        private const val AGENTS_EN = """(?:multiple|several|different|independent|two or more) agents\b"""
        private const val REVIEW_EN = """(?:an? |some )?independent (?:review|assessment|critique|check)\b"""
        private const val INVITE_EN = """(?:have|ask|let|use|get|assemble|form|create|organize|bring together)"""
        private const val WORK_EN = """(?:work|help|review|check|assess|analy[sz]e|compare|evaluate|draft|plan|research|solve|use|challenge|collaborate|investigate|design|write|tackle|brainstorm)"""
        private const val WANT_EN = """\b(?:i|we)(?: need| want| would like|['’]d like) """
        private val requestEn = Regex(
            """(?i)(?:^|\bplease\s+|\b(?:can|could|would|will) you\s+|${WANT_EN}you to |\b(?:and|then)\s+)(?:please\s+)?(?:""" +
                """$INVITE_EN (?:$TEAM_EN|$AGENTS_EN)(?: (?:of agents )?(?:to )?(?:(?:independently|jointly) )?$WORK_EN\b| (?:for|on) (?:this|the following)\b|\s*$)""" +
                """|(?:work|collaborate) (?:together )?as $TEAM_EN|team up\b""" +
                """|(?:give me |provide |do |run |conduct |arrange |request |seek |get (?:me )?)$REVIEW_EN|independently (?:review|assess|check|critique|verify)\b)""" +
                """|$WANT_EN(?:$REVIEW_EN|(?:$TEAM_EN|$AGENTS_EN) to $WORK_EN\b)"""
        )
        private const val TEAM_ZH = """(?:临时|自动|智能体|多智能体)?(?:团队|小组)"""
        private const val AGENTS_ZH = """(?:多(?:个|名|位)?|几个|几名|不同(?:的)?)(?:智能体|助手|[Aa]gent)"""
        private const val ASK_ZH = """(?:请(?:你|帮我)?|麻烦你?|帮我|我希望|我需要|我想请你|希望你|需要你|能不能|能否|可以)"""
        private const val JOINT_ZH = """(?:一起|协作|合作|分工)"""
        private val requestZh = Regex(
            """(?:^|$ASK_ZH|再|然后)(?:帮我)?(?:自动)?(?:组(?:个|一?个临时)?队|""" +
                """(?:组建|组织|组|建|成立|组个|拉个)(?:一个|一支|个)?$TEAM_ZH(?!建设)|""" +
                """(?:让|找|请|用|由|安排|组织)(?:一个|一支|个)?(?:$TEAM_ZH|$AGENTS_ZH)(?:来|帮我|$JOINT_ZH|从不同角度|分别|独立|评审|分析|审查|比较)|""" +
                """(?:做(?:一次|个)?|进行|安排)?独立(?:复核|复审|审核|审查|评审|审阅|检查|验证)(?!的|是))""" +
                """|$ASK_ZH(?:$TEAM_ZH|$AGENTS_ZH)$JOINT_ZH"""
        )
        private val withTeamEn = Regex("""(?i)^(?:(?:can|could|would) you )?(?:please )?(?:review|compare|assess|evaluate|draft|analy[sz]e|solve|research|design)\b.+?\s(?:as (?:a |an )?(?:agent )?team|with (?:a team of agents|$AGENTS_EN))\b""")

        // Refuse obvious private source material locally; never echo it in a notice.
        private val personalHealth = Regex(
            """(?i)\b(?:my|our|patient['’]s)\s+(?:(?:latest|last|recent|personal)\s+){0,2}(?:health records?|medical records?|lab results?|blood (?:pressure|sugar|tests?)|diagnosis|prescriptions?|symptoms?)\b""" +
                """|(?:我的?|患者的?|病人的?)(?:最近的?|上次的?|这次的?|最新的?)?(?:健康档案|病历|体检|化验|检验报告|血压|血糖|处方|诊断结果)""" +
                """|(?:\bblood pressure\b|血压)\s*[:：=为是]?\s*\d{2,3}\s*/\s*\d{2,3}"""
        )

        private fun start(objective: String): AutoGoalTeamCommand = when {
            objective.length > LIMIT -> TooLong
            personalHealth.containsMatchIn(objective) -> PrivateObjective
            else -> Start(objective)
        }

        // This is an exclusion gate only. A structured model decision, never this test, requests review.
        fun allowsModelReview(text: String): Boolean = text.isNotBlank() && !text.startsWith('/') &&
            start(text) is Start && !noDelegation.containsMatchIn(text) && HealthAgentLab.intent(text, true) == null

        fun parse(input: String): AutoGoalTeamCommand? {
            val text = input.trim()
            if (text.startsWith('/')) {
                val objective = slash.matchEntire(text)?.groupValues?.get(1)?.trim() ?: return null
                return when (objective.lowercase()) {
                    "", "help", "帮助" -> Help
                    "stop", "停止" -> Stop
                    else -> start(objective)
                }
            }
            if (text.length <= 100 && (stopEn.matches(text) || stopZh.matches(text))) return Stop
            val visible = quoted.replace(text.take(LIMIT), " ")
            if (noDelegation.containsMatchIn(visible)) return null
            val requested = separator.splitToSequence(visible).map(String::trim).any { clause ->
                clause.isNotEmpty() && !meta.containsMatchIn(clause) &&
                    (requestEn.containsMatchIn(clause) || requestZh.containsMatchIn(clause) || withTeamEn.containsMatchIn(clause))
            }
            // The objective may precede the request. Confirm the entire typed turn, verbatim.
            return if (requested) start(text) else null
        }
    }
}
