package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class DesktopRemoteControlReceiptTest {
    private val signerId = "desktop_test"
    private val signatureKeyId = DesktopControlReceiptProtocol.digest("desktop-key".toByteArray())
    private val controllerFingerprint = DesktopControlReceiptProtocol.digest("phone-key".toByteArray())
    private val secret = "receipt-secret".toByteArray()

    @Test
    fun verifiesIdentityBoundReceiptAndRejectsTampering() {
        val request = request()
        val pending = DesktopControlReceiptProtocol.pendingRequest(
            request,
            clientRouteId = "client-route-1",
            controllerFingerprint = controllerFingerprint,
            controllerSignalName = "signalasi:phone"
        )
        val receipt = receipt(request, pending)

        assertEquals(
            "aa03fde69a349af4c0c1914a040982621486077bac6e7229c1f0ca838ee85f93",
            pending.requestSha256
        )
        assertTrue(verify(receipt, pending))
        assertFalse(DesktopControlReceiptProtocol.verify(
            payload = receipt,
            expectedSignerId = signerId,
            expectedSignatureKeyId = signatureKeyId,
            expectedControllerFingerprint = DesktopControlReceiptProtocol.digest("other-phone".toByteArray()),
            pendingRequest = pending,
            verifier = AgentReputationSignatureVerifier {
                    _, _, payload, signature ->
                signature == DesktopControlReceiptProtocol.digest(secret + payload)
            }
        ))
        assertFalse(verify(JSONObject(receipt.toString()).put("summary", "tampered"), pending))
        val screenshot = receipt.getJSONObject("output").getJSONObject("screenshot")
        screenshot.put("image_base64", Base64.getEncoder().encodeToString("tampered".toByteArray()))
        assertFalse(verify(receipt, pending))
    }

    @Test
    fun requestDigestBindsTaskAndControllerRoute() {
        val request = request()
        val first = DesktopControlReceiptProtocol.pendingRequest(
            request,
            "client-route-1",
            controllerFingerprint,
            "signalasi:phone"
        )
        val second = DesktopControlReceiptProtocol.pendingRequest(
            JSONObject(request.toString()).put("task_id", "task-2"),
            "client-route-1",
            controllerFingerprint,
            "signalasi:phone"
        )
        val third = DesktopControlReceiptProtocol.pendingRequest(
            request,
            "client-route-2",
            controllerFingerprint,
            "signalasi:phone"
        )

        assertNotEquals(first.requestSha256, second.requestSha256)
        assertNotEquals(first.requestSha256, third.requestSha256)
    }

    @Test
    fun rejectsReceiptForDifferentPendingAction() {
        val request = request()
        val pending = DesktopControlReceiptProtocol.pendingRequest(
            request,
            "client-route-1",
            controllerFingerprint,
            "signalasi:phone"
        )
        val mismatched = pending.copy(actionId = "another-action")

        assertFalse(verify(receipt(request, pending), mismatched))
    }

    private fun request(): JSONObject = JSONObject()
        .put("type", "desktop_executor_request")
        .put("task_id", "task-1")
        .put("action_id", "00000000-0000-4000-8000-000000000001")
        .put("authorization_id", "00000000-0000-4000-8000-000000000002")
        .put("tool_id", "desktop.screenshot")
        .put("input", JSONObject())
        .put("sent_at", 1_800_000_000_000L)
        .put("expires_at", 1_800_000_030_000L)

    private fun receipt(
        request: JSONObject,
        pending: DesktopControlPendingRequest
    ): JSONObject {
        val screenshotBytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0xd9.toByte())
        val screenshot = JSONObject()
            .put("image_mime", "image/jpeg")
            .put("image_base64", Base64.getEncoder().encodeToString(screenshotBytes))
            .put("width", 480)
            .put("height", 270)
            .put("original_width", 1920)
            .put("original_height", 1080)
            .put("captured_at", 1_800_000_001_000L)
        val evidenceSha256 = DesktopControlReceiptProtocol.digest(screenshotBytes)
        val summary = "Executed desktop screenshot"
        val screenshotMetadata = JSONObject(screenshot.toString())
            .apply {
                remove("image_base64")
                put("image_sha256", evidenceSha256)
            }
        val outputSha256 = DesktopControlReceiptProtocol.digest(JSONObject()
            .put("status", "succeeded")
            .put("summary", summary)
            .put("error", JSONObject.NULL)
            .put("output", JSONObject().put("screenshot", screenshotMetadata))
            .put("post_screenshot", JSONObject.NULL))
        val completedAt = 1_800_000_001_000L
        val receiptId = DesktopControlReceiptProtocol.digest(JSONObject()
            .put("task_id", request.getString("task_id"))
            .put("action_id", request.getString("action_id"))
            .put("authorization_id", request.getString("authorization_id"))
            .put("request_sha256", pending.requestSha256)
            .put("output_sha256", outputSha256)
            .put("evidence_sha256", evidenceSha256)
            .put("completed_at", completedAt))
        val receipt = JSONObject()
            .put("type", "desktop_action_receipt")
            .put("receipt_version", DesktopControlReceiptProtocol.RECEIPT_VERSION)
            .put("receipt_id", receiptId)
            .put("task_id", request.getString("task_id"))
            .put("action_id", request.getString("action_id"))
            .put("authorization_id", request.getString("authorization_id"))
            .put("tool_id", request.getString("tool_id"))
            .put("status", "succeeded")
            .put("summary", summary)
            .put("error_code", "")
            .put("error_retryable", false)
            .put("request_sha256", pending.requestSha256)
            .put("input_sha256", pending.inputSha256)
            .put("output_sha256", outputSha256)
            .put("evidence_sha256", evidenceSha256)
            .put("controller_fingerprint", controllerFingerprint)
            .put("started_at", 1_800_000_000_500L)
            .put("completed_at", completedAt)
            .put("duration_ms", 500L)
            .put("signer_id", signerId)
            .put("signature_key_id", signatureKeyId)
            .put("output", JSONObject().put("screenshot", screenshot))
            .put("post_screenshot", JSONObject.NULL)
        val signedFields = JSONObject()
        listOf(
            "receipt_version",
            "receipt_id",
            "task_id",
            "action_id",
            "authorization_id",
            "tool_id",
            "status",
            "summary",
            "error_code",
            "error_retryable",
            "request_sha256",
            "input_sha256",
            "output_sha256",
            "evidence_sha256",
            "controller_fingerprint",
            "started_at",
            "completed_at",
            "duration_ms",
            "signer_id",
            "signature_key_id"
        ).forEach { key -> signedFields.put(key, receipt.get(key)) }
        val signature = DesktopControlReceiptProtocol.digest(
            secret + agentReputationCanonicalJson(signedFields).toByteArray()
        )
        return receipt.put("signature", signature)
    }

    private fun verify(
        receipt: JSONObject,
        pending: DesktopControlPendingRequest
    ): Boolean = DesktopControlReceiptProtocol.verify(
        payload = receipt,
        expectedSignerId = signerId,
        expectedSignatureKeyId = signatureKeyId,
        expectedControllerFingerprint = controllerFingerprint,
        pendingRequest = pending,
        verifier = AgentReputationSignatureVerifier {
                _, _, payload, signature ->
            signature == DesktopControlReceiptProtocol.digest(secret + payload)
        }
    )
}
