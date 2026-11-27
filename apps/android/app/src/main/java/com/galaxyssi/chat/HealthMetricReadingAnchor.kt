package com.galaxyssi.chat

import android.graphics.Rect
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.core.view.doOnPreDraw

internal class HealthMetricReadingAnchor private constructor(private val scroll: ScrollView, private val rows: LinearLayout,
    private val keys: List<String>, private val offset: Int, private val oldY: Int) {
    fun restore(filter: View) {
        rows.doOnPreDraw {
            if (!rows.isAttachedToWindow || !scroll.isAttachedToWindow) return@doOnPreDraw
            val limit = ((scroll.getChildAt(0)?.height ?: 0) - scroll.height + scroll.paddingTop + scroll.paddingBottom).coerceAtLeast(0)
            if (scroll.scrollY != oldY.coerceAtMost(limit)) return@doOnPreDraw
            val remaining = children(rows).associateBy { it.getTag(R.id.healthReadingKey) }
            val next = keys.firstNotNullOfOrNull { remaining[it] }
            scroll.scrollTo(0, top(scroll, next ?: filter) - if (next == null) scroll.paddingTop else offset)
        }
    }

    companion object {
        private fun children(rows: LinearLayout) = (0 until rows.childCount).map(rows::getChildAt)
            .filter { it.getTag(R.id.healthReadingKey) is String }
        private fun top(scroll: ScrollView, view: View): Int = Rect(0, 0, view.width, view.height).also {
            scroll.offsetDescendantRectToMyCoords(view, it)
        }.top
        fun capture(rows: LinearLayout): HealthMetricReadingAnchor? {
            val scroll = generateSequence(rows.parent) { it.parent }.filterIsInstance<ScrollView>().firstOrNull() ?: return null
            val y = scroll.scrollY
            if (y + scroll.paddingTop < top(scroll, rows) || y >= top(scroll, rows) + rows.height) return null
            val old = children(rows)
            val index = old.indexOfFirst { top(scroll, it) + it.height > y + scroll.paddingTop }
            if (index < 0) return null
            val order = old.indices.sortedWith(compareBy<Int> { kotlin.math.abs(it - index) }.thenByDescending { it })
            return HealthMetricReadingAnchor(scroll, rows, order.map { old[it].getTag(R.id.healthReadingKey) as String },
                top(scroll, old[index]) - y, y)
        }
    }
}
