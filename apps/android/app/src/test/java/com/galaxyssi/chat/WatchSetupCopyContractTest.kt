package com.galaxyssi.chat

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

class WatchSetupCopyContractTest {
    private fun strings(locale: String, name: String = "watch_setup_copy"): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/res/$locale/$name.xml"))
        val nodes = document.getElementsByTagName("string")
        val result = (0 until nodes.length).map { nodes.item(it) as Element }
            .associate { it.getAttribute("name") to it.textContent }
        assertEquals("Resource names must be unique", nodes.length, result.size)
        return result
    }

    @Test fun everySetupStringHasEnglishAndChineseResourcesWithMatchingPlaceholders() {
        val english = strings("values")
        val chinese = strings("values-zh")
        assertEquals(english.keys, chinese.keys)
        assertEquals(137, english.size)
        val placeholders = Regex("%[0-9]+\\$[sd]")
        for ((name, value) in english) {
            assertEquals(name, placeholders.findAll(value).map { it.value }.toList(),
                placeholders.findAll(chinese.getValue(name)).map { it.value }.toList())
        }
    }

    @Test fun activityUsesOnlyDeclaredSetupResourcesAndKeepsDeviceSelection() {
        val source = File("src/main/java/com/galaxyssi/chat/WatchSetupActivity.kt").readText()
        assertFalse(Regex("[\\u3400-\\u9fff]").containsMatchIn(source))
        assertFalse(source.contains("private fun tr("))
        assertTrue(source.contains("getString(if (glassesMode) glasses else watch)"))
        val names = Regex("R\\.string\\.(watch_setup_copy_[a-z0-9_]+)").findAll(source)
            .map { it.groupValues[1] }.toSet()
        assertEquals(strings("values").keys, names)
    }

    @Test fun archiveResourcesRetainMissingImageAndSourcePlaceholders() {
        val placeholders = Regex("%[0-9]+\\$[sd]")
        for (locale in listOf("values", "values-zh")) {
            val rows = strings(locale, "agent_web_archive_copy")
            assertEquals(listOf("%1\$d", "%2\$s"),
                placeholders.findAll(rows.getValue("agent_web_original_archive_notice")).map { it.value }.toList())
            assertEquals(1, placeholders.findAll(rows.getValue("agent_web_original_archive_filename")).count())
        }
        assertEquals("%1\$s-原貌.html", strings("values-zh", "agent_web_archive_copy").getValue("agent_web_original_archive_filename"))
    }
}
