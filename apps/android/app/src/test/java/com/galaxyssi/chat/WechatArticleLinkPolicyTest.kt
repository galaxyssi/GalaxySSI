package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class WechatArticleLinkPolicyTest {
    @Test fun matchesOnlyExactCopyLabels() {
        assertTrue(WechatArticleLinkPolicy.isCopy("复 制 链 接"))
        assertTrue(WechatArticleLinkPolicy.isCopy("複製連結"))
        assertTrue(WechatArticleLinkPolicy.isCopy("Copy link"))
        assertFalse(WechatArticleLinkPolicy.isCopy("不要复制链接"))
    }
    @Test fun requiresRecognizedMenuContext() {
        assertTrue(WechatArticleLinkPolicy.isMenu(listOf("取消", "收藏", "投诉")))
        assertFalse(WechatArticleLinkPolicy.isMenu(listOf("复制链接", "文章正文")))
    }
    @Test fun acceptsMergedOcrRowsWithoutCountingOneLabelTwice() {
        assertTrue(WechatArticleLinkPolicy.isArticle(listOf("听全文 AI摘要")))
        assertTrue(WechatArticleLinkPolicy.isMenu(listOf("转发给朋友 收藏", "浮窗 投诉", "取消")))
        assertFalse(WechatArticleLinkPolicy.isMenu(listOf("收藏", "收藏", "取消")))
    }
    @Test fun confirmsOnlyCopySuccess() {
        assertTrue(WechatArticleLinkPolicy.isConfirmation("已复制到剪贴板"))
        assertFalse(WechatArticleLinkPolicy.isConfirmation("复制失败"))
    }
    @Test fun findsToolbarDotsAtDifferentSizes() {
        for (width in listOf(720, 1080, 1440)) {
            val height = width * 2
            val cy = height / 12
            val cx = width * 92 / 100
            val radius = width / 240
            val gap = width / 50
            val result = WechatArticleLinkPolicy.moreButton(width, height) { x, y ->
                if (listOf(cx-gap, cx, cx+gap).any { (x-it)*(x-it)+(y-cy)*(y-cy) <= radius*radius }) 0xff333333.toInt()
                else 0xffffffff.toInt()
            }
            assertNotNull(result)
            assertTrue(kotlin.math.abs(result!!.first-cx) < 5)
        }
    }
    @Test fun refusesBlankOrSingleToolbarGlyph() {
        assertNull(WechatArticleLinkPolicy.moreButton(1080, 2340) { _, _ -> -1 })
        assertNull(WechatArticleLinkPolicy.moreButton(1080, 2340) { x, y -> if (x in 990..1000 && y in 170..180) 0 else -1 })
    }
}
