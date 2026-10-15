package com.galaxyssi.chat

/** Literal numbers stay exact; spelled-out counts and month names may become equivalent digits. */
internal object AttentionHeadlineNumbers {
    private val digits = Regex("[0-9]+(?:[.,][0-9]+)*")
    private val small = ("zero one two three four five six seven eight nine ten eleven twelve thirteen " +
        "fourteen fifteen sixteen seventeen eighteen nineteen").split(' ').withIndex().associate { it.value to it.index }
    private val tens = "twenty thirty forty fifty sixty seventy eighty ninety".split(' ')
        .withIndex().associate { it.value to (it.index + 2) * 10 }
    private val months = "january february march april may june july august september october november december"
        .split(' ').withIndex().flatMap { listOf(it.value to it.index + 1, it.value.take(3) to it.index + 1) }
        .toMap() + ("sept" to 9)
    private val words = Regex("(?<![A-Za-z0-9])(?:${(small.keys + tens.keys + months.keys).joinToString("|")})(?![A-Za-z0-9])",
        RegexOption.IGNORE_CASE)

    fun preserved(original: String, translated: String): Boolean {
        val remaining = digits.findAll(translated).map { it.value }.toMutableList()
        for (number in digits.findAll(original)) if (!remaining.remove(number.value)) return false
        val equivalents = mutableListOf<String>()
        val matches = words.findAll(original).toList()
        var index = 0
        while (index < matches.size) {
            val match = matches[index++]
            val word = match.value.lowercase(java.util.Locale.ROOT)
            var value = small[word] ?: tens[word] ?: months.getValue(word)
            val next = matches.getOrNull(index)
            val unit = next?.value?.lowercase(java.util.Locale.ROOT)?.let(small::get)
            if (word in tens && next != null && unit in 1..9 &&
                original.substring(match.range.last + 1, next.range.first).matches(Regex("[ -]+"))) {
                value += unit!!; index++
            }
            equivalents += value.toString()
        }
        return remaining.all { equivalents.remove(it) }
    }
}
