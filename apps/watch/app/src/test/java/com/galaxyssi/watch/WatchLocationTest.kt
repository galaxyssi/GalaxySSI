package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchLocationTest {
    @Test fun recenterPreservesZoomAndTargetsVisibleCenter() {
        val viewport = WatchMapViewport(22.2, 113.5)
        viewport.scaleBy(1.7, 20.0, 30.0)
        viewport.pan(300.0, -500.0)
        val zoom = viewport.zoom
        viewport.centerOn(22.2, 113.5, 0.0, 45.0)
        val point = WatchMapProjection.point(22.2, 113.5, 2)
        assertEquals(zoom, viewport.zoom, 0.0)
        assertEquals(0.0, (point.first / 4 - viewport.x) * viewport.scale, 1e-6)
        assertEquals(45.0, (point.second / 4 - viewport.y) * viewport.scale, 1e-6)
    }

    @Test fun mapPinchPreservesFocusAndPanTracksFinger() {
        val viewport = WatchMapViewport(22.2, 113.5)
        val focusBefore = viewport.x + 70 / viewport.scale
        val yBefore = viewport.y - 35 / viewport.scale
        viewport.scaleBy(1.5, 70.0, -35.0)
        assertEquals(focusBefore, viewport.x + 70 / viewport.scale, 1e-9)
        assertEquals(yBefore, viewport.y - 35 / viewport.scale, 1e-9)
        val x = viewport.x
        val y = viewport.y
        viewport.pan(40.0, -20.0)
        assertEquals(x - 40 / viewport.scale, viewport.x, 1e-9)
        assertEquals(y + 20 / viewport.scale, viewport.y, 1e-9)
    }
    @Test fun mapZoomAndPanStayWithinWorldBounds() {
        val viewport = WatchMapViewport(0.0, 179.99)
        viewport.scaleBy(100000.0, 0.0, 0.0)
        assertEquals(18.0, viewport.zoom, 0.0)
        viewport.scaleBy(0.0000001, 0.0, 0.0)
        assertEquals(2.0, viewport.zoom, 0.0)
        viewport.pan(-100000.0, 100000.0)
        assertTrue(viewport.x >= 0 && viewport.x < 256)
        assertEquals(0.0, viewport.y, 0.0)
        viewport.scaleBy(Double.NaN, 0.0, 0.0)
        assertEquals(2.0, viewport.zoom, 0.0)
    }

    @Test fun decodesKeylessAddressWithoutInventingMissingRoads() {
        assertEquals("珠海 情侣路", WatchLocation.addressText(org.json.JSONObject("""{"features":[{"properties":{"city":"珠海","street":"情侣路","name":"情侣路"}}]}""")))
        assertEquals("", WatchLocation.addressText(org.json.JSONObject("""{"features":[]}""")))
    }
    @Test fun recognizesCurrentLocationAndRoadQuestions() {
        listOf("我在哪？", "现在是什么地方", "现在是什么道路", "帮我看看我现在在什么路", "我目前位于哪里", "where am I?", "我的位置显示地图").forEach {
            assertTrue(it, WatchLocationIntent.matches(it))
        }
    }
    @Test fun doesNotLocateForUnrelatedQuestionsOrOptOut() {
        listOf("明天珠海天气", "北京在哪", "翻译我在哪里", "不要获取我的位置", "don't show my location", "如何开发当前位置地图").forEach {
            assertFalse(it, WatchLocationIntent.matches(it))
        }
    }
    @Test fun rejectsStaleFutureInvalidAndUnknownAccuracySamples() {
        assertTrue(WatchLocation.validSample(22.2, 113.5, 20f, 1_000_000_000))
        assertFalse(WatchLocation.validSample(22.2, 113.5, 20f, 31_000_000_000))
        assertFalse(WatchLocation.validSample(22.2, 113.5, 20f, -1))
        assertFalse(WatchLocation.validSample(91.0, 113.5, 20f, 0))
        assertFalse(WatchLocation.validSample(22.2, Double.NaN, 20f, 0))
        assertFalse(WatchLocation.validSample(22.2, 113.5, Float.NaN, 0))
    }
    @Test fun mercatorCentersEquatorAndKeepsPolesFinite() {
        val center = WatchMapProjection.point(0.0, 0.0, 2)
        assertEquals(512.0, center.first, 0.001)
        assertEquals(512.0, center.second, 0.001)
        assertTrue(WatchMapProjection.point(90.0, 180.0, 16).second.isFinite())
        assertTrue(WatchMapProjection.point(-90.0, -180.0, 16).second.isFinite())
    }
    @Test fun locationMetadataRoundTripsWithoutTrustingInvalidCoordinates() {
        val fix = WatchLocationFix(22.2, 113.5, 20f, 1000, "gps")
        assertEquals(fix, WatchLocationFix.parse(fix.json()))
        assertNull(WatchLocationFix.parse(fix.json().replace("22.2", "222.2")))
        val task = WatchTask.create("api", "profile", "model", "我在哪").copy(location = fix.json(), localOperation = "location")
        assertEquals(task, WatchTask.fromJson(task.json()))
    }
}
