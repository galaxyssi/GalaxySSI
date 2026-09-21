package com.galaxyssi.chat

/** One provider attempt only. A repair round must not replace a visible draft with its prefix. */
internal class CloudCitationPreviewPresentation {
    private var visible = ""

    fun replace(candidate: String): String? {
        if (candidate.isNotBlank() && candidate.length < visible.length) return null
        if (candidate == visible) return null
        visible = candidate
        return candidate
    }
}
