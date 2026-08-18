package com.signalasi.chat

import java.util.Base64
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal interface AgentProjectLinuxRuntime {
    fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse
    fun rollback(workspaceId: String, checkpointId: String)
}

/** Runs authoritative Git mutations in the phone Linux Guest against one stable project workspace. */
internal class AgentLinuxProjectGitBackend(
    private val runtime: AgentProjectLinuxRuntime,
    private val credentialProvider: AgentProjectCredentialProvider
) : AgentProjectGitBackend {
    override fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ) {
        progress("linux_git_prepare", "Preparing the stable Git workspace in phone Linux", 5)
        val token = credentialProvider.token().trim()
        val response = execute(
            workspaceId = workspaceId,
            operation = "clone",
            source = cloneScript(repositoryUrl, branch, depth),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = token,
            progress = progress
        )
        if (response.exitCode != 0) {
            if (response.checkpointId.isNotBlank()) {
                runCatching { runtime.rollback(workspaceId, response.checkpointId) }
            }
            throw IllegalStateException(cloneFailureMessage(response, repositoryUrl))
        }
        progress("linux_git_verify", "Verifying the repository in phone Linux", 95)
    }

    override fun checkoutBranch(workspaceId: String, branch: String, create: Boolean) {
        val mode = if (create) "-B " else ""
        requireSuccess(
            execute(
                workspaceId,
                "checkout",
                gitScript("git checkout -q $mode${shellQuote(branch)}"),
                DEFAULT_TIMEOUT_MILLIS
            ),
            "Phone Linux could not check out the project branch"
        )
    }

    override fun commit(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String
    ): String {
        val response = execute(
            workspaceId,
            "commit",
            gitScript(
                """
                git config user.name ${shellQuote(authorName)}
                git config user.email ${shellQuote(authorEmail)}
                git add -A
                git commit -q -m ${shellQuote(message)}
                git rev-parse HEAD
                """.trimIndent()
            ),
            DEFAULT_TIMEOUT_MILLIS
        )
        requireSuccess(response, "Phone Linux could not commit the project")
        return response.stdout.lineSequence().map(String::trim)
            .lastOrNull { COMMIT_PATTERN.matches(it) }
            .orEmpty()
    }

    override fun pull(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): String {
        val response = execute(
            workspaceId = workspaceId,
            operation = "pull",
            source = authenticatedGitScript(
                """
                git fetch --prune ${shellQuote(remote)} ${shellQuote(branch)}
                git merge --no-edit FETCH_HEAD
                git rev-parse HEAD
                """.trimIndent()
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim()
        )
        requireSuccess(response, "Phone Linux could not update the project")
        return response.stdout.lineSequence().map(String::trim)
            .lastOrNull { COMMIT_PATTERN.matches(it) }
            .orEmpty()
    }

    override fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> {
        val forceFlag = if (force) "--force-with-lease" else ""
        val response = execute(
            workspaceId = workspaceId,
            operation = "push",
            source = authenticatedGitScript(
                "git push --porcelain $forceFlag ${shellQuote(remote)} " +
                    shellQuote("refs/heads/$branch:refs/heads/$branch")
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim()
        )
        requireSuccess(response, "Phone Linux could not publish the project branch")
        return (response.stdout.lineSequence() + response.stderr.lineSequence())
            .map(String::trim)
            .filter(String::isNotBlank)
            .toList()
            .takeLast(MAX_RESULT_LINES)
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
            command -v git >/dev/null 2>&1 || {
              printf '%s\n' 'SignalASI linux-base does not contain Git' >&2
              exit 127
            }
            git() { command git -c safe.directory="${'$'}PWD" "${'$'}@"; }
            cat > "${'$'}askpass" <<'SIGNALASI_ASKPASS'
            #!/bin/sh
            case "${'$'}1" in
              *Username*) printf '%s\n' 'x-access-token' ;;
              *) printf '%s\n' "${'$'}SIGNALASI_GITHUB_TOKEN" ;;
            esac
            SIGNALASI_ASKPASS
            chmod 700 "${'$'}askpass"
            export GIT_ASKPASS="${'$'}PWD/${'$'}askpass"
            configure_signalasi_excludes() {
              exclude_file='.git/info/exclude'
              mkdir -p '.git/info'
              for pattern in \
                '.signalasi-runtime/' '.signalasi-tools/' '.signalasi-inputs/' '.tmp/' \
                'request.json' 'status.json' '.signalasi-checkpoint.json' \
                '.signalasi-stdout' '.signalasi-stderr' '.signalasi-main'; do
                grep -Fqx "${'$'}pattern" "${'$'}exclude_file" 2>/dev/null || \
                  printf '%s\n' "${'$'}pattern" >> "${'$'}exclude_file"
              done
            }
            printf '%s\n' '__SIGNALASI_STAGE__:prepare_repository'
            if [ -d .git ]; then
              configure_signalasi_excludes
              current_origin="${'$'}(git config --get remote.origin.url || true)"
              [ -n "${'$'}current_origin" ] || {
                printf '%s\n' 'Existing phone workspace has no origin remote' >&2
                exit 2
              }
              [ "${'$'}{current_origin%/}" = ${shellQuote(repositoryUrl.trim().removeSuffix("/"))} ] || {
                printf '%s\n' 'Existing phone workspace belongs to a different repository' >&2
                exit 2
              }
              printf '%s\n' '__SIGNALASI_STAGE__:fetch_repository'
              git -c credential.helper= fetch --depth $depth origin ${shellQuote(remoteRef)}
              if [ -z "${'$'}(git status --porcelain)" ]; then
                printf '%s\n' '__SIGNALASI_STAGE__:fast_forward_repository'
                git checkout -q -B ${shellQuote(localBranch)} FETCH_HEAD
              else
                printf '%s\n' '__SIGNALASI_STAGE__:preserve_worktree_changes'
              fi
            else
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
              git init -q .
              configure_signalasi_excludes
              git remote add origin ${shellQuote(repositoryUrl)}
              printf '%s\n' '__SIGNALASI_STAGE__:fetch_repository'
              git -c credential.helper= fetch --depth $depth origin ${shellQuote(remoteRef)}
              printf '%s\n' '__SIGNALASI_STAGE__:checkout_repository'
              git checkout -q -B ${shellQuote(localBranch)} FETCH_HEAD
            fi
            rm -f "${'$'}askpass"
            printf '%s\n' '__SIGNALASI_STAGE__:verify_repository'
            git status --short --branch
        """.trimIndent()
    }

    private fun gitScript(command: String): String = """
        set -eu
        export LC_ALL=C
        export GIT_TERMINAL_PROMPT=0
        command -v git >/dev/null 2>&1 || {
          printf '%s\n' 'SignalASI linux-base does not contain Git' >&2
          exit 127
        }
        git() { command git -c safe.directory="${'$'}PWD" "${'$'}@"; }
        $command
    """.trimIndent()

    private fun authenticatedGitScript(command: String): String = gitScript("") + "\n" + """
        control_dir='.signalasi-runtime'
        askpass="${'$'}control_dir/git-askpass.sh"
        mkdir -p "${'$'}control_dir"
        cat > "${'$'}askpass" <<'SIGNALASI_ASKPASS'
        #!/bin/sh
        case "${'$'}1" in
          *Username*) printf '%s\n' 'x-access-token' ;;
          *) printf '%s\n' "${'$'}SIGNALASI_GITHUB_TOKEN" ;;
        esac
        SIGNALASI_ASKPASS
        chmod 700 "${'$'}askpass"
        export GIT_ASKPASS="${'$'}PWD/${'$'}askpass"
        trap 'rm -f "${'$'}askpass"' EXIT
        $command
    """.trimIndent()

    private fun execute(
        workspaceId: String,
        operation: String,
        source: String,
        timeoutMillis: Long,
        networkEnabled: Boolean = false,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
        token: String = "",
        progress: (String, String, Int?) -> Unit = { _, _, _ -> }
    ): AgentRuntimeExecutionResponse {
        val heartbeatExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "SignalASILinuxGitHeartbeat").apply { isDaemon = true }
        }
        val heartbeat = heartbeatExecutor.scheduleAtFixedRate(
            {
                runCatching {
                    progress(
                        "linux_git_$operation",
                        "Phone Linux Git is still running",
                        null
                    )
                }
            },
            GIT_HEARTBEAT_MILLIS,
            GIT_HEARTBEAT_MILLIS,
            TimeUnit.MILLISECONDS
        )
        return try {
            runtime.execute(
                AgentRuntimeExecutionRequest(
                    language = AgentRuntimeLanguage.PYTHON,
                    source = baseGuestLauncher(source),
                    arguments = emptyList(),
                    timeoutMillis = timeoutMillis,
                    networkEnabled = networkEnabled,
                    artifactPaths = emptyList(),
                    workspaceId = workspaceId,
                    requestId = "linux-git-$operation-${UUID.randomUUID()}",
                    allowedNetworkDomains = if (networkEnabled) GITHUB_NETWORK_DOMAINS else emptyList(),
                    resourceLimits = AgentRuntimeResourceLimits(
                        wallClockMillis = timeoutMillis,
                        cpuMillis = (timeoutMillis * 5L / 6L).coerceAtLeast(100L),
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
            )
        } finally {
            heartbeat.cancel(true)
            heartbeatExecutor.shutdownNow()
        }
    }

    private fun baseGuestLauncher(shellSource: String): String {
        val encoded = Base64.getEncoder().encodeToString(shellSource.toByteArray(Charsets.UTF_8))
        return """
        import base64
        import os
        import subprocess

        shell = os.environ.get("SIGNALASI_BASE_GUEST_SHELL", "/bin/sh")
        source = base64.b64decode("$encoded").decode("utf-8")
        result = subprocess.run([shell, "-c", source], cwd=os.getcwd(), env=os.environ.copy())
        raise SystemExit(result.returncode)
        """.trimIndent()
    }

    private fun requireSuccess(response: AgentRuntimeExecutionResponse, prefix: String) {
        if (response.exitCode == 0) return
        val detail = listOf(response.stderr, response.stdout).joinToString("\n").trim()
            .takeLast(MAX_FAILURE_DETAIL_CHARS)
        error("$prefix: ${detail.ifBlank { "exit code ${response.exitCode}" }}")
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
        private const val DEFAULT_TIMEOUT_MILLIS = 5L * 60_000L
        private const val CLONE_MEMORY_BYTES = 1024L * 1024L * 1024L
        private const val CLONE_DISK_BYTES = 2L * 1024L * 1024L * 1024L
        private const val CLONE_OUTPUT_BYTES = 1024L * 1024L
        private const val GIT_HEARTBEAT_MILLIS = 15_000L
        private const val MAX_FAILURE_DETAIL_CHARS = 4_000
        private const val MAX_RESULT_LINES = 64
        private val COMMIT_PATTERN = Regex("[0-9a-f]{40,64}")
        private val GITHUB_NETWORK_DOMAINS = listOf(
            "github.com",
            "api.github.com",
            "codeload.github.com",
            "objects.githubusercontent.com"
        )
    }
}

internal typealias AgentLinuxProjectCloneBackend = AgentLinuxProjectGitBackend
