package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView

/** A top-aligned, non-dimming window; the keyguard is never dismissed. */
class ContactReminderActivity : Activity() {
    companion object {
        internal fun intent(context: Context, id: String) = Intent(context, ContactReminderActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("reminder_id", id)
    }
    private val main = Handler(Looper.getMainLooper())
    private var reminder: ContactReminder? = null
    private lateinit var title: TextView
    private lateinit var subtitle: TextView
    private lateinit var status: TextView
    private lateinit var actions: LinearLayout
    private var id = ""
    private val observer: (ContactReminder) -> Unit = { value -> if (value.id == id) render(value) }
    private val tick = object : Runnable {
        override fun run() {
            val value = reminder ?: return
            if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) redactHeader()
            if (ContactReminderNotifications.callActive(this@ContactReminderActivity)) stopSound()
            if (System.currentTimeMillis() >= value.expiresAt) {
                ContactReminders.load(this@ContactReminderActivity, id) { }
                closeCompletedReminder()
            } else main.postDelayed(this, 1_000)
        }
    }
    override fun attachBaseContext(base: Context) = super.attachBaseContext(AppLanguage.wrap(base))

    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        window.setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
        val density = resources.displayMetrics.density
        val fontScale = resources.configuration.fontScale.coerceAtLeast(1f)
        val width = resources.displayMetrics.widthPixels - (20 * density).toInt()
        window.setLayout(width, panelHeight(false))
        window.attributes = window.attributes.apply { y = dp(8); dimAmount = 0f }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(8))
            background = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(8).toFloat() }
        }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(ImageView(this).apply {
            id = R.id.contact_reminder_logo
            setImageResource(R.drawable.galaxyssi_mark_large)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = null
        }, LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginEnd = dp(10) })
        val labels = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        title = TextView(this).apply {
            id = R.id.contact_reminder_header_title
            textSize = 16f; setTextColor(Color.rgb(28, 34, 37)); maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setTypeface(typeface, Typeface.BOLD)
        }
        labels.addView(title)
        subtitle = TextView(this).apply {
            id = R.id.contact_reminder_header_subtitle
            textSize = 12f; setTextColor(Color.rgb(108, 116, 126)); maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setText(R.string.contact_reminder_subtitle)
        }
        labels.addView(subtitle)
        header.addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(ImageButton(this).apply {
            setImageResource(R.drawable.ic_tab_settings)
            background = null
            setPadding(dp(12), dp(12), dp(12), dp(12))
            contentDescription = getString(R.string.contact_reminder_settings)
            tooltipText = contentDescription
            setOnClickListener { ContactReminderSettings.show(this@ContactReminderActivity) }
        }, LinearLayout.LayoutParams(dp(44), dp(44)))
        root.addView(header, LinearLayout.LayoutParams(-1, dp(maxOf(56, (44 * fontScale).toInt()))))
        status = TextView(this).apply {
            textSize = 15f; setTextColor(Color.DKGRAY); gravity = Gravity.CENTER_VERTICAL; maxLines = 2
            visibility = View.GONE
        }
        root.addView(status, LinearLayout.LayoutParams(-1, dp(maxOf(28, (24 * fontScale).toInt()))))
        actions = LinearLayout(this).apply { gravity = Gravity.CENTER }
        root.addView(actions, LinearLayout.LayoutParams(-1, dp(maxOf(48, (24 * fontScale).toInt()))).apply { topMargin = dp(8) })
        val handle = TextView(this).apply { text = "\u2303"; gravity = Gravity.CENTER; textSize = 16f; setTextColor(Color.GRAY) }
        var start = 0f
        root.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> { start = event.rawY; true }
                MotionEvent.ACTION_UP -> { if (start - event.rawY > dp(24)) collapse(); true }
                else -> true
            }
        }
        handle.setOnClickListener { collapse() }
        root.addView(handle, LinearLayout.LayoutParams(-1, dp(16)))
        setContentView(root)
        window.setLayout(width, panelHeight(false))
        ContactReminders.observers.add(observer)
        open(intent)
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); open(intent) }
    private fun open(intent: Intent) {
        val requestedId = intent.getStringExtra("reminder_id").orEmpty()
        id = requestedId
        reminder = null
        main.removeCallbacks(tick)
        redactHeader()
        ContactReminders.load(this, requestedId) { value ->
            // A late load for an older panel must not close or replace a newer reminder.
            if (isFinishing || isDestroyed || requestedId != id) return@load
            if (value == null) { closeCompletedReminder(); return@load }
            render(value)
            if (!isFinishing) { main.removeCallbacks(tick); main.post(tick) }
        }
    }

    private fun render(value: ContactReminder) {
        if (isFinishing || isDestroyed || value.id != id) return
        reminder = value
        if (value.terminal || System.currentTimeMillis() >= value.expiresAt) {
            closeCompletedReminder()
            return
        }
        redactHeader()
        if (!getSystemService(KeyguardManager::class.java).isKeyguardLocked) {
            subtitle.setText(R.string.contact_reminder_subtitle)
            ContactReminders.submit {
                val name = AppStore.contactById(this, value.contactId)?.optString("name").orEmpty()
                main.post { if (!isFinishing && id == value.id && !getSystemService(KeyguardManager::class.java).isKeyguardLocked)
                    title.text = name.ifBlank { getString(R.string.contact_reminder_title) } }
            }
        }
        val showStatus = value.outgoing || value.status in setOf("quiet", "muted")
        status.visibility = if (showStatus) View.VISIBLE else View.GONE
        status.text = if (showStatus) getString(ContactReminders.statusText(value.status)) else ""
        window.setLayout(resources.displayMetrics.widthPixels - dp(20), panelHeight(showStatus))
        actions.removeAllViews()
        if (value.outgoing) {
            button(R.string.contact_reminder_cancel, "cancelled", false)
        } else {
            button(R.string.contact_reminder_mute, "muted", false)
            button(R.string.contact_reminder_ignore, "dismissed", false)
            button(R.string.contact_reminder_confirm, "acknowledged", true)
        }
        if (value.status == "muted") stopSound()
    }

    private fun button(label: Int, action: String, primary: Boolean) {
        actions.addView(Button(this).apply {
            setText(label); textSize = 14f; isAllCaps = false; minimumWidth = 0; minWidth = 0
            setPadding(dp(4), 0, dp(4), 0)
            setTextColor(if (primary) Color.WHITE else Color.DKGRAY)
            background = GradientDrawable().apply {
                setColor(if (primary) Color.rgb(0, 157, 130) else Color.rgb(245, 247, 248)); cornerRadius = dp(8).toFloat()
            }
            setOnClickListener {
                stopSound()
                ContactReminders.act(this@ContactReminderActivity, this@ContactReminderActivity.id, action)
                if (action != "muted") finish()
            }
        }, LinearLayout.LayoutParams(0, dp(44), 1f).apply { marginStart = dp(3); marginEnd = dp(3) })
    }

    private fun stopSound() = ContactReminderSound.stop(id)
    private fun redactHeader() {
        title.setText(R.string.contact_reminder_title)
        subtitle.setText(R.string.contact_reminder_brand)
    }
    private fun closeCompletedReminder() {
        main.removeCallbacks(tick)
        stopSound()
        finish()
    }
    private fun collapse() {
        stopSound()
        if (reminder?.outgoing == false) ContactReminders.act(this, id, "muted")
        finish()
    }
    @Deprecated("Back dismisses the reminder panel")
    override fun onBackPressed() = collapse()
    override fun onResume() {
        super.onResume()
        AppForegroundTracker.onActivityForeground(this)
        if (BuildConfig.DEBUG) android.util.Log.d("GalaxySSIReminderPanel", "Panel visible; locked=${getSystemService(KeyguardManager::class.java).isKeyguardLocked}")
    }
    // The bounded sound session belongs to the reminder, not this transient window.
    override fun onPause() { AppForegroundTracker.onActivityBackground(this); super.onPause() }
    override fun onDestroy() { main.removeCallbacksAndMessages(null); ContactReminders.observers.remove(observer); super.onDestroy() }
    private fun panelHeight(showStatus: Boolean): Int {
        val fontScale = resources.configuration.fontScale.coerceAtLeast(1f)
        return dp(20 + maxOf(56, (44 * fontScale).toInt()) + 8 + maxOf(48, (24 * fontScale).toInt()) +
            16 + if (showStatus) maxOf(28, (24 * fontScale).toInt()) else 0)
    }
    private fun dp(value: Int) = (resources.displayMetrics.density * value).toInt()
}
