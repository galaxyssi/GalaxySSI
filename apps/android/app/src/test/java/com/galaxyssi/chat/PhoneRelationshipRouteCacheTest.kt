package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class PhoneRelationshipRouteCacheTest {
    private fun route(local: String = "a", remote: String = "b") = GalaxySSILinkProtocol.Routes(
        "r".repeat(22), "s".repeat(43), local, remote)

    @Test fun repeatedVerifiedIdentityDoesNotRepeatAgreement() {
        val cache = PhoneRelationshipRouteCache()
        var derived = 0
        repeat(1000) { assertEquals(route(), cache.getOrDerive("a", "public-key", "b") { derived++; route() }) }
        assertEquals(1, derived)
    }

    @Test fun identityKeyFingerprintAndLocalIdentityChangesAlwaysMiss() {
        val cache = PhoneRelationshipRouteCache()
        var derived = 0
        cache.getOrDerive("a", "key", "b") { derived++; route() }
        cache.getOrDerive("a", "key-new", "b") { derived++; route() }
        cache.getOrDerive("a", "key", "c") { derived++; route(remote = "c") }
        cache.getOrDerive("d", "key", "b") { derived++; route(local = "d") }
        assertEquals(4, derived)
    }

    @Test fun failedVerificationIsNeverCached() {
        val cache = PhoneRelationshipRouteCache()
        var derived = 0
        repeat(2) { assertNull(cache.getOrDerive("a", "bad-key", "b") { derived++; null }) }
        assertEquals(2, derived)
    }

    @Test fun expiryAndRuntimeClearDiscardSecretsWithoutSlidingTtl() {
        var now = 0L
        val cache = PhoneRelationshipRouteCache(clock = { now })
        cache.getOrDerive("a", "key", "b") { route() }
        now = RuntimeCachePolicy.SENSITIVE_TTL_NANOS - 1
        cache.getOrDerive("a", "key", "b") { error("Must hit") }
        now++
        var derived = 0
        cache.getOrDerive("a", "key", "b") { derived++; route() }
        RuntimeSensitiveCaches.clearAll()
        cache.getOrDerive("a", "key", "b") { derived++; route() }
        assertEquals(2, derived)
    }
}
