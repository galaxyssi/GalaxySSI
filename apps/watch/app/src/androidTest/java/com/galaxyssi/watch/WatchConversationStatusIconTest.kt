package com.galaxyssi.watch

import android.view.View
import android.widget.FrameLayout
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class WatchConversationStatusIconTest {
    @Test fun iconsHaveAccessibleLabelsAndFixedSizeWithoutUnreadBadge() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val size = (28 * context.resources.displayMetrics.density).toInt()
            for (status in WatchConversationStatus.entries) {
                val icon = WatchConversationStatusIcon(context, status)
                icon.layoutParams = FrameLayout.LayoutParams(size, size)
                val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
                icon.measure(spec, spec)
                assertEquals(size, icon.measuredWidth)
                assertEquals(size, icon.measuredHeight)
                assertEquals(context.getString(status.label()), icon.contentDescription)
                assertNotNull(icon.drawable)
                assertNull(icon.background)
                assertEquals(status, icon.tag)
            }
        }
    }
}
