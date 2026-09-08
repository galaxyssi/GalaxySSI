package com.galaxyssi.chat

import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.Assume.assumeTrue
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ChatMessageViewportDeviceTest {
    @Test fun existingShortContactChatIsTopAligned() {
        val name = InstrumentationRegistry.getArguments().getString("contactName").orEmpty()
        assumeTrue("Explicit contactName is required for read-only real-history inspection", name.isNotBlank())
        check(Build.MODEL == "SM-T575")
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val contact = activity.storedContacts().first { it.name == name }
                activity.showChatPage(contact)
            }
            val deadline = SystemClock.elapsedRealtime() + 15_000
            var loaded = false
            while (!loaded && SystemClock.elapsedRealtime() < deadline) {
                scenario.onActivity { activity ->
                    loaded = (activity.messageList.adapter?.itemCount ?: 0) > 0 &&
                        activity.messageList.childCount > 0 && !activity.messageList.isLayoutRequested
                }
                if (!loaded) SystemClock.sleep(100)
            }
            assertTrue("Existing history must load", loaded)
            scenario.onActivity { activity ->
                val list = activity.messageList
                val layout = list.layoutManager as LinearLayoutManager
                assertFalse("This acceptance contact must fit on one screen", list.canScrollVertically(-1))
                assertFalse("This acceptance contact must fit on one screen", list.canScrollVertically(1))
                assertEquals(0, layout.findFirstVisibleItemPosition())
                assertEquals(list.paddingTop, layout.getDecoratedTop(layout.findViewByPosition(0)!!))
                val result = android.os.Bundle().apply { putString("contactId", activity.selectedContact!!.id) }
                InstrumentationRegistry.getInstrumentation().sendStatus(0, result)
            }
        }
    }

    private fun verify(count: Int, assertions: (RecyclerView, LinearLayoutManager) -> Unit) {
        check(Build.MODEL == "SM-T575") { "Run this acceptance test only on SM-T575" }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val layout = LinearLayoutManager(context).apply {
                stackFromEnd = ChatMessageViewportPolicy.stackFromEnd()
                reverseLayout = false
            }
            val list = RecyclerView(context).apply {
                layoutManager = layout
                itemAnimator = null
                adapter = object : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
                    override fun getItemCount() = count
                    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder =
                        object : RecyclerView.ViewHolder(TextView(context).apply {
                            layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 80)
                        }) {}
                    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
                        (holder.itemView as TextView).text = position.toString()
                    }
                }
            }
            fun place() {
                list.measure(View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY))
                list.layout(0, 0, 600, 800)
            }
            place()
            // Reproduce the contact page's existing latest-message navigation.
            layout.scrollToPositionWithOffset(count - 1, 0)
            place()
            assertions(list, layout)
            list.adapter = null
            list.layoutManager = null
        }
    }

    @Test fun shortChatStartsAtTopInChronologicalOrder() = verify(2) { _, layout ->
        assertEquals(0, layout.findFirstVisibleItemPosition())
        assertEquals(0, layout.findViewByPosition(0)!!.top)
        assertEquals(80, layout.findViewByPosition(1)!!.top)
    }

    @Test fun longChatStillOpensAtLatestMessage() = verify(100) { list, layout ->
        assertEquals(99, layout.findLastVisibleItemPosition())
        assertTrue(layout.findViewByPosition(99)!!.bottom <= list.height)
        assertFalse(layout.reverseLayout)
    }
}
