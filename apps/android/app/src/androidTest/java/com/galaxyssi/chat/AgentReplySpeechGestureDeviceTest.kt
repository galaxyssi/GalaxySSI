package com.galaxyssi.chat

import android.app.Dialog
import android.os.SystemClock
import android.text.Selection
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
import org.junit.Assert.*
import org.junit.Test

class AgentReplySpeechGestureDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private class Fixture(val list: RecyclerView, val text: ParagraphSelectingTextView, val image: ImageView,
        val button: Button) {
        var stopped = 0
        var played = 0
        var clicked = 0
        var menus = 0
    }

    @Test fun doubleTapReadsTheParagraphWithoutNativeCopyMenu() = fixture { f ->
        point(f.text, 20f, 20f).let { (x, y) -> tap(x, y); SystemClock.sleep(70); tap(x, y) }
        SystemClock.sleep(400)
        assertEquals(1, f.played)
        assertEquals(0, f.stopped)
        assertEquals(0, f.menus)
        assertEquals(-1, Selection.getSelectionStart(f.text.text))
    }

    @Test fun blankSingleTapStopsButTextAndControlsDoNot() = fixture { f ->
        point(f.text, 20f, 20f).let { (x, y) -> tap(x, y) }
        SystemClock.sleep(350)
        assertEquals("Text tap must not stop speech", 0, f.stopped)
        point(f.button, 20f, 20f).let { (x, y) -> tap(x, y) }
        SystemClock.sleep(350)
        assertEquals("Control tap must not stop speech", 0, f.stopped)
        point(f.image, 20f, 20f).let { (x, y) -> tap(x, y) }
        SystemClock.sleep(350)
        assertEquals(0, f.stopped)
        assertEquals(2, f.clicked)
        point(f.list, f.list.width - 30f, f.list.height - 120f).let { (x, y) -> tap(x, y) }
        SystemClock.sleep(350)
        assertEquals(1, f.stopped)
        assertEquals(0, f.played)
    }

    @Test fun emptySpaceAfterTheTextLineIsAlsoAStopTarget() = fixture { f ->
        point(f.text, f.text.width - 25f, 25f).let { (x, y) -> tap(x, y) }
        SystemClock.sleep(350)
        assertEquals(1, f.stopped)
        assertEquals(0, f.played)
    }

    @Test fun draggingAndHoldingBlankSpaceNeverStopPlayback() = fixture { f ->
        val (x, y) = point(f.list, f.list.width - 30f, f.list.height - 200f)
        val down = SystemClock.uptimeMillis()
        event(down, MotionEvent.ACTION_DOWN, x, y)
        SystemClock.sleep(40)
        event(down, MotionEvent.ACTION_MOVE, x, y - 100f)
        event(down, MotionEvent.ACTION_UP, x, y - 100f)
        SystemClock.sleep(350)
        val hold = SystemClock.uptimeMillis()
        event(hold, MotionEvent.ACTION_DOWN, x, y)
        SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 100)
        event(hold, MotionEvent.ACTION_UP, x, y)
        SystemClock.sleep(350)
        assertEquals(0, f.stopped)
        assertEquals(0, f.played)
    }

    @Test fun longPressKeepsSelectionWithoutStartingOrStoppingSpeech() = fixture { f ->
        val (x, y) = point(f.text, 20f, 20f)
        val down = SystemClock.uptimeMillis()
        event(down, MotionEvent.ACTION_DOWN, x, y)
        SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 150)
        event(down, MotionEvent.ACTION_UP, x, y)
        SystemClock.sleep(350)
        assertEquals(0, f.played)
        assertEquals(0, f.stopped)
        assertTrue(Selection.getSelectionStart(f.text.text) >= 0)
    }

    @Test fun holdingOrDraggingTheSecondTapDoesNotStartSpeech() = fixture { f ->
        val (x, y) = point(f.text, 20f, 20f)
        tap(x, y)
        SystemClock.sleep(70)
        val down = SystemClock.uptimeMillis()
        event(down, MotionEvent.ACTION_DOWN, x, y)
        SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 100)
        event(down, MotionEvent.ACTION_UP, x, y)
        SystemClock.sleep(350)
        tap(x, y)
        SystemClock.sleep(70)
        val drag = SystemClock.uptimeMillis()
        event(drag, MotionEvent.ACTION_DOWN, x, y)
        event(drag, MotionEvent.ACTION_MOVE, x + 120f, y + 80f)
        event(drag, MotionEvent.ACTION_UP, x + 120f, y + 80f)
        SystemClock.sleep(350)
        assertEquals(0, f.played)
        assertEquals(0, f.stopped)
    }

    private fun fixture(check: (Fixture) -> Unit) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var dialog: Dialog
            lateinit var f: Fixture
            scenario.onActivity { activity ->
                val text = ParagraphSelectingTextView(activity).apply {
                    this.text = "第一段内容。\n第二段内容。"
                    textSize = 16f
                    setPadding(16, 16, 16, 16)
                    exclusiveParagraphDoubleTap = true
                    setTextClassifier(android.view.textclassifier.TextClassifier.NO_OP)
                }
                val image = ImageView(activity).apply { setBackgroundColor(android.graphics.Color.BLUE) }
                val button = Button(activity).apply { this.text = "Control" }
                val row = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(text, LinearLayout.LayoutParams(-1, 220))
                    addView(image, LinearLayout.LayoutParams(-1, 100))
                    addView(button, LinearLayout.LayoutParams(-1, 100))
                    layoutParams = RecyclerView.LayoutParams(-1, 800)
                }
                val list = RecyclerView(activity).apply {
                    layoutManager = LinearLayoutManager(activity)
                    adapter = object : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
                        override fun onCreateViewHolder(parent: ViewGroup, type: Int) = object : RecyclerView.ViewHolder(row) {}
                        override fun getItemCount() = 1
                        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) = Unit
                    }
                }
                f = Fixture(list, text, image, button)
                text.setOnParagraphDoubleTapListener { f.played++ }
                text.customSelectionActionModeCallback = object : ActionMode.Callback {
                    override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean { f.menus++; return true }
                    override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
                    override fun onActionItemClicked(mode: ActionMode, item: MenuItem) = false
                    override fun onDestroyActionMode(mode: ActionMode) = Unit
                }
                image.setOnClickListener { f.clicked++ }
                button.setOnClickListener { f.clicked++ }
                list.addOnItemTouchListener(AgentReplySpeechTouchTarget.blankTapListener(list) { f.stopped++; true })
                dialog = Dialog(activity).apply {
                    setContentView(list); show()
                    window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
            instrumentation.waitForIdleSync()
            val deadline = SystemClock.elapsedRealtime() + 5000
            var ready = false
            while (!ready && SystemClock.elapsedRealtime() < deadline) {
                instrumentation.runOnMainSync { ready = f.text.layout != null && f.text.width > 0 && f.list.height > 0 }
                if (!ready) SystemClock.sleep(50)
            }
            assertTrue("Gesture fixture must be laid out", ready)
            try { check(f) } finally { scenario.onActivity { dialog.dismiss() } }
        }
    }

    private fun point(view: View, x: Float, y: Float): Pair<Float, Float> {
        val location = IntArray(2)
        instrumentation.runOnMainSync { view.getLocationOnScreen(location) }
        return location[0] + x to location[1] + y
    }

    private fun tap(x: Float, y: Float) {
        val down = SystemClock.uptimeMillis()
        event(down, MotionEvent.ACTION_DOWN, x, y)
        SystemClock.sleep(40)
        event(down, MotionEvent.ACTION_UP, x, y)
    }

    private fun event(down: Long, action: Int, x: Float, y: Float) {
        val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0).apply {
            source = android.view.InputDevice.SOURCE_TOUCHSCREEN
        }
        try { assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true)) } finally { event.recycle() }
    }
}
