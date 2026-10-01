package com.galaxyssi.chat

import java.net.URI

internal enum class WechatArticleOverlayHost { ACCESSIBILITY, APPLICATION, UNAVAILABLE }

internal object WechatArticleBrowserPolicy {
    fun overlayHost(accessibilityActive: Boolean, applicationOverlayAllowed: Boolean) = when {
        accessibilityActive -> WechatArticleOverlayHost.ACCESSIBILITY
        applicationOverlayAllowed -> WechatArticleOverlayHost.APPLICATION
        else -> WechatArticleOverlayHost.UNAVAILABLE
    }
    fun allowedNavigation(url: String, mainFrame: Boolean): Boolean = runCatching {
        val uri = URI(url)
        val host = uri.host.orEmpty().lowercase()
        uri.scheme == "https" && uri.userInfo == null && uri.port == -1 &&
            if (mainFrame) host == "mp.weixin.qq.com"
            else host == "qq.com" || host.endsWith(".qq.com") || host == "gtimg.com" || host.endsWith(".gtimg.com")
    }.getOrDefault(false)
}
