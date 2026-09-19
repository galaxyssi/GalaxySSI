package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import com.galaxyssi.chat.voice.modelstream.ModelStreamRequest
import com.galaxyssi.chat.voice.modelstream.ModelStreamTransport
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject

/** Only the wire encoding changes; evidence, limits, checks and checkpoints stay in one loop. */
internal object CloudResearchRequestMode {
    fun apply(request: ModelStreamRequest, streaming: Boolean): ModelStreamRequest {
        if (streaming) return request
        val body = JSONObject(request.bodyJson)
        val endpoint = if (request.provider == ModelStreamProvider.GEMINI) {
            body.remove("stream")
            request.endpoint.toHttpUrl().newBuilder()
                .encodedPath(request.endpoint.toHttpUrl().encodedPath.replace(":streamGenerateContent", ":generateContent"))
                .removeAllQueryParameters("alt").build().toString()
        } else {
            body.put("stream", false)
            body.remove("stream_options")
            request.endpoint
        }
        return request.copy(endpoint = endpoint, bodyJson = body.toString(), transport = ModelStreamTransport.COMPLETE_JSON)
    }
}
