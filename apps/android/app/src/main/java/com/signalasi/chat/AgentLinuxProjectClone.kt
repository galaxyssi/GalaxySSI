package com.signalasi.chat

import java.util.UUID

internal interface AgentProjectLinuxRuntime {
    fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse
    fun rollback(workspaceId: String, checkpointId: String)
}

/** Runs the authoritative repository clone inside the persistent phone Linux environment. */
internal class AgentLinuxProjectCloneBackend(
    private val runtime: AgentProjectLinuxRuntime,
    private val credentialProvider: AgentProjectCredentialProvider
) : AgentProjectCloneBackend {
    override fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ) {
        progress("linux_git_prepare", "Preparing Git in the phone Linux runtime", 5)
        val token = credentialProvider.token().trim()
        val request = AgentRuntimeExecutionRequest(
            language = AgentRuntimeLanguage.SHELL,
            source = cloneScript(repositoryUrl, branch, depth),
            arguments = emptyList(),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            artifactPaths = emptyList(),
            workspaceId = workspaceId,
            requestId = "linux-clone-${UUID.randomUUID()}",
            allowedNetworkDomains = GITHUB_NETWORK_DOMAINS,
            resourceLimits = AgentRuntimeResourceLimits(
                wallClockMillis = CLONE_TIMEOUT_MILLIS,
                cpuMillis = CLONE_CPU_MILLIS,
                memoryBytes = CLONE_MEMORY_BYTES,
                diskBytes = CLONE_DISK_BYTES,
                maxProcesses = 128,
                maxOutputBytes = CLONE_OUTPUT_BYTES,
                maxArtifactBytes = CLONE_OUTPUT_BYTES
            ),
            cancellationToken = cancellationToken,
            progressListener = { event ->
                progress(event.stage.ifBlank { "linux_git" }, event.message, event.percent)
            },
            secretEnvironment = token.takeIf(String::isNotEmpty)
                ?.let { mapOf(GITHUB_TOKEN_ENVIRONMENT to it) }
                .orEmpty()
        )
        val response = runtime.execute(request)
        if (response.exitCode != 0) {
            if (response.checkpointId.isNotBlank()) {
                runCatching { runtime.rollback(workspaceId, response.checkpointId) }
            }
            throw IllegalStateException(cloneFailureMessage(response, repositoryUrl))
        }
        progress("linux_git_verify", "Verifying the cloned repository in phone Linux", 95)
    }

    private fun cloneScript(repositoryUrl: String, branch: String, depth: Int): String {
        val localBranch = branch.trim().ifBlank { "main" }
        val remoteRef = branch.trim().takeIf(String::isNotBlank)
            ?.let { "refs/heads/$it" }
            ?: "HEAD"
        return """
            set -eu
            export LC_ALL=C
            export GIT_TERMINAL_PROMPT=0
            control_dir='.signalasi-runtime'
            askpass="${'$'}control_dir/git-askpass.sh"
            mkdir -p "${'$'}control_dir"
            if test -f /etc/debian_version; then mkdir -p /root/.cache/tmp; fi
            git_runtime_ready() {
              command -v git >/dev/null 2>&1 &&
                { test ! -f /etc/debian_version || test -s /etc/ssl/certs/ca-certificates.crt; }
            }
            if ! git_runtime_ready; then
              printf '%s\n' '__SIGNALASI_STAGE__:install_git'
              dpkg --configure -a || apt-get -o DPkg::Lock::Timeout=300 -f install -y
              if ! git_runtime_ready; then
                apt-get -o DPkg::Lock::Timeout=300 update
                apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends git ca-certificates openssh-client
              fi
            fi
            cat > "${'$'}askpass" <<'SIGNALASI_ASKPASS'
            #!/bin/sh
            case "${'$'}1" in
              *Username*) printf '%s\n' 'x-access-token' ;;
              *) printf '%s\n' "${'$'}SIGNALASI_GITHUB_TOKEN" ;;
            esac
            SIGNALASI_ASKPASS
            chmod 700 "${'$'}askpass"
            export GIT_ASKPASS="${'$'}PWD/${'$'}askpass"
            printf '%s\n' '__SIGNALASI_STAGE__:prepare_repository'
            find . -mindepth 1 -maxdepth 1 \
              ! -name "${'$'}control_dir" \
              ! -name '.signalasi-tools' \
              ! -name '.signalasi-inputs' \
              ! -name '.tmp' \
              ! -name 'request.json' \
              ! -name 'status.json' \
              ! -name '.signalasi-checkpoint.json' \
              ! -name '.signalasi-stdout' \
              ! -name '.signalasi-stderr' \
              ! -name '.signalasi-main' \
              -exec rm -rf -- {} +
            git config --global --add safe.directory "${'$'}PWD"
            git init -q .
            git remote add origin ${shellQuote(repositoryUrl)}
            printf '%s\n' '__SIGNALASI_STAGE__:fetch_repository'
            git -c credential.helper= fetch --depth $depth origin ${shellQuote(remoteRef)}
            printf '%s\n' '__SIGNALASI_STAGE__:checkout_repository'
            git checkout -q -B ${shellQuote(localBranch)} FETCH_HEAD
            rm -f "${'$'}askpass"
            printf '%s\n' '__SIGNALASI_STAGE__:verify_repository'
            git status --short --branch
        """.trimIndent()
    }

    private fun cloneFailureMessage(response: AgentRuntimeExecutionResponse, repositoryUrl: String): String {
        val detail = listOf(response.stderr, response.stdout)
            .joinToString("\n")
            .trim()
            .takeLast(MAX_FAILURE_DETAIL_CHARS)
        val normalized = detail.lowercase()
        return when {
            repositoryUrl.startsWith("https://github.com/", ignoreCase = true) &&
                ("could not resolve host" in normalized || "network is unreachable" in normalized ||
                    "connection timed out" in normalized || "failed to connect" in normalized) ->
                "Phone Linux cannot reach GitHub. Verify that the phone VPN includes SignalASI, then retry."
            "authentication failed" in normalized || "could not read username" in normalized ->
                "GitHub authentication failed. Update the GitHub credential in SignalASI and retry."
            "problem with the ssl ca cert" in normalized || "certificate problem" in normalized ->
                "Phone Linux could not repair its certificate store. Retry the task after the runtime finishes dependency recovery."
            "repository not found" in normalized ->
                "The GitHub repository was not found or the configured account cannot access it."
            else -> "Phone Linux git clone failed: ${detail.ifBlank { "exit code ${response.exitCode}" }}"
        }
    }

    private fun shellQuote(value: String): String = "'${value.replace("'", "'\"'\"'")}'"

    companion object {
        private const val GITHUB_TOKEN_ENVIRONMENT = "SIGNALASI_GITHUB_TOKEN"
        private const val CLONE_TIMEOUT_MILLIS = 30L * 60_000L
        private const val CLONE_CPU_MILLIS = 25L * 60_000L
        private const val CLONE_MEMORY_BYTES = 1024L * 1024L * 1024L
        private const val CLONE_DISK_BYTES = 2L * 1024L * 1024L * 1024L
        private const val CLONE_OUTPUT_BYTES = 1024L * 1024L
        private const val MAX_FAILURE_DETAIL_CHARS = 4_000
        private val GITHUB_NETWORK_DOMAINS = listOf(
            "github.com",
            "api.github.com",
            "codeload.github.com",
            "objects.githubusercontent.com"
        )
    }
}
