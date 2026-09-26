package com.galaxyssi.watch

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.DoorAccessConfigurationStore
import com.galaxyssi.chat.DoorAccessSkillPackage
import com.galaxyssi.chat.WatchSkillTransfer
import com.galaxyssi.chat.WatchSkillTransferInbox
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class WatchSkillManagerTest {
    // Isolate test preferences, including credentials, from the user's installed Skills.
    private fun isolatedContext(): Context {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val prefix = "skill_test_${UUID.randomUUID()}_"
        return object : ContextWrapper(target) {
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                target.getSharedPreferences(prefix + name, mode)
        }
    }

    private fun packageBytes(corrupt: Boolean = false, large: Boolean = false): ByteArray {
        val raw = """{
          "id":"com.galaxyssi.skill.door_access", "version":"1.3.0",
          "native_tools":["galaxyssi.door_access.open_panel"], "permissions":[],
          "steps":[{"tool_id":"galaxyssi.door_access.open_panel","input":{"door_config":{
            "version":1,"default_door":"test","list_commands":["测试门列表"],
            "default_open_commands":["测试开门"],"doors":[{
              "id":"test","service_name":"test","display_name":"Test door","commands":["打开测试门"]
            }]
          }}}]
        }"""
        val random = java.util.Random(42)
        val manifest = if (large) JSONObject(raw).put("description",
            (0 until 48000).map { ('a'.code + random.nextInt(26)).toChar() }.joinToString("")).toString().toByteArray()
            else raw.toByteArray()
        val hash = MessageDigest.getInstance("SHA-256").digest(manifest).joinToString("") { "%02x".format(it) }
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            zip.putNextEntry(ZipEntry("manifest.json")); zip.write(manifest); zip.closeEntry()
            zip.putNextEntry(ZipEntry("integrity.json"))
            zip.write(JSONObject().put("manifest_sha256", if (corrupt) "invalid" else hash).toString().toByteArray())
            zip.closeEntry()
        }
        return output.toByteArray()
    }

    @Test fun onlyInstalledAndEnabledSkillsRouteCommands() {
        val context = isolatedContext()
        val skills = WatchSkillManager(context)
        val skill = DoorAccessSkillPackage.inspect(packageBytes())
        assertFalse(skills.installed())
        assertNull(skills.activeConfiguration())
        // Stale configuration alone must not count as an installation.
        DoorAccessConfigurationStore(context).save(skill.configuration)
        assertFalse(skills.installed())
        assertNull(skills.activeConfiguration())
        skills.install(skill)
        assertTrue(skills.installed())
        assertNotNull(skills.activeConfiguration()?.parse("测试开门"))
        skills.setEnabled(false)
        assertTrue(skills.installed())
        assertNull(WatchSkillManager(context).activeConfiguration())
        skills.setEnabled(true)
        assertNotNull(skills.activeConfiguration())
        skills.uninstall()
        assertFalse(skills.installed())
        assertNull(DoorAccessConfigurationStore(context).load())
        assertNull(skills.activeConfiguration())
    }

    @Test fun invalidImportLeavesExistingDisabledSkillUnchanged() {
        val context = isolatedContext()
        val skills = WatchSkillManager(context)
        skills.install(DoorAccessSkillPackage.inspect(packageBytes()))
        skills.setEnabled(false)
        val saved = DoorAccessConfigurationStore(context).load()?.json
        assertTrue(runCatching { skills.install(DoorAccessSkillPackage.inspect(packageBytes(true))) }.isFailure)
        assertTrue(skills.installed())
        assertFalse(skills.enabled())
        assertEquals(saved, DoorAccessConfigurationStore(context).load()?.json)
        skills.uninstall()
    }

    @Test fun wifiTransferReassemblesMultipleBoundedChunksBeforeApproval() {
        val bytes = packageBytes(large = true)
        assertTrue(bytes.size > WatchSkillTransfer.CHUNK_BYTES)
        val inbox = WatchSkillTransferInbox()
        var chunkCount = 0
        var received: DoorAccessSkillPackage? = null
        val result = WatchSkillTransfer.send(bytes) { payload ->
            assertTrue(payload.toString().toByteArray().size <= 32768)
            when (payload.getString("kind")) {
                "skill_begin" -> inbox.begin(payload)
                "skill_chunk" -> { chunkCount++; inbox.append(payload) }
                else -> { received = inbox.finish(); JSONObject().put("status", "cancelled") }
            }
        }
        assertTrue(chunkCount > 1)
        assertEquals("1.3.0", received?.version)
        assertEquals("cancelled", result.getString("status"))
        assertTrue(runCatching { inbox.finish() }.isFailure)
    }

    @Test fun wifiTransferRejectsOversizeOutOfOrderAndIncompleteData() {
        val inbox = WatchSkillTransferInbox()
        val bytes = packageBytes()
        fun begin() = JSONObject().put("size", bytes.size).put("sha256", WatchSkillTransfer.digest(bytes))
        assertTrue(runCatching { inbox.begin(begin().put("size", DoorAccessSkillPackage.MAX_PACKAGE_BYTES + 1)) }.isFailure)
        inbox.begin(begin())
        assertTrue(runCatching { inbox.finish() }.isFailure)
        inbox.begin(begin())
        assertTrue(runCatching { inbox.append(JSONObject().put("index", 1).put("data", "YQ==")) }.isFailure)
        assertTrue(runCatching { inbox.finish() }.isFailure)
        inbox.begin(begin().put("size", 1))
        assertTrue(runCatching { inbox.append(JSONObject().put("index", 0).put("data", "YWI=")) }.isFailure)
    }
}
