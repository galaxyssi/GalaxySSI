package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal class AgentModelLoopCheckpoint(private val records: AgentModelLoopRecords) {
    var restored = false
        private set
    val cancelled: Boolean get() = records.read("cancelled") != null
    fun cancel() = records.write("cancelled", "{\"cancelled\":true}")

    fun initial(request: AgentModelToolLoopRequest, manifestSha: String): AgentModelToolLoopRequest {
        val messages = request.messages.map(::messageValue)
        val binding = mapOf("input" to request.recoveryInputIdentity.ifBlank { AgentNativeJsonCodec.sha256(messages) },
            "manifest" to manifestSha, "permissions" to request.grantedPermissions.sorted(),
            "consents" to request.grantedConsents.sorted(), "budget" to request.budget.toString())
        val existing = records.read("initial")
        if (existing == null) {
            records.write("initial", encode(mapOf("binding" to binding, "messages" to messages)))
            return request
        }
        val decoded = objectValue(existing)
        checkBinding(decoded["binding"], binding)
        restored = true
        return request.copy(messages = list(decoded["messages"]).map { message(map(it)) })
    }

    fun response(request: AgentModelRequest): AgentModelResponse? =
        records.read("model:${request.round}")?.let { encoded ->
            val record = objectValue(encoded)
            checkBinding(record["binding"], modelBinding(request))
            val value = map(record["response"])
            val usage = map(value["usage"])
            AgentModelResponse(value["text"] as String, list(value["calls"]).map { call(map(it)) },
                AgentModelUsage(number(usage["input"]), number(usage["output"])), map(value["metadata"]))
        }

    fun response(request: AgentModelRequest, response: AgentModelResponse) = records.write("model:${request.round}",
        encode(mapOf("binding" to modelBinding(request), "response" to mapOf("text" to response.assistantText,
            "calls" to response.toolCalls.map(::callValue), "metadata" to response.providerMetadata,
            "usage" to mapOf("input" to response.usage.inputTokens, "output" to response.usage.outputTokens)))))

    data class Invocation(val operation: String, val binding: String, val id: String,
        val result: AgentNativeToolResult?, val sequence: Long)

    fun invocation(round: Int, call: AgentModelToolCall, version: String, attempt: Int,
        idempotencyKey: String?, newId: () -> String): Invocation {
        val operation = "tool:" + AgentNativeJsonCodec.sha256(listOf(round, call.callId, attempt))
        val binding = AgentNativeJsonCodec.sha256(mapOf("call" to callValue(call), "version" to version,
            "effect" to idempotencyKey))
        val start = records.read("$operation:start")?.let(::objectValue)
        val id = if (start == null) newId().also {
            records.write("$operation:start", encode(mapOf("binding" to binding, "id" to it)))
        } else {
            checkBinding(start["binding"], binding)
            start["id"] as String
        }
        val result = records.read("$operation:result")?.let(::objectValue)
        if (result != null) checkBinding(result["binding"], binding)
        val native = result?.let {
            JSONObject(encode(it["result"])).toNativeToolResult()
                ?: throw AgentModelLoopRecoveryException("model_loop_result_invalid")
        }
        if (native != null && native.receipt.invocationId != id) {
            throw AgentModelLoopRecoveryException("model_loop_invocation_changed")
        }
        return Invocation(operation, binding, id, native, result?.let { number(it["sequence"]) } ?: 0L)
    }

    fun result(invocation: Invocation, result: AgentNativeToolResult, sequence: Long) = records.write(
        "${invocation.operation}:result", encode(mapOf("binding" to invocation.binding,
            "result" to result.toJsonValue(), "sequence" to sequence)))

    private fun modelBinding(request: AgentModelRequest) = AgentNativeJsonCodec.sha256(mapOf(
        "round" to request.round, "messages" to request.messages.map(::messageValue),
        "manifest" to request.toolManifestSha256))

    private fun checkBinding(first: Any?, second: Any?) {
        if (AgentNativeJsonCodec.sha256(first) != AgentNativeJsonCodec.sha256(second)) {
            throw AgentModelLoopRecoveryException("model_loop_checkpoint_binding_changed")
        }
    }

    private fun callValue(call: AgentModelToolCall) = mapOf("id" to call.callId, "tool" to call.toolId,
        "arguments" to call.arguments, "version" to call.toolVersion, "effect" to call.idempotencyKey, "depth" to call.depth)
    private fun call(value: Map<String, Any?>) = AgentModelToolCall(value["id"] as String, value["tool"] as String,
        map(value["arguments"]), value["version"] as? String, value["effect"] as? String, number(value["depth"]).toInt())

    private fun messageValue(message: AgentModelMessage): Map<String, Any?> = mapOf("role" to message.role.name,
        "text" to message.text, "calls" to message.toolCalls.map(::callValue), "result" to message.toolResult?.let {
            mapOf("id" to it.callId, "tool" to it.toolId, "status" to it.status, "output" to it.output,
                "message" to it.message, "error" to it.error?.let { error -> mapOf("code" to error.code,
                    "message" to error.message, "retryable" to error.retryable, "details" to error.details) },
                "invocation" to it.invocationId, "retries" to it.retryCount, "receipt" to it.receipt, "native" to it.nativeResult)
        })

    private fun message(value: Map<String, Any?>): AgentModelMessage {
        val result = value["result"]?.let { raw ->
            val r = map(raw)
            AgentModelToolResultContent(r["id"] as String, r["tool"] as String, r["status"] as String,
                map(r["output"]), r["message"] as String, r["error"]?.let { error ->
                    val e = map(error)
                    AgentNativeToolError(e["code"] as String, e["message"] as String,
                        e["retryable"] as Boolean, map(e["details"]))
                }, r["invocation"] as? String, number(r["retries"]).toInt(), r["receipt"]?.let(::map), r["native"]?.let(::map))
        }
        return AgentModelMessage(AgentModelMessageRole.valueOf(value["role"] as String), value["text"] as String,
            list(value["calls"]).map { call(map(it)) }, result)
    }

    private fun encode(value: Any?) = AgentNativeJsonCodec.stringify(value)
    private fun objectValue(encoded: String): Map<String, Any?> = try { map(convert(JSONObject(encoded))) }
    catch (error: Exception) { throw AgentModelLoopRecoveryException("model_loop_record_invalid", error) }
    private fun convert(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { convert(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { convert(value.get(it)) }
        else -> value
    }
    @Suppress("UNCHECKED_CAST")
    private fun map(value: Any?) = value as? Map<String, Any?> ?: throw AgentModelLoopRecoveryException("model_loop_object_missing")
    private fun list(value: Any?) = value as? List<*> ?: throw AgentModelLoopRecoveryException("model_loop_list_missing")
    private fun number(value: Any?) = (value as? Number)?.toLong() ?: throw AgentModelLoopRecoveryException("model_loop_number_missing")
}
