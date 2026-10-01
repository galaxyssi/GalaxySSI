package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class WechatArticleBrowserPolicyTest {
    @Test fun reusesAccessibilityWithoutRequiringApplicationOverlayPermission() {
        assertEquals(WechatArticleOverlayHost.ACCESSIBILITY, WechatArticleBrowserPolicy.overlayHost(true, false))
        assertEquals(WechatArticleOverlayHost.ACCESSIBILITY, WechatArticleBrowserPolicy.overlayHost(true, true))
        assertEquals(WechatArticleOverlayHost.APPLICATION, WechatArticleBrowserPolicy.overlayHost(false, true))
        assertEquals(WechatArticleOverlayHost.UNAVAILABLE, WechatArticleBrowserPolicy.overlayHost(false, false))
    }
    @Test fun mainNavigationStaysOnWeChat() {
        assertTrue(WechatArticleBrowserPolicy.allowedNavigation("https://mp.weixin.qq.com/s/example", true))
        assertTrue(WechatArticleBrowserPolicy.allowedNavigation("https://mp.weixin.qq.com/mp/secitptpage/verify", true))
        assertFalse(WechatArticleBrowserPolicy.allowedNavigation("https://qq.com/", true))
        assertFalse(WechatArticleBrowserPolicy.allowedNavigation("https://mp.weixin.qq.com.evil.test/", true))
    }
    @Test fun verificationFramesAllowOnlyHttpsTencentHosts() {
        assertTrue(WechatArticleBrowserPolicy.allowedNavigation("https://t.captcha.qq.com/", false))
        assertTrue(WechatArticleBrowserPolicy.allowedNavigation("https://captcha.gtimg.com/", false))
        assertFalse(WechatArticleBrowserPolicy.allowedNavigation("https://evilqq.com/", false))
        assertFalse(WechatArticleBrowserPolicy.allowedNavigation("https://gtimg.com.evil.test/", false))
    }
    @Test fun rejectsLocalSchemesPortsAndCredentials() {
        for (url in listOf("http://mp.weixin.qq.com/s/a", "file:///sdcard/a", "intent://test", "javascript:alert(1)",
            "https://user@mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com:8888/s/a")) {
            assertFalse(url, WechatArticleBrowserPolicy.allowedNavigation(url, true))
            assertFalse(url, WechatArticleBrowserPolicy.allowedNavigation(url, false))
        }
    }
}
