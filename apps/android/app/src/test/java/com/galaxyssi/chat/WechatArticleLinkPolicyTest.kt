package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class WechatArticleLinkPolicyTest {
    @Test fun retriesOnlyFreshlyLocatedCopyInStillVisibleMenu() {
        assertTrue(WechatArticleLinkPolicy.shouldRetryCopy(true, true, 1))
        assertTrue(WechatArticleLinkPolicy.shouldRetryCopy(true, true, 2))
        assertFalse(WechatArticleLinkPolicy.shouldRetryCopy(true, true, 3))
        assertFalse(WechatArticleLinkPolicy.shouldRetryCopy(false, true, 1))
        assertFalse(WechatArticleLinkPolicy.shouldRetryCopy(true, false, 1))
        assertFalse(WechatArticleLinkPolicy.shouldRetryCopy(true, true, 0))
    }
    private fun item(text: String, x: Int, y: Int) = WechatMenuLabel(text, x - 40, y - 14, x + 40, y + 14)
    @Test fun ignoresBackgroundArticleLabelsWhenLocatingMenuRow() {
        val items = listOf(item("听全文", 200, 700), item("取消", 540, 2120), item("收藏", 934, 1575),
            item("星标", 730, 1575), item("浮窗", 120, 1904), item("投诉", 940, 1904))
        val menu = WechatArticleMenuLayout.resolve(items, 1080, 2340)!!
        assertEquals(1792, menu.iconY)
        assertNull(menu.copyX)
    }
    @Test fun locatesCopyOnlyInsideSecondMenuRow() {
        val items = listOf(item("复制链接", 200, 700), item("取消", 540, 2120), item("收藏", 934, 1575),
            item("星标", 730, 1575), item("复制链接", 450, 1904), item("投诉", 240, 1904))
        assertEquals(450, WechatArticleMenuLayout.resolve(items, 1080, 2340)!!.copyX)
        assertEquals(1904, WechatArticleMenuLayout.resolve(items, 1080, 2340)!!.copyLabelY)
    }
    @Test fun doesNotSwipeWhenOnlyBackgroundTextRemains() {
        assertNull(WechatArticleMenuLayout.resolve(listOf(item("听全文", 200, 700), item("取消", 540, 2120),
            item("收藏", 934, 1575), item("星标", 730, 1575)), 1080, 2340))
    }
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
    @Test fun recognizesSamsungSystemCopyToastWithoutAcceptingOtherMessages() {
        assertTrue(WechatArticleLinkPolicy.isSystemConfirmation("已复制。"))
        assertTrue(WechatArticleLinkPolicy.isSystemConfirmation("巳复制。"))
        assertTrue(WechatArticleLinkPolicy.isSystemConfirmation("已複製"))
        assertTrue(WechatArticleLinkPolicy.isSystemConfirmation("Copied to clipboard"))
        assertFalse(WechatArticleLinkPolicy.isSystemConfirmation("复制失败"))
        assertFalse(WechatArticleLinkPolicy.isSystemConfirmation("尚未复制"))
        assertFalse(WechatArticleLinkPolicy.isSystemConfirmation("正文中提到已复制"))
        assertFalse(WechatArticleLinkPolicy.isConfirmation("已复制。"))
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
