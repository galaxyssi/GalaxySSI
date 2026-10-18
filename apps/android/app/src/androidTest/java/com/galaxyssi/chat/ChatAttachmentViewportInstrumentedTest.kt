package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ChatAttachmentViewportInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private class Rows : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        var ids = (1L..200L).toList()
        var attachmentHeight = 360
        init { setHasStableIds(true) }
        override fun getItemCount() = ids.size
        override fun getItemId(position: Int) = ids[position]
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            object : RecyclerView.ViewHolder(TextView(parent.context)) {}
        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            holder.itemView.layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                if (ids[position] >= 201L) attachmentHeight else 80)
            (holder.itemView as TextView).text = "Message ${ids[position]}"
        }
    }

    private fun withList(block: (RecyclerView, Rows, (Int) -> Unit) -> Unit) {
        instrumentation.runOnMainSync {
            val rows = Rows()
            val list = RecyclerView(instrumentation.targetContext).apply {
                layoutManager = ChatMessageLayoutManager(context) {}
                itemAnimator = null
                adapter = rows
                setPadding(0, 12, 0, 20)
            }
            fun place(height: Int) {
                list.measure(View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                list.layout(0, 0, 600, height)
            }
            try { place(800); block(list, rows, ::place) }
            finally { list.adapter = null; list.layoutManager = null }
        }
    }

    private fun pin(list: RecyclerView, place: (Int) -> Unit, height: Int = 800) {
        repeat(3) { alignChatViewportToLatest(list); place(height) }
        assertFalse("Latest message must remain visible", list.canScrollVertically(1))
        assertEquals(list.adapter!!.itemCount - 1,
            (list.layoutManager as LinearLayoutManager).findLastVisibleItemPosition())
    }

    @Test fun sendFileFromMiddleThenCollapseComposerPinsLatest() = withList { list, rows, place ->
        (list.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(73, -23)
        place(600)
        rows.ids = rows.ids + 201L
        rows.notifyItemInserted(200)
        pin(list, place, 600)
        place(800)
        pin(list, place)
    }

    @Test fun sendCameraImageThenDecodeLargerThumbnailKeepsBottom() = withList { list, rows, place ->
        pin(list, place)
        rows.ids = rows.ids + 201L
        rows.notifyItemInserted(200)
        pin(list, place)
        rows.attachmentHeight = 1300
        rows.notifyItemChanged(200)
        place(800)
        pin(list, place)
    }

    @Test fun foregroundReloadAtBottomSurvivesEmptyAdapter() = withList { list, rows, place ->
        pin(list, place)
        rows.ids = emptyList()
        rows.notifyDataSetChanged()
        place(800)
        rows.ids = (101L..200L).toList()
        rows.notifyDataSetChanged()
        place(800)
        pin(list, place)
    }

    @Test fun cancelPickerRestoresHistoricalMessageAndExactOffset() = withList { list, rows, place ->
        val layout = list.layoutManager as LinearLayoutManager
        layout.scrollToPositionWithOffset(73, -23)
        place(800)
        val id = rows.ids[layout.findFirstVisibleItemPosition()]
        val offset = layout.getDecoratedTop(layout.findViewByPosition(73)!!) - list.paddingTop
        rows.ids = emptyList()
        rows.notifyDataSetChanged()
        place(800)
        rows.ids = (24L..123L).toList()
        rows.notifyDataSetChanged()
        layout.scrollToPositionWithOffset(rows.ids.indexOf(id), offset)
        place(800)
        assertEquals(id, rows.ids[layout.findFirstVisibleItemPosition()])
        assertEquals(offset, layout.getDecoratedTop(layout.findViewByPosition(rows.ids.indexOf(id))!!) - list.paddingTop)
    }

    @Test fun incomingMessageDoesNotMoveHistoricalAnchor() = withList { list, rows, place ->
        val layout = list.layoutManager as LinearLayoutManager
        layout.scrollToPositionWithOffset(73, -23)
        place(800)
        val top = layout.findViewByPosition(73)!!.top
        rows.ids = rows.ids + 201L
        rows.notifyItemInserted(200)
        place(800)
        assertEquals(73, layout.findFirstVisibleItemPosition())
        assertEquals(top, layout.findViewByPosition(73)!!.top)
    }

    @Test fun shortConversationRemainsTopAligned() = withList { list, rows, place ->
        rows.ids = listOf(1, 2)
        rows.notifyDataSetChanged()
        place(800)
        pin(list, place)
        assertEquals(list.paddingTop, (list.layoutManager as LinearLayoutManager).findViewByPosition(0)!!.top)
    }

    @Test fun historicalReloadIsBoundedAndPaginatesBothDirections() = withDatabase { database ->
        seed(database)
        val sequence = database.page("desktop", pageSize = 600).messages
            .first { it.getLong("id") == 350L }.getLong(ChatHistoryDatabase.HISTORY_SEQUENCE)
        val page = database.viewportPage("desktop", sequence, 100)
        assertEquals((300L..399L).toList(), page.messages.map { it.getLong("id") })
        assertTrue(page.hasOlder)
        assertTrue(page.hasNewer)
        val before = database.page("desktop", page.oldestSequence, 100)
        val after = database.pageAfter("desktop", page.newestSequence!!, 100)
        assertEquals((200L..299L).toList(), before.messages.map { it.getLong("id") })
        assertEquals((400L..499L).toList(), after.messages.map { it.getLong("id") })
    }

    @Test fun latestReloadDoesNotIncludeUnrelatedContact() = withDatabase { database ->
        seed(database)
        val page = database.viewportPage("desktop", null, 100)
        assertEquals((501L..600L).toList(), page.messages.map { it.getLong("id") })
        assertFalse(page.hasNewer)
        assertTrue(page.hasOlder)
    }

    @Test fun deletedAnchorStillLoadsAdjacentHistory() = withDatabase { database ->
        seed(database)
        val sequence = database.page("desktop", pageSize = 600).messages
            .first { it.getLong("id") == 350L }.getLong(ChatHistoryDatabase.HISTORY_SEQUENCE)
        database.deleteMessage(350)
        val page = database.viewportPage("desktop", sequence, 100)
        assertEquals(100, page.messages.size)
        assertFalse(page.messages.any { it.getLong("id") == 350L })
        assertTrue(page.messages.any { it.getLong("id") == 351L })
    }

    private fun withDatabase(block: (ChatHistoryDatabase) -> Unit) {
        val context = instrumentation.targetContext
        val name = "viewport_${UUID.randomUUID()}.db"
        try { ChatHistoryDatabase(context, name).use(block) }
        finally { context.deleteDatabase(name) }
    }

    private fun seed(database: ChatHistoryDatabase) {
        database.upsertAll((1L..600L).flatMap { id ->
            listOf(JSONObject().put("id", id).put("contactId", "desktop").put("content", "message $id").put("timestamp", id),
                JSONObject().put("id", 1000 + id).put("contactId", "other").put("content", "other").put("timestamp", id))
        })
    }
}
