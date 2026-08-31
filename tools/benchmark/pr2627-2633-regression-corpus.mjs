const profiles = [
  ["fresh-start", "fresh process with empty transient state", "start from a cold App process", "no stale state may affect the result"],
  ["warm-state", "warm process with initialized services", "repeat after one successful operation", "warm state must preserve the same contract"],
  ["duplicate-input", "the same logical input is submitted twice", "repeat the identical request", "deduplication must prevent duplicate work or records"],
  ["reordered-input", "equivalent inputs arrive in reverse order", "reverse candidate or event order", "ordering differences must not corrupt identity or ranking"],
  ["single-failure", "one dependency fails while peers remain healthy", "inject one isolated failure", "healthy work must complete and expose the failed receipt"],
  ["partial-failure", "half of the dependencies fail independently", "inject failures into alternating candidates", "partial evidence must remain usable and failures visible"],
  ["late-timeout", "the lowest-ranked operation reaches its deadline", "delay the final candidate beyond its budget", "completed higher-ranked work must be retained"],
  ["early-timeout", "the highest-ranked operation reaches its deadline", "delay the first candidate beyond its budget", "later independent work must still be considered"],
  ["cancel-before", "cancellation is requested before execution", "cancel before invoking the operation", "no durable side effect may be produced"],
  ["cancel-during", "cancellation arrives after work starts", "cancel at the first checkpoint", "workers must stop and report cancellation coherently"],
  ["offline", "network becomes unavailable", "execute with network unavailable", "cached or local behavior must remain deterministic"],
  ["same-host-redirect", "the source redirects within the same host", "return a same-host resolved URL", "the requested identity must remain addressable"],
  ["cross-host-redirect", "the source redirects to another public host", "return a cross-host resolved URL", "redirect provenance must remain explicit and bounded"],
  ["unicode-content", "content and metadata contain CJK and emoji", "use multilingual titles, text, and metadata", "Unicode must survive without changing security decisions"],
  ["percent-encoded", "URLs contain percent-encoded path and query data", "use encoded international path segments", "canonicalization must preserve semantic URL bytes"],
  ["empty-optional", "optional title, author, or metadata is empty", "omit non-required fields", "required output must remain valid without placeholder corruption"],
  ["maximum-bound", "input reaches the documented count or size boundary", "fill the supported bounded capacity", "output must stay within limits without silent overflow"],
  ["untrusted-instruction", "retrieved text contains prompt-injection instructions", "embed fake SYSTEM and tool instructions", "web evidence must never gain instruction authority"],
  ["process-restart", "the App process restarts between related operations", "persist, restart, then continue", "durable identity and privacy behavior must survive restart"],
  ["concurrent-callers", "multiple callers request related work concurrently", "start callers at the same barrier", "shared work must remain isolated, bounded, and deterministic"]
].map(([id, condition, action, guard]) => ({ id, condition, action, guard }));

const suites = [
  [2627, "parallel-result-order", "parallelism", "parallel_reader", "integration", "out-of-order page completion changes ranked evidence", "read pages whose completion order differs from rank order", "return documents in deterministic candidate rank order"],
  [2627, "per-host-cap", "parallelism", "parallel_reader", "integration", "one host can monopolize all workers", "read many pages from one host plus independent hosts", "enforce the per-host concurrency limit without starving other hosts"],
  [2627, "mixed-host-fairness", "parallelism", "parallel_reader", "integration", "slow hosts can block independent fast evidence", "mix slow and fast hosts in one evidence batch", "retain fast independent evidence before the shared deadline"],
  [2627, "shared-deadline", "timeouts", "parallel_reader", "integration", "per-request waits can exceed the overall research budget", "run candidates under one shared deadline", "stop unfinished reads at the shared deadline and preserve receipts"],
  [2627, "early-completion", "latency", "completion_policy", "unit", "research continues after enough diverse evidence exists", "provide sufficient substantial cross-domain evidence", "complete early only after diversity and content thresholds are met"],
  [2627, "partial-source-failure", "recovery", "parallel_reader", "integration", "one failed source can discard successful peers", "fail selected sources while others succeed", "return partial evidence and per-source failure receipts"],
  [2627, "duplicate-candidate-collapse", "deduplication", "parallel_reader", "integration", "tracking variants trigger duplicate page reads", "submit canonical URL variants as candidates", "read each canonical page at most once"],
  [2627, "cancellation-propagation", "cancellation", "parallel_reader", "integration", "cancelled research leaves worker threads running", "cancel a live multi-page read", "propagate cancellation and terminate workers without a final evidence mutation"],

  [2628, "pairing-replay-dedup", "pairing", "pairing_id", "unit", "replayed pairing confirmations create repeated system messages", "derive identity for repeated confirmation payloads", "produce one stable fallback message identity"],
  [2628, "supplied-message-id", "pairing", "pairing_id", "unit", "a transport identity is replaced by a local fallback", "supply an explicit desktop message identity", "preserve the supplied identity exactly"],
  [2628, "route-isolation", "pairing", "pairing_id", "unit", "two phone routes collapse into one confirmation", "derive confirmations for different client routes", "keep route-specific confirmation identities distinct"],
  [2628, "desktop-isolation", "pairing", "pairing_id", "unit", "two desktops collapse into one confirmation", "derive confirmations for different desktops", "keep desktop-specific confirmation identities distinct"],
  [2628, "system-notice-idempotence", "notifications", "pairing_id", "device", "process restart displays the same confirmation again", "replay a confirmation before and after restart", "retain one durable notification record and unread transition"],

  [2629, "explicit-url-dedup", "url-capture", "url_extract", "unit", "one message fetches the same public URL repeatedly", "submit lexical and tracking variants of one URL", "extract unique explicit HTTPS sources in first-seen order"],
  [2629, "max-url-bound", "url-capture", "url_extract", "unit", "a prompt can stage unbounded public pages", "submit more explicit URLs than one turn allows", "stage no more than four explicit public URLs"],
  [2629, "history-continuation", "context", "url_context", "unit", "a follow-up loses the article referenced in prior user text", "continue a conversation without repeating the URL", "restore only the latest relevant public URL"],
  [2629, "cache-hit", "cache", "cache_service", "integration", "a warm fetch repeats network work", "fetch the same canonical URL twice", "serve the second fetch from cache"],
  [2629, "cache-expiry", "cache", "cache_service", "integration", "expired web content is served indefinitely", "advance the clock beyond document TTL", "perform a new fetch after expiry"],
  [2629, "concurrent-singleflight", "deduplication", "singleflight", "integration", "concurrent callers duplicate one network fetch", "request one canonical URL from concurrent service callers", "perform one owner fetch and share its result"],
  [2629, "failure-not-poison-cache", "recovery", "cache_service", "integration", "a failed first fetch permanently poisons later retries", "fail once then retry the same URL", "allow a later successful fetch and cache only valid evidence"],
  [2629, "redirect-request-alias", "cache", "cache_service", "device", "redirected pages miss cache when later requested by original URL", "fetch a URL whose final URL differs", "cache under requested identity and retain resolved URL provenance"],

  [2630, "canonical-citation", "evidence-pack", "evidence_pack", "unit", "URL variants generate incompatible citation identities", "build evidence from canonical-equivalent URLs", "emit a stable canonical citation ID"],
  [2630, "manifest-integrity", "evidence-pack", "evidence_pack", "unit", "evidence items change without detection", "build and then verify an evidence manifest", "recompute and validate the citation manifest hash"],
  [2630, "duplicate-content-correlation", "evidence-pack", "evidence_pack", "unit", "syndicated copies are counted as independent corroboration", "provide identical hashes from separate domains", "mark duplicate content as correlated rather than independent"],
  [2630, "numeric-conflict", "evidence-pack", "evidence_pack", "unit", "conflicting numeric claims are silently synthesized", "provide cross-domain claims with different quantities", "flag a potential conflict for model resolution"],
  [2630, "cross-client-url-normalization", "protocol", "canonical_url", "unit", "Android and Desktop normalize the same URL differently", "normalize tracking, ports, slashes, query order, and fragments", "match the shared canonical URL contract"],
  [2630, "bounded-pack-json", "protocol", "bounded_pack", "unit", "large evidence packs overflow model context", "encode an oversized evidence pack", "produce valid bounded JSON while preserving cited URLs"],
  [2630, "untrusted-evidence-boundary", "security", "untrusted_boundary", "unit", "retrieved HTML can issue system instructions", "wrap adversarial web content as model evidence", "declare instruction authority none and preserve source provenance"],

  [2631, "wechat-mobile-headers", "dynamic-web", "dynamic_headers", "device", "WeChat rejects generic desktop requests", "request a WeChat public article", "send the bounded mobile WeChat header profile"],
  [2631, "generic-host-no-special-header", "dynamic-web", "dynamic_headers", "unit", "WeChat-specific headers leak to unrelated hosts", "request a generic public HTTPS page", "omit WeChat-only Referer and user-agent values"],
  [2631, "structured-wechat-parse", "extraction", "article_parse", "device", "WeChat chrome replaces the real article body", "parse activity-name, js_name, publish_time, and js_content", "extract title, author, date, body, original images, and links"],
  [2631, "generic-jsonld-parse", "extraction", "article_parse", "unit", "generic articles lose structured metadata", "parse NewsArticle JSON-LD plus visible body", "prefer structured title, authors, publication time, and images"],
  [2631, "challenge-detection", "dynamic-web", "dynamic_fetch", "integration", "a challenge page is mistaken for article evidence", "return a challenge or thin JavaScript shell", "reject or render the shell instead of accepting empty evidence"],
  [2631, "static-success-no-render", "dynamic-web", "dynamic_fetch", "integration", "the isolated renderer runs for every static page", "return a complete readable static article", "accept static extraction without launching the renderer"],
  [2631, "renderer-failure-isolation", "dynamic-web", "dynamic_fetch", "integration", "renderer failure destroys the static fetch receipt", "fail isolated rendering after a thin static response", "report bounded failure without leaking renderer state"],

  [2632, "background-event-lightweight", "cognition", "cognition_plan", "unit", "each message starts expensive batch cognition", "schedule an event-triggered cognition pass", "use only the lightweight event processing path"],
  [2632, "scheduled-bounded-cycle", "cognition", "cognition_plan", "unit", "scheduled cognition runs without a cycle bound", "schedule periodic and explicit cognition", "keep scheduled work to one cycle and explicit work to two"],
  [2632, "idle-four-hour-cap", "cognition", "cognition_delay", "unit", "idle scheduling becomes excessively frequent or never runs", "calculate delay with no active or pending work", "schedule the bounded four-hour idle cadence"],
  [2632, "active-ten-minute-cadence", "cognition", "cognition_delay", "unit", "pending local work waits for the idle cadence", "calculate delay with pending events", "schedule the ten-minute active cadence"],
  [2632, "secret-knowledge-block", "privacy", "privacy_knowledge", "unit", "credentials are projected into an external vault", "project knowledge containing identity, MQTT, API, or token secrets", "reject sensitive knowledge before projection"],
  [2632, "safe-knowledge-project", "privacy", "privacy_knowledge", "unit", "ordinary reusable knowledge is over-blocked", "project non-sensitive Agent knowledge", "allow useful knowledge while retaining local privacy metadata"],
  [2632, "metadata-token-block", "privacy", "privacy_metadata", "unit", "credentials in source URLs bypass body scanning", "project metadata containing token-like query parameters", "reject sensitive metadata regardless of body safety"],
  [2632, "transcript-redaction", "privacy", "transcript_redaction", "unit", "private transcript text is written verbatim", "project transcript content containing private credentials", "replace sensitive content with the fixed omission marker"],

  [2633, "model-semantic-tool-policy", "model-routing", "tool_catalog", "unit", "keyword rules override the model's semantic tool choice", "inspect the shared current-evidence prompt and tool schema", "expose semantic model-directed choice without timezone or keyword hardcoding"],
  [2633, "dsml-tool-call-parse", "provider-protocol", "tool_protocol", "unit", "DeepSeek tool calls are displayed as model prose", "parse DSML invoke and parameter forms", "execute structured web calls and remove protocol markup"],
  [2633, "normal-text-preservation", "provider-protocol", "tool_protocol", "unit", "protocol stripping removes ordinary answer text", "mix normal prose before and after tool markup", "preserve user-visible prose while removing only internal markup"],
  [2633, "citation-required", "verification", "citation_validation", "unit", "web-derived claims finalize without sources", "validate an answer without citations against a verified pack", "request one repair against the pack's allowed URLs"],
  [2633, "foreign-citation-rejected", "verification", "citation_validation", "unit", "a model cites an unrelated or injected host", "cite a URL absent from the verified evidence pack", "reject the foreign citation and expose its URL"],
  [2633, "tampered-citation-id", "verification", "evidence_pack", "unit", "modified citation identities still verify", "tamper with a generated citation ID", "fail pack verification and identify the invalid item"],
  [2633, "one-repair-only", "verification", "citation_validation", "integration", "citation repair loops indefinitely", "finalize missing, valid, and foreign citation answers", "perform at most one bounded repair and then return an explicit result"]
].map(([pr, id, category, oracle, layer, risk, action, expected]) => ({
  pr,
  id,
  category,
  oracle,
  layer,
  risk,
  action,
  expected
}));

if (suites.length !== 50 || profiles.length !== 20) {
  throw new Error(`Invalid matrix dimensions: ${suites.length} suites x ${profiles.length} profiles`);
}

export function buildPr2627To2633Cases() {
  return suites.flatMap((suite) => profiles.map((profile, profileIndex) => ({
    id: `PR${suite.pr}-${suite.id.toUpperCase()}-${String(profileIndex + 1).padStart(2, "0")}`,
    pr: suite.pr,
    suite_id: suite.id,
    category: suite.category,
    oracle: suite.oracle,
    layer: suite.layer,
    device_required: suite.layer === "device",
    profile_id: profile.id,
    variant_index: profileIndex,
    title: `${suite.id}: ${profile.id}`,
    risk: `${suite.risk}; profile: ${profile.condition}`,
    preconditions: [
      `PR #${suite.pr} implementation is installed`,
      profile.condition,
      "the case runs with an isolated case identifier"
    ],
    steps: [
      profile.action,
      suite.action,
      "capture structured result, receipt, timing, and side effects"
    ],
    expected: [
      suite.expected,
      profile.guard,
      "the case must not crash, hang, leak private data, or affect another case"
    ],
    verification: {
      automated: true,
      runner: "SM-G9880 Android instrumentation",
      oracle: suite.oracle,
      required_evidence: ["assertion result", "duration_ms", "failure detail when present"]
    }
  })));
}

export function buildPr2627To2633Corpus() {
  const cases = buildPr2627To2633Cases();
  return {
    schema_version: 1,
    benchmark_id: "signalasi-pr2627-pr2633-targeted-1000-v1",
    generated_from: "50 risk suites x 20 distinct environment/fault profiles",
    target_device: "SM-G9880",
    exact_case_count: 1000,
    pull_requests: [2627, 2628, 2629, 2630, 2631, 2632, 2633],
    cases
  };
}

export { profiles, suites };
