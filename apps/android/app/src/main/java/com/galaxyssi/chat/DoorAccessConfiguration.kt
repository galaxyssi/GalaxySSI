package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.util.Locale
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.zip.ZipInputStream

internal data class DoorAccessTarget(val id: String, val serviceName: String, val displayName: String)

internal class DoorAccessConfiguration private constructor(
    val json: String,
    private val defaultDoorId: String,
    private val targets: List<DoorAccessTarget>,
    private val commands: Map<String, DoorAccessCommand>
) {
    fun parse(request: String): DoorAccessCommand? = commands[normalize(request)]

    fun select(command: DoorAccessCommand.Open, doors: List<DoorAccessDoor>): DoorAccessDoor? {
        val target = targets.singleOrNull { it.id == (command.target ?: defaultDoorId) } ?: return null
        return doors.filter { it.name == target.serviceName }.singleOrNull()
    }

    fun displayName(door: DoorAccessDoor): String =
        targets.singleOrNull { it.serviceName == door.name }?.displayName ?: door.name

    companion object {
        const val TOOL_ID = "galaxyssi.door_access.open_panel"
        private const val MAX_BYTES = 64 * 1024
        private val punctuation = Regex("[\\s，,。.!！?？;；]+")

        private fun normalize(value: String): String = value.trim().lowercase(Locale.ROOT)
            .replace('開', '开').replace('門', '门').replace('區', '区').replace('單', '单')
            .replace('幫', '帮').replace('啟', '启').replace('棟', '栋').replace('華', '华')
            .replace('潤', '润').replace('場', '场').replace('學', '学').replace('側', '侧')
            .replace(punctuation, "")

        fun fromManifest(raw: String): DoorAccessConfiguration? = runCatching {
            require(raw.toByteArray().size <= MAX_BYTES)
            val steps = JSONObject(raw).getJSONArray("steps")
            require(steps.length() == 1)
            val step = steps.getJSONObject(0)
            require(step.getString("tool_id") == TOOL_ID)
            fromJson(step.getJSONObject("input").getJSONObject("door_config").toString())
        }.getOrNull()

        fun fromJson(raw: String): DoorAccessConfiguration? = runCatching {
            require(raw.toByteArray().size <= MAX_BYTES)
            val root = JSONObject(raw)
            require(root.getInt("version") == 1)
            val targetArray = root.getJSONArray("doors")
            require(targetArray.length() in 1..32)
            val targets = (0 until targetArray.length()).map { index ->
                val item = targetArray.getJSONObject(index)
                DoorAccessTarget(item.getString("id"), item.getString("service_name"), item.getString("display_name"))
                    .also { target ->
                        require(target.id.matches(Regex("[a-zA-Z0-9._-]{1,64}")))
                        require(target.serviceName.isNotBlank() && target.serviceName.length <= 100)
                        require(target.displayName.isNotBlank() && target.displayName.length <= 100)
                    }
            }
            require(targets.map { it.id }.distinct().size == targets.size)
            require(targets.map { it.serviceName }.distinct().size == targets.size)
            val defaultDoorId = root.getString("default_door")
            require(targets.any { it.id == defaultDoorId })
            val commands = linkedMapOf<String, DoorAccessCommand>()
            var aliasCount = 0
            fun addAliases(aliases: org.json.JSONArray, command: DoorAccessCommand) {
                require(aliases.length() in 1..128)
                for (index in 0 until aliases.length()) {
                    val original = aliases.getString(index)
                    require(original.isNotBlank() && original.length <= 80)
                    val phrase = normalize(original)
                    require(phrase.isNotBlank())
                    val previous = commands.put(phrase, command)
                    require(previous == null || previous == command)
                    require(++aliasCount <= 512)
                }
            }
            addAliases(root.getJSONArray("list_commands"), DoorAccessCommand.ListDoors)
            addAliases(root.getJSONArray("default_open_commands"), DoorAccessCommand.Open(null))
            targets.forEachIndexed { index, target ->
                addAliases(targetArray.getJSONObject(index).getJSONArray("commands"), DoorAccessCommand.Open(target.id))
            }
            DoorAccessConfiguration(root.toString(), defaultDoorId, targets, commands)
        }.getOrNull()
    }
}

internal class DoorAccessConfigurationStore(context: Context) {
    private val context = context.applicationContext
    private val preferences = this.context.getSharedPreferences("door_access_configuration_v1", Context.MODE_PRIVATE)

    fun load(): DoorAccessConfiguration? {
        val raw = preferences.getString("imported_configuration", null) ?: return null
        return DoorAccessConfiguration.fromJson(raw)
    }

    fun save(configuration: DoorAccessConfiguration) {
        check(preferences.edit().remove("configuration").putString("imported_configuration", configuration.json).commit())
    }

    fun clear() { preferences.edit().clear().apply() }
}

internal data class DoorAccessSkillPackage(val version: String, val configuration: DoorAccessConfiguration) {
    companion object {
        const val MAX_PACKAGE_BYTES = 16 * 1024 * 1024

        fun inspect(bytes: ByteArray): DoorAccessSkillPackage {
            require(bytes.size <= MAX_PACKAGE_BYTES)
            val entries = linkedMapOf<String, ByteArray>()
            ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    require(!entry.isDirectory && entry.name in setOf("manifest.json", "integrity.json"))
                    require(entry.name !in entries)
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = zip.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= 256 * 1024)
                        output.write(buffer, 0, count)
                    }
                    entries[entry.name] = output.toByteArray()
                }
            }
            val manifestBytes = requireNotNull(entries["manifest.json"])
            val integrity = JSONObject(requireNotNull(entries["integrity.json"]).toString(Charsets.UTF_8))
            val hash = MessageDigest.getInstance("SHA-256").digest(manifestBytes)
                .joinToString("") { "%02x".format(it) }
            require(integrity.getString("manifest_sha256") == hash)
            val raw = manifestBytes.toString(Charsets.UTF_8)
            val manifest = JSONObject(raw)
            require(manifest.getString("id") == "com.galaxyssi.skill.door_access")
            val tools = manifest.getJSONArray("native_tools")
            require(tools.length() == 1 && tools.getString(0) == DoorAccessConfiguration.TOOL_ID)
            require(manifest.optJSONArray("permissions")?.length() == 0)
            val version = manifest.getString("version")
            require(version.matches(Regex("[a-zA-Z0-9._+-]{1,64}")))
            return DoorAccessSkillPackage(version, requireNotNull(DoorAccessConfiguration.fromManifest(raw)))
        }
    }
}
