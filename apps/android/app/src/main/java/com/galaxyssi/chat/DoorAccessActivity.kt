package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Local door Skill surface. Automatic requests are consumed once and require saved credentials. */
class DoorAccessActivity : Activity() {
    companion object {
        const val EXTRA_REQUEST = "door_access_request"
        const val EXTRA_COMMAND_ID = "door_access_command_id"
        const val EXTRA_CONFIGURATION = "door_access_configuration"
        private const val IMPORT_SKILL_REQUEST = 41
    }

    private val client = DoorAccessClient()
    private val credentials by lazy { DoorAccessCredentialStore(this) }
    private var restoredConfiguration: String? = null
    private val configuration by lazy {
        (restoredConfiguration ?: intent.getStringExtra(EXTRA_CONFIGURATION))?.let(DoorAccessConfiguration::fromJson)
            ?: if (isWatch) DoorAccessConfigurationStore(this).load() else null
    }
    private val main = Handler(Looper.getMainLooper())
    private fun text(name: String, vararg args: Any): String = doorAccessText(name, *args)
    private val isWatch get() = packageName == "com.galaxyssi.watch"
    private val skillPreferences by lazy { getSharedPreferences("door_access_skill_v1", MODE_PRIVATE) }
    private var session: DoorAccessSession? = null
    private var doors = emptyList<DoorAccessDoor>()
    private var running = false
    private var autoLoggingIn = false
    private var pendingCommand: DoorAccessCommand.Open? = null
    private lateinit var content: LinearLayout
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        restoredConfiguration = if (isWatch) null else savedInstanceState?.getString(EXTRA_CONFIGURATION)
        val scroll = ScrollView(this)
        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = if (isWatch) 18 else 24
            setPadding(padding, padding, padding, padding)
        }
        scroll.addView(content)
        setContentView(scroll)
        val savedCredentials = installed() && credentials.load() != null
        val command = configuration?.parse(intent.getStringExtra(EXTRA_REQUEST).orEmpty())
        val commandId = intent.getStringExtra(EXTRA_COMMAND_ID).orEmpty()
        if (savedCredentials && command is DoorAccessCommand.Open && consumeCommand(commandId)) {
            pendingCommand = command
        }
        intent.removeExtra(EXTRA_REQUEST)
        intent.removeExtra(EXTRA_COMMAND_ID)
        intent.removeExtra(EXTRA_CONFIGURATION)
        autoLoggingIn = savedCredentials
        show()
        if (autoLoggingIn) loadSavedSession()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        if (!isWatch) configuration?.let { outState.putString(EXTRA_CONFIGURATION, it.json) }
        super.onSaveInstanceState(outState)
    }

    private fun consumeCommand(id: String): Boolean {
        if (id.isBlank()) return false
        val history = skillPreferences.getString("consumed_commands", "").orEmpty()
            .split(',').filter(String::isNotBlank)
        if (id in history) return false
        return skillPreferences.edit().putString("consumed_commands", (history.takeLast(31) + id).joinToString(",")).commit()
    }

    private fun installed(): Boolean = !isWatch ||
        (skillPreferences.getBoolean("installed", false) && configuration != null)

    private fun show() {
        content.removeAllViews()
        title(text("title"))
        status = label(when {
            !installed() -> text("import_required")
            autoLoggingIn -> text("auto_login")
            session == null -> text("login_required")
            doors.isEmpty() -> text("no_doors")
            else -> text("choose_door")
        })
        if (!installed()) {
            button(text("import")) { importSkill() }
            return
        }
        if (autoLoggingIn) return
        if (session == null) {
            val saved = credentials.load()
            val account = field(text("account"), saved?.first.orEmpty(), false)
            val password = field(text("password"), "", true)
            button(text("login")) {
                val name = account.text.toString().trim()
                val secret = password.text.toString()
                if (name.isBlank() || secret.isBlank()) {
                    status.text = text("credentials_required")
                } else {
                    password.text.clear()
                    logIn(name, secret)
                }
            }
        } else {
            doors.forEach { door ->
                val displayName = configuration?.displayName(door) ?: door.name
                button(listOf(door.community, displayName).filter(String::isNotBlank).joinToString(" · ")) {
                    AlertDialog.Builder(this).setTitle(text("confirm_open"))
                        .setMessage(text("confirm_open_message", displayName))
                        .setNegativeButton(text("cancel"), null)
                        .setPositiveButton(text("send")) { _, _ -> unlock(door) }
                        .show()
                }
            }
            button(text("refresh")) { refreshDoors() }
            button(text("sign_out")) {
                AlertDialog.Builder(this).setMessage(text("confirm_clear"))
                    .setNegativeButton(text("cancel"), null)
                    .setPositiveButton(text("clear")) { _, _ ->
                        credentials.clear(); session = null; doors = emptyList(); show()
                    }.show()
            }
        }
        if (isWatch) button(text("update")) { importSkill() }
        if (isWatch) button(text("uninstall")) {
            AlertDialog.Builder(this).setMessage(text("confirm_uninstall"))
                .setNegativeButton(text("cancel"), null)
                .setPositiveButton(text("uninstall_action")) { _, _ ->
                    credentials.clear(); session = null; doors = emptyList()
                    DoorAccessConfigurationStore(this).clear()
                    skillPreferences.edit().putBoolean("installed", false).apply(); recreate()
                }.show()
        }
    }

    private fun importSkill() {
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }, IMPORT_SKILL_REQUEST)
        } catch (_: android.content.ActivityNotFoundException) {
            status.text = text("picker_missing")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (!isWatch || requestCode != IMPORT_SKILL_REQUEST || resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        runTask(text("checking"), onError = { status.text = text("invalid_package") }) {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= DoorAccessSkillPackage.MAX_PACKAGE_BYTES)
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: error("Cannot read Skill")
            val inspected = DoorAccessSkillPackage.inspect(bytes)
            main.post {
                if (isFinishing || isDestroyed) return@post
                AlertDialog.Builder(this).setTitle(text("import_title", inspected.version))
                    .setMessage(text("import_notice"))
                    .setNegativeButton(text("cancel"), null)
                    .setPositiveButton(text("import_enable")) { _, _ ->
                        val saved = runCatching {
                            DoorAccessConfigurationStore(this).save(inspected.configuration)
                            check(skillPreferences.edit().putBoolean("installed", true).commit())
                        }.isSuccess
                        if (saved) recreate() else status.text = text("save_failed")
                    }.show()
            }
        }
    }

    private fun loadSavedSession() {
        val (account, password) = credentials.load() ?: return
        logIn(account, password, remember = false)
    }

    private fun logIn(account: String, password: String, remember: Boolean = true) = runTask(
        text("connecting"),
        action = {
            val loggedIn = client.login(account, password)
            if (remember) credentials.save(account, password)
            val available = client.listDoors(loggedIn)
            val requested = pendingCommand
            val selected = requested?.let { configuration?.select(it, available) }
            val accepted = selected?.let { door ->
                runCatching { client.unlock(loggedIn, door, System.currentTimeMillis()) }
            }
            main.post {
                pendingCommand = null
                autoLoggingIn = false
                session = loggedIn
                doors = available
                show()
                if (requested != null) {
                    status.text = when {
                        selected == null -> text("not_unique")
                        accepted?.isFailure == true -> text("unconfirmed_panel")
                        accepted?.getOrNull() == true -> text("sent_panel")
                        else -> text("rejected")
                    }
                }
            }
        },
        onError = {
            if (autoLoggingIn) {
                autoLoggingIn = false
                show()
            }
            status.text = text("login_failed")
        }
    )

    private fun refreshDoors() {
        val active = session ?: return
        runTask(text("refreshing")) {
            val available = client.listDoors(active)
            main.post { doors = available; show() }
        }
    }

    private fun unlock(door: DoorAccessDoor) {
        val active = session ?: return
        if (doors.none { it.channel == door.channel }) return
        runTask(text("sending")) {
            val accepted = client.unlock(active, door, System.currentTimeMillis())
            main.post { status.text = if (accepted) text("sent_panel") else text("rejected") }
        }
    }

    private fun runTask(message: String, onError: (() -> Unit)? = null, action: () -> Unit) {
        if (running) return
        running = true
        status.text = message
        Thread {
            try { action() }
            catch (_: Exception) { main.post {
                if (onError != null) onError() else status.text = text("operation_failed")
            } }
            finally { main.post { running = false } }
        }.start()
    }

    private fun title(value: String) = TextView(this).apply {
        text = value; textSize = if (isWatch) 18f else 24f
        setTextColor(if (isWatch) Color.WHITE else Color.BLACK); gravity = Gravity.CENTER
        content.addView(this, LinearLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun label(value: String) = TextView(this).apply {
        text = value; textSize = 14f; setTextColor(if (isWatch) Color.LTGRAY else Color.DKGRAY)
        setPadding(0, 16, 0, 16)
        content.addView(this, LinearLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun field(hintText: String, value: String, secret: Boolean) = EditText(this).apply {
        hint = hintText; setText(value); isSingleLine = true
        if (isWatch) { setTextColor(Color.WHITE); setHintTextColor(Color.LTGRAY) }
        inputType = if (secret) InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            else InputType.TYPE_CLASS_TEXT
        content.addView(this, LinearLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun button(value: String, click: () -> Unit) = Button(this).apply {
        isAllCaps = false
        text = value; setOnClickListener { click() }
        content.addView(this, LinearLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT))
    }
}
