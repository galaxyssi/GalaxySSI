package com.galaxyssi.chat

import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.AgentChatShortcutBar
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale
import kotlin.math.roundToInt

@RunWith(AndroidJUnit4::class)
class AgentChatShortcutBarDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val ids = listOf(R.id.agentInsightBar, R.id.agentActionNewSession, R.id.agentActionSessions,
        R.id.agentActionCamera, R.id.agentActionAddFile)

    @Test fun fiveInlineActionsStayAccessibleAcrossWidthsLocalesAndFontSizes() = onMain {
        for (language in listOf("zh-CN", "en", "ar")) for (font in listOf(1f, 1.5f, 2f)) {
            for (width in listOf(320, 360, 412, 800)) {
                val context = context(language, font)
                val bar = AgentChatShortcutBar(context).apply { layoutDirection = View.LAYOUT_DIRECTION_LOCALE }
                measure(bar, width)
                val row = bar.getChildAt(0) as LinearLayout
                assertEquals(5, row.childCount)
                val density = context.resources.displayMetrics.density
                ids.forEachIndexed { index, id ->
                    val button = bar.findViewById<ViewGroup>(id)
                    assertSame(button, row.getChildAt(index))
                    assertTrue(button.isClickable && button.isFocusable)
                    assertFalse(button.contentDescription.isNullOrBlank())
                    assertTrue(button.width >= (48 * density).roundToInt())
                    assertTrue(button.height >= (48 * density).roundToInt())
                    val content = button.getChildAt(0) as LinearLayout
                    assertTrue(content.width <= button.width)
                    assertTrue(content.height <= button.height)
                    val label = content.getChildAt(1) as TextView
                    assertEquals(1, label.lineCount)
                    assertEquals(0, label.layout.getEllipsisCount(0))
                    val bounds = Rect()
                    label.paint.getTextBounds(label.text.toString(), 0, label.length(), bounds)
                    val image = content.getChildAt(0)
                    val textCenter = label.top + label.baseline + bounds.exactCenterY()
                    assertEquals("Icon and visible text must be centered", textCenter,
                        image.y + image.height / 2f, 0.5f)
                    if (button.childCount > 1) {
                        val dot = button.getChildAt(1)
                        val gap = (2 * density).roundToInt()
                        val expectedX = if (button.layoutDirection == View.LAYOUT_DIRECTION_RTL) {
                            content.left + label.left - gap - dot.width
                        } else content.left + label.right + gap
                        assertEquals("Unread dot must follow the label, not the touch target", expectedX, dot.left)
                        assertEquals(content.top + label.top + label.baseline + bounds.top - gap, dot.top)
                        assertEquals((4 * density).roundToInt(), dot.width)
                        assertTrue(dot.left >= 0 && dot.right <= button.width)
                        assertTrue(dot.top >= 0 && dot.bottom <= button.height)
                    }
                }
                if (font == 1f && language != "ar") {
                    assertEquals("Normal text should show all five actions", bar.width, row.width)
                }
                val positions = ids.map { bar.findViewById<View>(it).let { v -> v.left to v.width } }
                bar.showFeedUnread(12)
                bar.showSessionsUnread(true)
                measure(bar, width)
                assertEquals(positions, ids.map { bar.findViewById<View>(it).let { v -> v.left to v.width } })
            }
        }
    }

    @Test fun unreadDotIsBlackInLightModeAndVisibleInDarkMode() = onMain {
        for (night in listOf(false, true)) {
            val context = context("zh-CN", 1f, night)
            val bar = AgentChatShortcutBar(context)
            val background = bar.findViewById<View>(R.id.agentInsightUnreadDot).background as GradientDrawable
            assertEquals(if (night) context.getColor(R.color.text_primary) else Color.BLACK,
                background.color!!.defaultColor)
        }
    }

    @Test fun unreadMarkersAreIndependentAndDoNotReplaceActionLabels() = onMain {
        val bar = AgentChatShortcutBar(context("zh-CN", 1f))
        assertEquals(View.INVISIBLE, bar.findViewById<View>(R.id.agentInsightUnreadDot).visibility)
        assertEquals(View.INVISIBLE, bar.findViewById<View>(R.id.agentSessionsUnreadDot).visibility)
        bar.showFeedUnread(3)
        bar.showSessionsUnread(true)
        assertEquals(View.VISIBLE, bar.findViewById<View>(R.id.agentInsightUnreadDot).visibility)
        assertEquals(View.VISIBLE, bar.findViewById<View>(R.id.agentSessionsUnreadDot).visibility)
        assertEquals(bar.context.getString(R.string.chat_shortcut_feed),
            bar.findViewById<TextView>(R.id.agentInsightText).text.toString())
        bar.showFeedUnread(0)
        assertEquals(View.INVISIBLE, bar.findViewById<View>(R.id.agentInsightUnreadDot).visibility)
        assertEquals(View.VISIBLE, bar.findViewById<View>(R.id.agentSessionsUnreadDot).visibility)
        bar.showSessionsUnread(false)
        assertEquals(View.INVISIBLE, bar.findViewById<View>(R.id.agentSessionsUnreadDot).visibility)
        assertEquals(View.VISIBLE, bar.findViewById<View>(R.id.agentInsightBar).visibility)
    }

    @Test fun mainLayoutHasInlineActionsAndPreservesContactComposerAndMultilineInput() = onMain {
        val context = context("zh-CN", 1f)
        val root = LayoutInflater.from(context).inflate(R.layout.activity_main, null)
        val shortcuts = root.findViewById<AgentChatShortcutBar>(R.id.agentChatShortcuts)
        assertNotNull(shortcuts)
        ids.forEach { assertNotNull(root.findViewById<View>(it)) }
        assertEquals(8, root.findViewById<EditText>(R.id.agentGoalInput).maxLines)
        assertEquals(8, root.findViewById<EditText>(R.id.messageInput).maxLines)
        assertNotNull(root.findViewById<View>(R.id.agentSubmitButton))
        assertFalse(root.findViewById<View>(R.id.agentComposerRow).defaultFocusHighlightEnabled)
        assertNotNull(root.findViewById<View>(R.id.chatAttachmentActionTray))
        assertNotNull(root.findViewById<View>(R.id.contactReminderButton))
        val header = root.findViewById<LinearLayout>(R.id.agentFixedHeader)
        assertEquals(4, header.childCount)
        val brand = header.getChildAt(0) as LinearLayout
        assertEquals(R.id.agentBrandLogo, brand.getChildAt(0).id)
        assertEquals(R.id.agentBrandNewConversation, brand.getChildAt(1).id)
        assertEquals(context.getString(R.string.app_name),
            brand.findViewById<TextView>(R.id.agentBrandTitle).text.toString())
        assertEquals(R.id.agentSessionSummary, header.getChildAt(2).id)
        assertEquals(R.id.agentSettingsButton, header.getChildAt(3).id)
        assertEquals(android.view.Gravity.END,
            root.findViewById<TextView>(R.id.agentSessionTitle).gravity and
                android.view.Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK)
        assertNotNull(root.findViewById<View>(R.id.agentAttachButton))
        val tray = root.findViewById<LinearLayout>(R.id.agentAttachmentActionTray)
        assertEquals(View.GONE, tray.visibility)
        assertEquals(5, tray.childCount)
        listOf(R.id.agentTrayActionNewSession, R.id.agentTrayActionSessions, R.id.agentTrayActionScan,
            R.id.agentTrayActionCamera, R.id.agentTrayActionAddFile).forEach { id ->
            assertFalse(id in ids)
            assertNotNull(tray.findViewById<View>(id))
            assertNull(shortcuts.findViewById<View>(id))
        }
    }

    private fun context(language: String, font: Float, night: Boolean = false): android.content.Context {
        val base = instrumentation.targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(Locale.forLanguageTag(language))
            fontScale = font
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        }
        return ContextThemeWrapper(base.createConfigurationContext(configuration), android.R.style.Theme_Material_Light_NoActionBar)
    }

    private fun measure(view: View, widthDp: Int) {
        val width = (widthDp * view.resources.displayMetrics.density).roundToInt()
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        view.layout(0, 0, view.measuredWidth, view.measuredHeight)
    }

    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)
}
