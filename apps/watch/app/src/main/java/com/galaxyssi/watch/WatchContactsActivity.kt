package com.galaxyssi.watch

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import android.window.OnBackInvokedDispatcher
import com.galaxyssi.chat.WatchPerson
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** Contact UI deliberately owns no Signal or network work. */
class WatchContactsActivity : Activity() {
    private val repo get() = (application as WatchApplication).repository
    private var page = "list"
    private var peer = ""
    private var draft = ""
    private var voicePeer = ""
    private lateinit var peerVoice: WatchPeerVoice
    private var resumed = false
    private var busy = false
    private var qrBitmap: Bitmap? = null
    private var qrExpires = 0L
    private var revision = -1L
    private lateinit var root: LinearLayout
    private lateinit var body: LinearLayout
    private var chatRows: LinearLayout? = null
    private var scroll: ScrollView? = null
    private var editor: EditText? = null
    private var composer: WatchMessageComposer? = null
    private val green = Color.rgb(20, 198, 106)
    private val listener: () -> Unit = {
        if (revision != repo.contacts.revision) {
            revision = repo.contacts.revision
            if (page == "chat") updateMessages() else if (page != "qr") render()
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        peerVoice = WatchPeerVoice(this, { bytes, duration ->
            val target = voicePeer
            busy = true; composer?.sending(true)
            repo.contactAction({ try { sendVoice(target, bytes, duration) } finally { bytes.fill(0) } }) { ok ->
                busy = false; composer?.sending(false)
                if (ok) updateMessages() else error()
            }
        }, ::error)
        page = savedInstanceState?.getString("page") ?: "list"
        peer = savedInstanceState?.getString("peer") ?: intent.getStringExtra("peer").orEmpty()
        draft = savedInstanceState?.getString("draft").orEmpty()
        if (page in setOf("settings", "detail")) page = "chat"
        if (savedInstanceState == null && peer.isNotEmpty()) page = if (intent.getBooleanExtra("request", false)) "request" else "chat"
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) { back() }
        render()
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("page", page); out.putString("peer", peer); out.putString("draft", draft)
        super.onSaveInstanceState(out)
    }
    override fun onNewIntent(value: Intent) {
        super.onNewIntent(value); setIntent(value)
        peer = value.getStringExtra("peer").orEmpty(); draft = ""
        navigate(if (value.getBooleanExtra("request", false)) "request" else "chat")
    }
    override fun onResume() {
        super.onResume(); resumed = true
        repo.listen(listener); repo.foreground(true)
        if (repo.store.backgroundEnabled) startForegroundService(Intent(this, WatchConnectionService::class.java))
        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 42)
        visibility(); listener()
    }
    override fun onPause() {
        peerVoice.abort()
        resumed = false; repo.contacts.visiblePeer = ""; repo.unlisten(listener); repo.foreground(false)
        super.onPause()
    }
    override fun onDestroy() { peerVoice.close(); super.onDestroy() }
    private fun visibility() {
        repo.contacts.visiblePeer = if (resumed && page == "chat") peer else ""
        if (resumed && page == "chat") {
            repo.contactAction({ markRead(peer) })
            getSystemService(NotificationManager::class.java).cancel("peer", peer.hashCode())
        }
    }
    private fun navigate(value: String) { peerVoice.abort(); page = value; render(); visibility() }
    private fun back() {
        when (page) {
            "list" -> finish()
            "actions" -> navigate("chat")
            "paste" -> navigate("actions")
            "request" -> navigate("requests")
            else -> navigate("list")
        }
    }
    private fun render() {
        editor = null; composer = null; chatRows = null; scroll = null
        if (page == "qr") window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.BLACK)
            setPadding(dp(10), dp(20), dp(10), dp(18))
        }
        root.isFocusableInTouchMode = true
        root.requestFocus()
        setContentView(root)
        root.post { root.windowInsetsController?.hide(android.view.WindowInsets.Type.systemBars()) }
        val bar = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(if (page == "chat") 12 else 22), 0, dp(if (page == "chat") 16 else 22), 0)
        }
        if (page == "chat") {
            val backButton = object : View(this) {
                private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE; style = android.graphics.Paint.Style.STROKE
                    strokeWidth = dp(2).toFloat(); strokeCap = android.graphics.Paint.Cap.ROUND
                    strokeJoin = android.graphics.Paint.Join.ROUND
                }
                override fun onDraw(canvas: android.graphics.Canvas) {
                    val right = width - 6f
                    val center = height / 2f
                    canvas.drawPath(android.graphics.Path().apply {
                        moveTo(right, center - dp(5)); lineTo(right - dp(5), center)
                        lineTo(right, center + dp(5))
                    }, paint)
                }
            }.apply { contentDescription = getString(R.string.back); setOnClickListener { back() } }
            bar.addView(backButton, LinearLayout.LayoutParams(dp(24), dp(36)))
            bar.post {
                val hit = android.graphics.Rect(); backButton.getHitRect(hit)
                hit.inset(-dp(10), 0); bar.touchDelegate = android.view.TouchDelegate(hit, backButton)
            }
        } else bar.addView(text("‹", 28).apply {
            contentDescription = getString(R.string.back); setOnClickListener { back() }
        }, LinearLayout.LayoutParams(dp(36), dp(36)))
        val title = when(page) {
            "qr" -> getString(R.string.peer_my_qr)
            "requests" -> getString(R.string.peer_requests)
            "request" -> getString(R.string.peer_request)
            "chat" -> repo.contacts.person(peer)?.name ?: getString(R.string.contacts)
            else -> getString(R.string.contacts)
        }
        bar.addView(text(title, 16).apply {
            setTypeface(typeface, Typeface.BOLD); maxLines = 1
            ellipsize = if (page == "chat") null else android.text.TextUtils.TruncateAt.END
            if (page == "chat") {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL; includeFontPadding = false
                setHorizontallyScrolling(true)
            }
        }, LinearLayout.LayoutParams(0, dp(36), 1f).apply { if (page == "chat") leftMargin = 3 })
        if (page == "list") bar.addView(text("+", 23).apply {
            contentDescription = getString(R.string.peer_my_qr); setOnClickListener { openQr() }
        }, LinearLayout.LayoutParams(dp(36), dp(36)))
        if (page !in setOf("actions", "paste")) root.addView(bar)
        val scroller = ScrollView(this).apply { isFillViewport = false; clipToPadding = false }
        body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val sidePadding = if (page == "chat") (dp(8) - 5).coerceAtLeast(0) else dp(8)
            setPadding(sidePadding, dp(4), sidePadding, dp(10))
        }
        scroller.addView(body); root.addView(scroller, LinearLayout.LayoutParams(-1, 0, 1f)); scroll = scroller
        when (page) {
            "list" -> {
                row(getString(R.string.peer_my_qr)) { openQr() }
                row(getString(R.string.nearby_ble)) { startActivity(Intent(this, WatchNearbyActivity::class.java)) }
                row(getString(R.string.nearby_nfc)) { startActivity(Intent(this, WatchNearbyActivity::class.java).putExtra("nfc", true)) }
                val pending = repo.contacts.people().count { it.status in setOf("pending", "requesting") }
                row(getString(R.string.peer_requests) + if (pending > 0) "  • $pending" else "") { navigate("requests") }
                val approved = repo.contacts.people().filter { it.status == "approved" }
                if (approved.isEmpty()) body.addView(text(getString(R.string.peer_empty), 12))
                approved.forEach { person -> contactRow(person) { peer = person.id; draft = ""; navigate("chat") } }
            }
            "qr" -> {
                qrBitmap?.let { bitmap ->
                    body.addView(ImageView(this).apply { setImageBitmap(bitmap); contentDescription = getString(R.string.peer_my_qr) },
                        LinearLayout.LayoutParams(dp(140), dp(140)).apply { gravity = Gravity.CENTER_HORIZONTAL })
                    body.addView(text(getString(R.string.peer_qr_help), 12))
                    row(getString(R.string.peer_refresh_qr)) { qrBitmap = null; openQr(true) }
                }
            }
            "requests" -> {
                val pending = repo.contacts.people().filter { it.status in setOf("pending", "requesting") }
                if (pending.isEmpty()) body.addView(text(getString(R.string.peer_no_requests), 14))
                pending.forEach { person -> contactRow(person) { peer = person.id; navigate("request") } }
            }
            "request" -> {
                repo.contacts.person(peer)?.let { person ->
                    body.addView(avatar(person.fingerprint.ifBlank { person.id }), LinearLayout.LayoutParams(dp(44), dp(44)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(5) })
                }
                body.addView(text(repo.contacts.person(peer)?.name.orEmpty(), 21))
                if (repo.contacts.person(peer)?.status == "requesting") {
                    body.addView(text(getString(R.string.nearby_wait_approval), 13))
                } else {
                    body.addView(text(getString(R.string.peer_request_help), 13))
                    row(getString(R.string.peer_approve), green) { decide(true) }
                    row(getString(R.string.peer_reject)) { decide(false) }
                }
            }
            "chat" -> {
                chatRows = body; updateMessages(true)
                composer = WatchMessageComposer(this, draft, { draft = it }, { send(draft) }, ::voice, { navigate("actions") }, peerVoice::finish, peerVoice::move)
                editor = composer?.input
                root.addView(composer, composer!!.placement(10))

            }
            "actions" -> {
                row(getString(R.string.contacts)) { navigate("list") }
                row(getString(R.string.paste_message)) { navigate("paste") }
                row(getString(R.string.back)) { navigate("chat") }
            }
            "paste" -> {
                val clip = getSystemService(android.content.ClipboardManager::class.java).primaryClip
                val current = if (clip == null) emptyList() else (0 until clip.itemCount).mapNotNull {
                    clip.getItemAt(it).text?.toString()?.takeIf(String::isNotBlank)
                }
                val entries = (current + WatchClipboardHistory.snapshot()).distinct()
                if (entries.isEmpty()) body.addView(text(getString(R.string.clipboard_empty), 13))
                entries.forEach { value -> row(value.take(250)) {
                    draft = (draft + value).take(4000); navigate("chat"); editor?.setSelection(draft.length)
                } }
            }

        }
    }
    private fun contactRow(person: WatchPerson, click: () -> Unit) {
        val latest = repo.contacts.messages(person.id).lastOrNull()
        val last = (if (latest?.audioId?.isNotEmpty() == true) getString(R.string.peer_voice_message) else latest?.text.orEmpty()).take(22)
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(48); setPadding(dp(4), dp(5), dp(4), dp(5))
            setOnClickListener { click() }
            if (person.status == "approved") setOnLongClickListener {
                if (!busy) android.app.AlertDialog.Builder(this@WatchContactsActivity)
                    .setItems(arrayOf(getString(R.string.peer_delete))) { _, _ -> confirmDelete(person) }
                    .show()
                true
            }
        }
        row.addView(avatar(person.fingerprint.ifBlank { person.id }), LinearLayout.LayoutParams(dp(32), dp(32)))
        row.addView(text(person.name + if (last.isNotEmpty()) "\n$last" else "", 14).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL; setPadding(dp(9), 0, dp(3), 0)
            maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, -2, 1f))
        if (person.unread > 0) row.addView(text(person.unread.coerceAtMost(99).toString(), 12).apply {
            background = background(green)
        }, LinearLayout.LayoutParams(dp(22), dp(22)))
        body.addView(row, LinearLayout.LayoutParams(-1, -2))
    }
    private fun confirmDelete(person: WatchPerson) {
        if (busy || isFinishing || isDestroyed) return
        android.app.AlertDialog.Builder(this)
            .setTitle(R.string.peer_delete)
            .setMessage(getString(R.string.peer_delete_confirm, person.name))
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.confirm) { _, _ ->
                if (!busy) {
                    busy = true
                    repo.contactAction({ delete(person.id) }) { ok ->
                        busy = false
                        if (!isFinishing && !isDestroyed) {
                            if (ok) {
                                if (peer == person.id) { peer = ""; draft = "" }
                                navigate("list")
                            } else error()
                        }
                    }
                }
            }.show()
    }
    private fun updateMessages(initial: Boolean = false) {
        val rows = chatRows ?: return
        val view = scroll
        val nearEnd = initial || view == null || view.getChildAt(0).height - (view.scrollY + view.height) < dp(45)
        val oldY = view?.scrollY ?: 0
        rows.removeAllViews()
        repo.contacts.messages(peer).forEach { message ->
            val voice = message.audioId.isNotEmpty()
            val bubble = text(if (voice) "▶  ${((message.duration + 999) / 1000).coerceAtLeast(1)}″" else message.text.replace("[attachment]", getString(R.string.peer_attachment)), 15).apply {
                gravity = Gravity.START; setPadding(dp(10), dp(7), dp(10), dp(7)); setTextIsSelectable(true)
                setTextColor(if (message.outgoing) Color.BLACK else Color.WHITE)
                background = background(if (message.outgoing) 0xff95ec69.toInt() else 0xff26282b.toInt())
                maxWidth = (resources.displayMetrics.widthPixels * .67f).toInt() + 10
                if (voice) {
                    setTextIsSelectable(false); minWidth = dp(65); contentDescription = getString(R.string.peer_voice_message)
                    setOnClickListener {
                        peerVoice.stopPlayback()
                        val target = peer; var bytes: ByteArray? = null
                        repo.contactAction({ bytes = audioBytes(target, message.audioId) }) { ok ->
                            val audio = bytes
                            if (ok && audio != null && resumed && page == "chat" && peer == target) peerVoice.play(audio)
                            else { audio?.fill(0); if (resumed) Toast.makeText(this@WatchContactsActivity, R.string.peer_voice_loading, Toast.LENGTH_SHORT).show() }
                        }
                    }
                }
            }
            val messageRow = LinearLayout(this).apply {
                gravity = Gravity.TOP or if (message.outgoing) Gravity.END else Gravity.START
            }
            val fingerprint = if (message.outgoing) com.galaxyssi.chat.GalaxySSICrypto.localIdentitySha256()
                else repo.contacts.person(peer)?.fingerprint.orEmpty().ifBlank { peer }
            val icon = avatar(fingerprint)
            val iconParams = LinearLayout.LayoutParams(dp(24), dp(24)).apply {
                if (message.outgoing) leftMargin = dp(5) else rightMargin = dp(5)
            }
            if (!message.outgoing) messageRow.addView(icon, iconParams)
            messageRow.addView(bubble, LinearLayout.LayoutParams(-2, -2))
            if (message.outgoing) messageRow.addView(icon, iconParams)
            rows.addView(messageRow, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })
            if (message.outgoing) rows.addView(text(getString(when(message.state) {
                "delivered" -> R.string.peer_delivered
                "failed" -> R.string.peer_failed
                else -> R.string.peer_queued
            }), 10).apply { gravity = Gravity.END; setTextColor(Color.GRAY) })
        }
        view?.post { if (nearEnd) view.fullScroll(View.FOCUS_DOWN) else view.scrollTo(0, oldY) }
        if (resumed) visibility()
    }
    private fun openQr(force: Boolean = false) {
        if (!force && qrBitmap != null && System.currentTimeMillis() < qrExpires) { navigate("qr"); return }
        if (busy) return
        busy = true
        var bitmap: Bitmap? = null
        repo.contactAction({
            val value = createQr(force)
            val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, 640, 640)
            bitmap = Bitmap.createBitmap(640, 640, Bitmap.Config.ARGB_8888).apply {
                val pixels = IntArray(640 * 640) { if (matrix[it % 640, it / 640]) Color.BLACK else Color.WHITE }
                setPixels(pixels, 0, 640, 0, 0, 640, 640)
            }
        }) { ok ->
            busy = false
            if (ok && !isDestroyed) { qrBitmap = bitmap; qrExpires = System.currentTimeMillis() + 9 * 60_000; navigate("qr") } else error()
        }
    }
    private fun decide(approve: Boolean) {
        if (busy) return
        busy = true; val id = peer
        repo.contactAction({ decide(id, approve) }) { ok ->
            busy = false
            if (ok) { getSystemService(NotificationManager::class.java).cancel("peer", id.hashCode()); navigate("list") } else error()
        }
    }
    private fun send(value: String) {
        if (busy || value.isBlank() || repo.contacts.person(peer)?.status != "approved") return
        busy = true; composer?.sending(true); val id = peer; val original = value
        repo.contactAction({ send(id, original) }) { ok ->
            busy = false; composer?.sending(false)
            if (ok) { if (draft == original) { draft = ""; editor?.setText("") }; updateMessages() } else error()
        }
    }
    private fun voice() {
        if (busy || repo.contacts.person(peer)?.status != "approved") return
        voicePeer = peer; peerVoice.start()
    }
    private fun error() { if (!isDestroyed) Toast.makeText(this, R.string.peer_error, Toast.LENGTH_LONG).show() }
    private fun row(label: String, color: Int = 0xff1d1f21.toInt(), click: () -> Unit) {
        body.addView(text(label, 14).apply {
            gravity = Gravity.CENTER_VERTICAL; minHeight = dp(44); setPadding(dp(12), dp(7), dp(12), dp(7))
            background = background(color); setOnClickListener { click() }
        }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(5) })
    }
    private fun avatar(fingerprint: String) = ImageView(this).apply {
        setImageDrawable(com.galaxyssi.chat.GalaxySSIIdenticonDrawable(fingerprint))
        scaleType = ImageView.ScaleType.CENTER_CROP
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private fun text(value: String, size: Int) = TextView(this).apply { text = value; textSize = size.toFloat(); setTextColor(Color.WHITE); gravity = Gravity.CENTER }
    private fun background(color: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(18).toFloat() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

object WatchContactNotifications {
    fun show(context: Context, person: WatchPerson, text: String, request: Boolean) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("watch_contacts", context.getString(R.string.contacts), NotificationManager.IMPORTANCE_DEFAULT))
        if (context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return
        val open = PendingIntent.getActivity(context, person.id.hashCode(), Intent(context, WatchContactsActivity::class.java)
            .putExtra("peer", person.id).putExtra("request", request), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify("peer", person.id.hashCode(), Notification.Builder(context, "watch_contacts")
            .setSmallIcon(R.drawable.ic_galaxyssi_logo).setContentTitle(person.name)
            .setContentText(if (request) context.getString(R.string.peer_request_help) else text.take(120))
            .setContentIntent(open).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build())
    }
}
