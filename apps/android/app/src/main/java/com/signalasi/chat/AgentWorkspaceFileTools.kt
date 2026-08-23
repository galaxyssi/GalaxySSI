package com.signalasi.chat

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStreamReader
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.file.AccessDeniedException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.DirectoryNotEmptyException
import java.nio.file.FileAlreadyExistsException
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.InvalidPathException
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.NoSuchFileException
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.SimpleFileVisitor
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.COPY_ATTRIBUTES
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.CREATE_NEW
import java.nio.file.StandardOpenOption.READ
import java.nio.file.StandardOpenOption.WRITE
import java.nio.file.attribute.BasicFileAttributes
import java.nio.file.attribute.FileTime
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import kotlin.math.max

enum class AgentWorkspaceFileErrorCode {
    INVALID_WORKSPACE,
    INVALID_PATH,
    PATH_ESCAPE,
    SYMLINK_REJECTED,
    NOT_FOUND,
    ALREADY_EXISTS,
    NOT_A_FILE,
    NOT_A_DIRECTORY,
    DIRECTORY_NOT_EMPTY,
    UNSUPPORTED_FILE_TYPE,
    INVALID_TEXT,
    LIMIT_EXCEEDED,
    PATCH_MISMATCH,
    INVALID_ARCHIVE,
    ACCESS_DENIED,
    IO_ERROR
}

data class AgentWorkspaceFileError(
    val code: AgentWorkspaceFileErrorCode,
    val operation: String,
    val path: String,
    val message: String
)

sealed class AgentWorkspaceFileResult<out T> {
    data class Success<T>(val value: T) : AgentWorkspaceFileResult<T>()
    data class Failure(val error: AgentWorkspaceFileError) : AgentWorkspaceFileResult<Nothing>()

    val successful: Boolean get() = this is Success
}

data class AgentWorkspaceFilePolicy(
    val maxTextReadBytes: Long = 1L * 1024 * 1024,
    val maxBytesReadBytes: Long = 8L * 1024 * 1024,
    val maxWriteBytes: Long = 16L * 1024 * 1024,
    val maxListEntries: Int = 10_000,
    val maxTreeEntries: Int = 20_000,
    val maxSearchFileBytes: Long = 1L * 1024 * 1024,
    val maxSearchTotalBytes: Long = 16L * 1024 * 1024,
    val maxSearchResults: Int = 500,
    val maxPatchBytes: Long = 2L * 1024 * 1024,
    val maxHashBytes: Long = 128L * 1024 * 1024,
    val maxZipArchiveBytes: Long = 64L * 1024 * 1024,
    val maxZipEntries: Int = 2_048,
    val maxZipEntryBytes: Long = 16L * 1024 * 1024,
    val maxZipUncompressedBytes: Long = 64L * 1024 * 1024,
    val maxZipCompressionRatio: Double = 100.0,
    val maxZipEntryNameCharacters: Int = 512
) {
    init {
        require(maxTextReadBytes in 1..Int.MAX_VALUE.toLong())
        require(maxBytesReadBytes in 1..Int.MAX_VALUE.toLong())
        require(maxWriteBytes in 1..Int.MAX_VALUE.toLong())
        require(maxListEntries > 0)
        require(maxTreeEntries > 0)
        require(maxSearchFileBytes in 1..Int.MAX_VALUE.toLong())
        require(maxSearchTotalBytes > 0)
        require(maxSearchResults > 0)
        require(maxPatchBytes in 1..Int.MAX_VALUE.toLong())
        require(maxHashBytes > 0)
        require(maxZipArchiveBytes > 0)
        require(maxZipEntries > 0)
        require(maxZipEntryBytes > 0)
        require(maxZipUncompressedBytes > 0)
        require(maxZipCompressionRatio >= 1.0 && maxZipCompressionRatio.isFinite())
        require(maxZipEntryNameCharacters > 0)
    }
}

enum class AgentWorkspaceEntryType {
    FILE,
    DIRECTORY
}

data class AgentWorkspaceFileMetadata(
    val path: String,
    val type: AgentWorkspaceEntryType,
    val sizeBytes: Long,
    val lastModifiedMillis: Long
)

enum class AgentWorkspaceMutationKind {
    INITIALIZE,
    MKDIR,
    WRITE,
    CREATE,
    APPEND,
    MOVE,
    COPY,
    DELETE
}

data class AgentWorkspaceMutation(
    val kind: AgentWorkspaceMutationKind,
    val path: String,
    val sourcePath: String = "",
    val affectedEntries: Int = 1,
    val affectedBytes: Long = 0,
    val metadata: AgentWorkspaceFileMetadata? = null
)

data class AgentWorkspaceTextFile(
    val path: String,
    val text: String
)

data class AgentWorkspaceBatchMutation(
    val files: List<AgentWorkspaceMutation>,
    val affectedBytes: Long
)

data class AgentWorkspaceDirectoryListing(
    val path: String,
    val recursive: Boolean,
    val entries: List<AgentWorkspaceFileMetadata>
)

data class AgentWorkspaceTextRead(
    val path: String,
    val text: String,
    val sizeBytes: Long,
    val sha256: String,
    val returnedBytes: Long,
    val startLine: Int,
    val endLine: Int,
    val totalLines: Int,
    val truncatedBefore: Boolean,
    val truncatedAfter: Boolean
)

data class AgentWorkspaceBytesRead(
    val path: String,
    val bytes: ByteArray,
    val metadata: AgentWorkspaceFileMetadata,
    val sha256: String
)

data class AgentWorkspaceSearchMatch(
    val path: String,
    val line: Int,
    val column: Int,
    val excerpt: String
)

data class AgentWorkspaceTextSearchResult(
    val query: String,
    val matches: List<AgentWorkspaceSearchMatch>,
    val scannedFiles: Int,
    val skippedFiles: Int,
    val skippedDirectories: Int,
    val scannedBytes: Long,
    val truncated: Boolean
)

data class AgentWorkspaceDiffSummary(
    val beforeSha256: String,
    val afterSha256: String,
    val beforeBytes: Long,
    val afterBytes: Long,
    val beforeLines: Int,
    val afterLines: Int,
    val addedLines: Int,
    val deletedLines: Int,
    val changedLinePairs: Int,
    val firstChangedLine: Int?
)

data class AgentWorkspacePatchResult(
    val path: String,
    val replacements: Int,
    val diff: AgentWorkspaceDiffSummary,
    val metadata: AgentWorkspaceFileMetadata
)

data class AgentWorkspaceDigest(
    val path: String,
    val algorithm: String,
    val hex: String,
    val sizeBytes: Long
)

data class AgentWorkspaceZipEntryMetadata(
    val path: String,
    val directory: Boolean,
    val compressedBytes: Long,
    val uncompressedBytes: Long,
    val compressionRatio: Double,
    val crc32: Long,
    val lastModifiedMillis: Long
)

data class AgentWorkspaceZipListing(
    val archivePath: String,
    val archiveBytes: Long,
    val totalCompressedBytes: Long,
    val totalUncompressedBytes: Long,
    val entries: List<AgentWorkspaceZipEntryMetadata>
)

data class AgentWorkspaceZipExtraction(
    val archivePath: String,
    val destinationPath: String,
    val extractedEntries: Int,
    val extractedBytes: Long
)

/** App-private, workspace-scoped file operations with no shell execution surface. */
class AgentWorkspaceFileTools(
    storageRoot: Path,
    private val policy: AgentWorkspaceFilePolicy = AgentWorkspaceFilePolicy()
) {
    private val storageRoot: Path

    init {
        Files.createDirectories(storageRoot.toAbsolutePath().normalize())
        val canonical = storageRoot.toAbsolutePath().normalize().toRealPath()
        require(Files.isDirectory(canonical, NOFOLLOW_LINKS)) { "Workspace storage root is not a directory" }
        require(!Files.isSymbolicLink(canonical)) { "Workspace storage root cannot be a symbolic link" }
        this.storageRoot = canonical
    }

    fun initializeWorkspace(workspaceId: String): AgentWorkspaceFileResult<AgentWorkspaceMutation> =
        runOperation("initialize", workspaceId, workspaceId) {
            val relative = workspaceDirectoryName(workspaceId)
            val candidate = storageRoot.resolve(relative)
            val existed = Files.exists(candidate, NOFOLLOW_LINKS)
            val root = workspaceRoot(workspaceId)
            AgentWorkspaceMutation(
                kind = AgentWorkspaceMutationKind.INITIALIZE,
                path = "",
                affectedEntries = if (existed) 0 else 1,
                metadata = metadata(root, root)
            )
        }

    fun mkdir(
        workspaceId: String,
        path: String,
        recursive: Boolean = true
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> = runOperation("mkdir", workspaceId, path) {
        val root = workspaceRoot(workspaceId)
        val target = resolvePath(root, path, allowRoot = true)
        val existed = Files.exists(target, NOFOLLOW_LINKS)
        val created = if (recursive) {
            createDirectoriesSafely(root, target)
        } else {
            requireExistingParent(root, target)
            if (existed) {
                requireDirectory(target)
                0
            } else {
                Files.createDirectory(target)
                1
            }
        }
        AgentWorkspaceMutation(
            kind = AgentWorkspaceMutationKind.MKDIR,
            path = relativePath(root, target),
            affectedEntries = created,
            metadata = metadata(root, target)
        )
    }

    fun list(
        workspaceId: String,
        path: String = "",
        recursive: Boolean = false,
        maxEntries: Int = policy.maxListEntries
    ): AgentWorkspaceFileResult<AgentWorkspaceDirectoryListing> = runOperation("list", workspaceId, path) {
        val limit = requireLimit(maxEntries, policy.maxListEntries, "list entries")
        val root = workspaceRoot(workspaceId)
        val directory = resolvePath(root, path, allowRoot = true)
        requireDirectory(directory)
        val children = directoryChildren(directory)
        val paths = mutableListOf<Path>()
        for (child in children) {
            if (recursive) {
                scanTree(child, limit, paths)
            } else {
                validateEntry(child)
                paths.add(child)
            }
            if (paths.size > limit) limitExceeded("Directory listing exceeds $limit entries")
        }
        AgentWorkspaceDirectoryListing(
            path = relativePath(root, directory),
            recursive = recursive,
            entries = paths.map { metadata(root, it) }.sortedBy { it.path }
        )
    }

    fun stat(workspaceId: String, path: String): AgentWorkspaceFileResult<AgentWorkspaceFileMetadata> =
        runOperation("stat", workspaceId, path) {
            val root = workspaceRoot(workspaceId)
            metadata(root, resolvePath(root, path, allowRoot = true))
        }

    fun readText(
        workspaceId: String,
        path: String,
        maxBytes: Long = policy.maxTextReadBytes,
        startLine: Int = 1,
        maxLines: Int? = null
    ): AgentWorkspaceFileResult<AgentWorkspaceTextRead> = runOperation("read_text", workspaceId, path) {
        if (startLine < 1) invalidPath("Start line must be positive")
        if (maxLines != null && maxLines < 1) invalidPath("Maximum lines must be positive")
        val limit = requireLimit(maxBytes, policy.maxTextReadBytes, "text read bytes")
        val root = workspaceRoot(workspaceId)
        val file = resolvePath(root, path, allowRoot = false)
        val selection = readTextSelection(file, limit, startLine, maxLines)
        AgentWorkspaceTextRead(
            path = relativePath(root, file),
            text = selection.text,
            sizeBytes = selection.sizeBytes,
            sha256 = selection.sha256,
            returnedBytes = selection.returnedBytes,
            startLine = selection.startLine,
            endLine = selection.endLine,
            totalLines = selection.totalLines,
            truncatedBefore = selection.truncatedBefore,
            truncatedAfter = selection.truncatedAfter
        )
    }

    fun readBytes(
        workspaceId: String,
        path: String,
        maxBytes: Long = policy.maxBytesReadBytes
    ): AgentWorkspaceFileResult<AgentWorkspaceBytesRead> = runOperation("read_bytes", workspaceId, path) {
        val limit = requireLimit(maxBytes, policy.maxBytesReadBytes, "binary read bytes")
        val root = workspaceRoot(workspaceId)
        val file = resolvePath(root, path, allowRoot = false)
        val bytes = readFileBounded(file, limit)
        AgentWorkspaceBytesRead(
            path = relativePath(root, file),
            bytes = bytes,
            metadata = metadata(root, file),
            sha256 = sha256Hex(bytes)
        )
    }

    fun write(
        workspaceId: String,
        path: String,
        bytes: ByteArray,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> = mutateBytes(
        operation = "write",
        kind = AgentWorkspaceMutationKind.WRITE,
        workspaceId = workspaceId,
        path = path,
        bytes = bytes,
        createParents = createParents,
        requireMissing = false,
        appendExisting = false
    )

    fun create(
        workspaceId: String,
        path: String,
        bytes: ByteArray,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> = mutateBytes(
        operation = "create",
        kind = AgentWorkspaceMutationKind.CREATE,
        workspaceId = workspaceId,
        path = path,
        bytes = bytes,
        createParents = createParents,
        requireMissing = true,
        appendExisting = false
    )

    fun append(
        workspaceId: String,
        path: String,
        bytes: ByteArray
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> = mutateBytes(
        operation = "append",
        kind = AgentWorkspaceMutationKind.APPEND,
        workspaceId = workspaceId,
        path = path,
        bytes = bytes,
        createParents = false,
        requireMissing = false,
        appendExisting = true
    )

    fun writeText(
        workspaceId: String,
        path: String,
        text: String,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> =
        write(workspaceId, path, text.toByteArray(Charsets.UTF_8), createParents)

    fun createText(
        workspaceId: String,
        path: String,
        text: String,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> =
        create(workspaceId, path, text.toByteArray(Charsets.UTF_8), createParents)

    fun appendText(
        workspaceId: String,
        path: String,
        text: String
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> =
        append(workspaceId, path, text.toByteArray(Charsets.UTF_8))

    @Synchronized
    fun writeTextBatch(
        workspaceId: String,
        files: List<AgentWorkspaceTextFile>,
        overwrite: Boolean = true
    ): AgentWorkspaceFileResult<AgentWorkspaceBatchMutation> =
        runOperation("write_text_batch", workspaceId, "${files.size} files") {
            if (files.isEmpty() || files.size > MAX_BATCH_FILES) {
                limitExceeded("Batch must contain between 1 and $MAX_BATCH_FILES files")
            }
            if (files.map(AgentWorkspaceTextFile::path).distinct().size != files.size) {
                invalidPath("Batch contains duplicate file paths")
            }
            val encoded = files.map { item -> item to item.text.toByteArray(Charsets.UTF_8) }
            val totalBytes = encoded.sumOf { (_, bytes) -> bytes.size.toLong() }
            if (totalBytes > MAX_BATCH_WRITE_BYTES) {
                limitExceeded("Batch exceeds the $MAX_BATCH_WRITE_BYTES byte write limit")
            }

            val root = workspaceRoot(workspaceId)
            val prepared = encoded.map { (item, bytes) ->
                if (bytes.size.toLong() > policy.maxWriteBytes) {
                    limitExceeded("File ${item.path} exceeds the configured size limit")
                }
                val target = resolvePath(root, item.path, allowRoot = false)
                val existed = Files.exists(target, NOFOLLOW_LINKS)
                if (existed) {
                    requireFile(target)
                    if (!overwrite) alreadyExists("File already exists: ${item.path}")
                }
                BatchWrite(
                    target = target,
                    bytes = bytes,
                    previous = if (existed) readFileBounded(target, MAX_BATCH_ROLLBACK_BYTES) else null
                )
            }
            val rollbackBytes = prepared.sumOf { it.previous?.size?.toLong() ?: 0L }
            if (rollbackBytes > MAX_BATCH_ROLLBACK_BYTES) {
                limitExceeded("Existing files exceed the batch rollback limit")
            }

            val completed = mutableListOf<BatchWrite>()
            try {
                prepared.forEach { item ->
                    createDirectoriesSafely(root, item.target.parent)
                    atomicWrite(item.target, item.bytes, replace = item.previous != null)
                    completed += item
                }
            } catch (failure: Throwable) {
                completed.asReversed().forEach { item ->
                    runCatching {
                        if (item.previous == null) Files.deleteIfExists(item.target)
                        else atomicWrite(item.target, item.previous, replace = true)
                    }
                }
                throw failure
            }

            AgentWorkspaceBatchMutation(
                files = prepared.map { item ->
                    AgentWorkspaceMutation(
                        kind = AgentWorkspaceMutationKind.WRITE,
                        path = relativePath(root, item.target),
                        affectedBytes = item.bytes.size.toLong(),
                        metadata = metadata(root, item.target)
                    )
                },
                affectedBytes = totalBytes
            )
        }

    fun move(
        workspaceId: String,
        sourcePath: String,
        destinationPath: String,
        overwrite: Boolean = false,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> =
        runOperation("move", workspaceId, "$sourcePath -> $destinationPath") {
            val root = workspaceRoot(workspaceId)
            val source = resolvePath(root, sourcePath, allowRoot = false)
            val destination = resolvePath(root, destinationPath, allowRoot = false)
            val sourceEntries = scanTree(source, policy.maxTreeEntries)
            val sourceBytes = sourceEntries.sumOfRegularFileSizes()
            rejectNestedDestination(source, destination)
            prepareDestination(root, source, destination, overwrite, createParents)
            movePath(source, destination, overwrite)
            AgentWorkspaceMutation(
                kind = AgentWorkspaceMutationKind.MOVE,
                path = relativePath(root, destination),
                sourcePath = relativePath(root, source),
                affectedEntries = sourceEntries.size,
                affectedBytes = sourceBytes,
                metadata = metadata(root, destination)
            )
        }

    fun copy(
        workspaceId: String,
        sourcePath: String,
        destinationPath: String,
        overwrite: Boolean = false,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> =
        runOperation("copy", workspaceId, "$sourcePath -> $destinationPath") {
            val root = workspaceRoot(workspaceId)
            val source = resolvePath(root, sourcePath, allowRoot = false)
            val destination = resolvePath(root, destinationPath, allowRoot = false)
            val sourceEntries = scanTree(source, policy.maxTreeEntries)
            rejectNestedDestination(source, destination)
            prepareDestination(root, source, destination, overwrite, createParents)
            copyTree(source, destination, sourceEntries, overwrite)
            AgentWorkspaceMutation(
                kind = AgentWorkspaceMutationKind.COPY,
                path = relativePath(root, destination),
                sourcePath = relativePath(root, source),
                affectedEntries = sourceEntries.size,
                affectedBytes = sourceEntries.sumOfRegularFileSizes(),
                metadata = metadata(root, destination)
            )
        }

    fun delete(
        workspaceId: String,
        path: String,
        recursive: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> = runOperation("delete", workspaceId, path) {
        val root = workspaceRoot(workspaceId)
        val target = resolvePath(root, path, allowRoot = false)
        val entries = if (recursive) {
            scanTree(target, policy.maxTreeEntries)
        } else {
            listOf(validateEntry(target))
        }
        val bytes = entries.sumOfRegularFileSizes()
        if (recursive) {
            entries.sortedByDescending { it.nameCount }.forEach(Files::delete)
        } else {
            Files.delete(target)
        }
        AgentWorkspaceMutation(
            kind = AgentWorkspaceMutationKind.DELETE,
            path = relativePath(root, target),
            affectedEntries = entries.size,
            affectedBytes = bytes
        )
    }

    fun searchText(
        workspaceId: String,
        path: String,
        query: String,
        caseSensitive: Boolean = false,
        maxResults: Int = policy.maxSearchResults,
        includeGenerated: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceTextSearchResult> = runOperation("search_text", workspaceId, path) {
        if (query.isEmpty()) invalidPath("Search query cannot be empty")
        if (query.length > MAX_SEARCH_QUERY_CHARACTERS) limitExceeded("Search query is too long")
        val resultLimit = requireLimit(maxResults, policy.maxSearchResults, "search results")
        val root = workspaceRoot(workspaceId)
        val target = resolvePath(root, path, allowRoot = true)
        val candidateScan = if (Files.isDirectory(target, NOFOLLOW_LINKS)) {
            searchCandidates(target, policy.maxTreeEntries, includeGenerated)
        } else {
            requireFile(target)
            SearchCandidates(listOf(target), skippedFiles = 0, skippedDirectories = 0)
        }
        val matches = mutableListOf<AgentWorkspaceSearchMatch>()
        var scannedFiles = 0
        var skippedFiles = candidateScan.skippedFiles
        var scannedBytes = 0L
        var truncated = false
        candidateLoop@ for (file in candidateScan.files.sortedBy { relativePath(root, it) }) {
            val size = Files.size(file)
            if (size > policy.maxSearchFileBytes || safeAdd(scannedBytes, size) > policy.maxSearchTotalBytes) {
                skippedFiles++
                continue
            }
            val matchOffset = matches.size
            var invalidText = false
            var reachedResultLimit = false
            try {
                strictUtf8Reader(file).use { reader ->
                    var lineNumber = 0
                    while (true) {
                        val line = reader.readLine() ?: break
                        lineNumber++
                        if ('\u0000' in line) {
                            invalidText = true
                            break
                        }
                        if (reachedResultLimit) continue
                        var fromIndex = 0
                        while (fromIndex <= line.length - query.length) {
                            val index = line.indexOf(query, fromIndex, ignoreCase = !caseSensitive)
                            if (index < 0) break
                            matches += AgentWorkspaceSearchMatch(
                                path = relativePath(root, file),
                                line = lineNumber,
                                column = index + 1,
                                excerpt = excerpt(line, index, query.length)
                            )
                            if (matches.size >= resultLimit) {
                                reachedResultLimit = true
                                break
                            }
                            fromIndex = index + max(1, query.length)
                        }
                    }
                }
            } catch (_: CharacterCodingException) {
                invalidText = true
            }
            if (invalidText) {
                while (matches.size > matchOffset) matches.removeAt(matches.lastIndex)
                skippedFiles++
                continue
            }
            scannedFiles++
            scannedBytes = safeAdd(scannedBytes, size)
            truncated = reachedResultLimit
            if (truncated) break@candidateLoop
        }
        AgentWorkspaceTextSearchResult(
            query = query,
            matches = matches,
            scannedFiles = scannedFiles,
            skippedFiles = skippedFiles,
            skippedDirectories = candidateScan.skippedDirectories,
            scannedBytes = scannedBytes,
            truncated = truncated
        )
    }

    fun applyExactPatch(
        workspaceId: String,
        path: String,
        expectedText: String,
        replacementText: String,
        expectedOccurrences: Int = 1
    ): AgentWorkspaceFileResult<AgentWorkspacePatchResult> = runOperation("apply_exact_patch", workspaceId, path) {
        if (expectedText.isEmpty()) patchMismatch("Expected text cannot be empty")
        if (expectedOccurrences <= 0) patchMismatch("Expected occurrence count must be positive")
        val root = workspaceRoot(workspaceId)
        val file = resolvePath(root, path, allowRoot = false)
        val beforeBytes = readFileBounded(file, policy.maxPatchBytes)
        val before = decodeUtf8(beforeBytes)
        val occurrences = countOccurrences(before, expectedText)
        if (occurrences != expectedOccurrences) {
            patchMismatch("Expected $expectedOccurrences exact occurrence(s), found $occurrences")
        }
        val after = replaceOccurrences(before, expectedText, replacementText)
        val afterBytes = after.toByteArray(Charsets.UTF_8)
        if (afterBytes.size.toLong() > policy.maxPatchBytes || afterBytes.size.toLong() > policy.maxWriteBytes) {
            limitExceeded("Patched file exceeds the configured size limit")
        }
        val diff = summarizeDiff(before, after)
        atomicWrite(file, afterBytes, replace = true)
        AgentWorkspacePatchResult(
            path = relativePath(root, file),
            replacements = occurrences,
            diff = diff,
            metadata = metadata(root, file)
        )
    }

    fun diffSummary(
        workspaceId: String,
        path: String,
        proposedText: String
    ): AgentWorkspaceFileResult<AgentWorkspaceDiffSummary> = runOperation("diff_summary", workspaceId, path) {
        val proposedBytes = proposedText.toByteArray(Charsets.UTF_8)
        if (proposedBytes.size.toLong() > policy.maxPatchBytes) {
            limitExceeded("Proposed text exceeds the diff size limit")
        }
        val root = workspaceRoot(workspaceId)
        val file = resolvePath(root, path, allowRoot = false)
        val current = decodeUtf8(readFileBounded(file, policy.maxPatchBytes))
        summarizeDiff(current, proposedText)
    }

    fun sha256(
        workspaceId: String,
        path: String
    ): AgentWorkspaceFileResult<AgentWorkspaceDigest> = runOperation("sha256", workspaceId, path) {
        val root = workspaceRoot(workspaceId)
        val file = resolvePath(root, path, allowRoot = false)
        requireFile(file)
        val digest = MessageDigest.getInstance(SHA_256)
        var total = 0L
        Files.newInputStream(file, READ).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                total = safeAdd(total, read.toLong())
                if (total > policy.maxHashBytes) limitExceeded("File exceeds the hash size limit")
                digest.update(buffer, 0, read)
            }
        }
        AgentWorkspaceDigest(
            path = relativePath(root, file),
            algorithm = SHA_256,
            hex = digest.digest().toHex(),
            sizeBytes = total
        )
    }

    fun createZip(
        workspaceId: String,
        archivePath: String,
        sourcePaths: List<String>,
        overwrite: Boolean = false,
        createParents: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceZipListing> = runOperation("zip_create", workspaceId, archivePath) {
        if (sourcePaths.isEmpty()) invalidPath("At least one ZIP source path is required")
        val root = workspaceRoot(workspaceId)
        val archive = resolvePath(root, archivePath, allowRoot = false)
        if (createParents) createDirectoriesSafely(root, archive.parent) else requireExistingParent(root, archive)
        if (Files.exists(archive, NOFOLLOW_LINKS)) {
            requireFile(archive)
            if (!overwrite) alreadyExists("Archive already exists")
        }
        val sources = sourcePaths.map { resolvePath(root, it, allowRoot = false) }
        if (sources.any { archive == it || archive.startsWith(it) }) {
            invalidPath("Archive destination cannot be inside a selected source")
        }
        val sourceEntries = linkedMapOf<String, Path>()
        for (source in sources) {
            for (entry in scanTree(source, policy.maxZipEntries)) {
                val name = relativePath(root, entry)
                if (sourceEntries.putIfAbsent(name, entry) != null) {
                    invalidPath("ZIP sources overlap at $name")
                }
                if (sourceEntries.size > policy.maxZipEntries) {
                    limitExceeded("ZIP contains more than ${policy.maxZipEntries} entries")
                }
            }
        }
        var totalBytes = 0L
        sourceEntries.values.forEach { source ->
            if (Files.isRegularFile(source, NOFOLLOW_LINKS)) {
                val size = Files.size(source)
                if (size > policy.maxZipEntryBytes) limitExceeded("ZIP source entry exceeds the per-entry limit")
                totalBytes = safeAdd(totalBytes, size)
                if (totalBytes > policy.maxZipUncompressedBytes) {
                    limitExceeded("ZIP sources exceed the total uncompressed size limit")
                }
            }
        }
        val temp = Files.createTempFile(archive.parent, ".agent-zip-", ".tmp")
        try {
            ZipOutputStream(Files.newOutputStream(temp, WRITE)).use { zip ->
                for ((name, source) in sourceEntries.toSortedMap()) {
                    val attributes = readAttributes(source)
                    val entryName = if (attributes.isDirectory) "$name/" else name
                    if (entryName.length > policy.maxZipEntryNameCharacters) {
                        limitExceeded("ZIP entry name is too long")
                    }
                    val zipEntry = ZipEntry(entryName).apply {
                        lastModifiedTime = attributes.lastModifiedTime()
                    }
                    zip.putNextEntry(zipEntry)
                    if (attributes.isRegularFile) {
                        Files.newInputStream(source, READ).use { input -> input.copyTo(zip) }
                    }
                    zip.closeEntry()
                }
            }
            val inspected = inspectZip(temp, relativePath(root, archive))
            movePath(temp, archive, overwrite)
            inspected.copy(archiveBytes = Files.size(archive))
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    fun listZip(
        workspaceId: String,
        archivePath: String
    ): AgentWorkspaceFileResult<AgentWorkspaceZipListing> = runOperation("zip_list", workspaceId, archivePath) {
        val root = workspaceRoot(workspaceId)
        val archive = resolvePath(root, archivePath, allowRoot = false)
        requireFile(archive)
        inspectZip(archive, relativePath(root, archive))
    }

    fun extractZip(
        workspaceId: String,
        archivePath: String,
        destinationPath: String,
        overwrite: Boolean = false
    ): AgentWorkspaceFileResult<AgentWorkspaceZipExtraction> =
        runOperation("zip_extract", workspaceId, "$archivePath -> $destinationPath") {
            val root = workspaceRoot(workspaceId)
            val archive = resolvePath(root, archivePath, allowRoot = false)
            requireFile(archive)
            val listing = inspectZip(archive, relativePath(root, archive))
            val destination = resolvePath(root, destinationPath, allowRoot = true)
            preflightExtraction(root, archive, destination, listing.entries, overwrite)
            val staging = Files.createTempDirectory(root, ".agent-extract-")
            var extractedBytes = 0L
            try {
                ZipFile(archive.toFile()).use { zip ->
                    val entriesByName = listing.entries.associateBy { it.path }
                    val enumeration = zip.entries()
                    while (enumeration.hasMoreElements()) {
                        val zipEntry = enumeration.nextElement()
                        val normalizedName = normalizeArchiveEntry(zipEntry.name)
                        val inspected = entriesByName.getValue(normalizedName)
                        val output = staging.resolve(normalizedName).normalize()
                        if (!output.startsWith(staging)) invalidArchive("ZIP entry escapes the extraction directory")
                        if (inspected.directory) {
                            Files.createDirectories(output)
                            continue
                        }
                        Files.createDirectories(output.parent)
                        var entryBytes = 0L
                        zip.getInputStream(zipEntry).use { input ->
                            Files.newOutputStream(output, CREATE_NEW, WRITE).use { target ->
                                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read < 0) break
                                    entryBytes = safeAdd(entryBytes, read.toLong())
                                    extractedBytes = safeAdd(extractedBytes, read.toLong())
                                    if (entryBytes > policy.maxZipEntryBytes ||
                                        extractedBytes > policy.maxZipUncompressedBytes
                                    ) {
                                        limitExceeded("ZIP decompressed data exceeds the configured size limit")
                                    }
                                    if (compressionRatio(entryBytes, inspected.compressedBytes) >
                                        policy.maxZipCompressionRatio
                                    ) {
                                        limitExceeded("ZIP entry exceeds the compression ratio limit")
                                    }
                                    target.write(buffer, 0, read)
                                }
                            }
                        }
                        if (entryBytes != inspected.uncompressedBytes) {
                            invalidArchive("ZIP entry size changed during extraction")
                        }
                        if (inspected.lastModifiedMillis >= 0) {
                            Files.setLastModifiedTime(output, FileTime.fromMillis(inspected.lastModifiedMillis))
                        }
                    }
                }
                mergeExtractedTree(root, staging, destination, listing.entries, overwrite)
            } finally {
                deleteTreeUnchecked(staging)
            }
            AgentWorkspaceZipExtraction(
                archivePath = relativePath(root, archive),
                destinationPath = relativePath(root, destination),
                extractedEntries = listing.entries.size,
                extractedBytes = extractedBytes
            )
        }

    private fun mutateBytes(
        operation: String,
        kind: AgentWorkspaceMutationKind,
        workspaceId: String,
        path: String,
        bytes: ByteArray,
        createParents: Boolean,
        requireMissing: Boolean,
        appendExisting: Boolean
    ): AgentWorkspaceFileResult<AgentWorkspaceMutation> = runOperation(operation, workspaceId, path) {
        if (bytes.size.toLong() > policy.maxWriteBytes) limitExceeded("Write exceeds the configured size limit")
        val root = workspaceRoot(workspaceId)
        val file = resolvePath(root, path, allowRoot = false)
        if (createParents) createDirectoriesSafely(root, file.parent) else requireExistingParent(root, file)
        val exists = Files.exists(file, NOFOLLOW_LINKS)
        if (requireMissing && exists) alreadyExists("File already exists")
        if (exists) requireFile(file)
        if (appendExisting && !exists) notFound("Append target does not exist")
        val output = if (appendExisting) {
            val oldSize = Files.size(file)
            if (safeAdd(oldSize, bytes.size.toLong()) > policy.maxWriteBytes) {
                limitExceeded("Appended file exceeds the configured size limit")
            }
            val old = readFileBounded(file, policy.maxWriteBytes)
            ByteArrayOutputStream(old.size + bytes.size).apply {
                write(old)
                write(bytes)
            }.toByteArray()
        } else {
            bytes
        }
        atomicWrite(file, output, replace = !requireMissing)
        AgentWorkspaceMutation(
            kind = kind,
            path = relativePath(root, file),
            affectedBytes = bytes.size.toLong(),
            metadata = metadata(root, file)
        )
    }

    private fun workspaceRoot(workspaceId: String): Path {
        val directoryName = workspaceDirectoryName(workspaceId)
        val candidate = storageRoot.resolve(directoryName).normalize()
        if (!candidate.startsWith(storageRoot)) pathEscape("Workspace root escapes app-private storage")
        createDirectoriesSafely(storageRoot, candidate)
        checkNoSymbolicLinks(storageRoot, candidate)
        return candidate
    }

    private fun workspaceDirectoryName(workspaceId: String): String {
        if (!WORKSPACE_ID.matches(workspaceId)) {
            throw WorkspaceFailure(
                AgentWorkspaceFileErrorCode.INVALID_WORKSPACE,
                "Workspace ID must be 1-64 ASCII letters, digits, dots, underscores, or hyphens"
            )
        }
        return workspaceId
    }

    private fun resolvePath(root: Path, input: String, allowRoot: Boolean): Path {
        val normalized = normalizeRelativePath(input)
        val candidate = normalized.fold(root) { current, segment -> current.resolve(segment) }.normalize()
        if (!candidate.startsWith(root)) pathEscape("Path escapes its workspace")
        if (!allowRoot && candidate == root) invalidPath("Operation requires a non-root path")
        checkNoSymbolicLinks(root, candidate)
        return candidate
    }

    private fun normalizeRelativePath(input: String): List<String> {
        if ('\u0000' in input) invalidPath("Path contains a null character")
        val portable = input.replace('\\', '/')
        if (portable.startsWith('/') || portable.startsWith("//") || WINDOWS_ABSOLUTE.containsMatchIn(portable)) {
            pathEscape("Absolute paths are not allowed")
        }
        try {
            if (Paths.get(input).isAbsolute) pathEscape("Absolute paths are not allowed")
        } catch (_: InvalidPathException) {
            invalidPath("Path is invalid")
        }
        val segments = portable.split('/')
        if (segments.any { it == ".." }) pathEscape("Parent traversal is not allowed")
        return segments.filter { it.isNotEmpty() && it != "." }
    }

    private fun normalizeArchiveEntry(name: String): String {
        if (name.length > policy.maxZipEntryNameCharacters) invalidArchive("ZIP entry name is too long")
        if ('\u0000' in name) invalidArchive("ZIP entry contains a null character")
        val portable = name.trimEnd('/', '\\').replace('\\', '/')
        if (portable.startsWith('/') || portable.startsWith("//") || WINDOWS_ABSOLUTE.containsMatchIn(portable)) {
            invalidArchive("ZIP entry uses an absolute path")
        }
        val segments = portable.split('/')
        if (segments.any { it == ".." }) invalidArchive("ZIP entry contains parent traversal")
        val normalized = segments.filter { it.isNotEmpty() && it != "." }.joinToString("/")
        if (normalized.isEmpty()) invalidArchive("ZIP entry has an empty path")
        return normalized
    }

    private fun checkNoSymbolicLinks(root: Path, target: Path) {
        if (!target.startsWith(root)) pathEscape("Path escapes its workspace")
        var current = root
        if (Files.isSymbolicLink(current)) symlinkRejected("Symbolic links are not allowed")
        for (part in root.relativize(target)) {
            current = current.resolve(part)
            if (Files.exists(current, NOFOLLOW_LINKS) && Files.isSymbolicLink(current)) {
                symlinkRejected("Symbolic links are not allowed: ${relativePath(root, current)}")
            }
        }
    }

    private fun createDirectoriesSafely(root: Path, directory: Path): Int {
        if (!directory.startsWith(root)) pathEscape("Directory escapes its workspace")
        var current = root
        var created = 0
        for (part in root.relativize(directory)) {
            current = current.resolve(part)
            if (Files.exists(current, NOFOLLOW_LINKS)) {
                if (Files.isSymbolicLink(current)) symlinkRejected("Symbolic links are not allowed")
                requireDirectory(current)
            } else {
                try {
                    Files.createDirectory(current)
                    created++
                } catch (_: FileAlreadyExistsException) {
                    if (Files.isSymbolicLink(current)) symlinkRejected("Symbolic links are not allowed")
                    requireDirectory(current)
                }
            }
        }
        return created
    }

    private fun requireExistingParent(root: Path, target: Path) {
        val parent = target.parent ?: invalidPath("Path has no parent")
        checkNoSymbolicLinks(root, parent)
        requireDirectory(parent)
    }

    private fun requireFile(path: Path): Path {
        if (!Files.exists(path, NOFOLLOW_LINKS)) notFound("File does not exist")
        if (Files.isSymbolicLink(path)) symlinkRejected("Symbolic links are not allowed")
        if (!Files.isRegularFile(path, NOFOLLOW_LINKS)) notAFile("Path is not a regular file")
        return path
    }

    private fun requireDirectory(path: Path): Path {
        if (!Files.exists(path, NOFOLLOW_LINKS)) notFound("Directory does not exist")
        if (Files.isSymbolicLink(path)) symlinkRejected("Symbolic links are not allowed")
        if (!Files.isDirectory(path, NOFOLLOW_LINKS)) notADirectory("Path is not a directory")
        return path
    }

    private fun validateEntry(path: Path): Path {
        if (!Files.exists(path, NOFOLLOW_LINKS)) notFound("Path does not exist")
        if (Files.isSymbolicLink(path)) symlinkRejected("Symbolic links are not allowed")
        if (!Files.isRegularFile(path, NOFOLLOW_LINKS) && !Files.isDirectory(path, NOFOLLOW_LINKS)) {
            unsupportedType("Only regular files and directories are supported")
        }
        return path
    }

    private fun readAttributes(path: Path): BasicFileAttributes {
        validateEntry(path)
        return Files.readAttributes(path, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
    }

    private fun metadata(root: Path, path: Path): AgentWorkspaceFileMetadata {
        val attributes = readAttributes(path)
        return AgentWorkspaceFileMetadata(
            path = relativePath(root, path),
            type = if (attributes.isDirectory) AgentWorkspaceEntryType.DIRECTORY else AgentWorkspaceEntryType.FILE,
            sizeBytes = if (attributes.isRegularFile) attributes.size() else 0,
            lastModifiedMillis = attributes.lastModifiedTime().toMillis()
        )
    }

    private fun relativePath(root: Path, path: Path): String =
        root.relativize(path).joinToString("/") { it.toString() }

    private fun directoryChildren(directory: Path): List<Path> =
        Files.newDirectoryStream(directory).use { stream -> stream.toList().sortedBy { it.fileName.toString() } }

    private fun searchCandidates(
        start: Path,
        maxEntries: Int,
        includeGenerated: Boolean
    ): SearchCandidates {
        val files = mutableListOf<Path>()
        var visitedEntries = 0
        var skippedFiles = 0
        var skippedDirectories = 0
        Files.walkFileTree(start, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(directory: Path, attributes: BasicFileAttributes): FileVisitResult {
                visitedEntries++
                if (visitedEntries > maxEntries) limitExceeded("File tree exceeds the configured entry limit")
                if (directory != start && !includeGenerated && isGeneratedSearchDirectory(directory)) {
                    skippedDirectories++
                    return FileVisitResult.SKIP_SUBTREE
                }
                return FileVisitResult.CONTINUE
            }

            override fun visitFile(file: Path, attributes: BasicFileAttributes): FileVisitResult {
                visitedEntries++
                if (visitedEntries > maxEntries) limitExceeded("File tree exceeds the configured entry limit")
                if (attributes.isRegularFile && !attributes.isSymbolicLink) {
                    files.add(file)
                } else {
                    skippedFiles++
                }
                return FileVisitResult.CONTINUE
            }

            override fun visitFileFailed(file: Path, exception: IOException): FileVisitResult {
                skippedFiles++
                return FileVisitResult.CONTINUE
            }
        })
        return SearchCandidates(files, skippedFiles, skippedDirectories)
    }

    private fun isGeneratedSearchDirectory(directory: Path): Boolean =
        directory.fileName?.toString()?.lowercase(Locale.ROOT) in GENERATED_SEARCH_DIRECTORIES

    private fun scanTree(start: Path, maxEntries: Int): List<Path> {
        val paths = mutableListOf<Path>()
        scanTree(start, maxEntries, paths)
        return paths
    }

    private fun scanTree(start: Path, maxEntries: Int, output: MutableList<Path>) {
        if (maxEntries <= 0 || output.size >= maxEntries) {
            limitExceeded("File tree exceeds the configured entry limit")
        }
        validateEntry(start)
        output.add(start)
        if (Files.isDirectory(start, NOFOLLOW_LINKS)) {
            for (child in directoryChildren(start)) {
                scanTree(child, maxEntries, output)
            }
        }
    }

    private fun List<Path>.sumOfRegularFileSizes(): Long {
        var total = 0L
        for (path in this) {
            if (Files.isRegularFile(path, NOFOLLOW_LINKS)) total = safeAdd(total, Files.size(path))
        }
        return total
    }

    private fun readFileBounded(file: Path, maxBytes: Long): ByteArray {
        requireFile(file)
        if (Files.size(file) > maxBytes) limitExceeded("File exceeds the $maxBytes byte read limit")
        val output = ByteArrayOutputStream()
        Files.newInputStream(file, READ).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var total = 0L
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                total = safeAdd(total, read.toLong())
                if (total > maxBytes) limitExceeded("File exceeds the $maxBytes byte read limit")
                output.write(buffer, 0, read)
            }
        }
        return output.toByteArray()
    }

    private fun readTextSelection(
        file: Path,
        maxReturnedBytes: Long,
        requestedStartLine: Int,
        maxLines: Int?
    ): TextSelection {
        requireFile(file)
        val sizeBytes = Files.size(file)
        val rangedRead = requestedStartLine != 1 || maxLines != null
        if (!rangedRead && sizeBytes > maxReturnedBytes) {
            limitExceeded("File exceeds the $maxReturnedBytes byte read limit")
        }
        if (rangedRead && sizeBytes > policy.maxHashBytes) {
            limitExceeded("File exceeds the ${policy.maxHashBytes} byte text scan limit")
        }

        val requestedStartLineLong = requestedStartLine.toLong()
        val requestedEndLine = maxLines?.let { count ->
            requestedStartLineLong + count.toLong() - 1L
        } ?: Long.MAX_VALUE
        val selected = StringBuilder()
        val maxReturnedCharacters = maxReturnedBytes.toInt()
        var selectionExceeded = false
        var currentLine = 1L
        var sawCharacter = false
        var endedWithNewline = false
        val digest = MessageDigest.getInstance(SHA_256)
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)

        try {
            DigestInputStream(Files.newInputStream(file, READ), digest).use { input ->
                InputStreamReader(input, decoder).use { reader ->
                    val buffer = CharArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = reader.read(buffer)
                        if (read < 0) break
                        for (index in 0 until read) {
                            val character = buffer[index]
                            sawCharacter = true
                            endedWithNewline = character == '\n'
                            if (currentLine >= requestedStartLineLong && currentLine <= requestedEndLine) {
                                if (selected.length < maxReturnedCharacters) {
                                    selected.append(character)
                                } else {
                                    selectionExceeded = true
                                }
                            }
                            if (character == '\n') currentLine++
                        }
                    }
                }
            }
        } catch (_: CharacterCodingException) {
            throw WorkspaceFailure(AgentWorkspaceFileErrorCode.INVALID_TEXT, "File is not valid UTF-8 text")
        }

        val text = selected.toString()
        val returnedBytes = text.toByteArray(Charsets.UTF_8).size.toLong()
        if (selectionExceeded || returnedBytes > maxReturnedBytes) {
            limitExceeded("Selected text exceeds the $maxReturnedBytes byte read limit")
        }
        val totalLines = when {
            !sawCharacter -> 0
            endedWithNewline -> (currentLine - 1L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            else -> currentLine.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }
        val endLine = if (requestedStartLine > totalLines) {
            0
        } else {
            minOf(requestedEndLine, totalLines.toLong()).toInt()
        }
        return TextSelection(
            text = text,
            sizeBytes = sizeBytes,
            sha256 = digest.digest().toHex(),
            returnedBytes = returnedBytes,
            startLine = requestedStartLine,
            endLine = endLine,
            totalLines = totalLines,
            truncatedBefore = totalLines > 0 && requestedStartLine > 1,
            truncatedAfter = endLine in 1 until totalLines
        )
    }

    private data class TextSelection(
        val text: String,
        val sizeBytes: Long,
        val sha256: String,
        val returnedBytes: Long,
        val startLine: Int,
        val endLine: Int,
        val totalLines: Int,
        val truncatedBefore: Boolean,
        val truncatedAfter: Boolean
    )

    private fun strictUtf8Reader(file: Path) = InputStreamReader(
        Files.newInputStream(file, READ),
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
    ).buffered()

    private data class SearchCandidates(
        val files: List<Path>,
        val skippedFiles: Int,
        val skippedDirectories: Int
    )

    private fun decodeUtf8(bytes: ByteArray): String = try {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    } catch (_: CharacterCodingException) {
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.INVALID_TEXT, "File is not valid UTF-8 text")
    }

    private fun atomicWrite(file: Path, bytes: ByteArray, replace: Boolean) {
        val temp = Files.createTempFile(file.parent, ".agent-write-", ".tmp")
        try {
            Files.newOutputStream(temp, WRITE).use { it.write(bytes) }
            movePath(temp, file, replace)
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    private fun movePath(source: Path, destination: Path, replace: Boolean) {
        val options = if (replace) arrayOf(ATOMIC_MOVE, REPLACE_EXISTING) else arrayOf(ATOMIC_MOVE)
        try {
            Files.move(source, destination, *options)
        } catch (_: AtomicMoveNotSupportedException) {
            if (replace) Files.move(source, destination, REPLACE_EXISTING) else Files.move(source, destination)
        }
    }

    private fun rejectNestedDestination(source: Path, destination: Path) {
        if (source == destination) invalidPath("Source and destination must differ")
        if (Files.isDirectory(source, NOFOLLOW_LINKS) && destination.startsWith(source)) {
            invalidPath("Destination cannot be inside the source directory")
        }
    }

    private fun prepareDestination(
        root: Path,
        source: Path,
        destination: Path,
        overwrite: Boolean,
        createParents: Boolean
    ) {
        if (createParents) createDirectoriesSafely(root, destination.parent) else requireExistingParent(root, destination)
        if (!Files.exists(destination, NOFOLLOW_LINKS)) return
        validateEntry(destination)
        if (!overwrite) alreadyExists("Destination already exists")
        if (!Files.isRegularFile(source, NOFOLLOW_LINKS) || !Files.isRegularFile(destination, NOFOLLOW_LINKS)) {
            alreadyExists("Overwriting directories is not supported")
        }
    }

    private fun copyTree(source: Path, destination: Path, entries: List<Path>, overwrite: Boolean) {
        if (Files.isRegularFile(source, NOFOLLOW_LINKS)) {
            if (overwrite) Files.copy(source, destination, REPLACE_EXISTING, COPY_ATTRIBUTES)
            else Files.copy(source, destination, COPY_ATTRIBUTES)
            return
        }
        Files.createDirectory(destination)
        for (entry in entries.drop(1)) {
            val target = destination.resolve(source.relativize(entry).toString())
            if (Files.isDirectory(entry, NOFOLLOW_LINKS)) Files.createDirectory(target)
            else Files.copy(entry, target, COPY_ATTRIBUTES)
        }
    }

    private fun summarizeDiff(before: String, after: String): AgentWorkspaceDiffSummary {
        val beforeBytes = before.toByteArray(Charsets.UTF_8)
        val afterBytes = after.toByteArray(Charsets.UTF_8)
        val beforeLines = splitLines(before)
        val afterLines = splitLines(after)
        var prefix = 0
        while (prefix < beforeLines.size && prefix < afterLines.size && beforeLines[prefix] == afterLines[prefix]) {
            prefix++
        }
        var suffix = 0
        while (
            suffix < beforeLines.size - prefix &&
            suffix < afterLines.size - prefix &&
            beforeLines[beforeLines.lastIndex - suffix] == afterLines[afterLines.lastIndex - suffix]
        ) {
            suffix++
        }
        val removed = beforeLines.size - prefix - suffix
        val added = afterLines.size - prefix - suffix
        return AgentWorkspaceDiffSummary(
            beforeSha256 = sha256Hex(beforeBytes),
            afterSha256 = sha256Hex(afterBytes),
            beforeBytes = beforeBytes.size.toLong(),
            afterBytes = afterBytes.size.toLong(),
            beforeLines = beforeLines.size,
            afterLines = afterLines.size,
            addedLines = max(0, added - removed),
            deletedLines = max(0, removed - added),
            changedLinePairs = minOf(removed, added),
            firstChangedLine = if (removed == 0 && added == 0) null else prefix + 1
        )
    }

    private fun splitLines(text: String): List<String> = if (text.isEmpty()) emptyList() else text.split('\n')

    private fun countOccurrences(text: String, expected: String): Int {
        var count = 0
        var offset = 0
        while (offset <= text.length - expected.length) {
            val index = text.indexOf(expected, offset)
            if (index < 0) break
            count++
            offset = index + expected.length
        }
        return count
    }

    private fun replaceOccurrences(text: String, expected: String, replacement: String): String {
        val output = StringBuilder(text.length)
        var offset = 0
        while (true) {
            val index = text.indexOf(expected, offset)
            if (index < 0) break
            output.append(text, offset, index).append(replacement)
            offset = index + expected.length
        }
        return output.append(text, offset, text.length).toString()
    }

    private fun excerpt(line: String, matchIndex: Int, matchLength: Int): String {
        if (line.length <= MAX_SEARCH_EXCERPT_CHARACTERS) return line
        val radius = (MAX_SEARCH_EXCERPT_CHARACTERS - matchLength).coerceAtLeast(20) / 2
        val start = (matchIndex - radius).coerceAtLeast(0)
        val end = (matchIndex + matchLength + radius).coerceAtMost(line.length)
        return buildString {
            if (start > 0) append("...")
            append(line, start, end)
            if (end < line.length) append("...")
        }
    }

    private fun inspectZip(archive: Path, displayPath: String): AgentWorkspaceZipListing {
        requireFile(archive)
        val archiveBytes = Files.size(archive)
        if (archiveBytes > policy.maxZipArchiveBytes) limitExceeded("ZIP archive exceeds the compressed size limit")
        val entries = mutableListOf<AgentWorkspaceZipEntryMetadata>()
        val seen = mutableMapOf<String, Boolean>()
        var totalCompressed = 0L
        var totalUncompressed = 0L
        ZipFile(archive.toFile()).use { zip ->
            val enumeration = zip.entries()
            while (enumeration.hasMoreElements()) {
                val entry = enumeration.nextElement()
                if (entries.size >= policy.maxZipEntries) {
                    limitExceeded("ZIP contains more than ${policy.maxZipEntries} entries")
                }
                val name = normalizeArchiveEntry(entry.name)
                val previousDirectory = seen.putIfAbsent(name, entry.isDirectory)
                if (previousDirectory != null) invalidArchive("ZIP contains duplicate entry $name")
                val uncompressed = entry.size
                val compressed = entry.compressedSize
                if (uncompressed < 0 || compressed < 0) invalidArchive("ZIP entry sizes are missing")
                if (uncompressed > policy.maxZipEntryBytes) limitExceeded("ZIP entry exceeds the per-entry size limit")
                totalUncompressed = safeAdd(totalUncompressed, uncompressed)
                totalCompressed = safeAdd(totalCompressed, compressed)
                if (totalUncompressed > policy.maxZipUncompressedBytes) {
                    limitExceeded("ZIP exceeds the total uncompressed size limit")
                }
                val ratio = compressionRatio(uncompressed, compressed)
                if (ratio > policy.maxZipCompressionRatio) {
                    limitExceeded("ZIP entry exceeds the compression ratio limit")
                }
                entries += AgentWorkspaceZipEntryMetadata(
                    path = name,
                    directory = entry.isDirectory,
                    compressedBytes = compressed,
                    uncompressedBytes = uncompressed,
                    compressionRatio = ratio,
                    crc32 = entry.crc,
                    lastModifiedMillis = entry.lastModifiedTime?.toMillis() ?: -1
                )
            }
        }
        for ((name, _) in seen) {
            val parts = name.split('/')
            for (index in 1 until parts.size) {
                val parent = parts.take(index).joinToString("/")
                if (seen[parent] == false) invalidArchive("ZIP file entry is used as a directory: $parent")
            }
        }
        if (compressionRatio(totalUncompressed, totalCompressed) > policy.maxZipCompressionRatio) {
            limitExceeded("ZIP exceeds the total compression ratio limit")
        }
        return AgentWorkspaceZipListing(
            archivePath = displayPath,
            archiveBytes = archiveBytes,
            totalCompressedBytes = totalCompressed,
            totalUncompressedBytes = totalUncompressed,
            entries = entries.sortedBy { it.path }
        )
    }

    private fun preflightExtraction(
        root: Path,
        archive: Path,
        destination: Path,
        entries: List<AgentWorkspaceZipEntryMetadata>,
        overwrite: Boolean
    ) {
        checkNoSymbolicLinks(root, destination)
        if (Files.exists(destination, NOFOLLOW_LINKS)) requireDirectory(destination)
        else requireExistingParent(root, destination)
        for (entry in entries) {
            val target = destination.resolve(entry.path).normalize()
            if (!target.startsWith(destination) || !target.startsWith(root)) {
                pathEscape("ZIP entry escapes the extraction destination")
            }
            checkNoSymbolicLinks(root, target)
            var ancestor = target.parent
            while (ancestor != null && ancestor.startsWith(destination)) {
                if (Files.exists(ancestor, NOFOLLOW_LINKS) && !Files.isDirectory(ancestor, NOFOLLOW_LINKS)) {
                    alreadyExists("ZIP entry parent conflicts with a file")
                }
                if (ancestor == destination) break
                ancestor = ancestor.parent
            }
            if (target == archive) invalidArchive("ZIP cannot overwrite its own archive")
            if (!Files.exists(target, NOFOLLOW_LINKS)) continue
            validateEntry(target)
            if (entry.directory) {
                if (!Files.isDirectory(target, NOFOLLOW_LINKS)) alreadyExists("ZIP directory conflicts with a file")
            } else {
                if (!Files.isRegularFile(target, NOFOLLOW_LINKS) || !overwrite) {
                    alreadyExists("ZIP file destination already exists")
                }
            }
        }
    }

    private fun mergeExtractedTree(
        root: Path,
        staging: Path,
        destination: Path,
        entries: List<AgentWorkspaceZipEntryMetadata>,
        overwrite: Boolean
    ) {
        createDirectoriesSafely(root, destination)
        entries.filter { it.directory }.sortedBy { it.path.count { character -> character == '/' } }.forEach {
            createDirectoriesSafely(root, destination.resolve(it.path))
        }
        entries.filterNot { it.directory }.forEach { entry ->
            val source = staging.resolve(entry.path)
            val target = destination.resolve(entry.path)
            createDirectoriesSafely(root, target.parent)
            movePath(source, target, replace = overwrite)
            if (entry.lastModifiedMillis >= 0) {
                Files.setLastModifiedTime(target, FileTime.fromMillis(entry.lastModifiedMillis))
            }
        }
    }

    private fun deleteTreeUnchecked(path: Path) {
        if (!Files.exists(path, NOFOLLOW_LINKS)) return
        Files.walk(path).use { paths ->
            paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) }
        }
    }

    private fun compressionRatio(uncompressed: Long, compressed: Long): Double = when {
        uncompressed == 0L -> 0.0
        compressed <= 0L -> Double.POSITIVE_INFINITY
        else -> uncompressed.toDouble() / compressed.toDouble()
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance(SHA_256).digest(bytes).toHex()

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(Locale.US, it.toInt() and 0xff) }

    private fun safeAdd(left: Long, right: Long): Long {
        if (right > 0 && left > Long.MAX_VALUE - right) limitExceeded("Byte count overflow")
        return left + right
    }

    private fun requireLimit(requested: Long, configured: Long, label: String): Long {
        if (requested <= 0) invalidPath("$label must be positive")
        if (requested > configured) limitExceeded("$label exceeds the configured maximum of $configured")
        return requested
    }

    private fun requireLimit(requested: Int, configured: Int, label: String): Int {
        if (requested <= 0) invalidPath("$label must be positive")
        if (requested > configured) limitExceeded("$label exceeds the configured maximum of $configured")
        return requested
    }

    private fun <T> runOperation(
        operation: String,
        workspaceId: String,
        path: String,
        block: () -> T
    ): AgentWorkspaceFileResult<T> = try {
        AgentWorkspaceFileResult.Success(AgentWorkspaceScope.withLock(workspaceId, block))
    } catch (failure: WorkspaceFailure) {
        AgentWorkspaceFileResult.Failure(
            AgentWorkspaceFileError(failure.code, operation, path, failure.message.orEmpty())
        )
    } catch (failure: NoSuchFileException) {
        failureResult(AgentWorkspaceFileErrorCode.NOT_FOUND, operation, path, "Path does not exist")
    } catch (failure: FileAlreadyExistsException) {
        failureResult(AgentWorkspaceFileErrorCode.ALREADY_EXISTS, operation, path, "Path already exists")
    } catch (failure: DirectoryNotEmptyException) {
        failureResult(AgentWorkspaceFileErrorCode.DIRECTORY_NOT_EMPTY, operation, path, "Directory is not empty")
    } catch (failure: AccessDeniedException) {
        failureResult(AgentWorkspaceFileErrorCode.ACCESS_DENIED, operation, path, "Access denied")
    } catch (failure: ZipException) {
        failureResult(
            AgentWorkspaceFileErrorCode.INVALID_ARCHIVE,
            operation,
            path,
            failure.message?.take(MAX_ERROR_CHARACTERS) ?: "Invalid ZIP archive"
        )
    } catch (failure: InvalidPathException) {
        failureResult(AgentWorkspaceFileErrorCode.INVALID_PATH, operation, path, "Path is invalid")
    } catch (failure: SecurityException) {
        failureResult(AgentWorkspaceFileErrorCode.ACCESS_DENIED, operation, path, "Access denied")
    } catch (failure: IOException) {
        failureResult(
            AgentWorkspaceFileErrorCode.IO_ERROR,
            operation,
            path,
            failure.message?.take(MAX_ERROR_CHARACTERS) ?: "File operation failed"
        )
    }

    private fun <T> failureResult(
        code: AgentWorkspaceFileErrorCode,
        operation: String,
        path: String,
        message: String
    ): AgentWorkspaceFileResult<T> = AgentWorkspaceFileResult.Failure(
        AgentWorkspaceFileError(code, operation, path, message)
    )

    private fun invalidPath(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.INVALID_PATH, message)

    private fun pathEscape(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.PATH_ESCAPE, message)

    private fun symlinkRejected(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.SYMLINK_REJECTED, message)

    private fun notFound(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.NOT_FOUND, message)

    private fun alreadyExists(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.ALREADY_EXISTS, message)

    private fun notAFile(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.NOT_A_FILE, message)

    private fun notADirectory(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.NOT_A_DIRECTORY, message)

    private fun unsupportedType(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.UNSUPPORTED_FILE_TYPE, message)

    private fun limitExceeded(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED, message)

    private fun patchMismatch(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.PATCH_MISMATCH, message)

    private fun invalidArchive(message: String): Nothing =
        throw WorkspaceFailure(AgentWorkspaceFileErrorCode.INVALID_ARCHIVE, message)

    private class WorkspaceFailure(
        val code: AgentWorkspaceFileErrorCode,
        message: String
    ) : RuntimeException(message)

    private data class BatchWrite(
        val target: Path,
        val bytes: ByteArray,
        val previous: ByteArray?
    )

    companion object {
        private val WORKSPACE_ID = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
        private val WINDOWS_ABSOLUTE = Regex("^[A-Za-z]:")
        private const val SHA_256 = "SHA-256"
        private const val MAX_SEARCH_QUERY_CHARACTERS = 4_096
        private const val MAX_SEARCH_EXCERPT_CHARACTERS = 500
        private val GENERATED_SEARCH_DIRECTORIES = setOf(
            ".cxx",
            ".git",
            ".gradle",
            ".idea",
            "build",
            "coverage",
            "dist",
            "generated",
            "node_modules",
            "out",
            "target"
        )
        private const val MAX_ERROR_CHARACTERS = 300
        private const val MAX_BATCH_FILES = 64
        private const val MAX_BATCH_WRITE_BYTES = 1024L * 1024L
        private const val MAX_BATCH_ROLLBACK_BYTES = 16L * 1024L * 1024L
    }
}
