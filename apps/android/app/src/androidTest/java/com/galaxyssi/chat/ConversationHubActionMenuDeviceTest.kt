package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.res.Configuration
import android.graphics.Rect
import android.graphics.Typeface
import android.os.SystemClock
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class ConversationHubActionMenuDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private class State {
        val names = mutableListOf<String>()
        val completions = mutableListOf<(Boolean) -> Unit>()
        var pins = 0
        var deletes = 0
    }
    private class Host(val activity: ComposerEditingTestActivity, val root: FrameLayout,
        val anchor: LinearLayout, val menu: ConversationHubActionMenu, val state: State)
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun dialog(host: Host) = ConversationHubActionMenu::class.java.getDeclaredField("editor")
        .apply { isAccessible = true }.get(host.menu) as? AlertDialog
    private fun input(host: Host) = requireNotNull(dialog(host)).window!!.decorView.findViewWithTag<EditText>("conversation-rename-input")
    private fun action(host: Host, name: String) = host.menu.content.findViewWithTag<View>("conversation-action:$name")
    private fun openEditor(host: Host) {
        main { action(host, "RENAME").performClick() }
        instrumentation.waitForIdleSync()
        await { dialog(host)?.isShowing == true && input(host).selectionStart == 0 && input(host).selectionEnd == input(host).length() }
    }
    private fun await(ready: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5000
        do { var value = false; main { value = ready() }; if (value) return; SystemClock.sleep(40) }
        while (SystemClock.uptimeMillis() < deadline)
        fail("Conversation menu did not reach its expected state")
    }
    private fun withHost(title: String = "\u5468\u672b\u7814\u7a76\u8ba1\u5212", pinned: Boolean = false,
        contact: Boolean = false, readOnly: Boolean = false, bottom: Boolean = false,
        initialName: String = title,
        backend: ((String, (Boolean) -> Unit) -> Unit)? = null,
        test: (Host, ActivityScenario<ComposerEditingTestActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.setInTouchMode(true)
        ActivityScenario.launch(ComposerEditingTestActivity::class.java).use { screen ->
            lateinit var host: Host
            screen.onActivity { activity ->
                fun dp(value: Int) = (value * activity.resources.displayMetrics.density + .5f).toInt()
                activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                activity.window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
                val state = State()
                val root = FrameLayout(activity).apply {
                    setBackgroundColor(activity.getColor(R.color.page_bg)); setPadding(dp(16), dp(32), dp(16), dp(32))
                }
                root.addView(TextView(activity).apply {
                    text = activity.getString(R.string.conversation_hub_tab_conversations); textSize = 20f
                    setTypeface(typeface, Typeface.BOLD); gravity = Gravity.CENTER; setTextColor(activity.getColor(R.color.text_primary))
                }, FrameLayout.LayoutParams(-1, dp(56), Gravity.TOP))
                val anchor = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(4), dp(12), dp(4), dp(12))
                    addView(ImageView(activity).apply {
                        setImageResource(R.drawable.ic_agent_history)
                        imageTintList = android.content.res.ColorStateList.valueOf(activity.getColor(R.color.composer_send_icon))
                    }, LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginEnd = dp(12) })
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(TextView(activity).apply { text = title; textSize = 16f; maxLines = 2; setTextColor(activity.getColor(R.color.text_primary)) })
                        addView(TextView(activity).apply {
                            text = activity.getString(if (contact) R.string.conversation_action_contact else R.string.conversation_action_agent)
                            textSize = 13f; setTextColor(activity.getColor(R.color.text_secondary))
                        })
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }
                root.addView(anchor, FrameLayout.LayoutParams(-1, -2, if (bottom) Gravity.BOTTOM else Gravity.TOP).apply {
                    if (bottom) bottomMargin = dp(32) else topMargin = dp(100)
                })
                activity.setContentView(root)
                val save: ((String, (Boolean) -> Unit) -> Unit)? = if (readOnly) null else { name, done ->
                    state.names += name
                    if (backend == null) state.completions += done else backend(name, done)
                }
                val menu = ConversationHubActionMenu(activity, title, contact, pinned, save,
                    pin = { state.pins++ }, delete = { state.deletes++ }, initialName = initialName)
                anchor.setOnLongClickListener { menu.show(it); true }
                host = Host(activity, root, anchor, menu, state)
            }
            instrumentation.waitForIdleSync()
            main { host.activity.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                .hideSoftInputFromWindow(host.root.windowToken, 0) }
            instrumentation.waitForIdleSync()
            if (android.os.Build.VERSION.SDK_INT >= 30) await {
                host.activity.window.decorView.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime()) != true
            }
            main { assertTrue(host.anchor.performLongClick()) }
            await { host.menu.content.isShown && host.menu.content.width > 0 && host.menu.content.height > 0 }
            try { test(host, screen) } finally { main { host.menu.dismiss() } }
        }
    }
    private fun capture(host: Host, name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(150)
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            File(host.activity.getExternalFilesDir(null), "$name.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }; bitmap.recycle()
        }
    }

    @Test fun menuHasOrderedIconActionsAndAnAccessibleDestructiveSection() = withHost { host, _ ->
        main {
            val rows = (0 until host.menu.content.childCount).map(host.menu.content::getChildAt)
                .filter { it.tag?.toString()?.startsWith("conversation-action:") == true }
            assertEquals(listOf("conversation-action:RENAME", "conversation-action:PIN", "conversation-action:DELETE"), rows.map { it.tag })
            rows.forEach { row ->
                assertTrue(row.isFocusable); assertTrue(row.minimumHeight >= 48 * host.activity.resources.displayMetrics.density)
                assertFalse(row.contentDescription.isNullOrBlank())
                val group = row as ViewGroup
                assertTrue(group.getChildAt(0) is ImageView); assertTrue(group.getChildAt(1) is TextView)
            }
            val delete = views(rows.last()).filterIsInstance<TextView>().single()
            assertEquals(host.activity.getColor(R.color.conversation_action_destructive), delete.currentTextColor)
            assertEquals(host.activity.getString(R.string.agent_session_pin), rows[1].contentDescription)
        }
        capture(host, "conversation-actions-menu")
    }
    @Test fun destructiveTextHasReadableContrastInBothThemes() {
        listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES).forEach { mode ->
            val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
                uiMode = uiMode and Configuration.UI_MODE_NIGHT_MASK.inv() or mode
            }).resources
            assertTrue(ColorUtils.calculateContrast(resources.getColor(R.color.conversation_action_destructive, null),
                resources.getColor(R.color.surface_bg, null)) >= 4.5)
        }
    }
    @Test fun pinAndDeleteInvokeOnlyTheirSelectedAction() {
        listOf("PIN", "DELETE").forEach { choice -> withHost(pinned = true) { host, _ ->
            main {
                assertEquals(host.activity.getString(R.string.agent_session_unpin), action(host, "PIN").contentDescription)
                action(host, choice).performClick()
                assertEquals(if (choice == "PIN") 1 else 0, host.state.pins)
                assertEquals(if (choice == "DELETE") 1 else 0, host.state.deletes)
                assertTrue(host.state.names.isEmpty())
            }
            await { !host.menu.content.isShown }
        } }
    }
    @Test fun renamePrefillsSelectionAndRejectsBlankNamesWithoutSaving() = withHost { host, _ ->
        openEditor(host)
        main {
            val original = dialog(host)
            action(host, "RENAME").performClick()
            assertSame(original, dialog(host))
            val field = input(host)
            assertEquals(0, field.selectionStart); assertEquals(field.length(), field.selectionEnd)
            assertFalse(field.isSaveEnabled)
            assertTrue(field.imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING != 0)
            assertFalse(dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
            assertTrue(dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).alpha < 1f)
        }
        capture(host, "conversation-rename-editor")
        main {
            input(host).setText("   ")
            assertFalse(dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
            input(host).onEditorAction(EditorInfo.IME_ACTION_DONE)
            assertNotNull(input(host).error); assertTrue(host.state.names.isEmpty())
        }
    }
    @Test fun cancellingTheEditorDoesNotCommitAndClearsItsText() = withHost { host, _ ->
        openEditor(host)
        lateinit var field: EditText
        main {
            field = input(host); field.setText("Cancelled title")
            dialog(host)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        await { dialog(host) == null && field.text.isEmpty() }
        main { assertTrue(host.state.names.isEmpty()); assertEquals("", field.text.toString()) }
    }
    @Test fun savingTrimsTheNameAndPreventsDuplicateSubmissions() = withHost { host, _ ->
        openEditor(host)
        main {
            val field = input(host); field.setText("  Updated \ud83d\ude80  ")
            val save = dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE)
            save.performClick(); save.performClick()
            assertEquals(listOf("Updated \ud83d\ude80"), host.state.names)
            assertFalse(field.isEnabled); assertFalse(save.isEnabled)
            host.state.completions.single()(true)
            assertEquals("", field.text.toString()); assertNull(dialog(host))
        }
    }
    @Test fun failureKeepsTheDraftAndAnOlderCompletionCannotCloseARetry() = withHost { host, _ ->
        openEditor(host)
        main {
            input(host).setText("First attempt"); dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            host.state.completions[0](false)
            assertTrue(input(host).isEnabled); assertNotNull(input(host).error)
            input(host).setText("Second attempt"); dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            host.state.completions[0](true)
            assertTrue(dialog(host)!!.isShowing); assertFalse(input(host).isEnabled)
            host.state.completions[1](true)
            assertNull(dialog(host)); assertEquals(listOf("First attempt", "Second attempt"), host.state.names)
        }
    }
    @Test fun displayStatusIsNotCopiedIntoTheEditableName() = withHost(title = "Research plan - paused", initialName = "Research plan") { host, _ ->
        openEditor(host)
        main {
            assertEquals("Research plan", input(host).text.toString())
            input(host).setText("Updated plan"); dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            assertEquals(listOf("Updated plan"), host.state.names)
            host.state.completions.single()(true)
        }
    }
    @Test fun contactRenameUsesTheLocalRemarkEditorAndReadOnlyRowsKeepTheirOtherActions() {
        withHost(contact = true) { host, _ ->
            openEditor(host)
            main {
                assertEquals(host.activity.getString(R.string.contact_remark_name), input(host).hint.toString())
                input(host).setText("Local remark"); dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                host.state.completions.single()(true); assertEquals(listOf("Local remark"), host.state.names)
            }
        }
        withHost(contact = true, readOnly = true) { host, _ -> main {
            assertNull(host.menu.content.findViewWithTag<View>("conversation-action:RENAME"))
            assertNotNull(action(host, "PIN")); assertNotNull(action(host, "DELETE"))
        } }
    }
    @Test fun menuNearTheBottomStaysInsideTheVisibleFrameWithALongTitle() = withHost(title = "Long conversation title ".repeat(8), bottom = true) { host, _ ->
        main {
            val frame = Rect().also(host.anchor::getWindowVisibleDisplayFrame)
            val location = IntArray(2).also(host.menu.content::getLocationOnScreen)
            assertTrue(location[0] >= frame.left); assertTrue(location[1] >= frame.top)
            assertTrue(location[0] + host.menu.content.width <= frame.right)
            assertTrue(location[1] + host.menu.content.height <= frame.bottom)
            assertTrue(host.menu.content.findViewWithTag<TextView>("conversation-action-title").lineCount <= 2)
        }
    }
    @Test fun rebindingTheSourceRowDoesNotDiscardAnOpenRenameDraft() = withHost { host, _ ->
        openEditor(host)
        main {
            input(host).setText("Keep this draft")
            host.root.removeView(host.anchor)
            assertTrue(dialog(host)!!.isShowing); assertEquals("Keep this draft", input(host).text.toString())
            assertTrue(host.state.names.isEmpty())
        }
    }
    @Test fun backgroundingDismissesBothMenuAndEditorWithoutSaving() {
        listOf(false, true).forEach { editing -> withHost { host, screen ->
            var held: EditText? = null
            if (editing) { openEditor(host); main { held = input(host); held!!.setText("Private draft") } }
            screen.moveToState(Lifecycle.State.CREATED)
            main {
                assertFalse(host.menu.content.isShown); assertNull(dialog(host)); assertTrue(host.state.names.isEmpty())
                held?.let { assertEquals("", it.text.toString()) }
            }
            screen.moveToState(Lifecycle.State.RESUMED)
            main { assertFalse(host.menu.content.isShown); assertNull(dialog(host)) }
        } }
    }
    @Test fun sameNamedConversationsKeepTheirIdentityMetadataAndStoredPreview() {
        val name = "conversation-menu-test-${UUID.randomUUID()}.db"
        try {
            val first = AgentConversation(UUID.randomUUID().toString(), "Same title", 1000, 2000,
                selectedModelOrAgent = "Codex", summary = "Isolated summary", pinned = true, privateMode = true,
                latestMessageIndexed = true, latestMessageEntryId = "synthetic-entry", latestMessagePreview = "Isolated message", latestMessageTimestampMillis = 2000)
            val other = first.copy(id = UUID.randomUUID().toString())
            AgentConversationDatabase(context, name).use { db ->
                assertTrue(db.insertIfAbsent(first)); assertTrue(db.insertIfAbsent(other))
                withHost(title = first.title, backend = { value, done -> done(db.upsert(requireNotNull(db.read(first.id)).copy(title = value))) }) { host, _ ->
                    openEditor(host)
                    main {
                        input(host).setText("Renamed title")
                        dialog(host)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); assertNull(dialog(host))
                    }
                }
                assertEquals(first.copy(title = "Renamed title"), db.read(first.id)); assertEquals(other, db.read(other.id))
            }
            AgentConversationDatabase(context, name).use { assertEquals("Renamed title", it.read(first.id)?.title) }
        } finally { context.deleteDatabase(name) }
    }
    @Test fun backClosesOnlyTheMenuAndDoesNotInvokeAnAction() = withHost { host, _ ->
        instrumentation.waitForIdleSync(); SystemClock.sleep(150)
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        await { !host.menu.content.isShown }
        main { assertFalse(host.activity.isFinishing); assertEquals(0, host.state.pins + host.state.deletes); assertTrue(host.state.names.isEmpty()) }
    }
}
