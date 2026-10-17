package com.galaxyssi.chat

import org.json.JSONObject

internal object AgentBrowserRuntimeReadiness {
    private val dependencies = mapOf("linux-base" to "shell.execute", "node-js" to "javascript.execute",
        "browser-automation" to "browser.automation.execute")

    fun availability(status: AgentOnDeviceRuntimeStatus): AgentNativeToolAvailability {
        val missing = dependencies.filter { (id, capability) ->
            val pack = status.packs.firstOrNull { it.id == id }
            pack?.state != AgentRuntimePackState.READY || capability !in pack.manifest?.capabilities.orEmpty()
        }.keys
        if (missing.isNotEmpty()) return AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP,
            "Browser dependencies are not ready: ${missing.joinToString()}. Use ${AgentOnDeviceRuntimeTools.INSTALL_PACK}, " +
                "then browser.observe operation=readiness. Installation alone does not confirm a browser launch.")
        val backend = AgentOnDeviceRuntimeTools.executionAvailability(status)
        return if (backend.status == AgentNativeToolAvailabilityStatus.AVAILABLE) backend.copy(
            reason = "Dependencies installed; execution checks Node.js and the launcher. Use operation=readiness to verify Chromium startup.") else backend
    }

    /** Only pre-dispatch checks may assert executed=false. An arbitrary process exit cannot. */
    fun shellPrelude(): String = buildString {
        append("browser_setup_error() { printf '%s\\n' \"{\\\"ok\\\":false,\\\"error\\\":{\\\"code\\\":\\\"\$1\\\",\\\"message\\\":\\\"\$2\\\",\\\"details\\\":{\\\"executed\\\":false,\\\"goal_terminal\\\":false}}}\"; exit 0; }\n")
        for ((command, pack) in listOf("node" to "node-js", "galaxyssi-browser" to "browser-automation")) {
            val code = if (command == "node") "node" else "browser_launcher"
            append("if ! command -v $command >/dev/null 2>&1; then\n")
            append("  if [ -x /opt/galaxyssi/packs/$pack/bin/$command ]; then\n")
            append("    browser_setup_error ${code}_path_missing 'Installed executable is absent from PATH. Inspect runtime.diagnose and the guest PATH; do not reinstall blindly.'\n")
            append("  else browser_setup_error ${code}_missing 'Executable is missing from the mounted $pack pack. Inspect runtime.diagnose and installed pack mounts.'; fi\nfi\n")
        }
        append("node --version >/dev/null 2>&1 || browser_setup_error node_start_failed 'Node.js was found but could not start. Inspect the guest executable and native libraries.'\n")
    }

    fun verifyInstalled(
        invocation: AgentNativeToolInvocation,
        output: Map<String, Any?>,
        execute: (AgentRuntimeExecutionRequest) -> AgentRuntimeExecutionResponse,
        helpers: () -> List<AgentRuntimeHostInput>
    ): AgentNativeToolExecutionResult {
        invocation.reportProgress("verify", "Starting Chromium and verifying a local page before continuing the task")
        val response = try {
            execute(AgentInteractiveBrowserTools.runtimeRequest(invocation, helpers(), readinessOnly = true).copy(
                requestId = invocation.context.invocationId + "-browser-readiness",
                networkEnabled = false
            ))
        } catch (error: Exception) {
            if (error is AgentNativeToolCancelledException || error is java.util.concurrent.CancellationException ||
                error is InterruptedException) throw error
            return AgentNativeToolExecutionResult.failure("browser_readiness_unobserved",
                "Packs are installed, but the browser probe did not return. Inspect runtime.diagnose before retrying.",
                details = mapOf("installed" to output["installed"], "packs_installed" to true,
                    "browser_ready" to false, "goal_terminal" to false))
        }
        val envelope = runCatching { JSONObject(response.stdout.trim()) }.getOrNull()
        val ready = response.exitCode == 0 && envelope?.optBoolean("ok") == true &&
            envelope.optJSONObject("result")?.optBoolean("browser_ready") == true
        return if (ready) AgentNativeToolExecutionResult.success(output + mapOf(
            "browser_ready" to true, "verification" to "chromium_local_page",
            "goal_terminal" to false, "next_action" to "Continue the original task using the browser; the local probe is not a website result."
        ), "Runtime packs installed and Chromium startup verified")
        else {
            val error = envelope?.optJSONObject("error")
            AgentNativeToolExecutionResult.failure(error?.optString("code")?.takeIf(String::isNotBlank)
                ?: "browser_readiness_unobserved",
                error?.optString("message")?.takeIf(String::isNotBlank)
                    ?: "Packs are installed but browser startup was not verified. Inspect runtime.diagnose before retrying.",
                details = mapOf("installed" to output["installed"], "browser_ready" to false,
                    "packs_installed" to true, "goal_terminal" to false, "exit_code" to response.exitCode,
                    "verification_tool" to AgentInteractiveBrowserTools.OBSERVE, "verification_operation" to "readiness"))
        }
    }
}
