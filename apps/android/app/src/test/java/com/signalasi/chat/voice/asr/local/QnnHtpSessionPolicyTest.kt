package com.signalasi.chat.voice.asr.local

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QnnHtpSessionPolicyTest {
    @Test
    fun enablesSharedAllocatorOnlyWhenCdsprpcIsAvailable() {
        val enabled = QnnHtpSessionPolicy.providerOptions(sharedMemoryAvailable = true)
        val disabled = QnnHtpSessionPolicy.providerOptions(sharedMemoryAvailable = false)

        assertEquals("htp", enabled["backend_type"])
        assertEquals("0", enabled["offload_graph_io_quantization"])
        assertEquals("1", enabled[QnnHtpSessionPolicy.SHARED_MEMORY_OPTION])
        assertEquals("0", disabled[QnnHtpSessionPolicy.SHARED_MEMORY_OPTION])
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
