package com.galaxyssi.chat.voice.asr.local

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QnnHtpSessionPolicyTest {
    @Test
    fun enablesSharedAllocatorOnlyWhenCdsprpcIsAvailable() {
        val backend = "/data/app/com.galaxyssi.chat/lib/arm64/libQnnHtp.so"
        val enabled = QnnHtpSessionPolicy.providerOptions(backend, sharedMemoryAvailable = true)
        val disabled = QnnHtpSessionPolicy.providerOptions(backend, sharedMemoryAvailable = false)

        assertEquals(backend, enabled["backend_path"])
        assertFalse(enabled.containsKey("backend_type"))
        assertEquals("0", enabled["offload_graph_io_quantization"])
        assertEquals("1", enabled[QnnHtpSessionPolicy.SHARED_MEMORY_OPTION])
        assertEquals("0", disabled[QnnHtpSessionPolicy.SHARED_MEMORY_OPTION])
        assertEquals("burst", enabled[QnnHtpSessionPolicy.PERFORMANCE_MODE_OPTION])
        assertEquals("high", enabled[QnnHtpSessionPolicy.CONTEXT_PRIORITY_OPTION])
        assertEquals("100", enabled[QnnHtpSessionPolicy.RPC_CONTROL_LATENCY_OPTION])
    }

    @Test
    fun keepsEachInferenceInBurstModeWithLowRpcLatency() {
        assertEquals(
            mapOf(
                QnnHtpSessionPolicy.RUN_PERFORMANCE_MODE_OPTION to "burst",
                QnnHtpSessionPolicy.RUN_RPC_CONTROL_LATENCY_OPTION to "100"
            ),
            QnnHtpSessionPolicy.runConfigEntries
        )
    }

    @Test
    fun cachesSuccessfulNativeLibraryProbe() {
        val calls = AtomicInteger()
        val availability = QnnHtpSharedMemoryAvailability { library ->
            assertEquals("cdsprpc", library)
            calls.incrementAndGet()
        }

        assertTrue(availability.isAvailable())
        assertTrue(availability.isAvailable())
        assertEquals(1, calls.get())
    }

    @Test
    fun cachesMissingNativeLibraryProbeWithoutThrowing() {
        val calls = AtomicInteger()
        val availability = QnnHtpSharedMemoryAvailability {
            calls.incrementAndGet()
            throw UnsatisfiedLinkError("not available")
        }

        assertFalse(availability.isAvailable())
        assertFalse(availability.isAvailable())
        assertEquals(1, calls.get())
    }
}
