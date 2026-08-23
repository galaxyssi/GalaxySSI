package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AgentRuntimeProjectVerificationPlannerTest {
    private lateinit var root: File

    @Before
    fun setUp() {
        root = Files.createTempDirectory("signalasi-project-verifier-").toFile()
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    @Test
    fun selectsTheProjectNativeNodeScriptAndPackageManager() {
        File(root, "package.json").writeText(
            """{"scripts":{"test":"vitest","check":"node check.js","build":"vite build"}}"""
        )
        File(root, "pnpm-lock.yaml").writeText("lockfileVersion: 9")

        val test = plan(AgentRuntimeVerificationKind.TEST)
        val lint = plan(AgentRuntimeVerificationKind.LINT)
        val build = plan(AgentRuntimeVerificationKind.BUILD)

        assertEquals("node", test.adapter)
        assertEquals("pnpm run test", test.command)
        assertEquals("pnpm run check", lint.command)
        assertEquals("pnpm run build", build.command)
        assertTrue(test.source.contains("SignalASI verification command: pnpm run test"))
    }

    @Test
    fun selectsStableGradleTasksWithoutRequiringAnExecutableWrapperBit() {
        File(root, "gradlew").writeText("#!/bin/sh")

        assertEquals("sh ./gradlew test", plan(AgentRuntimeVerificationKind.TEST).command)
        assertEquals("sh ./gradlew build", plan(AgentRuntimeVerificationKind.BUILD).command)
        assertEquals("sh ./gradlew check", plan(AgentRuntimeVerificationKind.LINT).command)
        assertEquals("sh ./gradlew assemble", plan(AgentRuntimeVerificationKind.PACKAGE).command)
    }

    @Test
    fun recognizesCommonLanguageAndBuildEcosystems() {
        val cases = listOf(
            Triple("python", "pyproject.toml", "python -m pytest"),
            Triple("rust", "Cargo.toml", "cargo test"),
            Triple("go", "go.mod", "go test ./..."),
            Triple("maven", "pom.xml", "mvn test"),
            Triple("cmake", "CMakeLists.txt", "ctest --test-dir"),
            Triple("swift", "Package.swift", "swift test"),
            Triple("make", "Makefile", "make test")
        )
        cases.forEachIndexed { index, (adapter, manifest, commandFragment) ->
            val directory = File(root, "project-$index").apply { mkdirs() }
            File(directory, manifest).writeText("manifest")
            val result = AgentRuntimeProjectVerificationPlanner.plan(
                projectRoot = root,
                requestedScope = directory.name,
                verificationKind = AgentRuntimeVerificationKind.TEST
            )

            assertEquals(adapter, result.adapter)
            assertTrue(result.command.contains(commandFragment))
        }
    }

    @Test
    fun discoversOneNestedProjectWhenTheWorkspaceRootHasNoRunnableManifest() {
        File(root, "package.json").writeText("""{"scripts":{}}""")
        val nested = File(root, "apps/android").apply { mkdirs() }
        File(nested, "settings.gradle.kts").writeText("rootProject.name = \"sample\"")

        val result = plan(AgentRuntimeVerificationKind.TEST)

        assertEquals("apps/android", result.scope)
        assertEquals("gradle", result.adapter)
        assertEquals("gradle test", result.command)
    }

    @Test
    fun requiresScopeWhenMoreThanOneRunnableProjectExists() {
        File(root, "services/api").apply {
            mkdirs()
            File(this, "go.mod").writeText("module example/api")
        }
        File(root, "services/worker").apply {
            mkdirs()
            File(this, "Cargo.toml").writeText("[package]")
        }

        val failure = runCatching { plan(AgentRuntimeVerificationKind.TEST) }.exceptionOrNull()

        assertTrue(failure?.message.orEmpty().contains("Multiple project roots"))
        assertTrue(failure?.message.orEmpty().contains("project_scope"))
    }

    @Test
    fun explicitScopeSelectsTheRequestedMonorepoProject() {
        File(root, "apps/web").apply {
            mkdirs()
            File(this, "package.json").writeText("""{"scripts":{"lint":"eslint ."}}""")
        }
        File(root, "apps/android").apply {
            mkdirs()
            File(this, "build.gradle.kts").writeText("plugins {}")
        }

        val result = AgentRuntimeProjectVerificationPlanner.plan(
            projectRoot = root,
            requestedScope = "apps/web",
            verificationKind = AgentRuntimeVerificationKind.LINT
        )

        assertEquals("apps/web", result.scope)
        assertEquals("npm run lint", result.command)
        assertTrue(result.source.contains("cd 'apps/web'"))
    }

    @Test
    fun explicitScopeExplainsWhenTheRequestedVerificationCommandIsUnavailable() {
        File(root, "apps/web").apply {
            mkdirs()
            File(this, "package.json").writeText("""{"scripts":{"build":"vite build"}}""")
        }

        val failure = runCatching {
            AgentRuntimeProjectVerificationPlanner.plan(
                projectRoot = root,
                requestedScope = "apps/web",
                verificationKind = AgentRuntimeVerificationKind.TEST
            )
        }.exceptionOrNull()

        assertTrue(failure?.message.orEmpty().contains("No project-native test command"))
        assertTrue(failure?.message.orEmpty().contains("apps/web"))
    }

    @Test
    fun rejectsAbsoluteTraversalAndMissingScopes() {
        listOf("../outside", "/root/project", "C:/project", "missing").forEach { scope ->
            val failure = runCatching {
                AgentRuntimeProjectVerificationPlanner.plan(
                    projectRoot = root,
                    requestedScope = scope,
                    verificationKind = AgentRuntimeVerificationKind.TEST
                )
            }

            assertTrue("Scope $scope must be rejected", failure.isFailure)
        }
    }

    @Test
    fun rejectsVerificationWithoutAProjectManifestOrVerificationKind() {
        assertTrue(runCatching { plan(AgentRuntimeVerificationKind.TEST) }.isFailure)
        assertTrue(runCatching { plan(AgentRuntimeVerificationKind.NONE) }.isFailure)
    }

    private fun plan(kind: AgentRuntimeVerificationKind): AgentRuntimeProjectVerificationPlan =
        AgentRuntimeProjectVerificationPlanner.plan(root, "", kind)
}
