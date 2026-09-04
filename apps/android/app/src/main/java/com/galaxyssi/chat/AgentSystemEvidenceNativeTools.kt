package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Low-risk system facts that an Agent can cite through the normal native-tool receipt path. */
object AgentSystemEvidenceNativeTools {
    const val DEVICE_INFO = "galaxyssi.system.device.info"
    const val APP_INFO = "galaxyssi.system.app.info"
    const val LOCAL_TIME = "galaxyssi.system.time.local"
    const val JSON_VALIDATE = "galaxyssi.data.json.validate"

    val toolIds: Set<String> = linkedSetOf(DEVICE_INFO, APP_INFO, LOCAL_TIME, JSON_VALIDATE)

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val app = context.applicationContext
        return listOf(
            readOnlyDefinition(
                id = DEVICE_INFO,
                title = "Read device and Android version",
                description = "Returns the app-visible manufacturer, model, Android release and SDK level.",
                inputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = false)
            ) {
                AgentNativeToolExecutionResult.success(output = linkedMapOf(
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "device" to Build.DEVICE,
                    "android_release" to Build.VERSION.RELEASE,
                    "sdk_int" to Build.VERSION.SDK_INT,
                    "observed_at_epoch_ms" to System.currentTimeMillis()
                ))
            },
            readOnlyDefinition(
                id = APP_INFO,
                title = "Read GalaxySSI application version",
                description = "Returns this installed GalaxySSI build's package, version name and version code.",
                inputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = false)
            ) {
                AgentNativeToolExecutionResult.success(output = linkedMapOf(
                    "package_name" to app.packageName,
                    "version_name" to BuildConfig.VERSION_NAME,
                    "version_code" to BuildConfig.VERSION_CODE.toLong(),
                    "observed_at_epoch_ms" to System.currentTimeMillis()
                ))
            },
            readOnlyDefinition(
                id = LOCAL_TIME,
                title = "Read local date and timezone",
                description = "Returns the current local ISO timestamp, timezone id and UTC offset.",
                inputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = false)
            ) {
                val now = Date()
                val zone = TimeZone.getDefault()
                val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
                    timeZone = zone
                }
                AgentNativeToolExecutionResult.success(output = linkedMapOf(
                    "local_iso_8601" to formatter.format(now),
                    "timezone_id" to zone.id,
                    "utc_offset_millis" to zone.getOffset(now.time),
                    "observed_at_epoch_ms" to now.time
                ))
            },
            readOnlyDefinition(
                id = JSON_VALIDATE,
                title = "Validate a JSON value",
                description = "Parses a bounded JSON object or array and returns its canonical shape and digest.",
                inputSchema = AgentNativeJsonSchema.objectSchema(
                    properties = mapOf("json" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 65_536)),
                    required = setOf("json"),
                    additionalProperties = false
                )
            ) { invocation ->
                val raw = invocation.input["json"]?.toString().orEmpty().trim()
                val parsed = runCatching {
                    when {
                        raw.startsWith("{") -> "object" to JSONObject(raw).toString()
                        raw.startsWith("[") -> "array" to JSONArray(raw).toString()
                        else -> error("Only a JSON object or array is accepted")
                    }
                }.getOrElse { error ->
                    return@readOnlyDefinition AgentNativeToolExecutionResult.failure(
                        code = "invalid_json",
                        message = error.message ?: "Invalid JSON"
                    )
                }
                AgentNativeToolExecutionResult.success(output = linkedMapOf(
                    "valid" to true,
                    "kind" to parsed.first,
                    "canonical_json" to parsed.second,
                    "sha256" to AgentNativeJsonCodec.sha256(parsed.second)
                ))
            }
        )
    }

    private fun readOnlyDefinition(
        id: String,
        title: String,
        description: String,
        inputSchema: AgentNativeJsonSchema,
        execute: (AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
    ) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = title,
            description = description,
            location = AgentNativeToolLocation.ANDROID_SYSTEM,
            inputSchema = inputSchema,
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW,
            capabilities = setOf("system.evidence.read"),
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY
        ),
        executor = AgentNativeToolExecutor { invocation -> execute(invocation) },
        executorId = "galaxyssi.android.system_evidence"
    )
}
