package com.galaxyssi.chat

import java.text.Normalizer
import java.util.Locale
import org.json.JSONObject

private const val EN_CONTRAST = "Purpose: %1\$s\n" +
    "Prediction: If %2\$s is %3\$s, a valid reading of %4\$s should be %5\$s.\n" +
    "Contrary observation: Under the same assumptions, if %2\$s is %3\$s, a valid reading of %4\$s " +
    "that is %6\$s would contradict the prediction; a missing, invalid or uninterpretable measurement would not.\n" +
    "Alternative explanation: %7\$s; missing evidence: %8\$s. This is a hypothesis, not an experimental or clinical conclusion."

internal data class TeamContrastText(val format: String = EN_CONTRAST, val higher: String = "higher", val lower: String = "lower")

internal object TeamPredictionContrast {
    private val fields = setOf("purpose", "input", "input_direction", "readout", "expected_direction", "alternative", "gap")
    private val clauses = Regex("""[.!?;。！？；\n]+""")
    private val quoted = Regex("""(?s)\x60{3}.*?(?:\x60{3}|$)|\x60[^\x60]*(?:\x60|$)|"[^"]*"|“[^”]*”|「[^」]*」|‘[^’]*’|(?<!\w)'[^'\n]+'(?!\w)""")
    private val excluded = Regex("""(?i)\b(?:translate|define|do not|don't|don’t|no need to|without asking)\b|翻译|词义|不要|不用|无需|不必""")
    private const val CLAIM = """(?:(?:this|that|the|your|our|my|a|an) )?(?:prediction|explanation|hypothesis|claim|model)\b|it\b"""
    private const val AGAINST = """falsify|refute|contradict|disprove|rule out|count (?:as evidence )?against|(?:be )?(?:incompatible|inconsistent) with|conflict with|(?:cannot|could not|can't) coexist with|make (?:you|us|me) (?:abandon|drop|reject|give up)"""
    private val english = Regex(
        """(?i)\b(?:what|which|name|give|identify|describe|specify)\s+(?:(?:a|an|one|the) )?(?:(?:valid |contrary |possible )?(?:observation|result|outcome|finding|evidence|measurement)s? )?(?:that )?(?:(?:would|could|can|might) )?(?:(?:$AGAINST) (?:$CLAIM)|prove (?:$CLAIM) wrong\b)""" +
            """|\bhow (?:can|could|would) (?:(?:$CLAIM) be (?:falsified|disproved|refuted)\b|(?:I|you|we) (?:falsify|disprove|refute) (?:$CLAIM))""" +
            """|\b(?:is|was) (?:$CLAIM) falsifiable\b"""
    )
    private val chinese = Regex(
        """(?:什么|哪[种个些]|怎样的)(?:样的)?(?:观察|现象|结果|证据|变化|读数)(?:会|能|可以|能够|将|足以)?(?:让|使|迫使)?(?:你|我们|我)?(?:(?:证伪|推翻|反驳|否定|放弃)(?:这[个一项]?|该|上述|你的)?(?:假设|解释|预测|说法)|(?:与|和)(?:这[个一项]?|该|上述)?(?:预测|解释|假设)(?:不能同时成立|不相容|相矛盾|相冲突))""" +
            """|(?:如何|怎样|怎么)(?:才能|能|可以)?(?:证伪|推翻)(?:这[个一项]?|该)(?:预测|假设|解释)"""
    )

    fun requested(objective: String): Boolean {
        if (objective.length !in 1..8000) return false
        return clauses.splitToSequence(quoted.replace(objective, " ")).any {
            !excluded.containsMatchIn(it) && (english.containsMatchIn(it) || chinese.containsMatchIn(it))
        }
    }

    private val unsafe = Regex("""[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}<>{}|\x60]|://|\]\(|%\d*\x24?s""")
    private val spaces = Regex("""[\s\p{Z}]+""")
    private fun normalized(s: String) = Normalizer.normalize(s, Normalizer.Form.NFKC)
        .lowercase(Locale.ROOT).replace(spaces, " ").trim()
    private val placeholders = fields + setOf("string", "text", "placeholder", "placeholder text", "todo", "tbd", "n/a", "na", "none",
        "null", "unknown", "unspecified", "not applicable", "not provided", "input variable", "readout variable", "input name", "readout name",
        "alternative explanation", "missing evidence", "x", "y", "foo", "bar", "占位符", "待填写", "待补充", "待填", "待定", "未知",
        "输入", "读数", "目的", "替代解释", "缺失证据", "无")

    fun render(obj: JSONObject, text: TeamContrastText): String {
        require(obj.keys().asSequence().toSet() == fields) { "Unexpected prediction contrast fields" }
        fun field(key: String, max: Int): String {
            val raw = obj.opt(key) as? String ?: throw IllegalArgumentException("Expected text: $key")
            require(raw.length in 1..max) { "Invalid prediction contrast length: $key" }
            val clean = normalized(raw)
            require(clean.any(Char::isLetter) && clean !in placeholders &&
                !unsafe.containsMatchIn(raw) && !unsafe.containsMatchIn(clean) &&
                !(clean.startsWith('[') && clean.endsWith(']'))) { "Invalid prediction contrast field: $key" }
            return raw.trim()
        }
        fun direction(key: String) = when (obj.opt(key)) {
            "higher" -> true
            "lower" -> false
            else -> throw IllegalArgumentException("Invalid direction: $key")
        }
        fun label(up: Boolean) = if (up) text.higher else text.lower
        val input = field("input", 120)
        val readout = field("readout", 120)
        require(normalized(input) != normalized(readout)) { "Input and readout must differ" }
        val expected = direction("expected_direction")
        return String.format(Locale.ROOT, text.format, field("purpose", 400), input, label(direction("input_direction")),
            readout, label(expected), label(!expected), field("alternative", 400), field("gap", 400))
    }
}
