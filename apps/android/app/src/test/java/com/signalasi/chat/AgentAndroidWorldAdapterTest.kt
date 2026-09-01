package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentAndroidWorldAdapterTest {
    @Test
    fun codecAndEvaluatorVerifyConcreteAndroidState() {
        val task = AgentAndroidWorldTaskCodec.decode(
            """{
              "task_id":"open-settings-test",
              "instruction":"Open Wi-Fi settings and show Network preferences",
              "category":"device_control",
              "required_packages":["com.android.settings"],
              "verifiers":[
                {"kind":"foreground_package","key":"package","expected":"com.android.settings"},
                {"kind":"visible_text","key":"screen","expected":"Network preferences","operator":"contains"},
                {"kind":"app_file","key":"receipts/result.json","expected":"true","operator":"exists"},
                {"kind":"system_setting","key":"global:airplane_mode_on","expected":"0"}
              ]
            }""".trimIndent()
        )
        val result = AgentAndroidWorldEvaluator.evaluate(
            task,
            AgentAndroidWorldObservation(
                foregroundPackage = "com.android.settings",
                visibleTexts = listOf("Wi-Fi", "Network preferences"),
                appFiles = mapOf("receipts/result.json" to true),
                systemSettings = mapOf("global:airplane_mode_on" to "0")
            ),
            runId = "run-1"
        )

        assertEquals("open-settings-test", task.id)
        assertTrue(result.passed)
        assertTrue(result.verifierResults.all(AgentAndroidWorldVerifierResult::passed))
    }

    @Test
    fun evaluatorReportsVerifiedFailureInsteadOfGuessingSuccess() {
        val task = AgentAndroidWorldTask(
            id = "wrong-screen",
            instruction = "Open Settings",
            category = "device_control",
            requiredPackages = listOf("com.android.settings"),
            verifiers = listOf(AgentAndroidWorldVerifier(
                kind = AgentAndroidWorldVerifierKind.FOREGROUND_PACKAGE,
                key = "package",
                expected = "com.android.settings"
            ))
        )

        val result = AgentAndroidWorldEvaluator.evaluate(
            task,
            AgentAndroidWorldObservation(
                foregroundPackage = "com.signalasi.chat",
                visibleTexts = emptyList(),
                appFiles = emptyMap(),
                systemSettings = emptyMap()
            ),
            runId = "run-2"
        )

        assertFalse(result.passed)
        assertFalse(result.verifierResults.single().passed)
    }
}
