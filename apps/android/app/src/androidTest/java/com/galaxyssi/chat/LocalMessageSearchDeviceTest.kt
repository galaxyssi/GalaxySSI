package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.EditText
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class LocalMessageSearchDeviceTest {
    @get:org.junit.Rule val permissions = ViewportNoPermissionPromptRule()
    private val ctx get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun deepChunkAttachmentAndPrivateBoundariesUseTheOriginalEncryptedRows() {
        val store = AgentTranscriptStore(ctx)
        val old = store.activeConversation().id
        val created = mutableListOf<String>()
        val token = "needle-" + UUID.randomUUID()
        try {
            val chat = store.createConversation("Search fixture").id.also(created::add)
            repeat(24) { store.append(AgentTranscriptRole.USER, "Earlier fixture $it", conversationId = chat) }
            val huge = "x".repeat(8190) + token + "y".repeat(9500)
            assertTrue(store.append(AgentTranscriptRole.USER, huge, conversationId = chat))
            assertTrue(store.append(AgentTranscriptRole.ASSISTANT, "Attached fixture", conversationId = chat,
                richOutputJson = AgentRichContentCodec.encode(listOf(AgentRichBlock("f", AgentRichBlockType.FILE, title = "$token.pdf")))))
            repeat(60) { store.append(AgentTranscriptRole.USER, "Later fixture $it", conversationId = chat) }
            for (scope in listOf("private", "health", "paused")) {
                val id = store.createConversation("Excluded fixture", privateMode = scope == "private").id.also(created::add)
                assertTrue(store.append(AgentTranscriptRole.USER, token, conversationId = id))
                if (scope == "health") assertTrue(store.bindGlobalTopic(id, "health:test:$token"))
                if (scope == "paused") assertTrue(store.setTrackingPaused(id, true))
            }
            val hits = LocalMessageSearch.scan(ctx, token, false) { false }.toList()
            assertEquals(2, hits.size)
            assertTrue(hits.all { it.owner == chat && it.snippet.contains(token) })
            val text = hits.single { !it.filename }
            val file = hits.single { it.filename }
            val page = requireNotNull(text.contextPage(ctx))
            assertEquals(huge, page.lines.single { it.id == text.message }.text)
            assertEquals(listOf("$token.pdf"), page.lines.single { it.id == file.message }.files)
            assertNotNull(page.older); assertNotNull(page.newer)
            assertTrue(requireNotNull(text.contextPage(ctx, older = page.older)).lines.none { l -> page.lines.any { it.id == l.id } })
            assertTrue(requireNotNull(text.contextPage(ctx, newer = page.newer)).lines.none { l -> page.lines.any { it.id == l.id } })
            assertTrue(store.setPrivateMode(chat, true))
            assertNull(text.contextPage(ctx))
        } finally { store.switchConversation(old); created.forEach(store::deleteConversation) }
    }

    @Test fun returningFromTheOriginalMessageKeepsTheQueryAndResultPosition() {
        val store = AgentTranscriptStore(ctx)
        val old = store.activeConversation().id
        val token = "local-" + UUID.randomUUID().toString().take(8)
        val chat = store.createConversation("Reader fixture").id
        try {
            repeat(40) { store.append(AgentTranscriptRole.USER, "$token source row $it", conversationId = chat) }
            store.switchConversation(old)
            ActivityScenario.launch(MainActivity::class.java).use { screen ->
                screen.onActivity { it.showAgentSessionsPage() }
                lateinit var input: EditText
                lateinit var list: RecyclerView
                fun until(label: String, test: (MainActivity) -> Boolean) {
                    val end = SystemClock.elapsedRealtime() + 18000
                    do {
                        var ok = false; screen.onActivity { ok = test(it) }
                        if (ok) return
                        SystemClock.sleep(65)
                    } while (SystemClock.elapsedRealtime() < end)
                    fail(label)
                }
                until("Open the hub search") { a ->
                    val root = a.agentSessionsDialog?.window?.decorView ?: return@until false
                    val children = views(root)
                    val search = children.firstOrNull { it.contentDescription == a.getString(R.string.conversation_hub_search_hint) }
                        ?: return@until false
                    input = children.filterIsInstance<EditText>().first()
                    list = children.filterIsInstance<RecyclerView>().first()
                    search.performClick(); input.setText(token); true
                }
                val lm = list.layoutManager as LinearLayoutManager
                val adapter = list.adapter as ConversationHubListAdapter
                until("Full result page") { adapter.currentList.filterIsInstance<ConversationHubRow.Message>().size >= 20 }
                screen.onActivity { lm.scrollToPositionWithOffset(9, -7) }
                lateinit var hit: LocalMessageHit
                var start = -1; var offset = 0
                until("The selected original row is visible") {
                    start = lm.findFirstVisibleItemPosition()
                    if (start != 9) return@until false
                    offset = lm.findViewByPosition(start)!!.top
                    val index = start + 1
                    hit = (adapter.currentList[index] as ConversationHubRow.Message).hit
                    views(lm.findViewByPosition(index)!!).firstOrNull { it.isClickable }?.performClick() == true
                }
                until("The reader displays the original message, not the last turn") { a ->
                    val root = WindowInspector.getGlobalWindowViews().firstOrNull { r ->
                        views(r).any { it is TextView && it.tag == hit.message && it.isShown && it.text.contains(token) }
                    } ?: return@until false
                    views(root).single { it.contentDescription == a.getString(R.string.chat_search_back) }.performClick()
                }
                until("Return to the same result and pixel offset") { a ->
                    input.text.toString() == token && a.agentSessionsDialog?.window?.decorView?.hasWindowFocus() == true &&
                        lm.findFirstVisibleItemPosition() == start && lm.findViewByPosition(start)?.top == offset
                }
                assertEquals(old, store.activeConversation().id)
            }
        } finally { store.switchConversation(old); store.deleteConversation(chat) }
    }

    private fun views(v: View): List<View> = listOf(v) + if (v is ViewGroup)
        (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()
}
