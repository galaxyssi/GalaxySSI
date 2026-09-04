package com.signalasi.chat

object AgentEvalBenchmarkCatalog {
    val standard: AgentBenchmarkSuite by lazy {
        AgentBenchmarkSuite(
            id = "signalasi-android-real-agent",
            version = "1.2.0",
            title = "SignalASI Android Real Agent EvalOps",
            cases = taskQualityCases() + planningCases() + androidWorldCases() +
                immediateMemoryCases() + recoveryCases() + multiAgentCases(),
            targetPassRate = 0.95
        )
    }

    val longitudinalMemory: AgentBenchmarkSuite by lazy {
        AgentBenchmarkSuite(
            id = "signalasi-android-longitudinal-memory",
            version = "1.0.0",
            title = "SignalASI Android 30/90-day Memory Certification",
            cases = longTermMemoryCases(),
            targetPassRate = 0.95,
            minimumTaskCount = 10,
            maximumTaskCount = 10
        )
    }

    val suites: List<AgentBenchmarkSuite> by lazy { listOf(standard, longitudinalMemory) }

    fun suite(id: String, version: String): AgentBenchmarkSuite? = suites.firstOrNull {
        it.id == id && it.version == version
    }

    private fun taskQualityCases() = listOf(
        quality("quality-01", "多步算术", "计算 (17 × 23) - (144 ÷ 12)，只给出最终整数。", "^379$"),
        quality("quality-02", "约束排序", "将 9、2、5、2、1 升序排列，使用 JSON 数组输出，不要解释。", "^\\[\\s*1\\s*,\\s*2\\s*,\\s*2\\s*,\\s*5\\s*,\\s*9\\s*]$"),
        qualityJson(
            "quality-03",
            "结构化输出",
            "只输出有效 JSON 对象，status 必须为 ready，count 必须为 3。",
            mapOf("status" to "ready", "count" to "3")
        ),
        quality("quality-04", "依赖路径", "任务 A 用2分钟；B在A后用3分钟；C在A后用4分钟；D要等B和C后用1分钟。给出最短总时长和关键路径。", "(?s)(7\\s*分钟|7\\s*min).*(A.*C.*D)"),
        quality("quality-05", "加权评分", "三个指标权重为0.5、0.3、0.2，得分为80、90、70。计算加权总分，只输出数字。", "^81$"),
        quality("quality-06", "条件推理", "所有蓝盒都很重；盒子K不重。K是否可能是蓝盒？只回答‘不可能’并给出一句理由。", "(?s)^不可能.*(蓝盒.*重|不重.*蓝盒)"),
        qualityJson(
            "quality-07",
            "信息抽取",
            "从‘设备SM-T575，Android 13，内存4GB’提取 device、os、ram，只输出一行JSON。",
            mapOf("device" to "SM-T575", "os" to "Android 13", "ram" to "4GB")
        ),
        quality("quality-08", "单位换算", "1.5 GiB 等于多少 MiB？只输出数字。", "^1536$"),
        quality("quality-09", "去重统计", "事件序列[a,b,a,c,b,d]中有多少个不同事件？列出数量和按首次出现顺序的事件。", "(?s)(4).*(a.*b.*c.*d)"),
        quality(
            "quality-10",
            "冲突识别",
            "记录1：屏幕理解已启用。记录2（时间更晚）：屏幕理解已移除。当前状态是什么？",
            "(?s)(?=.*(?:已移除|移除))(?=.*(?:记录2|更新|较晚|更晚|最新)).*"
        )
    )

    private fun planningCases() = listOf(
        planning("plan-tool-01", "设备版本核验", "先列出简短计划，再使用可用工具核验当前设备型号和 Android 版本，最后给出工具证据。"),
        planning("plan-tool-02", "应用版本核验", "先规划，再使用工具读取当前 SignalASI 的版本名称和版本号，最后报告证据。"),
        planning("plan-tool-03", "网络状态核验", "先规划，再使用工具检查当前网络是否可用及是否已验证，最后给出结论和证据。"),
        planning("plan-tool-04", "电池状态核验", "先规划，再使用工具读取电量、充电状态和温度，最后报告工具证据。"),
        planning("plan-tool-05", "存储状态核验", "先规划，再使用工具读取应用可用存储空间，最后给出数值和证据。"),
        planning("plan-tool-06", "时间核验", "先规划，再调用可信时间工具获取当前本地日期和时区，最后说明工具来源。"),
        planning("plan-tool-07", "文件完整性", "先规划，再在允许的测试目录创建文本文件、读取验证并计算 SHA-256，最后给出摘要。"),
        planning("plan-tool-08", "失败恢复", "先规划，尝试一个无副作用的工具检查；若失败则调整一次方案，最后报告每一步结果。"),
        planning("plan-tool-09", "多来源调研", "先规划，再使用检索工具查找两份一手资料，交叉验证后给出带来源的结论。", sources = true),
        planning("plan-tool-10", "产物验证", "先规划，生成一个小型 JSON 产物，使用工具验证其可解析性，最后报告验证结果。")
    )

    private fun androidWorldCases() = listOf(
        world("android-world-01", "前台应用", "确认 SignalASI 当前位于前台，并报告其包名。"),
        world("android-world-02", "Android ID", "读取并报告当前设备的 Android ID。"),
        world("android-world-03", "屏幕亮度", "读取并报告当前系统屏幕亮度数值。"),
        world("android-world-04", "息屏时间", "读取并报告当前系统息屏超时毫秒数。"),
        world("android-world-05", "飞行模式", "读取并报告当前飞行模式状态值。"),
        world("android-world-06", "无障碍状态", "读取并报告当前无障碍总开关状态值。"),
        world("android-world-07", "自动旋转", "读取并报告当前自动旋转状态值。"),
        world("android-world-08", "字体比例", "读取并报告当前系统字体比例。"),
        world("android-world-09", "定位模式", "读取并报告当前系统定位模式值。"),
        world("android-world-10", "省电模式", "读取并报告当前系统低电量模式状态值。")
    )

    private fun immediateMemoryCases() = listOf(
        immediateMemory("immediate-memory-01", "即时身份记忆", "从跨会话即时记忆回答 IM-01 的值；只输出记住的值。", "SASI-IM-NOVA"),
        immediateMemory("immediate-memory-02", "即时偏好记忆", "从跨会话即时记忆回答 IM-02 的值；只输出记住的值。", "SASI-IM-DARK"),
        immediateMemory("immediate-memory-03", "即时设备记忆", "从跨会话即时记忆回答 IM-03 的值；只输出记住的值。", "SASI-IM-TABLET"),
        immediateMemory("immediate-memory-04", "即时项目记忆", "从跨会话即时记忆回答 IM-04 的值；只输出记住的值。", "SASI-IM-PROJECT"),
        immediateMemory("immediate-memory-05", "即时知识记忆", "从跨会话即时记忆回答 IM-05 的值；只输出记住的值。", "SASI-IM-KNOWLEDGE"),
        immediateMemory("immediate-memory-06", "即时工作流记忆", "从跨会话即时记忆回答 IM-06 的值；只输出记住的值。", "SASI-IM-WORKFLOW"),
        immediateMemory("immediate-memory-07", "即时决策记忆", "从跨会话即时记忆回答 IM-07 的值；只输出记住的值。", "SASI-IM-DECISION"),
        immediateMemory("immediate-memory-08", "记忆更新", "回答 IM-08 当前有效的值；不要返回已经被替代的旧值。", "SASI-IM-CURRENT", "SASI-IM-OLD"),
        immediateMemory("immediate-memory-09", "实体消歧", "只回答属于 IM-09-B 的记忆值，不要混入 IM-09-A。", "SASI-IM-BETA", "SASI-IM-ALPHA"),
        immediateMemory("immediate-memory-10", "来源追踪", "从带来源的跨会话即时记忆回答 IM-10 的值；只输出记住的值。", "SASI-IM-PROVENANCE")
    )

    private fun longTermMemoryCases() = listOf(
        memory("memory-30-01", "30天身份记忆", "从长期记忆回答测试夹具 M30-01 的值；不要猜测。", 30, "SASI-M30-ALPHA"),
        memory("memory-30-02", "30天偏好记忆", "从长期记忆回答测试夹具 M30-02 的值；不要猜测。", 30, "SASI-M30-BRAVO"),
        memory("memory-30-03", "30天设备记忆", "从长期记忆回答测试夹具 M30-03 的值；不要猜测。", 30, "SASI-M30-CHARLIE"),
        memory("memory-30-04", "30天项目记忆", "从长期记忆回答测试夹具 M30-04 的值；不要猜测。", 30, "SASI-M30-DELTA"),
        memory("memory-30-05", "30天决策记忆", "从长期记忆回答测试夹具 M30-05 的值；不要猜测。", 30, "SASI-M30-ECHO"),
        memory("memory-90-01", "90天身份记忆", "从长期记忆回答测试夹具 M90-01 的值；不要猜测。", 90, "SASI-M90-FOXTROT"),
        memory("memory-90-02", "90天偏好记忆", "从长期记忆回答测试夹具 M90-02 的值；不要猜测。", 90, "SASI-M90-GOLF"),
        memory("memory-90-03", "90天设备记忆", "从长期记忆回答测试夹具 M90-03 的值；不要猜测。", 90, "SASI-M90-HOTEL"),
        memory("memory-90-04", "90天项目记忆", "从长期记忆回答测试夹具 M90-04 的值；不要猜测。", 90, "SASI-M90-INDIA"),
        memory("memory-90-05", "90天更新记忆", "从长期记忆回答测试夹具 M90-05 当前有效的值；不要返回已废弃值。", 90, "SASI-M90-JULIET")
    )

    private fun immediateMemory(
        id: String,
        title: String,
        prompt: String,
        expected: String,
        forbidden: String = ""
    ) = AgentBenchmarkCase(
        id,
        AgentBenchmarkDimension.IMMEDIATE_MEMORY,
        title,
        prompt,
        AgentBenchmarkExpectation(
            requiredOutputPatterns = listOf(Regex.escape(expected)),
            forbiddenOutputPatterns = forbidden.takeIf(String::isNotBlank)?.let(Regex::escape)?.let(::listOf)
                ?: emptyList(),
            requiredEvidence = setOf(
                AgentOutcomeEvidenceKind.FINAL_RESPONSE,
                AgentOutcomeEvidenceKind.MEMORY_PROVENANCE
            )
        )
    )

    private fun recoveryCases() = listOf(
        recovery("recovery-network-01", "断网恢复1", "完成可靠性回声任务；测试期间会发生一次断网，恢复后只返回一次 RECOVERED-NET-01。", AgentEvalCondition.NETWORK_LOSS, "RECOVERED-NET-01"),
        recovery("recovery-network-02", "断网恢复2", "保存检查点并完成任务；测试期间会发生网络中断，恢复后只返回一次 RECOVERED-NET-02。", AgentEvalCondition.NETWORK_LOSS, "RECOVERED-NET-02"),
        recovery("recovery-network-03", "断网恢复3", "执行可恢复任务；测试期间会断网，恢复后只返回一次 RECOVERED-NET-03。", AgentEvalCondition.NETWORK_LOSS, "RECOVERED-NET-03"),
        recovery("recovery-process-01", "进程死亡恢复1", "保存检查点；测试期间会发生进程死亡，恢复后只返回一次 RECOVERED-PROC-01。", AgentEvalCondition.PROCESS_DEATH, "RECOVERED-PROC-01"),
        recovery("recovery-process-02", "进程死亡恢复2", "执行可恢复任务；测试期间会杀进程，恢复后只返回一次 RECOVERED-PROC-02。", AgentEvalCondition.PROCESS_DEATH, "RECOVERED-PROC-02"),
        recovery("recovery-process-03", "进程死亡恢复3", "保持幂等；测试期间会进程死亡，恢复后只返回一次 RECOVERED-PROC-03。", AgentEvalCondition.PROCESS_DEATH, "RECOVERED-PROC-03"),
        recovery("recovery-doze-01", "Doze恢复1", "测试期间设备会进入 Doze，退出后只返回一次 RECOVERED-DOZE-01。", AgentEvalCondition.DOZE, "RECOVERED-DOZE-01"),
        recovery("recovery-doze-02", "Doze恢复2", "保存检查点并等待设备休眠，退出待机后只返回一次 RECOVERED-DOZE-02。", AgentEvalCondition.DOZE, "RECOVERED-DOZE-02"),
        recovery("recovery-reboot-01", "重启恢复1", "测试期间设备会重启，恢复后只返回一次 RECOVERED-BOOT-01。", AgentEvalCondition.REBOOT, "RECOVERED-BOOT-01"),
        recovery("recovery-reboot-02", "重启恢复2", "保持任务幂等；测试期间会重启手机，恢复后只返回一次 RECOVERED-BOOT-02。", AgentEvalCondition.REBOOT, "RECOVERED-BOOT-02")
    )

    private fun multiAgentCases() = listOf(
        multi("multi-agent-01", "实现与审查", "至少让两个不同 Agent 协作：一个提出实现方案，一个独立审查，最后合并结论。"),
        multi("multi-agent-02", "研究与反证", "至少让两个不同 Agent 协作：一个给出研究结论，一个寻找反例，最后合并结论。"),
        multi("multi-agent-03", "计划与风险", "至少让两个不同 Agent 协作：一个拆解计划，一个审查风险，最后合并结论。"),
        multi("multi-agent-04", "编码与测试", "至少让两个不同 Agent 协作：一个设计代码，一个独立设计测试，最后合并结论。"),
        multi("multi-agent-05", "性能与UX", "至少让两个不同 Agent 协作：一个分析性能，一个分析UX，最后合并优先级。"),
        multi("multi-agent-06", "安全双审", "至少让两个不同 Agent 独立分析同一安全方案，指出共识与分歧。"),
        multi("multi-agent-07", "双阶段评审", "让两个不同 Agent 分别负责方案与独立反驳，最后只给一份经过复核的综合结论。"),
        multi("multi-agent-08", "模型盲测", "至少让两个不同 Agent 独立回答，再隐藏身份比较结果并给出选择依据。"),
        multi("multi-agent-09", "故障诊断", "至少让两个不同 Agent 协作：一个定位根因，一个验证修复不会回归。"),
        multi("multi-agent-10", "证据合并", "至少让两个不同 Agent 各自提供证据，去重并输出可追溯的统一结论。")
    )

    private fun quality(id: String, title: String, prompt: String, pattern: String) = AgentBenchmarkCase(
        id, AgentBenchmarkDimension.TASK_QUALITY, title, prompt,
        AgentBenchmarkExpectation(requiredOutputPatterns = listOf(pattern), minimumOutputChars = 1)
    )

    private fun qualityJson(
        id: String,
        title: String,
        prompt: String,
        fields: Map<String, String>
    ) = AgentBenchmarkCase(
        id, AgentBenchmarkDimension.TASK_QUALITY, title, prompt,
        AgentBenchmarkExpectation(requiredJsonFields = fields, minimumOutputChars = 1)
    )

    private fun planning(id: String, title: String, prompt: String, sources: Boolean = false) = AgentBenchmarkCase(
        id, AgentBenchmarkDimension.PLANNING_AND_TOOLS, title, prompt,
        AgentBenchmarkExpectation(
            minimumOutputChars = 20,
            minimumPlanEvents = 1,
            minimumToolReceipts = 1,
            requiredEvidence = buildSet {
                add(AgentOutcomeEvidenceKind.FINAL_RESPONSE)
                add(AgentOutcomeEvidenceKind.TOOL_RECEIPT)
                if (sources) add(AgentOutcomeEvidenceKind.VERIFIED_SOURCE)
            },
            minimumVerifiedSources = if (sources) 2 else 0
        )
    )

    private fun world(id: String, title: String, prompt: String) = AgentBenchmarkCase(
        id, AgentBenchmarkDimension.ANDROID_WORLD, title, prompt,
        AgentBenchmarkExpectation(
            minimumOutputChars = 1,
            requiredEvidence = setOf(
                AgentOutcomeEvidenceKind.FINAL_RESPONSE,
                AgentOutcomeEvidenceKind.PROGRAMMATIC_VERIFIER
            ),
            androidWorldTaskId = id,
            requireAndroidObservedValuesInOutput = true
        )
    )

    private fun memory(id: String, title: String, prompt: String, days: Int, expected: String) = AgentBenchmarkCase(
        id,
        AgentBenchmarkDimension.LONG_TERM_MEMORY,
        title,
        "$prompt 只允许使用至少${days}天前写入且带来源的记忆。",
        AgentBenchmarkExpectation(
            requiredOutputPatterns = listOf(Regex.escape(expected)),
            memoryHorizonDays = days,
            requiredEvidence = setOf(
                AgentOutcomeEvidenceKind.FINAL_RESPONSE,
                AgentOutcomeEvidenceKind.MEMORY_PROVENANCE
            )
        )
    )

    private fun recovery(
        id: String,
        title: String,
        prompt: String,
        condition: AgentEvalCondition,
        expected: String
    ) = AgentBenchmarkCase(
        id, AgentBenchmarkDimension.RECOVERY, title, prompt,
        AgentBenchmarkExpectation(
            requiredOutputPatterns = listOf(Regex.escape(expected)),
            forbiddenOutputPatterns = listOf("(?s)(${Regex.escape(expected)}.*){2,}"),
            requiredCondition = condition,
            requiredEvidence = setOf(
                AgentOutcomeEvidenceKind.FINAL_RESPONSE,
                AgentOutcomeEvidenceKind.RECOVERY_EVENT
            )
        )
    )

    private fun multi(id: String, title: String, prompt: String, agents: Int = 2) = AgentBenchmarkCase(
        id, AgentBenchmarkDimension.MULTI_AGENT, title, prompt,
        AgentBenchmarkExpectation(
            minimumOutputChars = 40,
            minimumDistinctAgents = agents,
            minimumHandoffs = agents - 1,
            requiredEvidence = setOf(AgentOutcomeEvidenceKind.FINAL_RESPONSE)
        )
    )
}
