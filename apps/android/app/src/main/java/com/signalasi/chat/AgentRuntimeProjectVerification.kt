package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import org.json.JSONObject

internal data class AgentRuntimeProjectVerificationPlan(
    val scope: String,
    val adapter: String,
    val command: String
) {
    val source: String = buildString {
        appendLine("set -eu")
        appendLine("cd ${shellQuote(scope)}")
        appendLine("printf '%s\\n' ${shellQuote("SignalASI verification adapter: $adapter")}")
        appendLine("printf '%s\\n' ${shellQuote("SignalASI verification command: $command")}")
        appendLine(command)
    }
}

internal object AgentRuntimeProjectVerificationPlanner {
    fun plan(
        projectRoot: File,
        requestedScope: String,
        verificationKind: AgentRuntimeVerificationKind
    ): AgentRuntimeProjectVerificationPlan {
        require(verificationKind != AgentRuntimeVerificationKind.NONE) {
            "Project verification kind is required"
        }
        val canonicalRoot = projectRoot.canonicalFile
        require(canonicalRoot.isDirectory) { "The phone project workspace is empty" }
        val explicitScope = requestedScope.trim().isNotEmpty()
        val requestedDirectory = resolveScope(canonicalRoot, requestedScope)
        val requestedAdapter = selectAdapter(requestedDirectory, verificationKind)
        val selection = when {
            requestedAdapter != null -> requestedDirectory to requestedAdapter
            explicitScope -> error(
                "No project-native ${verificationKind.wireValue} command is available in " +
                    displayScope(canonicalRoot, requestedDirectory)
            )
            else -> discoverSingleProject(canonicalRoot, verificationKind)
        }
        val projectDirectory = selection.first
        val adapter = selection.second
        val scope = displayScope(canonicalRoot, projectDirectory)
        return AgentRuntimeProjectVerificationPlan(
            scope = scope,
            adapter = adapter.first,
            command = adapter.second
        )
    }

    private fun resolveScope(projectRoot: File, requestedScope: String): File {
        val normalized = requestedScope.trim().replace('\\', '/').trim('/')
        if (normalized.isBlank() || normalized == ".") return projectRoot
        require(!DRIVE_PATH.matches(normalized) && !normalized.startsWith('/')) {
            "Project scope must be relative"
        }
        require(normalized.length <= MAX_SCOPE_CHARS) { "Project scope is too long" }
        require(normalized.split('/').all { it.isNotBlank() && it !in setOf(".", "..") }) {
            "Project scope is invalid"
        }
        val target = File(projectRoot, normalized).canonicalFile
        require(target.toPath().startsWith(projectRoot.toPath())) { "Project scope leaves the workspace" }
        require(target.isDirectory && !Files.isSymbolicLink(target.toPath())) {
            "Project scope is unavailable"
        }
        return target
    }

    private fun discoverSingleProject(
        projectRoot: File,
        verificationKind: AgentRuntimeVerificationKind
    ): Pair<File, Pair<String, String>> {
        val candidates = projectRoot.walkTopDown()
            .maxDepth(MAX_DISCOVERY_DEPTH)
            .onEnter { directory ->
                directory == projectRoot ||
                    (directory.name !in IGNORED_DIRECTORIES && !Files.isSymbolicLink(directory.toPath()))
            }
            .filter { directory -> directory.isDirectory && hasProjectManifest(directory) }
            .mapNotNull { directory ->
                selectAdapter(directory, verificationKind)?.let { adapter -> directory to adapter }
            }
            .take(MAX_DISCOVERY_RESULTS + 1)
            .toList()
        require(candidates.isNotEmpty()) { "No supported project manifest exists in the phone workspace" }
        require(candidates.size == 1) {
            val scopes = candidates.take(MAX_DISCOVERY_RESULTS)
                .joinToString { candidate -> displayScope(projectRoot, candidate.first) }
            "Multiple project roots were found ($scopes); provide project_scope"
        }
        return candidates.single()
    }

    private fun selectAdapter(
        directory: File,
        kind: AgentRuntimeVerificationKind
    ): Pair<String, String>? = nodeAdapter(directory, kind)
        ?: gradleAdapter(directory, kind)
        ?: mavenAdapter(directory, kind)
        ?: pythonAdapter(directory, kind)
        ?: rustAdapter(directory, kind)
        ?: goAdapter(directory, kind)
        ?: cmakeAdapter(directory, kind)
        ?: swiftAdapter(directory, kind)
        ?: dotnetAdapter(directory, kind)
        ?: makeAdapter(directory, kind)

    private fun nodeAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        val manifest = File(directory, "package.json").takeIf(File::isFile) ?: return null
        val scripts = runCatching {
            val json = JSONObject(manifest.readText(Charsets.UTF_8).take(MAX_MANIFEST_CHARS))
            val objectValue = json.optJSONObject("scripts") ?: return@runCatching emptySet()
            objectValue.keys().asSequence().toSet()
        }.getOrDefault(emptySet())
        val script = nodeScriptCandidates(kind).firstOrNull(scripts::contains) ?: return null
        val runner = when {
            File(directory, "pnpm-lock.yaml").isFile -> "pnpm run"
            File(directory, "yarn.lock").isFile -> "yarn run"
            File(directory, "bun.lock").isFile || File(directory, "bun.lockb").isFile -> "bun run"
            else -> "npm run"
        }
        return "node" to "$runner $script"
    }

    private fun gradleAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        val wrapper = File(directory, "gradlew")
        if (!wrapper.isFile && !File(directory, "settings.gradle").isFile &&
            !File(directory, "settings.gradle.kts").isFile && !File(directory, "build.gradle").isFile &&
            !File(directory, "build.gradle.kts").isFile
        ) return null
        val executable = if (wrapper.isFile) "sh ./gradlew" else "gradle"
        val task = when (kind) {
            AgentRuntimeVerificationKind.TEST -> "test"
            AgentRuntimeVerificationKind.BUILD -> "build"
            AgentRuntimeVerificationKind.LINT -> "check"
            AgentRuntimeVerificationKind.PACKAGE -> "assemble"
            AgentRuntimeVerificationKind.NONE -> return null
        }
        return "gradle" to "$executable $task"
    }

    private fun mavenAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        if (!File(directory, "pom.xml").isFile) return null
        val executable = if (File(directory, "mvnw").isFile) "sh ./mvnw" else "mvn"
        val task = when (kind) {
            AgentRuntimeVerificationKind.TEST -> "test"
            AgentRuntimeVerificationKind.BUILD, AgentRuntimeVerificationKind.PACKAGE -> "package"
            AgentRuntimeVerificationKind.LINT -> "verify"
            AgentRuntimeVerificationKind.NONE -> return null
        }
        return "maven" to "$executable $task"
    }

    private fun pythonAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        if (PYTHON_MANIFESTS.none { File(directory, it).isFile }) return null
        val command = when (kind) {
            AgentRuntimeVerificationKind.TEST -> "python -m pytest"
            AgentRuntimeVerificationKind.BUILD, AgentRuntimeVerificationKind.PACKAGE -> "python -m build"
            AgentRuntimeVerificationKind.LINT -> "python -m compileall -q ."
            AgentRuntimeVerificationKind.NONE -> return null
        }
        return "python" to command
    }

    private fun rustAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? =
        File(directory, "Cargo.toml").takeIf(File::isFile)?.let {
            "rust" to when (kind) {
                AgentRuntimeVerificationKind.TEST -> "cargo test"
                AgentRuntimeVerificationKind.BUILD -> "cargo build"
                AgentRuntimeVerificationKind.LINT -> "cargo check"
                AgentRuntimeVerificationKind.PACKAGE -> "cargo build --release"
                AgentRuntimeVerificationKind.NONE -> return null
            }
        }

    private fun goAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? =
        File(directory, "go.mod").takeIf(File::isFile)?.let {
            "go" to when (kind) {
                AgentRuntimeVerificationKind.TEST -> "go test ./..."
                AgentRuntimeVerificationKind.BUILD, AgentRuntimeVerificationKind.PACKAGE -> "go build ./..."
                AgentRuntimeVerificationKind.LINT -> "go vet ./..."
                AgentRuntimeVerificationKind.NONE -> return null
            }
        }

    private fun cmakeAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        if (!File(directory, "CMakeLists.txt").isFile) return null
        val build = "cmake -S . -B .signalasi-runtime/verify-build && " +
            "cmake --build .signalasi-runtime/verify-build"
        return "cmake" to if (kind == AgentRuntimeVerificationKind.TEST) {
            "$build && ctest --test-dir .signalasi-runtime/verify-build"
        } else {
            build
        }
    }

    private fun swiftAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? =
        File(directory, "Package.swift").takeIf(File::isFile)?.let {
            "swift" to if (kind == AgentRuntimeVerificationKind.TEST) "swift test" else "swift build"
        }

    private fun dotnetAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        val hasProject = directory.listFiles().orEmpty().any { file ->
            file.isFile && (file.extension.equals("sln", true) || file.extension.equals("csproj", true))
        }
        if (!hasProject) return null
        return "dotnet" to when (kind) {
            AgentRuntimeVerificationKind.TEST -> "dotnet test"
            AgentRuntimeVerificationKind.PACKAGE -> "dotnet publish"
            else -> "dotnet build"
        }
    }

    private fun makeAdapter(directory: File, kind: AgentRuntimeVerificationKind): Pair<String, String>? {
        if (!File(directory, "Makefile").isFile && !File(directory, "makefile").isFile) return null
        val target = when (kind) {
            AgentRuntimeVerificationKind.TEST -> "test"
            AgentRuntimeVerificationKind.LINT -> "lint"
            AgentRuntimeVerificationKind.PACKAGE -> "package"
            else -> "all"
        }
        return "make" to "make $target"
    }

    private fun hasProjectManifest(directory: File): Boolean = PROJECT_MANIFESTS.any { name ->
        File(directory, name).isFile
    } || directory.listFiles().orEmpty().any { file ->
        file.isFile && (file.extension.equals("sln", true) || file.extension.equals("csproj", true))
    }

    private fun nodeScriptCandidates(kind: AgentRuntimeVerificationKind): List<String> = when (kind) {
        AgentRuntimeVerificationKind.TEST -> listOf("test", "check")
        AgentRuntimeVerificationKind.BUILD -> listOf("build", "check", "test")
        AgentRuntimeVerificationKind.LINT -> listOf("lint", "check", "test")
        AgentRuntimeVerificationKind.PACKAGE -> listOf("package", "dist", "build", "check")
        AgentRuntimeVerificationKind.NONE -> emptyList()
    }

    private fun displayScope(projectRoot: File, directory: File): String =
        directory.relativeTo(projectRoot).invariantSeparatorsPath.ifBlank { "." }

    private val PROJECT_MANIFESTS = setOf(
        "package.json", "gradlew", "settings.gradle", "settings.gradle.kts", "build.gradle",
        "build.gradle.kts", "pom.xml", "pyproject.toml", "pytest.ini", "setup.py", "setup.cfg",
        "Cargo.toml", "go.mod", "CMakeLists.txt", "Package.swift", "Makefile", "makefile"
    )
    private val PYTHON_MANIFESTS = setOf("pyproject.toml", "pytest.ini", "setup.py", "setup.cfg")
    private val IGNORED_DIRECTORIES = setOf(
        ".git", ".gradle", ".idea", ".signalasi-runtime", "build", "dist", "node_modules", "target"
    )
    private val DRIVE_PATH = Regex("^[A-Za-z]:.*")
    private const val MAX_SCOPE_CHARS = 1_024
    private const val MAX_MANIFEST_CHARS = 1024 * 1024
    private const val MAX_DISCOVERY_DEPTH = 4
    private const val MAX_DISCOVERY_RESULTS = 8
}

private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\\"'\\\"'") + "'"
