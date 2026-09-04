package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

data class AgentEvalFaultControllerLease(
    val controllerId: String,
    val packageName: String,
    val deviceModel: String,
    val issuedAtMillis: Long,
    val heartbeatAtMillis: Long,
    val expiresAtMillis: Long
)

data class AgentEvalFaultRequest(
    val nonce: String,
    val caseId: String,
    val trialId: String = "",
    val runId: String,
    val condition: AgentEvalCondition,
    val controllerId: String,
    val packageName: String,
    val deviceModel: String,
    val createdAtMillis: Long,
    val expiresAtMillis: Long
)

data class AgentEvalFaultReceipt(
    val nonce: String,
    val caseId: String,
    val trialId: String = "",
    val runId: String,
    val condition: AgentEvalCondition,
    val controllerId: String,
    val injectedAtMillis: Long,
    val action: String
)

internal object AgentEvalFaultControllerProtocol {
    fun activeLease(
        lease: AgentEvalFaultControllerLease?,
        packageName: String,
        deviceModel: String,
        nowMillis: Long
    ): Boolean = lease != null &&
        lease.controllerId.isNotBlank() &&
        lease.packageName == packageName &&
        lease.deviceModel == deviceModel &&
        lease.issuedAtMillis in 1..nowMillis + CLOCK_SKEW_MILLIS &&
        lease.heartbeatAtMillis in lease.issuedAtMillis..nowMillis + CLOCK_SKEW_MILLIS &&
        lease.expiresAtMillis > nowMillis &&
        lease.expiresAtMillis - lease.heartbeatAtMillis <= MAX_LEASE_MILLIS

    fun validReceipt(
        request: AgentEvalFaultRequest,
        receipt: AgentEvalFaultReceipt?,
        activeControllerId: String,
        nowMillis: Long
    ): Boolean = receipt != null &&
        request.controllerId.isNotBlank() &&
        receipt.nonce == request.nonce &&
        receipt.caseId == request.caseId &&
        receipt.trialId == request.trialId &&
        receipt.runId == request.runId &&
        receipt.condition == request.condition &&
        receipt.controllerId == request.controllerId &&
        receipt.controllerId == activeControllerId &&
        receipt.action == request.condition.wireValue &&
        receipt.injectedAtMillis in request.createdAtMillis..nowMillis + CLOCK_SKEW_MILLIS &&
        receipt.injectedAtMillis <= request.expiresAtMillis

    const val CLOCK_SKEW_MILLIS = 30_000L
    const val MAX_LEASE_MILLIS = 5L * 60L * 1_000L
}

class AgentEvalFaultControllerStore(context: Context) {
    private val appContext = context.applicationContext
    private val root = File(appContext.filesDir, ROOT_DIRECTORY)
    private val requestDirectory = File(root, REQUEST_DIRECTORY)
    private val receiptDirectory = File(root, RECEIPT_DIRECTORY)

    fun activeLease(nowMillis: Long = System.currentTimeMillis()): AgentEvalFaultControllerLease? {
        val lease = decodeLease(readJson(File(root, LEASE_FILE))) ?: return null
        return lease.takeIf {
            AgentEvalFaultControllerProtocol.activeLease(
                lease = it,
                packageName = appContext.packageName,
                deviceModel = Build.MODEL,
                nowMillis = nowMillis
            )
        }
    }

    fun request(
        caseId: String,
        trialId: String,
        runId: String,
        condition: AgentEvalCondition,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentEvalFaultRequest? {
        val lease = activeLease(nowMillis)
        if (condition == AgentEvalCondition.NORMAL || lease == null) return null
        prune(nowMillis)
        val request = AgentEvalFaultRequest(
            nonce = UUID.randomUUID().toString(),
            caseId = caseId.trim(),
            trialId = trialId.trim(),
            runId = runId.trim(),
            condition = condition,
            controllerId = lease.controllerId,
            packageName = appContext.packageName,
            deviceModel = Build.MODEL,
            createdAtMillis = nowMillis,
            expiresAtMillis = nowMillis + REQUEST_TTL_MILLIS
        )
        writeJson(requestFile(request.nonce), encode(request))
        return request
    }

    fun requestForTrial(
        caseId: String,
        trialId: String,
        condition: AgentEvalCondition,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentEvalFaultRequest? {
        if (caseId.isBlank() || trialId.isBlank() || condition == AgentEvalCondition.NORMAL) return null
        val lease = activeLease(nowMillis) ?: return null
        return requestDirectory.listFiles().orEmpty()
            .asSequence()
            .filter(File::isFile)
            .mapNotNull { decodeRequest(readJson(it)) }
            .filter { it.caseId == caseId && it.trialId == trialId && it.condition == condition }
            .filter { it.controllerId == lease.controllerId }
            .filter { it.expiresAtMillis + RECOVERY_GRACE_MILLIS >= nowMillis }
            .maxByOrNull(AgentEvalFaultRequest::createdAtMillis)
    }

    fun verifiedReceipt(
        request: AgentEvalFaultRequest,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentEvalFaultReceipt? {
        val lease = activeLease(nowMillis) ?: return null
        val receipt = decodeReceipt(readJson(receiptFile(request.nonce))) ?: return null
        return receipt.takeIf {
            AgentEvalFaultControllerProtocol.validReceipt(request, it, lease.controllerId, nowMillis)
        }
    }

    fun markCompleted(request: AgentEvalFaultRequest, completedRunId: String) {
        val completion = JSONObject()
            .put("nonce", request.nonce)
            .put("case_id", request.caseId)
            .put("source_run_id", request.runId)
            .put("completed_run_id", completedRunId.trim())
            .put("completed_at_millis", System.currentTimeMillis())
        writeJson(File(root, "$COMPLETION_PREFIX${request.nonce}.json"), completion)
    }

    private fun prune(nowMillis: Long) {
        requestDirectory.listFiles().orEmpty().forEach { file ->
            val request = decodeRequest(readJson(file))
            if (request == null || request.expiresAtMillis + RETENTION_MILLIS < nowMillis) file.delete()
        }
        receiptDirectory.listFiles().orEmpty().forEach { file ->
            val receipt = decodeReceipt(readJson(file))
            if (receipt == null || receipt.injectedAtMillis + RETENTION_MILLIS < nowMillis) file.delete()
        }
        root.listFiles { file -> file.name.startsWith(COMPLETION_PREFIX) }.orEmpty().forEach { file ->
            val completedAt = readJson(file)?.optLong("completed_at_millis") ?: 0L
            if (completedAt <= 0L || completedAt + RETENTION_MILLIS < nowMillis) file.delete()
        }
    }

    private fun requestFile(nonce: String) = File(requestDirectory, "${safeNonce(nonce)}.json")
    private fun receiptFile(nonce: String) = File(receiptDirectory, "${safeNonce(nonce)}.json")

    private fun safeNonce(value: String): String = value.filter { it.isLetterOrDigit() || it == '-' }.take(80)

    private fun readJson(file: File): JSONObject? = runCatching {
        if (!file.isFile) return@runCatching null
        JSONObject(file.readText(Charsets.UTF_8))
    }.getOrNull()

    private fun writeJson(file: File, json: JSONObject) {
        file.parentFile?.mkdirs()
        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try {
            output.write(json.toString().toByteArray(Charsets.UTF_8))
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun encode(value: AgentEvalFaultRequest) = JSONObject()
        .put("schema_version", 3)
        .put("nonce", value.nonce)
        .put("case_id", value.caseId)
        .put("trial_id", value.trialId)
        .put("run_id", value.runId)
        .put("condition", value.condition.wireValue)
        .put("controller_id", value.controllerId)
        .put("package_name", value.packageName)
        .put("device_model", value.deviceModel)
        .put("created_at_millis", value.createdAtMillis)
        .put("expires_at_millis", value.expiresAtMillis)

    private fun decodeLease(json: JSONObject?): AgentEvalFaultControllerLease? = runCatching {
        require(json != null && json.optInt("schema_version") in 1..3)
        AgentEvalFaultControllerLease(
            controllerId = json.getString("controller_id"),
            packageName = json.getString("package_name"),
            deviceModel = json.getString("device_model"),
            issuedAtMillis = json.getLong("issued_at_millis"),
            heartbeatAtMillis = json.getLong("heartbeat_at_millis"),
            expiresAtMillis = json.getLong("expires_at_millis")
        )
    }.getOrNull()

    private fun decodeRequest(json: JSONObject?): AgentEvalFaultRequest? = runCatching {
        require(json != null && json.optInt("schema_version") in 1..3)
        AgentEvalFaultRequest(
            nonce = json.getString("nonce"),
            caseId = json.getString("case_id"),
            trialId = json.optString("trial_id"),
            runId = json.getString("run_id"),
            condition = AgentEvalCondition.entries.first { it.wireValue == json.getString("condition") },
            controllerId = json.optString("controller_id"),
            packageName = json.getString("package_name"),
            deviceModel = json.getString("device_model"),
            createdAtMillis = json.getLong("created_at_millis"),
            expiresAtMillis = json.getLong("expires_at_millis")
        )
    }.getOrNull()

    private fun decodeReceipt(json: JSONObject?): AgentEvalFaultReceipt? = runCatching {
        require(json != null && json.optInt("schema_version") in 1..2)
        AgentEvalFaultReceipt(
            nonce = json.getString("nonce"),
            caseId = json.getString("case_id"),
            trialId = json.optString("trial_id"),
            runId = json.getString("run_id"),
            condition = AgentEvalCondition.entries.first { it.wireValue == json.getString("condition") },
            controllerId = json.getString("controller_id"),
            injectedAtMillis = json.getLong("injected_at_millis"),
            action = json.getString("action")
        )
    }.getOrNull()

    private companion object {
        const val ROOT_DIRECTORY = "agent_eval_fault_controller"
        const val REQUEST_DIRECTORY = "requests"
        const val RECEIPT_DIRECTORY = "receipts"
        const val LEASE_FILE = "lease.json"
        const val COMPLETION_PREFIX = "completed-"
        val REQUEST_TTL_MILLIS = TimeUnit.MINUTES.toMillis(15)
        val RECOVERY_GRACE_MILLIS = TimeUnit.MINUTES.toMillis(10)
        val RETENTION_MILLIS = TimeUnit.DAYS.toMillis(1)
    }
}
