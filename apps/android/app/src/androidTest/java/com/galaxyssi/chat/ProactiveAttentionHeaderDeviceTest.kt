package com.galaxyssi.chat

import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.CompoundButton
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProactiveAttentionHeaderDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun feedHeaderMatchesPageBackgroundInBothThemes() {
        instrumentation.runOnMainSync {
            for (nightMode in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                val config = Configuration(instrumentation.targetContext.resources.configuration).apply {
                    uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or nightMode
                }
                val context = instrumentation.targetContext.createConfigurationContext(config)
                val header = ProactiveAttentionHeader(context, {}, {})
                for (settings in listOf(false, true, false)) {
                    header.render(settings, 18)
                    assertEquals(context.getColor(if (settings) R.color.surface_bg else R.color.page_bg),
                        (header.background as ColorDrawable).color)
                }
            }
        }
    }

    @Test fun titleStaysAtPhysicalCenterWhenUnreadCountChanges() {
        instrumentation.runOnMainSync {
            for (scale in listOf(1f, 1.5f, 2f)) for (locale in listOf(Locale.SIMPLIFIED_CHINESE, Locale.ENGLISH)) {
                val config = Configuration(instrumentation.targetContext.resources.configuration).apply {
                    fontScale = scale; setLocale(locale)
                }
                val context = instrumentation.targetContext.createConfigurationContext(config)
                val density = context.resources.displayMetrics.density
                val header = ProactiveAttentionHeader(context, {}, {})
                for (widthDp in listOf(320, 384, 600)) {
                    val width = (widthDp * density).toInt()
                    val height = (56 * density).toInt()
                    var previousTitleLeft: Int? = null
                    for (count in listOf(null, 0, 18, 999, 10_000, Int.MAX_VALUE, 1, 0)) {
                        header.render(false, count)
                        header.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                        header.layout(0, 0, width, height)
                        assertEquals(context.getString(R.string.attention_discoveries), header.title.text.toString())
                        assertTrue("Title must be centered at font scale $scale / width $widthDp",
                            kotlin.math.abs(header.title.left + header.title.right - width) <= 1)
                        previousTitleLeft?.let { assertEquals(it, header.title.left) }
                        previousTitleLeft = header.title.left
                        if (count != null && count > 0) {
                            assertEquals(View.VISIBLE, header.unread.visibility)
                            assertTrue(header.unread.left >= header.title.right)
                            assertTrue(header.unread.right <= header.action.left)
                            assertEquals(context.getString(R.string.attention_header_unread, count), header.unread.contentDescription)
                        } else assertEquals(View.GONE, header.unread.visibility)
                    }
                    header.render(true, 18)
                    assertEquals(context.getString(R.string.attention_title), header.title.text.toString())
                    assertEquals(View.GONE, header.unread.visibility)
                }
            }
        }
    }

    @Test fun menuUsesOneBareCheckAndDispatchesEachAction() {
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            for (selected in listOf(AttentionFeedFilter.ALL, AttentionFeedFilter.UNREAD, AttentionFeedFilter.SAVED)) {
                val actions = mutableListOf<AttentionFeedFilter>()
                var settings = 0
                val menu = ProactiveAttentionFeedMenu(context, selected, { actions += it }, { settings++ }, {})
                val all = views(menu.content)
                assertFalse("No checkbox or radio-button frames", all.any { it is CompoundButton })
                val checks = all.filter { it.tag?.toString()?.startsWith("attention-menu-check:") == true }
                assertEquals(4, checks.size)
                assertEquals(listOf("attention-menu-check:${selected.name}"), checks.filter { it.visibility == View.VISIBLE }.map { it.tag })
                val rows = all.filter { it.tag?.toString()?.startsWith("attention-menu:") == true }
                assertEquals(listOf("attention-menu:${selected.name}"), rows.filter { it.isSelected }.map { it.tag })
                rows.forEach { it.performClick() }
                assertEquals(listOf(AttentionFeedFilter.ALL, AttentionFeedFilter.UNREAD, AttentionFeedFilter.SAVED), actions)
                assertEquals(1, settings)
            }
        }
    }

    @Test fun menuVectorsUseDotClusterAndUnboxedCheck() {
        val context = instrumentation.targetContext
        fun render(id: Int): Bitmap {
            val image = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
            context.getDrawable(id)!!.apply { setBounds(0, 0, 96, 96); draw(Canvas(image)) }
            return image
        }
        val dots = render(R.drawable.ic_attention_more)
        val check = render(R.drawable.ic_attention_check)
        try {
            listOf(12 to 5, 5 to 12, 12 to 12, 19 to 12, 12 to 19).forEach { (x, y) ->
                assertTrue(Color.alpha(dots.getPixel(x * 4, y * 4)) > 0)
            }
            assertEquals(0, Color.alpha(dots.getPixel(20, 20)))
            assertTrue(Color.alpha(check.getPixel(40, 68)) > 0)
            listOf(3 to 3, 12 to 3, 21 to 12, 12 to 21, 3 to 12).forEach { (x, y) ->
                assertEquals("Check must not have a surrounding frame", 0, Color.alpha(check.getPixel(x * 4, y * 4)))
            }
        } finally { dots.recycle(); check.recycle() }
    }

    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
}
