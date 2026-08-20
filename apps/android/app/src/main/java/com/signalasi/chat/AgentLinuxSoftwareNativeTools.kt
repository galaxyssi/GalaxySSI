package com.signalasi.chat

import android.content.Context
import java.util.Locale
import java.util.UUID

internal data class AgentLinuxSoftwareRecord(
    val id: String,
    val version: String,
    val installed: Boolean,
    val description: String
) {
    fun publicValue(): AgentNativeJsonObject = mapOf(
        "software_id" to id,
        "source" to AgentLinuxSoftwareNativeTools.SOURCE_LINUX_PACKAGE,
        "version" to version,
        "installed" to installed,
        "compatible" to true,
        "description" to description,
        "install_tool_id" to AgentLinuxSoftwareNativeTools.INSTALL
    )
}

/** A single model-facing software layer for signed runtime packs and Debian packages. */
object AgentLinuxSoftwareNativeTools {
    const val CATALOG = "signalasi.runtime.software.catalog"
    const val SEARCH = "signalasi.runtime.software.search"
    const val INSPECT = "signalasi.runtime.software.inspect"
    const val INSTALL = "signalasi.runtime.software.install"
    const val REMOVE = "signalasi.runtime.software.remove"

    internal const val SOURCE_AUTO = "auto"
    internal const val SOURCE_RUNTIME_PACK = "runtime_pack"
    internal const val SOURCE_LINUX_PACKAGE = "linux_package"

    val toolIds: Set<String> = setOf(CATALOG, SEARCH, INSPECT, INSTALL, REMOVE)

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val appContext = context.applicationContext
        val manager = AgentOnDeviceRuntimeManager(appContext)
        return listOf(
            definition(
                id = CATALOG,
                title = "List phone Linux software capabilities",
                description = "Lists managed runtime packs and the Linux package source available to the phone Agent.",
                input = AgentNativeJsonSchema.objectSchema(additionalProperties = false),
                timeoutMillis = 30_000L
            ) {
                val status = manager.status()
                AgentNativeToolExecutionResult.success(
                    mapOf(
                        "architecture" to status.architecture,
                        "linux_ready" to status.backendReady,
                        "sources" to listOf(
                            mapOf(
                                "id" to SOURCE_RUNTIME_PACK,
                                "trusted" to true,
                                "searchable" to true,
                                "install_tool_id" to INSTALL
                            ),
                            mapOf(
                                "id" to SOURCE_LINUX_PACKAGE,
                                "trusted" to false,
                                "searchable" to status.backendReady,
                                "install_tool_id" to INSTALL
                            )
                        ),
                        "software" to managedPackValues(status.packs, status.architecture)
                    ),
                    "Phone Linux software capabilities listed"
                )
            },
            definition(
                id = SEARCH,
                title = "Search compatible phone Linux software",
                description = "Searches signed runtime packs and Debian package metadata, returning compatibility and installation actions.",
                input = AgentNativeJsonSchema.objectSchema(
                    properties = mapOf(
                        "query" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 160),
                        "source" to sourceSchema(),
                        "limit" to AgentNativeJsonSchema.integer(1, MAX_RESULTS.toLong())
                    ),
                    required = setOf("query"),
                    additionalProperties = false
                ),
                timeoutMillis = PACKAGE_SEARCH_TIMEOUT_MILLIS
            ) { invocation ->
                val query = invocation.input["query"]?.toString().orEmpty().trim()
                val source = invocation.input["source"]?.toString().orEmpty().ifBlank { SOURCE_AUTO }
                val limit = ((invocation.input["limit"] as? Number)?.toInt() ?: DEFAULT_RESULTS)
                    .coerceIn(1, MAX_RESULTS)
                val status = manager.status()
                val managed = if (source != SOURCE_LINUX_PACKAGE) {
                    managedPackValues(status.packs, status.architecture, query)
                } else emptyList()
                var packageSearchError = ""
                val packages = if (source != SOURCE_RUNTIME_PACK && status.backendReady) {
                    executeLinux(
                        manager,
                        invocation,
                        aptSearchScript(query, limit),
                        timeoutMillis = PACKAGE_SEARCH_TIMEOUT_MILLIS,
                        networkEnabled = true
                    ).let { response ->
                        if (response.exitCode == 0) {
                            rankPackageRecords(
                                parsePackageRecords(response.stdout),
                                query,
                                limit
                            ).map { it.publicValue() }
                        }
                        else {
                            packageSearchError = response.stderr.trim()
                                .ifBlank { "Linux package search exited with ${response.exitCode}" }
                                .take(MAX_DIAGNOSTIC_CHARS)
                            emptyList()
                        }
                    }
                } else emptyList()
                AgentNativeToolExecutionResult.success(
                    mapOf(
                        "query" to query,
                        "architecture" to status.architecture,
                        "linux_ready" to status.backendReady,
                        "source_errors" to listOfNotNull(
                            packageSearchError.takeIf(String::isNotBlank)?.let { error ->
                                mapOf("source" to SOURCE_LINUX_PACKAGE, "message" to error)
                            }
                        ),
                        "results" to (managed + packages).take(limit)
                    ),
                    "Compatible phone Linux software searched"
                )
            },
            definition(
                id = INSPECT,
                title = "Inspect phone Linux software",
                description = "Inspects one signed runtime pack or Debian package and reports installation and compatibility state.",
                input = softwareInputSchema(),
                timeoutMillis = 60_000L
            ) { invocation ->
                val softwareId = softwareId(invocation)
                val source = resolvedSource(invocation, softwareId)
                if (source == SOURCE_RUNTIME_PACK) {
                    val status = manager.status()
                    val value = managedPackValues(status.packs, status.architecture)
                        .firstOrNull { it["software_id"] == softwareId }
                        ?: return@definition AgentNativeToolExecutionResult.failure(
                            "software_not_found", "Managed runtime pack was not found"
                        )
                    return@definition AgentNativeToolExecutionResult.success(value, "Managed runtime pack inspected")
                }
                val response = executeLinux(
                    manager,
                    invocation,
                    packageInspectScript(softwareId),
                    timeoutMillis = 60_000L,
                    networkEnabled = true
                )
                if (response.exitCode != 0) return@definition runtimeFailure("software_inspect_failed", response)
                AgentNativeToolExecutionResult.success(
                    parsePackageRecords(response.stdout).firstOrNull()?.publicValue()
                        ?: mapOf(
                            "software_id" to softwareId,
                            "source" to SOURCE_LINUX_PACKAGE,
                            "installed" to false,
                            "compatible" to false,
                            "reason" to "No package candidate is available"
                        ),
                    "Phone Linux software inspected"
                )
            },
            definition(
                id = INSTALL,
                title = "Install compatible phone Linux software",
                description = "Installs either a signed managed runtime pack or a compatible Debian package, then verifies its installed state.",
                input = softwareInputSchema(),
                timeoutMillis = 30 * 60_000L
            ) { invocation ->
                val softwareId = softwareId(invocation)
                when (resolvedSource(invocation, softwareId)) {
                    SOURCE_RUNTIME_PACK -> AgentOnDeviceRuntimeTools.installRuntimePack(
                        appContext,
                        manager,
                        invocation,
                        softwareId
                    )
                    else -> {
                        val response = executeLinux(
                            manager,
                            invocation,
                            packageMutationScript("install", softwareId),
                            timeoutMillis = 30 * 60_000L,
                            networkEnabled = true
                        )
                        if (response.exitCode != 0) runtimeFailure("software_install_failed", response)
                        else AgentNativeToolExecutionResult.success(
                            parsePackageRecords(response.stdout).lastOrNull()?.publicValue()
                                ?: mapOf(
                                    "software_id" to softwareId,
                                    "source" to SOURCE_LINUX_PACKAGE,
                                    "installed" to true
                                ),
                            "Phone Linux software installed and verified"
                        )
                    }
                }
            },
            definition(
                id = REMOVE,
                title = "Remove phone Linux software",
                description = "Removes a Debian package from the persistent phone Linux system and verifies that it is absent.",
                input = softwareInputSchema(allowedSources = listOf(SOURCE_AUTO, SOURCE_LINUX_PACKAGE)),
                timeoutMillis = 30 * 60_000L
            ) { invocation ->
                val softwareId = softwareId(invocation)
                if (softwareId in AgentOnDeviceRuntimeManager.REQUIRED_PACKS) {
                    return@definition AgentNativeToolExecutionResult.failure(
                        "managed_pack_removal_unsupported",
                        "Managed runtime packs are lifecycle-managed and cannot be removed through the Linux package tool"
                    )
                }
                val response = executeLinux(
                    manager,
                    invocation,
                    packageMutationScript("remove", softwareId),
                    timeoutMillis = 30 * 60_000L,
                    networkEnabled = true
                )
                if (response.exitCode != 0) runtimeFailure("software_remove_failed", response)
                else AgentNativeToolExecutionResult.success(
                    mapOf(
                        "software_id" to softwareId,
                        "source" to SOURCE_LINUX_PACKAGE,
                        "installed" to false
                    ),
                    "Phone Linux software removed and verified"
                )
            }
        )
    }

    internal fun parsePackageRecords(raw: String): List<AgentLinuxSoftwareRecord> = raw.lineSequence()
        .map(String::trim)
        .filter(String::isNotBlank)
        .mapNotNull { line ->
            val fields = line.split('\t', limit = 4)
            val id = fields.getOrNull(0).orEmpty()
            if (!PACKAGE_ID.matches(id)) return@mapNotNull null
            AgentLinuxSoftwareRecord(
                id = id,
                version = fields.getOrNull(1).orEmpty(),
                installed = fields.getOrNull(2) == "installed",
                description = fields.getOrNull(3).orEmpty().take(MAX_DESCRIPTION_CHARS)
            )
        }
        .distinctBy(AgentLinuxSoftwareRecord::id)
        .take(MAX_RESULTS)
        .toList()

    internal fun rankPackageRecords(
        records: List<AgentLinuxSoftwareRecord>,
        query: String,
        limit: Int
    ): List<AgentLinuxSoftwareRecord> {
        val normalized = query.trim().lowercase(Locale.ROOT)
        return records.sortedWith(
            compareBy<AgentLinuxSoftwareRecord> { record ->
                val id = record.id.lowercase(Locale.ROOT)
                when {
                    id == normalized -> 0
                    id.startsWith(normalized) -> 1
                    normalized in id -> 2
                    normalized in record.description.lowercase(Locale.ROOT) -> 3
                    else -> 4
                }
            }.thenBy { it.id }
        ).take(limit.coerceIn(1, MAX_RESULTS))
    }

    private fun managedPackValues(
        statuses: List<AgentRuntimePackStatus>,
        architecture: String,
        query: String = ""
    ): List<AgentNativeJsonObject> {
        val normalized = query.trim().lowercase(Locale.ROOT)
        return statuses.mapNotNull { status ->
            val aliases = MANAGED_PACK_ALIASES[status.id].orEmpty()
            if (normalized.isNotBlank() &&
                normalized !in status.id.lowercase(Locale.ROOT) &&
                aliases.none { normalized in it }
            ) return@mapNotNull null
            mapOf(
                "software_id" to status.id,
                "source" to SOURCE_RUNTIME_PACK,
                "version" to status.manifest?.version.orEmpty(),
                "installed" to (status.state == AgentRuntimePackState.READY),
                "compatible" to (status.state != AgentRuntimePackState.INCOMPATIBLE),
                "state" to status.state.wireValue,
                "reason" to status.reason,
                "architecture" to architecture,
                "capabilities" to status.manifest?.capabilities.orEmpty(),
                "install_tool_id" to INSTALL
            )
        }
    }

    private fun executeLinux(
        manager: AgentOnDeviceRuntimeManager,
        invocation: AgentNativeToolInvocation,
        source: String,
        timeoutMillis: Long,
        networkEnabled: Boolean
    ): AgentRuntimeExecutionResponse = manager.execute(
        AgentRuntimeExecutionRequest(
            language = AgentRuntimeLanguage.SHELL,
            source = source,
            arguments = emptyList(),
            timeoutMillis = timeoutMillis,
            networkEnabled = networkEnabled,
            artifactPaths = emptyList(),
            workspaceId = invocationWorkspaceId(invocation),
            requestId = invocation.context.invocationId.ifBlank { UUID.randomUUID().toString() },
            cancellationToken = invocation.cancellationToken,
            progressListener = { progress ->
                invocation.reportProgress(
                    progress.stage,
                    progress.message,
                    progress.percent,
                    progress.sequence,
                    progress.timestampMillis
                )
            }
        )
    )

    private fun aptSearchScript(query: String, limit: Int): String = """
        set -eu
        export LC_ALL=C
        command -v apt-cache >/dev/null 2>&1 || { echo 'apt-cache is unavailable' >&2; exit 127; }
        ${ensurePackageIndexScript()}
        query=${shellSingleQuote(query)}
        limit=$limit
        exact=${'$'}(printf '%s' "${'$'}query" | tr '[:upper:]' '[:lower:]')
        temp_dir=${'$'}(mktemp -d)
        trap 'rm -rf "${'$'}temp_dir"' EXIT HUP INT TERM
        apt-cache search --names-only -- "${'$'}query" > "${'$'}temp_dir/search"
        awk -F ' - ' -v exact="${'$'}exact" '${'$'}1 == exact { print; exit }' \
          "${'$'}temp_dir/search" > "${'$'}temp_dir/selected"
        selected=${'$'}(wc -l < "${'$'}temp_dir/selected")
        remaining=${'$'}((limit - selected))
        if [ "${'$'}remaining" -gt 0 ]; then
          awk -F ' - ' -v exact="${'$'}exact" '${'$'}1 != exact { print }' \
            "${'$'}temp_dir/search" | head -n "${'$'}remaining" >> "${'$'}temp_dir/selected"
        fi
        [ -s "${'$'}temp_dir/selected" ] || exit 0
        cut -d ' ' -f 1 "${'$'}temp_dir/selected" > "${'$'}temp_dir/packages"
        # Loading Debian metadata is expensive under QEMU. Query every candidate in one
        # apt-cache process instead of reparsing the full index once per result.
        xargs apt-cache policy < "${'$'}temp_dir/packages" |
          awk '
            /^[^ ][^:]*:$/ { package=substr(${'$'}0, 1, length(${'$'}0) - 1); next }
            /^  Candidate: / { print package "\t" substr(${'$'}0, 14) }
          ' > "${'$'}temp_dir/versions"
        xargs dpkg-query -W -f='${'$'}{Package}\t${'$'}{db:Status-Abbrev}\n' -- \
          < "${'$'}temp_dir/packages" 2>/dev/null > "${'$'}temp_dir/installed" || true
        while IFS= read -r line; do
          package=${'$'}{line%% - *}
          description=${'$'}{line#* - }
          version=${'$'}(awk -F '\t' -v package="${'$'}package" '${'$'}1 == package { print ${'$'}2; exit }' \
            "${'$'}temp_dir/versions")
          installed=no
          awk -F '\t' -v package="${'$'}package" '${'$'}1 == package && ${'$'}2 ~ /^ii / { found=1 } END { exit !found }' \
            "${'$'}temp_dir/installed" && installed=installed || true
          printf '%s\t%s\t%s\t%s\n' "${'$'}package" "${'$'}version" "${'$'}installed" "${'$'}description"
        done < "${'$'}temp_dir/selected"
    """.trimIndent()

    private fun packageInspectScript(packageId: String): String = """
        set -eu
        export LC_ALL=C
        command -v apt-cache >/dev/null 2>&1 || { echo 'apt-cache is unavailable' >&2; exit 127; }
        ${ensurePackageIndexScript()}
        package=${shellSingleQuote(packageId)}
        version=${'$'}(apt-cache policy "${'$'}package" | sed -n 's/^  Candidate: //p' | head -n 1)
        installed=no
        installed_version=${'$'}(dpkg-query -W -f='${'$'}{Version}' "${'$'}package" 2>/dev/null || true)
        [ -n "${'$'}installed_version" ] && installed=installed && version=${'$'}installed_version
        description=${'$'}(apt-cache show "${'$'}package" 2>/dev/null | sed -n 's/^Description-en: //p; s/^Description: //p' | head -n 1)
        printf '%s\t%s\t%s\t%s\n' "${'$'}package" "${'$'}version" "${'$'}installed" "${'$'}description"
    """.trimIndent()

    private fun ensurePackageIndexScript(): String = """
        if ! find /var/lib/apt/lists -maxdepth 1 -type f -name '*_Packages*' -print -quit 2>/dev/null | grep -q .; then
          command -v apt-get >/dev/null 2>&1 || { echo 'apt-get is unavailable' >&2; exit 127; }
          apt-get \
            -o Acquire::Languages=none \
            -o Acquire::Retries=1 \
            -o Acquire::ForceIPv4=true \
            -o Acquire::http::Timeout=30 \
            -o Acquire::https::Timeout=30 \
            update >&2
        fi
    """.trimIndent()

    private fun packageMutationScript(operation: String, packageId: String): String {
        require(operation == "install" || operation == "remove")
        val verify = if (operation == "install") {
            "dpkg-query -W -f='${'$'}{binary:Package}\\t${'$'}{Version}\\tinstalled\\t\\n' \"${'$'}package\""
        } else {
            "! dpkg-query -W \"${'$'}package\" >/dev/null 2>&1"
        }
        return """
            set -eu
            export LC_ALL=C DEBIAN_FRONTEND=noninteractive
            package=${shellSingleQuote(packageId)}
            apt-get update
            apt-get $operation -y --no-install-recommends "${'$'}package"
            $verify
        """.trimIndent()
    }

    private fun runtimeFailure(code: String, response: AgentRuntimeExecutionResponse) =
        AgentNativeToolExecutionResult.failure(
            code,
            response.stderr.trim().ifBlank { "Phone Linux software operation failed with ${response.exitCode}" },
            details = mapOf(
                "exit_code" to response.exitCode,
                "stdout" to response.stdout.take(MAX_DIAGNOSTIC_CHARS),
                "stderr" to response.stderr.take(MAX_DIAGNOSTIC_CHARS)
            )
        )

    private fun softwareId(invocation: AgentNativeToolInvocation): String =
        invocation.input["software_id"]?.toString().orEmpty().also { value ->
            require(PACKAGE_ID.matches(value)) { "Software id is invalid" }
        }

    private fun resolvedSource(invocation: AgentNativeToolInvocation, softwareId: String): String {
        val requested = invocation.input["source"]?.toString().orEmpty().ifBlank { SOURCE_AUTO }
        return if (requested == SOURCE_AUTO) {
            if (softwareId in AgentOnDeviceRuntimeManager.REQUIRED_PACKS) SOURCE_RUNTIME_PACK
            else SOURCE_LINUX_PACKAGE
        } else requested
    }

    private fun invocationWorkspaceId(invocation: AgentNativeToolInvocation): String =
        invocation.context.attributes["workspace_id"].orEmpty()
            .ifBlank { invocation.context.turnId }
            .ifBlank { invocation.context.conversationId }
            .ifBlank { invocation.context.invocationId }

    private fun softwareInputSchema(
        allowedSources: List<String> = listOf(SOURCE_AUTO, SOURCE_RUNTIME_PACK, SOURCE_LINUX_PACKAGE)
    ) = AgentNativeJsonSchema.objectSchema(
        properties = mapOf(
            "software_id" to AgentNativeJsonSchema.string(
                minLength = 1,
                maxLength = 128,
                pattern = PACKAGE_ID.pattern
            ),
            "source" to AgentNativeJsonSchema.string(enumValues = allowedSources)
        ),
        required = setOf("software_id"),
        additionalProperties = false
    )

    private fun sourceSchema() = AgentNativeJsonSchema.string(
        enumValues = listOf(SOURCE_AUTO, SOURCE_RUNTIME_PACK, SOURCE_LINUX_PACKAGE)
    )

    private fun definition(
        id: String,
        title: String,
        description: String,
        input: AgentNativeJsonSchema,
        timeoutMillis: Long,
        execute: (AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
    ) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = title,
            description = description,
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = input,
            outputSchema = AgentNativeJsonSchema.any(),
            risk = AgentNativeToolRisk.LOW,
            capabilities = setOf("runtime.software", "runtime.linux", "runtime.root"),
            timeoutMillis = timeoutMillis,
            idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT,
            availability = AgentNativeToolAvailability.AVAILABLE
        ),
        executor = AgentNativeToolExecutor(execute),
        executorId = "signalasi.android_linux_software",
        provenanceMetadata = mapOf("platform" to "phone_linux")
    )

    private const val DEFAULT_RESULTS = 20
    private const val MAX_RESULTS = 50
    internal const val PACKAGE_SEARCH_TIMEOUT_MILLIS = 10 * 60_000L
    private const val MAX_DESCRIPTION_CHARS = 500
    private const val MAX_DIAGNOSTIC_CHARS = 8_000
    private val PACKAGE_ID = Regex("[a-z0-9][a-z0-9+.-]{0,127}")
    private val MANAGED_PACK_ALIASES = mapOf(
        "linux-base" to listOf("linux", "shell", "git", "ssh", "curl", "wget", "zip"),
        "python-uv" to listOf("python", "uv", "pip"),
        "node-js" to listOf("node", "nodejs", "npm", "javascript", "typescript"),
        "go" to listOf("go", "golang"),
        "rust" to listOf("rust", "cargo"),
        "cpp" to listOf("c", "c++", "cpp", "gcc", "g++"),
        "java" to listOf("java", "jdk"),
        "gradle" to listOf("gradle"),
        "android-sdk" to listOf("android", "sdk", "ndk", "apk"),
        "browser-automation" to listOf("browser", "chromium", "playwright"),
        "ffmpeg" to listOf("ffmpeg", "ffprobe", "video", "audio", "image")
    )
}
