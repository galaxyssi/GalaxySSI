package com.galaxyssi.chat

import java.io.File
import java.nio.file.Files
import org.json.JSONObject

internal data class AgentRuntimeProjectVerificationPlan(
    val scope: String,
    val adapter: String,
    val command: String,
    val requiredExecutables: List<String>
) {
    val source: String = buildString {
        appendLine("set -eu")
        appendLine("cd ${shellQuote(scope)}")
        appendLine("printf '%s\\n' ${shellQuote("GalaxySSI verification adapter: $adapter")}")
        appendLine("printf '%s\\n' ${shellQuote("GalaxySSI verification command: $command")}")
        requiredExecutables.forEach { executable ->
            appendLine(
                "command -v ${shellQuote(executable)} >/dev/null 2>&1 || { " +
                    "printf '%s\\n' ${shellQuote("GalaxySSI missing executable: $executable")} >&2; exit 127; }"
            )
        }
        appendLine(command)
    }
}

internal data class AgentRuntimeProjectProfile(
    val scope: String,
    val adapter: String,
    val commands: Map<AgentRuntimeVerificationKind, String>,
    val requiredExecutables: Map<AgentRuntimeVerificationKind, List<String>>
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "scope" to scope,
        "adapter" to adapter,
        "verification_commands" to commands.entries.associate { (kind, command) ->
            kind.wireValue to command
        },
        "required_executables" to requiredExecutables.entries.associate { (kind, executables) ->
            kind.wireValue to executables
        }
    )
}

private data class AgentRuntimeNodeManifest(
    val scripts: Map<String, String>,
    val packageManager: String
)

internal object AgentRuntimeProjectVerificationExecutionPolicy {
    fun timeoutMillis(
        automaticVerification: Boolean,
        requestedTimeoutMillis: Long?
    ): Long = requestedTimeoutMillis ?: if (automaticVerification) {
        AUTOMATIC_VERIFICATION_TIMEOUT_MILLIS
    } else {
        CUSTOM_COMMAND_TIMEOUT_MILLIS
    }

    private const val AUTOMATIC_VERIFICATION_TIMEOUT_MILLIS = 30 * 60_000L
    private const val CUSTOM_COMMAND_TIMEOUT_MILLIS = 60_000L
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
            command = adapter.second,
            requiredExecutables = projectCommandRequirements(adapter.first, adapter.second)
        )
    }

    fun profiles(projectRoot: File): List<AgentRuntimeProjectProfile> {
        val canonicalRoot = projectRoot.canonicalFile
        if (!canonicalRoot.isDirectory) return emptyList()
        return projectDirectories(canonicalRoot)
            .flatMap { directory -> profilesForDirectory(canonicalRoot, directory) }
            .take(MAX_DISCOVERY_RESULTS)
            .toList()
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
        val candidates = projectDirectories(projectRoot)
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

    private fun projectDirectories(projectRoot: File): Sequence<File> = sequence {
        val pending = java.util.ArrayDeque<Pair<File, Int>>()
        pending.addLast(projectRoot to 0)
        while (pending.isNotEmpty()) {
            val (directory, depth) = pending.removeLast()
            if (hasProjectManifest(directory)) yield(directory)
            if (depth >= MAX_DISCOVERY_DEPTH) continue
            directory.listFiles()
                .orEmpty()
                .asSequence()
                .filter(File::isDirectory)
                .filter { child ->
                    child.name !in IGNORED_DIRECTORIES && !Files.isSymbolicLink(child.toPath())
                }
                .sortedBy(File::getName)
                .toList()
                .asReversed()
                .forEach { child -> pending.addLast(child to depth + 1) }
        }
    }

    private fun profilesForDirectory(
        projectRoot: File,
        directory: File
    ): Sequence<AgentRuntimeProjectProfile> = sequenceOf(
        profile(projectRoot, directory, "node", ::nodeAdapter),
        profile(projectRoot, directory, "gradle", ::gradleAdapter),
        profile(projectRoot, directory, "maven", ::mavenAdapter),
        profile(projectRoot, directory, "python", ::pythonAdapter),
        profile(projectRoot, directory, "rust", ::rustAdapter),
        profile(projectRoot, directory, "go", ::goAdapter),
        profile(projectRoot, directory, "cmake", ::cmakeAdapter),
        profile(projectRoot, directory, "swift", ::swiftAdapter),
        profile(projectRoot, directory, "dotnet", ::dotnetAdapter),
        profile(projectRoot, directory, "make", ::makeAdapter)
    ).filterNotNull()

    private fun profile(
        projectRoot: File,
        directory: File,
        adapter: String,
        resolver: (File, AgentRuntimeVerificationKind) -> Pair<String, String>?
    ): AgentRuntimeProjectProfile? {
        val commands = AgentRuntimeVerificationKind.entries
            .asSequence()
            .filterNot { kind -> kind == AgentRuntimeVerificationKind.NONE }
            .mapNotNull { kind ->
                resolver(directory, kind)
                    ?.takeIf { result -> result.first == adapter }
                    ?.second
                    ?.let { command -> kind to command }
            }
            .toMap(linkedMapOf())
        if (commands.isEmpty()) return null
        return AgentRuntimeProjectProfile(
            scope = displayScope(projectRoot, directory),
            adapter = adapter,
            commands = commands,
            requiredExecutables = commands.mapValues { (_, command) ->
                projectCommandRequirements(adapter, command)
            }
        )
    }

    private fun projectCommandRequirements(adapter: String, command: String): List<String> = when (adapter) {
        "node" -> listOf("node", nodeRunnerExecutable(command))
        "gradle" -> listOf("java", if (command.startsWith("sh ")) "sh" else "gradle")
        "maven" -> listOf("java", if (command.startsWith("sh ")) "sh" else "mvn")
        "python" -> listOf(if (command.startsWith("uv ")) "uv" else "python")
        "rust" -> listOf("cargo")
        "go" -> listOf("go")
        "cmake" -> buildList {
            add("cmake")
            if (command.contains("ctest")) add("ctest")
        }
        "swift" -> listOf("swift")
        "dotnet" -> listOf("dotnet")
        "make" -> listOf("make")
        else -> emptyList()
    }.distinct()

    private fun nodeRunnerExecutable(command: String): String = command
        .removePrefix("CI=1 ")
        .substringBefore(' ')

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
        val parsed = runCatching {
            val json = JSONObject(manifest.readText(Charsets.UTF_8).take(MAX_MANIFEST_CHARS))
            val scripts = json.optJSONObject("scripts")
                ?.let { objectValue ->
                    objectValue.keys().asSequence().associateWith { name -> objectValue.optString(name) }
                }
                .orEmpty()
            AgentRuntimeNodeManifest(
                scripts = scripts,
                packageManager = json.optString("packageManager")
            )
        }.getOrNull() ?: return null
        val script = nodeScriptCandidates(kind).firstOrNull { candidate ->
            parsed.scripts[candidate]?.let(::isRunnableNodeScript) == true
        } ?: return null
        val runner = nodePackageRunner(directory, parsed.packageManager)
        val environment = if (kind == AgentRuntimeVerificationKind.TEST) "CI=1 " else ""
        return "node" to "$environment$runner $script"
    }

    private fun nodePackageRunner(directory: File, declaredPackageManager: String): String {
        val declared = declaredPackageManager.substringBefore('@').trim().lowercase()
        return when {
            declared in NODE_PACKAGE_RUNNERS -> NODE_PACKAGE_RUNNERS.getValue(declared)
            File(directory, "pnpm-lock.yaml").isFile -> NODE_PACKAGE_RUNNERS.getValue("pnpm")
            File(directory, "yarn.lock").isFile -> NODE_PACKAGE_RUNNERS.getValue("yarn")
            File(directory, "bun.lock").isFile || File(directory, "bun.lockb").isFile ->
                NODE_PACKAGE_RUNNERS.getValue("bun")
            else -> NODE_PACKAGE_RUNNERS.getValue("npm")
        }
    }

    private fun isRunnableNodeScript(command: String): Boolean {
        val normalized = command.trim().lowercase()
        if (normalized.isBlank()) return false
        return !(normalized.contains("error: no test specified") && normalized.contains("exit 1"))
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
        val usesUv = File(directory, "uv.lock").isFile
        val command = when (kind) {
            AgentRuntimeVerificationKind.TEST -> if (usesUv) {
                "uv run --frozen python -m pytest"
            } else {
                "python -m pytest"
            }
            AgentRuntimeVerificationKind.BUILD, AgentRuntimeVerificationKind.PACKAGE -> if (usesUv) {
                "uv build"
            } else {
                "python -m build"
            }
            AgentRuntimeVerificationKind.LINT -> if (usesUv) {
                "uv run --frozen python -m compileall -q ."
            } else {
                "python -m compileall -q ."
            }
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
        val build = "cmake -S . -B .galaxyssi-runtime/verify-build && " +
            "cmake --build .galaxyssi-runtime/verify-build"
        return "cmake" to if (kind == AgentRuntimeVerificationKind.TEST) {
            "$build && ctest --test-dir .galaxyssi-runtime/verify-build"
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
    private val NODE_PACKAGE_RUNNERS = mapOf(
        "npm" to "npm run",
        "pnpm" to "pnpm run",
        "yarn" to "yarn run",
        "bun" to "bun run"
    )
    private val IGNORED_DIRECTORIES = setOf(
        ".git", ".gradle", ".idea", ".galaxyssi-runtime", "build", "dist", "node_modules", "target"
    )
    private val DRIVE_PATH = Regex("^[A-Za-z]:.*")
    private const val MAX_SCOPE_CHARS = 1_024
    private const val MAX_MANIFEST_CHARS = 1024 * 1024
    private const val MAX_DISCOVERY_DEPTH = 4
    private const val MAX_DISCOVERY_RESULTS = 8
}

private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\\"'\\\"'") + "'"
