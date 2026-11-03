package com.galaxyssi.glasses

import java.io.File
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

class LocalizedCopyTest {
    private fun strings(locale: String): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/res/$locale/glasses_copy.xml"))
        val nodes = document.getElementsByTagName("string")
        val rows = (0 until nodes.length).map { nodes.item(it) as Element }
            .associate { it.getAttribute("name") to it.textContent.removeSurrounding("\"")
                .replace("\\'", "'").replace("\\\"", "\"") }
        assertEquals(nodes.length, rows.size)
        return rows
    }

    @Test fun everyCopyHasMatchingResourcesAndFormatArguments() {
        val english = strings("values")
        val chinese = strings("values-zh")
        assertEquals(123, english.size)
        assertEquals(english.keys, chinese.keys)
        val placeholders = Regex("%[0-9]+\\\$s")
        for ((name, value) in english) {
            assertEquals(name, placeholders.findAll(value).map { it.value }.toList(),
                placeholders.findAll(chinese.getValue(name)).map { it.value }.toList())
        }
    }

    @Test fun cameraReadyFeedbackAndDynamicStatusRetainTheirSemantics() {
        for (locale in listOf("values", "values-zh")) {
            val copy = strings(locale)
            assertTrue(copy.getValue("glasses_copy_camera_ready_say_take_photo_or_start_video")
                .startsWith(copy.getValue("glasses_copy_camera_ready")))
            val battery = String.format(Locale.ROOT, copy.getValue("glasses_copy_battery"), 82)
            assertTrue(battery.endsWith("82%"))
            assertFalse(battery.contains("%%"))
            val agent = String.format(Locale.ROOT, copy.getValue("glasses_copy_current_agent"), "Agent", "Model")
            assertTrue(agent.contains("Agent · Model"))
        }
    }

    @Test fun resourcesAreNotReadBeforeActivityAttachment() {
        val source = File("src/main/java/com/galaxyssi/glasses/MainActivity.kt").readText()
        assertFalse(source.substringBefore("override fun onCreate").contains("getString("))
        assertTrue(source.indexOf("status = getString(R.string.glasses_copy_ready)") >
            source.indexOf("super.onCreate(savedInstanceState)"))
        assertFalse(Regex("[\\u3400-\\u9fff]").containsMatchIn(source))
    }
}
