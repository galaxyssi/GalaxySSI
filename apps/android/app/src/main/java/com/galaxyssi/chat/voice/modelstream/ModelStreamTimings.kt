package com.galaxyssi.chat.voice.modelstream

import okhttp3.Call
import okhttp3.Connection
import okhttp3.EventListener
import okhttp3.Handshake
import okhttp3.Protocol
import okhttp3.Response
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy

data class ModelStreamTiming(val requestId: String, val milliseconds: Map<String, Long>)

/** Transport-observable spans only: provider queue/prefill cannot be separated by client clocks. */
internal class ModelStreamTimings(
    private val requestId: String,
    private val now: () -> Long = { System.nanoTime() / 1_000_000L }
) : EventListener() {
    private val started = now()
    private val marks = linkedMapOf<String, Long>()
    private val spans = linkedMapOf<String, Long>()
    private var connects = 0L
    private var acquired = false

    @Synchronized fun mark(name: String) { marks.putIfAbsent(name, now()) }
    @Synchronized private fun begin(name: String) { marks["${name}_start"] = now() }
    @Synchronized private fun end(name: String) {
        marks.remove("${name}_start")?.let { spans[name] = (spans[name] ?: 0L) + (now() - it).coerceAtLeast(0L) }
    }

    override fun dnsStart(call: Call, domainName: String) = begin("dns_ms")
    override fun dnsEnd(call: Call, domainName: String, inetAddressList: List<InetAddress>) = end("dns_ms")
    override fun connectStart(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy) {
        synchronized(this) { connects++ }
        begin("connect_ms")
    }
    override fun connectEnd(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy, protocol: Protocol?) = end("connect_ms")
    override fun connectFailed(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy, protocol: Protocol?, ioe: java.io.IOException) = end("connect_ms")
    override fun secureConnectStart(call: Call) = begin("tls_ms")
    override fun secureConnectEnd(call: Call, handshake: Handshake?) = end("tls_ms")
    override fun connectionAcquired(call: Call, connection: Connection) { synchronized(this) { acquired = true } }
    override fun requestHeadersStart(call: Call) = mark("request_write_start")
    override fun requestBodyEnd(call: Call, byteCount: Long) = mark("request_write_end")
    override fun responseHeadersEnd(call: Call, response: Response) = mark("response_headers")

    @Synchronized fun snapshot(): ModelStreamTiming {
        fun since(name: String) = marks[name]?.minus(started)?.coerceAtLeast(0L) ?: -1L
        fun between(start: String, end: String): Long {
            val from = marks[start] ?: return -1L
            return marks[end]?.minus(from)?.coerceAtLeast(0L) ?: -1L
        }
        return ModelStreamTiming(requestId, linkedMapOf(
            "local_queue_ms" to since("reader_started"),
            "dns_ms" to (spans["dns_ms"] ?: -1L),
            // connect_ms includes TLS; these spans must not be added together.
            "connect_ms" to (spans["connect_ms"] ?: -1L), "tls_ms" to (spans["tls_ms"] ?: -1L),
            "connection_reused" to if (acquired && connects == 0L) 1L else 0L,
            "connect_attempts" to connects,
            "request_write_ms" to between("request_write_start", "request_write_end"),
            "response_headers_wait_ms" to between("request_write_end", "response_headers"),
            "headers_to_first_text_ms" to between("response_headers", "first_text"),
            "first_frame_ms" to since("first_frame"), "first_text_ms" to since("first_text"),
            "first_tool_ms" to since("first_tool"),
            "stream_tail_ms" to (marks["first_text"]?.let { (now() - it).coerceAtLeast(0L) } ?: -1L),
            "total_ms" to (now() - started).coerceAtLeast(0L)
        ))
    }
}
