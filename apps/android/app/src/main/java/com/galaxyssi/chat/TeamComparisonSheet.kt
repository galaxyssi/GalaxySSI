package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject

/** Evaluate only an explicit table with an input and single threshold per row. Never infer units or missing values. */
internal object TeamComparisonSheet {
    data class Sheet(val evidence: JSONObject, val plannerObjective: String, val table: String)
    private val decimal = Regex("""-?(?:0|[1-9]\d{0,8})(?:\.\d{1,9})?""")
    private val gate = Regex("""(<=|>=|<|>)\s*(-?(?:0|[1-9]\d{0,8})(?:\.\d{1,9})?)""")
    private val divider = Regex(""":?-{3,}:?""")
    private fun cells(line: String): List<String>? = line.trim().takeIf { it.startsWith('|') && it.endsWith('|') }
        ?.drop(1)?.dropLast(1)?.split('|')?.map(String::trim)

    fun evaluate(objective: String): Sheet? {
        val lines = objective.lines()
        val headers = lines.indices.filter { i ->
            cells(lines[i])?.take(2)?.map(String::lowercase) in listOf(listOf("input","gate"), listOf("输入","门槛"))
        }
        val start = headers.singleOrNull() ?: return null
        val header = cells(lines[start]) ?: return null
        val names = header.drop(2)
        if (names.size !in 1..10 || names.toSet().size != names.size ||
            names.any { it.isBlank() || it.length > 40 }) return null
        val separators = lines.getOrNull(start+1)?.let(::cells) ?: return null
        if (separators.size != header.size || separators.any { !divider.matches(it) }) return null
        val cases = lines.drop(start+2).takeWhile { it.trimStart().startsWith('|') }
        if (cases.size !in 1..32) return null
        val seen = mutableSetOf<String>()
        val passes = names.toMutableSet()
        val rows = JSONArray()
        val points = mutableListOf<String>()
        var gates = 0
        for (line in cases) {
            val fields = cells(line) ?: return null
            if (fields.size != header.size || fields[0].isBlank() || fields[0].length > 40 || !seen.add(fields[0])) return null
            val check = gate.matchEntire(fields[1])
            if (check == null && fields[1] != "-") return null
            if (check != null) gates++
            val values = JSONObject()
            for ((index, name) in names.withIndex()) {
                val raw = fields[index+2]
                if (!decimal.matches(raw)) return null
                val value = JSONObject().put("value", raw)
                if (check != null) {
                    val cmp = BigDecimal(raw).compareTo(BigDecimal(check.groupValues[2]))
                    val pass = when (check.groupValues[1]) {
                        "<" -> cmp < 0
                        "<=" -> cmp <= 0
                        ">" -> cmp > 0
                        else -> cmp >= 0
                    }
                    value.put("pass", pass)
                    if (!pass) passes.remove(name)
                }
                values.put(name, value)
            }
            rows.put(JSONObject().put("input", fields[0]).put("gate", fields[1]).put("series", values))
            points += "x=${fields[0]}: " + names.zip(fields.drop(2)).joinToString(", ") { (n,v) -> "$n=$v" }
        }
        if (gates == 0) return null
        val plannerObjective = (lines.take(start).joinToString("\n").trimEnd() + " " + points.joinToString("; ") +
            "\n" + lines.drop(start+2+cases.size).joinToString("\n")).trim()
        return Sheet(JSONObject().put("rows", rows).put("pass_all", JSONArray(names.filter { it in passes })), plannerObjective,
            lines.subList(start, start+2+cases.size).joinToString("\n"))
    }
}
