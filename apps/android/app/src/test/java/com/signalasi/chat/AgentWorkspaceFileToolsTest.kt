package com.signalasi.chat

import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.Comparator
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Before
import org.junit.Test

class AgentWorkspaceFileToolsTest {
    private lateinit var storageRoot: Path
    private lateinit var tools: AgentWorkspaceFileTools

    @Before
    fun setUp() {
        storageRoot = Files.createTempDirectory("agent-workspace-tools-")
        tools = AgentWorkspaceFileTools(storageRoot)
    }

    @After
    fun tearDown() {
        if (!::storageRoot.isInitialized || !Files.exists(storageRoot)) return
        Files.walk(storageRoot).use { paths ->
            paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) }
        }
    }

    @Test
    fun performsScopedFileOperationsAndReturnsMetadata() {
        tools.initializeWorkspace("alpha").success()
        val mkdir = tools.mkdir("alpha", "docs/nested").success()
        assertEquals(2, mkdir.affectedEntries)

        tools.createText("alpha", "docs/nested/note.txt", "hello").success()
        assertEquals(
            AgentWorkspaceFileErrorCode.ALREADY_EXISTS,
            tools.createText("alpha", "docs/nested/note.txt", "again").failureCode()
        )
        tools.appendText("alpha", "docs/nested/note.txt", " world").success()
        assertEquals("hello world", tools.readText("alpha", "docs/nested/note.txt").success().text)

        val bytes = tools.readBytes("alpha", "docs/nested/note.txt").success()
        assertArrayEquals("hello world".toByteArray(), bytes.bytes)
        assertEquals(AgentWorkspaceEntryType.FILE, bytes.metadata.type)
        assertEquals(11, bytes.metadata.sizeBytes)
        assertEquals(sha256("hello world".toByteArray()), bytes.sha256)

        tools.writeText("alpha", "docs/nested/note.txt", "rewritten").success()
        val stat = tools.stat("alpha", "docs/nested/note.txt").success()
        assertEquals("docs/nested/note.txt", stat.path)
        assertEquals(9, stat.sizeBytes)

        val listing = tools.list("alpha", "docs", recursive = true).success()
        assertEquals(listOf("docs/nested", "docs/nested/note.txt"), listing.entries.map { it.path })
        assertFalse(listing.truncated)
        assertEquals("", listing.nextCursor)
        assertEquals(
            AgentWorkspaceFileErrorCode.NOT_FOUND,
            tools.stat("beta", "docs/nested/note.txt").failureCode()
        )
    }

    @Test
    fun batchWriteRollsBackCompletedFilesWhenALaterPathFails() {
        tools.createText("batch", "existing.txt", "before", createParents = true).success()
        tools.createText("batch", "blocked", "not a directory").success()

        val result = tools.writeTextBatch(
            workspaceId = "batch",
            files = listOf(
                AgentWorkspaceTextFile("existing.txt", "after"),
                AgentWorkspaceTextFile("created.txt", "temporary"),
                AgentWorkspaceTextFile("blocked/nested.txt", "must fail")
            )
        )

        assertEquals(AgentWorkspaceFileErrorCode.NOT_A_DIRECTORY, result.failureCode())
        assertEquals("before", tools.readText("batch", "existing.txt").success().text)
        assertEquals(AgentWorkspaceFileErrorCode.NOT_FOUND, tools.stat("batch", "created.txt").failureCode())
        assertEquals("not a directory", tools.readText("batch", "blocked").success().text)
    }

    @Test
    fun copiesMovesSearchesAndDeletesTrees() {
        tools.createText("work", "docs/one.txt", "Needle one\nsecond needle", createParents = true).success()
        tools.createText("work", "docs/two.txt", "nothing here").success()
        tools.create("work", "docs/binary.bin", byteArrayOf(0xc3.toByte(), 0x28)).success()

        val search = tools.searchText("work", "docs", "needle", maxResults = 1).success()
        assertEquals(1, search.matches.size)
        assertEquals("docs/one.txt", search.matches.single().path)
        assertEquals(1, search.matches.single().line)
        assertTrue(search.truncated)

        val copied = tools.copy("work", "docs", "backup").success()
        assertEquals(4, copied.affectedEntries)
        assertEquals("Needle one\nsecond needle", tools.readText("work", "backup/one.txt").success().text)

        val moved = tools.move("work", "backup/one.txt", "backup/moved.txt").success()
        assertEquals("Needle one\nsecond needle".toByteArray().size.toLong(), moved.affectedBytes)
        assertEquals(AgentWorkspaceFileErrorCode.NOT_FOUND, tools.stat("work", "backup/one.txt").failureCode())
        assertEquals(
            AgentWorkspaceFileErrorCode.DIRECTORY_NOT_EMPTY,
            tools.delete("work", "backup").failureCode()
        )
        val deleted = tools.delete("work", "backup", recursive = true).success()
        assertEquals(4, deleted.affectedEntries)
        assertEquals(AgentWorkspaceFileErrorCode.NOT_FOUND, tools.stat("work", "backup").failureCode())
    }

    @Test
    fun searchStreamsSourceAndPrunesGeneratedDirectoriesByDefault() {
        tools.createText("search", "src/main.kt", "first\nNeedle source\nlast", createParents = true).success()
        tools.createText("search", ".git/internal.txt", "Needle git", createParents = true).success()
        tools.createText("search", "build/generated.txt", "Needle build", createParents = true).success()
        tools.createText("search", "node_modules/package/index.js", "Needle dependency", createParents = true).success()

        val sourceOnly = tools.searchText("search", ".", "needle").success()
        assertEquals(listOf("src/main.kt"), sourceOnly.matches.map { it.path })
        assertEquals(3, sourceOnly.skippedDirectories)
        assertEquals("Needle source", sourceOnly.matches.single().excerpt)

        val everything = tools.searchText(
            workspaceId = "search",
            path = ".",
            query = "needle",
            includeGenerated = true
        ).success()
        assertEquals(
            listOf(
                ".git/internal.txt",
                "build/generated.txt",
                "node_modules/package/index.js",
                "src/main.kt"
            ),
            everything.matches.map { it.path }
        )
        assertEquals(0, everything.skippedDirectories)

        val explicitGeneratedPath = tools.searchText("search", ".git", "needle").success()
        assertEquals(listOf(".git/internal.txt"), explicitGeneratedPath.matches.map { it.path })
    }

    @Test
    fun searchSkipsInvalidUtf8WithoutKeepingEarlierMatches() {
        tools.create(
            "search-invalid",
            "src/bad.txt",
            "needle\n".toByteArray() + byteArrayOf(0xc3.toByte(), 0x28),
            createParents = true
        ).success()
        tools.createText("search-invalid", "src/good.txt", "needle good").success()

        val result = tools.searchText("search-invalid", "src", "needle", maxResults = 1).success()

        assertEquals(listOf("src/good.txt"), result.matches.map { it.path })
        assertEquals(1, result.scannedFiles)
        assertEquals(1, result.skippedFiles)
        assertTrue(result.truncated)
    }

    @Test
    fun generatedDirectoryPruningPreservesTheSourceTreeBudget() {
        repeat(12) { index ->
            tools.createText(
                "search-budget",
                "node_modules/package-$index/index.js",
                "dependency needle",
                createParents = true
            ).success()
        }
        tools.createText("search-budget", "src/main.kt", "source needle", createParents = true).success()
        val budgetedTools = AgentWorkspaceFileTools(
            storageRoot,
            AgentWorkspaceFilePolicy(maxTreeEntries = 4)
        )

        val source = budgetedTools.searchText("search-budget", ".", "needle").success()
        assertEquals(listOf("src/main.kt"), source.matches.map { it.path })
        assertEquals(1, source.skippedDirectories)
        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            budgetedTools.searchText("search-budget", ".", "needle", includeGenerated = true).failureCode()
        )
    }

    @Test
    fun rejectsAbsoluteTraversalAndInvalidWorkspacePaths() {
        val attempts = listOf(
            tools.writeText("alpha", "../escape.txt", "bad"),
            tools.writeText("alpha", "docs/../escape.txt", "bad", createParents = true),
            tools.writeText("alpha", "..\\escape.txt", "bad"),
            tools.writeText("alpha", "/absolute.txt", "bad"),
            tools.writeText("alpha", "C:\\absolute.txt", "bad")
        )
        attempts.forEach { assertEquals(AgentWorkspaceFileErrorCode.PATH_ESCAPE, it.failureCode()) }
        assertEquals(
            AgentWorkspaceFileErrorCode.INVALID_WORKSPACE,
            tools.initializeWorkspace("../alpha").failureCode()
        )
        assertFalse(Files.exists(storageRoot.resolve("escape.txt")))
    }

    @Test
    fun readsExactTextLineRangesWithoutChangingWholeFileIdentity() {
        val content = "first\r\nsecond\nthird\nfourth\n"
        tools.createText("range", "src/sample.txt", content, createParents = true).success()

        val full = tools.readText("range", "src/sample.txt").success()
        val ranged = tools.readText(
            workspaceId = "range",
            path = "src/sample.txt",
            startLine = 2,
            maxLines = 2
        ).success()

        assertEquals("second\nthird\n", ranged.text)
        assertEquals(2, ranged.startLine)
        assertEquals(3, ranged.endLine)
        assertEquals(4, ranged.totalLines)
        assertTrue(ranged.truncatedBefore)
        assertTrue(ranged.truncatedAfter)
        assertEquals(ranged.text.toByteArray(Charsets.UTF_8).size.toLong(), ranged.returnedBytes)
        assertEquals(full.sizeBytes, ranged.sizeBytes)
        assertEquals(full.sha256, ranged.sha256)

        val beyondEnd = tools.readText(
            workspaceId = "range",
            path = "src/sample.txt",
            startLine = 8,
            maxLines = 2
        ).success()
        assertEquals("", beyondEnd.text)
        assertEquals(0, beyondEnd.endLine)
        assertEquals(4, beyondEnd.totalLines)
        assertTrue(beyondEnd.truncatedBefore)
        assertFalse(beyondEnd.truncatedAfter)
        assertEquals(
            AgentWorkspaceFileErrorCode.INVALID_PATH,
            tools.readText("range", "src/sample.txt", startLine = 0).failureCode()
        )
    }

    @Test
    fun readsRelatedTextRangesAsOneBoundedBatch() {
        tools.createText("batch-read", "src/one.kt", "one-a\none-b\none-c\n", createParents = true).success()
        tools.createText("batch-read", "src/two.kt", "two-a\ntwo-b\n").success()

        val result = tools.readTextBatch(
            workspaceId = "batch-read",
            requests = listOf(
                AgentWorkspaceTextReadRequest("src/one.kt", startLine = 2, maxLines = 1),
                AgentWorkspaceTextReadRequest("src/two.kt")
            )
        ).success()

        assertEquals(listOf("src/one.kt", "src/two.kt"), result.files.map { it.path })
        assertEquals("one-b\n", result.files[0].text)
        assertEquals("two-a\ntwo-b\n", result.files[1].text)
        assertEquals(result.files.sumOf { it.returnedBytes }, result.returnedBytes)
        assertEquals(result.files.sumOf { it.sizeBytes }, result.scannedBytes)
        assertEquals(2, result.changedFiles)
        assertEquals(0, result.unchangedFiles)
        assertTrue(result.files.none(AgentWorkspaceTextRead::unchanged))
    }

    @Test
    fun omitsUnchangedTextAndReturnsOnlyChangedFilesOnConditionalBatchRead() {
        tools.createText("conditional-read", "src/one.kt", "one-a\none-b\n", createParents = true).success()
        tools.createText("conditional-read", "src/two.kt", "two-a\ntwo-b\n").success()
        val initial = tools.readTextBatch(
            workspaceId = "conditional-read",
            requests = listOf(
                AgentWorkspaceTextReadRequest("src/one.kt", startLine = 2, maxLines = 1),
                AgentWorkspaceTextReadRequest("src/two.kt")
            )
        ).success()

        val unchanged = tools.readTextBatch(
            workspaceId = "conditional-read",
            requests = listOf(
                AgentWorkspaceTextReadRequest(
                    "src/one.kt",
                    startLine = 2,
                    maxLines = 1,
                    knownSha256 = initial.files[0].sha256
                ),
                AgentWorkspaceTextReadRequest("src/two.kt", knownSha256 = initial.files[1].sha256)
            )
        ).success()

        assertEquals(0, unchanged.changedFiles)
        assertEquals(2, unchanged.unchangedFiles)
        assertEquals(0L, unchanged.returnedBytes)
        assertTrue(unchanged.files.all(AgentWorkspaceTextRead::unchanged))
        assertTrue(unchanged.files.all { it.text.isEmpty() })
        assertEquals(2, unchanged.files[0].startLine)
        assertEquals(2, unchanged.files[0].endLine)
        assertEquals(2, unchanged.files[0].totalLines)

        tools.writeText("conditional-read", "src/two.kt", "two-a\ntwo-updated\n").success()
        val partial = tools.readTextBatch(
            workspaceId = "conditional-read",
            requests = listOf(
                AgentWorkspaceTextReadRequest("src/one.kt", knownSha256 = initial.files[0].sha256),
                AgentWorkspaceTextReadRequest("src/two.kt", knownSha256 = initial.files[1].sha256)
            )
        ).success()

        assertEquals(1, partial.changedFiles)
        assertEquals(1, partial.unchangedFiles)
        assertTrue(partial.files[0].unchanged)
        assertEquals("", partial.files[0].text)
        assertFalse(partial.files[1].unchanged)
        assertEquals("two-a\ntwo-updated\n", partial.files[1].text)
        assertFalse(partial.files[1].sha256 == initial.files[1].sha256)
    }

    @Test
    fun rejectsMalformedConditionalBatchHashes() {
        tools.createText("conditional-hash", "source.txt", "content", createParents = true).success()

        val result = tools.readTextBatch(
            workspaceId = "conditional-hash",
            requests = listOf(AgentWorkspaceTextReadRequest("source.txt", knownSha256 = "invalid"))
        )

        assertEquals(AgentWorkspaceFileErrorCode.INVALID_PATH, result.failureCode())
    }

    @Test
    fun rejectsTextReadBatchesWhoseRequestedOutputExceedsTheAggregateLimit() {
        val result = tools.readTextBatch(
            workspaceId = "batch-read-limit",
            requests = listOf(
                AgentWorkspaceTextReadRequest("one.kt", maxBytes = 200L * 1024L),
                AgentWorkspaceTextReadRequest("two.kt", maxBytes = 200L * 1024L),
                AgentWorkspaceTextReadRequest("three.kt", maxBytes = 200L * 1024L)
            )
        )

        assertEquals(AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED, result.failureCode())
    }

    @Test
    fun rejectsDuplicateTextRangesInOneBatch() {
        tools.createText("batch-read-duplicate", "same.txt", "same", createParents = true).success()

        val result = tools.readTextBatch(
            workspaceId = "batch-read-duplicate",
            requests = listOf(
                AgentWorkspaceTextReadRequest("same.txt"),
                AgentWorkspaceTextReadRequest("same.txt")
            )
        )

        assertEquals(AgentWorkspaceFileErrorCode.INVALID_PATH, result.failureCode())
    }

    @Test
    fun streamsARequestedRangeFromAFileLargerThanTheReturnLimit() {
        val limited = AgentWorkspaceFileTools(
            storageRoot,
            AgentWorkspaceFilePolicy(maxTextReadBytes = 24)
        )
        limited.initializeWorkspace("large-range").success()
        val content = (1..80).joinToString(separator = "\n", postfix = "\n") { line -> "line-$line" }
        Files.write(storageRoot.resolve("large-range/src.txt"), content.toByteArray())

        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            limited.readText("large-range", "src.txt").failureCode()
        )
        val ranged = limited.readText(
            workspaceId = "large-range",
            path = "src.txt",
            startLine = 77,
            maxLines = 2
        ).success()

        assertEquals("line-77\nline-78\n", ranged.text)
        assertEquals(content.toByteArray().size.toLong(), ranged.sizeBytes)
        assertEquals(sha256(content.toByteArray()), ranged.sha256)
        assertEquals(77, ranged.startLine)
        assertEquals(78, ranged.endLine)
        assertEquals(80, ranged.totalLines)
        assertTrue(ranged.truncatedBefore)
        assertTrue(ranged.truncatedAfter)
    }

    @Test
    fun validatesTheWholeUtf8StreamDuringARangedRead() {
        val limited = AgentWorkspaceFileTools(
            storageRoot,
            AgentWorkspaceFilePolicy(maxTextReadBytes = 16)
        )
        limited.initializeWorkspace("invalid-range").success()
        Files.write(
            storageRoot.resolve("invalid-range/src.txt"),
            "first\nsecond\n".toByteArray() + byteArrayOf(0xc3.toByte(), 0x28)
        )

        assertEquals(
            AgentWorkspaceFileErrorCode.INVALID_TEXT,
            limited.readText(
                workspaceId = "invalid-range",
                path = "src.txt",
                startLine = 1,
                maxLines = 1
            ).failureCode()
        )
    }

    @Test
    fun rejectsSymbolicLinksEvenWhenTheirTargetIsInsidePrivateStorage() {
        tools.initializeWorkspace("alpha").success()
        val target = storageRoot.resolve("other-workspace").also { Files.createDirectories(it) }
        Files.write(target.resolve("secret.txt"), "secret".toByteArray())
        val link = storageRoot.resolve("alpha/link")
        try {
            Files.createSymbolicLink(link, target)
        } catch (error: UnsupportedOperationException) {
            Assume.assumeNoException(error)
        } catch (error: SecurityException) {
            Assume.assumeNoException(error)
        } catch (error: IOException) {
            Assume.assumeNoException(error)
        }

        assertEquals(AgentWorkspaceFileErrorCode.SYMLINK_REJECTED, tools.stat("alpha", "link").failureCode())
        assertEquals(
            AgentWorkspaceFileErrorCode.SYMLINK_REJECTED,
            tools.readText("alpha", "link/secret.txt").failureCode()
        )
    }

    @Test
    fun enforcesReadWriteListAndUtf8Bounds() {
        val limited = AgentWorkspaceFileTools(
            storageRoot,
            AgentWorkspaceFilePolicy(
                maxTextReadBytes = 4,
                maxBytesReadBytes = 4,
                maxWriteBytes = 5,
                maxListEntries = 2
            )
        )
        limited.initializeWorkspace("limits").success()
        val root = storageRoot.resolve("limits")
        Files.write(root.resolve("large.txt"), "12345".toByteArray())
        Files.write(root.resolve("invalid.txt"), byteArrayOf(0xc3.toByte(), 0x28))
        Files.write(root.resolve("third.txt"), byteArrayOf(1))

        assertEquals(AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED, limited.readText("limits", "large.txt").failureCode())
        assertEquals(AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED, limited.readBytes("limits", "large.txt").failureCode())
        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            limited.write("limits", "too-large.bin", ByteArray(6)).failureCode()
        )
        assertEquals(AgentWorkspaceFileErrorCode.INVALID_TEXT, limited.readText("limits", "invalid.txt").failureCode())
        val firstPage = limited.list("limits").success()
        assertEquals(listOf("invalid.txt", "large.txt"), firstPage.entries.map { it.path })
        assertTrue(firstPage.truncated)
        assertEquals("large.txt", firstPage.nextCursor)
        val secondPage = limited.list("limits", cursor = firstPage.nextCursor).success()
        assertEquals(listOf("third.txt"), secondPage.entries.map { it.path })
        assertFalse(secondPage.truncated)
    }

    @Test
    fun listsLargeProjectTreesInDeterministicSourceOnlyPages() {
        tools.createText("tree", "build/generated/output.kt", "generated", createParents = true).success()
        tools.createText("tree", "node_modules/package/index.js", "dependency", createParents = true).success()
        tools.createText("tree", "src/a.kt", "a", createParents = true).success()
        tools.createText("tree", "src/b.kt", "b").success()
        tools.createText("tree", "src/c.kt", "c").success()

        val firstPage = tools.list("tree", recursive = true, maxEntries = 2).success()
        assertEquals(listOf("src", "src/a.kt"), firstPage.entries.map { it.path })
        assertEquals(2, firstPage.skippedDirectories)
        assertTrue(firstPage.truncated)
        assertEquals("src/a.kt", firstPage.nextCursor)

        val secondPage = tools.list(
            workspaceId = "tree",
            recursive = true,
            maxEntries = 2,
            cursor = firstPage.nextCursor
        ).success()
        assertEquals(listOf("src/b.kt", "src/c.kt"), secondPage.entries.map { it.path })
        assertEquals(2, secondPage.skippedDirectories)
        assertFalse(secondPage.truncated)
        assertEquals("", secondPage.nextCursor)

        val generated = tools.list(
            workspaceId = "tree",
            recursive = true,
            includeGenerated = true
        ).success()
        assertTrue(generated.entries.any { it.path == "build/generated/output.kt" })
        assertTrue(generated.entries.any { it.path == "node_modules/package/index.js" })
        assertEquals(0, generated.skippedDirectories)
    }

    @Test
    fun rejectsDirectoryListingCursorOutsideSelectedPath() {
        tools.createText("tree-cursor", "docs/note.txt", "note", createParents = true).success()
        tools.createText("tree-cursor", "src/main.kt", "main", createParents = true).success()

        assertEquals(
            AgentWorkspaceFileErrorCode.INVALID_PATH,
            tools.list("tree-cursor", "src", recursive = true, cursor = "docs/note.txt").failureCode()
        )
    }

    @Test
    fun directoryListingCursorFollowsTraversalOrderWithoutDroppingSiblingFiles() {
        tools.createText("tree-order", "a/z.kt", "nested", createParents = true).success()
        tools.createText("tree-order", "a.txt", "sibling").success()

        val firstPage = tools.list("tree-order", recursive = true, maxEntries = 2).success()
        assertEquals(listOf("a", "a/z.kt"), firstPage.entries.map { it.path })
        assertTrue(firstPage.truncated)

        val secondPage = tools.list(
            workspaceId = "tree-order",
            recursive = true,
            maxEntries = 2,
            cursor = firstPage.nextCursor
        ).success()
        assertEquals(listOf("a.txt"), secondPage.entries.map { it.path })
        assertFalse(secondPage.truncated)
    }

    @Test
    fun appliesOnlyExactPatchesAndSummarizesDiffs() {
        tools.createText("patch", "note.txt", "one\ntwo\nthree\n", createParents = true).success()
        assertEquals(
            AgentWorkspaceFileErrorCode.PATCH_MISMATCH,
            tools.applyExactPatch("patch", "note.txt", "two", "TWO", expectedOccurrences = 2).failureCode()
        )
        assertEquals("one\ntwo\nthree\n", tools.readText("patch", "note.txt").success().text)

        val patch = tools.applyExactPatch("patch", "note.txt", "two", "TWO").success()
        assertEquals(1, patch.replacements)
        assertEquals(2, patch.diff.firstChangedLine)
        assertEquals(1, patch.diff.changedLinePairs)
        assertNotEquals(patch.diff.beforeSha256, patch.diff.afterSha256)

        val unchanged = tools.diffSummary("patch", "note.txt", "one\nTWO\nthree\n").success()
        assertNull(unchanged.firstChangedLine)
        assertEquals(0, unchanged.addedLines)
        assertEquals(0, unchanged.deletedLines)
        val digest = tools.sha256("patch", "note.txt").success()
        assertEquals(sha256("one\nTWO\nthree\n".toByteArray()), digest.hex)
        assertEquals("SHA-256", digest.algorithm)
    }

    @Test
    fun appliesMultipleExactPatchesAsOneAtomicMutation() {
        tools.createText("batch-patch", "src/one.kt", "val one = 1\n", createParents = true).success()
        tools.createText("batch-patch", "src/two.kt", "val two = 2\n").success()

        val result = tools.applyExactPatchBatch(
            workspaceId = "batch-patch",
            patches = listOf(
                AgentWorkspaceExactPatch("src/one.kt", "one = 1", "one = 10"),
                AgentWorkspaceExactPatch("src/two.kt", "two = 2", "two = 20")
            )
        ).success()

        assertEquals(listOf("src/one.kt", "src/two.kt"), result.patches.map { it.path })
        assertEquals(2, result.patches.sumOf { it.replacements })
        assertEquals("val one = 10\n", tools.readText("batch-patch", "src/one.kt").success().text)
        assertEquals("val two = 20\n", tools.readText("batch-patch", "src/two.kt").success().text)
        assertEquals(26, result.affectedBytes)
    }

    @Test
    fun rejectsWholeExactPatchBatchBeforeWritingWhenOnePatchDoesNotMatch() {
        tools.createText("batch-reject", "one.txt", "before one", createParents = true).success()
        tools.createText("batch-reject", "two.txt", "before two").success()

        val result = tools.applyExactPatchBatch(
            workspaceId = "batch-reject",
            patches = listOf(
                AgentWorkspaceExactPatch("one.txt", "before", "after"),
                AgentWorkspaceExactPatch("two.txt", "missing", "after")
            )
        )

        assertEquals(AgentWorkspaceFileErrorCode.PATCH_MISMATCH, result.failureCode())
        assertEquals("before one", tools.readText("batch-reject", "one.txt").success().text)
        assertEquals("before two", tools.readText("batch-reject", "two.txt").success().text)
    }

    @Test
    fun rejectsDuplicateExactPatchTargetsWithoutWriting() {
        tools.createText("batch-duplicate", "same.txt", "before", createParents = true).success()

        val result = tools.applyExactPatchBatch(
            workspaceId = "batch-duplicate",
            patches = listOf(
                AgentWorkspaceExactPatch("same.txt", "before", "first"),
                AgentWorkspaceExactPatch("same.txt", "before", "second")
            )
        )

        assertEquals(AgentWorkspaceFileErrorCode.INVALID_PATH, result.failureCode())
        assertEquals("before", tools.readText("batch-duplicate", "same.txt").success().text)
    }

    @Test
    fun createsListsAndExtractsZipArchives() {
        tools.createText("zip", "docs/a.txt", "alpha", createParents = true).success()
        tools.createText("zip", "docs/nested/b.txt", "beta", createParents = true).success()

        val created = tools.createZip("zip", "bundle.zip", listOf("docs")).success()
        assertTrue(created.archiveBytes > 0)
        assertEquals(
            listOf("docs", "docs/a.txt", "docs/nested", "docs/nested/b.txt"),
            created.entries.map { it.path }
        )
        val listed = tools.listZip("zip", "bundle.zip").success()
        assertEquals(9, listed.totalUncompressedBytes)

        val extracted = tools.extractZip("zip", "bundle.zip", "unpacked").success()
        assertEquals(4, extracted.extractedEntries)
        assertEquals(9, extracted.extractedBytes)
        assertEquals("alpha", tools.readText("zip", "unpacked/docs/a.txt").success().text)
        assertEquals("beta", tools.readText("zip", "unpacked/docs/nested/b.txt").success().text)
    }

    @Test
    fun rejectsZipSlipAndDoesNotWriteOutsideDestination() {
        tools.initializeWorkspace("zip-slip").success()
        val workspace = storageRoot.resolve("zip-slip")
        writeZip(workspace.resolve("bad.zip"), listOf("../escaped.txt" to "bad".toByteArray()))

        assertEquals(AgentWorkspaceFileErrorCode.INVALID_ARCHIVE, tools.listZip("zip-slip", "bad.zip").failureCode())
        assertEquals(
            AgentWorkspaceFileErrorCode.INVALID_ARCHIVE,
            tools.extractZip("zip-slip", "bad.zip", "out").failureCode()
        )
        assertFalse(Files.exists(workspace.resolve("escaped.txt")))
        assertFalse(Files.exists(storageRoot.resolve("escaped.txt")))
    }

    @Test
    fun rejectsZipEntryCountSizeAndCompressionRatioBombs() {
        tools.initializeWorkspace("zip-limits").success()
        val workspace = storageRoot.resolve("zip-limits")
        writeZip(
            workspace.resolve("entries.zip"),
            listOf("one" to byteArrayOf(), "two" to byteArrayOf(), "three" to byteArrayOf())
        )
        val entryLimited = AgentWorkspaceFileTools(storageRoot, AgentWorkspaceFilePolicy(maxZipEntries = 2))
        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            entryLimited.listZip("zip-limits", "entries.zip").failureCode()
        )

        writeZip(
            workspace.resolve("total.zip"),
            listOf("one" to ByteArray(5) { it.toByte() }, "two" to ByteArray(5) { (it + 5).toByte() })
        )
        val sizeLimited = AgentWorkspaceFileTools(
            storageRoot,
            AgentWorkspaceFilePolicy(
                maxZipEntryBytes = 8,
                maxZipUncompressedBytes = 8,
                maxZipCompressionRatio = 1_000.0
            )
        )
        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            sizeLimited.listZip("zip-limits", "total.zip").failureCode()
        )

        writeZip(workspace.resolve("ratio.zip"), listOf("zeros.bin" to ByteArray(4_096)))
        val ratioLimited = AgentWorkspaceFileTools(
            storageRoot,
            AgentWorkspaceFilePolicy(
                maxZipEntryBytes = 8_192,
                maxZipUncompressedBytes = 8_192,
                maxZipCompressionRatio = 2.0
            )
        )
        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            ratioLimited.listZip("zip-limits", "ratio.zip").failureCode()
        )
        assertEquals(
            AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED,
            ratioLimited.extractZip("zip-limits", "ratio.zip", "out").failureCode()
        )
    }

    private fun writeZip(path: Path, entries: List<Pair<String, ByteArray>>) {
        ZipOutputStream(Files.newOutputStream(path)).use { zip ->
            entries.forEach { (name, bytes) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(Locale.US, it.toInt() and 0xff) }

    private fun <T> AgentWorkspaceFileResult<T>.success(): T = when (this) {
        is AgentWorkspaceFileResult.Success -> value
        is AgentWorkspaceFileResult.Failure -> throw AssertionError("Expected success, got $error")
    }

    private fun AgentWorkspaceFileResult<*>.failureCode(): AgentWorkspaceFileErrorCode = when (this) {
        is AgentWorkspaceFileResult.Success -> throw AssertionError("Expected failure, got $value")
        is AgentWorkspaceFileResult.Failure -> error.code
    }
}
