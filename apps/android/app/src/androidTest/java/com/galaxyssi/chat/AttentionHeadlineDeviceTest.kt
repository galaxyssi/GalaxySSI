package com.galaxyssi.chat

import android.content.ClipboardManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.os.SystemClock
import android.text.Selection
import android.text.Spannable
import android.text.TextUtils
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.textclassifier.TextClassifier
import android.widget.LinearLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class AttentionHeadlineDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val title = "苹果详解新设备手写笔支持：完整新闻标题可以选择复制，折叠时隐藏的末尾文字也不能丢失。"
    private val translated = "人工智能研究取得新进展，中文译文支持按需选择复制。"

    private fun item(title: String = this.title, translation: String = "") = GlobalProactiveInboxPolicy.project(
        listOf(GlobalProactiveMessage(id = "attention-feed:headline-test",
            sourceEventId = "research:attention-research:ai:feed:headline-test", sourceConversationId = "",
            target = GlobalProactiveTarget.NEW_CONVERSATION, title = title,
            content = "这是独立测试正文，不保存新闻或修改真实聊天记录。", topic = "科技",
            urgent = false, status = GlobalProactiveMessageStatus.DELIVERED, newsArticleKey = "headline-test")),
        emptyList()).single().copy(translatedTitle = translation)

    private class Host(val activity: ComposerEditingTestActivity, val article: ProactiveAttentionArticleView,
                       val headline: AttentionHeadlineView, val row: AttentionReaderRow) {
        var opened = 0
        var articleMenus = 0
        val feedback = mutableListOf<Pair<String, AttentionHeadlineAction>>()
    }

    private fun withHeadline(expanded: Boolean = false, translation: String = "", block: (Host) -> Unit) {
        instrumentation.setInTouchMode(true)
        instrumentation.uiAutomation.serviceInfo = instrumentation.uiAutomation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        ActivityScenario.launch(ComposerEditingTestActivity::class.java).use { scenario ->
            lateinit var host: Host
            scenario.onActivity { activity ->
                activity.window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                val row = AttentionReaderRow(item(translation = translation), expanded, false)
                val article = ProactiveAttentionArticleView(activity, { host.opened++ }, {}, {}, {},
                    { _, done -> done(null) }, { item, action ->
                        host.articleMenus++
                        host.feedback += item.key to action
                    })
                article.bind(row)
                host = Host(activity, article, article.findViewWithTag("attention-headline:${row.item.key}"), row)
                activity.setContentView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(24, 100, 24, 24)
                    addView(article, LinearLayout.LayoutParams(-1, -2))
                })
            }
            instrumentation.waitForIdleSync()
            block(host)
        }
    }

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)
    private fun waitUntil(check: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5000
        do {
            if (check()) return
            SystemClock.sleep(50)
        } while (SystemClock.uptimeMillis() < deadline)
        assertTrue("UI condition did not become true", check())
    }

    private fun nodes(node: AccessibilityNodeInfo?): Sequence<AccessibilityNodeInfo> = sequence {
        if (node == null) return@sequence
        yield(node)
        for (index in 0 until node.childCount) yieldAll(nodes(node.getChild(index)))
    }

    private fun clickMenu(host: Host, resource: Int) {
        val label = host.activity.getString(resource)
        waitUntil {
            val visible = nodes(instrumentation.uiAutomation.rootInActiveWindow).toList()
            if (visible.none { it.contentDescription?.toString() == host.activity.getString(R.string.attention_read) })
                return@waitUntil false
            var node = visible.firstOrNull {
                it.text?.toString() == label || it.contentDescription?.toString() == label
            }
            while (node != null && !node.isClickable) node = node.parent
            node?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
        }
        instrumentation.waitForIdleSync()
    }

    private fun select(host: Host) {
        main { assertTrue(host.headline.performLongClick()) }
        clickMenu(host, R.string.common_select)
        waitUntil {
            var ready = false
            main { ready = host.headline.isTextSelectable && host.headline.selectionEnd > host.headline.selectionStart }
            ready
        }
        waitUntil {
            instrumentation.uiAutomation.windows.any { window -> nodes(window.root).any {
                it.text?.toString() == host.activity.getString(android.R.string.copy) ||
                    it.contentDescription?.toString() == host.activity.getString(android.R.string.copy)
            }
            }
        }
    }

    private fun clipboard(host: Host) = host.activity.getSystemService(ClipboardManager::class.java)
        .primaryClip!!.getItemAt(0).text.toString()

    @Test fun copyIncludesEllipsizedTitleAndDoesNotOpenArticleMenu() = withHeadline { host ->
        main {
            assertTrue((0 until host.headline.layout.lineCount).any { host.headline.layout.getEllipsisCount(it) > 0 })
            host.headline.performLongClick()
        }
        clickMenu(host, R.string.common_copy)
        main {
            assertEquals(title, clipboard(host))
            assertEquals(0, host.opened)
            assertEquals(0, host.articleMenus)
            assertFalse(host.headline.isTextSelectable)
        }
    }

    @Test fun copyUsesDisplayedTranslationAndSingleTapStillOpensArticle() = withHeadline(translation = translated) { host ->
        main {
            assertEquals(translated, host.headline.text.toString())
            host.headline.performLongClick()
        }
        clickMenu(host, R.string.common_copy)
        main {
            assertEquals(translated, clipboard(host))
            host.headline.performClick()
            assertEquals(1, host.opened)
        }
    }

    @Test fun nativeSelectionCopiesOnlyChosenRangeThenRestoresCollapsedLayout() = withHeadline { host ->
        var height = 0
        main { height = host.headline.layoutParams.height }
        select(host)
        main {
            assertEquals(0, host.headline.selectionStart)
            assertEquals(title.length, host.headline.selectionEnd)
            assertEquals(Int.MAX_VALUE, host.headline.maxLines)
            assertNull(host.headline.ellipsize)
            assertFalse(host.headline.onCheckIsTextEditor())
            Selection.setSelection(host.headline.text as Spannable, 2, 8)
            host.headline.onTextContextMenuItem(android.R.id.copy)
            assertEquals(title.substring(2, 8), clipboard(host))
        }
        waitUntil { var done = false; main { done = !host.headline.isTextSelectable }; done }
        main {
            assertEquals(2, host.headline.maxLines)
            assertEquals(TextUtils.TruncateAt.END, host.headline.ellipsize)
            assertEquals(height, host.headline.layoutParams.height)
            host.headline.performClick()
            assertEquals(1, host.opened)
            assertEquals(0, host.articleMenus)
        }
    }

    @Test fun statusAndTranslationUpdatesDoNotResetAnActiveSelection() = withHeadline { host ->
        select(host)
        main {
            Selection.setSelection(host.headline.text as Spannable, 3, 12)
            host.article.updateStatus(host.row.copy(saved = true))
            host.article.updateStatus(host.row.copy(item = host.row.item.copy(translatedTitle = translated)))
            assertEquals(title, host.headline.text.toString())
            assertEquals(3, host.headline.selectionStart)
            assertEquals(12, host.headline.selectionEnd)
            host.headline.onTextContextMenuItem(android.R.id.copy)
            assertEquals(title.substring(3, 12), clipboard(host))
        }
        waitUntil { var done = false; main { done = host.headline.text.toString() == translated }; done }
    }

    @Test fun popupCopiesTheTitleItOpenedOnBeforeApplyingLateTranslation() = withHeadline { host ->
        main {
            host.headline.performLongClick()
            host.article.updateStatus(host.row.copy(item = host.row.item.copy(translatedTitle = translated)))
            assertEquals(title, host.headline.text.toString())
        }
        clickMenu(host, R.string.common_copy)
        main {
            assertEquals(title, clipboard(host))
            assertEquals(translated, host.headline.text.toString())
        }
    }

    @Test fun detachingSelectedRowCleansUpAndAnotherRowRemainsClickable() = withHeadline { host ->
        main { assertSame(TextClassifier.NO_OP, host.headline.textClassifier) }
        select(host)
        main {
            host.article.bind(host.row.copy(item = host.row.item.copy(key = "replacement", title = "另一条新闻")))
            assertFalse(host.headline.isTextSelectable)
            val next = host.article.findViewWithTag<AttentionHeadlineView>("attention-headline:replacement")
            next.performClick()
            assertEquals(1, host.opened)
            assertEquals("另一条新闻", next.text.toString())
        }
    }

    @Test fun expandedHeadlineRemainsExpandedAfterSelection() = withHeadline(expanded = true) { host ->
        select(host)
        main { host.headline.onTextContextMenuItem(android.R.id.copy) }
        waitUntil { var done = false; main { done = !host.headline.isTextSelectable }; done }
        main {
            assertEquals(Int.MAX_VALUE, host.headline.maxLines)
            assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, host.headline.layoutParams.height)
            assertEquals(View.VISIBLE, host.headline.visibility)
        }
    }

    @Test fun mergedMenuPreservesReadAndRelevanceActionsForTheCorrectArticle() = withHeadline { host ->
        main { host.headline.performLongClick() }
        clickMenu(host, R.string.attention_read)
        main { host.article.readable.performLongClick() }
        clickMenu(host, R.string.agent_global_feedback_not_relevant)
        main {
            assertEquals(listOf(host.row.item.key to AttentionHeadlineAction.READ,
                host.row.item.key to AttentionHeadlineAction.NOT_RELEVANT), host.feedback)
            assertEquals(0, host.opened)
        }
    }

    @Test fun repeatedSelectionAndRecyclingKeepsNativeCopyWithoutAsyncClassification() = withHeadline { host ->
        repeat(12) { index ->
            lateinit var current: Host
            main {
                host.article.bind(host.row)
                current = Host(host.activity, host.article,
                    host.article.findViewWithTag("attention-headline:${host.row.item.key}"), host.row)
                assertSame(TextClassifier.NO_OP, current.headline.textClassifier)
            }
            instrumentation.waitForIdleSync()
            select(current)
            main {
                Selection.setSelection(current.headline.text as Spannable, index, index + 2)
                current.headline.onTextContextMenuItem(android.R.id.copy)
                assertEquals(title.substring(index, index + 2), clipboard(current))
            }
            instrumentation.waitForIdleSync()
        }
    }
}
