package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONObject

internal enum class HealthResultKind { NUMBER, COMPARISON, RANGE, QUALITATIVE }

/** A reported bound or label is not an exact measurement and must never enter numeric aggregation as one. */
internal data class HealthResult(val kind: HealthResultKind, val raw: String, val canonical: String,
    val number: String = "", val operator: String = "", val upper: String = "") {
    val exactNumber: BigDecimal? get() = if (kind == HealthResultKind.NUMBER) number.toBigDecimal() else null
    fun json() = JSONObject().put("kind", kind.name).put("raw", raw).put("canonical", canonical)
        .put("number", number).put("operator", operator).put("upper", upper)
    companion object {
        const val MAX_LENGTH = 128
        private const val DECIMAL = "(?:[0-9]+(?:[.,][0-9]+)?|[.,][0-9]+)"
        private val exact = Regex("^$DECIMAL$")
        private val comparison = Regex("^(<=|>=|<|>|\u2264|\u2265|\uff1c|\uff1e)\\s*($DECIMAL)$")
        private val range = Regex("^($DECIMAL)\\s*(?:-|\u2013|\u2014|~|\u301c|\uff5e|\u81f3|\\bto\\b)\\s*($DECIMAL)$", RegexOption.IGNORE_CASE)
        private val labels = setOf("negative", "positive", "trace", "indeterminate", "inconclusive", "reactive", "nonreactive", "non-reactive", "detected", "not detected",
            "\u9634\u6027", "\u9633\u6027", "\u5f31\u9633\u6027", "\u53ef\u7591", "\u672a\u68c0\u51fa", "\u68c0\u51fa")
        private val grade = Regex("(?:[1-4]\\+|[+]{1,4}|[+-]|\u00b1)")
        private fun numeric(raw: String, zero: Boolean): String? {
            if (raw.length > 20 || !exact.matches(raw)) return null
            val number = raw.replace(',', '.').toBigDecimalOrNull() ?: return null
            return number.takeIf { if (zero) it >= BigDecimal.ZERO else it > BigDecimal.ZERO }?.stripTrailingZeros()?.toPlainString()
        }
        fun parse(input: String, form: HealthResultForm): HealthResult? {
            val raw = input.trim()
            if (raw.isEmpty() || raw.length > MAX_LENGTH || raw.any(Char::isISOControl)) return null
            if (form == HealthResultForm.COUNT && !raw.matches(Regex("[0-9]+"))) return null
            if (form == HealthResultForm.QUALITATIVE) {
                if (raw.none(Char::isLetter) && !grade.matches(raw)) return null
                if (raw.startsWith('=') || raw.contains('<') || raw.contains('>')) return null
                return HealthResult(HealthResultKind.QUALITATIVE, raw, "label:" + raw.lowercase(java.util.Locale.ROOT))
            }
            numeric(raw, form != HealthResultForm.POSITIVE)?.let { value ->
                if (form == HealthResultForm.COUNT && value.toBigDecimal().stripTrailingZeros().scale() > 0) return null
                return HealthResult(HealthResultKind.NUMBER, raw, value, value)
            }
            if (form != HealthResultForm.LABORATORY) return null
            comparison.matchEntire(raw)?.let { match ->
                val value = numeric(match.groupValues[2], true) ?: return null
                val op = when (match.groupValues[1]) {
                    "\u2264" -> "<="; "\u2265" -> ">="; "\uff1c" -> "<"; "\uff1e" -> ">"
                    else -> match.groupValues[1]
                }
                return HealthResult(HealthResultKind.COMPARISON, raw, "$op$value", value, op)
            }
            range.matchEntire(raw)?.let { match ->
                val lower = numeric(match.groupValues[1], true) ?: return null
                val upper = numeric(match.groupValues[2], true) ?: return null
                if (lower.toBigDecimal() > upper.toBigDecimal()) return null
                return HealthResult(HealthResultKind.RANGE, raw, "range:$lower..$upper", lower, upper = upper)
            }
            if (raw.lowercase(java.util.Locale.ROOT) in labels || grade.matches(raw))
                return HealthResult(HealthResultKind.QUALITATIVE, raw, "label:" + raw.lowercase(java.util.Locale.ROOT))
            return null
        }
        fun from(j: JSONObject) = HealthResult(HealthResultKind.valueOf(j.getString("kind")), j.getString("raw"), j.getString("canonical"),
            j.getString("number"), j.getString("operator"), j.getString("upper"))
    }
}
