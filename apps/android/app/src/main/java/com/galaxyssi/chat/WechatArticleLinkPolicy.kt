package com.galaxyssi.chat

internal object WechatArticleLinkPolicy {
    fun shouldRetryCopy(menuVisible: Boolean, copyLocated: Boolean, attempts: Int) =
        menuVisible && copyLocated && attempts in 1..2
    private fun normalized(text: String) = text.filterNot(Char::isWhitespace).lowercase()
    fun isCopy(text: String) = normalized(text) in setOf("复制链接", "複製連結", "複製鏈接", "copylink")
    fun isConfirmation(text: String) = normalized(text) in setOf(
        "已复制到剪贴板", "已複製到剪貼簿", "链接已复制", "連結已複製", "copied", "linkcopied", "copiedtoclipboard")
    fun isSystemConfirmation(text: String) = normalized(text).trimEnd('.', '。', '!') in setOf(
        "已复制", "巳复制", "已複製", "copied", "copiedtoclipboard")
    fun isMenu(lines: List<String>): Boolean {
        val text = lines.joinToString("", transform = ::normalized)
        return listOf("取消", "cancel").any(text::contains) &&
            listOf("收藏", "转发给朋友", "轉發給朋友", "复制链接", "複製連結", "投诉", "投訴", "favorite", "sendtochat", "copylink").count(text::contains) >= 2
    }
    // Locate the actual three-dot toolbar glyph; never tap a fixed screen coordinate.
    fun moreButton(width: Int, height: Int, pixel: (Int, Int) -> Int): Pair<Int, Int>? {
        if (width < 100 || height < 100) return null
        val hits = mutableListOf<Pair<Int, Int>>()
        for (y in (height * .035).toInt()..(height * .14).toInt()) {
            val runs = mutableListOf<IntRange>()
            var start = -1
            for (x in (width * .84).toInt() until (width * .99).toInt()) {
                val color = pixel(x, y)
                val dark = ((color ushr 16) and 255) < 115 && ((color ushr 8) and 255) < 115 && (color and 255) < 115
                if (dark && start < 0) start = x
                if (!dark && start >= 0) { runs += start until x; start = -1 }
            }
            if (runs.size != 3) continue
            val sizes = runs.map { it.last - it.first + 1 }
            val gaps = runs.zipWithNext { a, b -> b.first - a.last - 1 }
            if (sizes.all { it in 2..maxOf(3, width / 60) } && sizes.max() <= sizes.min() * 2 &&
                gaps.all { it in 2..width / 30 } && kotlin.math.abs(gaps[0] - gaps[1]) <= width / 150 + 2) {
                hits += ((runs.first().first + runs.last().last) / 2) to y
            }
        }
        val group = hits.groupBy { it.first / 4 }.values.maxByOrNull { it.size } ?: return null
        if (group.size < 3 || group.last().second - group.first().second > width / 30) return null
        return group[group.size / 2]
    }
}
