package com.galaxyssi.chat

internal data class WechatMenuLabel(val text: String, val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val x get() = (left + right) / 2
    val y get() = (top + bottom) / 2
    val height get() = bottom - top
}

internal data class WechatArticleMenu(val iconY: Int, val copyX: Int?)

internal object WechatArticleMenuLayout {
    val labels = listOf("复制链接", "複製連結", "複製鏈接", "copylink", "浮窗", "听全文", "稍后听",
        "保存为图片", "投诉", "刷新", "划线和留言", "取消", "cancel", "收藏", "星标", "问小微", "转发给朋友")
    private val firstRow = setOf("收藏", "星标", "问小微", "转发给朋友")
    private val secondRow = labels.toSet() - firstRow - setOf("取消", "cancel")

    fun resolve(items: List<WechatMenuLabel>, width: Int, height: Int): WechatArticleMenu? {
        val cancel = items.filter { it.text in setOf("取消", "cancel") && it.y > height * .65 }
            .maxByOrNull { it.y } ?: return null
        val upper = items.filter { it.text in firstRow && it.y > height * .45 && it.bottom < cancel.top }
        if (upper.size < 2) return null
        val upperY = upper.map { it.y }.sorted().let { it[it.size / 2] }
        val lower = items.filter { it.text in secondRow && it.height > 0 && it.right > it.left &&
            it.left >= 0 && it.right <= width && it.y > upperY + it.height * 3 && it.bottom < cancel.top }
        if (lower.isEmpty()) return null
        val rowY = lower.map { it.y }.sorted().let { it[it.size / 2] }
        val font = lower.map { it.height }.sorted().let { it[it.size / 2] }
        val row = lower.filter { kotlin.math.abs(it.y - rowY) <= font * 2 }
        val iconY = rowY - font * 4
        if (iconY <= upperY + font || iconY >= rowY || iconY > cancel.top) return null
        val copy = row.singleOrNull { WechatArticleLinkPolicy.isCopy(it.text) && it.right - it.left < width / 3 }
        return WechatArticleMenu(iconY, copy?.x)
    }
}
