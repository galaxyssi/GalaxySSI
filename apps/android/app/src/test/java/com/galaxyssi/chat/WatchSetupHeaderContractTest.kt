package com.galaxyssi.chat

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

class WatchSetupHeaderContractTest {
    private fun layout(name: String) = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        .parse(File("src/main/res/layout/$name.xml"))
    private fun id(document: org.w3c.dom.Document, id: String): Element {
        val nodes = document.getElementsByTagName("*")
        return (0 until nodes.length).map { nodes.item(it) as Element }
            .first { it.getAttribute("android:id") == "@+id/$id" }
    }
    @Test fun titleMatchesExistingSettingsPages() {
        val main = layout("activity_main")
        val watch = layout("watch_setup_header")
        val source = id(main, "featureTitle")
        val target = id(watch, "watchSetupTitle")
        listOf("layout_width", "layout_height", "layout_weight", "gravity", "textSize", "textStyle", "textColor").forEach {
            assertEquals(it, source.getAttribute("android:$it"), target.getAttribute("android:$it"))
        }
        val sourceBar = source.parentNode as Element
        listOf("layout_height", "paddingStart", "paddingEnd", "background", "gravity").forEach {
            assertEquals(it, sourceBar.getAttribute("android:$it"), watch.documentElement.getAttribute("android:$it"))
        }
    }
    @Test fun backButtonReusesExistingIconAndHitTargetStyle() {
        assertEquals(id(layout("activity_main"), "featureBackButton").getAttribute("style"),
            id(layout("watch_setup_header"), "watchSetupBack").getAttribute("style"))
        val source = File("src/main/java/com/galaxyssi/chat/WatchSetupActivity.kt").readText()
        assertTrue(source.contains("layoutInflater.inflate(R.layout.watch_setup_header"))
        assertFalse(source.contains("text = \"\u2039\""))
    }
}
