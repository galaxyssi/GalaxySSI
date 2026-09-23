package com.galaxyssi.chat

import android.app.Dialog
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class ConversationHubBackgroundRestoreDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun visibleListRestoresMiddleAnchorAfterBackground() = withActivity { activity ->
        val (dialog, list) = openList(activity)
        val before = scrollToMiddle(activity, list)
        background(activity)
        onMain {
            assertTrue(activity.runtimePlaintextCleared)
            assertFalse(dialog.isShowing)
            assertNull(activity.agentSessionsDialog)
            assertNull(activity.captureConversationHubNavigation)
            assertEquals(before.anchor?.stableRowId, activity.suspendedConversationHub?.anchor?.stableRowId)
        }
        foreground(activity)
        await("List did not automatically restore") { activity.agentSessionsDialog?.isShowing == true }
        assertRestored(activity, before)
    }

    @Test fun hiddenListDoesNotReplaceConversationButRestoresOnReturn() = withActivity { activity ->
        val (dialog, list) = openList(activity)
        val before = scrollToMiddle(activity, list)
        onMain {
            val layout = list.layoutManager as LinearLayoutManager
            val adapter = list.adapter as ConversationHubListAdapter
            val position = (layout.findFirstVisibleItemPosition()..layout.findLastVisibleItemPosition()).first { i ->
                (adapter.currentList.getOrNull(i) as? ConversationHubRow.Conversation)?.item?.let {
                    it.kind == ConversationHubItemKind.AGENT && it.agentStatus == ConversationHubAgentStatus.READ
                } == true
            }
            assertTrue(clickable(requireNotNull(layout.findViewByPosition(position)))!!.performClick())
        }
        await("List did not hide") { !dialog.isShowing }
        background(activity)
        foreground(activity)
        onMain { assertNull(activity.agentSessionsDialog); activity.showAgentSessionsPage() }
        assertRestored(activity, before)
    }

    @Test fun explicitlyDismissedListDoesNotReopen() = withActivity { activity ->
        val (dialog, _) = openList(activity)
        onMain { dialog.dismiss() }
        await("Dialog dismissal did not clear references") { activity.agentSessionsDialog == null }
        background(activity)
        foreground(activity)
        onMain { assertNull(activity.agentSessionsDialog); assertNull(activity.suspendedConversationHub) }
    }

    @Test fun contactsTabRestoresWithoutChangingTab() = withActivity { activity ->
        onMain { activity.showConversationHub(ConversationHubTab.CONTACTS) }
        await("Contacts did not open") { activity.agentSessionsDialog?.isShowing == true }
        background(activity)
        foreground(activity)
        await("Contacts did not restore") { activity.agentSessionsDialog?.isShowing == true }
        onMain { assertEquals(ConversationHubTab.CONTACTS, activity.captureConversationHubNavigation?.invoke()?.tab) }
    }

    private fun openList(activity: MainActivity): Pair<Dialog, RecyclerView> {
        onMain { activity.showAgentSessionsPage() }
        var dialog: Dialog? = null
        var list: RecyclerView? = null
        await("List did not load") {
            dialog = activity.agentSessionsDialog
            list = dialog?.window?.decorView?.let(::recycler)
            (list?.adapter as? ConversationHubListAdapter)?.currentList?.count { it is ConversationHubRow.Conversation }?.let { it >= 12 } == true
        }
        return requireNotNull(dialog) to requireNotNull(list)
    }

    private fun scrollToMiddle(activity: MainActivity, list: RecyclerView): ConversationHubNavigationState {
        onMain { (list.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(8, 25) }
        instrumentation.waitForIdleSync()
        var result: ConversationHubNavigationState? = null
        await("Middle row not visible") {
            result = activity.captureConversationHubNavigation?.invoke()
            (result?.anchor?.position ?: 0) >= 7
        }
        return requireNotNull(result)
    }

    private fun assertRestored(activity: MainActivity, before: ConversationHubNavigationState) {
        await("Scroll anchor was not restored") {
            val list = activity.agentSessionsDialog?.window?.decorView?.let(::recycler)
            val layout = list?.layoutManager as? LinearLayoutManager
            val position = layout?.findFirstVisibleItemPosition() ?: -1
            val row = (list?.adapter as? ConversationHubListAdapter)?.currentList?.getOrNull(position)
            val top = layout?.findViewByPosition(position)?.top
            row?.stableId == before.anchor?.stableRowId && top != null &&
                kotlin.math.abs(top - (list?.paddingTop ?: 0) - (before.anchor?.topOffset ?: 0)) <= 2
        }
    }

    private fun background(activity: MainActivity) {
        instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_HOME").close()
        await("Activity did not clear runtime plaintext") { activity.runtimePlaintextCleared }
    }

    private fun foreground(activity: MainActivity) {
        onMain {
            activity.startActivity(Intent(activity, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
        }
        await("Activity did not resume") { !activity.runtimePlaintextCleared }
        instrumentation.waitForIdleSync()
    }

    private fun withActivity(block: (MainActivity) -> Unit) {
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        var original = ""
        try {
            await("Initial hydration did not finish") { !activity.initialAgentHydrationPending }
            original = activity.agentTranscriptStore.activeConversation().id
            block(activity)
        } finally {
            onMain {
                activity.agentSessionsDialog?.dismiss()
                activity.suspendedConversationHub = null
                activity.restoreHiddenConversationHub = null
                if (original.isNotBlank()) activity.agentTranscriptStore.switchConversation(original)
                activity.finish()
            }
        }
    }

    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)
    private fun await(message: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            onMain { ready = predicate() }
            if (ready) return
            SystemClock.sleep(50)
        }
        throw AssertionError(message)
    }
    private fun recycler(view: View): RecyclerView? = if (view is RecyclerView) view else
        if (view is ViewGroup) (0 until view.childCount).firstNotNullOfOrNull { recycler(view.getChildAt(it)) } else null
    private fun clickable(view: View): View? = if (view.isClickable) view else
        if (view is ViewGroup) (0 until view.childCount).firstNotNullOfOrNull { clickable(view.getChildAt(it)) } else null
}
