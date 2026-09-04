package com.galaxyssi.chat

import android.content.Context
import java.io.File

/** Imports large ADB-staged archives without exposing Android shared storage to the guest. */
object AgentMobileProjectArchiveTools {
    const val IMPORT_PROJECT = "galaxyssi.project.archive.import"
    const val IMPORT_GRADLE_CACHE = "galaxyssi.project.gradle_cache.import"

    val toolIds: Set<String> = linkedSetOf(IMPORT_PROJECT, IMPORT_GRADLE_CACHE)

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val appContext = context.applicationContext
        val runtime = AgentOnDeviceRuntimeManager(appContext)
        val sourceResolver = AgentProjectArchiveSourceResolver(appContext)
        return listOf(
            definition(
                id = IMPORT_PROJECT,
                title = "Import a project archive into the phone workspace",
                description = "Imports a tar.gz project staged for GalaxySSI into the current Android-local Linux project workspace. Shared Download aliases are resolved by the App; the guest never receives unrestricted shared-storage access."
            ) { invocation ->
                guarded("project_archive_import_failed") {
                    val workspaceId = invocation.string("workspace_id")
                    val source = sourceResolver.resolve(invocation.string("source_path"))
                    invocation.reportProgress("import", "Importing the project archive on this phone")
                    val response = runtime.execute(
                        AgentRuntimeExecutionRequest(
                            language = AgentRuntimeLanguage.SHELL,
                            source = PROJECT_IMPORT_SCRIPT,
                            arguments = emptyList(),
                            timeoutMillis = 30 * 60_000L,
                            networkEnabled = false,
                            artifactPaths = emptyList(),
                            workspaceId = workspaceId,
                            verificationKind = AgentRuntimeVerificationKind.NONE,
                            resourceLimits = AgentRuntimeResourceLimits(
                                wallClockMillis = 30 * 60_000L,
                                cpuMillis = 30 * 60_000L,
                                memoryBytes = 1024L * 1024L * 1024L,
                                diskBytes = 4L * 1024L * 1024L * 1024L,
                                maxProcesses = 64,
                                maxOutputBytes = 1024L * 1024L,
                                maxArtifactBytes = 1024L * 1024L
                            ),
                            cancellationToken = invocation.cancellationToken,
                            progressListener = { progress ->
                                invocation.reportProgress(progress.stage, progress.message, progress.percent)
                            },
                            hostInputFiles = listOf(AgentRuntimeHostInput(source, "project.tar.gz"))
                        )
                    )
                    check(response.exitCode == 0) {
                        response.stderr.ifBlank { "Project archive extraction failed" }
                    }
                    linkedMapOf(
                        "workspace_id" to workspaceId,
                        "source_file" to source.name,
                        "project_file_count" to response.projectFileCount,
                        "project_bytes" to response.projectBytes,
                        "workspace_disposition" to response.workspaceDisposition.wireValue,
                        "summary" to response.stdout.trim().take(4_000)
                    )
                }
            },
            definition(
                id = IMPORT_GRADLE_CACHE,
                title = "Restore the phone Linux Gradle dependency cache",
                description = "Restores a staged Gradle modules-2 tar.gz archive into the persistent Android-local Linux root account cache for offline builds."
            ) { invocation ->
                guarded("gradle_cache_import_failed") {
                    val workspaceId = invocation.string("workspace_id")
                    val source = sourceResolver.resolve(invocation.string("source_path"))
                    invocation.reportProgress("restore", "Restoring the Gradle cache in phone Linux")
                    val response = runtime.execute(
                        AgentRuntimeExecutionRequest(
                            language = AgentRuntimeLanguage.SHELL,
                            source = GRADLE_CACHE_IMPORT_SCRIPT,
                            arguments = emptyList(),
                            timeoutMillis = 30 * 60_000L,
                            networkEnabled = false,
                            artifactPaths = emptyList(),
                            workspaceId = workspaceId,
                            verificationKind = AgentRuntimeVerificationKind.NONE,
                            resourceLimits = AgentRuntimeResourceLimits(
                                wallClockMillis = 30 * 60_000L,
                                cpuMillis = 30 * 60_000L,
                                memoryBytes = 1024L * 1024L * 1024L,
                                diskBytes = 2L * 1024L * 1024L * 1024L,
                                maxProcesses = 64,
                                maxOutputBytes = 1024L * 1024L,
                                maxArtifactBytes = 1024L * 1024L
                            ),
                            cancellationToken = invocation.cancellationToken,
                            progressListener = { progress ->
                                invocation.reportProgress(progress.stage, progress.message, progress.percent)
                            },
                            hostInputFiles = listOf(AgentRuntimeHostInput(source, "gradle-modules-2.tar.gz"))
                        )
                    )
                    check(response.exitCode == 0) {
                        response.stderr.ifBlank { "Gradle dependency cache extraction failed" }
                    }
                    linkedMapOf(
                        "workspace_id" to workspaceId,
                        "source_file" to source.name,
                        "restored" to true,
                        "summary" to response.stdout.trim().take(4_000)
                    )
                }
            }
        )
    }

    private fun definition(
        id: String,
        title: String,
        description: String,
        executor: (AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
    ) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = title,
            description = description,
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = mapOf(
                    "workspace_id" to AgentNativeJsonSchema.string(
                        maxLength = 128,
                        pattern = "[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
                    ),
                    "source_path" to AgentNativeJsonSchema.string(maxLength = 2_048)
                ),
                required = setOf("workspace_id", "source_path"),
                additionalProperties = false
            ),
            outputSchema = AgentNativeJsonSchema.any(),
            risk = AgentNativeToolRisk.LOW,
            capabilities = setOf("project.android_local", "project.import", "runtime.linux"),
            requiredPermissions = listOf(
                AgentNativePermissionRequirement(
                    AgentPhoneNativeToolCatalog.WORKSPACE_PRIVATE_PERMISSION,
                    "App-private project workspace",
                    "Limits imported project data to the current GalaxySSI workspace"
                )
            ),
            timeoutMillis = 30 * 60_000L,
            idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT
        ),
        executor = AgentNativeToolExecutor(executor),
        executorId = "galaxyssi.android_project_archive",
        provenanceMetadata = mapOf("storage_scope" to "app_private", "execution_scope" to "phone_linux")
    )

    private inline fun guarded(
        code: String,
        block: () -> AgentNativeJsonObject
    ): AgentNativeToolExecutionResult = runCatching(block).fold(
        onSuccess = { AgentNativeToolExecutionResult.success(it, "Phone project archive operation completed") },
        onFailure = { error ->
            if (error is AgentNativeToolCancelledException) throw error
            AgentNativeToolExecutionResult.failure(code, error.message ?: "Phone project archive operation failed")
        }
    )

    private fun AgentNativeToolInvocation.string(key: String): String =
        input[key]?.toString()?.trim().orEmpty()

    internal val PROJECT_IMPORT_SCRIPT = """
        set -eu
        python3 - <<'PY'
        import os, pathlib, shutil, tarfile
        root = pathlib.Path.cwd().resolve()
        archive = root / '.galaxyssi-inputs' / 'project.tar.gz'
        stage = root / '.galaxyssi-import-stage'
        if stage.exists(): shutil.rmtree(stage)
        stage.mkdir()
        with tarfile.open(archive, 'r|gz') as tf:
            total = 0
            entries = 0
            extracted = 0
            for member in tf:
                entries += 1
                if entries > 200000: raise RuntimeError('Project archive contains too many entries')
                name = member.name.replace('\\', '/').strip('/')
                parts = [p for p in name.split('/') if p not in ('', '.')]
                if not parts or '..' in parts or member.issym() or member.islnk() or not (member.isdir() or member.isfile()):
                    if parts and not member.isdir(): raise RuntimeError('Project archive contains an unsafe entry')
                    continue
                total += member.size
                if total > 3 * 1024 * 1024 * 1024: raise RuntimeError('Project archive expands beyond 3 GiB')
                target = stage.joinpath(*parts).resolve()
                if target != stage and stage not in target.parents: raise RuntimeError('Project archive escapes the workspace')
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                source = tf.extractfile(member)
                if source is None: raise RuntimeError('Project archive entry cannot be read')
                with source, target.open('wb') as output: shutil.copyfileobj(source, output, 1024 * 1024)
                os.chmod(target, member.mode & 0o777)
                extracted += 1
        stage_children = list(stage.iterdir())
        payload = stage_children[0] if len(stage_children) == 1 and stage_children[0].is_dir() else stage
        if not (payload / '.git').is_dir(): raise RuntimeError('Imported archive is not a Git repository')
        for child in root.iterdir():
            if child.name.startswith('.galaxyssi-'): continue
            if child.is_dir(): shutil.rmtree(child)
            else: child.unlink()
        for child in list(payload.iterdir()): shutil.move(str(child), str(root / child.name))
        if payload != stage: payload.rmdir()
        stage.rmdir()
        print(f'Imported {extracted} project files into the phone workspace')
        PY
    """.trimIndent()

    internal val GRADLE_CACHE_IMPORT_SCRIPT = """
        set -eu
        python3 - <<'PY'
        import pathlib, shutil, tarfile
        root = pathlib.Path.cwd().resolve()
        archive = root / '.galaxyssi-inputs' / 'gradle-modules-2.tar.gz'
        target = pathlib.Path('/root/.gradle/caches').resolve()
        target.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, 'r|gz') as tf:
            total = 0
            extracted = 0
            entries = 0
            for member in tf:
                entries += 1
                if entries > 300000: raise RuntimeError('Gradle cache archive contains too many entries')
                name = member.name.replace('\\', '/').strip('/')
                parts = [p for p in name.split('/') if p not in ('', '.')]
                if not parts or '..' in parts or member.issym() or member.islnk() or not (member.isdir() or member.isfile()):
                    if parts and not member.isdir(): raise RuntimeError('Gradle cache archive contains an unsafe entry')
                    continue
                total += member.size
                if total > 8 * 1024 * 1024 * 1024: raise RuntimeError('Gradle cache expands beyond 8 GiB')
                destination = target.joinpath(*parts).resolve()
                if destination != target and target not in destination.parents: raise RuntimeError('Gradle cache escapes its destination')
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                    continue
                destination.parent.mkdir(parents=True, exist_ok=True)
                source = tf.extractfile(member)
                if source is None: raise RuntimeError('Gradle cache entry cannot be read')
                with source, destination.open('wb') as output: shutil.copyfileobj(source, output, 1024 * 1024)
                extracted += 1
        print(f'Restored {extracted} Gradle cache files for the phone Linux root account')
        PY
    """.trimIndent()
}

internal class AgentProjectArchiveSourceResolver(context: Context) {
    private val root = File(context.getExternalFilesDir(null), "GalaxySSI").canonicalFile.apply {
        check(mkdirs() || isDirectory) { "GalaxySSI archive staging is unavailable" }
    }

    fun resolve(requestedPath: String): File {
        require(requestedPath.isNotBlank()) { "Archive source path is required" }
        val normalized = requestedPath.replace('\\', '/')
        val candidate = if (
            normalized.startsWith("/sdcard/Download/GalaxySSI/") ||
            normalized.startsWith("/storage/emulated/0/Download/GalaxySSI/")
        ) {
            File(root, normalized.substringAfterLast('/'))
        } else {
            File(requestedPath)
        }.canonicalFile
        require(candidate.path.startsWith(root.path + File.separator)) {
            "Archive must be staged in GalaxySSI's app-specific import directory"
        }
        require(candidate.isFile && candidate.canRead()) {
            "Archive is not staged for GalaxySSI: ${candidate.name}"
        }
        require(candidate.name.endsWith(".tar.gz", ignoreCase = true) || candidate.name.endsWith(".tgz", ignoreCase = true)) {
            "Only tar.gz project and dependency archives are supported"
        }
        require(candidate.length() in 1..MAX_ARCHIVE_BYTES) { "Archive size is invalid" }
        return candidate
    }

    companion object {
        private const val MAX_ARCHIVE_BYTES = 2L * 1024L * 1024L * 1024L
    }
}
