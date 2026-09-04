package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopSurfaceCatalogTest {
    @Test
    fun parsesDisplaysWindowsAndIndependentSelection() {
        val catalog = parseDesktopSurfaceCatalog(
            JSONObject()
                .put("surface_contract", "galaxyssi.desktop-surfaces/1.0")
                .put(
                    "displays",
                    JSONArray()
                        .put(
                            JSONObject()
                                .put("display_id", "display:primary")
                                .put("name", "Display 1")
                                .put("primary", true)
                                .put(
                                    "bounds",
                                    JSONObject()
                                        .put("left", 0)
                                        .put("top", 0)
                                        .put("width", 1920)
                                        .put("height", 1080)
                                )
                        )
                        .put(
                            JSONObject()
                                .put("display_id", "display:left")
                                .put("name", "Display 2")
                                .put(
                                    "bounds",
                                    JSONObject()
                                        .put("left", -1280)
                                        .put("top", 40)
                                        .put("width", 1280)
                                        .put("height", 1024)
                                )
                        )
                )
                .put(
                    "windows",
                    JSONArray().put(
                        JSONObject()
                            .put("window_id", "window:browser")
                            .put("title", "Browser")
                            .put("display_id", "display:left")
                            .put("foreground", true)
                            .put("minimized", false)
                            .put(
                                "bounds",
                                JSONObject()
                                    .put("left", -1200)
                                    .put("top", 100)
                                    .put("width", 1000)
                                    .put("height", 760)
                            )
                    )
                )
                .put(
                    "selection",
                    JSONObject()
                        .put("selected_display_id", "display:left")
                        .put("selected_window_id", "window:browser")
                        .put("target_kind", "window")
                )
                .put(
                    "target",
                    JSONObject()
                        .put("title", "Browser")
                        .put(
                            "bounds",
                            JSONObject()
                                .put("left", -1200)
                                .put("top", 100)
                                .put("width", 1000)
                                .put("height", 760)
                        )
                )
        )

        requireNotNull(catalog)
        assertEquals(2, catalog.displays.size)
        assertEquals(1, catalog.windows.size)
        assertEquals("display:left", catalog.selection.displayId)
        assertEquals("window:browser", catalog.selection.windowId)
        assertEquals("window", catalog.selection.targetKind)
        assertEquals(-1200, catalog.targetBounds.left)
        assertTrue(catalog.windows.single().foreground)
    }

    @Test
    fun rejectsUnknownContractOrMissingDisplays() {
        assertNull(parseDesktopSurfaceCatalog(JSONObject()))
        assertNull(
            parseDesktopSurfaceCatalog(
                JSONObject()
                    .put("surface_contract", "galaxyssi.desktop-surfaces/1.0")
                    .put("displays", JSONArray())
            )
        )
    }
}
