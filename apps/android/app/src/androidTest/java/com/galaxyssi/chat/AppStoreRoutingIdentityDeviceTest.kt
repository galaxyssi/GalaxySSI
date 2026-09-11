package com.galaxyssi.chat

import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class AppStoreRoutingIdentityDeviceTest {
    @Test fun routingReadsTheSameIdentityWithoutConstructingTheFullProfile() {
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fullSamples = JSONArray()
        val routeSamples = JSONArray()
        repeat(6) {
            val fullStarted = SystemClock.elapsedRealtimeNanos()
            val expected = AppStore.profile(context).getString("device_id")
            fullSamples.put((SystemClock.elapsedRealtimeNanos() - fullStarted) / 1_000_000.0)
            val routeStarted = SystemClock.elapsedRealtimeNanos()
            val actual = AppStore.localDeviceRouteId(context)
            routeSamples.put((SystemClock.elapsedRealtimeNanos() - routeStarted) / 1_000_000.0)
            assertTrue(GalaxySSILinkProtocol.validRouteId(actual))
            assertEquals(expected, actual)
        }
        File(context.getExternalFilesDir("reports"), "routing-identity-latency.json").writeText(
            JSONObject().put("same_identity", true).put("full_profile_ms", fullSamples)
                .put("route_only_ms", routeSamples).toString(2)
        )
    }
}
