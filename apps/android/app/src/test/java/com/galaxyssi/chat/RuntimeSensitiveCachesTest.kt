package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class RuntimeSensitiveCachesTest {
    @Test fun policiesSeparateTenMinutePlaintextFromOneDayMetadata() {
        assertEquals(600_000L, RuntimeCachePolicy.SENSITIVE_TTL_MILLIS)
        assertEquals(600_000_000_000L, RuntimeCachePolicy.SENSITIVE_TTL_NANOS)
        assertEquals(86_400_000_000_000L, RuntimeCachePolicy.STATIC_METADATA_TTL_NANOS)
    }

    @Test fun backgroundBoundaryClearsAllRegisteredCaches() {
        val first = Fixture()
        val second = Fixture()
        RuntimeSensitiveCaches.track(first)
        RuntimeSensitiveCaches.track(second)
        RuntimeSensitiveCaches.clearAll()
        assertFalse(first.active)
        assertFalse(second.active)
    }

    @Test fun maintenanceExpiresUnaccessedCachesWithoutAnotherRead() {
        val expired = CountDownLatch(1)
        val cache = object : RuntimeSensitiveCache {
            override fun pruneExpired(): Boolean { expired.countDown(); return false }
            override fun clearSensitive() = Unit
        }
        RuntimeSensitiveCaches.track(cache)
        assertTrue("Shared sweeper must run without a cache read", expired.await(5, TimeUnit.SECONDS))
    }

    @Test fun oneFailedCacheDoesNotPreventOtherCachesFromExpiring() {
        val failing = object : RuntimeSensitiveCache {
            override fun pruneExpired(): Boolean = error("fixture")
            override fun clearSensitive() = Unit
        }
        val healthy = Fixture()
        RuntimeSensitiveCaches.track(failing)
        RuntimeSensitiveCaches.track(healthy)
        RuntimeSensitiveCaches.pruneExpired()
        assertTrue(healthy.prunes >= 1)
        RuntimeSensitiveCaches.clearAll()
    }

    private class Fixture : RuntimeSensitiveCache {
        @Volatile var active = true
        @Volatile var prunes = 0
        override fun pruneExpired(): Boolean { prunes++; return active }
        override fun clearSensitive() { active = false }
    }
}
