package com.signalasi.chat.voice.asr.local

internal object QnnHtpSessionPolicy {
    const val SHARED_MEMORY_OPTION = "enable_htp_shared_memory_allocator"

    fun providerOptions(sharedMemoryAvailable: Boolean): Map<String, String> = linkedMapOf(
        "backend_type" to "htp",
        "offload_graph_io_quantization" to "0",
        SHARED_MEMORY_OPTION to if (sharedMemoryAvailable) "1" else "0"
    )
}

internal class QnnHtpSharedMemoryAvailability(
    private val loadLibrary: (String) -> Unit
) {
    @Volatile
    private var cached: Boolean? = null

    fun isAvailable(): Boolean = cached ?: synchronized(this) {
        cached ?: runCatching { loadLibrary(LIBRARY_NAME) }
            .isSuccess
            .also { cached = it }
    }

    companion object {
        private const val LIBRARY_NAME = "cdsprpc"

        val android = QnnHtpSharedMemoryAvailability(System::loadLibrary)
    }
}
