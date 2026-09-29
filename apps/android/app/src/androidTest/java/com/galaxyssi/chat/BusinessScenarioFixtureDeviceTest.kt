package com.galaxyssi.chat

import android.graphics.BitmapFactory
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessScenarioFixtureDeviceTest {
    @Test fun selectsConfiguredCloudModelsAndPairedAgentsByIdentity() {
        val cloud = AgentCallableTarget("model-test", "Renamed model", AgentConnectorKind.MODEL,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT),
            failureDomain = "cloud:deepseek", adapterType = "cloud-model-api")
        val paired = AgentCallableTarget("desktop-test:codex", "Renamed agent", AgentConnectorKind.AGENT,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT))
        val targets = listOf(cloud, paired) + StaticAgentConnectorRegistry().availableTargets()
        assertEquals(cloud, selectBusinessTarget(targets, "deepseek"))
        assertEquals(paired, selectBusinessTarget(targets, "codex"))
        assertNull(selectBusinessTarget(listOf(cloud.copy(status = AgentConnectorStatus.DISCONNECTED)), "deepseek"))
        assertNull(selectBusinessTarget(listOf(cloud.copy(failureDomain = "cloud:other", title = "DeepSeek")), "deepseek"))
        assertNull(selectBusinessTarget(StaticAgentConnectorRegistry().availableTargets(), "codex"))
    }

    @Test fun renderSyntheticImagesWithoutCallingModels() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("business_render") == "true")
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.getExternalFilesDir(null), "business-eval")
        val plan = JSONObject(File(root, "plan.json").readText())
        val directory = File(root, "fixtures-preview").apply { mkdirs() }
        val results = JSONArray()
        val cases = plan.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            for (index in 0 until case.getJSONArray("fixtures").length()) {
                BusinessScenarioFixtures.image(directory, case, index)
                val file = File(directory, case.getString("id") + "-$index.png")
                val image = requireNotNull(BitmapFactory.decodeFile(file.path))
                try {
                    assertEquals(1200, image.width)
                    assertEquals(1000, image.height)
                    assertTrue(file.length() > 1000)
                    results.put(JSONObject().put("case", case.getString("id")).put("file", file.name).put("bytes", file.length()))
                } finally { image.recycle() }
            }
        }
        assertEquals(100, results.length())
        File(directory, "images.json").writeText(JSONObject().put("catalog_sha256", plan.getString("catalog_sha256"))
            .put("images", results).toString(2))
    }
}
