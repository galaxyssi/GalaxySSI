package com.galaxyssi.chat

import android.content.Context

object AgentWebIntelligenceNativeTools {
    const val SEARCH = "galaxyssi.web.intelligence.search"
    const val FETCH = "galaxyssi.web.intelligence.fetch"
    const val CRAWL = "galaxyssi.web.intelligence.crawl"
    const val EXTRACT = "galaxyssi.web.intelligence.extract"
    const val CACHE = "galaxyssi.web.intelligence.cache"
    const val FIND_SIMILAR = "galaxyssi.web.intelligence.find_similar"
    const val RESEARCH = "galaxyssi.web.intelligence.research"
    const val AGENT = "galaxyssi.web.intelligence.agent"
    const val DIFF = "galaxyssi.web.intelligence.diff"
    const val WATCH = "galaxyssi.web.intelligence.watch"

    private const val VERSION = "1.0.0"
    private const val EXECUTOR_ID = "galaxyssi.android.web_intelligence"

    val toolIds: Set<String> = linkedSetOf(
        SEARCH,
        FETCH,
        CRAWL,
        EXTRACT,
        CACHE,
        FIND_SIMILAR,
        RESEARCH,
        AGENT,
        DIFF,
        WATCH
    )

    fun androidDefinitions(
        context: Context,
        web: AgentBoundedWebService
    ): List<AgentNativeToolDefinition> = definitions(
        AgentWebIntelligenceService.android(context.applicationContext, web),
        web.availability
    )

    fun definitions(
        service: AgentWebIntelligenceService,
        availability: AgentNativeToolAvailability = AgentNativeToolAvailability.AVAILABLE
    ): List<AgentNativeToolDefinition> = listOf(
        definition(
            SEARCH,
            "Search across independent web sources",
            "Queries parallel general, news, code, academic, community, documentation and knowledge sources, then fuses and locally reranks results.",
            searchSchema(),
            60_000L,
            service,
            availability
        ),
        definition(
            FETCH,
            "Fetch and cache readable public content",
            "Fetches one public HTTPS resource through pinned DNS, extracts readable content and stores an encrypted local copy with provenance.",
            fetchSchema(),
            120_000L,
            service,
            availability
        ),
        definition(
            CRAWL,
            "Crawl a bounded public site",
            "Traverses a bounded set of public HTTPS pages with depth, origin, pattern, cancellation and deadline controls.",
            crawlSchema(),
            10L * 60_000L,
            service,
            availability,
            timeoutPolicy = AgentNativeToolTimeoutPolicy.PROGRESS_AWARE
        ),
        definition(
            EXTRACT,
            "Extract structured readable content",
            "Extracts readable text, headings, links, language and requested fields from a public URL or supplied content.",
            extractSchema(),
            120_000L,
            service,
            availability,
            networkRequired = false
        ),
        definition(
            CACHE,
            "Manage encrypted web intelligence cache",
            "Inspects, searches or clears GalaxySSI's encrypted local web document and search cache.",
            cacheSchema(),
            60_000L,
            service,
            availability,
            networkRequired = false
        ),
        definition(
            FIND_SIMILAR,
            "Find semantically similar evidence",
            "Uses a small on-device feature-hash embedding model to find related cached documents and optionally supplements them from the public web.",
            similarSchema(),
            120_000L,
            service,
            availability,
            networkRequired = false
        ),
        definition(
            RESEARCH,
            "Build a cited research evidence pack",
            "Searches, retrieves and organizes untrusted web evidence for final synthesis by the selected GalaxySSI model or Agent.",
            researchSchema(),
            5L * 60_000L,
            service,
            availability,
            timeoutPolicy = AgentNativeToolTimeoutPolicy.PROGRESS_AWARE
        ),
        definition(
            AGENT,
            "Run autonomous multi-source web investigation",
            "Expands a research objective across multiple evidence rounds, retrieves sources and returns a cited evidence pack with source receipts.",
            researchSchema(),
            10L * 60_000L,
            service,
            availability,
            timeoutPolicy = AgentNativeToolTimeoutPolicy.PROGRESS_AWARE
        ),
        definition(
            DIFF,
            "Compare a public page with its prior state",
            "Refetches a cached public page and reports content hashes plus a bounded human-readable change summary.",
            fetchSchema(),
            120_000L,
            service,
            availability
        ),
        definition(
            WATCH,
            "Create and check public page watches",
            "Creates, lists, removes and checks encrypted page watches for material content changes.",
            watchSchema(),
            10L * 60_000L,
            service,
            availability,
            networkRequired = false,
            timeoutPolicy = AgentNativeToolTimeoutPolicy.PROGRESS_AWARE
        )
    )

    private fun definition(
        id: String,
        title: String,
        description: String,
        inputSchema: AgentNativeJsonSchema,
        timeoutMillis: Long,
        service: AgentWebIntelligenceService,
        availability: AgentNativeToolAvailability,
        networkRequired: Boolean = true,
        timeoutPolicy: AgentNativeToolTimeoutPolicy = AgentNativeToolTimeoutPolicy.FIXED
    ): AgentNativeToolDefinition = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = id,
            version = VERSION,
            title = title,
            description = description,
            location = AgentNativeToolLocation.PHONE,
            inputSchema = inputSchema,
            outputSchema = outputSchema(),
            risk = AgentNativeToolRisk.LOW,
            capabilities = setOf(
                "web_intelligence.native",
                "cache.encrypted",
                "source.receipts"
            ) + if (networkRequired) {
                setOf(
                    "network.public_https",
                    "network.dns_pinned",
                    "network.redirect_bounded"
                )
            } else {
                setOf("offline.available")
            },
            requiredPermissions = if (networkRequired) {
                listOf(
                    AgentNativePermissionRequirement(
                        AgentWebMediaNativeTools.INTERNET_PERMISSION,
                        "Internet access",
                        "Uses the app-declared Android Internet permission for public HTTPS only."
                    )
                )
            } else {
                emptyList()
            },
            timeoutMillis = timeoutMillis,
            timeoutPolicy = timeoutPolicy,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            availability = if (networkRequired) availability else AgentNativeToolAvailability.AVAILABLE
        ),
        executor = AgentNativeToolExecutor { invocation ->
            try {
                invocation.reportProgress("web_intelligence", title)
                val operation = id.substringAfterLast('.')
                val output = service.invoke(
                    operation,
                    invocation.input,
                    invocation.cancellationToken,
                    invocation::checkpoint
                )
                AgentNativeToolExecutionResult.success(
                    output = output,
                    message = "$title completed",
                    metadata = mapOf(
                        "protocol" to AGENT_WEB_INTELLIGENCE_PROTOCOL,
                        "implementation" to "galaxyssi_native_android",
                        "source_isolation" to true,
                        "evidence_is_untrusted" to true
                    )
                )
            } catch (error: AgentNativeToolCancelledException) {
                throw error
            } catch (error: AgentNativeToolTimeoutException) {
                throw error
            } catch (error: AgentWebMediaException) {
                AgentNativeToolExecutionResult.failure(
                    error.code,
                    error.message,
                    error.retryable,
                    error.details
                )
            } catch (error: IllegalArgumentException) {
                AgentNativeToolExecutionResult.failure(
                    "invalid_argument",
                    error.message ?: "Web intelligence input is invalid"
                )
            } catch (error: Throwable) {
                AgentNativeToolExecutionResult.failure(
                    "web_intelligence_failed",
                    error.message ?: "Web intelligence operation failed",
                    retryable = true
                )
            }
        },
        executorId = EXECUTOR_ID,
        provenanceMetadata = mapOf(
            "implementation" to "clean_room_galaxyssi",
            "platform" to "android_phone",
            "engine_catalog_size" to AgentWebIntelligenceEngineCatalog.entries.size.toString(),
            "ranker" to AgentWebIntelligenceRanker.MODEL_ID,
            "cache" to "android_keystore_encrypted",
            "cookies" to "none"
        ),
        availabilityProvider = AgentNativeToolAvailabilityProvider {
            if (networkRequired) availability else AgentNativeToolAvailability.AVAILABLE
        }
    )

    private fun searchSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "query" to string(1, 4_096),
            "limit" to integer(1, 100),
            "profile" to AgentNativeJsonSchema.string(
                enumValues = AgentWebIntelligenceSearchProfile.entries.map { it.wireValue }
            ),
            "engine_fanout" to integer(1, 32),
            "engines" to stringArray(32, 64),
            "verticals" to AgentNativeJsonSchema.array(
                AgentNativeJsonSchema.string(
                    enumValues = AgentWebIntelligenceVertical.entries.map { it.wireValue }
                ),
                maxItems = AgentWebIntelligenceVertical.entries.size
            ),
            "categories" to stringArray(32, 64),
            "timeout_ms" to integer(1_000, 60_000),
            "use_cache" to AgentNativeJsonSchema.boolean()
        ),
        setOf("query")
    )

    private fun fetchSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "url" to string(8, 4_096),
            "force" to AgentNativeJsonSchema.boolean(),
            "max_bytes" to integer(1_024, AgentWebIntelligenceService.MAX_FETCH_BYTES),
            "timeout_ms" to integer(1_000, 120_000),
            "cache_ttl_ms" to integer(60_000, AgentWebIntelligenceService.MAX_CACHE_TTL_MILLIS)
        ),
        setOf("url")
    )

    private fun crawlSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "url" to string(8, 4_096),
            "max_pages" to integer(1, 100),
            "max_depth" to integer(0, 5),
            "same_origin" to AgentNativeJsonSchema.boolean(),
            "include_pattern" to string(0, 512),
            "exclude_pattern" to string(0, 512),
            "timeout_ms" to integer(1_000, 600_000)
        ),
        setOf("url")
    )

    private fun extractSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "url" to string(0, 4_096),
            "content" to string(0, AgentWebIntelligenceService.MAX_CONTENT_CHARS),
            "source_url" to string(0, 4_096),
            "title" to string(0, 2_048),
            "fields" to stringArray(100, 128),
            "force" to AgentNativeJsonSchema.boolean(),
            "timeout_ms" to integer(1_000, 120_000)
        )
    )

    private fun cacheSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "action" to AgentNativeJsonSchema.string(
                enumValues = listOf(
                    "status", "query", "get", "clear", "clear_expired",
                    "source_health", "reset_source_health"
                )
            ),
            "query" to string(0, 4_096),
            "url" to string(0, 4_096),
            "limit" to integer(1, 100),
            "engines" to stringArray(32, 64)
        )
    )

    private fun similarSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "query" to string(0, 4_096),
            "url" to string(0, 4_096),
            "limit" to integer(1, 100),
            "search_web" to AgentNativeJsonSchema.boolean(),
            "timeout_ms" to integer(1_000, 120_000)
        )
    )

    private fun researchSchema(): AgentNativeJsonSchema = objectSchema(
        buildMap {
            put("query", string(1, 4_096))
            put("query_plan", researchQueryPlanSchema())
            put("evidence_limit", integer(2, 24))
            put("engine_fanout", integer(1, 32))
            put(
                "profile",
                AgentNativeJsonSchema.string(
                    enumValues = AgentWebIntelligenceSearchProfile.entries.map { it.wireValue }
                )
            )
            put("engines", stringArray(32, 64))
            put(
                "verticals",
                AgentNativeJsonSchema.array(
                    AgentNativeJsonSchema.string(
                    enumValues = AgentWebIntelligenceVertical.entries.map { it.wireValue }
                    ),
                    maxItems = AgentWebIntelligenceVertical.entries.size
                )
            )
            put("categories", stringArray(32, 64))
            put("use_cache", AgentNativeJsonSchema.boolean())
            put("timeout_ms", integer(2_000, 60_000))
            put("page_read_parallelism", integer(1, 6))
            put("per_host_parallelism", integer(1, 2))
            put("page_read_timeout_ms", integer(2_000, 60_000))
            put("early_complete", AgentNativeJsonSchema.boolean())
        },
        setOf("query")
    )

    private fun researchQueryPlanSchema(): AgentNativeJsonSchema = AgentNativeJsonSchema.array(
        AgentNativeJsonSchema.objectSchema(
            properties = mapOf(
                "query" to string(1, AgentWebResearchPlanCodec.MAX_QUERY_CHARACTERS),
                "purpose" to string(0, AgentWebResearchPlanCodec.MAX_PURPOSE_CHARACTERS),
                "verticals" to AgentNativeJsonSchema.array(
                    AgentNativeJsonSchema.string(
                        enumValues = AgentWebIntelligenceVertical.entries.map { it.wireValue }
                    ),
                    maxItems = AgentWebIntelligenceVertical.entries.size
                ),
                "categories" to stringArray(AgentWebResearchPlanCodec.MAX_CATEGORIES, 64),
                "engines" to stringArray(AgentWebResearchPlanCodec.MAX_ENGINES, 64)
            ),
            required = setOf("query"),
            additionalProperties = true
        ),
        maxItems = AgentWebResearchPlanCodec.MAX_ITEMS
    )

    private fun watchSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "action" to AgentNativeJsonSchema.string(
                enumValues = listOf("create", "list", "remove", "check", "check_due")
            ),
            "watch_id" to AgentNativeJsonSchema.string(
                minLength = 0,
                maxLength = 96,
                pattern = "[A-Za-z0-9][A-Za-z0-9._-]{0,95}"
            ),
            "url" to string(0, 4_096),
            "interval_minutes" to integer(15, 10_080),
            "enabled" to AgentNativeJsonSchema.boolean(),
            "limit" to integer(1, 100),
            "timeout_ms" to integer(1_000, 60_000)
        )
    )

    private fun outputSchema(): AgentNativeJsonSchema = objectSchema(
        mapOf(
            "protocol" to AgentNativeJsonSchema.string(enumValues = listOf(AGENT_WEB_INTELLIGENCE_PROTOCOL)),
            "operation" to AgentNativeJsonSchema.string(
                enumValues = listOf(
                    "search",
                    "fetch",
                    "crawl",
                    "extract",
                    "cache",
                    "find_similar",
                    "research",
                    "agent",
                    "diff",
                    "watch"
                )
            ),
            "status" to AgentNativeJsonSchema.string(
                enumValues = listOf("completed", "partial", "failed")
            ),
            "request_id" to string(0, 128),
            "started_at_millis" to integer(0, Long.MAX_VALUE),
            "completed_at_millis" to integer(0, Long.MAX_VALUE)
        ),
        setOf("protocol", "operation", "status")
    )

    private fun objectSchema(
        properties: Map<String, AgentNativeJsonSchema>,
        required: Set<String> = emptySet()
    ): AgentNativeJsonSchema = AgentNativeJsonSchema.objectSchema(
        properties,
        required,
        additionalProperties = true
    )

    private fun string(min: Int, max: Int): AgentNativeJsonSchema =
        AgentNativeJsonSchema.string(minLength = min, maxLength = max)

    private fun integer(min: Number, max: Number): AgentNativeJsonSchema =
        AgentNativeJsonSchema.integer(min.toLong(), max.toLong())

    private fun stringArray(maxItems: Int, maxLength: Int): AgentNativeJsonSchema =
        AgentNativeJsonSchema.array(
            AgentNativeJsonSchema.string(minLength = 1, maxLength = maxLength),
            maxItems = maxItems
        )
}
