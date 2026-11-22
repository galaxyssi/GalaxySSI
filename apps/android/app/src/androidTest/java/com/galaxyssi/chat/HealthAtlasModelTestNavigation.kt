package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Rect
import android.view.View
import android.widget.EditText
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

@Suppress("DEPRECATION")
internal fun Activity.closeAtlasStandaloneModel() {
    val decor = window.decorView
    check(decor.findViewWithTag<View>("atlas-standalone-models") != null)
    onBackPressed()
    check(decor.findViewWithTag<View>("atlas-standalone-models") == null)
    check(decor.findViewWithTag<View>("atlas-tab-1")?.isSelected == true)
}

internal fun Activity.openAtlasFromFigureOrSearch(id: String) {
    val decor = window.decorView
    val marker = decor.findViewWithTag<View>("atlas-hotspot-$id")
    if (marker != null && marker.performClick()) return
    requireNotNull(decor.findViewWithTag<View>("atlas-search-button")).performClick()
    if (id.startsWith("cell-") || id.startsWith("fragment-"))
        requireNotNull(decor.findViewWithTag<View>("atlas-tab-3")).performClick()
    else if (id.startsWith("tissue-"))
        requireNotNull(decor.findViewWithTag<View>("atlas-catalogue-layer-1")).performClick()
    requireNotNull(decor.findViewWithTag<EditText>("atlas-search")).setText(id)
    requireNotNull(decor.findViewWithTag<View>("atlas-entry-$id")) { id }.performClick()
}
