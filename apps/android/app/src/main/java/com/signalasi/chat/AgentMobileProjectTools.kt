package com.signalasi.chat

import android.content.Context
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import java.nio.file.Files
import java.nio.file.LinkOption
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.lib.ProgressMonitor
import org.eclipse.jgit.lib.Repository
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.eclipse.jgit.transport.RefSpec
import org.eclipse.jgit.transport.UsernamePasswordCredentialsProvider
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
    val conflicting: List<String>
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "workspace_id" to workspaceId,
        "repository_url" to repositoryUrl,
        "branch" to branch,
        "head_commit" to headCommit,
        "clean" to clean,
        "staged" to staged,
        "modified" to modified,
        "untracked" to untracked,
        "conflicting" to conflicting
    )
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

internal fun interface AgentProjectCloneBackend {
    fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    )
}

/** Host-mediated Git operations for one app-private Agent project workspace. */
internal class AgentMobileProjectRepository(
    projectRoot: File,
    private val credentialProvider: AgentProjectCredentialProvider,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val repositoryPolicy: (String) -> Boolean = ::isTrustedRepositoryUrl,
    private val publicationGuard: AgentProjectPublicationGuard = AgentProjectPublicationGuard.ALLOW_ALL,
    private val cloneBackend: AgentProjectCloneBackend? = null
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
        require(replaceExisting || !hasCloneBlockingContent(target)) {
            "The phone project workspace is not empty"
        }
        cloneBackend?.let { backend ->
            progress("clone", "Cloning repository in the phone Linux runtime", 0)
            try {
                backend.clone(
                    workspaceId = workspaceId,
                    repositoryUrl = cleanUrl,
                    branch = cleanBranch,
                    depth = depth,
                    replaceExisting = replaceExisting,
                    cancellationToken = cancellationToken,
                    progress = progress
                )
                check(projectBytes(target) <= MAX_PROJECT_BYTES) { "Cloned project exceeds the phone workspace quota" }
                publicationGuard.invalidate(workspaceId)
                progress("clone", "Linux repository clone completed", 100)
                return@withLock open(workspaceId).use { snapshot(workspaceId, it) }
            } catch (error: Throwable) {
                throw projectFailure("Linux repository clone failed", error)
            }
        }
        val parent = target.parentFile ?: error("Phone project storage is invalid")
        val staging = File(parent, ".${target.name}.clone-staging").canonicalFile
        val backup = File(parent, ".${target.name}.clone-backup").canonicalFile
        require(staging.path.startsWith(root.path + File.separator)) { "Clone staging path is invalid" }
        staging.deleteRecursively()
        backup.deleteRecursively()
        progress("clone", "Cloning repository into the phone project workspace", 0)
        try {
            val command = Git.cloneRepository()
                .setURI(cleanUrl)
                .setDirectory(staging)
                .setCloneAllBranches(false)
                .setDepth(depth)
                .setTimeout(CLONE_TIMEOUT_SECONDS)
                .setProgressMonitor(CancellableProgressMonitor(cancellationToken, progress))
            if (cleanBranch.isNotBlank()) command.setBranch(cleanBranch)
            credentials()?.let(command::setCredentialsProvider)
            command.call().use { git ->
                check(projectBytes(staging) <= MAX_PROJECT_BYTES) { "Cloned project exceeds the phone workspace quota" }
            }
            if (target.listFiles().orEmpty().isNotEmpty()) check(target.renameTo(backup)) {
                "Existing phone project could not be staged"
            } else target.deleteRecursively()
            if (!staging.renameTo(target)) {
                target.deleteRecursively()
                if (backup.exists()) backup.renameTo(target)
                error("Cloned repository could not be committed to the phone workspace")
            }
            backup.deleteRecursively()
            publicationGuard.invalidate(workspaceId)
            progress("clone", "Repository clone completed", 100)
            open(workspaceId).use { snapshot(workspaceId, it) }
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw projectFailure("Repository clone failed", error)
        }
    }

    fun inspect(workspaceId: String): AgentProjectRepositorySnapshot =
        AgentWorkspaceScope.withLock(workspaceId) {
            open(workspaceId).use { repository -> snapshot(workspaceId, repository) }
        }

    fun diff(workspaceId: String, maxCharacters: Int): String =
        AgentWorkspaceScope.withLock(workspaceId) {
            require(maxCharacters in 1_000..MAX_DIFF_CHARACTERS) { "Diff output limit is invalid" }
            openGit(workspaceId).use { git ->
                val output = ByteArrayOutputStream()
                git.diff().setOutputStream(output).call()
                git.diff().setCached(true).setOutputStream(output).call()
                output.toString(Charsets.UTF_8.name()).take(maxCharacters)
            }
        }

    fun checkoutBranch(workspaceId: String, branch: String, create: Boolean): AgentProjectRepositorySnapshot =
        AgentWorkspaceScope.withLock(workspaceId) {
            val cleanBranch = branch.trim().also(::validateRefName)
            openGit(workspaceId).use { git ->
                git.checkout().setName(cleanBranch).setCreateBranch(create).call()
                publicationGuard.invalidate(workspaceId)
                snapshot(workspaceId, git.repository)
            }
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
        openGit(workspaceId).use { git ->
            val before = git.status().call()
            require(!before.isClean) { "The phone project has no changes to commit" }
            val changed = changedFiles(before)
            git.add().addFilepattern(".").call()
            git.add().setUpdate(true).addFilepattern(".").call()
            val commit = git.commit()
                .setMessage(cleanMessage)
                .setAuthor(name, email)
                .setCommitter(name, email)
                .call()
            AgentProjectCommitResult(commit.name, git.repository.branch.orEmpty(), changed).also { result ->
                publicationGuard.recordCommit(workspaceId, result.commit, result.branch)
            }
        }
    }

    fun pull(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentProjectPullResult = AgentWorkspaceScope.withLock(workspaceId) {
        val cleanRemote = validateRemoteName(remote)
        val cleanBranch = branch.trim().ifBlank { currentBranch(workspaceId) }.also(::validateRefName)
        openGit(workspaceId).use { git ->
            requireAllowedRemote(git.repository, cleanRemote)
            val command = git.pull()
                .setRemote(cleanRemote)
                .setRemoteBranchName(cleanBranch)
                .setProgressMonitor(CancellableProgressMonitor(cancellationToken) { _, _, _ -> })
            credentials()?.let(command::setCredentialsProvider)
            val result = command.call()
            publicationGuard.invalidate(workspaceId)
            AgentProjectPullResult(
                successful = result.isSuccessful,
                mergeStatus = result.mergeResult?.mergeStatus?.toString()
                    ?: result.rebaseResult?.status?.toString().orEmpty(),
                headCommit = git.repository.resolve("HEAD")?.name.orEmpty()
            )
        }
    }

    fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentProjectPushResult = AgentWorkspaceScope.withLock(workspaceId) {
        val credentials = credentials() ?: error("Configure a GitHub token before publishing a phone project")
        val cleanRemote = validateRemoteName(remote)
        val cleanBranch = branch.trim().ifBlank { currentBranch(workspaceId) }.also(::validateRefName)
        publicationGuard.requirePushable(workspaceId, cleanBranch)
        openGit(workspaceId).use { git ->
            requireAllowedRemote(git.repository, cleanRemote)
            val updates = git.push()
                .setRemote(cleanRemote)
                .setRefSpecs(RefSpec("refs/heads/$cleanBranch:refs/heads/$cleanBranch"))
                .setForce(force)
                .setCredentialsProvider(credentials)
                .setProgressMonitor(CancellableProgressMonitor(cancellationToken) { _, _, _ -> })
                .call()
                .flatMap { result -> result.remoteUpdates.map { update -> "${update.remoteName}: ${update.status}" } }
            require(updates.none { it.contains("REJECTED", ignoreCase = true) }) {
                "Remote rejected the phone project update: ${updates.joinToString()}"
            }
            AgentProjectPushResult(cleanBranch, updates).also {
                publicationGuard.recordPush(
                    workspaceId,
                    git.repository.resolve("HEAD")?.name.orEmpty(),
                    cleanBranch
                )
            }
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
        val cleanTitle = title.trim().take(MAX_PULL_REQUEST_TITLE_CHARACTERS)
        require(cleanTitle.isNotBlank()) { "Pull request title is required" }
        val cleanBase = base.trim().ifBlank { "main" }.also(::validateRefName)
        val cleanHead = head.trim().ifBlank { currentBranch(workspaceId) }.also(::validateRefName)
        publicationGuard.requirePullRequestReady(workspaceId, cleanHead)
        val repository = open(workspaceId).use(::githubCoordinates)
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

    private fun snapshot(workspaceId: String, repository: Repository): AgentProjectRepositorySnapshot {
        Git(repository).use { git ->
            val status = git.status().call()
            return AgentProjectRepositorySnapshot(
                workspaceId = workspaceId,
                repositoryUrl = repository.config.getString("remote", "origin", "url").orEmpty(),
                branch = repository.branch.orEmpty(),
                headCommit = repository.resolve("HEAD")?.name.orEmpty(),
                clean = status.isClean,
                staged = (status.added + status.changed + status.removed).sorted(),
                modified = (status.modified + status.missing).sorted(),
                untracked = status.untracked.sorted(),
                conflicting = status.conflicting.sorted()
            )
        }
    }

    private fun openGit(workspaceId: String): Git = Git(open(workspaceId))

    private fun open(workspaceId: String): Repository {
        val workspace = workspaceDirectory(workspaceId)
        val gitDirectory = File(workspace, ".git")
        require(gitDirectory.isDirectory) { "The phone workspace does not contain a Git repository" }
        return FileRepositoryBuilder().setGitDir(gitDirectory).setWorkTree(workspace).build()
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
        if (cloneBackend == null) return entries.isNotEmpty()
        return entries.any { entry ->
            Files.isSymbolicLink(entry.toPath()) || entry.name !in LINUX_RUNTIME_MANAGED_ENTRIES
        }
    }

    private fun currentBranch(workspaceId: String): String = open(workspaceId).use { it.branch.orEmpty() }

    private fun credentials(): UsernamePasswordCredentialsProvider? = credentialProvider.token().trim()
        .takeIf(String::isNotBlank)
        ?.let { UsernamePasswordCredentialsProvider("x-access-token", it) }

    private fun githubCoordinates(repository: Repository): Pair<String, String> {
        val url = normalizeRepositoryUrl(repository.config.getString("remote", "origin", "url").orEmpty())
        val uri = URI(url)
        require(uri.host.equals("github.com", ignoreCase = true)) { "Pull requests require a GitHub origin" }
        val segments = uri.path.trim('/').removeSuffix(".git").split('/').filter(String::isNotBlank)
        require(segments.size == 2) { "GitHub repository origin is invalid" }
        return segments[0] to segments[1]
    }

    private fun requireAllowedRemote(repository: Repository, remote: String) {
        val url = repository.config.getString("remote", remote, "url").orEmpty()
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

    private fun changedFiles(status: org.eclipse.jgit.api.Status): List<String> = (
        status.added + status.changed + status.removed + status.modified + status.missing +
            status.untracked + status.conflicting
        ).distinct().sorted()

    private class CancellableProgressMonitor(
        private val cancellationToken: AgentNativeToolCancellationToken,
        private val observer: (String, String, Int?) -> Unit
    ) : ProgressMonitor {
        private var totalWork = ProgressMonitor.UNKNOWN
        private var completed = 0
        private var title = "repository"

        override fun start(totalTasks: Int) {
            observer("git", "Preparing repository operation", 0)
        }

        override fun beginTask(title: String?, totalWork: Int) {
            this.title = title.orEmpty().ifBlank { "repository" }
            this.totalWork = totalWork
            completed = 0
            observer("git", this.title, if (totalWork == ProgressMonitor.UNKNOWN) null else 0)
        }

        override fun update(completed: Int) {
            this.completed += completed.coerceAtLeast(0)
            val percent = totalWork.takeIf { it > 0 }?.let { ((this.completed * 100L) / it).toInt().coerceIn(0, 99) }
            observer("git", title, percent)
        }

        override fun endTask() {
            observer("git", title, 100)
        }

        override fun isCancelled(): Boolean = cancellationToken.isCancellationRequested

        override fun showDuration(enabled: Boolean) = Unit
    }

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
        private const val MAX_COMMIT_MESSAGE_CHARACTERS = 4_000
        private const val MAX_PULL_REQUEST_TITLE_CHARACTERS = 256
        private const val MAX_PULL_REQUEST_BODY_CHARACTERS = 32 * 1024
        private const val MAX_GITHUB_RESPONSE_CHARACTERS = 256 * 1024
        private const val CLONE_TIMEOUT_SECONDS = 90
        private const val DEFAULT_AUTHOR_NAME = "SignalASI"
        private const val DEFAULT_AUTHOR_EMAIL = "signalasi@hotmail.com"

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
        val repository = AgentMobileProjectRepository(
            projectRoot = File(appContext.filesDir, "agent-native-workspaces"),
            credentialProvider = credentialProvider,
            publicationGuard = AgentEncryptedProjectPublicationGuard(appContext),
            cloneBackend = AgentLinuxProjectCloneBackend(
                runtime = object : AgentProjectLinuxRuntime {
                    override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse =
                        runtimeManager.execute(request)

                    override fun rollback(workspaceId: String, checkpointId: String) {
                        runtimeManager.rollbackWorkspace(workspaceId, checkpointId)
                    }
                },
                credentialProvider = credentialProvider
            )
        )
        return definitions(repository)
    }

    internal fun definitions(repository: AgentMobileProjectRepository): List<AgentNativeToolDefinition> = listOf(
        definition(
            CLONE,
            "Clone a repository into the phone project",
            "Clones one trusted GitHub repository directly inside the phone Linux runtime. Credentials are injected only into the built-in clone process and are never shown to the model or stored in the project.",
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
            "Returns the current branch, commit, remote, and bounded working-tree state for the conversation project.",
            workspaceOnlySchema(),
            AgentNativeToolRisk.LOW,
            READ_CONSENT
        ) { invocation -> guarded("project_inspect_failed") { repository.inspect(invocation.string("workspace_id")).publicValue() } },
        definition(
            DIFF,
            "Read the phone project diff",
            "Returns a bounded staged and unstaged Git diff so the supervising model can review edits before building or committing.",
            objectSchema(
                mapOf(
                    "workspace_id" to workspaceIdSchema(),
                    "max_characters" to AgentNativeJsonSchema.integer(1_000, 256 * 1024L)
                ),
                setOf("workspace_id")
            ),
            AgentNativeToolRisk.LOW,
            READ_CONSENT
        ) { invocation ->
            guarded("project_diff_failed") {
                mapOf("diff" to repository.diff(invocation.string("workspace_id"), invocation.integer("max_characters", 64 * 1024)))
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
                    invocation.boolean("create", true)
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
            "Fetches and integrates the selected remote branch using host-mediated Git with encrypted credentials.",
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
