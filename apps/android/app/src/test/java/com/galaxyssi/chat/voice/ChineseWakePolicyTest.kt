package com.galaxyssi.chat.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChineseWakePolicyTest {
    @Test fun missingLanguageIsNotReady() {
        assertEquals(LocalWakeAvailability.NEEDS_DOWNLOAD,
            ChineseWakePolicy.languageSupport(emptyList(), emptyList(), listOf("en-US", "cmn-Hans-CN")).availability)
    }

    @Test fun downloadedLanguageWinsOverPendingAndPreservesActualTag() {
        assertEquals(LocalWakeSnapshot(LocalWakeAvailability.READY, "cmn-Hans-CN"),
            ChineseWakePolicy.languageSupport(listOf("cmn-Hans-CN"), listOf("zh-CN"), listOf("zh-CN")))
    }

    @Test fun pendingDownloadIsNotReady() {
        assertEquals(LocalWakeAvailability.DOWNLOAD_PENDING,
            ChineseWakePolicy.languageSupport(emptyList(), listOf("zh-CN"), listOf("zh-CN")).availability)
    }

    @Test fun unrelatedOrTraditionalOnlyLanguageIsUnavailable() {
        assertEquals(LocalWakeAvailability.UNAVAILABLE,
            ChineseWakePolicy.languageSupport(listOf("en-US", "cmn-Hant-TW"), emptyList(), emptyList()).availability)
    }

    @Test fun emptyProviderListsAreUnavailable() {
        assertEquals(LocalWakeAvailability.UNAVAILABLE,
            ChineseWakePolicy.languageSupport(emptyList(), emptyList(), emptyList()).availability)
    }

    @Test fun handlesProviderLocaleCaseAndUnderscores() {
        assertEquals(LocalWakeAvailability.READY,
            ChineseWakePolicy.languageSupport(listOf("ZH_cn"), emptyList(), emptyList()).availability)
    }

    @Test fun acceptsDirectWakeWithChinesePunctuation() {
        assertEquals("", ChineseWakePolicy.commandAfterWake("你好，Galaxy！"))
        assertEquals("", ChineseWakePolicy.commandAfterWake("你好  ＧＡＬＡＸＹ"))
        assertEquals("", ChineseWakePolicy.commandAfterWake("你好盖乐世"))
    }

    @Test fun preservesCommandAfterWake() {
        assertEquals("查找科技新闻，再给出来源。",
            ChineseWakePolicy.commandAfterWake("你好，Galaxy，查找科技新闻，再给出来源。"))
    }

    @Test fun rejectsQuotedWakeAndOtherNames() {
        assertNull(ChineseWakePolicy.commandAfterWake("唤醒词是你好Galaxy"))
        assertNull(ChineseWakePolicy.commandAfterWake("你好 GalaxyStore"))
        assertNull(ChineseWakePolicy.commandAfterWake("你好"))
        assertNull(ChineseWakePolicy.commandAfterWake("Galaxy"))
    }
}
