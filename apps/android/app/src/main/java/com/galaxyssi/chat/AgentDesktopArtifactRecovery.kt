package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import android.util.AtomicFile
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal object AgentDesktopArtifactRecovery {
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor { Thread(it, "artifact-recovery").apply { isDaemon = true } }
    private var scannedAt = 0L
    private val hash = Regex("[0-9a-f]{64}")
    private val fields = listOf("client_route_id", "conversation_id", "task_id", "turn_id", "contact_id", "source_message_id")

    fun attach(context: Context, mqtt: MqttPoolTransport, routes: MqttPeerRoutes) {
        mqtt.onTick = {
            routes.maintenance()
            if (mqtt.isConnected) tick(context, routes::readyForTopic)
        }
    }

    fun tick(context: Context, ready: (String) -> Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (now - scannedAt < 15_000 || !running.compareAndSet(false, true)) return
        scannedAt = now
        executor.execute {
            try {
                recover(context, System.currentTimeMillis(), ready) { desktop, route, request ->
                    GalaxySSIMqttClient.publishDesktopControlPayload(desktop, request, durable = false, clientRouteId = route)
                }
            } catch (error: Exception) {
                Log.w("ArtifactRecovery", "Recovery scan deferred: ${error.javaClass.simpleName}")
            } finally { running.set(false) }
        }
    }

    fun remember(context: Context, payload: JSONObject, desktopId: String) {
        val id = payload.optString("artifact_id")
        if (!hash.matches(id)) return
        val directory = File(context.filesDir, "desktop-artifacts-v2/incoming/$id")
        if (!directory.isDirectory) return
        val binding = JSONObject().put("desktop_id", desktopId).put("peer_chat", payload.optBoolean("peer_chat"))
        fields.forEach { binding.put(it, payload.optString(it)) }
        val file = File(directory, "recovery.json")
        if (!file.exists()) write(file, JSONObject().put("binding", binding))
    }

    internal fun recover(context: Context, now: Long, ready: (String) -> Boolean,
        links: List<GalaxySSILinkProtocol.ServerLink> = GalaxySSILinkProtocol.allServerLinks(context),
        publish: (String, String, JSONObject) -> Boolean): Int {
        val root = File(context.filesDir, "desktop-artifacts-v2/incoming")
        var requested = 0
        for (directory in root.listFiles().orEmpty().sortedBy { File(it, "recovery.json").lastModified() }) {
            if (requested >= 8) break
            if (!directory.isDirectory || !hash.matches(directory.name)) continue
            runCatching {
                val manifest = read(File(directory, "manifest.json")) ?: return@runCatching
                val size = manifest.optLong("size_bytes")
                val count = manifest.optInt("chunk_count")
                if (manifest.optString("artifact_id") != directory.name || !hash.matches(manifest.optString("sha256")) ||
                    size !in 1..(64L * 1024 * 1024) || count !in 1..256 || (size + 262143) / 262144 != count.toLong()) return@runCatching
                val missing = (0 until count).filter { index ->
                    runCatching { AttachmentLocalStore.metadata(File(directory, "$index.chunk.sasie")).plaintextLength }
                        .getOrNull() != minOf(262144L, size - index * 262144L)
                }
                if (missing.isEmpty()) return@runCatching
                val file = File(directory, "recovery.json")
                val state = read(file) ?: JSONObject()
                val binding = state.optJSONObject("binding")
                    ?: AgentTaskIdentityStore.recoveryBinding(context, manifest.optString("task_id")) ?: return@runCatching
                if (binding.optString("task_id") != manifest.optString("task_id")) return@runCatching
                val route = binding.optString("client_route_id")
                val link = links.singleOrNull { it.paired && it.routes.clientRouteId == route } ?: return@runCatching
                if (binding.optString("desktop_id", link.desktopId) != link.desktopId || !ready(link.routes.control)) return@runCatching
                if (!binding.optBoolean("peer_chat") && !AgentTaskIdentityStore.matchesRegistered(context, binding)) return@runCatching
                val signature = missing.joinToString(",")
                val unchanged = state.optString("missing") == signature
                val latest = directory.listFiles().orEmpty().filter { it.name.endsWith(".chunk.sasie") }
                    .maxOfOrNull { it.lastModified() } ?: directory.lastModified()
                val next = state.optLong("next_at")
                if (now - latest in 0 until 10_000 || (unchanged && next - now in 1..300_000)) return@runCatching
                val attempts = if (unchanged) state.optInt("attempts").coerceIn(0, 4) + 1 else 1
                state.put("binding", binding.put("desktop_id", link.desktopId)).put("missing", signature)
                    .put("attempts", attempts).put("next_at", now + retryDelay(attempts))
                // Persist the pacing decision before network I/O. The next scan reuses the same partial files.
                write(file, state)
                val request = JSONObject().put("type", "artifact_missing_chunks_request")
                    .put("artifact_id", directory.name).put("artifact_uri", manifest.getString("artifact_uri"))
                    .put("sha256", manifest.getString("sha256")).put("task_id", manifest.getString("task_id"))
                    .put("missing_chunks", JSONArray(missing.take(8)))
                publish(link.desktopId, route, request)
                requested++
            }.onFailure { Log.w("ArtifactRecovery", "Partial artifact retained: ${it.javaClass.simpleName}") }
        }
        return requested
    }

    internal fun retryDelay(attempts: Int): Long = minOf(300_000L, 30_000L * (1L shl (attempts - 1).coerceIn(0, 4)))

    private fun read(file: File): JSONObject? = runCatching {
        if (!file.isFile || file.length() > 16_384) return null
        JSONObject(AtomicFile(file).openRead().bufferedReader().use { it.readText() })
    }.getOrNull()

    private fun write(file: File, value: JSONObject) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(value.toString().toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (error: Exception) { atomic.failWrite(stream); throw error }
    }
}
