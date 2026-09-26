package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DoorAccessConfigurationDeviceTest {
    private fun fixture(): String = InstrumentationRegistry.getInstrumentation().context.assets
        .open("manifest.json").bufferedReader().use { it.readText() }

    @Test fun importedRulesDistinguishListFromOpenWithoutNetworkOrUnlock() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertFalse(context.assets.list("").orEmpty().contains("door_access_skill"))
        val rules = requireNotNull(DoorAccessConfiguration.fromManifest(fixture()))
        listOf("打开门禁", "打开门禁列表", "打開門禁", "打開門禁列表").forEach {
            assertEquals(it, DoorAccessCommand.ListDoors, rules.parse(it))
        }
        val expected = mapOf(
            "学校门" to "south", "打开学校门" to "south", "打開學校門" to "south",
            "华润门" to "north", "打开华润门" to "north", "打開華潤門" to "north",
            "市场门" to "side", "打开市场门" to "side", "打開市場門" to "side",
            "单元门" to "home", "打开单元门" to "home", "打開單元門" to "home"
        )
        expected.forEach { (phrase, target) ->
            assertEquals(phrase, DoorAccessCommand.Open(target), rules.parse(phrase))
            assertNotNull(DoorAccessNativeTool.actionFor(phrase, "device-test", rules))
        }
        assertNull(rules.parse("不要打开市场门"))
    }

    @Test fun installedSkillChangesRoutingAndDisableIsRespected() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val raw = fixture()
        val updated = JSONObject(raw).put("version", "1.4.0")
        updated.getJSONArray("steps").getJSONObject(0).getJSONObject("input")
            .getJSONObject("door_config").getJSONArray("default_open_commands").put("测试专用开门口令")
        val runtime = AgentSkillRuntime(availableNativeToolIds = setOf(DoorAccessNativeTool.ID))
        assertNull(DoorAccessNativeTool.configuration(context, runtime))
        val installation = runtime.install(updated.toString())
        assertEquals(DoorAccessCommand.Open(null),
            DoorAccessNativeTool.configuration(context, runtime)?.parse("测试专用开门口令"))
        runtime.disable(installation.id, installation.version)
        assertNull(DoorAccessNativeTool.configuration(context, runtime))
        runtime.enable(installation.id, installation.version)
        runtime.setAutoInvoke(installation.id, installation.version, false)
        assertNull(DoorAccessNativeTool.configuration(context, runtime))
    }

    @Test fun legacySkillWithoutRulesHasNoDefaultFallback() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val legacy = JSONObject(fixture()).put("version", "1.0.0")
        legacy.getJSONArray("steps").getJSONObject(0).getJSONObject("input").remove("door_config")
        val runtime = AgentSkillRuntime(availableNativeToolIds = setOf(DoorAccessNativeTool.ID))
        runtime.install(legacy.toString())
        assertNull(DoorAccessNativeTool.configuration(context, runtime))
    }
}
