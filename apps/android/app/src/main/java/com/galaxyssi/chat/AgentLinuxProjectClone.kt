package com.galaxyssi.chat

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
    override val supportsAtomicCommitObservation: Boolean = true
    override val supportsAtomicPushObservation: Boolean = true
    override val supportsAtomicCommitPushObservation: Boolean = true

    override fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ) {
        cloneAndInspect(
            workspaceId = workspaceId,
            repositoryUrl = repositoryUrl,
            branch = branch,
            depth = depth,
            replaceExisting = replaceExisting,
            cancellationToken = cancellationToken,
            progress = progress
        )
    }

    override fun cloneAndInspect(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ): AgentProjectRepositorySnapshot {
        progress("linux_git_prepare", "Preparing the stable Git workspace in phone Linux", 5)
        val token = credentialProvider.token().trim()
        val response = execute(
            workspaceId = workspaceId,
            operation = "clone",
            source = cloneScript(repositoryUrl, branch, depth, replaceExisting),
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
        return parseSnapshot(workspaceId, response.stdout, workingTreeInspected = false)
    }

    override fun prepareAndInspect(
        workspaceId: String,
        repositoryUrl: String,
        baseBranch: String,
        featureBranch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ): AgentProjectRepositorySnapshot {
        progress("linux_git_prepare", "Preparing the development branch in phone Linux", 5)
        val response = execute(
            workspaceId = workspaceId,
            operation = "prepare",
            source = cloneScript(
                repositoryUrl = repositoryUrl,
                branch = baseBranch,
                depth = depth.coerceAtLeast(PREPARE_HISTORY_DEPTH),
                replaceExisting = replaceExisting,
                featureBranch = featureBranch
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim(),
            progress = progress
        )
        if (response.exitCode != 0) {
            if (response.checkpointId.isNotBlank()) {
                runCatching { runtime.rollback(workspaceId, response.checkpointId) }
            }
            throw IllegalStateException(cloneFailureMessage(response, repositoryUrl))
        }
        progress("linux_git_verify", "Verifying the development branch in phone Linux", 95)
        return parseSnapshot(workspaceId, response.stdout, workingTreeInspected = false)
    }

    override fun inspect(workspaceId: String): AgentProjectRepositorySnapshot {
        return inspect(workspaceId, includeWorkingTree = true)
    }

    override fun inspectMetadata(workspaceId: String): AgentProjectRepositorySnapshot {
        return inspect(workspaceId, includeWorkingTree = false)
    }

    override fun stateFingerprint(workspaceId: String): String {
        val response = execute(
            workspaceId = workspaceId,
            operation = "fingerprint",
            source = gitScript(
                """
                if ! git rev-parse --git-dir >/dev/null 2>&1; then
                  exit 0
                fi
                ${repositoryFingerprintFunction()}
                repository_fingerprint
                """.trimIndent()
            ),
            timeoutMillis = DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false
        )
        requireSuccess(response, "Phone Linux could not fingerprint the project repository")
        return response.stdout.lineSequence()
            .map(String::trim)
            .firstOrNull { SHA256_PATTERN.matches(it) }
            .orEmpty()
    }

    private fun inspect(
        workspaceId: String,
        includeWorkingTree: Boolean
    ): AgentProjectRepositorySnapshot {
        val response = execute(
            workspaceId,
            "inspect",
            repositoryInspectionScript(includeWorkingTree),
            DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false
        )
        requireSuccess(response, "Phone Linux could not inspect the project repository")
        return parseSnapshot(workspaceId, response.stdout, includeWorkingTree)
    }

    override fun diff(workspaceId: String, maxCharacters: Int): String {
        val response = execute(
            workspaceId,
            "diff",
            gitScript(
                """
                git diff --no-ext-diff --binary
                git diff --cached --no-ext-diff --binary
                """.trimIndent()
            ),
            DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false
        )
        requireSuccess(response, "Phone Linux could not read the project diff")
        return response.stdout.take(maxCharacters)
    }

    override fun diffRefs(
        workspaceId: String,
        baseRef: String,
        headRef: String,
        maxCharacters: Int
    ): String {
        val response = execute(
            workspaceId,
            "diff_refs",
            gitScript(
                "git diff --no-ext-diff --binary ${shellQuote("$baseRef...$headRef")} --"
            ),
            DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false
        )
        requireSuccess(response, "Phone Linux could not compare project refs")
        return response.stdout.take(maxCharacters)
    }

    override fun log(workspaceId: String, ref: String, maxEntries: Int, maxCharacters: Int): String {
        val response = execute(
            workspaceId,
            "log",
            gitScript(
                "git log --date=iso-strict --pretty=format:'%H%x09%an%x09%ad%x09%s' " +
                    "-n $maxEntries ${shellQuote(ref)} --"
            ),
            DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false
        )
        requireSuccess(response, "Phone Linux could not read recent project commits")
        return response.stdout.take(maxCharacters)
    }

    override fun observe(
        workspaceId: String,
        includeWorkingTree: Boolean,
        includeDiff: Boolean,
        includeLog: Boolean,
        logRef: String,
        maxLogEntries: Int,
        maxDiffCharacters: Int,
        maxLogCharacters: Int
    ): AgentProjectRepositoryObservation {
        val workingTreeInspection = if (includeWorkingTree) {
            """
                emit_paths '__GALAXYSSI_STAGED__:' git diff --cached --name-only --no-renames
                emit_paths '__GALAXYSSI_MODIFIED__:' git diff --name-only --no-renames
                emit_paths '__GALAXYSSI_UNTRACKED__:' git ls-files --others --exclude-standard
                emit_paths '__GALAXYSSI_CONFLICT__:' git diff --name-only --diff-filter=U --no-renames
            """.trimIndent()
        } else {
            ""
        }
        val diffCapture = if (includeDiff) {
            """
                {
                  git diff --no-ext-diff --binary
                  git diff --cached --no-ext-diff --binary
                } > "${'$'}diff_file"
            """.trimIndent()
        } else {
            ": > \"${'$'}diff_file\""
        }
        val logCapture = if (includeLog) {
            """
                if [ -n "${'$'}head" ]; then
                  git log --date=iso-strict --pretty=format:'%H%x09%an%x09%ad%x09%s' -n $maxLogEntries ${shellQuote(logRef)} -- > "${'$'}log_file"
                else
                  : > "${'$'}log_file"
                fi
            """.trimIndent()
        } else {
            ": > \"${'$'}log_file\""
        }
        val response = execute(
            workspaceId = workspaceId,
            operation = "observe",
            source = """
                set -eu
                export LC_ALL=C
                export GIT_TERMINAL_PROMPT=0
                emit_value() {
                  marker="${'$'}1"
                  value="${'$'}2"
                  encoded="${'$'}(printf '%s' "${'$'}value" | base64 | tr -d '\n')"
                  printf '%s%s\n' "${'$'}marker" "${'$'}encoded"
                }
                emit_paths() {
                  marker="${'$'}1"
                  shift
                  "${'$'}@" | while IFS= read -r path; do
                    [ -n "${'$'}path" ] && emit_value "${'$'}marker" "${'$'}path"
                  done
                }
                emit_bounded_file() {
                  marker="${'$'}1"
                  truncated_marker="${'$'}2"
                  file="${'$'}3"
                  limit="${'$'}4"
                  size="${'$'}(wc -c < "${'$'}file" | tr -d ' ')"
                  truncated=false
                  if [ "${'$'}size" -gt "${'$'}limit" ]; then
                    head -c "${'$'}limit" "${'$'}file" > "${'$'}file.trimmed"
                    mv "${'$'}file.trimmed" "${'$'}file"
                    truncated=true
                  fi
                  emit_value "${'$'}marker" "${'$'}(cat "${'$'}file")"
                  emit_value "${'$'}truncated_marker" "${'$'}truncated"
                }
                temp_root="${'$'}{TMPDIR:-/tmp}/galaxyssi-repository-observe-${'$'}${'$'}"
                diff_file="${'$'}temp_root/diff"
                log_file="${'$'}temp_root/log"
                mkdir -p "${'$'}temp_root"
                trap 'rm -rf "${'$'}temp_root"' EXIT
                if [ ! -e .git ]; then
                  emit_value '__GALAXYSSI_STATE__:' 'empty'
                  : > "${'$'}diff_file"
                  : > "${'$'}log_file"
                  emit_bounded_file '__GALAXYSSI_DIFF__:' '__GALAXYSSI_DIFF_TRUNCATED__:' "${'$'}diff_file" $maxDiffCharacters
                  emit_bounded_file '__GALAXYSSI_LOG__:' '__GALAXYSSI_LOG_TRUNCATED__:' "${'$'}log_file" $maxLogCharacters
                  exit 0
                fi
                command -v git >/dev/null 2>&1 || {
                  printf '%s\n' 'Git is not installed in the persistent phone Linux environment; clone the project to provision it' >&2
                  exit 127
                }
                git() { command git -c safe.directory="${'$'}PWD" -c protocol.file.allow=always "${'$'}@"; }
                if ! git rev-parse --git-dir >/dev/null 2>&1; then
                  emit_value '__GALAXYSSI_STATE__:' 'empty'
                  : > "${'$'}diff_file"
                  : > "${'$'}log_file"
                  emit_bounded_file '__GALAXYSSI_DIFF__:' '__GALAXYSSI_DIFF_TRUNCATED__:' "${'$'}diff_file" $maxDiffCharacters
                  emit_bounded_file '__GALAXYSSI_LOG__:' '__GALAXYSSI_LOG_TRUNCATED__:' "${'$'}log_file" $maxLogCharacters
                  exit 0
                fi
                ${repositoryFingerprintFunction()}
                remote="${'$'}(git remote get-url origin 2>/dev/null || true)"
                head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
                branch="${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
                if [ -z "${'$'}branch" ]; then
                  git_dir="${'$'}(git rev-parse --absolute-git-dir 2>/dev/null || true)"
                  if [ -n "${'$'}git_dir" ] && [ -f "${'$'}git_dir/HEAD" ]; then
                    branch="${'$'}(sed -n 's#^ref: refs/heads/##p' "${'$'}git_dir/HEAD")"
                  fi
                fi
                if [ -n "${'$'}remote" ] && [ -n "${'$'}head" ]; then
                  emit_value '__GALAXYSSI_STATE__:' 'ready'
                else
                  emit_value '__GALAXYSSI_STATE__:' 'partial'
                fi
                emit_value '__GALAXYSSI_REMOTE__:' "${'$'}remote"
                emit_value '__GALAXYSSI_BRANCH__:' "${'$'}branch"
                emit_value '__GALAXYSSI_HEAD__:' "${'$'}head"
                emit_value '__GALAXYSSI_FINGERPRINT__:' "${'$'}(repository_fingerprint)"
                $workingTreeInspection
                $diffCapture
                $logCapture
                emit_bounded_file '__GALAXYSSI_DIFF__:' '__GALAXYSSI_DIFF_TRUNCATED__:' "${'$'}diff_file" $maxDiffCharacters
                emit_bounded_file '__GALAXYSSI_LOG__:' '__GALAXYSSI_LOG_TRUNCATED__:' "${'$'}log_file" $maxLogCharacters
            """.trimIndent(),
            timeoutMillis = DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false,
            maxOutputBytes = OBSERVATION_OUTPUT_BYTES
        )
        requireSuccess(response, "Phone Linux could not observe the project repository")
        return AgentProjectRepositoryObservation(
            repository = parseSnapshot(workspaceId, response.stdout, includeWorkingTree),
            projectFingerprint = markerValues(response.stdout, FINGERPRINT_MARKER).lastOrNull().orEmpty(),
            diff = markerValues(response.stdout, DIFF_MARKER).lastOrNull().orEmpty(),
            recentCommits = markerValues(response.stdout, LOG_MARKER).lastOrNull().orEmpty(),
            diffTruncated = markerValues(response.stdout, DIFF_TRUNCATED_MARKER).lastOrNull() == "true",
            recentCommitsTruncated = markerValues(response.stdout, LOG_TRUNCATED_MARKER).lastOrNull() == "true"
        )
    }

    override fun remoteUrl(workspaceId: String, remote: String): String {
        val response = execute(
            workspaceId,
            "remote",
            gitScript("git remote get-url ${shellQuote(remote)}"),
            DEFAULT_TIMEOUT_MILLIS,
            workspaceMutationExpected = false
        )
        requireSuccess(response, "Phone Linux could not read the Git remote")
        return response.stdout.lineSequence().map(String::trim).lastOrNull(String::isNotBlank).orEmpty()
    }

    override fun checkoutBranch(workspaceId: String, branch: String, create: Boolean) {
        checkoutBranchAt(workspaceId, branch, create, "")
    }

    override fun checkoutBranchAt(workspaceId: String, branch: String, create: Boolean, baseRef: String) {
        val mode = if (create) "-B " else ""
        val base = baseRef.takeIf(String::isNotBlank)?.let { " ${shellQuote(it)}" }.orEmpty()
        requireSuccess(
            execute(
                workspaceId,
                "checkout",
                // checkout -B can repair an unborn or broken symbolic HEAD directly.
                // reset cannot: it aborts while trying to update the missing branch ref.
                gitMutationScript("git checkout -q $mode${shellQuote(branch)}$base"),
                DEFAULT_TIMEOUT_MILLIS
            ),
            "Phone Linux could not check out the project branch"
        )
    }

    override fun checkoutBranchAndInspect(
        workspaceId: String,
        branch: String,
        create: Boolean,
        baseRef: String
    ): AgentProjectRepositorySnapshot {
        val mode = if (create) "-B " else ""
        val base = baseRef.takeIf(String::isNotBlank)?.let { " ${shellQuote(it)}" }.orEmpty()
        val response = execute(
            workspaceId = workspaceId,
            operation = "checkout",
            source = gitMutationScript(
                """
                git checkout -q $mode${shellQuote(branch)}$base
                ${repositoryInspectionScript(includeWorkingTree = true)}
                """.trimIndent()
            ),
            timeoutMillis = DEFAULT_TIMEOUT_MILLIS
        )
        requireSuccess(response, "Phone Linux could not check out the project branch")
        return parseSnapshot(workspaceId, response.stdout, workingTreeInspected = true)
    }

    override fun fetch(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> = fetch(
        workspaceId = workspaceId,
        remote = remote,
        ref = ref,
        cancellationToken = cancellationToken,
        expectedRepositoryUrl = ""
    )

    override fun fetchFromTrustedRemote(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedRepositoryUrl: String
    ): List<String> = fetch(
        workspaceId = workspaceId,
        remote = remote,
        ref = ref,
        cancellationToken = cancellationToken,
        expectedRepositoryUrl = expectedRepositoryUrl
    )

    private fun fetch(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedRepositoryUrl: String
    ): List<String> {
        var verifiedTrackingRef = ""
        val fetchCommand = if (ref.isBlank()) {
            "git fetch --prune ${shellQuote(remote)}"
        } else {
            val sourceRef = if (ref.startsWith("refs/")) ref else "refs/heads/$ref"
            val trackingRef = sourceRef.removePrefix("refs/heads/")
                .takeIf { sourceRef.startsWith("refs/heads/") }
                ?.let { branch -> "refs/remotes/$remote/$branch" }
            verifiedTrackingRef = trackingRef.orEmpty()
            val refspec = trackingRef?.let { destination -> "+$sourceRef:$destination" } ?: sourceRef
            "git fetch --prune ${shellQuote(remote)} ${shellQuote(refspec)}"
        }
        val remoteValidation = expectedRepositoryUrl.takeIf(String::isNotBlank)?.let { expected ->
            """
            expected_remote=${shellQuote(expected)}
            current_remote="${'$'}(git remote get-url ${shellQuote(remote)} 2>/dev/null || true)"
            if [ "${'$'}current_remote" != "${'$'}expected_remote" ]; then
              printf '%s\n' 'The phone project remote changed before fetching' >&2
              exit 65
            fi
            """.trimIndent()
        }.orEmpty()
        val response = execute(
            workspaceId = workspaceId,
            operation = "fetch",
            source = authenticatedGitScript(
                """
                $remoteValidation
                $fetchCommand
                git rev-parse --verify FETCH_HEAD 2>/dev/null | sed 's/^/FETCH_HEAD:/' || true
                git for-each-ref --format='%(refname:short)' ${shellQuote("refs/remotes/$remote/")}
                """.trimIndent()
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim()
        )
        requireSuccess(response, "Phone Linux could not fetch project refs")
        return buildList {
            addAll(response.stdout.lineSequence().map(String::trim).filter(String::isNotBlank))
            if (verifiedTrackingRef.isNotBlank() && none { value ->
                    value == verifiedTrackingRef || value == verifiedTrackingRef.removePrefix("refs/remotes/")
                }
            ) {
                add(verifiedTrackingRef)
            }
        }.distinct().takeLast(MAX_RESULT_LINES)
    }

    override fun commit(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String
    ): String = commitAndInspect(workspaceId, message, authorName, authorEmail, expectedFingerprint = "").commit

    override fun commitAndInspect(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String,
        expectedFingerprint: String
    ): AgentProjectCommitBackendResult {
        val response = execute(
            workspaceId,
            "commit",
            gitScript(
                """
                emit_value() {
                  marker="${'$'}1"
                  value="${'$'}2"
                  encoded="${'$'}(printf '%s' "${'$'}value" | base64 | tr -d '\n')"
                  printf '%s%s\n' "${'$'}marker" "${'$'}encoded"
                }
                emit_paths() {
                  marker="${'$'}1"
                  shift
                  "${'$'}@" | while IFS= read -r path; do
                    [ -n "${'$'}path" ] && emit_value "${'$'}marker" "${'$'}path"
                  done
                }
                ${repositoryFingerprintFunction()}
                if [ -z "${'$'}(git status --porcelain --untracked-files=all)" ]; then
                  printf '%s\n' 'The phone project has no changes to commit' >&2
                  exit 64
                fi
                emit_paths '__GALAXYSSI_STAGED__:' git diff --cached --name-only --no-renames
                emit_paths '__GALAXYSSI_MODIFIED__:' git diff --name-only --no-renames
                emit_paths '__GALAXYSSI_UNTRACKED__:' git ls-files --others --exclude-standard
                emit_paths '__GALAXYSSI_CONFLICT__:' git diff --name-only --diff-filter=U --no-renames
                expected_fingerprint=${shellQuote(expectedFingerprint)}
                current_fingerprint="${'$'}(repository_fingerprint)"
                if [ -n "${'$'}expected_fingerprint" ] && [ "${'$'}current_fingerprint" != "${'$'}expected_fingerprint" ]; then
                  printf '%s\n' 'The phone project changed after verification; run verification again before committing' >&2
                  exit 65
                fi
                git config user.name ${shellQuote(authorName)}
                git config user.email ${shellQuote(authorEmail)}
                git add -A
                git commit -q -m ${shellQuote(message)}
                remote="${'$'}(git remote get-url origin 2>/dev/null || true)"
                branch="${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
                head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
                state='partial'
                if [ -n "${'$'}remote" ] && [ -n "${'$'}head" ]; then
                  state='ready'
                fi
                emit_value '__GALAXYSSI_STATE__:' "${'$'}state"
                emit_value '__GALAXYSSI_REMOTE__:' "${'$'}remote"
                emit_value '__GALAXYSSI_BRANCH__:' "${'$'}branch"
                emit_value '__GALAXYSSI_HEAD__:' "${'$'}head"
                emit_value '__GALAXYSSI_FINGERPRINT__:' "${'$'}(repository_fingerprint)"
                """.trimIndent()
            ),
            DEFAULT_TIMEOUT_MILLIS
        )
        requireSuccess(response, "Phone Linux could not commit the project")
        val changedFiles = listOf(STAGED_MARKER, MODIFIED_MARKER, UNTRACKED_MARKER, CONFLICT_MARKER)
            .flatMap { marker -> markerValues(response.stdout, marker) }
            .distinct()
            .sorted()
        val repository = parseSnapshot(workspaceId, response.stdout, workingTreeInspected = false).copy(
            clean = true,
            staged = emptyList(),
            modified = emptyList(),
            untracked = emptyList(),
            conflicting = emptyList()
        )
        return AgentProjectCommitBackendResult(
            commit = repository.headCommit,
            repository = repository,
            projectFingerprint = markerValues(response.stdout, FINGERPRINT_MARKER).lastOrNull().orEmpty(),
            changedFiles = changedFiles
        )
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

    override fun pullAndInspect(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedRepositoryUrl: String
    ): AgentProjectPullBackendResult {
        val response = execute(
            workspaceId = workspaceId,
            operation = "pull",
            source = authenticatedGitScript(
                """
                expected_remote=${shellQuote(expectedRepositoryUrl)}
                current_remote="${'$'}(git remote get-url ${shellQuote(remote)} 2>/dev/null || true)"
                if [ -z "${'$'}expected_remote" ] || [ "${'$'}current_remote" != "${'$'}expected_remote" ]; then
                  printf '%s\n' 'The phone project remote changed before updating' >&2
                  exit 65
                fi
                git fetch --prune ${shellQuote(remote)} ${shellQuote(branch)}
                git merge --no-edit FETCH_HEAD
                ${repositoryInspectionScript(includeWorkingTree = false)}
                """.trimIndent()
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim()
        )
        requireSuccess(response, "Phone Linux could not update the project")
        val repository = parseSnapshot(workspaceId, response.stdout, workingTreeInspected = false)
        return AgentProjectPullBackendResult(repository.headCommit, repository)
    }

    override fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedFingerprint: String,
        expectedHead: String
    ): List<String> = pushAndInspect(
        workspaceId = workspaceId,
        remote = remote,
        branch = branch,
        force = force,
        cancellationToken = cancellationToken,
        expectedFingerprint = expectedFingerprint,
        expectedHead = expectedHead,
        expectedRepositoryUrl = ""
    ).remoteMessages

    override fun pushAndInspect(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedFingerprint: String,
        expectedHead: String,
        expectedRepositoryUrl: String
    ): AgentProjectPushBackendResult {
        val forceFlag = if (force) "--force-with-lease" else ""
        val response = execute(
            workspaceId = workspaceId,
            operation = "push",
            source = authenticatedGitScript(
                """
                ${repositoryFingerprintFunction()}
                emit_value() {
                  marker="${'$'}1"
                  value="${'$'}2"
                  encoded="${'$'}(printf '%s' "${'$'}value" | base64 | tr -d '\n')"
                  printf '%s%s\n' "${'$'}marker" "${'$'}encoded"
                }
                expected_fingerprint=${shellQuote(expectedFingerprint)}
                expected_head=${shellQuote(expectedHead)}
                expected_remote=${shellQuote(expectedRepositoryUrl)}
                current_fingerprint="${'$'}(repository_fingerprint)"
                current_head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
                current_remote="${'$'}(git remote get-url ${shellQuote(remote)} 2>/dev/null || true)"
                if [ -n "${'$'}expected_fingerprint" ] && [ "${'$'}current_fingerprint" != "${'$'}expected_fingerprint" ]; then
                  printf '%s\n' 'The phone project changed after commit; verify and commit it before publishing' >&2
                  exit 65
                fi
                if [ -n "${'$'}expected_head" ] && [ "${'$'}current_head" != "${'$'}expected_head" ]; then
                  printf '%s\n' 'The phone project HEAD changed before publishing' >&2
                  exit 65
                fi
                if [ -n "${'$'}expected_remote" ] && [ "${'$'}current_remote" != "${'$'}expected_remote" ]; then
                  printf '%s\n' 'The phone project remote changed before publishing' >&2
                  exit 65
                fi
                git push --porcelain $forceFlag ${shellQuote(remote)} ${shellQuote("refs/heads/$branch:refs/heads/$branch")}
                current_remote="${'$'}(git remote get-url ${shellQuote(remote)} 2>/dev/null || true)"
                current_branch="${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
                current_head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
                state='partial'
                if [ -n "${'$'}current_remote" ] && [ -n "${'$'}current_head" ]; then
                  state='ready'
                fi
                emit_value '__GALAXYSSI_STATE__:' "${'$'}state"
                emit_value '__GALAXYSSI_REMOTE__:' "${'$'}current_remote"
                emit_value '__GALAXYSSI_BRANCH__:' "${'$'}current_branch"
                emit_value '__GALAXYSSI_HEAD__:' "${'$'}current_head"
                emit_value '__GALAXYSSI_FINGERPRINT__:' "${'$'}(repository_fingerprint)"
                """.trimIndent()
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim()
        )
        requireSuccess(response, "Phone Linux could not publish the project branch")
        val repository = parseSnapshot(workspaceId, response.stdout, workingTreeInspected = false).copy(clean = true)
        val messages = (response.stdout.lineSequence() + response.stderr.lineSequence())
            .map(String::trim)
            .filter(String::isNotBlank)
            .filterNot { line -> RESULT_MARKERS.any(line::startsWith) }
            .toList()
            .takeLast(MAX_RESULT_LINES)
        return AgentProjectPushBackendResult(
            repository = repository,
            projectFingerprint = markerValues(response.stdout, FINGERPRINT_MARKER).lastOrNull().orEmpty(),
            remoteMessages = messages
        )
    }

    override fun commitPushAndInspect(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedFingerprint: String,
        expectedRepositoryUrl: String
    ): AgentProjectCommitPushBackendResult {
        val forceFlag = if (force) "--force-with-lease" else ""
        val response = execute(
            workspaceId = workspaceId,
            operation = "commit_push",
            source = authenticatedGitScript(
                """
                emit_value() {
                  marker="${'$'}1"
                  value="${'$'}2"
                  encoded="${'$'}(printf '%s' "${'$'}value" | base64 | tr -d '\n')"
                  printf '%s%s\n' "${'$'}marker" "${'$'}encoded"
                }
                emit_paths() {
                  marker="${'$'}1"
                  shift
                  "${'$'}@" | while IFS= read -r path; do
                    [ -n "${'$'}path" ] && emit_value "${'$'}marker" "${'$'}path"
                  done
                }
                ${repositoryFingerprintFunction()}
                if [ -z "${'$'}(git status --porcelain --untracked-files=all)" ]; then
                  printf '%s\n' 'The phone project has no changes to commit' >&2
                  exit 64
                fi
                expected_fingerprint=${shellQuote(expectedFingerprint)}
                expected_remote=${shellQuote(expectedRepositoryUrl)}
                expected_branch=${shellQuote(branch)}
                current_fingerprint="${'$'}(repository_fingerprint)"
                current_remote="${'$'}(git remote get-url ${shellQuote(remote)} 2>/dev/null || true)"
                current_branch="${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
                if [ -z "${'$'}expected_fingerprint" ] || [ "${'$'}current_fingerprint" != "${'$'}expected_fingerprint" ]; then
                  printf '%s\n' 'The phone project changed after verification; run verification again before publishing' >&2
                  exit 65
                fi
                if [ -z "${'$'}expected_remote" ] || [ "${'$'}current_remote" != "${'$'}expected_remote" ]; then
                  printf '%s\n' 'The phone project remote changed before publishing' >&2
                  exit 65
                fi
                if [ -z "${'$'}expected_branch" ] || [ "${'$'}current_branch" != "${'$'}expected_branch" ]; then
                  printf '%s\n' 'The phone project branch changed before publishing' >&2
                  exit 65
                fi
                emit_value '__GALAXYSSI_VERIFIED_FINGERPRINT__:' "${'$'}current_fingerprint"
                emit_paths '__GALAXYSSI_STAGED__:' git diff --cached --name-only --no-renames
                emit_paths '__GALAXYSSI_MODIFIED__:' git diff --name-only --no-renames
                emit_paths '__GALAXYSSI_UNTRACKED__:' git ls-files --others --exclude-standard
                emit_paths '__GALAXYSSI_CONFLICT__:' git diff --name-only --diff-filter=U --no-renames
                git config user.name ${shellQuote(authorName)}
                git config user.email ${shellQuote(authorEmail)}
                git add -A
                git commit -q -m ${shellQuote(message)}
                git push --porcelain $forceFlag ${shellQuote(remote)} ${shellQuote("refs/heads/$branch:refs/heads/$branch")}
                current_head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
                state='partial'
                if [ -n "${'$'}current_remote" ] && [ -n "${'$'}current_head" ]; then
                  state='ready'
                fi
                emit_value '__GALAXYSSI_STATE__:' "${'$'}state"
                emit_value '__GALAXYSSI_REMOTE__:' "${'$'}current_remote"
                emit_value '__GALAXYSSI_BRANCH__:' "${'$'}current_branch"
                emit_value '__GALAXYSSI_HEAD__:' "${'$'}current_head"
                emit_value '__GALAXYSSI_FINGERPRINT__:' "${'$'}(repository_fingerprint)"
                """.trimIndent()
            ),
            timeoutMillis = CLONE_TIMEOUT_MILLIS,
            networkEnabled = true,
            cancellationToken = cancellationToken,
            token = credentialProvider.token().trim()
        )
        requireSuccess(response, "Phone Linux could not commit and publish the project")
        val changedFiles = listOf(STAGED_MARKER, MODIFIED_MARKER, UNTRACKED_MARKER, CONFLICT_MARKER)
            .flatMap { marker -> markerValues(response.stdout, marker) }
            .distinct()
            .sorted()
        val repository = parseSnapshot(workspaceId, response.stdout, workingTreeInspected = false).copy(clean = true)
        val messages = (response.stdout.lineSequence() + response.stderr.lineSequence())
            .map(String::trim)
            .filter(String::isNotBlank)
            .filterNot { line -> RESULT_MARKERS.any(line::startsWith) }
            .toList()
            .takeLast(MAX_RESULT_LINES)
        return AgentProjectCommitPushBackendResult(
            commit = repository.headCommit,
            repository = repository,
            verifiedProjectFingerprint = markerValues(
                response.stdout,
                VERIFIED_FINGERPRINT_MARKER
            ).lastOrNull().orEmpty(),
            projectFingerprint = markerValues(response.stdout, FINGERPRINT_MARKER).lastOrNull().orEmpty(),
            changedFiles = changedFiles,
            remoteMessages = messages
        )
    }

    private fun parseSnapshot(
        workspaceId: String,
        output: String,
        workingTreeInspected: Boolean
    ): AgentProjectRepositorySnapshot {
        val staged = markerValues(output, STAGED_MARKER).distinct().sorted()
        val modified = markerValues(output, MODIFIED_MARKER).distinct().sorted()
        val untracked = markerValues(output, UNTRACKED_MARKER).distinct().sorted()
        val conflicting = markerValues(output, CONFLICT_MARKER).distinct().sorted()
        return AgentProjectRepositorySnapshot(
            workspaceId = workspaceId,
            repositoryUrl = markerValues(output, REMOTE_MARKER).lastOrNull().orEmpty(),
            branch = markerValues(output, BRANCH_MARKER).lastOrNull().orEmpty(),
            headCommit = markerValues(output, HEAD_MARKER).lastOrNull().orEmpty(),
            clean = staged.isEmpty() && modified.isEmpty() && untracked.isEmpty() && conflicting.isEmpty(),
            staged = staged,
            modified = modified,
            untracked = untracked,
            conflicting = conflicting,
            workingTreeInspected = workingTreeInspected,
            state = markerValues(output, STATE_MARKER).lastOrNull()
                ?.let { value -> AgentProjectRepositoryState.entries.firstOrNull { it.wireValue == value } }
                ?: AgentProjectRepositoryState.PARTIAL
        )
    }

    private fun markerValues(output: String, marker: String): List<String> = output.lineSequence()
        .filter { it.startsWith(marker) }
        .map { encoded ->
            val value = encoded.removePrefix(marker)
            runCatching { String(Base64.getDecoder().decode(value), Charsets.UTF_8) }
                .getOrElse { error("Phone Linux returned invalid Git metadata") }
        }
        .toList()

    private fun cloneScript(
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        featureBranch: String = ""
    ): String {
        val localBranch = branch.trim().ifBlank { "main" }
        val requestedFeatureBranch = featureBranch.trim()
        val remoteRef = branch.trim().takeIf(String::isNotBlank)
            ?.let { "refs/heads/$it" }
            ?: "HEAD"
        return """
            set -eu
            export LC_ALL=C
            export GIT_TERMINAL_PROMPT=0
            export GIT_PROTOCOL_FROM_USER=1
            control_dir='.galaxyssi-runtime'
            askpass="${'$'}control_dir/git-askpass.sh"
            git_metadata_root="${'$'}{GALAXYSSI_GIT_METADATA_ROOT:-/var/lib/galaxyssi/git}"
            workspace_key="${'$'}(basename "${'$'}PWD")"
            case "${'$'}workspace_key" in
              *[!A-Za-z0-9._-]*|'')
                printf '%s\n' 'Phone Linux workspace name is invalid' >&2
                exit 2
                ;;
            esac
            git_metadata_dir="${'$'}git_metadata_root/${'$'}workspace_key"
            emit_value() {
              marker="${'$'}1"
              value="${'$'}2"
              encoded="${'$'}(printf '%s' "${'$'}value" | base64 | tr -d '\n')"
              printf '%s%s\n' "${'$'}marker" "${'$'}encoded"
            }
            mkdir -p "${'$'}control_dir"
            if ! command -v git >/dev/null 2>&1; then
              printf '%s\n' '__GALAXYSSI_STAGE__:install_git'
              if ! command -v apt-get >/dev/null 2>&1; then
                printf '%s\n' 'Phone Linux has no Git and no supported package manager' >&2
                exit 127
              fi
              apt-get update
              apt-get install -y --no-install-recommends git openssh-client ca-certificates
            fi
            command -v git >/dev/null 2>&1 || {
              printf '%s\n' 'Git installation did not provide an executable command' >&2
              exit 127
            }
            git() { command git -c safe.directory="${'$'}PWD" -c protocol.file.allow=always "${'$'}@"; }
            cat > "${'$'}askpass" <<'GALAXYSSI_ASKPASS'
            #!/bin/sh
            case "${'$'}1" in
              *Username*) printf '%s\n' 'x-access-token' ;;
              *) printf '%s\n' "${'$'}GALAXYSSI_GITHUB_TOKEN" ;;
            esac
            GALAXYSSI_ASKPASS
            chmod 700 "${'$'}askpass"
            export GIT_ASKPASS="${'$'}PWD/${'$'}askpass"
            configure_galaxyssi_excludes() {
              exclude_file="${'$'}(git rev-parse --git-path info/exclude)"
              mkdir -p "${'$'}(dirname "${'$'}exclude_file")"
              for pattern in \
                '.galaxyssi-runtime/' '.galaxyssi-tools/' '.galaxyssi-inputs/' '.tmp/' \
                'request.json' 'status.json' '.galaxyssi-checkpoint.json' \
                '.galaxyssi-stdout' '.galaxyssi-stderr' '.galaxyssi-main'; do
                grep -Fqx "${'$'}pattern" "${'$'}exclude_file" 2>/dev/null || \
                  printf '%s\n' "${'$'}pattern" >> "${'$'}exclude_file"
              done
            }
            replace_existing=${if (replaceExisting) "true" else "false"}
            feature_branch=${shellQuote(requestedFeatureBranch)}
            reset_project_workspace() {
              find . -mindepth 1 -maxdepth 1 \
                ! -name "${'$'}control_dir" \
                ! -name '.galaxyssi-tools' \
                ! -name '.galaxyssi-inputs' \
                ! -name '.tmp' \
                ! -name 'request.json' \
                ! -name 'status.json' \
                ! -name '.galaxyssi-checkpoint.json' \
                ! -name '.galaxyssi-stdout' \
                ! -name '.galaxyssi-stderr' \
                ! -name '.galaxyssi-main' \
                -exec rm -rf -- {} +
            }
            printf '%s\n' '__GALAXYSSI_STAGE__:prepare_repository'
            existing_checkout=false
            if git rev-parse --git-dir >/dev/null 2>&1; then
              configure_galaxyssi_excludes
              current_origin="${'$'}(git config --get remote.origin.url || true)"
              if [ -n "${'$'}current_origin" ] && \
                 [ "${'$'}{current_origin%/}" = ${shellQuote(repositoryUrl.trim().removeSuffix("/"))} ]; then
                existing_checkout=true
              elif [ "${'$'}replace_existing" = true ]; then
                printf '%s\n' '__GALAXYSSI_STAGE__:replace_repository'
                reset_project_workspace
                rm -rf -- "${'$'}git_metadata_dir"
              elif [ -z "${'$'}current_origin" ] && \
                   ! git rev-parse --verify HEAD >/dev/null 2>&1 && \
                   [ -z "${'$'}(git status --porcelain --untracked-files=all)" ]; then
                printf '%s\n' '__GALAXYSSI_STAGE__:repair_partial_repository'
                rm -rf .git
                rm -rf -- "${'$'}git_metadata_dir"
              elif [ -z "${'$'}current_origin" ]; then
                printf '%s\n' 'Existing phone workspace has no origin remote' >&2
                exit 2
              else
                printf '%s\n' 'Existing phone workspace belongs to a different repository' >&2
                exit 2
              fi
            fi
            if [ "${'$'}existing_checkout" = true ]; then
              printf '%s\n' '__GALAXYSSI_STAGE__:fetch_repository'
              git -c credential.helper= fetch --depth $depth origin ${shellQuote(remoteRef)}
              if [ -n "${'$'}(git status --porcelain)" ]; then
                printf '%s\n' '__GALAXYSSI_STAGE__:preserve_worktree_changes'
                if [ -n "${'$'}feature_branch" ] &&
                   [ "${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "${'$'}feature_branch" ]; then
                  printf '%s\n' 'Uncommitted changes prevent switching to the requested feature branch' >&2
                  exit 2
                fi
              elif [ -n "${'$'}feature_branch" ]; then
                printf '%s\n' '__GALAXYSSI_STAGE__:checkout_feature_branch'
                if git show-ref --verify --quiet "refs/heads/${'$'}feature_branch"; then
                  git checkout -q "${'$'}feature_branch"
                  printf '%s\n' '__GALAXYSSI_STAGE__:update_feature_branch'
                  git merge --no-edit FETCH_HEAD
                else
                  git checkout -q -b "${'$'}feature_branch" FETCH_HEAD
                fi
              else
                printf '%s\n' '__GALAXYSSI_STAGE__:fast_forward_repository'
                git checkout -q -B ${shellQuote(localBranch)} FETCH_HEAD
              fi
            else
              reset_project_workspace
              rm -rf -- "${'$'}git_metadata_dir"
              mkdir -p "${'$'}git_metadata_root"
              git init -q --separate-git-dir="${'$'}git_metadata_dir" .
              configure_galaxyssi_excludes
              git remote add origin ${shellQuote(repositoryUrl)}
              printf '%s\n' '__GALAXYSSI_STAGE__:fetch_repository'
              git -c credential.helper= fetch --depth $depth origin ${shellQuote(remoteRef)}
              printf '%s\n' '__GALAXYSSI_STAGE__:checkout_repository'
              if [ -n "${'$'}feature_branch" ]; then
                printf '%s\n' '__GALAXYSSI_STAGE__:checkout_feature_branch'
                git checkout -q -B "${'$'}feature_branch" FETCH_HEAD
              else
                git checkout -q -B ${shellQuote(localBranch)} FETCH_HEAD
              fi
            fi
            rm -f "${'$'}askpass"
            printf '%s\n' '__GALAXYSSI_STAGE__:verify_repository'
            origin="${'$'}(git config --get remote.origin.url || true)"
            current_branch="${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
            current_head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
            repository_state='partial'
            if [ -n "${'$'}origin" ] && [ -n "${'$'}current_head" ]; then
              repository_state='ready'
            fi
            emit_value '__GALAXYSSI_STATE__:' "${'$'}repository_state"
            emit_value '__GALAXYSSI_REMOTE__:' "${'$'}origin"
            emit_value '__GALAXYSSI_BRANCH__:' "${'$'}current_branch"
            emit_value '__GALAXYSSI_HEAD__:' "${'$'}current_head"
        """.trimIndent()
    }

    private fun gitScript(command: String): String = """
        set -eu
        export LC_ALL=C
        export GIT_TERMINAL_PROMPT=0
        command -v git >/dev/null 2>&1 || {
          printf '%s\n' 'GalaxySSI linux-base does not contain Git' >&2
          exit 127
        }
        git() { command git -c safe.directory="${'$'}PWD" -c protocol.file.allow=always "${'$'}@"; }
        $command
    """.trimIndent()

    private fun repositoryInspectionScript(includeWorkingTree: Boolean): String {
        val workingTreeInspection = if (includeWorkingTree) {
            """
                emit_paths '__GALAXYSSI_STAGED__:' git diff --cached --name-only --no-renames
                emit_paths '__GALAXYSSI_MODIFIED__:' git diff --name-only --no-renames
                emit_paths '__GALAXYSSI_UNTRACKED__:' git ls-files --others --exclude-standard
                emit_paths '__GALAXYSSI_CONFLICT__:' git diff --name-only --diff-filter=U --no-renames
            """.trimIndent()
        } else {
            ""
        }
        return """
            set -eu
            export LC_ALL=C
            export GIT_TERMINAL_PROMPT=0
            emit_value() {
              marker="${'$'}1"
              value="${'$'}2"
              encoded="${'$'}(printf '%s' "${'$'}value" | base64 | tr -d '\n')"
              printf '%s%s\n' "${'$'}marker" "${'$'}encoded"
            }
            emit_paths() {
              marker="${'$'}1"
              shift
              "${'$'}@" | while IFS= read -r path; do
                [ -n "${'$'}path" ] && emit_value "${'$'}marker" "${'$'}path"
              done
            }
            if [ ! -e .git ]; then
              emit_value '__GALAXYSSI_STATE__:' 'empty'
              exit 0
            fi
            command -v git >/dev/null 2>&1 || {
              printf '%s\n' 'Git is not installed in the persistent phone Linux environment; clone the project to provision it' >&2
              exit 127
            }
            git() { command git -c safe.directory="${'$'}PWD" -c protocol.file.allow=always "${'$'}@"; }
            if ! git rev-parse --git-dir >/dev/null 2>&1; then
              emit_value '__GALAXYSSI_STATE__:' 'empty'
              exit 0
            fi
            remote="${'$'}(git remote get-url origin 2>/dev/null || true)"
            head="${'$'}(git rev-parse --verify HEAD 2>/dev/null || true)"
            branch="${'$'}(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
            if [ -z "${'$'}branch" ]; then
              git_dir="${'$'}(git rev-parse --absolute-git-dir 2>/dev/null || true)"
              if [ -n "${'$'}git_dir" ] && [ -f "${'$'}git_dir/HEAD" ]; then
                branch="${'$'}(sed -n 's#^ref: refs/heads/##p' "${'$'}git_dir/HEAD")"
              fi
            fi
            if [ -n "${'$'}remote" ] && [ -n "${'$'}head" ]; then
              emit_value '__GALAXYSSI_STATE__:' 'ready'
            else
              emit_value '__GALAXYSSI_STATE__:' 'partial'
            fi
            emit_value '__GALAXYSSI_REMOTE__:' "${'$'}remote"
            emit_value '__GALAXYSSI_BRANCH__:' "${'$'}branch"
            emit_value '__GALAXYSSI_HEAD__:' "${'$'}head"
            $workingTreeInspection
        """.trimIndent()
    }

    private fun repositoryFingerprintFunction(): String = """
        repository_fingerprint() {
          {
            printf '%s\n' '__GALAXYSSI_HEAD__'
            git rev-parse --verify HEAD 2>/dev/null || true
            printf '%s\n' '__GALAXYSSI_STATUS__'
            git status --porcelain=v2 --untracked-files=all
            printf '%s\n' '__GALAXYSSI_TRACKED_DIFF__'
            if git rev-parse --verify HEAD >/dev/null 2>&1; then
              git diff --no-ext-diff --binary HEAD --
            else
              git diff --cached --no-ext-diff --binary --
            fi
            printf '%s\n' '__GALAXYSSI_UNTRACKED_CONTENT__'
            git ls-files --others --exclude-standard -z |
              xargs -0 -r git -c safe.directory="${'$'}PWD" hash-object --no-filters --
          } | sha256sum | awk '{ print ${'$'}1 }'
        }
    """.trimIndent()

    /**
     * AgentWorkspaceScope serializes every repository action for a workspace. If
     * index.lock is still present when the next action starts, the process that
     * owned it has already ended or was interrupted and the lock is stale.
     */
    private fun gitMutationScript(command: String): String = gitScript(
        """
            git_dir="${'$'}(git rev-parse --git-dir)"
            index_lock="${'$'}git_dir/index.lock"
            if [ -f "${'$'}index_lock" ]; then
              printf '%s\n' '__GALAXYSSI_STAGE__:remove_stale_git_lock'
              rm -f -- "${'$'}index_lock"
            fi
            $command
        """.trimIndent()
    )

    private fun authenticatedGitScript(command: String): String = gitScript("") + "\n" + """
        control_dir='.galaxyssi-runtime'
        askpass="${'$'}control_dir/git-askpass.sh"
        mkdir -p "${'$'}control_dir"
        cat > "${'$'}askpass" <<'GALAXYSSI_ASKPASS'
        #!/bin/sh
        case "${'$'}1" in
          *Username*) printf '%s\n' 'x-access-token' ;;
          *) printf '%s\n' "${'$'}GALAXYSSI_GITHUB_TOKEN" ;;
        esac
        GALAXYSSI_ASKPASS
        chmod 700 "${'$'}askpass"
        export GIT_ASKPASS="${'$'}PWD/${'$'}askpass"
        trap 'rm -f "${'$'}askpass"' EXIT
    """.trimIndent() + "\n" + command

    private fun execute(
        workspaceId: String,
        operation: String,
        source: String,
        timeoutMillis: Long,
        networkEnabled: Boolean = false,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
        token: String = "",
        workspaceMutationExpected: Boolean = true,
        maxOutputBytes: Long = CLONE_OUTPUT_BYTES,
        progress: (String, String, Int?) -> Unit = { _, _, _ -> }
    ): AgentRuntimeExecutionResponse {
        val heartbeatExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "GalaxySSILinuxGitHeartbeat").apply { isDaemon = true }
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
                    language = AgentRuntimeLanguage.SHELL,
                    source = source,
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
                        maxOutputBytes = maxOutputBytes,
                        maxArtifactBytes = maxOutputBytes
                    ),
                    cancellationToken = cancellationToken,
                    progressListener = { event ->
                        progress(event.stage.ifBlank { "linux_git" }, event.message, event.percent)
                    },
                    secretEnvironment = token.takeIf(String::isNotEmpty)
                        ?.let { mapOf(GITHUB_TOKEN_ENVIRONMENT to it) }
                        .orEmpty(),
                    workspaceMutationExpected = workspaceMutationExpected,
                    discoverBuildArtifacts = false
                )
            )
        } finally {
            heartbeat.cancel(true)
            heartbeatExecutor.shutdownNow()
        }
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
                "Phone Linux cannot reach GitHub. Verify that the phone VPN includes GalaxySSI, then retry."
            "authentication failed" in normalized || "could not read username" in normalized ->
                "GitHub authentication failed. Update the GitHub credential in GalaxySSI and retry."
            "problem with the ssl ca cert" in normalized || "certificate problem" in normalized ->
                "Phone Linux could not repair its certificate store. Retry the task after the runtime finishes dependency recovery."
            "repository not found" in normalized ->
                "The GitHub repository was not found or the configured account cannot access it."
            else -> "Phone Linux git clone failed: ${detail.ifBlank { "exit code ${response.exitCode}" }}"
        }
    }

    private fun shellQuote(value: String): String = "'${value.replace("'", "'\"'\"'")}'"

    companion object {
        private const val GITHUB_TOKEN_ENVIRONMENT = "GALAXYSSI_GITHUB_TOKEN"
        private const val PREPARE_HISTORY_DEPTH = 50
        private const val CLONE_TIMEOUT_MILLIS = 30L * 60_000L
        private const val DEFAULT_TIMEOUT_MILLIS = 5L * 60_000L
        private const val CLONE_MEMORY_BYTES = 1024L * 1024L * 1024L
        private const val CLONE_DISK_BYTES = 2L * 1024L * 1024L * 1024L
        private const val CLONE_OUTPUT_BYTES = 1024L * 1024L
        private const val OBSERVATION_OUTPUT_BYTES = 2L * 1024L * 1024L
        private const val GIT_HEARTBEAT_MILLIS = 15_000L
        private const val MAX_FAILURE_DETAIL_CHARS = 4_000
        private const val MAX_RESULT_LINES = 64
        private const val REMOTE_MARKER = "__GALAXYSSI_REMOTE__:"
        private const val STATE_MARKER = "__GALAXYSSI_STATE__:"
        private const val BRANCH_MARKER = "__GALAXYSSI_BRANCH__:"
        private const val HEAD_MARKER = "__GALAXYSSI_HEAD__:"
        private const val STAGED_MARKER = "__GALAXYSSI_STAGED__:"
        private const val MODIFIED_MARKER = "__GALAXYSSI_MODIFIED__:"
        private const val UNTRACKED_MARKER = "__GALAXYSSI_UNTRACKED__:"
        private const val CONFLICT_MARKER = "__GALAXYSSI_CONFLICT__:"
        private const val FINGERPRINT_MARKER = "__GALAXYSSI_FINGERPRINT__:"
        private const val VERIFIED_FINGERPRINT_MARKER = "__GALAXYSSI_VERIFIED_FINGERPRINT__:"
        private const val DIFF_MARKER = "__GALAXYSSI_DIFF__:"
        private const val DIFF_TRUNCATED_MARKER = "__GALAXYSSI_DIFF_TRUNCATED__:"
        private const val LOG_MARKER = "__GALAXYSSI_LOG__:"
        private const val LOG_TRUNCATED_MARKER = "__GALAXYSSI_LOG_TRUNCATED__:"
        private val RESULT_MARKERS = listOf(
            STATE_MARKER,
            REMOTE_MARKER,
            BRANCH_MARKER,
            HEAD_MARKER,
            FINGERPRINT_MARKER,
            VERIFIED_FINGERPRINT_MARKER,
            STAGED_MARKER,
            MODIFIED_MARKER,
            UNTRACKED_MARKER,
            CONFLICT_MARKER
        )
        private val COMMIT_PATTERN = Regex("[0-9a-f]{40,64}")
        private val SHA256_PATTERN = Regex("[0-9a-f]{64}")
        private val GITHUB_NETWORK_DOMAINS = listOf(
            "github.com",
            "api.github.com",
            "codeload.github.com",
            "objects.githubusercontent.com"
        )
    }
}

internal typealias AgentLinuxProjectCloneBackend = AgentLinuxProjectGitBackend
