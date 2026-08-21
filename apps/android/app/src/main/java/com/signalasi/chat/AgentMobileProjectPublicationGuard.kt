package com.signalasi.chat

import android.content.Context
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.security.MessageDigest
import java.util.Locale
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.json.JSONObject

internal data class AgentProjectVerificationTicket(
    val workspaceId: String,
    val verificationKind: AgentRuntimeVerificationKind,
    val requestId: String,
    val projectDigest: String,
    val stdoutSha256: String,
    val completedAtMillis: Long,
    val commit: String = "",
    val branch: String = "",
    val pushedCommit: String = "",
    val pushedBranch: String = ""
)

internal interface AgentProjectPublicationGuard {
    fun invalidate(workspaceId: String)
    fun recordVerification(receipt: AgentRuntimeExecutionReceipt)
    fun recordDocumentationReview(workspaceId: String, diff: String)
    fun requireVerified(workspaceId: String)
    fun recordCommit(workspaceId: String, commit: String, branch: String)
    fun requirePushable(workspaceId: String, branch: String)
    fun recordPush(workspaceId: String, commit: String, branch: String)
    fun requirePullRequestReady(workspaceId: String, head: String)
    fun hasPullRequestEvidence(workspaceId: String, head: String): Boolean

    companion object {
        val ALLOW_ALL = object : AgentProjectPublicationGuard {
            override fun invalidate(workspaceId: String) = Unit
            override fun recordVerification(receipt: AgentRuntimeExecutionReceipt) = Unit
            override fun recordDocumentationReview(workspaceId: String, diff: String) = Unit
            override fun requireVerified(workspaceId: String) = Unit
            override fun recordCommit(workspaceId: String, commit: String, branch: String) = Unit
            override fun requirePushable(workspaceId: String, branch: String) = Unit
            override fun recordPush(workspaceId: String, commit: String, branch: String) = Unit
            override fun requirePullRequestReady(workspaceId: String, head: String) = Unit
            override fun hasPullRequestEvidence(workspaceId: String, head: String): Boolean = true
        }
    }
}

internal interface AgentProjectVerificationTicketStore {
    fun read(workspaceId: String): AgentProjectVerificationTicket?
    fun write(ticket: AgentProjectVerificationTicket)
    fun remove(workspaceId: String)
}

internal class AgentProjectPublicationPolicy(
    private val projectRoot: File,
    private val ticketStore: AgentProjectVerificationTicketStore
) : AgentProjectPublicationGuard {

    override fun invalidate(workspaceId: String) {
        ticketStore.remove(workspaceId)
    }

    override fun recordVerification(receipt: AgentRuntimeExecutionReceipt) {
        require(receipt.status == AgentRuntimeReceiptStatus.COMPLETED && receipt.exitCode == 0) {
            "Only a successful runtime receipt can verify a project"
        }
        require(receipt.verificationKind != AgentRuntimeVerificationKind.NONE) {
            "Runtime verification kind is required"
        }
        if (!AgentProjectStateDigester.isRepository(projectRoot, receipt.workspaceId)) {
            ticketStore.remove(receipt.workspaceId)
            return
        }
        val ticket = AgentProjectVerificationTicket(
            workspaceId = receipt.workspaceId,
            verificationKind = receipt.verificationKind,
            requestId = receipt.requestId,
            projectDigest = AgentProjectStateDigester.digest(projectRoot, receipt.workspaceId),
            stdoutSha256 = receipt.stdoutSha256,
            completedAtMillis = receipt.completedAtMillis
        )
        ticketStore.write(ticket)
    }

    override fun recordDocumentationReview(workspaceId: String, diff: String) {
        require(diff.isNotBlank() && '\u0000' !in diff && "GIT binary patch" !in diff) {
            "A complete text diff is required to verify documentation changes"
        }
        if (!AgentProjectStateDigester.isRepository(projectRoot, workspaceId)) {
            ticketStore.remove(workspaceId)
            return
        }
        val changedFiles = AgentProjectStateDigester.changedFiles(projectRoot, workspaceId)
        require(changedFiles.isNotEmpty() && changedFiles.all(::isDocumentationPath)) {
            "Documentation review can verify documentation-only changes"
        }
        val diffSha256 = MessageDigest.getInstance("SHA-256")
            .digest(diff.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        ticketStore.write(
            AgentProjectVerificationTicket(
                workspaceId = workspaceId,
                verificationKind = AgentRuntimeVerificationKind.LINT,
                requestId = "documentation-diff:$diffSha256",
                projectDigest = AgentProjectStateDigester.digest(projectRoot, workspaceId),
                stdoutSha256 = diffSha256,
                completedAtMillis = System.currentTimeMillis()
            )
        )
    }

    override fun requireVerified(workspaceId: String) {
        val ticket = ticketStore.read(workspaceId)
            ?: error("Run a successful project test, build, lint, or package verification before committing")
        check(ticket.projectDigest == AgentProjectStateDigester.digest(projectRoot, workspaceId)) {
            "The phone project changed after verification; run verification again before committing"
        }
    }

    override fun recordCommit(workspaceId: String, commit: String, branch: String) {
        val ticket = ticketStore.read(workspaceId) ?: error("Project verification ticket is unavailable")
        ticketStore.write(ticket.copy(commit = commit, branch = branch, pushedCommit = "", pushedBranch = ""))
    }

    override fun requirePushable(workspaceId: String, branch: String) {
        val ticket = ticketStore.read(workspaceId) ?: error("Commit verified project changes before publishing")
        if (AgentProjectStateDigester.usesGuestGitMetadata(projectRoot, workspaceId)) {
            check(ticket.projectDigest == AgentProjectStateDigester.digest(projectRoot, workspaceId)) {
                "The phone project changed after verification; verify and commit it before publishing"
            }
            check(ticket.commit.isNotBlank() && ticket.branch == branch) {
                "The current phone project commit is not covered by the verification ticket"
            }
            return
        }
        val state = AgentProjectStateDigester.repositoryState(projectRoot, workspaceId)
        check(state.clean) { "The phone project changed after commit; verify and commit it before publishing" }
        check(ticket.commit.isNotBlank() && ticket.commit == state.headCommit && ticket.branch == branch) {
            "The current phone project commit is not covered by the verification ticket"
        }
    }

    override fun recordPush(workspaceId: String, commit: String, branch: String) {
        val ticket = ticketStore.read(workspaceId) ?: error("Project verification ticket is unavailable")
        ticketStore.write(ticket.copy(pushedCommit = commit, pushedBranch = branch))
    }

    override fun requirePullRequestReady(workspaceId: String, head: String) {
        val ticket = ticketStore.read(workspaceId)
            ?: error("Push a verified phone project branch before creating a pull request")
        if (AgentProjectStateDigester.usesGuestGitMetadata(projectRoot, workspaceId)) {
            check(
                ticket.projectDigest == AgentProjectStateDigester.digest(projectRoot, workspaceId) &&
                    ticket.pushedCommit.isNotBlank() && ticket.pushedBranch == head
            ) {
                "The pull request branch is not the latest verified and pushed phone project commit"
            }
            return
        }
        val state = AgentProjectStateDigester.repositoryState(projectRoot, workspaceId)
        check(state.clean && ticket.pushedCommit == state.headCommit && ticket.pushedBranch == head) {
            "The pull request branch is not the latest verified and pushed phone project commit"
        }
    }

    override fun hasPullRequestEvidence(workspaceId: String, head: String): Boolean =
        runCatching { requirePullRequestReady(workspaceId, head) }.isSuccess

    private fun isDocumentationPath(path: String): Boolean {
        val normalized = path.replace('\\', '/').lowercase(Locale.ROOT)
        val name = normalized.substringAfterLast('/')
        return name in DOCUMENTATION_NAMES || DOCUMENTATION_EXTENSIONS.any(normalized::endsWith)
    }

    private companion object {
        val DOCUMENTATION_NAMES = setOf(
            "readme",
            "license",
            "notice",
            "changelog",
            "contributing",
            "code_of_conduct",
            "security"
        )
        val DOCUMENTATION_EXTENSIONS = setOf(".md", ".mdx", ".rst", ".adoc", ".txt")
    }
}

internal class AgentEncryptedProjectPublicationGuard(
    context: Context,
    projectRoot: File = File(context.applicationContext.filesDir, "agent-native-workspaces")
) : AgentProjectPublicationGuard by AgentProjectPublicationPolicy(
    projectRoot = projectRoot,
    ticketStore = AgentEncryptedProjectVerificationTicketStore(context.applicationContext)
)

private class AgentEncryptedProjectVerificationTicketStore(
    context: Context
) : AgentProjectVerificationTicketStore {
    private val database = AgentEncryptedDatabase(context, DATABASE)

    override fun read(workspaceId: String): AgentProjectVerificationTicket? {
        val raw = database.readString(key(workspaceId), "")
        if (raw.isBlank()) return null
        return runCatching {
            val json = JSONObject(raw)
            AgentProjectVerificationTicket(
                workspaceId = json.getString("workspace_id"),
                verificationKind = AgentRuntimeVerificationKind.fromWireValue(json.getString("verification_kind")),
                requestId = json.getString("request_id"),
                projectDigest = json.getString("project_digest"),
                stdoutSha256 = json.optString("stdout_sha256"),
                completedAtMillis = json.getLong("completed_at_millis"),
                commit = json.optString("commit"),
                branch = json.optString("branch"),
                pushedCommit = json.optString("pushed_commit"),
                pushedBranch = json.optString("pushed_branch")
            )
        }.getOrNull()?.takeIf { it.workspaceId == workspaceId }
    }

    override fun write(ticket: AgentProjectVerificationTicket) {
        database.writeString(key(ticket.workspaceId), JSONObject()
            .put("workspace_id", ticket.workspaceId)
            .put("verification_kind", ticket.verificationKind.wireValue)
            .put("request_id", ticket.requestId)
            .put("project_digest", ticket.projectDigest)
            .put("stdout_sha256", ticket.stdoutSha256)
            .put("completed_at_millis", ticket.completedAtMillis)
            .put("commit", ticket.commit)
            .put("branch", ticket.branch)
            .put("pushed_commit", ticket.pushedCommit)
            .put("pushed_branch", ticket.pushedBranch)
            .toString())
    }

    override fun remove(workspaceId: String) {
        database.remove(key(workspaceId))
    }

    private fun key(workspaceId: String): String = "workspace:${workspaceId.lowercase(Locale.ROOT)}"

    private companion object {
        const val DATABASE = "agent_project_publication_guard_v1.db"
    }
}

internal object AgentProjectStateDigester {
    data class RepositoryState(val headCommit: String, val branch: String, val clean: Boolean)

    fun repositoryState(projectRoot: File, workspaceId: String): RepositoryState = open(projectRoot, workspaceId).use { repository ->
        Git(repository).use { git ->
            RepositoryState(
                headCommit = repository.resolve("HEAD")?.name.orEmpty(),
                branch = repository.branch.orEmpty(),
                clean = git.status().call().isClean
            )
        }
    }

    fun digest(projectRoot: File, workspaceId: String): String {
        if (usesGuestGitMetadata(projectRoot, workspaceId)) {
            return digestGuestWorkspace(workspaceDirectory(projectRoot, workspaceId))
        }
        return open(projectRoot, workspaceId).use { repository ->
        Git(repository).use { git ->
            val status = git.status().call()
            check(status.conflicting.isEmpty()) { "Resolve Git conflicts before verifying the phone project" }
            val workspace = repository.workTree.canonicalFile
            val paths = (
                status.added + status.changed + status.removed + status.modified + status.missing + status.untracked
                ).distinct().sorted()
            val digest = MessageDigest.getInstance("SHA-256")
            digest.update(repository.resolve("HEAD")?.name.orEmpty().toByteArray(Charsets.UTF_8))
            paths.forEach { path ->
                val candidate = File(workspace, path).canonicalFile
                check(candidate.path.startsWith(workspace.path + File.separator)) { "Git path escapes the phone project" }
                digest.update(path.toByteArray(Charsets.UTF_8))
                when {
                    !candidate.exists() -> digest.update("deleted".toByteArray(Charsets.UTF_8))
                    Files.isSymbolicLink(candidate.toPath()) -> error("Symbolic links are not allowed in phone projects")
                    Files.isRegularFile(candidate.toPath(), LinkOption.NOFOLLOW_LINKS) -> candidate.inputStream().buffered().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            digest.update(buffer, 0, read)
                        }
                    }
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        }
        }
    }

    fun changedFiles(projectRoot: File, workspaceId: String): List<String> =
        open(projectRoot, workspaceId).use { repository ->
            Git(repository).use { git ->
                val status = git.status().call()
                (status.added + status.changed + status.removed + status.modified + status.missing +
                    status.untracked + status.conflicting).distinct().sorted()
            }
        }

    fun isRepository(projectRoot: File, workspaceId: String): Boolean = runCatching {
        val git = workspaceDirectory(projectRoot, workspaceId).resolve(".git")
        git.isDirectory || validGuestGitPointer(git, workspaceId)
    }.getOrDefault(false)

    fun usesGuestGitMetadata(projectRoot: File, workspaceId: String): Boolean = runCatching {
        validGuestGitPointer(workspaceDirectory(projectRoot, workspaceId).resolve(".git"), workspaceId)
    }.getOrDefault(false)

    private fun open(projectRoot: File, workspaceId: String) = run {
        val workspace = workspaceDirectory(projectRoot, workspaceId)
        val gitDirectory = File(workspace, ".git")
        require(gitDirectory.isDirectory) { "The phone workspace does not contain a Git repository" }
        FileRepositoryBuilder().setGitDir(gitDirectory).setWorkTree(workspace).build()
    }

    private fun workspaceDirectory(projectRoot: File, workspaceId: String): File {
        require(workspaceId.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}"))) { "Phone project workspace id is invalid" }
        val root = projectRoot.canonicalFile
        val workspace = File(root, workspaceId).canonicalFile
        require(workspace.path.startsWith(root.path + File.separator)) { "Phone project path escapes app storage" }
        return workspace
    }

    private fun validGuestGitPointer(git: File, workspaceId: String): Boolean {
        if (!git.isFile || git.length() !in 1..512) return false
        return git.readText(Charsets.UTF_8).trim() == "gitdir: /var/lib/signalasi/git/$workspaceId"
    }

    private fun digestGuestWorkspace(workspace: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        Files.walk(workspace.toPath()).use { paths ->
            paths.filter { path ->
                Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) &&
                    !Files.isSymbolicLink(path) &&
                    !isRuntimeManaged(workspace.toPath().relativize(path).toString())
            }.sorted().forEach { path ->
                val relative = workspace.toPath().relativize(path).toString().replace(File.separatorChar, '/')
                digest.update(relative.toByteArray(Charsets.UTF_8))
                digest.update(0)
                Files.newInputStream(path).use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                    }
                }
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun isRuntimeManaged(relativePath: String): Boolean {
        val normalized = relativePath.replace('\\', '/')
        val first = normalized.substringBefore('/')
        return first in RUNTIME_MANAGED_DIRECTORIES || first in RUNTIME_MANAGED_FILES
    }

    private val RUNTIME_MANAGED_DIRECTORIES = setOf(
        ".git",
        ".tmp",
        ".signalasi-runtime",
        ".signalasi-inputs",
        ".signalasi-tools"
    )

    private val RUNTIME_MANAGED_FILES = setOf(
        ".signalasi-checkpoint.json",
        ".signalasi-stdout",
        ".signalasi-stderr",
        ".signalasi-main"
    )
}
