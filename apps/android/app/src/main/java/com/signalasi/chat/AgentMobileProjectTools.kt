package com.signalasi.chat

import android.content.Context
import java.io.File
import java.net.URI
import java.nio.file.Files
import java.nio.file.LinkOption
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

internal data class AgentProjectRepositorySnapshot(
    val workspaceId: String,
    val repositoryUrl: String,
    val branch: String,
    val headCommit: String,
    val clean: Boolean,
    val staged: List<String>,
    val modified: List<String>,
    val untracked: List<String>,
    val conflicting: List<String>,
    val workingTreeInspected: Boolean = true,
    val state: AgentProjectRepositoryState = AgentProjectRepositoryState.READY
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "workspace_id" to workspaceId,
        "repository_state" to state.wireValue,
        "repository_present" to (state != AgentProjectRepositoryState.EMPTY),
        "repository_ready" to (state == AgentProjectRepositoryState.READY),
        "head_present" to headCommit.isNotBlank(),
        "recovery_required" to (state == AgentProjectRepositoryState.PARTIAL),
        "recovery_hint" to if (state == AgentProjectRepositoryState.PARTIAL) {
            "Repository metadata exists but HEAD is not usable. Do not clone or repeat inspection. " +
                "Fetch the remote refs, then check out a branch from the intended remote base ref."
        } else "",
        "repository_url" to repositoryUrl,
        "branch" to branch,
        "head_commit" to headCommit,
        "working_tree_inspected" to workingTreeInspected,
        "clean" to clean.takeIf { workingTreeInspected },
        "staged" to staged,
        "modified" to modified,
        "untracked" to untracked,
        "conflicting" to conflicting
    )
}

internal enum class AgentProjectRepositoryState(val wireValue: String) {
    EMPTY("empty"),
    PARTIAL("partial"),
    READY("ready")
}

internal data class AgentProjectCommitResult(
    val commit: String,
    val branch: String,
    val changedFiles: List<String>
)

internal data class AgentProjectPullResult(
    val successful: Boolean,
    val mergeStatus: String,
    val headCommit: String
)

internal data class AgentProjectPushResult(
    val branch: String,
    val remoteMessages: List<String>
)

internal data class AgentProjectPullRequestResult(
    val number: Long,
    val url: String,
    val state: String
)

internal fun interface AgentProjectCredentialProvider {
    fun token(): String
}

internal interface AgentProjectGitBackend {
    fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    )
    fun inspect(workspaceId: String): AgentProjectRepositorySnapshot

    fun inspectMetadata(workspaceId: String): AgentProjectRepositorySnapshot = inspect(workspaceId)

    fun cloneAndInspect(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ): AgentProjectRepositorySnapshot {
        clone(
            workspaceId = workspaceId,
            repositoryUrl = repositoryUrl,
            branch = branch,
            depth = depth,
            replaceExisting = replaceExisting,
            cancellationToken = cancellationToken,
            progress = progress
        )
        return inspectMetadata(workspaceId)
    }

    fun stateFingerprint(workspaceId: String): String =
        error("The project backend cannot fingerprint the phone Linux working tree")

    fun diff(workspaceId: String, maxCharacters: Int): String

    fun diffRefs(
        workspaceId: String,
        baseRef: String,
        headRef: String,
        maxCharacters: Int
    ): String = diff(workspaceId, maxCharacters)

    fun log(workspaceId: String, ref: String, maxEntries: Int, maxCharacters: Int): String = ""

    fun remoteUrl(workspaceId: String, remote: String): String

    fun checkoutBranch(workspaceId: String, branch: String, create: Boolean)

    fun checkoutBranchAt(workspaceId: String, branch: String, create: Boolean, baseRef: String) =
        checkoutBranch(workspaceId, branch, create)

    fun fetch(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> = emptyList()

    fun commit(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String
    ): String

    fun pull(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): String

    fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String>
}

/** Phone Linux-backed Git operations for one persistent Agent project workspace. */
internal class AgentMobileProjectRepository(
    projectRoot: File,
    private val credentialProvider: AgentProjectCredentialProvider,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val repositoryPolicy: (String) -> Boolean = ::isTrustedRepositoryUrl,
    private val publicationGuard: AgentProjectPublicationGuard = AgentProjectPublicationGuard.ALLOW_ALL,
    private val gitBackend: AgentProjectGitBackend? = null
) {
    private val root = projectRoot.canonicalFile.apply {
        check(mkdirs() || isDirectory) { "Agent project storage is unavailable" }
    }

    fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ): AgentProjectRepositorySnapshot = AgentWorkspaceScope.withLock(workspaceId) {
        val cleanUrl = normalizeRepositoryUrl(repositoryUrl)
        require(repositoryPolicy(cleanUrl)) { "Repository URL is not allowed by the phone project policy" }
        require(depth in 1..100) { "Clone depth is invalid" }
        val cleanBranch = branch.trim().also { value ->
            if (value.isNotBlank()) validateRefName(value)
        }
        val target = workspaceDirectory(workspaceId)
        val repositoryAlreadyPresent = File(target, ".git").exists()
        require(repositoryAlreadyPresent || replaceExisting || !hasCloneBlockingContent(target)) {
            "The phone project workspace is not empty"
        }
        val backend = requireLinuxGitBackend()
        progress(
            "clone",
            if (repositoryAlreadyPresent) {
                "Updating the existing repository in the phone Linux runtime"
            } else {
                "Cloning repository in the phone Linux runtime"
            },
            0
        )
        try {
            val snapshot = backend.cloneAndInspect(
                workspaceId = workspaceId,
                repositoryUrl = cleanUrl,
                branch = cleanBranch,
                depth = depth,
                replaceExisting = replaceExisting,
                cancellationToken = cancellationToken,
                progress = progress
            )
            if (!repositoryAlreadyPresent) {
                check(projectBytes(target) <= MAX_PROJECT_BYTES) { "Cloned project exceeds the phone workspace quota" }
            }
            publicationGuard.invalidate(workspaceId)
            progress("clone", "Phone Linux repository is ready", 100)
            snapshot
        } catch (error: Throwable) {
            throw projectFailure("Linux repository clone failed", error)
        }
    }

    fun inspect(workspaceId: String, includeWorkingTree: Boolean = true): AgentProjectRepositorySnapshot =
        AgentWorkspaceScope.withLock(workspaceId) {
            if (includeWorkingTree) {
                requireLinuxGitBackend().inspect(workspaceId)
            } else {
                requireLinuxGitBackend().inspectMetadata(workspaceId)
            }
        }

    fun diff(
        workspaceId: String,
        maxCharacters: Int,
        baseRef: String = "",
        headRef: String = ""
    ): String =
        AgentWorkspaceScope.withLock(workspaceId) {
            require(maxCharacters in 1_000..MAX_DIFF_CHARACTERS) { "Diff output limit is invalid" }
            val cleanBase = baseRef.trim()
            val cleanHead = headRef.trim()
            require(cleanBase.isNotBlank() || cleanHead.isBlank()) { "A Git diff head ref requires a base ref" }
            if (cleanBase.isNotBlank()) validateRefName(cleanBase)
            if (cleanHead.isNotBlank()) validateRefName(cleanHead)
            val diff = if (cleanBase.isBlank()) {
                requireLinuxGitBackend().diff(workspaceId, maxCharacters)
            } else {
                requireLinuxGitBackend().diffRefs(
                    workspaceId,
                    cleanBase,
                    cleanHead.ifBlank { "HEAD" },
                    maxCharacters
                )
            }
            diff.also {
                if (diff.isNotBlank() && diff.length < maxCharacters) {
                    runCatching { publicationGuard.recordDocumentationReview(workspaceId, diff) }
                }
            }
        }

    fun log(
        workspaceId: String,
        ref: String,
        maxEntries: Int,
        maxCharacters: Int
    ): String = AgentWorkspaceScope.withLock(workspaceId) {
        require(maxEntries in 1..MAX_LOG_ENTRIES) { "Git log entry limit is invalid" }
        require(maxCharacters in 1_000..MAX_LOG_CHARACTERS) { "Git log output limit is invalid" }
        val cleanRef = ref.trim().ifBlank { "HEAD" }.also(::validateRefName)
        requireLinuxGitBackend().log(workspaceId, cleanRef, maxEntries, maxCharacters)
    }

    fun checkoutBranch(
        workspaceId: String,
        branch: String,
        create: Boolean,
        baseRef: String = ""
    ): AgentProjectRepositorySnapshot =
        AgentWorkspaceScope.withLock(workspaceId) {
            val cleanBranch = branch.trim().also(::validateRefName)
            val cleanBase = baseRef.trim()
            if (cleanBase.isNotBlank()) {
                require(create) { "A base ref can only be used when creating or resetting a branch" }
                validateRefName(cleanBase)
            }
            requireLinuxGitBackend().checkoutBranchAt(workspaceId, cleanBranch, create, cleanBase)
            publicationGuard.invalidate(workspaceId)
            requireLinuxGitBackend().inspect(workspaceId)
        }

    fun fetch(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> = AgentWorkspaceScope.withLock(workspaceId) {
        val cleanRemote = validateRemoteName(remote)
        val cleanRef = ref.trim()
        if (cleanRef.isNotBlank()) validateRefName(cleanRef)
        requireAllowedRemote(workspaceId, cleanRemote)
        requireLinuxGitBackend().fetch(workspaceId, cleanRemote, cleanRef, cancellationToken)
    }

    fun commit(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String
    ): AgentProjectCommitResult = AgentWorkspaceScope.withLock(workspaceId) {
        val cleanMessage = message.trim().take(MAX_COMMIT_MESSAGE_CHARACTERS)
        require(cleanMessage.isNotBlank()) { "Commit message is required" }
        val name = authorName.trim().ifBlank { DEFAULT_AUTHOR_NAME }.take(120)
        val email = authorEmail.trim().ifBlank { DEFAULT_AUTHOR_EMAIL }.take(254)
        require(EMAIL_PATTERN.matches(email)) { "Commit author email is invalid" }
        publicationGuard.requireVerified(workspaceId)
        val beforeCommit = requireLinuxGitBackend().inspect(workspaceId)
        val changed = changedFiles(beforeCommit)
        require(changed.isNotEmpty()) { "The phone project has no changes to commit" }
        val reportedCommit = requireLinuxGitBackend().commit(workspaceId, cleanMessage, name, email)
        val committedState = requireLinuxGitBackend().inspectMetadata(workspaceId)
        val commit = reportedCommit.ifBlank { committedState.headCommit }
        require(OBJECT_ID_PATTERN.matches(commit)) { "Phone Linux did not create a readable Git commit" }
        val branch = committedState.branch
        AgentProjectCommitResult(commit, branch, changed).also { result ->
            publicationGuard.recordCommit(workspaceId, result.commit, result.branch)
        }
    }

    fun pull(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentProjectPullResult = AgentWorkspaceScope.withLock(workspaceId) {
        val backend = requireLinuxGitBackend()
        val repository = backend.inspectMetadata(workspaceId)
        val cleanRemote = validateRemoteName(remote)
        val cleanBranch = branch.trim().ifBlank { repository.branch }.also(::validateRefName)
        val remoteUrl = if (cleanRemote == "origin") {
            repository.repositoryUrl
        } else {
            backend.remoteUrl(workspaceId, cleanRemote)
        }
        requireAllowedRemoteUrl(remoteUrl)
        val reportedHead = backend.pull(workspaceId, cleanRemote, cleanBranch, cancellationToken)
        val head = reportedHead.ifBlank { backend.inspectMetadata(workspaceId).headCommit }
        require(OBJECT_ID_PATTERN.matches(head)) { "Phone Linux updated the project but HEAD is unreadable" }
        publicationGuard.invalidate(workspaceId)
        AgentProjectPullResult(true, "updated", head)
    }

    fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentProjectPushResult = AgentWorkspaceScope.withLock(workspaceId) {
        require(credentialProvider.token().isNotBlank()) { "Configure a GitHub token before publishing a phone project" }
        val backend = requireLinuxGitBackend()
        val repository = backend.inspectMetadata(workspaceId)
        val cleanRemote = validateRemoteName(remote)
        val cleanBranch = branch.trim().ifBlank { repository.branch }.also(::validateRefName)
        publicationGuard.requirePushable(workspaceId, cleanBranch)
        val remoteUrl = if (cleanRemote == "origin") {
            repository.repositoryUrl
        } else {
            backend.remoteUrl(workspaceId, cleanRemote)
        }
        requireAllowedRemoteUrl(remoteUrl)
        require(OBJECT_ID_PATTERN.matches(repository.headCommit)) {
            "Phone Linux project HEAD is unreadable"
        }
        val updates = backend.push(workspaceId, cleanRemote, cleanBranch, force, cancellationToken)
        AgentProjectPushResult(cleanBranch, updates).also {
            publicationGuard.recordPush(
                workspaceId,
                repository.headCommit,
                cleanBranch
            )
        }
    }

    fun createPullRequest(
        workspaceId: String,
        title: String,
        body: String,
        base: String,
        head: String
    ): AgentProjectPullRequestResult = AgentWorkspaceScope.withLock(workspaceId) {
        val token = credentialProvider.token().trim()
        require(token.isNotBlank()) { "Configure a GitHub token before creating a pull request" }
        val repositorySnapshot = requireLinuxGitBackend().inspectMetadata(workspaceId)
        val cleanTitle = title.trim().take(MAX_PULL_REQUEST_TITLE_CHARACTERS)
        require(cleanTitle.isNotBlank()) { "Pull request title is required" }
        val cleanBase = base.trim().ifBlank { "main" }.also(::validateRefName)
        val cleanHead = head.trim().ifBlank { repositorySnapshot.branch }.also(::validateRefName)
        publicationGuard.requirePullRequestReady(workspaceId, cleanHead)
        val repository = githubCoordinates(repositorySnapshot.repositoryUrl)
        val payload = JSONObject()
            .put("title", cleanTitle)
            .put("body", body.take(MAX_PULL_REQUEST_BODY_CHARACTERS))
            .put("base", cleanBase)
            .put("head", cleanHead)
            .toString()
            .toRequestBody(JSON_MEDIA_TYPE)
        val request = Request.Builder()
            .url("https://api.github.com/repos/${repository.first}/${repository.second}/pulls")
            .header("Accept", "application/vnd.github+json")
            .header("Authorization", "Bearer $token")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .post(payload)
            .build()
        httpClient.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty().take(MAX_GITHUB_RESPONSE_CHARACTERS)
            check(response.isSuccessful) {
                val message = runCatching { JSONObject(text).optString("message") }.getOrDefault("")
                "GitHub pull request creation failed (${response.code}): ${message.ifBlank { "request rejected" }}"
            }
            val json = JSONObject(text)
            AgentProjectPullRequestResult(
                number = json.getLong("number"),
                url = json.getString("html_url"),
                state = json.optString("state", "open")
            )
        }
    }

    private fun workspaceDirectory(workspaceId: String): File {
        require(WORKSPACE_ID_PATTERN.matches(workspaceId)) { "Phone project workspace id is invalid" }
        val candidate = File(root, workspaceId).canonicalFile
        require(candidate.path.startsWith(root.path + File.separator)) { "Phone project path escapes app storage" }
        check(candidate.mkdirs() || candidate.isDirectory) { "Phone project workspace is unavailable" }
        return candidate
    }

    private fun hasCloneBlockingContent(workspace: File): Boolean {
        val entries = workspace.listFiles().orEmpty()
        return entries.any { entry ->
            Files.isSymbolicLink(entry.toPath()) || entry.name !in LINUX_RUNTIME_MANAGED_ENTRIES
        }
    }

    private fun currentBranch(workspaceId: String): String = requireLinuxGitBackend().inspectMetadata(workspaceId).branch

    private fun requireLinuxGitBackend(): AgentProjectGitBackend = gitBackend
        ?: error("Phone Linux Git backend is required for repository operations")

    private fun githubCoordinates(repositoryUrl: String): Pair<String, String> {
        val url = normalizeRepositoryUrl(repositoryUrl)
        val uri = URI(url)
        require(uri.host.equals("github.com", ignoreCase = true)) { "Pull requests require a GitHub origin" }
        val segments = uri.path.trim('/').removeSuffix(".git").split('/').filter(String::isNotBlank)
        require(segments.size == 2) { "GitHub repository origin is invalid" }
        return segments[0] to segments[1]
    }

    private fun requireAllowedRemote(workspaceId: String, remote: String) {
        requireAllowedRemoteUrl(requireLinuxGitBackend().remoteUrl(workspaceId, remote))
    }

    private fun requireAllowedRemoteUrl(url: String) {
        require(url.isNotBlank() && repositoryPolicy(normalizeRepositoryUrl(url))) {
            "Git remote is missing or not allowed by the phone project policy"
        }
    }

    private fun projectBytes(directory: File): Long {
        var total = 0L
        var files = 0
        Files.walk(directory.toPath()).use { paths ->
            paths.forEach { path ->
                require(!Files.isSymbolicLink(path)) { "Symbolic links are not allowed in phone projects" }
                if (Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                    files += 1
                    check(files <= MAX_PROJECT_FILES) { "Phone project contains too many files" }
                    total += Files.size(path)
                    check(total <= MAX_PROJECT_BYTES) { "Phone project exceeds its storage quota" }
                }
            }
        }
        return total
    }

    private fun changedFiles(snapshot: AgentProjectRepositorySnapshot): List<String> = (
        snapshot.staged + snapshot.modified + snapshot.untracked + snapshot.conflicting
        ).distinct().sorted()

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val WORKSPACE_ID_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
        private val BRANCH_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._/-]{0,127}")
        private val REMOTE_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
        private val EMAIL_PATTERN = Regex("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")
        private val LINUX_RUNTIME_MANAGED_ENTRIES = setOf(
            ".signalasi-tools",
            ".signalasi-runtime",
            ".signalasi-inputs",
            ".tmp",
            "request.json",
            "status.json",
            ".signalasi-checkpoint.json",
            ".signalasi-stdout",
            ".signalasi-stderr",
            ".signalasi-main"
        )
        private const val MAX_PROJECT_BYTES = 2L * 1024L * 1024L * 1024L
        private const val MAX_PROJECT_FILES = 200_000
        private const val MAX_DIFF_CHARACTERS = 256 * 1024
        private const val MAX_LOG_CHARACTERS = 256 * 1024
        private const val MAX_LOG_ENTRIES = 200
        private const val MAX_COMMIT_MESSAGE_CHARACTERS = 4_000
        private const val MAX_PULL_REQUEST_TITLE_CHARACTERS = 256
        private const val MAX_PULL_REQUEST_BODY_CHARACTERS = 32 * 1024
        private const val MAX_GITHUB_RESPONSE_CHARACTERS = 256 * 1024
        private const val DEFAULT_AUTHOR_NAME = "SignalASI"
        private const val DEFAULT_AUTHOR_EMAIL = "signalasi@hotmail.com"
        private val OBJECT_ID_PATTERN = Regex("[0-9a-f]{40,64}")

        internal fun isTrustedRepositoryUrl(value: String): Boolean = runCatching {
            val uri = URI(normalizeRepositoryUrl(value))
            uri.scheme.equals("https", ignoreCase = true) &&
                uri.host.equals("github.com", ignoreCase = true) &&
                uri.userInfo == null && uri.port == -1 && uri.query == null && uri.fragment == null &&
                uri.path.trim('/').removeSuffix(".git").split('/').filter(String::isNotBlank).size == 2
        }.getOrDefault(false)

        internal fun normalizeRepositoryUrl(value: String): String = value.trim().removeSuffix("/")

        internal fun validateRefName(value: String) {
            require(BRANCH_PATTERN.matches(value) && ".." !in value && !value.endsWith(".") &&
                !value.endsWith("/") && !value.startsWith("/") && "//" !in value && "@{" !in value
            ) { "Git branch or ref is invalid" }
        }

        private fun validateRemoteName(value: String): String = value.trim().ifBlank { "origin" }.also {
            require(REMOTE_PATTERN.matches(it)) { "Git remote name is invalid" }
        }

        private fun projectFailure(prefix: String, error: Throwable): IllegalStateException {
            val detail = generateSequence(error) { it.cause }.mapNotNull(Throwable::message).firstOrNull().orEmpty()
            return IllegalStateException("$prefix: ${detail.ifBlank { error::class.java.simpleName }}", error)
        }
    }
}

/** Structured project and Git tools exposed to model-driven phone development loops. */
object AgentMobileProjectNativeTools {
    const val CLONE = "signalasi.project.repository.clone"
    const val INSPECT = "signalasi.project.repository.inspect"
    const val DIFF = "signalasi.project.repository.diff"
    const val LOG = "signalasi.project.repository.log"
    const val FETCH = "signalasi.project.repository.fetch"
    const val CHECKOUT_BRANCH = "signalasi.project.repository.branch.checkout"
    const val COMMIT = "signalasi.project.repository.commit"
    const val PULL = "signalasi.project.repository.pull"
    const val PUSH = "signalasi.project.repository.push"
    const val CREATE_PULL_REQUEST = "signalasi.project.github.pull_request.create"

    const val READ_CONSENT = "signalasi.consent.project_read"
    const val WRITE_CONSENT = "signalasi.consent.project_write"
    const val PUBLISH_CONSENT = "signalasi.consent.project_publish"

    val toolIds: Set<String> = linkedSetOf(
        CLONE,
        INSPECT,
        DIFF,
        LOG,
        FETCH,
        CHECKOUT_BRANCH,
        COMMIT,
        PULL,
        PUSH,
        CREATE_PULL_REQUEST
    )

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val appContext = context.applicationContext
        val credentialProvider = AgentProjectCredentialProvider {
            AgentEncryptedWebIntelligenceCredentials(appContext)
                .credential(AgentEncryptedWebIntelligenceCredentials.GITHUB_TOKEN)
        }
        val runtimeManager = AgentOnDeviceRuntimeManager(appContext)
        val linuxRuntime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse =
                runtimeManager.execute(request)

            override fun rollback(workspaceId: String, checkpointId: String) {
                runtimeManager.rollbackWorkspace(workspaceId, checkpointId)
            }
        }
        val gitBackend = AgentLinuxProjectGitBackend(linuxRuntime, credentialProvider)
        val repository = AgentMobileProjectRepository(
            projectRoot = File(appContext.filesDir, "agent-native-workspaces"),
            credentialProvider = credentialProvider,
            publicationGuard = AgentEncryptedProjectPublicationGuard(
                appContext,
                stateReader = AgentLinuxProjectStateReader(gitBackend)
            ),
            gitBackend = gitBackend
        )
        return definitions(repository)
    }

    internal fun definitions(repository: AgentMobileProjectRepository): List<AgentNativeToolDefinition> = listOf(
        definition(
            CLONE,
            "Prepare a repository in the phone project",
            "Ensures the phone Linux repository is synchronized with the requested remote branch. It clones only when absent; otherwise it fetches and fast-forwards the same persistent workspace. Do not call pull immediately after this succeeds. Credentials are injected only into the built-in Linux Git process and are never shown to the model or stored in the project.",
            input = objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "repository_url" to AgentNativeJsonSchema.string(maxLength = 2_048),
                    "branch" to refSchema(),
                    "depth" to AgentNativeJsonSchema.integer(1, 100),
                    "replace_existing" to AgentNativeJsonSchema.boolean()
                ),
                setOf("workspace_id", "repository_url")
            ),
            risk = AgentNativeToolRisk.MEDIUM,
            consentId = WRITE_CONSENT,
            timeoutMillis = 30 * 60_000L
        ) { invocation ->
            guarded("project_clone_failed") {
                repository.clone(
                    workspaceId = invocation.string("workspace_id"),
                    repositoryUrl = invocation.string("repository_url"),
                    branch = invocation.string("branch"),
                    depth = invocation.integer("depth", 1),
                    replaceExisting = invocation.boolean("replace_existing", false),
                    cancellationToken = invocation.cancellationToken
                ) { stage, message, percent -> invocation.reportProgress(stage, message, percent) }
                    .publicValue()
            }
        },
        definition(
            INSPECT,
            "Inspect the phone project repository",
            "Returns empty, partial, or ready repository state plus the current branch, commit, and remote. Set working_tree=true only when the next decision genuinely requires a full staged, modified, untracked, and conflict scan; metadata-only inspection is the fast default for large phone projects.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "working_tree" to AgentNativeJsonSchema.boolean()
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.LOW,
            READ_CONSENT
        ) { invocation ->
            guarded("project_inspect_failed") {
                repository.inspect(
                    workspaceId = invocation.string("workspace_id"),
                    includeWorkingTree = invocation.boolean("working_tree", false)
                ).publicValue()
            }
        },
        definition(
            DIFF,
            "Read the phone project diff",
            "Returns a bounded staged and unstaged Git diff, or compares base_ref...head_ref when base_ref is supplied, so the supervising model can review edits or branch changes.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "base_ref" to refSchema(),
                    "head_ref" to refSchema(),
                    "max_characters" to AgentNativeJsonSchema.integer(1_000, 256 * 1024L)
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.LOW,
            READ_CONSENT
        ) { invocation ->
            guarded("project_diff_failed") {
                mapOf(
                    "diff" to repository.diff(
                        workspaceId = invocation.string("workspace_id"),
                        maxCharacters = invocation.integer("max_characters", 64 * 1024),
                        baseRef = invocation.string("base_ref"),
                        headRef = invocation.string("head_ref")
                    )
                )
            }
        },
        definition(
            LOG,
            "Read recent phone project commits",
            "Returns a bounded machine-readable Git log for the requested ref so the supervising model can understand recent repository history without inventing shell Git commands.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "ref" to refSchema(),
                    "max_entries" to AgentNativeJsonSchema.integer(1, 200),
                    "max_characters" to AgentNativeJsonSchema.integer(1_000, 256 * 1024L)
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.LOW,
            READ_CONSENT
        ) { invocation ->
            guarded("project_log_failed") {
                mapOf(
                    "log" to repository.log(
                        workspaceId = invocation.string("workspace_id"),
                        ref = invocation.string("ref"),
                        maxEntries = invocation.integer("max_entries", 20),
                        maxCharacters = invocation.integer("max_characters", 64 * 1024)
                    )
                )
            }
        },
        definition(
            FETCH,
            "Fetch phone project remote refs",
            "Fetches remote Git refs in phone Linux without merging them into the current branch. Public repositories do not require a credential; private repositories use the encrypted GitHub credential when configured. Use pull only when the current branch should be updated.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "remote" to AgentNativeJsonSchema.string(maxLength = 160),
                    "ref" to refSchema()
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.MEDIUM,
            WRITE_CONSENT,
            timeoutMillis = 30 * 60_000L
        ) { invocation ->
            guarded("project_fetch_failed") {
                mapOf(
                    "remote_refs" to repository.fetch(
                        workspaceId = invocation.string("workspace_id"),
                        remote = invocation.string("remote").ifBlank { "origin" },
                        ref = invocation.string("ref"),
                        cancellationToken = invocation.cancellationToken
                    )
                )
            }
        },
        definition(
            CHECKOUT_BRANCH,
            "Switch the phone project branch",
            "Creates or checks out a validated Git branch in the current phone project.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "branch" to refSchema(),
                    "base_ref" to refSchema(),
                    "create" to AgentNativeJsonSchema.boolean()
                ),
                setOf("workspace_id", "branch")
            ),
            AgentNativeToolRisk.MEDIUM,
            WRITE_CONSENT
        ) { invocation ->
            guarded("project_branch_failed") {
                repository.checkoutBranch(
                    invocation.string("workspace_id"),
                    invocation.string("branch"),
                    invocation.boolean("create", true),
                    invocation.string("base_ref")
                ).publicValue()
            }
        },
        definition(
            COMMIT,
            "Commit verified phone project changes",
            "Stages all current project changes and creates a local Git commit after the model has inspected and verified the result.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "message" to AgentNativeJsonSchema.string(maxLength = 4_000),
                    "author_name" to AgentNativeJsonSchema.string(maxLength = 120),
                    "author_email" to AgentNativeJsonSchema.string(maxLength = 254)
                ),
                setOf("workspace_id", "message")
            ),
            AgentNativeToolRisk.MEDIUM,
            WRITE_CONSENT
        ) { invocation ->
            guarded("project_commit_failed") {
                repository.commit(
                    invocation.string("workspace_id"),
                    invocation.string("message"),
                    invocation.string("author_name", "SignalASI"),
                    invocation.string("author_email", "signalasi@hotmail.com")
                ).let { mapOf("commit" to it.commit, "branch" to it.branch, "changed_files" to it.changedFiles) }
            }
        },
        definition(
            PULL,
            "Update the phone project from its remote",
            "Fetches and integrates the selected remote branch inside the phone Linux Guest. Public repositories work without a credential; private repositories use the encrypted GitHub credential when configured.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "remote" to remoteSchema(),
                    "branch" to refSchema()
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.MEDIUM,
            WRITE_CONSENT,
            timeoutMillis = 30 * 60_000L
        ) { invocation ->
            guarded("project_pull_failed") {
                repository.pull(
                    invocation.string("workspace_id"),
                    invocation.string("remote", "origin"),
                    invocation.string("branch"),
                    invocation.cancellationToken
                ).let { mapOf("successful" to it.successful, "merge_status" to it.mergeStatus, "head_commit" to it.headCommit) }
            }
        },
        definition(
            PUSH,
            "Publish the phone project branch",
            "Pushes one validated branch to its configured remote with an encrypted host credential that is never shown to the model.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "remote" to remoteSchema(),
                    "branch" to refSchema(),
                    "force" to AgentNativeJsonSchema.boolean()
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.HIGH,
            PUBLISH_CONSENT,
            timeoutMillis = 30 * 60_000L
        ) { invocation ->
            guarded("project_push_failed") {
                repository.push(
                    invocation.string("workspace_id"),
                    invocation.string("remote", "origin"),
                    invocation.string("branch"),
                    invocation.boolean("force", false),
                    invocation.cancellationToken
                ).let { mapOf("branch" to it.branch, "remote_messages" to it.remoteMessages) }
            }
        },
        definition(
            CREATE_PULL_REQUEST,
            "Create a GitHub pull request",
            "Creates a GitHub pull request for a verified phone project branch using the encrypted GitHub credential.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "title" to AgentNativeJsonSchema.string(maxLength = 256),
                    "body" to AgentNativeJsonSchema.string(maxLength = 32 * 1024),
                    "base" to refSchema(),
                    "head" to refSchema()
                ),
                setOf("workspace_id", "title")
            ),
            AgentNativeToolRisk.HIGH,
            PUBLISH_CONSENT,
            timeoutMillis = 60_000L
        ) { invocation ->
            guarded("pull_request_create_failed") {
                repository.createPullRequest(
                    invocation.string("workspace_id"),
                    invocation.string("title"),
                    invocation.string("body"),
                    invocation.string("base", "main"),
                    invocation.string("head")
                ).let { mapOf("number" to it.number, "url" to it.url, "state" to it.state) }
            }
        }
    )

    private fun definition(
        id: String,
        title: String,
        description: String,
        input: AgentNativeJsonSchema,
        risk: AgentNativeToolRisk,
        consentId: String,
        timeoutMillis: Long = 30_000L,
        executor: (AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
    ) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = title,
            description = description,
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = input,
            outputSchema = AgentNativeJsonSchema.any(),
            risk = risk,
            capabilities = setOf("project.android_local", "project.git", "project.supervised"),
            requiredPermissions = listOf(
                AgentNativePermissionRequirement(
                    AgentPhoneNativeToolCatalog.WORKSPACE_PRIVATE_PERMISSION,
                    "App-private project workspace",
                    "Limits repository access to the current SignalASI conversation project"
                )
            ),
            requiredConsents = listOf(AgentNativeConsentRequirement(consentId)),
            timeoutMillis = timeoutMillis,
            idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT
        ),
        executor = AgentNativeToolExecutor(executor),
        executorId = "signalasi.android_project_repository",
        provenanceMetadata = mapOf("credential_scope" to "host_encrypted", "storage_scope" to "app_private")
    )

    private inline fun guarded(code: String, block: () -> AgentNativeJsonObject): AgentNativeToolExecutionResult =
        runCatching(block).fold(
            onSuccess = { AgentNativeToolExecutionResult.success(it, "Phone project operation completed") },
            onFailure = { error ->
                if (error is AgentNativeToolCancelledException) throw error
                AgentNativeToolExecutionResult.failure(code, error.message ?: "Phone project operation failed")
            }
        )

    private fun workspaceOnlySchema() = objectSchema(
        mapOf("workspace_id" to workspaceIdSchema()),
        setOf("workspace_id")
    )

    private fun objectSchema(properties: Map<String, AgentNativeJsonSchema>, required: Set<String>) =
        AgentNativeJsonSchema.objectSchema(properties, required, additionalProperties = false)

    private fun workspaceIdSchema() = AgentNativeJsonSchema.string(
        maxLength = 128,
        pattern = "[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
    )

    private fun refSchema() = AgentNativeJsonSchema.string(maxLength = 128)
    private fun remoteSchema() = AgentNativeJsonSchema.string(maxLength = 64)

    private fun AgentNativeToolInvocation.string(key: String, default: String = ""): String =
        input[key]?.toString()?.trim().orEmpty().ifBlank { default }

    private fun AgentNativeToolInvocation.integer(key: String, default: Int): Int =
        (input[key] as? Number)?.toInt() ?: default

    private fun AgentNativeToolInvocation.boolean(key: String, default: Boolean): Boolean =
        input[key] as? Boolean ?: default
}
