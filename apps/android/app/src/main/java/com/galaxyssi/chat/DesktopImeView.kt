package com.galaxyssi.chat

import android.content.Context
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection

/** A local IME endpoint, not a second copy of the remote document. */
internal class DesktopImeView(context: Context) : View(context) {
    var password = false
    var onCommit: (String) -> Unit = {}
    var onKey: (String) -> Unit = {}
    private var connection: RemoteConnection? = null

    init { isFocusable = true; isFocusableInTouchMode = true }
    override fun onCheckIsTextEditor() = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or if (password) {
            InputType.TYPE_TEXT_VARIATION_PASSWORD
        } else InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or
            EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or EditorInfo.IME_ACTION_NONE
        outAttrs.initialSelStart = 0
        outAttrs.initialSelEnd = 0
        return RemoteConnection().also { connection = it }
    }

    fun discardComposition() { connection?.discard(); connection = null }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = handleKey(event) || super.onKeyDown(keyCode, event)

    private fun handleKey(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return true
        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_DEL -> "backspace"
            KeyEvent.KEYCODE_FORWARD_DEL -> "delete"
            KeyEvent.KEYCODE_ENTER -> "enter"
            KeyEvent.KEYCODE_TAB -> "tab"
            KeyEvent.KEYCODE_DPAD_LEFT -> "left"
            KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
            KeyEvent.KEYCODE_DPAD_UP -> "up"
            KeyEvent.KEYCODE_DPAD_DOWN -> "down"
            else -> null
        }
        if (key != null) { onKey(key); return true }
        if (event.unicodeChar in 1..Character.MAX_CODE_POINT) {
            onCommit(String(Character.toChars(event.unicodeChar))); return true
        }
        return false
    }

    private inner class RemoteConnection : BaseInputConnection(this@DesktopImeView, false) {
        private var composing = ""
        fun discard() { composing = "" }
        override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
            composing = text?.toString().orEmpty()
            return true
        }
        override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
            composing = ""
            text?.toString()?.takeIf { it.isNotEmpty() }?.let(onCommit)
            return true
        }
        override fun finishComposingText(): Boolean {
            val value = composing
            composing = ""
            if (value.isNotEmpty()) onCommit(value)
            return true
        }
        override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
            if (composing.isNotEmpty()) {
                composing = composing.dropLast(beforeLength.coerceAtLeast(0))
            } else {
                repeat(beforeLength.coerceIn(0, 64)) { onKey("backspace") }
                repeat(afterLength.coerceIn(0, 64)) { onKey("delete") }
            }
            return true
        }
        override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int) =
            deleteSurroundingText(beforeLength, afterLength)
        override fun sendKeyEvent(event: KeyEvent) = handleKey(event)
        override fun performEditorAction(editorAction: Int): Boolean { onKey("enter"); return true }
        override fun getTextBeforeCursor(n: Int, flags: Int): CharSequence = composing.takeLast(n.coerceAtLeast(0))
        override fun getTextAfterCursor(n: Int, flags: Int): CharSequence = ""
        override fun closeConnection() { discard() }
    }
}
