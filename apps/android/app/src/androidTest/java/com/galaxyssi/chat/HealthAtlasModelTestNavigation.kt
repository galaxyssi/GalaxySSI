package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Rect
import android.view.View
import android.widget.ScrollView
import androidx.core.view.doOnLayout

internal fun Activity.openAtlasModelDetails() {
    val decor = window.decorView
    if (decor.findViewWithTag<View>("atlas-standalone-models") != null) return
    val function = requireNotNull(decor.findViewWithTag<View>("atlas-tab-1"))
    if (!function.isSelected) function.performClick()
    val inline = requireNotNull(decor.findViewWithTag<View>("atlas-open-simulation"))
    if (!inline.isSelected) inline.performClick()
    val models = decor.findViewWithTag<View>("atlas-inline-models") ?: return
    val scroll = requireNotNull(decor.findViewWithTag<ScrollView>("atlas-scroll"))
    models.doOnLayout {
        scroll.post {
            if (!models.isAttachedToWindow || models.visibility != View.VISIBLE) return@post
            val rect = Rect()
            models.getDrawingRect(rect)
            scroll.offsetDescendantRectToMyCoords(models, rect)
            scroll.scrollTo(0, rect.top)
        }
    }
}

internal fun Activity.hasOpenAtlasModels(): Boolean =
    window.decorView.findViewWithTag<View>("atlas-standalone-models") != null ||
        window.decorView.findViewWithTag<View>("atlas-inline-models")?.visibility == View.VISIBLE
