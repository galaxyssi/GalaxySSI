package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
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
    private lateinit var status: TextView
    private lateinit var actions: LinearLayout
    private var id = ""
    private val observer: (ContactReminder) -> Unit = { value -> if (value.id == id) render(value) }
    private val tick = object : Runnable {
        override fun run() {
            val value = reminder ?: return
            if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) title.setText(R.string.contact_reminder_title)
            if (ContactReminderNotifications.callActive(this@ContactReminderActivity)) stopSound()
            if (System.currentTimeMillis() >= value.expiresAt) {
                stopSound()
                ContactReminders.load(this@ContactReminderActivity, id) { if (it != null) render(it) }
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
        val height = maxOf(resources.configuration.screenHeightDp * .20f, 100f + 38f * fontScale, 158f)
        val width = resources.displayMetrics.widthPixels - (20 * density).toInt()
        window.setLayout(width, (height * density).toInt())
        window.attributes = window.attributes.apply { y = dp(8); dimAmount = 0f }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(6))
            background = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(8).toFloat() }
        }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(ImageView(this).apply {
            setImageResource(R.drawable.ic_voice_call_wave)
            imageTintList = ColorStateList.valueOf(Color.rgb(0, 153, 128))
            contentDescription = null
        }, LinearLayout.LayoutParams(dp(32), dp(32)).apply { marginEnd = dp(10) })
        val labels = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        title = TextView(this).apply { textSize = 16f; setTextColor(Color.rgb(28, 34, 37)); maxLines = 1 }
        labels.addView(title)
        header.addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(header, LinearLayout.LayoutParams(-1, dp(maxOf(42, (24 * fontScale).toInt()))))
        status = TextView(this).apply { textSize = 15f; setTextColor(Color.DKGRAY); gravity = Gravity.CENTER_VERTICAL; maxLines = 2 }
        root.addView(status, LinearLayout.LayoutParams(-1, 0, 1f))
        actions = LinearLayout(this).apply { gravity = Gravity.CENTER }
        root.addView(actions, LinearLayout.LayoutParams(-1, dp(maxOf(48, (24 * fontScale).toInt()))))
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
        window.setLayout(width, (height * density).toInt())
        ContactReminders.observers.add(observer)
        open(intent)
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); open(intent) }
    private fun open(intent: Intent) {
        id = intent.getStringExtra("reminder_id").orEmpty()
        ContactReminders.load(this, id) { value ->
            if (isFinishing || value?.id != id) { if (value == null) finish(); return@load }
            render(value)
            main.removeCallbacks(tick); main.post(tick)
        }
    }

    private fun render(value: ContactReminder) {
        reminder = value
        title.text = getString(R.string.contact_reminder_title)
        if (!getSystemService(KeyguardManager::class.java).isKeyguardLocked) {
            ContactReminders.submit {
                val name = AppStore.contactById(this, value.contactId)?.optString("name").orEmpty()
                main.post { if (!isFinishing && id == value.id && !getSystemService(KeyguardManager::class.java).isKeyguardLocked)
                    title.text = name.ifBlank { getString(R.string.contact_reminder_title) } }
            }
        }
        status.setText(if (value.outgoing || value.terminal || value.status in setOf("quiet", "muted"))
            ContactReminders.statusText(value.status) else R.string.contact_reminder_message)
        actions.removeAllViews()
        if (value.terminal) {
            stopSound(); button(R.string.contact_reminder_close, "close", false)
        } else if (value.outgoing) {
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
                if (action != "close") ContactReminders.act(this@ContactReminderActivity, this@ContactReminderActivity.id, action)
                if (action != "muted") finish()
            }
        }, LinearLayout.LayoutParams(0, dp(44), 1f).apply { marginStart = dp(3); marginEnd = dp(3) })
    }

    private fun stopSound() = ContactReminderSound.stop(id)
    private fun collapse() {
        stopSound()
        if (reminder?.outgoing == false) ContactReminders.act(this, id, "muted")
        finish()
    }
    @Deprecated("Back dismisses the reminder panel")
    override fun onBackPressed() = collapse()
    override fun onResume() { super.onResume(); AppForegroundTracker.onActivityForeground(this) }
    // The bounded sound session belongs to the reminder, not this transient window.
    override fun onPause() { AppForegroundTracker.onActivityBackground(this); super.onPause() }
    override fun onDestroy() { main.removeCallbacksAndMessages(null); ContactReminders.observers.remove(observer); super.onDestroy() }
    private fun dp(value: Int) = (resources.displayMetrics.density * value).toInt()
}
