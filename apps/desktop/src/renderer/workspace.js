const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => Array.from(document.querySelectorAll(selector));

const TERMINAL_STATES = new Set(["completed", "failed", "cancelled", "timed_out"]);
const DEFAULT_AGENT_CONTACTS = [
  ["codex", "Codex", "local-cli"],
  ["hermes", "Hermes", "local-cli"],
  ["claude", "Claude Code", "local-cli"],
  ["openclaw", "OpenClaw", "local-cli"],
  ["local-llm", "Local LLM", "local-model"]
].map(([id, name, kind]) => ({ id, name, kind, status: "checking", detail: "Checking" }));
const CLOUD_PROVIDER_PRESETS = Object.freeze({
  openai: {
    name: "OpenAI",
    endpoint: "https://api.openai.com/v1/chat/completions"
  },
  deepseek: {
    name: "DeepSeek",
    endpoint: "https://api.deepseek.com/chat/completions"
  },
  qwen: {
    name: "Qwen",
    endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
  },
  openrouter: {
    name: "OpenRouter",
    endpoint: "https://openrouter.ai/api/v1/chat/completions"
  },
  custom: {
    name: "Cloud Model",
    endpoint: ""
  }
});
const LANGUAGE_POLICY_CHOICES = new Set(["auto", "zh-CN", "en-US", "zh-HK", "zh-TW"]);

function normalizeLanguagePolicy(value) {
  const candidate = String(value || "").trim();
  return LANGUAGE_POLICY_CHOICES.has(candidate) ? candidate : "auto";
}

function systemLanguageTag() {
  const language = String(navigator.language || "en-US").replace("_", "-").toLowerCase();
  if (language.startsWith("zh-hk") || language.startsWith("zh-mo")) return "zh-HK";
  if (language.startsWith("zh-tw") || language.startsWith("zh-hant")) return "zh-TW";
  if (language.startsWith("zh")) return "zh-CN";
  return "en-US";
}

function resolveLanguagePolicy(value) {
  const normalized = normalizeLanguagePolicy(value);
  return normalized === "auto" ? systemLanguageTag() : normalized;
}

const savedInterfaceLanguage = localStorage.getItem("signalasi-desktop-language") || "auto";
const state = {
  languagePreference: ["auto", "en", "zh-CN"].includes(savedInterfaceLanguage) ? savedInterfaceLanguage : "auto",
  language: savedInterfaceLanguage === "zh-CN" || (savedInterfaceLanguage === "auto" && systemLanguageTag().startsWith("zh")) ? "zh-CN" : "en",
  locale: {},
  backend: null,
  agents: DEFAULT_AGENT_CONTACTS,
  agentConfig: null,
  pairing: null,
  pairingGrantDesktopExecutor: false,
  desktopControl: null,
  memory: { memories: [], stats: {} },
  skills: [],
  mcp: [],
  proactiveTasks: [],
  proactiveRuns: [],
  selectedProactiveTaskId: "",
  editingProactiveTaskId: "",
  runtime: { summary: {}, runtimes: [], error: "" },
  commands: { catalog_size: 0, roots: [], commands: [] },
  commandRuns: [],
  evolutionTasks: [],
  evolutionHealth: null,
  tasks: [],
  currentConversationId: crypto.randomUUID(),
  selectedAgentId: "auto",
  selectedAgentName: "Agent",
  attachments: [],
  renderingSignature: "",
  polling: false,
  taskStream: null,
  taskStreamConnected: false,
  taskStreamReconnectTimer: 0,
  emptyConversationIntent: false,
  toastTimer: 0,
  speechRecognition: null,
  agentRefreshPromise: null
};

const elements = {
  history: $("#taskHistory"),
  title: $("#conversationTitle"),
  taskState: $("#taskStateText"),
  route: $("#routeText"),
  stream: $("#conversationStream"),
  empty: $("#emptyState"),
  messages: $("#messageList"),
  prompt: $("#promptInput"),
  send: $("#sendButton"),
  attachments: $("#attachmentTray"),
  selectedAgent: $("#selectedAgentLabel"),
  agentCount: $("#agentCount"),
  capabilityCount: $("#capabilityCount"),
  gatewayCount: $("#gatewayCount"),
  desktopVersion: $("#desktopVersion"),
  backendBadge: $("#backendBadge"),
  backendDetail: $("#backendDetail"),
  drawer: $("#utilityDrawer"),
  backdrop: $("#drawerBackdrop"),
  drawerTitle: $("#drawerTitle"),
  drawerSubtitle: $("#drawerSubtitle"),
  toast: $("#toast")
};

function t(key, params = {}) {
  let value = state.locale[key] || key;
  for (const [name, replacement] of Object.entries(params)) {
    value = value.replaceAll(`{${name}}`, String(replacement));
  }
  return value;
}

window.signalasiDesktopI18n = Object.freeze({
  translate: (key, params = {}) => t(key, params),
  language: () => state.language
});

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatBytes(value) {
  const size = Number(value || 0);
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / 1024 / 1024).toFixed(1)} MB`;
}

function formatDuration(value) {
    const seconds = Math.max(1, Math.floor(Number(value || 0) / 1000));
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    const remainder = seconds % 60;
    if (minutes < 60) return `${minutes}m ${remainder}s`;
    const hours = Math.floor(minutes / 60);
    return `${hours}h ${minutes % 60}m ${remainder}s`;
}

function formatLatency(value) {
  const milliseconds = Math.max(0, Number(value || 0));
  if (milliseconds < 1000) return `${Math.round(milliseconds)}ms`;
  if (milliseconds < 10_000) return `${(milliseconds / 1000).toFixed(1)}s`;
  return formatDuration(milliseconds);
}

function relativeTime(timestamp) {
  const delta = Math.max(0, Date.now() - Number(timestamp || Date.now()));
  if (delta < 60_000) return t("Just now");
  if (delta < 3_600_000) return t("{count} min ago", { count: Math.floor(delta / 60_000) });
  if (delta < 86_400_000) return t("{count} hr ago", { count: Math.floor(delta / 3_600_000) });
  return new Date(Number(timestamp)).toLocaleDateString(state.language === "zh-CN" ? "zh-CN" : "en-US", { month: "short", day: "numeric" });
}

function titleFromPrompt(prompt) {
  const clean = String(prompt || t("Attached files")).replace(/\s+/g, " ").trim();
  return clean.length > 42 ? `${clean.slice(0, 42)}...` : clean;
}

function statusLabel(status) {
  const labels = {
    accepted: "Accepted",
    queued: "Queued",
    running: "Running",
    completed: "Completed",
    failed: "Failed",
    cancelled: "Cancelled",
    timed_out: "Timed out"
  };
  return t(labels[status] || status || "Ready");
}

function taskStatusLabel(task) {
  if (task?.task_kind !== "self_evolution") return statusLabel(task?.status);
  const labels = {
    proposed: "Preparing",
    preparing: "Preparing",
    running: "Running",
    validating: "Validating",
    waiting_approval: "Candidate ready",
    publishing: "Publishing",
    published: "Pull request created",
    blocked: "Needs attention",
    failed: "Failed",
    cancelled: "Cancelled",
    rolled_back: "Rolled back"
  };
  return t(labels[task.evolution_status] || statusLabel(task.status));
}

function agentName(agentId) {
  if (!agentId || agentId === "auto") return t("Agent");
  if (agentId.startsWith("mcp:")) {
    const connection = state.mcp.find((item) => item.id === agentId.slice(4));
    return connection?.name || agentId.slice(4);
  }
  return state.agents.find((agent) => (agent.mobile_contact_id || agent.id) === agentId)?.name
    || ({ desktop: "SignalASI Desktop", "self-evolution": t("Self-evolution"), codex: "Codex", hermes: "Hermes", claude: "Claude Code", openclaw: "OpenClaw", "local-llm": "Local LLM" })[agentId]
    || agentId;
}

function taskRouteName(task) {
  if (!task) return t("Automatic routing");
  const primary = agentName(task.agent_id);
  return task.delegate_agent_id ? `${primary} · ${agentName(task.delegate_agent_id)}` : primary;
}

function applyInlineMarkup(value) {
  return value
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" data-external-link="$2">$1</a>');
}

function renderMarkdown(value) {
  const escaped = escapeHtml(value).replace(/\r\n/g, "\n");
  const chunks = escaped.split(/```/);
  return chunks.map((chunk, index) => {
    if (index % 2 === 1) {
      const lines = chunk.replace(/^\w+\n/, "").replace(/\n$/, "");
      return `<pre><code>${lines}</code></pre>`;
    }
    const lines = chunk.split("\n");
    const output = [];
    let listType = "";
    const closeList = () => {
      if (listType) output.push(`</${listType}>`);
      listType = "";
    };
    for (const line of lines) {
      const bullet = line.match(/^\s*[-*]\s+(.+)$/);
      const numbered = line.match(/^\s*\d+[.)]\s+(.+)$/);
      if (bullet || numbered) {
        const nextType = bullet ? "ul" : "ol";
        if (listType !== nextType) {
          closeList();
          listType = nextType;
          output.push(`<${nextType}>`);
        }
        output.push(`<li>${applyInlineMarkup((bullet || numbered)[1])}</li>`);
        continue;
      }
      closeList();
      if (!line.trim()) continue;
      if (line.startsWith("### ")) output.push(`<h3>${applyInlineMarkup(line.slice(4))}</h3>`);
      else if (line.startsWith("## ")) output.push(`<h2>${applyInlineMarkup(line.slice(3))}</h2>`);
      else if (line.startsWith("# ")) output.push(`<h2>${applyInlineMarkup(line.slice(2))}</h2>`);
      else output.push(`<p>${applyInlineMarkup(line)}</p>`);
    }
    closeList();
    return output.join("");
  }).join("");
}

function showToast(message) {
  window.clearTimeout(state.toastTimer);
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  state.toastTimer = window.setTimeout(() => { elements.toast.hidden = true; }, 3200);
}

async function setLanguage(language, persist = true) {
  state.languagePreference = ["auto", "en", "zh-CN"].includes(language) ? language : "auto";
  state.language = state.languagePreference === "zh-CN"
    || (state.languagePreference === "auto" && systemLanguageTag().startsWith("zh"))
    ? "zh-CN"
    : "en";
  state.locale = await window.signalasi.loadLocale(state.language);
  document.documentElement.lang = state.language === "zh-CN" ? "zh-Hans" : "en";
  if (persist) localStorage.setItem("signalasi-desktop-language", state.languagePreference);
  $$('[data-i18n]').forEach((node) => { node.textContent = t(node.dataset.i18n); });
  $$('[data-i18n-placeholder]').forEach((node) => { node.placeholder = t(node.dataset.i18nPlaceholder); });
  $("#languageSelect").value = state.languagePreference;
  renderHistory();
  renderConversation(true);
  renderEvolutionTasks();
  updateHeaderStatus();
  document.dispatchEvent(new CustomEvent("signalasi:locale-changed", {
    detail: { language: state.language }
  }));
}

function conversationTasks(conversationId = state.currentConversationId) {
  return state.tasks
    .filter((task) => task.conversation_id === conversationId)
    .sort((a, b) => Number(a.created_at) - Number(b.created_at));
}

function conversationGroups() {
  const groups = new Map();
  for (const task of [...state.tasks].sort((a, b) => Number(b.updated_at) - Number(a.updated_at))) {
    const id = task.conversation_id || task.task_id;
    if (!groups.has(id)) groups.set(id, { id, latest: task, tasks: [] });
    groups.get(id).tasks.push(task);
  }
  return Array.from(groups.values());
}

function renderHistory() {
  const groups = conversationGroups();
  if (!groups.length) {
    elements.history.innerHTML = `<div class="history-empty">${escapeHtml(t("Tasks will appear here after you send the first request."))}</div>`;
    return;
  }
  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  let currentSection = "";
  const html = [];
  for (const group of groups) {
    const section = Number(group.latest.updated_at) >= todayStart.getTime() ? "Today" : "Earlier";
    if (section !== currentSection) {
      currentSection = section;
      html.push(`<div class="history-group-label">${escapeHtml(t(section))}</div>`);
    }
    const running = group.tasks.some((task) => !TERMINAL_STATES.has(task.status));
    const latestLabel = running ? taskStatusLabel(group.latest) : relativeTime(group.latest.updated_at);
    html.push(`
      <button class="history-item ${group.id === state.currentConversationId ? "active" : ""}" data-conversation-id="${escapeHtml(group.id)}">
        <strong>${escapeHtml(titleFromPrompt(group.tasks.sort((a, b) => Number(a.created_at) - Number(b.created_at))[0]?.prompt))}</strong>
        <span class="${running ? "running" : ""}">${escapeHtml(latestLabel)}</span>
      </button>`);
  }
  elements.history.innerHTML = html.join("");
}

function taskElapsed(task) {
  const start = Number(task.started_at || task.created_at || Date.now());
  const end = Number(task.completed_at || (TERMINAL_STATES.has(task.status) ? task.updated_at : Date.now()));
  return Math.max(1000, end - start);
}

function renderArtifacts(task) {
  const files = Array.isArray(task.output_files) ? task.output_files : [];
  if (!files.length) return "";
  return `<div class="artifact-list">${files.map((file) => {
    const extension = String(file.name || "file").split(".").pop().slice(0, 5).toUpperCase();
    return `<div class="artifact-row"><div class="artifact-icon">${escapeHtml(extension)}</div><div><strong>${escapeHtml(file.name)}</strong><small>${escapeHtml(file.relative_path || "")} · ${escapeHtml(formatBytes(file.size))}</small></div><button data-open-artifact="${escapeHtml(file.relative_path || "")}" data-task-id="${escapeHtml(task.task_id)}">${escapeHtml(t("Open"))}</button></div>`;
  }).join("")}</div>`;
}

function renderLatencySummary(task) {
  const latency = task?.latency && typeof task.latency === "object" ? task.latency : null;
  const stages = Array.isArray(latency?.stages) ? latency.stages : [];
  if (!latency || !stages.length) return "";
  const rawFirstOutput = latency.first_output_ms;
  const firstOutput = Number(rawFirstOutput);
  const total = Math.max(0, Number(latency.total_ms || 0));
  return `<div class="latency-summary">
    ${rawFirstOutput != null && Number.isFinite(firstOutput) && firstOutput >= 0
      ? `<span>${escapeHtml(t("First output"))}<strong>${escapeHtml(formatLatency(firstOutput))}</strong></span>`
      : ""}
    <span>${escapeHtml(t("Traced time"))}<strong>${escapeHtml(formatLatency(total))}</strong></span>
  </div>`;
}

function renderTurn(task) {
  const statusClass = task.status === "completed" ? "completed" : (TERMINAL_STATES.has(task.status) ? "failed" : "");
  const isEvolution = task.task_kind === "self_evolution";
  const evolutionMetadata = isEvolution && (task.candidate_commit || task.pull_request_url)
    ? `<div class="evolution-result-meta">${task.candidate_commit ? `<span>${escapeHtml(t("Candidate"))} <code>${escapeHtml(task.candidate_commit.slice(0, 10))}</code></span>` : ""}${task.pull_request_url ? `<a href="${escapeHtml(task.pull_request_url)}" data-external-link="${escapeHtml(task.pull_request_url)}">${escapeHtml(t("Open pull request"))}</a>` : ""}</div>`
    : "";
  const answerText = isEvolution
    ? t(task.result || "The self-evolution run completed.")
    : (task.result || t("Task completed."));
  const answer = task.status === "completed"
    ? `<article class="assistant-answer">${renderMarkdown(answerText)}${evolutionMetadata}<div class="assistant-actions"><button data-speak-task="${escapeHtml(task.task_id)}">${escapeHtml(t("Read aloud"))}</button></div></article>${renderArtifacts(task)}`
    : (TERMINAL_STATES.has(task.status)
      ? `<article class="assistant-answer error-answer">${escapeHtml(task.error || task.result || t("The task could not be completed."))}<button class="retry-task" data-retry-task="${escapeHtml(task.task_id)}">${escapeHtml(t("Retry"))}</button></article>`
      : "");
  const events = Array.isArray(task.events) ? task.events : [];
  const latencySummary = renderLatencySummary(task);
  const detail = events.length
    ? `<div class="event-list">${events.map((event) => `<div class="event-row ${escapeHtml(event.status || "")}"><span></span><div><strong>${escapeHtml(t(event.title || "Task step"))}</strong>${event.detail ? `<small>${escapeHtml(event.detail)}</small>` : ""}</div></div>`).join("")}</div>`
    : escapeHtml(task.current_step ? t(task.current_step) : `${agentName(task.agent_id)} · ${statusLabel(task.status)}`);
  const attachments = Array.isArray(task.attachments) ? task.attachments : [];
  const attachmentRows = attachments.length
    ? `<div class="user-attachments">${attachments.map((path) => `<span title="${escapeHtml(path)}">${escapeHtml(String(path).split(/[\\/]/).pop() || path)}</span>`).join("")}</div>`
    : "";
  const originLabel = isEvolution
    ? `<small class="task-origin">${escapeHtml(t(task.automatic ? "Automatic self-evolution" : "Self-evolution"))}</small>`
    : "";
  const detailHidden = isEvolution && !TERMINAL_STATES.has(task.status) ? "" : "hidden";
  return `
    <article class="task-turn ${isEvolution ? "self-evolution-turn" : ""}" data-task-id="${escapeHtml(task.task_id)}">
      <div class="user-message-row"><div class="user-message ${isEvolution ? "self-evolution-message" : ""}">${originLabel}${escapeHtml(task.prompt || t("Attached files"))}</div></div>${attachmentRows}
      <button class="run-summary ${statusClass}" data-toggle-run="${escapeHtml(task.task_id)}">
        <span class="status-pulse"></span>
        <strong>${escapeHtml(taskStatusLabel(task))} <span data-elapsed-task="${escapeHtml(task.task_id)}">${escapeHtml(formatDuration(taskElapsed(task)))}</span></strong>
        <span>${escapeHtml(taskRouteName(task))}</span><span class="chevron" aria-hidden="true"></span>
      </button>
      <div class="run-detail" data-run-detail="${escapeHtml(task.task_id)}" ${detailHidden}>${latencySummary}${detail}</div>
      ${answer}
    </article>`;
}

function renderConversation(force = false) {
  const tasks = conversationTasks();
  const signature = JSON.stringify(tasks.map((task) => [
    task.task_id,
    task.status,
    task.updated_at,
    task.result?.length,
    task.output_files?.length,
    task.events?.length,
    task.delivery_trace?.length,
    task.latency?.first_output_ms,
    task.latency?.total_ms,
    task.delegate_agent_id
  ]));
  if (!force && signature === state.renderingSignature) return;
  state.renderingSignature = signature;
  const wasNearBottom = elements.stream.scrollHeight - elements.stream.scrollTop - elements.stream.clientHeight < 140;
  elements.empty.hidden = tasks.length > 0;
  elements.messages.innerHTML = tasks.map(renderTurn).join("");
  const first = tasks[0];
  elements.title.textContent = first ? titleFromPrompt(first.prompt) : t("New task");
  updateHeaderStatus();
  if (force || wasNearBottom) requestAnimationFrame(() => { elements.stream.scrollTop = elements.stream.scrollHeight; });
}

function updateElapsedLabels() {
  for (const node of $$('[data-elapsed-task]')) {
    const task = state.tasks.find((item) => item.task_id === node.dataset.elapsedTask);
    if (task) node.textContent = formatDuration(taskElapsed(task));
  }
}

function updateHeaderStatus() {
  const tasks = conversationTasks();
  const active = [...tasks].reverse().find((task) => !TERMINAL_STATES.has(task.status));
  const latest = tasks[tasks.length - 1];
  const status = active?.status || latest?.status || "ready";
  elements.taskState.textContent = active || latest ? taskStatusLabel(active || latest) : statusLabel(status);
  elements.taskState.className = active ? "running" : (latest && latest.status !== "completed" ? "failed" : "");
  elements.route.textContent = latest ? taskRouteName(latest) : t("Automatic routing");
}

async function refreshTasks(force = false) {
  if (state.polling) return;
  state.polling = true;
  try {
    const payload = await window.signalasi.listDesktopTasks(200);
    state.tasks = Array.isArray(payload.tasks) ? payload.tasks : [];
    selectActiveEvolutionTask();
    renderHistory();
    renderConversation(force);
  } catch (error) {
    if (force) showToast(`${t("Task history unavailable")}: ${error.message || error}`);
  } finally {
    state.polling = false;
  }
}

function selectActiveEvolutionTask() {
  if (state.emptyConversationIntent || conversationTasks().length || elements.prompt.value.trim()) return;
  const active = state.tasks
    .filter((task) => task.task_kind === "self_evolution" && !TERMINAL_STATES.has(task.status))
    .sort((a, b) => Number(b.updated_at) - Number(a.updated_at))[0];
  if (active) state.currentConversationId = active.conversation_id;
}

function mergeTaskUpdate(task) {
  if (!task?.task_id) return;
  const currentConversationHadTasks = conversationTasks().length > 0;
  const optimisticIndex = state.tasks.findIndex((item) =>
    String(item.task_id || "").startsWith("pending-")
    && item.conversation_id === task.conversation_id
    && item.prompt === task.prompt);
  if (optimisticIndex >= 0) state.tasks.splice(optimisticIndex, 1);

  const index = state.tasks.findIndex((item) => item.task_id === task.task_id);
  const isNewTask = index < 0;
  if (index >= 0) {
    state.tasks[index] = { ...state.tasks[index], ...task };
  } else {
    state.tasks.push(task);
  }
  if (
    isNewTask
    && task.task_kind === "self_evolution"
    && !currentConversationHadTasks
    && !state.emptyConversationIntent
    && !elements.prompt.value.trim()
  ) {
    state.currentConversationId = task.conversation_id;
    state.renderingSignature = "";
  }
  if (isNewTask && task.task_kind === "self_evolution") {
    showToast(t(task.automatic ? "Automatic self-evolution started" : "Self-evolution started"));
  }
  renderHistory();
  if (task.conversation_id === state.currentConversationId) renderConversation();
}

function scheduleTaskStreamReconnect() {
  window.clearTimeout(state.taskStreamReconnectTimer);
  state.taskStreamReconnectTimer = window.setTimeout(connectTaskStream, 1500);
}

async function connectTaskStream() {
  if (state.taskStream && [WebSocket.CONNECTING, WebSocket.OPEN].includes(state.taskStream.readyState)) return;
  try {
    const stream = await window.signalasi.desktopTaskStreamConfig();
    const socket = new WebSocket(stream.url, stream.protocols);
    state.taskStream = socket;
    socket.addEventListener("open", () => {
      if (state.taskStream !== socket) return;
      state.taskStreamConnected = true;
    });
    socket.addEventListener("message", (event) => {
      if (state.taskStream !== socket) return;
      let payload;
      try {
        payload = JSON.parse(event.data);
      } catch {
        return;
      }
      if (payload.type === "desktop_tasks_snapshot" && Array.isArray(payload.tasks)) {
        state.tasks = payload.tasks;
        selectActiveEvolutionTask();
        renderHistory();
        renderConversation();
      } else if (payload.type === "desktop_task_update") {
        mergeTaskUpdate(payload.task);
      }
    });
    socket.addEventListener("close", () => {
      if (state.taskStream !== socket) return;
      state.taskStream = null;
      state.taskStreamConnected = false;
      scheduleTaskStreamReconnect();
    });
    socket.addEventListener("error", () => socket.close());
  } catch {
    state.taskStream = null;
    state.taskStreamConnected = false;
    scheduleTaskStreamReconnect();
  }
}

function updateSendState() {
  const ready = Boolean(elements.prompt.value.trim() || state.attachments.length);
  elements.send.classList.toggle("ready", ready);
  elements.send.disabled = !ready;
  elements.prompt.style.height = "35px";
  elements.prompt.style.height = `${Math.min(104, Math.max(35, elements.prompt.scrollHeight))}px`;
}

function renderAttachmentTray() {
  elements.attachments.hidden = state.attachments.length === 0;
  elements.attachments.innerHTML = state.attachments.map((path, index) => {
    const name = path.split(/[\\/]/).pop() || path;
    return `<div class="attachment-chip"><span title="${escapeHtml(path)}">${escapeHtml(name)}</span><button data-remove-attachment="${index}" aria-label="Remove">×</button></div>`;
  }).join("");
  updateSendState();
}

async function addAttachments() {
  try {
    const files = await window.signalasi.chooseAttachments();
    const combined = [...state.attachments, ...files];
    state.attachments = Array.from(new Set(combined)).slice(0, 12);
    renderAttachmentTray();
  } catch (error) {
    showToast(error.message || String(error));
  }
}

async function sendTask() {
  const prompt = elements.prompt.value.trim();
  if (!prompt && !state.attachments.length) return;
  state.emptyConversationIntent = false;
  const attachments = [...state.attachments];
  elements.prompt.value = "";
  state.attachments = [];
  renderAttachmentTray();
  updateSendState();
  const optimistic = {
    task_id: `pending-${Date.now()}`,
    conversation_id: state.currentConversationId,
    source_message_id: "desktop:pending",
    prompt: prompt || t("Attached files"),
    agent_id: state.selectedAgentId,
    status: "accepted",
    created_at: Date.now(),
    updated_at: Date.now(),
    started_at: 0,
    output_files: []
  };
  state.tasks.unshift(optimistic);
  state.renderingSignature = "";
  renderHistory();
  renderConversation(true);
  try {
    const task = await window.signalasi.startDesktopTask({
      prompt,
      agentId: state.selectedAgentId,
      conversationId: state.currentConversationId,
      attachments,
      responseLanguage: resolveLanguagePolicy(
        state.agentConfig?.language_policy?.response_language || "auto"
      )
    });
    state.tasks = state.tasks.filter((item) => item.task_id !== optimistic.task_id);
    mergeTaskUpdate(task);
    updateSelectedAgent();
    state.renderingSignature = "";
    renderConversation(true);
  } catch (error) {
    state.tasks = state.tasks.filter((item) => item.task_id !== optimistic.task_id);
    elements.prompt.value = prompt;
    state.attachments = attachments;
    renderAttachmentTray();
    state.renderingSignature = "";
    renderConversation(true);
    showToast(`${t("Could not start task")}: ${error.message || error}`);
  }
}

function newTask(agentId = "auto", name = "Agent") {
  state.currentConversationId = crypto.randomUUID();
  state.emptyConversationIntent = true;
  state.selectedAgentId = agentId;
  state.selectedAgentName = name;
  state.attachments = [];
  state.renderingSignature = "";
  elements.prompt.value = "";
  renderAttachmentTray();
  updateSelectedAgent();
  renderHistory();
  renderConversation(true);
  elements.prompt.focus();
}

function updateSelectedAgent() {
  elements.selectedAgent.textContent = state.selectedAgentId === "auto" ? t("Agent") : state.selectedAgentName;
  $("#autoModeButton").classList.toggle("active", state.selectedAgentId === "auto");
  $("#localModeButton").classList.toggle("active", state.selectedAgentId === "desktop");
}

async function refreshBackend() {
  try {
    state.backend = await window.signalasi.startBackend();
  } catch (error) {
    state.backend = { running: false, error: error.message || String(error) };
  }
  const online = Boolean(state.backend?.running);
  elements.backendBadge.className = `state-badge ${online ? "ok" : "bad"}`;
  elements.backendBadge.textContent = t(online ? "Online" : "Offline");
  elements.backendDetail.textContent = online ? state.backend.origin : (state.backend?.error || t("Backend unavailable"));
}

function updateAgentCounters() {
  elements.agentCount.textContent = String(state.agents.length);
}

function renderAgentContacts() {
  const target = $("#agentContactList");
  if (!state.agents.length) {
    target.innerHTML = `<div class="history-empty">${escapeHtml(t("No agents detected."))}</div>`;
    return;
  }
  target.innerHTML = state.agents.map((agent) => {
    const id = agent.mobile_contact_id || agent.id;
    const ready = ["ready", "detected"].includes(agent.status);
    const checking = agent.status === "checking";
    const initials = String(agent.name || id).split(/\s+/).map((part) => part[0]).join("").slice(0, 2).toUpperCase();
    const stateLabel = checking ? "Checking" : (ready ? "Ready" : "Setup");
    return `<article class="agent-contact"><div class="agent-contact-icon">${escapeHtml(initials)}</div><div><strong>${escapeHtml(agent.name || id)}<span class="contact-state ${ready ? "" : "setup"}">${escapeHtml(t(stateLabel))}</span></strong><small>${escapeHtml(t(agent.detail || agent.note || agent.kind || ""))}</small></div><div class="contact-actions"><button data-use-agent="${escapeHtml(id)}">${escapeHtml(t("Use"))}</button><button class="primary" data-chat-agent="${escapeHtml(id)}">${escapeHtml(t("Chat"))}</button></div></article>`;
  }).join("");
}

async function refreshAgents() {
  if (state.agentRefreshPromise) return state.agentRefreshPromise;
  state.agentRefreshPromise = (async () => {
    try {
      state.agents = await window.signalasi.detectAgents();
      state.agentConfig = await window.signalasi.getAgentConfig();
      renderAgentContacts();
      updateAgentCounters();
      fillAgentSettings();
    } catch (error) {
      $("#agentContactList").innerHTML = `<div class="history-empty">${escapeHtml(error.message || String(error))}</div>`;
    } finally {
      state.agentRefreshPromise = null;
    }
  })();
  return state.agentRefreshPromise;
}

function fillAgentSettings() {
  const config = state.agentConfig || {};
  const commands = config.commands || {};
  $("#cmdHermes").value = commands.hermes || "";
  $("#cmdCodex").value = commands.codex || "";
  $("#cmdClaude").value = commands.claude || "";
  $("#cmdOpenClaw").value = commands.openclaw || "";
  fillLanguagePolicySettings(config);
  fillCloudModelSettings(config.cloud_model || {});
  fillWebSearchSettings(config.web_search || {});
}

function fillLanguagePolicySettings(config = state.agentConfig || {}) {
  const languagePolicy = config.language_policy || {};
  $("#responseLanguageSelect").value = normalizeLanguagePolicy(languagePolicy.response_language);
  $("#asrLanguageSelect").value = normalizeLanguagePolicy(languagePolicy.asr_language);
  $("#ttsLanguageSelect").value = normalizeLanguagePolicy(languagePolicy.tts_language);
}

async function saveLanguagePolicySettings() {
  const config = state.agentConfig || await window.signalasi.getAgentConfig();
  config.language_policy = {
    ...(config.language_policy || {}),
    response_language: normalizeLanguagePolicy($("#responseLanguageSelect").value),
    asr_language: normalizeLanguagePolicy($("#asrLanguageSelect").value),
    tts_language: normalizeLanguagePolicy($("#ttsLanguageSelect").value)
  };
  state.agentConfig = await window.signalasi.saveAgentConfig(config);
  fillLanguagePolicySettings(state.agentConfig);
  showToast(t("Voice and language settings saved."));
}

function cloudProviderFor(config) {
  const saved = String(config.provider || "").trim().toLowerCase();
  if (Object.hasOwn(CLOUD_PROVIDER_PRESETS, saved)) return saved;
  const endpoint = String(config.url || "").trim().toLowerCase();
  return Object.entries(CLOUD_PROVIDER_PRESETS)
    .find(([, preset]) => preset.endpoint && endpoint === preset.endpoint.toLowerCase())?.[0] || "custom";
}

function setCloudModelStatus(status, detail = "") {
  const badge = $("#cloudModelBadge");
  const result = $("#cloudModelTestResult");
  const labels = {
    ready: "Ready",
    testing: "Testing...",
    missing: "Not configured",
    error: "Needs attention"
  };
  badge.className = `state-badge ${status === "ready" ? "ok" : (status === "error" ? "bad" : "pending")}`;
  badge.textContent = t(labels[status] || labels.missing);
  if (!detail) {
    result.hidden = true;
    result.textContent = "";
    result.className = "cloud-test-result";
    return;
  }
  result.hidden = false;
  result.textContent = detail;
  result.className = `cloud-test-result ${status === "ready" ? "ok" : (status === "error" ? "bad" : "")}`;
}

function fillCloudModelSettings(config = {}) {
  const provider = cloudProviderFor(config);
  $("#cloudProvider").value = provider;
  $("#cloudDisplayName").value = config.name || CLOUD_PROVIDER_PRESETS[provider].name;
  $("#cloudEndpoint").value = config.url || CLOUD_PROVIDER_PRESETS[provider].endpoint;
  $("#cloudModelId").value = config.model || "";
  $("#cloudApiKey").value = config.api_key || "";
  $("#cloudContextWindow").value = String(config.context_window_tokens || 64000);
  $("#cloudOutputReserve").value = String(config.max_output_tokens || 4096);
  $("#cloudModelSummary").checked = ![false, "", "false", "0"].includes(config.context_model_summary);
  const ready = Boolean($("#cloudEndpoint").value.trim() && $("#cloudModelId").value.trim() && $("#cloudApiKey").value.trim());
  setCloudModelStatus(ready ? "ready" : "missing");
}

function applyCloudProviderPreset() {
  const provider = $("#cloudProvider").value;
  const preset = CLOUD_PROVIDER_PRESETS[provider] || CLOUD_PROVIDER_PRESETS.custom;
  const endpoint = $("#cloudEndpoint");
  const displayName = $("#cloudDisplayName");
  const presetEndpoints = Object.values(CLOUD_PROVIDER_PRESETS).map((item) => item.endpoint).filter(Boolean);
  if (provider === "custom") {
    if (presetEndpoints.includes(endpoint.value.trim())) endpoint.value = "";
  } else {
    endpoint.value = preset.endpoint;
  }
  if (!displayName.value.trim() || Object.values(CLOUD_PROVIDER_PRESETS).some((item) => item.name === displayName.value.trim())) {
    displayName.value = preset.name;
  }
}

function boundedInteger(selector, fallback, minimum, maximum) {
  const parsed = Number.parseInt($(selector).value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, parsed));
}

function readCloudModelSettings() {
  return {
    provider: $("#cloudProvider").value,
    name: $("#cloudDisplayName").value.trim() || CLOUD_PROVIDER_PRESETS[$("#cloudProvider").value]?.name || "Cloud Model",
    url: $("#cloudEndpoint").value.trim(),
    model: $("#cloudModelId").value.trim(),
    api_key: $("#cloudApiKey").value.trim(),
    context_window_tokens: boundedInteger("#cloudContextWindow", 64000, 4096, 1000000),
    max_output_tokens: boundedInteger("#cloudOutputReserve", 4096, 512, 128000),
    context_model_summary: $("#cloudModelSummary").checked ? "true" : ""
  };
}

function validateCloudModelSettings(config) {
  if (!config.url || !config.model || !config.api_key) return t("Enter the endpoint, model ID, and API key.");
  let parsed;
  try {
    parsed = new URL(config.url);
  } catch (_error) {
    return t("Enter a valid endpoint URL.");
  }
  const local = ["localhost", "127.0.0.1", "::1"].includes(parsed.hostname);
  if (parsed.protocol !== "https:" && !(local && parsed.protocol === "http:")) {
    return t("Use HTTPS, except for a local endpoint.");
  }
  if (config.max_output_tokens >= config.context_window_tokens) {
    return t("Reserved output must be smaller than the context window.");
  }
  return "";
}

async function saveCloudModelSettings(testAfterSave = false) {
  const cloudModel = readCloudModelSettings();
  const validation = validateCloudModelSettings(cloudModel);
  if (validation) {
    setCloudModelStatus("error", validation);
    return;
  }
  const config = state.agentConfig || await window.signalasi.getAgentConfig();
  config.cloud_model = { ...(config.cloud_model || {}), ...cloudModel };
  setCloudModelStatus(testAfterSave ? "testing" : "ready", testAfterSave ? t("Testing the configured model...") : "");
  try {
    state.agentConfig = await window.signalasi.saveAgentConfig(config);
    fillCloudModelSettings(state.agentConfig.cloud_model || cloudModel);
    if (!testAfterSave) {
      showToast(t("Cloud API settings saved."));
      return;
    }
    setCloudModelStatus("testing", t("Testing the configured model..."));
    const response = await window.signalasi.testAgent("cloud-model", "Reply with only: SignalASI cloud API ready.");
    const reply = String(response?.reply || "").trim();
    if (!reply) throw new Error(t("The model returned an empty response."));
    setCloudModelStatus("ready", `${t("Connected")}: ${reply}`);
    showToast(t("Cloud API is ready."));
  } catch (error) {
    setCloudModelStatus("error", error.message || String(error));
  }
}

function fillWebSearchSettings(config = {}) {
  $("#webBraveApiKey").value = config.brave_api_key || "";
  $("#webGithubToken").value = config.github_token || "";
}

async function saveWebSearchSettings() {
  const config = state.agentConfig || await window.signalasi.getAgentConfig();
  config.web_search = {
    ...(config.web_search || {}),
    brave_api_key: $("#webBraveApiKey").value.trim(),
    github_token: $("#webGithubToken").value.trim()
  };
  state.agentConfig = await window.signalasi.saveAgentConfig(config);
  fillWebSearchSettings(state.agentConfig.web_search || {});
  showToast(t("Web intelligence source credentials saved."));
}

async function saveAgentCommands() {
  const config = state.agentConfig || await window.signalasi.getAgentConfig();
  config.commands = {
    ...(config.commands || {}),
    hermes: $("#cmdHermes").value.trim(),
    codex: $("#cmdCodex").value.trim(),
    claude: $("#cmdClaude").value.trim(),
    openclaw: $("#cmdOpenClaw").value.trim()
  };
  state.agentConfig = await window.signalasi.saveAgentConfig(config);
  showToast(t("Agent commands saved."));
  await refreshAgents();
}

async function saveCustomAgent() {
  const id = $("#customAgentId").value.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-|-$/g, "");
  const name = $("#customAgentName").value.trim();
  const command = $("#customAgentCommand").value.trim();
  if (!id || !name || !command) {
    showToast(t("Complete the agent ID, name, and command."));
    return;
  }
  const config = state.agentConfig || await window.signalasi.getAgentConfig();
  const rows = Array.isArray(config.custom_agents) ? config.custom_agents.filter((item) => item.id !== id) : [];
  rows.push({ id, name, command });
  config.custom_agents = rows;
  state.agentConfig = await window.signalasi.saveAgentConfig(config);
  $("#customAgentId").value = "";
  $("#customAgentName").value = "";
  $("#customAgentCommand").value = "";
  showToast(t("Custom agent added."));
  await refreshAgents();
}

function renderGateway() {
  const status = state.pairing || {};
  const clients = Array.isArray(status.clients) ? status.clients : [];
  const count = Number(status.client_count || clients.length || 0);
  elements.gatewayCount.textContent = count ? t("{count} online", { count }) : t("Offline");
  $("#gatewaySummary .status-orb").classList.toggle("online", count > 0);
  $("#gatewaySummary p").textContent = count ? t("{count} verified phone(s) connected", { count }) : t("No phone paired");
  $("#pairedClientList").innerHTML = clients.length ? clients.map((client) => {
    const id = client.client_route_id || "";
    const access = client.access?.profile === "desktop_executor" ? t("Full access") : t("Restricted");
    const fingerprint = client.identity_fingerprint_short || id.slice(0, 12) || t("Verified");
    return `<article class="paired-client"><span class="phone-outline"></span><div><strong>${escapeHtml(client.remote_name || client.device_name || t("SignalASI phone"))}</strong><small>${escapeHtml(`${fingerprint} · ${access}`)}</small></div><button data-revoke-client="${escapeHtml(id)}">${escapeHtml(t("Revoke"))}</button></article>`;
  }).join("") : `<div class="history-empty">${escapeHtml(t("Scan the QR code below to pair a phone."))}</div>`;
}

async function refreshGateway() {
  try {
    state.pairing = await window.signalasi.getPairingStatus();
    renderGateway();
  } catch (error) {
    state.pairing = { clients: [] };
    renderGateway();
    $("#gatewaySummary p").textContent = error.message || String(error);
  }
}

async function loadPairingFrame() {
  const image = $("#pairingFrame");
  if (image.getAttribute("src")) return;
  const fingerprint = $("#pairingFingerprint");
  const accessSummary = $("#pairingAccessSummary");
  fingerprint.textContent = t("Preparing secure pairing QR...");
  accessSummary.textContent = "";
  try {
    const pairing = await window.signalasi.getPairingQr(state.pairingGrantDesktopExecutor);
    image.src = pairing.imageDataUrl;
    fingerprint.textContent = pairing.fingerprint
      ? t("Computer fingerprint: {fingerprint}", { fingerprint: pairing.fingerprint })
      : "";
    accessSummary.textContent = state.pairingGrantDesktopExecutor
      ? t("Full Desktop Executor access will be granted to this phone.")
      : t("Restricted pairing: Agent chat and explicit task attachments only.");
  } catch (error) {
    image.removeAttribute("src");
    fingerprint.textContent = t("Unable to load the pairing QR. Restart the Desktop backend and try again.");
    throw error;
  }
}

function formatControlTime(value) {
  const timestamp = Number(value || 0);
  if (!timestamp) return t("Never");
  return new Intl.DateTimeFormat(state.language === "zh-CN" ? "zh-CN" : "en", {
    month: "short", day: "numeric", hour: "2-digit", minute: "2-digit"
  }).format(new Date(timestamp));
}

function renderDesktopControl() {
  const control = state.desktopControl || { recent_audit: [] };
  const audit = Array.isArray(control.recent_audit)
    ? control.recent_audit.filter((row) => row.event_type !== "settings_changed").slice(0, 20)
    : [];
  $("#desktopControlAuditList").innerHTML = audit.length
    ? audit.map((row) => `<article class="control-audit-row"><strong>${escapeHtml(row.summary || row.event_type || "")}</strong><small>${escapeHtml(`${formatControlTime(row.created_at)} · ${row.status || ""}`)}</small></article>`).join("")
    : `<div class="history-empty">${escapeHtml(t("No remote-control activity yet."))}</div>`;
}

async function refreshDesktopControl() {
  try {
    state.desktopControl = await window.signalasi.getDesktopControl();
    renderDesktopControl();
  } catch (error) {
    $("#desktopControlAuditList").innerHTML = `<div class="history-empty">${escapeHtml(error.message || String(error))}</div>`;
  }
}

function parsePhrases(value) {
  return Array.from(new Set(String(value || "").split(/[,;\n]/).map((item) => item.trim()).filter(Boolean))).slice(0, 32);
}

function renderMemory() {
  const rows = Array.isArray(state.memory.memories) ? state.memory.memories : [];
  const stats = state.memory.stats || {};
  $("#memorySummary").textContent = t("{count} active memories", { count: Number(stats.active || rows.length || 0) });
  $("#memoryList").innerHTML = rows.length ? rows.map((memory) => `
    <article class="capability-item">
      <div><strong>${escapeHtml(memory.kind || t("Memory"))}</strong><small title="${escapeHtml(memory.content || "")}">${escapeHtml(String(memory.content || "").slice(0, 180))}</small></div>
      <div class="capability-item-actions"><button data-forget-memory="${escapeHtml(memory.id)}">${escapeHtml(t("Forget"))}</button></div>
    </article>`).join("") : `<div class="history-empty">${escapeHtml(t("No matching memory."))}</div>`;
}

function renderSkills() {
  const enabled = state.skills.filter((skill) => skill.enabled).length;
  $("#skillSummary").textContent = t("{enabled} of {total} enabled", { enabled, total: state.skills.length });
  $("#skillList").innerHTML = state.skills.length ? state.skills.map((skill) => `
    <article class="capability-item">
      <div><strong>${escapeHtml(skill.name || skill.id)}</strong><small>${escapeHtml(skill.description || skill.id)}</small></div>
      <div class="capability-item-actions">
        ${skill.source === "user" ? `<button data-delete-skill="${escapeHtml(skill.id)}">${escapeHtml(t("Delete"))}</button>` : ""}
        <button class="capability-toggle ${skill.enabled ? "on" : ""}" data-toggle-skill="${escapeHtml(skill.id)}" data-enabled="${skill.enabled ? "1" : "0"}" aria-label="${escapeHtml(t(skill.enabled ? "Disable" : "Enable"))}"></button>
      </div>
    </article>`).join("") : `<div class="history-empty">${escapeHtml(t("No skills installed."))}</div>`;
}

function renderMcp() {
  $("#mcpSummary").textContent = t("{count} configured connections", { count: state.mcp.length });
  $("#mcpList").innerHTML = state.mcp.length ? state.mcp.map((connection) => `
    <article class="capability-item">
      <div><strong>${escapeHtml(connection.name || connection.id)}</strong><small>${escapeHtml(connection.default_tool || t("Automatic tool selection"))}${connection.auto_invoke ? ` · ${escapeHtml(t("Auto"))}` : ""}</small></div>
      <div class="capability-item-actions">
        <button data-probe-mcp="${escapeHtml(connection.id)}">${escapeHtml(t("Test"))}</button>
        <button class="primary" data-chat-mcp="${escapeHtml(connection.id)}">${escapeHtml(t("Chat"))}</button>
        <button data-delete-mcp="${escapeHtml(connection.id)}">${escapeHtml(t("Delete"))}</button>
      </div>
    </article>`).join("") : `<div class="history-empty">${escapeHtml(t("No MCP connections configured."))}</div>`;
}

function proactiveTriggerSummary(trigger = {}) {
  if (trigger.kind === "cron") return `${trigger.cron || "-"} \u00b7 ${trigger.time_zone || "UTC"}`;
  if (trigger.kind === "interval" || trigger.kind === "goal_checkpoint") {
    return t("Every {seconds} seconds", { seconds: Number(trigger.interval_seconds || 0) });
  }
  if (trigger.kind === "webhook") return t("Trusted webhook");
  return t("Manual");
}

function proactiveStatusLabel(status) {
  const labels = {
    queued: "Queued",
    running: "Running",
    waiting: "Waiting",
    retrying: "Retrying",
    completed: "Completed",
    failed: "Failed",
    cancelled: "Cancelled",
    skipped: "Skipped"
  };
  return t(labels[status] || status || "Queued");
}

function renderProactiveTasks() {
  const tasks = Array.isArray(state.proactiveTasks) ? state.proactiveTasks : [];
  const active = tasks.filter((task) => task.enabled).length;
  $("#proactiveSummary").textContent = tasks.length
    ? t("{active} active of {total} proactive tasks", { active, total: tasks.length })
    : t("Durable Cron, goal, webhook, Agent team, workflow, and tool execution");
  $("#proactiveTaskList").innerHTML = tasks.length ? tasks.map((task) => {
    const next = Number(task.next_run_at_millis || 0);
    const detail = [
      proactiveTriggerSummary(task.trigger),
      task.action?.kind ? t(task.action.kind.replaceAll("_", " ")) : "",
      next ? new Date(next).toLocaleString() : ""
    ].filter(Boolean).join(" \u00b7 ");
    return `<article class="capability-item ${task.task_id === state.selectedProactiveTaskId ? "selected" : ""}">
      <div>
        <strong>${escapeHtml(task.name || task.task_id)}</strong>
        <small>${escapeHtml(detail)}</small>
      </div>
      <div class="capability-item-actions">
        <button data-toggle-proactive="${escapeHtml(task.task_id)}" data-enabled="${task.enabled ? "1" : "0"}">${escapeHtml(t(task.enabled ? "Pause" : "Enable"))}</button>
        <button data-edit-proactive="${escapeHtml(task.task_id)}">${escapeHtml(t("Edit"))}</button>
        <button data-runs-proactive="${escapeHtml(task.task_id)}">${escapeHtml(t("Runs"))}</button>
        <button class="primary" data-trigger-proactive="${escapeHtml(task.task_id)}">${escapeHtml(t("Run"))}</button>
        <button data-delete-proactive="${escapeHtml(task.task_id)}">${escapeHtml(t("Delete"))}</button>
      </div>
    </article>`;
  }).join("") : `<div class="history-empty">${escapeHtml(t("No proactive tasks configured."))}</div>`;
  renderProactiveRuns();
}

function renderProactiveRuns() {
  const runs = Array.isArray(state.proactiveRuns) ? state.proactiveRuns : [];
  $("#proactiveRunList").innerHTML = runs.length ? runs.map((run) => {
    const output = String(run.output?.reply || run.error_message || "").trim();
    const active = !["completed", "failed", "cancelled", "skipped"].includes(run.status);
    return `<article class="capability-item">
      <div>
        <strong>${escapeHtml(proactiveStatusLabel(run.status))}</strong>
        <small>${escapeHtml(new Date(Number(run.scheduled_for_millis || Date.now())).toLocaleString())}${output ? ` \u00b7 ${escapeHtml(output.slice(0, 180))}` : ""}</small>
      </div>
      <div class="capability-item-actions">
        ${active ? `<button data-cancel-proactive-run="${escapeHtml(run.run_id)}">${escapeHtml(t("Cancel"))}</button>` : ""}
      </div>
    </article>`;
  }).join("") : "";
}

function updateCapabilityCount() {
  const total = Number(state.memory.stats?.active || 0)
    + state.skills.filter((skill) => skill.enabled).length
    + state.mcp.filter((item) => item.enabled).length
    + state.proactiveTasks.filter((item) => item.enabled).length;
  elements.capabilityCount.textContent = String(total);
}

async function refreshMemory(query = "") {
  state.memory = await window.signalasi.getDesktopMemory(query, 100);
  renderMemory();
  updateCapabilityCount();
}

async function refreshCapabilities() {
  try {
    const [memory, skills, mcp, proactive, proactiveRuns] = await Promise.all([
      window.signalasi.getDesktopMemory("", 100),
      window.signalasi.getDesktopSkills(),
      window.signalasi.getDesktopMcp(),
      window.signalasi.listProactiveTasks(200),
      window.signalasi.listProactiveRuns(state.selectedProactiveTaskId, 100)
    ]);
    state.memory = memory;
    state.skills = Array.isArray(skills.skills) ? skills.skills : [];
    state.mcp = Array.isArray(mcp.connections) ? mcp.connections : [];
    state.proactiveTasks = Array.isArray(proactive.tasks) ? proactive.tasks : [];
    state.proactiveRuns = Array.isArray(proactiveRuns.runs) ? proactiveRuns.runs : [];
    renderMemory();
    renderSkills();
    renderMcp();
    renderProactiveTasks();
    updateCapabilityCount();
  } catch (error) {
    $("#memorySummary").textContent = error.message || String(error);
  }
}

function renderCommandCatalog() {
  const summary = $("#commandSummary");
  const catalog = $("#commandCatalog");
  const commands = Array.isArray(state.commands?.commands) ? state.commands.commands : [];
  const roots = Array.isArray(state.commands?.roots) ? state.commands.roots : [];
  if (!summary || !catalog) return;
  summary.innerHTML = `
    <span><strong>${t("Catalog")}</strong>${Number(state.commands?.catalog_size || commands.length)} ${t("commands")}</span>
    <span><strong>${t("Roots")}</strong>${roots.length}</span>
    <span><strong>${t("Handlers")}</strong>${commands.filter((item) => item.handler).length}/${commands.length}</span>
    <span><strong>${t("Shown")}</strong>${Math.min(commands.length, 120)}</span>
  `;
  catalog.innerHTML = "";
  if (!commands.length) {
    catalog.textContent = t("No commands matched the current filter.");
    return;
  }
  for (const command of commands.slice(0, 120)) {
    const row = document.createElement("button");
    row.className = "command-row";
    row.type = "button";
    row.dataset.commandId = command.command_id || "";
    row.innerHTML = `
      <span><strong>${escapeHtml(command.command_id || "")}</strong><em>${escapeHtml((command.aliases || [])[0] || `/${command.root || ""} ${command.action || ""}`)}</em></span>
      <span>${escapeHtml(command.risk || "read")}</span>
      <span>${command.handler ? t("handler") : t("missing")}</span>
      <span>${escapeHtml(command.summary || "")}</span>
    `;
    catalog.appendChild(row);
  }
}

function renderCommandRuns() {
  const target = $("#commandRuns");
  if (!target) return;
  target.innerHTML = "";
  if (!state.commandRuns.length) {
    target.textContent = t("No command runs yet.");
    return;
  }
  for (const run of state.commandRuns.slice(0, 30)) {
    const row = document.createElement("div");
    const status = String(run.status || "unknown");
    row.className = `audit-entry ${status === "completed" ? "ok" : ["failed", "denied", "unavailable", "not_found"].includes(status) ? "warn" : ""}`;
    row.innerHTML = `
      <div><strong>${escapeHtml(run.command_id || "command")}</strong><span>${escapeHtml(status)}</span></div>
      <div><strong>${escapeHtml(run.run_id || "")}</strong><span>${escapeHtml(run.error_code || "ok")}</span></div>
      <div><strong>${escapeHtml(run.completed_at || "")}</strong><span>${escapeHtml(run.message || JSON.stringify(run.data || {}).slice(0, 160))}</span></div>
    `;
    target.appendChild(row);
  }
}

async function refreshCommands() {
  const button = $("#refreshCommandsButton");
  if (button) button.disabled = true;
  try {
    const root = $("#commandRootFilter")?.value.trim() || "";
    state.commands = await window.signalasi.listCommands(root);
    renderCommandCatalog();
  } catch (error) {
    $("#commandSummary").textContent = `${t("Command catalog unavailable")}: ${error.message || String(error)}`;
    $("#commandCatalog").textContent = "";
  } finally {
    if (button) button.disabled = false;
  }
}

async function refreshCommandRuns() {
  const button = $("#refreshCommandRunsButton");
  if (button) button.disabled = true;
  try {
    const response = await window.signalasi.getCommandRuns(30);
    state.commandRuns = Array.isArray(response?.runs) ? response.runs : [];
    renderCommandRuns();
  } catch (error) {
    $("#commandRuns").textContent = `${t("Command runs unavailable")}: ${error.message || String(error)}`;
  } finally {
    if (button) button.disabled = false;
  }
}

async function executeCommandFromPanel() {
  const input = $("#commandInput");
  const approve = $("#commandApprove");
  const button = $("#executeCommandButton");
  const output = $("#commandResult");
  const value = input?.value.trim() || "";
  if (!value) return;
  if (button) button.disabled = true;
  if (output) output.textContent = t("Executing command...");
  try {
    const payload = value.startsWith("/")
      ? { slash: value, approve: Boolean(approve?.checked), source: "desktop" }
      : { command_id: value, args: {}, approve: Boolean(approve?.checked), source: "desktop" };
    const result = await window.signalasi.executeCommand(payload);
    if (output) output.textContent = JSON.stringify(result, null, 2);
    await refreshCommandRuns();
  } catch (error) {
    if (output) output.textContent = error.message || String(error);
  } finally {
    if (button) button.disabled = false;
  }
}

function parseProactiveTeam(value) {
  const team = String(value || "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean).map((line) => {
    const separator = line.indexOf(":");
    if (separator < 1) throw new Error(t("Use role:agent-id for every team member."));
    const member = {
      role: line.slice(0, separator).trim().toLowerCase(),
      agent_id: line.slice(separator + 1).trim(),
      instructions: ""
    };
    if (!["lead", "executor", "observer", "verifier"].includes(member.role) || !member.agent_id) {
      throw new Error(t("Use role:agent-id for every team member."));
    }
    return member;
  });
  if (team.filter((member) => member.role === "lead").length !== 1) {
    throw new Error(t("A team requires exactly one lead."));
  }
  if (new Set(team.map((member) => member.agent_id)).size !== team.length) {
    throw new Error(t("Each team member must be unique."));
  }
  return team;
}

function proactiveTriggerPayload(kind, schedule, timeZone, name, existing = {}) {
  if (kind === "cron") return { kind, cron: schedule || "0 9 * * *", time_zone: timeZone || "UTC" };
  if (kind === "interval") {
    return { kind, interval_seconds: Math.max(60, Number(schedule || 3600)), time_zone: timeZone || "UTC" };
  }
  if (kind === "goal_checkpoint") {
    return {
      kind,
      interval_seconds: Math.max(60, Number(schedule || 3600)),
      time_zone: timeZone || "UTC",
      goal_id: existing.goal_id || `goal:${String(name || "task").toLowerCase().replace(/[^a-z0-9._-]+/g, "-").slice(0, 80) || Date.now()}`
    };
  }
  if (kind === "webhook") {
    return {
      kind,
      time_zone: timeZone || "UTC",
      ...(existing.webhook_id ? { webhook_id: existing.webhook_id } : {})
    };
  }
  return { kind: "manual", time_zone: timeZone || "UTC" };
}

function resetProactiveEditor() {
  state.editingProactiveTaskId = "";
  $("#proactiveName").value = "";
  $("#proactiveTriggerKind").value = "manual";
  $("#proactiveSchedule").value = "";
  $("#proactiveTimeZone").value = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  $("#proactiveActionKind").value = "agent";
  $("#proactiveTarget").value = "codex";
  $("#proactivePrompt").value = "";
  $("#proactiveTeam").value = "";
  $("#proactiveArguments").value = "{}";
  $("#proactiveDelivery").value = "store";
  $("#proactiveNetwork").value = "any";
  $("#proactiveAttempts").value = "3";
  $("#proactiveConcurrency").value = "1";
  $("#proactiveCharging").checked = false;
  $("#cancelProactiveEditButton").hidden = true;
  $("#createProactiveButton").textContent = t("Create proactive task");
  syncProactiveFormVisibility();
}

function editProactiveTask(taskId) {
  const task = state.proactiveTasks.find((item) => item.task_id === taskId);
  if (!task) return;
  state.editingProactiveTaskId = taskId;
  $("#proactiveName").value = task.name || "";
  $("#proactiveTriggerKind").value = task.trigger?.kind || "manual";
  $("#proactiveSchedule").value = task.trigger?.kind === "cron"
    ? task.trigger.cron || ""
    : String(task.trigger?.interval_seconds || "");
  $("#proactiveTimeZone").value = task.trigger?.time_zone || "UTC";
  $("#proactiveActionKind").value = task.action?.kind || "agent";
  $("#proactiveTarget").value = task.action?.target_id || "";
  $("#proactivePrompt").value = task.action?.prompt || "";
  $("#proactiveTeam").value = (task.action?.team || [])
    .map((member) => `${member.role}:${member.agent_id}`)
    .join("\n");
  $("#proactiveArguments").value = JSON.stringify(task.action?.arguments || {}, null, 2);
  $("#proactiveDelivery").value = task.action?.delivery?.mode || "store";
  $("#proactiveNetwork").value = task.policy?.network || "any";
  $("#proactiveAttempts").value = String(task.policy?.max_attempts || 3);
  $("#proactiveConcurrency").value = String(task.policy?.max_concurrency || 1);
  $("#proactiveCharging").checked = Boolean(task.policy?.requires_charging);
  $("#cancelProactiveEditButton").hidden = false;
  $("#createProactiveButton").textContent = t("Update proactive task");
  $("#proactiveCreateDetails").open = true;
  syncProactiveFormVisibility();
  $("#proactiveCreateDetails").scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function syncProactiveFormVisibility() {
  const trigger = $("#proactiveTriggerKind").value;
  const action = $("#proactiveActionKind").value;
  $("#proactiveScheduleField").hidden = !["cron", "interval", "goal_checkpoint"].includes(trigger);
  $("#proactiveTimeZoneField").hidden = trigger !== "cron";
  $("#proactiveTargetField").hidden = action === "subagent_team";
  $("#proactiveTeamField").hidden = action !== "subagent_team";
  $("#proactiveArgumentsField").hidden = action !== "native_tool";
  $("#proactivePromptField").hidden = action === "native_tool";
  $("#proactiveSchedule").placeholder = trigger === "cron" ? "0 9 * * *" : "3600";
}

async function createProactiveTask() {
  const button = $("#createProactiveButton");
  const name = $("#proactiveName").value.trim();
  const actionKind = $("#proactiveActionKind").value;
  if (!name) return showToast(t("Add a task name."));
  let argumentsValue;
  let team;
  try {
    argumentsValue = JSON.parse($("#proactiveArguments").value.trim() || "{}");
    team = actionKind === "subagent_team" ? parseProactiveTeam($("#proactiveTeam").value) : [];
  } catch (error) {
    return showToast(error.message || String(error));
  }
  const targetId = $("#proactiveTarget").value.trim();
  if (actionKind !== "subagent_team" && !targetId) return showToast(t("Add a target ID."));
  const prompt = $("#proactivePrompt").value.trim();
  if (["agent", "subagent_team"].includes(actionKind) && !prompt) {
    return showToast(t("Add a goal or instructions."));
  }
  const editingTask = state.proactiveTasks.find(
    (task) => task.task_id === state.editingProactiveTaskId
  );
  button.disabled = true;
  try {
    const payload = {
      name,
      trigger: proactiveTriggerPayload(
        $("#proactiveTriggerKind").value,
        $("#proactiveSchedule").value.trim(),
        $("#proactiveTimeZone").value.trim(),
        name,
        editingTask?.trigger
      ),
      action: {
        kind: actionKind,
        target_id: targetId,
        prompt,
        arguments: argumentsValue,
        team,
        delivery: { mode: $("#proactiveDelivery").value }
      },
      policy: {
        max_attempts: Math.max(1, Number($("#proactiveAttempts").value || 3)),
        max_concurrency: Math.max(1, Number($("#proactiveConcurrency").value || 1)),
        network: $("#proactiveNetwork").value,
        requires_charging: $("#proactiveCharging").checked
      },
      enabled: true
    };
    if (editingTask) {
      payload.enabled = Boolean(editingTask.enabled);
      await window.signalasi.updateProactiveTask(editingTask.task_id, payload);
    } else {
      await window.signalasi.createProactiveTask(payload);
    }
    const message = editingTask ? t("Proactive task updated.") : t("Proactive task created.");
    resetProactiveEditor();
    $("#proactiveCreateDetails").open = false;
    showToast(message);
    await refreshCapabilities();
  } catch (error) {
    showToast(error.message || String(error));
  } finally {
    button.disabled = false;
  }
}

async function handleProactiveAction(event) {
  const toggle = event.target.closest("[data-toggle-proactive]");
  const edit = event.target.closest("[data-edit-proactive]");
  const runs = event.target.closest("[data-runs-proactive]");
  const trigger = event.target.closest("[data-trigger-proactive]");
  const remove = event.target.closest("[data-delete-proactive]");
  const cancelRun = event.target.closest("[data-cancel-proactive-run]");
  const button = toggle || edit || runs || trigger || remove || cancelRun;
  if (!button) return;
  button.disabled = true;
  try {
    if (edit) {
      editProactiveTask(edit.dataset.editProactive);
      return;
    } else if (toggle) {
      await window.signalasi.updateProactiveTask(toggle.dataset.toggleProactive, {
        enabled: toggle.dataset.enabled !== "1"
      });
    } else if (runs) {
      state.selectedProactiveTaskId = runs.dataset.runsProactive;
      const response = await window.signalasi.listProactiveRuns(state.selectedProactiveTaskId, 100);
      state.proactiveRuns = Array.isArray(response.runs) ? response.runs : [];
      renderProactiveTasks();
      return;
    } else if (trigger) {
      await window.signalasi.triggerProactiveTask(trigger.dataset.triggerProactive);
    } else if (remove) {
      if (!window.confirm(t("Delete this proactive task and its run history?"))) return;
      await window.signalasi.deleteProactiveTask(remove.dataset.deleteProactive);
      if (state.selectedProactiveTaskId === remove.dataset.deleteProactive) {
        state.selectedProactiveTaskId = "";
        state.proactiveRuns = [];
      }
    } else if (cancelRun) {
      await window.signalasi.cancelProactiveRun(cancelRun.dataset.cancelProactiveRun);
    }
    await refreshCapabilities();
  } catch (error) {
    showToast(error.message || String(error));
  } finally {
    button.disabled = false;
  }
}

async function addMemory() {
  const content = $("#memoryContent").value.trim();
  if (!content) return;
  await window.signalasi.rememberDesktopMemory({ content, kind: "manual", importance: 0.8 });
  $("#memoryContent").value = "";
  showToast(t("Memory saved."));
  await refreshMemory($("#memorySearch").value.trim());
}

async function saveSkill() {
  const payload = {
    id: $("#skillId").value.trim().toLowerCase(),
    name: $("#skillName").value.trim(),
    description: "",
    triggers: parsePhrases($("#skillTriggers").value),
    instructions: $("#skillInstructions").value.trim(),
    enabled: true
  };
  if (!payload.id || !payload.name || !payload.triggers.length || !payload.instructions) {
    return showToast(t("Complete the skill ID, name, triggers, and instructions."));
  }
  await window.signalasi.saveDesktopSkill(payload);
  for (const id of ["#skillId", "#skillName", "#skillTriggers", "#skillInstructions"]) $(id).value = "";
  showToast(t("Skill added."));
  await refreshCapabilities();
}

async function saveMcp() {
  const payload = {
    id: $("#mcpId").value.trim().toLowerCase(),
    name: $("#mcpName").value.trim(),
    command: $("#mcpCommand").value.trim(),
    default_tool: $("#mcpTool").value.trim(),
    triggers: parsePhrases($("#mcpTriggers").value),
    enabled: true,
    auto_invoke: $("#mcpAutoInvoke").checked,
    timeout_seconds: 20
  };
  if (!payload.id || !payload.name || !payload.command) return showToast(t("Complete the MCP ID, name, and server command."));
  await window.signalasi.saveDesktopMcp(payload);
  for (const id of ["#mcpId", "#mcpName", "#mcpCommand", "#mcpTool", "#mcpTriggers"]) $(id).value = "";
  $("#mcpAutoInvoke").checked = false;
  showToast(t("MCP connection added."));
  await refreshCapabilities();
}

function selectCapabilityTab(name) {
  $$('[data-capability-tab]').forEach((button) => button.classList.toggle("active", button.dataset.capabilityTab === name));
  $$(".capability-pane").forEach((pane) => pane.classList.remove("active"));
  $(`#${name}Capability`)?.classList.add("active");
}

async function runDiagnostics() {
  const output = $("#diagnosticsOutput");
  output.hidden = false;
  output.textContent = t("Running diagnostics...");
  try {
    const [runtime, agents, pairing] = await Promise.all([
      window.signalasi.getRuntimeDiagnostics(),
      window.signalasi.getAgentDiagnostics(),
      window.signalasi.getPairingStatus()
    ]);
    output.textContent = JSON.stringify({ runtime, agents, pairing }, null, 2);
  } catch (error) {
    output.textContent = error.message || String(error);
  }
}

function runtimeStatusLabel(status) {
  if (status === "ready") return "Ready";
  if (status === "partial") return "Partial";
  return "Missing";
}

function renderRuntimeManager() {
  const summary = state.runtime?.summary || {};
  const rows = Array.isArray(state.runtime?.runtimes) ? state.runtime.runtimes : [];
  const summaryNode = $("#runtimeManagerSummary");
  if (state.runtime?.error) {
    summaryNode.textContent = state.runtime.error;
  } else if (rows.length) {
    summaryNode.textContent = t("{ready} ready · {partial} partial · {missing} missing", {
      ready: Number(summary.ready || 0),
      partial: Number(summary.partial || 0),
      missing: Number(summary.missing || 0)
    });
  } else {
    summaryNode.textContent = t("Runtime inventory has not been checked.");
  }
  $("#runtimeManagerList").innerHTML = rows.length ? rows.map((runtime) => {
    const status = String(runtime.status || "missing");
    const detail = runtime.version
      || (runtime.missing_components || []).map((item) => t("Missing {component}", { component: item })).join(", ")
      || runtime.source
      || "";
    return `<article class="runtime-row">
      <div><strong>${escapeHtml(runtime.title || runtime.id)}</strong><small title="${escapeHtml(detail)}">${escapeHtml(detail)}</small></div>
      <span class="state-badge ${status === "ready" ? "ok" : status === "missing" ? "bad" : ""}">${escapeHtml(t(runtimeStatusLabel(status)))}</span>
    </article>`;
  }).join("") : "";
}

async function refreshRuntimeManager(refresh = false) {
  const button = $("#refreshRuntimeButton");
  button.disabled = true;
  try {
    const diagnostics = await window.signalasi.getRuntimeDiagnostics(refresh);
    state.runtime = diagnostics.managedRuntime || { summary: {}, runtimes: [], error: "" };
    renderRuntimeManager();
  } catch (error) {
    state.runtime = { summary: {}, runtimes: [], error: error.message || String(error) };
    renderRuntimeManager();
  } finally {
    button.disabled = false;
  }
}

const ACTIVE_EVOLUTION_STATES = new Set(["proposed", "preparing", "running", "validating", "publishing"]);

function evolutionStatusLabel(status) {
  const labels = {
    proposed: "Proposed",
    preparing: "Preparing",
    running: "Editing",
    validating: "Validating",
    waiting_approval: "Ready for review",
    publishing: "Publishing",
    published: "PR created",
    failed: "Failed",
    cancelled: "Cancelled",
    rolled_back: "Rolled back"
  };
  return t(labels[status] || status || "Proposed");
}

function parseEvolutionList(value) {
  return String(value || "")
    .split(/[\n,;]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function evolutionGateSummary(task) {
  const attempt = Array.isArray(task.attempts) ? task.attempts.at(-1) : null;
  const gates = Array.isArray(attempt?.gates) ? attempt.gates : [];
  if (!gates.length) return t("Quality gates pending");
  const passed = gates.filter((gate) => gate.status === "passed").length;
  return t("{passed} of {total} quality gates passed", { passed, total: gates.length });
}

function renderEvolutionHealth() {
  const health = state.evolutionHealth && typeof state.evolutionHealth === "object"
    ? state.evolutionHealth
    : null;
  const element = $("#evolutionHealthSummary");
  if (!health || !Number(health.total_tasks || 0)) {
    element.hidden = true;
    element.innerHTML = "";
    return;
  }
  const decidedGates = Number(health.passed_gates || 0) + Number(health.failed_gates || 0);
  const statusCounts = health.status_counts && typeof health.status_counts === "object"
    ? health.status_counts
    : {};
  const decidedTasks = Number(health.successful_tasks || 0)
    + Number(statusCounts.failed || 0)
    + Number(statusCounts.blocked || 0);
  const metrics = [
    [decidedTasks ? `${Number(health.success_percent || 0)}%` : "--", t("Success")],
    [decidedGates ? `${Number(health.gate_pass_percent || 0)}%` : "--", t("Gate pass")],
    [Number(health.retries || 0), t("Retries")],
    [Number(health.attention_tasks || 0), t("Attention")]
  ];
  element.innerHTML = metrics.map(([value, label]) => `
    <span class="evolution-health-metric">
      <strong>${escapeHtml(value)}</strong>
      <small>${escapeHtml(label)}</small>
    </span>
  `).join("");
  element.classList.toggle("attention", Number(health.attention_tasks || 0) > 0);
  element.hidden = false;
}

function renderEvolutionTasks() {
  const tasks = Array.isArray(state.evolutionTasks) ? state.evolutionTasks : [];
  const active = tasks.filter((task) => ACTIVE_EVOLUTION_STATES.has(task.status)).length;
  const ready = tasks.filter((task) => task.status === "waiting_approval").length;
  const badge = $("#evolutionSummaryBadge");
  badge.textContent = tasks.length
    ? (ready ? t("{count} ready for review", { count: ready }) : active ? t("{count} active", { count: active }) : t("{count} candidates", { count: tasks.length }))
    : t("No candidates");
  badge.className = `state-badge ${ready ? "ok" : ""}`;
  renderEvolutionHealth();
  $("#evolutionTaskList").innerHTML = tasks.map((task) => {
    const status = String(task.status || "proposed");
    const candidate = String(task.candidate_commit || "");
    const error = String(task.last_error || "");
    const detail = error
      ? error
      : candidate
        ? `${t("Candidate")} ${candidate.slice(0, 10)}`
        : evolutionGateSummary(task);
    const actions = [];
    if (ACTIVE_EVOLUTION_STATES.has(status) && status !== "publishing") {
      actions.push(`<button class="secondary-button" data-cancel-evolution="${escapeHtml(task.task_id)}">${escapeHtml(t("Cancel"))}</button>`);
    }
    if (status === "waiting_approval") {
      actions.push(`<button class="secondary-button" data-rollback-evolution="${escapeHtml(task.task_id)}">${escapeHtml(t("Rollback"))}</button>`);
      actions.push(`<button class="primary-button" data-publish-evolution="${escapeHtml(task.task_id)}">${escapeHtml(t("Create PR"))}</button>`);
    }
    return `<article class="evolution-task-row" data-evolution-task="${escapeHtml(task.task_id)}">
      <div>
        <strong>${escapeHtml(task.problem || task.task_id)}</strong>
        <small><span class="evolution-gate-summary">${escapeHtml(evolutionStatusLabel(status))}</span> · ${escapeHtml(detail)}</small>
      </div>
      <div class="evolution-task-actions">${actions.join("")}</div>
    </article>`;
  }).join("");
}

async function refreshEvolutionTasks(showError = false) {
  try {
    const response = await window.signalasi.listEvolutionTasks(50);
    state.evolutionTasks = Array.isArray(response?.tasks) ? response.tasks : [];
    state.evolutionHealth = response?.health && typeof response.health === "object"
      ? response.health
      : null;
    renderEvolutionTasks();
  } catch (error) {
    if (showError) showToast(error.message || String(error));
  }
}

async function createEvolutionCandidate() {
  const button = $("#createEvolutionButton");
  const problem = $("#evolutionProblem").value.trim();
  const scope = parseEvolutionList($("#evolutionScope").value);
  const acceptance = parseEvolutionList($("#evolutionAcceptance").value);
  if (problem.length < 12 || !scope.length || !acceptance.length) {
    showToast(t("Add a clear problem, allowed source path, and acceptance criteria."));
    return;
  }
  button.disabled = true;
  try {
    await window.signalasi.createEvolutionTask({
      problem,
      scope,
      acceptance,
      riskLevel: $("#evolutionRisk").value,
      agentId: $("#evolutionAgent").value,
      maxAttempts: 3,
      start: true
    });
    $("#evolutionProblem").value = "";
    $("#evolutionAcceptance").value = "";
    $(".evolution-create").open = false;
    showToast(t("Isolated candidate started."));
    await refreshEvolutionTasks(true);
  } catch (error) {
    showToast(error.message || String(error));
  } finally {
    button.disabled = false;
  }
}

async function handleEvolutionAction(event) {
  const cancel = event.target.closest("[data-cancel-evolution]");
  const rollback = event.target.closest("[data-rollback-evolution]");
  const publish = event.target.closest("[data-publish-evolution]");
  const button = cancel || rollback || publish;
  if (!button) return;
  button.disabled = true;
  try {
    if (cancel) {
      await window.signalasi.cancelEvolutionTask(cancel.dataset.cancelEvolution);
    } else if (rollback) {
      if (!window.confirm(t("Discard this isolated candidate and its worktree?"))) return;
      await window.signalasi.rollbackEvolutionTask(rollback.dataset.rollbackEvolution);
    } else {
      const task = state.evolutionTasks.find((item) => item.task_id === publish.dataset.publishEvolution);
      if (!task?.approval_hash || !task?.candidate_commit) {
        showToast(t("Candidate identity is incomplete."));
        return;
      }
      const approved = window.confirm(t("Create a PR for candidate {commit}?\n\nApproval hash:\n{hash}", {
        commit: task.candidate_commit.slice(0, 12),
        hash: task.approval_hash
      }));
      if (!approved) return;
      const result = await window.signalasi.publishEvolutionTask(task.task_id, task.approval_hash);
      showToast(result.pull_request_url ? t("Pull request created.") : t("Candidate published."));
      if (result.pull_request_url) await window.signalasi.openExternal(result.pull_request_url);
    }
    await refreshEvolutionTasks(true);
  } catch (error) {
    showToast(error.message || String(error));
  } finally {
    button.disabled = false;
  }
}

const PANEL_META = {
  agents: ["Agents", "Private agents and local execution engines"],
  capabilities: ["Capabilities", "Memory, Skills, MCP, and proactive automation"],
  commands: ["Commands", "Deterministic local command catalog"],
  gateway: ["Mobile Gateway", "Trusted phones and SignalASI Link"],
  settings: ["Settings", "Language, cloud API, commands, and diagnostics"]
};
let panelOpenSequence = 0;

async function openPanel(name) {
  const panelName = Object.hasOwn(PANEL_META, name) ? name : "settings";
  const sequence = ++panelOpenSequence;
  const meta = PANEL_META[panelName];
  elements.drawerTitle.textContent = t(meta[0]);
  elements.drawerSubtitle.textContent = t(meta[1]);
  $$(".drawer-panel").forEach((panel) => panel.classList.remove("active"));
  $(`#${panelName}Panel`)?.classList.add("active");
  elements.backdrop.hidden = false;
  elements.drawer.classList.add("open");
  elements.drawer.setAttribute("aria-hidden", "false");
  elements.drawer.dataset.panelLoading = "true";
  delete elements.drawer.dataset.panelReady;
  try {
    if (panelName === "agents") await refreshAgents();
    if (panelName === "gateway") {
      await Promise.all([refreshGateway(), refreshDesktopControl()]);
      await loadPairingFrame();
    }
    if (panelName === "capabilities") await refreshCapabilities();
    if (panelName === "commands") await Promise.all([refreshCommands(), refreshCommandRuns()]);
    if (panelName === "settings") {
      await Promise.all([refreshBackend(), refreshAgents(), refreshRuntimeManager(false), refreshEvolutionTasks(false)]);
    }
  } finally {
    if (sequence === panelOpenSequence) {
      elements.drawer.dataset.panelLoading = "false";
      elements.drawer.dataset.panelReady = panelName;
    }
  }
}

function closePanel() {
  elements.drawer.classList.remove("open");
  elements.drawer.setAttribute("aria-hidden", "true");
  window.setTimeout(() => { elements.backdrop.hidden = true; }, 180);
}

function latestTask() {
  return conversationTasks().at(-1) || null;
}

async function cancelRunningTask() {
  const task = [...conversationTasks()].reverse().find((item) => !TERMINAL_STATES.has(item.status));
  if (!task) {
    showToast(t("No task is currently running."));
    return;
  }
  await window.signalasi.cancelDesktopTask(task.task_id);
  $("#workspaceMenu").hidden = true;
  await refreshTasks(true);
}

async function retryTask(taskId) {
  try {
    const task = await window.signalasi.retryDesktopTask(taskId);
    if (state.tasks.some((item) => item.task_id === task.task_id)) {
      mergeTaskUpdate(task);
    } else {
      state.tasks.push(task);
    }
    state.renderingSignature = "";
    renderHistory();
    renderConversation(true);
  } catch (error) {
    showToast(`${t("Could not retry task")}: ${error.message || error}`);
  }
}

async function revealWorkspace() {
  const task = latestTask();
  if (!task) return showToast(t("This conversation has no task workspace yet."));
  try { await window.signalasi.revealTaskWorkspace(task.task_id); }
  catch (error) { showToast(error.message || String(error)); }
  $("#workspaceMenu").hidden = true;
}

async function deleteConversation() {
  if (!conversationTasks().length) return newTask();
  if (!window.confirm(t("Delete this conversation and its task history?"))) return;
  await window.signalasi.deleteDesktopConversation(state.currentConversationId);
  newTask();
  await refreshTasks(true);
  $("#workspaceMenu").hidden = true;
}

function startVoiceInput() {
  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!Recognition) {
    showToast(t("Voice input is not available on this desktop."));
    return;
  }
  if (state.speechRecognition) {
    state.speechRecognition.stop();
    return;
  }
  const recognition = new Recognition();
  state.speechRecognition = recognition;
  recognition.lang = resolveLanguagePolicy(
    state.agentConfig?.language_policy?.asr_language || "auto"
  );
  recognition.interimResults = true;
  $("#voiceButton").classList.add("active");
  recognition.onresult = (event) => {
    elements.prompt.value = Array.from(event.results).map((result) => result[0].transcript).join("");
    updateSendState();
  };
  recognition.onerror = (event) => showToast(`${t("Voice input failed")}: ${event.error}`);
  recognition.onend = () => {
    state.speechRecognition = null;
    $("#voiceButton").classList.remove("active");
  };
  recognition.start();
}

function speakTaskResult(taskId) {
  const task = state.tasks.find((item) => item.task_id === taskId);
  const text = String(task?.result || "").trim();
  if (!text || !window.speechSynthesis || !window.SpeechSynthesisUtterance) {
    showToast(t("Text-to-speech is not available on this desktop."));
    return;
  }
  const container = document.createElement("div");
  container.innerHTML = renderMarkdown(text);
  const utterance = new SpeechSynthesisUtterance(container.textContent || text);
  utterance.lang = resolveLanguagePolicy(
    state.agentConfig?.language_policy?.tts_language || "auto"
  );
  const matchingVoice = window.speechSynthesis.getVoices().find((voice) =>
    String(voice.lang || "").toLowerCase().startsWith(utterance.lang.toLowerCase())
  );
  if (matchingVoice) utterance.voice = matchingVoice;
  window.speechSynthesis.cancel();
  window.speechSynthesis.speak(utterance);
}

function bindEvents() {
  $("#newTaskButton").addEventListener("click", () => newTask());
  $("#attachButton").addEventListener("click", addAttachments);
  $("#voiceButton").addEventListener("click", startVoiceInput);
  $("#agentPickerButton").addEventListener("click", () => openPanel("agents"));
  $("#sendButton").addEventListener("click", sendTask);
  $("#autoModeButton").addEventListener("click", () => { state.selectedAgentId = "auto"; state.selectedAgentName = t("Agent"); updateSelectedAgent(); });
  $("#localModeButton").addEventListener("click", () => { state.selectedAgentId = "desktop"; state.selectedAgentName = t("This desktop"); updateSelectedAgent(); });
  elements.prompt.addEventListener("input", updateSendState);
  elements.prompt.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      sendTask();
    }
  });
  elements.history.addEventListener("click", (event) => {
    const item = event.target.closest("[data-conversation-id]");
    if (!item) return;
    state.currentConversationId = item.dataset.conversationId;
    state.emptyConversationIntent = false;
    state.renderingSignature = "";
    renderHistory();
    renderConversation(true);
  });
  elements.messages.addEventListener("click", async (event) => {
    const speak = event.target.closest("[data-speak-task]");
    if (speak) {
      speakTaskResult(speak.dataset.speakTask);
      return;
    }
    const retry = event.target.closest("[data-retry-task]");
    if (retry) {
      await retryTask(retry.dataset.retryTask);
      return;
    }
    const toggle = event.target.closest("[data-toggle-run]");
    if (toggle) {
      const detail = elements.messages.querySelector(`[data-run-detail="${CSS.escape(toggle.dataset.toggleRun)}"]`);
      if (detail) detail.hidden = !detail.hidden;
      return;
    }
    const artifact = event.target.closest("[data-open-artifact]");
    if (artifact) {
      try { await window.signalasi.openTaskArtifact(artifact.dataset.taskId, artifact.dataset.openArtifact); }
      catch (error) { showToast(error.message || String(error)); }
    }
    const link = event.target.closest("[data-external-link]");
    if (link) {
      event.preventDefault();
      await window.signalasi.openExternal(link.dataset.externalLink);
    }
  });
  elements.attachments.addEventListener("click", (event) => {
    const button = event.target.closest("[data-remove-attachment]");
    if (!button) return;
    state.attachments.splice(Number(button.dataset.removeAttachment), 1);
    renderAttachmentTray();
  });
  $$('[data-open-panel]').forEach((button) => button.addEventListener("click", () => openPanel(button.dataset.openPanel)));
  $("#closeDrawer").addEventListener("click", closePanel);
  elements.backdrop.addEventListener("click", closePanel);
  $("#refreshAgentsButton").addEventListener("click", refreshAgents);
  $("#agentContactList").addEventListener("click", (event) => {
    const use = event.target.closest("[data-use-agent]");
    const chat = event.target.closest("[data-chat-agent]");
    const button = use || chat;
    if (!button) return;
    const id = button.dataset.useAgent || button.dataset.chatAgent;
    const name = agentName(id);
    if (chat) newTask(id, name);
    else { state.selectedAgentId = id; state.selectedAgentName = name; updateSelectedAgent(); }
    closePanel();
  });
  $("#saveCustomAgentButton").addEventListener("click", saveCustomAgent);
  $("#saveAgentCommandsButton").addEventListener("click", saveAgentCommands);
  $("#cloudProvider").addEventListener("change", applyCloudProviderPreset);
  $("#saveCloudModelButton").addEventListener("click", () => saveCloudModelSettings(false));
  $("#testCloudModelButton").addEventListener("click", () => saveCloudModelSettings(true));
  $("#saveWebSearchButton").addEventListener("click", saveWebSearchSettings);
  $("#refreshGatewayButton").addEventListener("click", async () => {
    $("#pairingFrame").removeAttribute("src");
    await Promise.all([refreshGateway(), refreshDesktopControl()]);
    await loadPairingFrame();
  });
  $("#pairingDesktopExecutorEnabled").addEventListener("change", async (event) => {
    state.pairingGrantDesktopExecutor = Boolean(event.target.checked);
    $("#pairingFrame").removeAttribute("src");
    try {
      await loadPairingFrame();
      await refreshDesktopControl();
    } catch (error) {
      showToast(error.message || String(error));
    }
  });
  $("#pairedClientList").addEventListener("click", async (event) => {
    const button = event.target.closest("[data-revoke-client]");
    if (!button || !window.confirm(t("Revoke this phone? It must scan the QR code again."))) return;
    await window.signalasi.clearPairing(button.dataset.revokeClient);
    await refreshGateway();
    await refreshDesktopControl();
  });
  $$('[data-capability-tab]').forEach((button) => button.addEventListener("click", () => selectCapabilityTab(button.dataset.capabilityTab)));
  $("#refreshMemoryButton").addEventListener("click", () => refreshMemory($("#memorySearch").value.trim()));
  let memorySearchTimer = 0;
  $("#memorySearch").addEventListener("input", () => {
    window.clearTimeout(memorySearchTimer);
    memorySearchTimer = window.setTimeout(() => refreshMemory($("#memorySearch").value.trim()), 240);
  });
  $("#addMemoryButton").addEventListener("click", () => addMemory().catch((error) => showToast(error.message || String(error))));
  $("#memoryList").addEventListener("click", async (event) => {
    const button = event.target.closest("[data-forget-memory]");
    if (!button) return;
    await window.signalasi.forgetDesktopMemory(button.dataset.forgetMemory);
    await refreshMemory($("#memorySearch").value.trim());
  });
  $("#saveSkillButton").addEventListener("click", () => saveSkill().catch((error) => showToast(error.message || String(error))));
  $("#skillList").addEventListener("click", async (event) => {
    const toggle = event.target.closest("[data-toggle-skill]");
    const remove = event.target.closest("[data-delete-skill]");
    if (toggle) await window.signalasi.setDesktopSkillEnabled(toggle.dataset.toggleSkill, toggle.dataset.enabled !== "1");
    if (remove && window.confirm(t("Delete this skill?"))) await window.signalasi.deleteDesktopSkill(remove.dataset.deleteSkill);
    if (toggle || remove) await refreshCapabilities();
  });
  $("#saveMcpButton").addEventListener("click", () => saveMcp().catch((error) => showToast(error.message || String(error))));
  $("#mcpList").addEventListener("click", async (event) => {
    const probe = event.target.closest("[data-probe-mcp]");
    const chat = event.target.closest("[data-chat-mcp]");
    const remove = event.target.closest("[data-delete-mcp]");
    if (probe) {
      const result = await window.signalasi.probeDesktopMcp(probe.dataset.probeMcp);
      const names = (result.tools || []).map((tool) => tool.name).join(", ");
      showToast(result.status === "ready" ? `${t("MCP ready")}: ${names}` : `${t("MCP failed")}: ${result.error || ""}`);
    }
    if (chat) {
      const connection = state.mcp.find((item) => item.id === chat.dataset.chatMcp);
      newTask(`mcp:${chat.dataset.chatMcp}`, connection?.name || chat.dataset.chatMcp);
      closePanel();
    }
    if (remove && window.confirm(t("Delete this MCP connection?"))) {
      await window.signalasi.deleteDesktopMcp(remove.dataset.deleteMcp);
      await refreshCapabilities();
    }
  });
  $("#refreshProactiveButton").addEventListener("click", () =>
    refreshCapabilities().catch((error) => showToast(error.message || String(error))));
  $("#createProactiveButton").addEventListener("click", createProactiveTask);
  $("#cancelProactiveEditButton").addEventListener("click", () => {
    resetProactiveEditor();
    $("#proactiveCreateDetails").open = false;
  });
  $("#proactiveTriggerKind").addEventListener("change", syncProactiveFormVisibility);
  $("#proactiveActionKind").addEventListener("change", syncProactiveFormVisibility);
  $("#proactiveTaskList").addEventListener("click", handleProactiveAction);
  $("#proactiveRunList").addEventListener("click", handleProactiveAction);
  $("#runDiagnosticsButton").addEventListener("click", runDiagnostics);
  $("#refreshRuntimeButton").addEventListener("click", () => refreshRuntimeManager(true));
  $("#refreshCommandsButton").addEventListener("click", refreshCommands);
  $("#refreshCommandRunsButton").addEventListener("click", refreshCommandRuns);
  $("#executeCommandButton").addEventListener("click", executeCommandFromPanel);
  $("#commandRootFilter").addEventListener("keydown", (event) => {
    if (event.key === "Enter") refreshCommands();
  });
  $("#commandInput").addEventListener("keydown", (event) => {
    if (event.key === "Enter") executeCommandFromPanel();
  });
  $("#commandCatalog").addEventListener("click", (event) => {
    const row = event.target.closest("[data-command-id]");
    if (!row) return;
    $("#commandInput").value = row.dataset.commandId || "";
    $("#commandResult").textContent = JSON.stringify({ command_id: row.dataset.commandId || "" }, null, 2);
  });
  $("#createEvolutionButton").addEventListener("click", createEvolutionCandidate);
  $("#evolutionTaskList").addEventListener("click", handleEvolutionAction);
  $("#languageSelect").addEventListener("change", (event) => setLanguage(event.target.value));
  $("#responseLanguageSelect").addEventListener("change", () => saveLanguagePolicySettings().catch((error) => showToast(error.message || String(error))));
  $("#asrLanguageSelect").addEventListener("change", () => saveLanguagePolicySettings().catch((error) => showToast(error.message || String(error))));
  $("#ttsLanguageSelect").addEventListener("change", () => saveLanguagePolicySettings().catch((error) => showToast(error.message || String(error))));
  $("#workspaceMenuButton").addEventListener("click", () => { $("#workspaceMenu").hidden = !$("#workspaceMenu").hidden; });
  $("#cancelRunningTask").addEventListener("click", cancelRunningTask);
  $("#revealWorkspaceButton").addEventListener("click", revealWorkspace);
  $("#deleteConversationButton").addEventListener("click", deleteConversation);
  document.addEventListener("click", (event) => {
    if (!event.target.closest("#workspaceMenu") && !event.target.closest("#workspaceMenuButton")) $("#workspaceMenu").hidden = true;
  });
}

async function init() {
  bindEvents();
  const appVersion = await window.signalasi.getAppVersion();
  elements.desktopVersion.textContent = `v${appVersion}`;
  await setLanguage(state.languagePreference, false);
  resetProactiveEditor();
  renderAgentContacts();
  updateAgentCounters();
  updateSelectedAgent();
  updateSendState();
  await refreshBackend();
  await Promise.all([refreshAgents(), refreshGateway(), refreshDesktopControl(), refreshCapabilities(), refreshTasks(true)]);
  connectTaskStream();
  window.setInterval(updateElapsedLabels, 1000);
  window.setInterval(() => {
    if (!state.taskStreamConnected) refreshTasks(false);
  }, 10_000);
  window.setInterval(() => { refreshBackend(); refreshGateway(); }, 30_000);
  window.setInterval(() => {
    if (elements.drawer.classList.contains("open") && $("#gatewayPanel").classList.contains("active")) {
      refreshDesktopControl();
    }
    if (elements.drawer.classList.contains("open") && $("#settingsPanel").classList.contains("active")
        && state.evolutionTasks.some((task) => ACTIVE_EVOLUTION_STATES.has(task.status))) {
      refreshEvolutionTasks(false);
    }
  }, 2_000);
}

init().catch((error) => showToast(error.stack || error.message || String(error)));
