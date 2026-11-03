package com.galaxyssi.chat

import android.graphics.Rect
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.galaxyssi.chat.ui.ParagraphSelectingTextView

/** Only empty output space is a stop target; media, links and controls keep their gestures. */
internal object AgentReplySpeechTouchTarget {
    fun blankTapListener(root: RecyclerView, onBlankTap: () -> Boolean): RecyclerView.OnItemTouchListener {
        var blankDownTime: Long? = null
        val detector = GestureDetector(root.context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean {
                blankDownTime = event.downTime.takeIf { isBlank(root, event.rawX, event.rawY) }
                return true
            }

            override fun onSingleTapConfirmed(event: MotionEvent): Boolean =
                blankDownTime == event.downTime && isBlank(root, event.rawX, event.rawY) && onBlankTap()
        })
        return object : RecyclerView.SimpleOnItemTouchListener() {
            override fun onInterceptTouchEvent(recyclerView: RecyclerView, event: MotionEvent): Boolean {
                detector.onTouchEvent(event)
                return false
            }
        }
    }

    fun isBlank(root: View, rawX: Float, rawY: Float): Boolean {
        val windowOrigin = IntArray(2)
        root.rootView.getLocationOnScreen(windowOrigin)
        fun occupied(view: View): Boolean {
            val bounds = Rect()
            if (!view.isShown || !view.getGlobalVisibleRect(bounds)) return false
            // Global visible rectangles are window-root-relative, including in dialogs.
            bounds.offset(windowOrigin[0], windowOrigin[1])
            if (!bounds.contains(rawX.toInt(), rawY.toInt())) return false
            if (view is WebView || view is ImageView) return true
            if (view is ParagraphSelectingTextView) {
                val location = IntArray(2)
                view.getLocationOnScreen(location)
                return view.hasTextAt(rawX - location[0], rawY - location[1])
            }
            if (view is TextView && view.text.isNotBlank()) return true
            if (view !== root && (view.isClickable || view.isLongClickable)) return true
            if (view is ViewGroup) for (index in view.childCount - 1 downTo 0) {
                if (occupied(view.getChildAt(index))) return true
            }
            return false
        }
        return !occupied(root)
    }
}
