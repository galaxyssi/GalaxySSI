package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessFixtureEvidenceDeviceTest {
    @Test fun outputScreenshotsCannotOverwriteInputImages() {
        val cache = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir
        val directory = File(cache, "fixture-evidence-${System.nanoTime()}").apply { mkdirs() }
        try {
            for (style in listOf("annotation_sheet", "table")) {
                val case = JSONObject("""{"id":"A032","fixture_style":"$style","fixtures":[
                    {"title":"Fixture","code":"ART-032","unit":"items","rows":[
                    {"label":"1. 12 + 7 =","answer":"18","value":18}]}]}""")
                BusinessScenarioFixtures.image(directory, case, 0)
                val original = File(directory, "A032-input-0.png")
                assertTrue(original.isFile)
                val bytes = original.readBytes()
                assertTrue(bytes.size > 100)
                File(directory, "A032-0.png").writeText("output screenshot stand-in")
                File(directory, "A032-0-process.png").writeText("process screenshot stand-in")
                assertArrayEquals(bytes, original.readBytes())
            }
        } finally {
            directory.deleteRecursively()
        }
    }
}
