package com.galaxyssi.chat

import android.app.Activity
import android.view.View

internal fun Activity.openAtlasModelDetails() {
    val decor = window.decorView
    val standalone = decor.findViewWithTag<View>("atlas-tab-3")
    if (standalone != null) {
        standalone.performClick()
        return
    }
    val function = requireNotNull(decor.findViewWithTag<View>("atlas-tab-1"))
    if (!function.isSelected) function.performClick()
    val inline = requireNotNull(decor.findViewWithTag<View>("atlas-open-simulation"))
    if (!inline.isSelected) inline.performClick()
}

internal fun Activity.hasOpenAtlasModels(): Boolean =
    window.decorView.findViewWithTag<View>("atlas-tab-3")?.isSelected == true ||
        window.decorView.findViewWithTag<View>("atlas-inline-models")?.visibility == View.VISIBLE
