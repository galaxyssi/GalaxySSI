package com.galaxyssi.chat

import java.util.Locale

/** Only complete, labeled report rows become suggestions. The original line remains evidence. */
internal data class HealthOcrLabRow(val metric: HealthMetric, val result: HealthResult, val unit: String, val reference: String = "") {
    companion object {
        private val ambiguous = setOf("cr", "ua", "pro", "chol", "gpt", "got", "hb")
        private val space = Regex("\\s+")
        private val labels = buildMap {
            HealthMetricCatalog.entries.filter { it.laboratory }.forEach { entry ->
                (listOf(entry.english, entry.chinese) + entry.aliases).forEach { label ->
                    val key = label.lowercase(Locale.ROOT)
                    if (key !in ambiguous) put(key, entry.metric)
                }
            }
            put("glucose", HealthMetric.GLUCOSE)
            put("hemoglobin a1c", HealthMetric.HBA1C)
        }
        private val labelPattern = labels.keys.sortedByDescending(String::length)
            .joinToString("|") { label -> label.split(' ').joinToString("\\s+", transform = Regex::escape) }
        private val labeled = Regex("^(?:[0-9]{1,3}[.)]\\s+)?($labelPattern)" +
            "(?=\\s|[:=\\uff1a(\\uff08<>\\u2264\\u2265\\uff1c\\uff1e]|(?<=[\\u3400-\\u9fff])[0-9])\\s*[:=\\uff1a]?\\s*(.+)$",
            RegexOption.IGNORE_CASE)
        private val referenceSuffix = Regex(
            "\\s*[;\\uff1b]\\s*(?:reference(?:\\s+(?:range|interval))?|\\u53c2\\u8003(?:\\u8303\\u56f4|\\u503c))\\s*[:\\uff1a]\\s*(.+)$",
            RegexOption.IGNORE_CASE,
        )
        private val alternate = Regex("^(.+?)\\s*[(\\uff08]\\s*(.+?)\\s*[)\\uff09]$")
        private val flag = Regex("(?:\\s+[HL]|\\s*[\\u2191\\u2193])$")
        private val unitPatterns = mapOf(
            "mmol/L" to "mmol\\s*/\\s*l",
            "mg/dL" to "mg\\s*/\\s*dl",
            "g/L" to "g\\s*/\\s*l",
            "g/dL" to "g\\s*/\\s*dl",
            "%" to "[%\\uff05]",
            "mmol/mol" to "mmol\\s*/\\s*mol",
            "10^9/L" to "(?:[x\\u00d7]\\s*)?10(?:\\^\\s*9|\\u2079)\\s*/\\s*l",
            "10^3/uL" to "(?:[x\\u00d7]\\s*)?10(?:\\^\\s*3|\\u00b3)\\s*/\\s*[u\\u00b5\\u03bc]l",
            "U/L" to "u\\s*/\\s*l",
            "umol/L" to "[u\\u00b5\\u03bc]mol\\s*/\\s*l",
            "mg/L" to "mg\\s*/\\s*l",
            "mIU/L" to "miu\\s*/\\s*l",
            "uIU/mL" to "[u\\u00b5\\u03bc]iu\\s*/\\s*ml",
        ).mapValues { (_, unit) ->
            Regex("^(.+?)\\s*(?:$unit)$", RegexOption.IGNORE_CASE) to
                Regex("^(?:[(\\uff08]\\s*(?:$unit)\\s*[)\\uff09]|(?:$unit))\\s*[:=\\uff1a]?\\s*(.+)$", RegexOption.IGNORE_CASE)
        }

        fun parse(line: String): HealthOcrLabRow? {
            val text = line.trim()
            if (text.length > 480 || text.any { it.isISOControl() && it != '\t' }) return null
            val match = labeled.matchEntire(text) ?: return null
            val metric = labels[match.groupValues[1].lowercase(Locale.ROOT).replace(space, " ")] ?: return null
            val body = match.groupValues[2]
            val suffix = referenceSuffix.find(body)
            val reference = suffix?.groupValues?.get(1)?.trim().orEmpty()
            if (reference.length > 200 || reference.any(Char::isISOControl)) return null
            val value = (suffix?.let { body.substring(0, it.range.first) } ?: body).trim()
            val parsed = readRow(metric, value) ?: flag.find(value)?.let {
                readRow(metric, value.substring(0, it.range.first).trimEnd())
            }
            return parsed?.copy(reference = reference)
        }

        private fun readRow(metric: HealthMetric, value: String): HealthOcrLabRow? {
            readValue(metric, value)?.let { return it }
            val pair = alternate.matchEntire(value) ?: return null
            val primary = readValue(metric, pair.groupValues[1].trim()) ?: return null
            val converted = readValue(metric, pair.groupValues[2].trim()) ?: return null
            if (primary.unit.isBlank() || converted.unit.isBlank() || primary.unit == converted.unit ||
                primary.result.kind != converted.result.kind) return null
            return primary.copy(unit = "")
        }

        private fun readValue(metric: HealthMetric, value: String): HealthOcrLabRow? {
            fun result(raw: String, unit: String): HealthOcrLabRow? {
                val typed = HealthResult.parse(raw, HealthResultForm.LABORATORY) ?: return null
                if ((metric.form == HealthResultForm.QUALITATIVE) != (typed.kind == HealthResultKind.QUALITATIVE)) return null
                return HealthOcrLabRow(metric, typed, unit)
            }
            result(value, "")?.let { return it }
            for (unit in metric.units) {
                val (suffix, prefix) = unitPatterns[unit] ?: continue
                for (pattern in listOf(suffix, prefix)) {
                    val raw = pattern.matchEntire(value)?.groupValues?.get(1) ?: continue
                    result(raw.trim(), unit)?.let { return it }
                }
            }
            return null
        }
    }
}
