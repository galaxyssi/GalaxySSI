package com.galaxyssi.chat

import android.content.res.Configuration
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
                val bar = AgentChatShortcutBar(context)
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
        assertEquals(3, header.childCount)
        assertEquals(R.id.agentBrandLogo, header.getChildAt(0).id)
        assertEquals(R.id.agentSessionSummary, header.getChildAt(1).id)
        assertEquals(R.id.agentSettingsButton, header.getChildAt(2).id)
    }

    private fun context(language: String, font: Float): android.content.Context {
        val base = instrumentation.targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(Locale.forLanguageTag(language))
            fontScale = font
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
