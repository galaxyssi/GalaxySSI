package com.galaxyssi.chat.voice.asr.local

internal object QnnHtpSessionPolicy {
    const val SHARED_MEMORY_OPTION = "enable_htp_shared_memory_allocator"
    const val PERFORMANCE_MODE_OPTION = "htp_performance_mode"
    const val CONTEXT_PRIORITY_OPTION = "qnn_context_priority"
    const val RPC_CONTROL_LATENCY_OPTION = "rpc_control_latency"

    const val RUN_PERFORMANCE_MODE_OPTION = "qnn.perf_mode"
    const val RUN_RPC_CONTROL_LATENCY_OPTION = "qnn.rpc_control_latency"

    private const val PERFORMANCE_MODE = "burst"
    private const val CONTEXT_PRIORITY = "high"
    private const val RPC_CONTROL_LATENCY_US = "100"

    fun providerOptions(
        backendPath: String,
        sharedMemoryAvailable: Boolean
    ): Map<String, String> = linkedMapOf(
        "backend_path" to backendPath,
        "offload_graph_io_quantization" to "0",
        SHARED_MEMORY_OPTION to if (sharedMemoryAvailable) "1" else "0",
        PERFORMANCE_MODE_OPTION to PERFORMANCE_MODE,
        CONTEXT_PRIORITY_OPTION to CONTEXT_PRIORITY,
        RPC_CONTROL_LATENCY_OPTION to RPC_CONTROL_LATENCY_US
    )

    val runConfigEntries: Map<String, String> = linkedMapOf(
        RUN_PERFORMANCE_MODE_OPTION to PERFORMANCE_MODE,
        RUN_RPC_CONTROL_LATENCY_OPTION to RPC_CONTROL_LATENCY_US
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
