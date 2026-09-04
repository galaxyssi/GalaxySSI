package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class MicrosoftTtsVoiceCatalogTest {
    @Test
    fun exposesTheThreeSupportedXiaoxiaoVoicesInStableOrder() {
        assertEquals(
            listOf(
                "zh-CN-XiaoxiaoNeural",
                "zh-CN-Xiaoxiao:DragonHDFlashLatestNeural",
                "zh-CN-Xiaoxiao2:DragonHDFlashLatestNeural"
            ),
            MicrosoftTtsVoiceCatalog.voices
        )
    }

    @Test
    fun canonicalizesKnownIdsAndFallsBackFromUnknownValues() {
        assertEquals(
            MicrosoftTtsVoiceCatalog.XIAOXIAO_DRAGON_HD_FLASH,
            MicrosoftTtsVoiceCatalog.canonical(
                "  zh-cn-xiaoxiao:dragonhdflashlatestneural  "
            )
        )
        assertEquals(
            MicrosoftTtsVoiceCatalog.XIAOXIAO,
            MicrosoftTtsVoiceCatalog.canonical("unsupported")
        )
    }
}
