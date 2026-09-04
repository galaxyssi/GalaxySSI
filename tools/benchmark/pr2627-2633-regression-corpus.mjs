const profiles = [
  ["fresh-start", "fresh process with empty transient state", "start from a cold App process", "no stale state may affect the result", "冷启动空状态", "从完全冷启动且无临时状态开始", "冷启动后执行目标能力", "不得受到旧状态污染"],
  ["warm-state", "warm process with initialized services", "repeat after one successful operation", "warm state must preserve the same contract", "热启动已初始化", "服务已经初始化且刚成功运行过一次", "在热状态下重复目标能力", "热状态必须保持相同契约"],
  ["duplicate-input", "the same logical input is submitted twice", "repeat the identical request", "deduplication must prevent duplicate work or records", "重复输入", "同一逻辑输入连续提交两次", "重复提交完全相同的输入", "去重必须阻止重复工作或记录"],
  ["reordered-input", "equivalent inputs arrive in reverse order", "reverse candidate or event order", "ordering differences must not corrupt identity or ranking", "输入乱序", "等价输入以相反顺序到达", "反转候选项或事件顺序", "乱序不得破坏身份、排序或结果"],
  ["single-failure", "one dependency fails while peers remain healthy", "inject one isolated failure", "healthy work must complete and expose the failed receipt", "单点失败", "一个依赖失败而其他依赖正常", "注入一个隔离故障", "正常分支必须完成并暴露失败回执"],
  ["partial-failure", "half of the dependencies fail independently", "inject failures into alternating candidates", "partial evidence must remain usable and failures visible", "部分失败", "一半依赖分别失败", "向交替候选项注入故障", "可用部分必须保留且失败必须可见"],
  ["late-timeout", "the lowest-ranked operation reaches its deadline", "delay the final candidate beyond its budget", "completed higher-ranked work must be retained", "尾部超时", "最低优先级操作达到截止时间", "让最后一个候选项超过预算", "已完成的高优先级结果必须保留"],
  ["early-timeout", "the highest-ranked operation reaches its deadline", "delay the first candidate beyond its budget", "later independent work must still be considered", "首项超时", "最高优先级操作达到截止时间", "让第一个候选项超过预算", "后续独立工作仍必须继续评估"],
  ["cancel-before", "cancellation is requested before execution", "cancel before invoking the operation", "no durable side effect may be produced", "执行前取消", "执行开始前收到取消请求", "调用目标能力前取消", "不得产生持久化副作用"],
  ["cancel-during", "cancellation arrives after work starts", "cancel at the first checkpoint", "workers must stop and report cancellation coherently", "执行中取消", "工作开始后收到取消请求", "在第一个检查点取消", "工作线程必须停止并一致报告取消"],
  ["offline", "network becomes unavailable", "execute with network unavailable", "cached or local behavior must remain deterministic", "离线", "执行期间网络不可用", "在断网状态执行目标能力", "缓存或本地行为必须确定且可解释"],
  ["same-host-redirect", "the source redirects within the same host", "return a same-host resolved URL", "the requested identity must remain addressable", "同站重定向", "来源在同一主机内重定向", "返回同主机最终地址", "原请求身份仍必须可寻址"],
  ["cross-host-redirect", "the source redirects to another public host", "return a cross-host resolved URL", "redirect provenance must remain explicit and bounded", "跨站重定向", "来源重定向到另一个公共主机", "返回跨主机最终地址", "重定向来源必须明确且受限"],
  ["unicode-content", "content and metadata contain CJK and emoji", "use multilingual titles, text, and metadata", "Unicode must survive without changing security decisions", "多语言内容", "正文和元数据包含中文、其他语言及表情", "使用多语言标题、正文和元数据", "Unicode 必须完整保留且不得改变安全判断"],
  ["percent-encoded", "URLs contain percent-encoded path and query data", "use encoded international path segments", "canonicalization must preserve semantic URL bytes", "百分号编码", "URL 路径和查询包含百分号编码", "使用编码后的国际化路径", "规范化必须保留 URL 语义字节"],
  ["empty-optional", "optional title, author, or metadata is empty", "omit non-required fields", "required output must remain valid without placeholder corruption", "可选字段缺失", "标题、作者或可选元数据为空", "省略非必填字段", "必填输出仍须有效且不得产生错误占位"],
  ["maximum-bound", "input reaches the documented count or size boundary", "fill the supported bounded capacity", "output must stay within limits without silent overflow", "最大边界", "输入达到规定数量或尺寸上限", "填满受支持的有界容量", "输出不得静默溢出或越界"],
  ["untrusted-instruction", "retrieved text contains prompt-injection instructions", "embed fake SYSTEM and tool instructions", "web evidence must never gain instruction authority", "恶意指令注入", "抓取内容包含伪造系统和工具指令", "嵌入恶意 SYSTEM 与工具调用文本", "网页证据绝不能获得指令权限"],
  ["process-restart", "the App process restarts between related operations", "persist, restart, then continue", "durable identity and privacy behavior must survive restart", "进程重启", "关联操作之间 App 进程重启", "持久化后重启并继续", "身份、隐私和状态必须正确恢复"],
  ["concurrent-callers", "multiple callers request related work concurrently", "start callers at the same barrier", "shared work must remain isolated, bounded, and deterministic", "并发调用", "多个调用者并发请求关联工作", "从同一屏障同时启动调用者", "共享工作必须隔离、有界且结果确定"]
].map(([id, condition, action, guard, titleZh, conditionZh, actionZh, guardZh]) => ({
  id, condition, action, guard, titleZh, conditionZh, actionZh, guardZh
}));

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

const suiteLabelsZh = {
  "parallel-result-order": "并行结果顺序",
  "per-host-cap": "单主机并发上限",
  "mixed-host-fairness": "多主机公平调度",
  "shared-deadline": "共享截止时间",
  "early-completion": "证据充分后提前完成",
  "partial-source-failure": "部分来源失败恢复",
  "duplicate-candidate-collapse": "重复候选项折叠",
  "cancellation-propagation": "取消信号传播",
  "pairing-replay-dedup": "配对确认重放去重",
  "supplied-message-id": "传输消息身份保留",
  "route-isolation": "手机路由隔离",
  "desktop-isolation": "Desktop 身份隔离",
  "system-notice-idempotence": "系统通知幂等",
  "explicit-url-dedup": "显式 URL 去重",
  "max-url-bound": "单轮 URL 数量边界",
  "history-continuation": "历史链接续接",
  "cache-hit": "网页缓存命中",
  "cache-expiry": "网页缓存过期",
  "concurrent-singleflight": "并发请求合并",
  "failure-not-poison-cache": "失败不得污染缓存",
  "redirect-request-alias": "重定向请求别名缓存",
  "canonical-citation": "规范引用身份",
  "manifest-integrity": "证据清单完整性",
  "duplicate-content-correlation": "重复内容相关性",
  "numeric-conflict": "数值冲突识别",
  "cross-client-url-normalization": "跨端 URL 规范化",
  "bounded-pack-json": "证据包上下文边界",
  "untrusted-evidence-boundary": "不可信证据权限边界",
  "wechat-mobile-headers": "微信公众号移动请求头",
  "generic-host-no-special-header": "普通网站请求头隔离",
  "structured-wechat-parse": "微信公众号正文解析",
  "generic-jsonld-parse": "通用 JSON-LD 文章解析",
  "challenge-detection": "挑战页识别",
  "static-success-no-render": "静态正文免渲染",
  "renderer-failure-isolation": "渲染器失败隔离",
  "background-event-lightweight": "后台事件轻量认知",
  "scheduled-bounded-cycle": "定时认知循环边界",
  "idle-four-hour-cap": "空闲调度上限",
  "active-ten-minute-cadence": "活跃任务调度频率",
  "secret-knowledge-block": "敏感知识阻断",
  "safe-knowledge-project": "安全知识投影",
  "metadata-token-block": "元数据令牌阻断",
  "transcript-redaction": "私密对话脱敏",
  "model-semantic-tool-policy": "模型语义工具决策",
  "dsml-tool-call-parse": "DSML 工具调用解析",
  "normal-text-preservation": "普通回答文本保留",
  "citation-required": "网页结论引用要求",
  "foreign-citation-rejected": "外部伪造引用拒绝",
  "tampered-citation-id": "篡改引用身份检测",
  "one-repair-only": "引用修复次数边界"
};

if (suites.length !== 50 || profiles.length !== 20 || Object.keys(suiteLabelsZh).length !== 50) {
  throw new Error(`Invalid matrix dimensions: ${suites.length} suites x ${profiles.length} profiles`);
}

export function buildPr2627To2633Cases() {
  return suites.flatMap((suite, suiteIndex) => profiles.map((profile, profileIndex) => {
    const ordinal = suiteIndex * profiles.length + profileIndex + 1;
    const paddedOrdinal = String(ordinal).padStart(4, "0");
    const labelZh = suiteLabelsZh[suite.id];
    return {
      id: `PR${suite.pr}-${suite.id.toUpperCase()}-${String(profileIndex + 1).padStart(2, "0")}`,
      ordinal,
      risk_id: `RISK-${paddedOrdinal}`,
      conversation_id: `regression-pr2627-pr2633-${paddedOrdinal}`,
      pr: suite.pr,
      suite_id: suite.id,
      category: suite.category,
      oracle: suite.oracle,
      layer: suite.layer,
      device_required: suite.layer === "device",
      profile_id: profile.id,
      variant_index: profileIndex,
      title: `${suite.id}: ${profile.id}`,
      title_zh: `${paddedOrdinal} · ${labelZh} · ${profile.titleZh}`,
      risk: `${suite.risk}; profile: ${profile.condition}`,
      risk_zh: `${labelZh}在“${profile.conditionZh}”场景下可能违反生产契约。`,
      preconditions: [
        `PR #${suite.pr} implementation is installed`,
        profile.condition,
        "the case runs with an isolated case identifier"
      ],
      preconditions_zh: [
        `已在 SM-G9880 安装包含 PR #${suite.pr} 的待测版本`,
        profile.conditionZh,
        `使用独立风险身份 RISK-${paddedOrdinal}，不复用其他用例状态`
      ],
      steps: [
        profile.action,
        suite.action,
        "capture structured result, receipt, timing, and side effects"
      ],
      steps_zh: [
        profile.actionZh,
        `执行“${labelZh}”对应的真实生产代码断言`,
        "记录断言结果、耗时、失败详情和持久化副作用"
      ],
      expected: [
        suite.expected,
        profile.guard,
        "the case must not crash, hang, leak private data, or affect another case"
      ],
      expected_zh: [
        `“${labelZh}”生产契约必须成立`,
        profile.guardZh,
        "不得崩溃、卡死、泄漏私密数据或影响其他测试会话"
      ],
      verification: {
        automated: true,
        runner: "SM-G9880 Android instrumentation",
        oracle: suite.oracle,
        required_evidence: ["assertion result", "duration_ms", "failure detail when present"]
      }
    };
  }));
}

export function buildPr2627To2633Corpus() {
  const cases = buildPr2627To2633Cases();
  return {
    schema_version: 2,
    benchmark_id: "galaxyssi-pr2627-pr2633-visible-1000-v2",
    generated_from: "1000 individually addressable production-risk scenarios",
    target_device: "SM-G9880",
    exact_case_count: 1000,
    exact_conversation_count: 1000,
    pull_requests: [2627, 2628, 2629, 2630, 2631, 2632, 2633],
    cases
  };
}

export { profiles, suites, suiteLabelsZh };
