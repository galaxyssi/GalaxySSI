package com.galaxyssi.chat

import java.math.BigDecimal
import java.text.Normalizer

/** Compare quantities, not their English/Chinese written units. */
internal object AttentionArticleNumbers {
    private val tokens = Regex("[0-9]+(?:,[0-9]{3})*(?:\\.[0-9]+)*(?:\\s*(?:trillion\\b|billion\\b|million\\b|" +
        "thousand\\b|hundred\\b|[kmb]\\b|[\u5341\u767e\u5343\u4e07\u4ebf\u5146]+))?|[\u96f6\u3007\u4e00\u4e8c\u4e24\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d\u5341\u767e\u5343\u4e07\u4ebf\u5146]+", RegexOption.IGNORE_CASE)
    private val units = mapOf("hundred" to "100", "thousand" to "1000", "k" to "1000", "million" to "1000000",
        "m" to "1000000", "billion" to "1000000000", "b" to "1000000000", "trillion" to "1000000000000")
    private val digits = "\u96f6\u4e00\u4e8c\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d"
    private val physicalUnits = mapOf(
        "MW" to ("power" to "1000000"), "megawatt" to ("power" to "1000000"), "megawatts" to ("power" to "1000000"),
        "\u5146\u74e6" to ("power" to "1000000"), "kW" to ("power" to "1000"), "\u5343\u74e6" to ("power" to "1000"),
        "GW" to ("power" to "1000000000"), "\u5409\u74e6" to ("power" to "1000000000"), "W" to ("power" to "1"), "\u74e6" to ("power" to "1"),
        "MHz" to ("frequency" to "1000000"), "\u5146\u8d6b\u5179" to ("frequency" to "1000000"),
        "kHz" to ("frequency" to "1000"), "\u5343\u8d6b\u5179" to ("frequency" to "1000"),
        "GHz" to ("frequency" to "1000000000"), "\u5409\u8d6b\u5179" to ("frequency" to "1000000000"),
        "MB" to ("bytes" to "1000000"), "\u5146\u5b57\u8282" to ("bytes" to "1000000"),
        "GB" to ("bytes" to "1000000000"), "\u5409\u5b57\u8282" to ("bytes" to "1000000000"),
        "TB" to ("bytes" to "1000000000000"), "\u592a\u5b57\u8282" to ("bytes" to "1000000000000")
    )
    private val physical = Regex("([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]+)?)\\s*(" +
        physicalUnits.keys.sortedByDescending(String::length).joinToString("|", transform = Regex::escape) + ")(?![A-Za-z])")

    fun values(text: String): Map<String, Int> {
        val normalized = Normalizer.normalize(text, Normalizer.Form.NFKC)
        val measured = physical.findAll(normalized).toList()
        val values = measured.map { match ->
            val (dimension, factor) = physicalUnits.getValue(match.groupValues[2])
            dimension + ":" + match.groupValues[1].replace(",", "").toBigDecimal()
                .multiply(factor.toBigDecimal()).stripTrailingZeros().toPlainString()
        } + tokens.findAll(normalized).filter { number -> measured.none { it.range.first <= number.range.last && number.range.first <= it.range.last } }
            .map { canonical(it.value) }.toList()
        return values.groupingBy { it }.eachCount()
    }

    private fun canonical(raw: String): String {
        val value = raw.lowercase().replace(",", "").replace(Regex("\\s+"), "")
        val number = value.takeWhile { it.isDigit() || it == '.' }
        if (number.count { it == '.' } > 1) return value // Version identifiers are not decimals.
        val suffix = value.drop(number.length)
        val result = if (number.isNotEmpty()) {
            val multiplier = units[suffix]?.toBigDecimal() ?: if (suffix.isEmpty()) BigDecimal.ONE else chinese(suffix)
            number.toBigDecimal().multiply(multiplier)
        } else chinese(value)
        return result.stripTrailingZeros().toPlainString()
    }

    private fun chinese(raw: String): BigDecimal {
        val text = raw.replace('\u4e24', '\u4e8c').replace('\u3007', '\u96f6')
        for ((unit, factor) in listOf('\u5146' to "1000000000000", '\u4ebf' to "100000000", '\u4e07' to "10000")) {
            val index = text.lastIndexOf(unit)
            if (index >= 0) return (if (index == 0) BigDecimal.ONE else chinese(text.take(index)))
                .multiply(factor.toBigDecimal()).add(if (index == text.lastIndex) BigDecimal.ZERO else chinese(text.drop(index + 1)))
        }
        if (text.all { it in digits }) return text.map { digits.indexOf(it) }.joinToString("").toBigDecimalOrNull() ?: BigDecimal.ZERO
        var total = 0L
        var digit = 0
        for (char in text) {
            val value = digits.indexOf(char)
            if (value >= 0) digit = value else {
                total += digit.coerceAtLeast(1) * when (char) { '\u5341' -> 10; '\u767e' -> 100; '\u5343' -> 1000; else -> 1 }
                digit = 0
            }
        }
        return BigDecimal.valueOf(total + digit)
    }
}
