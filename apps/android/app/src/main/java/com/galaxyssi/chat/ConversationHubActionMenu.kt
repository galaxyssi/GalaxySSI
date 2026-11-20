package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.Application
import android.content.res.ColorStateList
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Build
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView

/** A row-scoped menu; selection is identified by the caller, never by the visible title. */
internal class ConversationHubActionMenu(
    private val activity: Activity,
    title: String,
    private val contact: Boolean,
    pinned: Boolean,
    private val rename: ((String, (Boolean) -> Unit) -> Unit)?,
    pin: () -> Unit,
    delete: () -> Unit,
    initialName: String = title
) : Application.ActivityLifecycleCallbacks {
    private var currentName = initialName
    private var closed = false
    private var editing = false
    private var saving = false
    private var owner: View? = null
    private var editor: AlertDialog? = null
    private var input: EditText? = null
    private val popup = PopupWindow(activity)
    private val heading = label(title, 14f).apply {
        tag = "conversation-action-title"; maxLines = 2; ellipsize = TextUtils.TruncateAt.END
        setTypeface(typeface, Typeface.BOLD)
    }
    val content = LinearLayout(activity).apply {
        tag = "conversation-action-menu"; orientation = LinearLayout.VERTICAL
        setPadding(dp(4), dp(4), dp(4), dp(4))
        contentDescription = activity.getString(R.string.conversation_action_menu)
    }
    private val detached = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) = Unit
        override fun onViewDetachedFromWindow(view: View) { dismiss() }
    }

    init {
        content.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(8), 0, dp(8))
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(heading)
                addView(label(activity.getString(if (contact) R.string.conversation_action_contact else R.string.conversation_action_agent), 12f).apply {
                    setTextColor(activity.getColor(R.color.text_secondary)); setPadding(0, dp(4), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ImageButton(activity).apply {
                tag = "conversation-action-close"; setImageResource(R.drawable.ic_agent_progress_close)
                imageTintList = ColorStateList.valueOf(activity.getColor(R.color.text_secondary))
                contentDescription = activity.getString(R.string.common_cancel); tooltipText = contentDescription
                background = selectable(); setPadding(dp(14), dp(14), dp(14), dp(14))
                setOnClickListener { dismiss() }
            }, LinearLayout.LayoutParams(dp(48), dp(48)))
        })
        if (rename != null) content.addView(row("RENAME", R.string.agent_session_rename, R.drawable.ic_hub_compose) { openEditor() })
        content.addView(row("PIN", if (pinned) R.string.agent_session_unpin else R.string.agent_session_pin,
            R.drawable.ic_hub_pin) { dismiss(); pin() })
        content.addView(View(activity).apply { setBackgroundColor(activity.getColor(R.color.separator)) },
            LinearLayout.LayoutParams(-1, dp(1)).apply { marginStart = dp(12); marginEnd = dp(12); topMargin = dp(4); bottomMargin = dp(4) })
        content.addView(row("DELETE", R.string.agent_session_delete, R.drawable.ic_delete, destructive = true) { dismiss(); delete() })
        popup.contentView = ScrollView(activity).apply { isFillViewport = false; addView(content) }
        popup.isFocusable = true; popup.isOutsideTouchable = true
        popup.inputMethodMode = PopupWindow.INPUT_METHOD_NOT_NEEDED
        popup.setBackgroundDrawable(background())
        popup.elevation = dp(10).toFloat()
        popup.setOnDismissListener { if (!editing) dismiss() }
    }

    fun show(anchor: View) {
        if (closed || owner != null || activity.isFinishing || activity.isDestroyed || !anchor.isAttachedToWindow) return
        val frame = Rect().also(anchor::getWindowVisibleDisplayFrame)
        val width = dp(264).coerceAtMost((frame.width() - dp(16)).coerceAtLeast(1))
        content.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        popup.width = width
        popup.height = content.measuredHeight.coerceAtMost((frame.height() - dp(16)).coerceAtLeast(1))
        val location = IntArray(2).also(anchor::getLocationOnScreen)
        val edge = if (anchor.layoutDirection == View.LAYOUT_DIRECTION_RTL) location[0] + anchor.width - width else location[0]
        val x = edge.coerceIn(frame.left + dp(8), maxOf(frame.left + dp(8), frame.right - width - dp(8)))
        val below = location[1] + anchor.height + dp(4)
        val y = if (below + popup.height <= frame.bottom - dp(8)) below
            else maxOf(frame.top + dp(8), location[1] - popup.height - dp(4))
        // Observe the owning window, not a recyclable row that may rebind during a reply.
        owner = anchor.rootView.also { it.addOnAttachStateChangeListener(detached) }
        activity.application.registerActivityLifecycleCallbacks(this)
        if (Build.VERSION.SDK_INT >= 29) {
            popup.setIsLaidOutInScreen(true)
            popup.showAtLocation(requireNotNull(owner), Gravity.TOP or Gravity.LEFT, x, y)
        } else popup.showAsDropDown(anchor, 0, dp(4), Gravity.START)
    }

    fun dismiss() {
        if (closed) return
        closed = true
        input?.let { activity.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(it.windowToken, 0) }
        input?.text?.clear(); input = null
        editor?.setOnDismissListener(null); editor?.dismiss(); editor = null
        popup.dismiss()
        heading.text = ""; currentName = ""
        owner?.removeOnAttachStateChangeListener(detached); owner = null
        activity.application.unregisterActivityLifecycleCallbacks(this)
    }

    private fun openEditor() {
        if (closed || editing) return
        val renameAction = rename ?: return
        editing = true; popup.dismiss()
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(4))
        }
        val field = EditText(activity).apply {
            tag = "conversation-rename-input"; setText(currentName)
            filters = arrayOf(InputFilter.LengthFilter(ConversationRenamePolicy.MAX_CHARACTERS))
            hint = activity.getString(if (contact) R.string.contact_remark_name else R.string.conversation_rename_hint)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            setSingleLine(true); textSize = 16f; minimumHeight = dp(48)
            setTextColor(activity.getColor(R.color.text_primary)); setHintTextColor(activity.getColor(R.color.text_secondary))
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat(); setColor(activity.getColor(R.color.button_soft))
            }
            isSaveEnabled = false; importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        }
        input = field
        body.addView(field, LinearLayout.LayoutParams(-1, -2))
        val counter = label("", 12f).apply { gravity = Gravity.END; setPadding(0, dp(6), 0, 0); setTextColor(activity.getColor(R.color.text_secondary)) }
        body.addView(counter)
        val dialog = AlertDialog.Builder(activity)
            .setCustomTitle(label(activity.getString(if (contact) R.string.contact_edit_remark_title else R.string.conversation_rename_title), 18f).apply {
                setTypeface(typeface, Typeface.BOLD); setPadding(dp(20), dp(20), dp(20), dp(8))
            }).setView(body).setPositiveButton(R.string.common_save, null).setNegativeButton(R.string.common_cancel, null).create()
        editor = dialog
        var attempt = 0
        fun bind() {
            if (closed) return
            val valid = ConversationRenamePolicy.normalize(field.text.toString())
            dialog.getButton(AlertDialog.BUTTON_POSITIVE)?.apply {
                isEnabled = !saving && valid != null && valid != currentName.trim()
                alpha = if (isEnabled) 1f else .4f
            }
            counter.text = activity.getString(R.string.conversation_rename_counter, field.length(), ConversationRenamePolicy.MAX_CHARACTERS)
        }
        fun complete(sequence: Int, success: Boolean) = activity.runOnUiThread {
            if (closed || editor !== dialog || !dialog.isShowing || !saving || sequence != attempt) return@runOnUiThread
            saving = false
            if (success) dismiss() else {
                field.isEnabled = true; dialog.getButton(AlertDialog.BUTTON_NEGATIVE).isEnabled = true
                field.error = activity.getString(R.string.conversation_rename_failed); bind()
            }
        }
        fun save() {
            if (closed || saving) return
            val name = ConversationRenamePolicy.normalize(field.text.toString())
            if (name == null) {
                field.error = if (field.text.isNullOrBlank()) activity.getString(R.string.conversation_rename_required)
                    else activity.getString(R.string.conversation_rename_invalid, ConversationRenamePolicy.MAX_CHARACTERS)
                return
            }
            if (name == currentName.trim()) { dismiss(); return }
            saving = true; field.isEnabled = false
            val sequence = ++attempt
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE).isEnabled = false; bind()
            runCatching { renameAction(name) { complete(sequence, it) } }.onFailure { complete(sequence, false) }
        }
        field.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { field.error = null; bind() }
            override fun afterTextChanged(s: Editable?) = Unit
        })
        field.setOnEditorActionListener { _, action, _ -> if (action == EditorInfo.IME_ACTION_DONE) { save(); true } else false }
        dialog.setOnDismissListener { dismiss() }
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).apply {
                setTextColor(activity.getColor(R.color.composer_send_icon)); setOnClickListener { save() }
            }
            bind(); field.requestFocus(); field.selectAll()
            field.post { if (!closed) activity.getSystemService(InputMethodManager::class.java).showSoftInput(field, InputMethodManager.SHOW_IMPLICIT) }
        }
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        dialog.show()
        val frame = Rect().also { activity.window.decorView.getWindowVisibleDisplayFrame(it) }
        dialog.window?.apply {
            setBackgroundDrawable(background()); setLayout(dp(344).coerceAtMost((frame.width() - dp(32)).coerceAtLeast(1)), -2)
        }
    }

    private fun row(key: String, title: Int, icon: Int, destructive: Boolean = false, action: () -> Unit) = LinearLayout(activity).apply {
        tag = "conversation-action:$key"; orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(52); setPadding(dp(12), dp(12), dp(12), dp(12)); isFocusable = true
        contentDescription = activity.getString(title); background = selectable()
        val ink = activity.getColor(if (destructive) R.color.conversation_action_destructive else R.color.text_primary)
        addView(ImageView(activity).apply {
            setImageResource(icon); imageTintList = ColorStateList.valueOf(ink); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(20), dp(20)))
        addView(label(activity.getString(title), 16f).apply { setTextColor(ink); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(12) })
        setOnClickListener { if (!closed && !editing) action() }
    }
    private fun label(value: String, size: Float) = TextView(activity).apply {
        text = value; textSize = size; letterSpacing = 0f; setTextColor(activity.getColor(R.color.text_primary))
    }
    private fun background() = GradientDrawable().apply {
        cornerRadius = dp(8).toFloat(); setColor(activity.getColor(R.color.surface_bg)); setStroke(dp(1), activity.getColor(R.color.separator))
    }
    private fun selectable() = activity.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground)).let {
        try { it.getDrawable(0) } finally { it.recycle() }
    }
    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density + .5f).toInt()

    override fun onActivityPaused(owner: Activity) { if (owner === activity) dismiss() }
    override fun onActivityDestroyed(owner: Activity) { if (owner === activity) dismiss() }
    override fun onActivityCreated(owner: Activity, state: Bundle?) = Unit
    override fun onActivityStarted(owner: Activity) = Unit
    override fun onActivityResumed(owner: Activity) = Unit
    override fun onActivityStopped(owner: Activity) = Unit
    override fun onActivitySaveInstanceState(owner: Activity, state: Bundle) = Unit
}
