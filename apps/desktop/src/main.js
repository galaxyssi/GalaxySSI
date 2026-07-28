const { app, BrowserWindow, clipboard, dialog, ipcMain, shell } = require("electron");
const { spawn, spawnSync, execFile } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

const requestedBackendPort = Number.parseInt(process.env.SIGNALASI_BACKEND_PORT || "8765", 10);
const BACKEND_PORT = requestedBackendPort >= 1024 && requestedBackendPort <= 65535
  ? requestedBackendPort
  : 8765;
const BACKEND_ORIGIN = `http://127.0.0.1:${BACKEND_PORT}`;
const DESKTOP_TASK_STREAM_URL = `ws://127.0.0.1:${BACKEND_PORT}/ws/desktop/tasks`;
const PAIRING_URL = `${BACKEND_ORIGIN}/signalasi/verify`;
const APP_ROOT = path.resolve(__dirname, "..");
const DEV_BACKEND_DIR = path.join(APP_ROOT, "core", "signalasi-link", "backend");
const PACKAGED_BACKEND_DIR = path.resolve(APP_ROOT, "..", "signalasi-link", "backend");
const BACKEND_DIR = fs.existsSync(DEV_BACKEND_DIR) ? DEV_BACKEND_DIR : PACKAGED_BACKEND_DIR;
const RUNTIME_ROOT = fs.existsSync(DEV_BACKEND_DIR) ? APP_ROOT : path.resolve(APP_ROOT, "..");
const UI_SMOKE = process.env.SIGNALASI_UI_SMOKE === "1";
if (UI_SMOKE) {
  const smokeUserData = path.join(process.env.SIGNALASI_UI_SMOKE_DIR || path.join(RUNTIME_ROOT, "ui-smoke"), "user-data");
  app.setPath("userData", smokeUserData);
}

let mainWindow;
let backendProcess;
let backendRestartTimer;
let appIsQuitting = false;
let cachedDesktopTaskStreamToken = "";

const hasSingleInstanceLock = app.requestSingleInstanceLock();
if (!hasSingleInstanceLock) {
  app.quit();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 960,
    height: 640,
    title: "SignalASI Desktop",
    icon: path.join(APP_ROOT, "assets", "signalasi-mark.png"),
    backgroundColor: "#f5f6f7",
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      backgroundThrottling: !UI_SMOKE
    }
  });

  mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));
  if (UI_SMOKE) {
    mainWindow.webContents.on("console-message", (_event, level, message, line, sourceId) => {
      console.log(`[renderer:${level}] ${message} (${sourceId}:${line})`);
    });
    mainWindow.webContents.once("did-finish-load", runUiSmoke);
  }
}

async function runUiSmoke() {
  const outDir = process.env.SIGNALASI_UI_SMOKE_DIR || path.join(RUNTIME_ROOT, "ui-smoke");
  const overviewPath = path.join(outDir, "desktop-overview.png");
  const languageEnPath = path.join(outDir, "desktop-language-en.png");
  const languageZhPath = path.join(outDir, "desktop-language-zh.png");
  const setupPath = path.join(outDir, "desktop-setup-guide.png");
  const matrixPath = path.join(outDir, "desktop-status-matrix.png");
  const agentsPath = path.join(outDir, "desktop-agents.png");
  const capabilitiesPath = path.join(outDir, "desktop-capabilities.png");
  const settingsPath = path.join(outDir, "desktop-settings.png");
  const evolutionV2Path = path.join(outDir, "desktop-evolution-v2.png");
  const runtimePath = path.join(outDir, "desktop-runtimes.png");
  try {
    fs.mkdirSync(outDir, { recursive: true });
    let state;
    for (let attempt = 0; attempt < 60; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 500));
      state = await mainWindow.webContents.executeJavaScript(`(() => ({
        app: Boolean(document.querySelector("#agentApp")),
        title: document.querySelector("#conversationTitle")?.textContent || "",
        composer: Boolean(document.querySelector("#promptInput")),
        backend: document.querySelector("#backendBadge")?.textContent || "",
        agents: document.querySelectorAll("#agentContactList .agent-contact").length
      }))()`);
      if (state.app && state.title.trim() && state.composer && state.backend.trim()) break;
    }
    if (!state?.app || !state.title.trim() || !state.composer || !state.backend.trim()) {
      throw new Error(`Desktop Agent workspace did not render: ${JSON.stringify(state)}`);
    }
    const defaultLanguage = await mainWindow.webContents.executeJavaScript(`
      (() => ({
        lang: document.documentElement.lang,
        selected: document.querySelector("#languageSelect")?.value || "",
        title: document.querySelector("#conversationTitle")?.textContent || "",
        system: navigator.language || ""
      }))()
    `);
    const systemUsesChinese = String(defaultLanguage.system || "").toLowerCase().startsWith("zh");
    const expectedDefaultLanguage = systemUsesChinese ? "zh-Hans" : "en";
    const expectedDefaultTitle = systemUsesChinese ? "\u65b0\u5efa\u4efb\u52a1" : "New task";
    if (defaultLanguage.lang !== expectedDefaultLanguage
        || defaultLanguage.selected !== "auto"
        || defaultLanguage.title !== expectedDefaultTitle) {
      throw new Error(`Desktop did not follow the system language by default: ${JSON.stringify(defaultLanguage)}`);
    }
    await captureSmokeScreenshot(languageEnPath);
    const zhLanguage = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        const select = document.querySelector("#languageSelect");
        select.value = "zh-CN";
        select.dispatchEvent(new Event("change", { bubbles: true }));
        await new Promise((resolve) => setTimeout(resolve, 900));
        return {
          lang: document.documentElement.lang,
          selected: select.value,
          title: document.querySelector("#conversationTitle")?.textContent || ""
        };
      })()
    `);
    if (zhLanguage.lang !== "zh-Hans" || zhLanguage.selected !== "zh-CN" || zhLanguage.title !== "\u65b0\u5efa\u4efb\u52a1") {
      throw new Error(`Desktop Simplified Chinese language switch failed: ${JSON.stringify(zhLanguage)}`);
    }
    await captureSmokeScreenshot(languageZhPath);
    const restoredLanguage = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        const select = document.querySelector("#languageSelect");
        select.value = "en";
        select.dispatchEvent(new Event("change", { bubbles: true }));
        await new Promise((resolve) => setTimeout(resolve, 900));
        return {
          lang: document.documentElement.lang,
          selected: select.value,
          title: document.querySelector("#conversationTitle")?.textContent || ""
        };
      })()
    `);
    if (restoredLanguage.lang !== "en" || restoredLanguage.selected !== "en" || restoredLanguage.title !== "New task") {
      throw new Error(`Desktop English language restore failed: ${JSON.stringify(restoredLanguage)}`);
    }
    await captureSmokeScreenshot(overviewPath);
    const agentsState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        document.querySelector('[data-open-panel="agents"]')?.click();
        for (let attempt = 0; attempt < 30; attempt += 1) {
          if (document.querySelectorAll("#agentContactList .agent-contact").length > 0) break;
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
        return {
          open: document.querySelector("#utilityDrawer")?.classList.contains("open") || false,
          active: document.querySelector("#agentsPanel")?.classList.contains("active") || false,
          contacts: document.querySelectorAll("#agentContactList .agent-contact").length,
          customFields: document.querySelectorAll("#agentsPanel .form-stack input").length,
          contactText: document.querySelector("#agentContactList")?.textContent || ""
        };
      })()
    `);
    if (!agentsState.open || !agentsState.active || agentsState.contacts < 1 || agentsState.customFields < 3) {
      throw new Error(`Agent drawer did not expose contacts and custom Agent setup: ${JSON.stringify(agentsState)}`);
    }
    await captureSmokeScreenshot(agentsPath);
    const capabilitiesState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        document.querySelector('[data-open-panel="capabilities"]')?.click();
        for (let attempt = 0; attempt < 40; attempt += 1) {
          if (document.querySelectorAll("#skillList .capability-item").length >= 4) break;
          await new Promise((resolve) => setTimeout(resolve, 250));
        }
        document.querySelector('[data-capability-tab="automation"]')?.click();
        await new Promise((resolve) => setTimeout(resolve, 250));
        return {
          active: document.querySelector("#capabilitiesPanel")?.classList.contains("active") || false,
          tabs: document.querySelectorAll("[data-capability-tab]").length,
          skills: document.querySelectorAll("#skillList .capability-item").length,
          memory: document.querySelector("#memorySummary")?.textContent || "",
          mcpForm: Boolean(document.querySelector("#mcpCommand")),
          automationActive: document.querySelector("#automationCapability")?.classList.contains("active") || false,
          automationSummary: document.querySelector("#proactiveSummary")?.textContent || "",
          automationEditor: Boolean(document.querySelector("#proactiveCreateDetails"))
        };
      })()
    `);
    if (!capabilitiesState.active || capabilitiesState.tabs !== 4 || capabilitiesState.skills < 4
        || !capabilitiesState.memory.trim() || !capabilitiesState.mcpForm
        || !capabilitiesState.automationActive || !capabilitiesState.automationSummary.trim()
        || !capabilitiesState.automationEditor) {
      throw new Error(`Capabilities drawer did not expose memory, Skills, MCP, and automation: ${JSON.stringify(capabilitiesState)}`);
    }
    await captureSmokeScreenshot(capabilitiesPath);
    const gatewayControlState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        document.querySelector('[data-open-panel="gateway"]')?.click();
        for (let attempt = 0; attempt < 30; attempt += 1) {
          if (document.querySelector("#desktopControlAuditList")?.children.length > 0) break;
          await new Promise((resolve) => setTimeout(resolve, 250));
        }
        const history = document.querySelector(".gateway-access-history");
        if (history) history.open = true;
        return {
          active: document.querySelector("#gatewayPanel")?.classList.contains("active") || false,
          accessHistory: document.querySelector("#desktopControlAuditList")?.children.length || 0,
          pairingExecutor: Boolean(document.querySelector("#pairingDesktopExecutorEnabled")),
          computerPanel: Boolean(document.querySelector("#computerPanel")),
          desktopToolList: Boolean(document.querySelector("#desktopToolList"))
        };
      })()
    `);
    if (
      !gatewayControlState.active
      || gatewayControlState.accessHistory < 1
      || !gatewayControlState.pairingExecutor
      || gatewayControlState.computerPanel
      || gatewayControlState.desktopToolList
    ) {
      throw new Error(`Mobile Gateway did not consolidate Desktop control access: ${JSON.stringify(gatewayControlState)}`);
    }
    await captureSmokeScreenshot(setupPath);
    const settingsState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        if (typeof openPanel === "function") {
          await openPanel("settings");
        } else {
          document.querySelector('[data-open-panel="settings"]')?.click();
        }
        for (let attempt = 0; attempt < 100; attempt += 1) {
          if (
            document.querySelector("#settingsPanel")?.classList.contains("active")
            && document.querySelector("#drawerTitle")?.textContent?.trim()
            && document.querySelector("#utilityDrawer")?.dataset.panelReady === "settings"
            && document.querySelector("#utilityDrawer")?.dataset.panelLoading === "false"
            && document.querySelector("#cloudModelBadge")?.textContent?.trim()
            && document.querySelector("#evolutionV2Shell")
          ) break;
          await new Promise((resolve) => setTimeout(resolve, 250));
        }
        return {
          active: document.querySelector("#settingsPanel")?.classList.contains("active") || false,
          title: document.querySelector("#drawerTitle")?.textContent || "",
          ready: document.querySelector("#utilityDrawer")?.dataset.panelReady || "",
          provider: document.querySelector("#cloudProvider")?.value || "",
          fields: document.querySelectorAll("#settingsPanel .cloud-settings-surface input, #settingsPanel .cloud-settings-surface select").length,
          save: Boolean(document.querySelector("#saveCloudModelButton")),
          test: Boolean(document.querySelector("#testCloudModelButton")),
          badge: document.querySelector("#cloudModelBadge")?.textContent || "",
          evolution: {
            form: Boolean(document.querySelector(".evolution-create")),
            problem: Boolean(document.querySelector("#evolutionProblem")),
            scope: Boolean(document.querySelector("#evolutionScope")),
            acceptance: Boolean(document.querySelector("#evolutionAcceptance")),
            list: Boolean(document.querySelector("#evolutionTaskList"))
          },
          evolutionV2: {
            shell: Boolean(document.querySelector("#evolutionV2Shell")),
            toolbar: Boolean(document.querySelector("#evolutionV2Shell .evolution-v2-toolbar")),
            tabs: document.querySelectorAll("#evolutionV2Shell .evolution-v2-tab").length,
            stylesheet: Array.from(document.styleSheets).some(
              (sheet) => String(sheet.href || "").endsWith("/evolution-v2-panel.css")
            )
          },
          languagePolicy: [
            document.querySelector("#responseLanguageSelect")?.value || "",
            document.querySelector("#asrLanguageSelect")?.value || "",
            document.querySelector("#ttsLanguageSelect")?.value || ""
          ],
          secureValidation: validateCloudModelSettings({
            url: "https://api.example.com/v1/chat/completions",
            model: "test-model",
            api_key: "test-key",
            context_window_tokens: 8192,
            max_output_tokens: 1024
          }),
          insecureValidation: validateCloudModelSettings({
            url: "http://api.example.com/v1/chat/completions",
            model: "test-model",
            api_key: "test-key",
            context_window_tokens: 8192,
            max_output_tokens: 1024
          }),
          budgetValidation: validateCloudModelSettings({
            url: "https://api.example.com/v1/chat/completions",
            model: "test-model",
            api_key: "test-key",
            context_window_tokens: 4096,
            max_output_tokens: 4096
          })
        };
      })()
    `);
    if (!settingsState.active || !settingsState.title.trim() || settingsState.ready !== "settings"
        || settingsState.fields < 7 || !settingsState.save || !settingsState.test
        || !settingsState.badge.trim() || settingsState.secureValidation
        || !settingsState.insecureValidation || !settingsState.budgetValidation
        || Object.values(settingsState.evolution).some((value) => !value)
        || !settingsState.evolutionV2.shell || !settingsState.evolutionV2.toolbar
        || settingsState.evolutionV2.tabs !== 6 || !settingsState.evolutionV2.stylesheet
        || settingsState.languagePolicy.some((value) => value !== "auto")) {
      throw new Error(`Settings drawer did not expose cloud API configuration: ${JSON.stringify(settingsState)}`);
    }
    await captureSmokeScreenshot(settingsPath);
    const evolutionViewportState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        const shell = document.querySelector("#evolutionV2Shell");
        const panel = document.querySelector("#settingsPanel");
        if (!shell || !panel) return { visible: false, scrollTop: 0 };
        panel.style.scrollBehavior = "auto";
        const pinEvolutionPanel = () => {
          panel.scrollTop = Math.max(
            0,
            panel.scrollTop
              + shell.getBoundingClientRect().top
              - panel.getBoundingClientRect().top
              - 12
          );
        };
        clearInterval(window.__signalasiSmokeEvolutionPin);
        pinEvolutionPanel();
        window.__signalasiSmokeEvolutionPin = setInterval(pinEvolutionPanel, 50);
        await new Promise((resolve) => setTimeout(resolve, 300));
        const shellRect = shell.getBoundingClientRect();
        const panelRect = panel.getBoundingClientRect();
        return {
          visible: shellRect.top >= panelRect.top && shellRect.top < panelRect.bottom,
          scrollTop: panel.scrollTop,
          shellTop: shellRect.top,
          panelTop: panelRect.top,
          panelBottom: panelRect.bottom
        };
      })()
    `);
    if (!evolutionViewportState.visible || evolutionViewportState.scrollTop <= 0) {
      throw new Error(`Evolution V2 panel was not visible for UI smoke: ${JSON.stringify(evolutionViewportState)}`);
    }
    await mainWindow.webContents.executeJavaScript(`
      (() => {
        document.querySelector("#evolutionV2SmokePreview")?.remove();
        const shell = document.querySelector("#evolutionV2Shell");
        const drawer = document.querySelector("#utilityDrawer");
        if (!shell || !drawer) return false;
        const preview = shell.cloneNode(true);
        preview.id = "evolutionV2SmokePreview";
        preview.setAttribute("aria-hidden", "true");
        Object.assign(preview.style, {
          position: "fixed",
          zIndex: "32",
          top: "70px",
          right: "0",
          width: drawer.getBoundingClientRect().width + "px",
          height: "calc(100vh - 70px)",
          margin: "0",
          padding: "15px 16px 28px",
          overflowY: "auto",
          boxSizing: "border-box",
          background: "#f7f8f9",
          transform: "translateZ(0)",
          willChange: "transform"
        });
        document.body.append(preview);
        return new Promise((resolve) => {
          requestAnimationFrame(() => requestAnimationFrame(() => resolve(true)));
        });
      })()
    `);
    mainWindow.showInactive();
    await captureSmokeScreenshot(evolutionV2Path, 1_000);
    await mainWindow.webContents.executeJavaScript(`
      clearInterval(window.__signalasiSmokeEvolutionPin);
      delete window.__signalasiSmokeEvolutionPin;
      document.querySelector("#evolutionV2SmokePreview")?.remove();
    `);
    const runtimeState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        for (let attempt = 0; attempt < 80; attempt += 1) {
          if (document.querySelectorAll("#runtimeManagerList .runtime-row").length >= 10) break;
          await new Promise((resolve) => setTimeout(resolve, 250));
        }
        const target = document.querySelector("#runtimeManagerList");
        const panel = document.querySelector("#settingsPanel");
        if (target && panel) {
          panel.scrollTop = Math.max(0, target.offsetTop - panel.clientHeight / 3);
        }
        await new Promise((resolve) => setTimeout(resolve, 500));
        return {
          rows: document.querySelectorAll("#runtimeManagerList .runtime-row").length,
          summary: document.querySelector("#runtimeManagerSummary")?.textContent || "",
          statuses: Array.from(document.querySelectorAll("#runtimeManagerList .state-badge")).map((node) => node.textContent || ""),
          scrollTop: panel?.scrollTop || 0
        };
      })()
    `);
    if (runtimeState.rows < 10 || !runtimeState.summary.trim() || runtimeState.statuses.length !== runtimeState.rows || runtimeState.scrollTop < 1) {
      throw new Error(`Desktop runtime manager did not render verified inventory: ${JSON.stringify(runtimeState)}`);
    }
    await captureSmokeScreenshot(runtimePath);
    const gatewayState = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        document.querySelector('[data-open-panel="gateway"]')?.click();
        const pairing = document.querySelector("#pairingDetails");
        if (pairing) pairing.open = true;
        for (let attempt = 0; attempt < 60; attempt += 1) {
          const frame = document.querySelector("#pairingFrame");
          const hasFrame = Boolean(frame?.src && frame.complete);
          if (hasFrame) break;
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
        const frame = document.querySelector("#pairingFrame");
        return {
          active: document.querySelector("#gatewayPanel")?.classList.contains("active") || false,
          frame: Boolean(frame?.src && frame.complete),
          frameWidth: Math.round(frame?.getBoundingClientRect().width || 0),
          clients: document.querySelectorAll("#pairedClientList .paired-client").length,
          summary: document.querySelector("#gatewaySummary")?.textContent || ""
        };
      })()
    `);
    if (!gatewayState.active || !gatewayState.frame || gatewayState.frameWidth > 161 || !gatewayState.summary.trim()) {
      throw new Error(`Gateway drawer did not render: ${JSON.stringify(gatewayState)}`);
    }
    await captureSmokeScreenshot(matrixPath);
    console.log(`[ui-smoke] screenshot: ${overviewPath}`);
    console.log(`[ui-smoke] screenshot: ${languageEnPath}`);
    console.log(`[ui-smoke] screenshot: ${languageZhPath}`);
    console.log(`[ui-smoke] screenshot: ${setupPath}`);
    console.log(`[ui-smoke] screenshot: ${matrixPath}`);
    console.log(`[ui-smoke] screenshot: ${agentsPath}`);
    console.log(`[ui-smoke] screenshot: ${capabilitiesPath}`);
    console.log(`[ui-smoke] screenshot: ${settingsPath}`);
    console.log(`[ui-smoke] screenshot: ${evolutionV2Path}`);
    console.log(`[ui-smoke] screenshot: ${runtimePath}`);
    app.exit(0);
  } catch (error) {
    console.error(`[ui-smoke] failed: ${error.stack || error.message || error}`);
    app.exit(1);
  }
}

async function captureSmokeScreenshot(target, initialDelayMs = 200) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const delayMs = attempt === 0 ? initialDelayMs : 500;
    if (delayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
    const image = await mainWindow.webContents.capturePage();
    const png = image.toPNG();
    if (png.length >= 1000) {
      fs.writeFileSync(target, png);
      return;
    }
  }
  throw new Error(`UI smoke screenshot was empty: ${target}`);
}

function findPython() {
  const bundledPython = path.join(RUNTIME_ROOT, "python", "venv", "Scripts", "python.exe");
  const candidates = [
    process.env.SIGNALASI_PYTHON,
    bundledPython,
    path.join(os.homedir(), "AppData", "Local", "hermes", "hermes-agent", "venv", "Scripts", "python.exe"),
    path.join(os.homedir(), "AppData", "Roaming", "uv", "python", "cpython-3.11-windows-x86_64-none", "python.exe"),
    "python"
  ].filter(Boolean);
  return candidates.find((candidate) => candidate === "python" || fs.existsSync(candidate)) || "python";
}

async function backendStatus() {
  try {
    const response = await fetch(`${BACKEND_ORIGIN}/api/agents/diagnostics`, { method: "GET" });
    const payload = response.ok ? await response.json() : null;
    const identityMatches = payload?.protocol === "SignalASI Link Protocol"
      && payload?.connector === "SignalASI Desktop";
    return {
      running: response.ok && identityMatches,
      status: response.status,
      identityMatches,
      origin: BACKEND_ORIGIN,
      pairingUrl: PAIRING_URL,
      backendDir: BACKEND_DIR,
      error: response.ok && !identityMatches
        ? `Port ${BACKEND_PORT} is owned by another service.`
        : undefined
    };
  } catch (error) {
    return {
      running: false,
      status: 0,
      origin: BACKEND_ORIGIN,
      pairingUrl: PAIRING_URL,
      backendDir: BACKEND_DIR,
      error: error.message
    };
  }
}

function desktopTaskStreamToken() {
  if (cachedDesktopTaskStreamToken) return cachedDesktopTaskStreamToken;
  const runtimeDir = path.join(app.getPath("userData"), "runtime");
  const tokenPath = path.join(runtimeDir, "desktop_task_stream_token");
  fs.mkdirSync(runtimeDir, { recursive: true });
  try {
    const existing = fs.readFileSync(tokenPath, "utf8").trim();
    if (/^[A-Za-z0-9_-]{32,128}$/.test(existing)) {
      cachedDesktopTaskStreamToken = existing;
      return existing;
    }
  } catch {
    // Create the token below.
  }
  cachedDesktopTaskStreamToken = crypto.randomBytes(32).toString("base64url");
  fs.writeFileSync(tokenPath, cachedDesktopTaskStreamToken, { encoding: "utf8", mode: 0o600 });
  return cachedDesktopTaskStreamToken;
}

function reclaimLegacyBackendPort() {
  if (process.platform !== "win32") return Promise.resolve({ reclaimed: false });
  const script = `
$owner = Get-NetTCPConnection -LocalPort ${BACKEND_PORT} -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $owner) { exit 3 }
$process = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $owner.OwningProcess) -ErrorAction SilentlyContinue
$combined = ""
$cursor = $process
for ($depth = 0; $cursor -and $depth -lt 8; $depth++) {
  $combined += " " + [string]$cursor.CommandLine
  if (-not $cursor.ParentProcessId) { break }
  $cursor = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $cursor.ParentProcessId) -ErrorAction SilentlyContinue
}
$combined = $combined.ToLowerInvariant().Replace('\\', '/')
$legacy = $combined.Contains('/hermesworkspace/signalasi-desktop-win/') -or $combined.Contains('/hermesworkspace/hermeschat/backend')
if (-not $legacy) { exit 2 }
Stop-Process -Id $owner.OwningProcess -Force -ErrorAction Stop
exit 0
`;
  return new Promise((resolve) => {
    execFile("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], { windowsHide: true, timeout: 5000 }, (error) => {
      resolve({ reclaimed: !error, code: error?.code ?? 0 });
    });
  });
}

async function startBackend() {
  let current = await backendStatus();
  if (current.running) return current;
  if (current.status > 0 && current.identityMatches === false) {
    const reclaim = await reclaimLegacyBackendPort();
    if (!reclaim.reclaimed) {
      return { ...current, portConflict: true };
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
    current = await backendStatus();
  }
  if (!fs.existsSync(path.join(BACKEND_DIR, "main.py"))) {
    return { ...current, error: `Backend not found: ${BACKEND_DIR}` };
  }
  if (backendProcess && !backendProcess.killed) {
    for (let attempt = 0; attempt < 12; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 500));
      const status = await backendStatus();
      if (status.running) return status;
    }
    return backendStatus();
  }

  const python = findPython();
  const signalasiDataDir = path.join(app.getPath("userData"), "runtime");
  fs.mkdirSync(signalasiDataDir, { recursive: true });
  const backendLogPath = path.join(app.getPath("userData"), "backend.log");
  const backendLog = fs.openSync(backendLogPath, "a");
  try {
    backendProcess = spawn(python, ["-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", String(BACKEND_PORT)], {
      cwd: BACKEND_DIR,
      env: {
        ...process.env,
        SIGNALASI_DATA_DIR: signalasiDataDir,
        SIGNALASI_DESKTOP_TASK_STREAM_TOKEN: desktopTaskStreamToken(),
        PYTHONUNBUFFERED: "1"
      },
      windowsHide: true,
      stdio: ["ignore", backendLog, backendLog],
      detached: false
    });
  } catch (error) {
    return { ...current, error: error.message || String(error) };
  }

  backendProcess.on("exit", () => {
    backendProcess = undefined;
    if (appIsQuitting || backendRestartTimer) return;
    backendRestartTimer = setTimeout(async () => {
      backendRestartTimer = undefined;
      const status = await backendStatus();
      if (!status.running && !appIsQuitting) startBackend();
    }, 1500);
  });

  for (let attempt = 0; attempt < 12; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    const status = await backendStatus();
    if (status.running) return status;
  }
  return backendStatus();
}

function commandExists(command, args = ["--version"]) {
  return new Promise((resolve) => {
    try {
      execFile(command, args, { windowsHide: true, timeout: 2500 }, (error, stdout, stderr) => {
        resolve({
          ok: !error,
          code: error?.code ?? 0,
          output: String(stdout || stderr || error?.message || "").split(/\r?\n/)[0].trim()
        });
      });
    } catch (error) {
      resolve({
        ok: false,
        code: error?.code ?? 1,
        output: error.message || String(error)
      });
    }
  });
}

function runCommand(command, args = [], timeout = 5000) {
  return new Promise((resolve) => {
    execFile(command, args, { windowsHide: true, timeout }, (error, stdout, stderr) => {
      resolve({
        ok: !error,
        code: error?.code ?? 0,
        output: String(stdout || stderr || "").trim()
      });
    });
  });
}

function loadLocale(language) {
  const normalized = language === "en" ? "en" : "zh-CN";
  const localePath = path.join(APP_ROOT, "src", "renderer", "locales", `${normalized}.json`);
  try {
    return JSON.parse(fs.readFileSync(localePath, "utf8"));
  } catch {
    return {};
  }
}

async function runtimeDiagnostics(refresh = false) {
  const python = findPython();
  const pythonVersion = await runCommand(python, ["--version"], 5000);
  const pythonDeps = pythonVersion.ok
    ? await runCommand(python, ["-c", "import fastapi, uvicorn, paho.mqtt.client, sqlalchemy, pydantic; print('backend deps ok')"], 8000)
    : { ok: false, code: 1, output: "Python not found" };
  const sidecarRuntime = path.join(BACKEND_DIR, "signal_sidecar", "build", "install", "signalasi-link-sidecar", "bin", "signalasi-link-sidecar.bat");
  const packaged = Boolean(app.isPackaged);
  let managedRuntime = {
    contract_version: "signalasi.desktop-runtime/1.0",
    summary: { ready: 0, partial: 0, missing: 0, total: 0 },
    capabilities: [],
    runtimes: [],
    error: ""
  };
  try {
    const status = await startBackend();
    if (!status.running) {
      managedRuntime.error = status.error || "Desktop backend is unavailable";
    } else {
      const response = await fetch(`${BACKEND_ORIGIN}/api/desktop-runtime?refresh=${refresh ? "true" : "false"}`);
      if (!response.ok) throw new Error(`Runtime inventory returned HTTP ${response.status}`);
      managedRuntime = await response.json();
    }
  } catch (error) {
    managedRuntime.error = error.message || String(error);
  }
  return {
    app: {
      packaged,
      appPath: app.getAppPath(),
      resourcesPath: process.resourcesPath,
      backendOrigin: BACKEND_ORIGIN
    },
    backend: {
      dir: BACKEND_DIR,
      exists: fs.existsSync(path.join(BACKEND_DIR, "main.py")),
      sidecarRuntime,
      sidecarExists: fs.existsSync(sidecarRuntime)
    },
    python: {
      command: python,
      ok: pythonVersion.ok,
      version: pythonVersion.output,
      depsOk: pythonDeps.ok,
      depsOutput: pythonDeps.output
    },
    managedRuntime,
    installHint: "If Python deps are missing, run install-backend-deps.bat from the portable package or pip install -r backend/requirements.txt."
  };
}

async function detectAgents() {
  try {
    const status = await startBackend();
    if (status.running) {
      const response = await fetch(`${BACKEND_ORIGIN}/api/agents`);
      if (response.ok) {
        const agents = await response.json();
        return agents.map((agent) => ({
          id: agent.id,
          name: agent.name,
          kind: agent.kind,
          status: agent.status === "ready" ? "detected" : agent.status === "needs_setup" ? "manual" : agent.status,
          detail: agent.detail || agent.note || "",
          pairing: agent.id === "hermes" ? "SignalASI Link QR" : "Connector managed"
        }));
      }
    }
  } catch {
    // Fall back to local command probing below.
  }

  const [hermes, codex, claude, ollama] = await Promise.all([
    commandExists("hermes", ["--version"]),
    commandExists("codex", ["--version"]),
    commandExists("claude", ["--version"]),
    commandExists("ollama", ["--version"])
  ]);

  return [
    {
      id: "hermes",
      name: "Hermes Agent",
      kind: "local-cli",
      status: hermes.ok ? "detected" : "missing",
      detail: hermes.output || "Install Hermes CLI or configure a custom command.",
      pairing: "SignalASI Link QR"
    },
    {
      id: "codex",
      name: "Codex Agent",
      kind: "local-cli",
      status: codex.ok ? "detected" : "missing",
      detail: codex.output || "Use the SignalASI Desktop Connector to wrap Codex as a contact.",
      pairing: "Connector managed"
    },
    {
      id: "claude",
      name: "Claude Code",
      kind: "local-cli",
      status: claude.ok ? "detected" : "missing",
      detail: claude.output || "Install Claude Code CLI or set a custom command later.",
      pairing: "Connector managed"
    },
    {
      id: "local-llm",
      name: "Local LLM",
      kind: "local-model",
      status: ollama.ok ? "detected" : "manual",
      detail: ollama.output || "Ollama not detected. OpenAI-compatible localhost endpoints can be added next.",
      pairing: "Connector managed"
    },
    {
      id: "custom-agent",
      name: "Custom Agent",
      kind: "custom-cli",
      status: "manual",
      detail: "Set any CLI or MCP wrapper command in SignalASI Desktop.",
      pairing: "Connector managed"
    }
  ];
}

async function fetchJson(pathname, options = {}) {
  let lastError;
  for (let attempt = 0; attempt < 8; attempt += 1) {
    try {
      const { headers: extraHeaders = {}, ...requestOptions } = options;
      const response = await fetch(`${BACKEND_ORIGIN}${pathname}`, {
        ...requestOptions,
        headers: {
          "Content-Type": "application/json",
          "X-SignalASI-Token": desktopTaskStreamToken(),
          ...extraHeaders
        }
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const contentType = response.headers.get("content-type") || "";
      if (!contentType.includes("application/json")) {
        throw new Error(`Expected JSON from ${pathname}, got ${contentType || "unknown content-type"}`);
      }
      return response.json();
    } catch (error) {
      lastError = error;
      if (attempt === 7) break;
      await startBackend();
      await new Promise((resolve) => setTimeout(resolve, 350));
    }
  }
  throw lastError;
}

async function getAgentConfig() {
  await startBackend();
  return fetchJson("/api/agents/config");
}

async function getAgentDiagnostics() {
  await startBackend();
  return fetchJson("/api/agents/diagnostics");
}

async function getAgentExecutionLog(limit = 50) {
  await startBackend();
  return fetchJson(`/api/agents/execution-log?limit=${encodeURIComponent(limit)}`);
}

async function getAgentTasks(limit = 100) {
  await startBackend();
  return fetchJson(`/api/agent/tasks?limit=${encodeURIComponent(limit)}`);
}

async function getPairingStatus() {
  await startBackend();
  return fetchJson("/api/pairing/status");
}

async function getPairingQr(grantDesktopExecutor = false) {
  await startBackend();
  const pairing = await fetchJson(
    `/api/pairing/qr?desktop_executor=${grantDesktopExecutor ? "true" : "false"}`
  );
  const imageDataUrl = pairing.image_data_url || "";
  if (!imageDataUrl) throw new Error("Pairing QR image was missing from the Desktop response");
  return {
    imageDataUrl,
    fingerprint: pairing.fingerprint || "",
    pairingAccess: pairing.pairing_access || {}
  };
}

async function clearPairing(clientRouteId = "") {
  await startBackend();
  const query = clientRouteId ? `?client_route_id=${encodeURIComponent(clientRouteId)}` : "";
  return fetchJson(`/api/pairing/clear${query}`, { method: "POST" });
}

async function runAgentSelfTest(options = {}) {
  await startBackend();
  return fetchJson("/api/agents/self-test", {
    method: "POST",
    body: JSON.stringify({
      include_agent_calls: Boolean(options.includeAgentCalls),
      include_mobile_delivery: options.includeMobileDelivery !== false
    })
  });
}

async function saveAgentConfig(config) {
  await startBackend();
  return fetchJson("/api/agents/config", {
    method: "POST",
    body: JSON.stringify(config)
  });
}

async function testAgent(agentId, prompt) {
  await startBackend();
  return fetchJson(`/api/agents/${encodeURIComponent(agentId)}/test`, {
    method: "POST",
    body: JSON.stringify({ prompt: prompt || "hello" })
  });
}

async function sendMobileTestMessage(contactId, content) {
  await startBackend();
  return fetchJson("/api/mobile/test-message", {
    method: "POST",
    body: JSON.stringify({ contact_id: contactId, content: content || `DESKTOP_TEST_${Date.now()}` })
  });
}

async function syncMobileStatus() {
  await startBackend();
  return fetchJson("/api/agents/sync-mobile-status", { method: "POST" });
}

async function listDesktopTasks(limit = 100) {
  await startBackend();
  return fetchJson(`/api/desktop/tasks?limit=${encodeURIComponent(limit)}`);
}

async function getDesktopTask(taskId) {
  await startBackend();
  return fetchJson(`/api/desktop/tasks/${encodeURIComponent(taskId)}`);
}

async function startDesktopTask(payload = {}) {
  await startBackend();
  return fetchJson("/api/desktop/tasks", {
    method: "POST",
    body: JSON.stringify({
      prompt: String(payload.prompt || ""),
      agent_id: String(payload.agentId || "auto"),
      conversation_id: String(payload.conversationId || ""),
      attachments: Array.isArray(payload.attachments) ? payload.attachments : [],
      response_language: String(payload.responseLanguage || "")
    })
  });
}

async function cancelDesktopTask(taskId) {
  await startBackend();
  return fetchJson(`/api/desktop/tasks/${encodeURIComponent(taskId)}/cancel`, { method: "POST" });
}

async function retryDesktopTask(taskId) {
  await startBackend();
  return fetchJson(`/api/desktop/tasks/${encodeURIComponent(taskId)}/retry`, { method: "POST" });
}

async function deleteDesktopConversation(conversationId) {
  await startBackend();
  return fetchJson(`/api/desktop/conversations/${encodeURIComponent(conversationId)}`, { method: "DELETE" });
}

async function listEvolutionTasks(limit = 100) {
  await startBackend();
  return fetchJson(`/api/evolution/tasks?limit=${encodeURIComponent(limit)}`);
}

async function getEvolutionTask(taskId) {
  await startBackend();
  return fetchJson(`/api/evolution/tasks/${encodeURIComponent(taskId)}`);
}

async function createEvolutionTask(payload = {}) {
  await startBackend();
  return fetchJson("/api/evolution/tasks", {
    method: "POST",
    body: JSON.stringify({
      problem: String(payload.problem || ""),
      scope: Array.isArray(payload.scope) ? payload.scope : [],
      acceptance: Array.isArray(payload.acceptance) ? payload.acceptance : [],
      reproduction_steps: Array.isArray(payload.reproductionSteps) ? payload.reproductionSteps : [],
      risk_level: String(payload.riskLevel || "medium"),
      max_attempts: Number(payload.maxAttempts || 3),
      agent_id: String(payload.agentId || "auto"),
      start: payload.start !== false
    })
  });
}

async function cancelEvolutionTask(taskId) {
  await startBackend();
  return fetchJson(`/api/evolution/tasks/${encodeURIComponent(taskId)}/cancel`, { method: "POST" });
}

async function rollbackEvolutionTask(taskId) {
  await startBackend();
  return fetchJson(`/api/evolution/tasks/${encodeURIComponent(taskId)}/rollback`, { method: "POST" });
}

async function publishEvolutionTask(taskId, approvalHash) {
  await startBackend();
  return fetchJson(`/api/evolution/tasks/${encodeURIComponent(taskId)}/publish`, {
    method: "POST",
    body: JSON.stringify({ approval_hash: String(approvalHash || ""), base_branch: "main" })
  });
}

async function evolutionV2Request(method = "GET", pathname = "/health", body = null) {
  await startBackend();
  const safeMethod = String(method || "GET").toUpperCase();
  if (!["GET", "POST"].includes(safeMethod)) {
    throw new Error("Invalid evolution V2 API method");
  }
  const cleanPath = String(pathname || "/health");
  if (
    cleanPath.length > 2_048
    || !cleanPath.startsWith("/")
    || cleanPath.includes("..")
    || cleanPath.includes("#")
    || /[\u0000-\u001f\u007f]/.test(cleanPath)
  ) {
    throw new Error("Invalid evolution V2 API path");
  }
  const parsed = new URL(cleanPath, "http://signalasi.local");
  const identifier = "[A-Za-z0-9._-]{1,128}";
  const allowedPath = safeMethod === "GET"
    ? new RegExp(
      `^/(?:health|preflight|policy|tasks/${identifier}/metadata|`
      + `research/runs(?:/${identifier})?|roadmaps(?:/${identifier})?|proposals|`
      + "issues|campaigns|audit(?:/verify)?|scheduler|github/checks)$"
    )
    : new RegExp(
      `^/(?:research/runs|roadmaps|proposals/${identifier}/materialize|`
      + `issues/(?:scan|ingest)|campaigns(?:/${identifier}/tick)?|scheduler/tick)$`
    );
  if (!allowedPath.test(parsed.pathname)) {
    throw new Error("Evolution V2 API route is not allowed");
  }
  const options = { method: safeMethod };
  if (body !== null && body !== undefined && safeMethod !== "GET") {
    options.body = JSON.stringify(body);
  }
  return fetchJson(`/api/evolution/v2${parsed.pathname}${parsed.search}`, options);
}

async function listProactiveTasks(limit = 200) {
  await startBackend();
  return fetchJson(`/api/proactive/tasks?limit=${encodeURIComponent(limit)}`);
}

async function createProactiveTask(payload = {}) {
  await startBackend();
  return fetchJson("/api/proactive/tasks", {
    method: "POST",
    body: JSON.stringify(payload)
  });
}

async function updateProactiveTask(taskId, payload = {}) {
  await startBackend();
  return fetchJson(`/api/proactive/tasks/${encodeURIComponent(taskId)}`, {
    method: "POST",
    body: JSON.stringify(payload)
  });
}

async function deleteProactiveTask(taskId) {
  await startBackend();
  return fetchJson(`/api/proactive/tasks/${encodeURIComponent(taskId)}`, {
    method: "DELETE"
  });
}

async function triggerProactiveTask(taskId) {
  await startBackend();
  return fetchJson(`/api/proactive/tasks/${encodeURIComponent(taskId)}/trigger`, {
    method: "POST",
    body: JSON.stringify({ cause: { type: "manual", source: "desktop_ui" } })
  });
}

async function listProactiveRuns(taskId = "", limit = 100) {
  await startBackend();
  const query = new URLSearchParams({
    task_id: String(taskId || ""),
    limit: String(limit)
  });
  return fetchJson(`/api/proactive/runs?${query.toString()}`);
}

async function cancelProactiveRun(runId) {
  await startBackend();
  return fetchJson(`/api/proactive/runs/${encodeURIComponent(runId)}/cancel`, {
    method: "POST"
  });
}

async function getDesktopControl() {
  await startBackend();
  return fetchJson("/api/desktop-control");
}

async function getDesktopMemory(query = "", limit = 100) {
  await startBackend();
  return fetchJson(`/api/desktop-memory?query=${encodeURIComponent(query || "")}&limit=${encodeURIComponent(limit || 100)}`);
}

async function rememberDesktopMemory(payload = {}) {
  await startBackend();
  return fetchJson("/api/desktop-memory", { method: "POST", body: JSON.stringify(payload) });
}

async function forgetDesktopMemory(memoryId) {
  await startBackend();
  return fetchJson(`/api/desktop-memory/${encodeURIComponent(memoryId)}`, { method: "DELETE" });
}

async function getDesktopSkills() {
  await startBackend();
  return fetchJson("/api/desktop-skills");
}

async function saveDesktopSkill(payload = {}) {
  await startBackend();
  return fetchJson("/api/desktop-skills", { method: "POST", body: JSON.stringify(payload) });
}

async function setDesktopSkillEnabled(skillId, enabled) {
  await startBackend();
  return fetchJson(`/api/desktop-skills/${encodeURIComponent(skillId)}/enabled`, {
    method: "POST",
    body: JSON.stringify({ enabled: Boolean(enabled) })
  });
}

async function deleteDesktopSkill(skillId) {
  await startBackend();
  return fetchJson(`/api/desktop-skills/${encodeURIComponent(skillId)}`, { method: "DELETE" });
}

async function getDesktopMcp() {
  await startBackend();
  return fetchJson("/api/desktop-mcp");
}

async function saveDesktopMcp(payload = {}) {
  await startBackend();
  return fetchJson("/api/desktop-mcp", { method: "POST", body: JSON.stringify(payload) });
}

async function probeDesktopMcp(connectionId) {
  await startBackend();
  return fetchJson(`/api/desktop-mcp/${encodeURIComponent(connectionId)}/probe`, { method: "POST" });
}

async function deleteDesktopMcp(connectionId) {
  await startBackend();
  return fetchJson(`/api/desktop-mcp/${encodeURIComponent(connectionId)}`, { method: "DELETE" });
}

async function chooseAttachments() {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "Add files to SignalASI",
    buttonLabel: "Add",
    properties: ["openFile", "multiSelections"]
  });
  return result.canceled ? [] : result.filePaths;
}

function resolveTaskPath(taskId, relativePath = "") {
  const safeTaskId = String(taskId || "");
  if (!/^[A-Za-z0-9._-]{1,96}$/.test(safeTaskId)) {
    throw new Error("Invalid task id");
  }
  const tasksRoot = path.resolve(os.homedir(), "SignalASIWorkspace", "tasks");
  const taskRoot = path.resolve(tasksRoot, safeTaskId);
  const target = path.resolve(taskRoot, String(relativePath || "."));
  if (target !== taskRoot && !target.startsWith(`${taskRoot}${path.sep}`)) {
    throw new Error("Task artifact escaped its workspace");
  }
  return target;
}

async function openTaskArtifact(taskId, relativePath = "") {
  const target = resolveTaskPath(taskId, relativePath);
  if (!fs.existsSync(target)) throw new Error("Task artifact not found");
  const error = await shell.openPath(target);
  if (error) throw new Error(error);
  return { ok: true, path: target };
}

async function revealTaskWorkspace(taskId) {
  const target = resolveTaskPath(taskId);
  if (!fs.existsSync(target)) throw new Error("Task workspace not found");
  shell.showItemInFolder(target);
  return { ok: true, path: target };
}

ipcMain.handle("app:version", () => app.getVersion());
ipcMain.handle("backend:start", startBackend);
ipcMain.handle("backend:status", backendStatus);
ipcMain.handle("runtime:diagnostics", (_event, refresh = false) => runtimeDiagnostics(Boolean(refresh)));
ipcMain.handle("pairing:status", getPairingStatus);
ipcMain.handle("pairing:qr", (_event, grantDesktopExecutor = false) =>
  getPairingQr(Boolean(grantDesktopExecutor)));
ipcMain.handle("pairing:clear", (_event, clientRouteId = "") => clearPairing(clientRouteId));
ipcMain.handle("agents:detect", detectAgents);
ipcMain.handle("agents:diagnostics", getAgentDiagnostics);
ipcMain.handle("agents:execution-log", (_event, limit) => getAgentExecutionLog(limit));
ipcMain.handle("agents:tasks", (_event, limit) => getAgentTasks(limit));
ipcMain.handle("agents:self-test", (_event, options) => runAgentSelfTest(options));
ipcMain.handle("agents:config:get", getAgentConfig);
ipcMain.handle("agents:config:save", (_event, config) => saveAgentConfig(config));
ipcMain.handle("agents:test", (_event, agentId, prompt) => testAgent(agentId, prompt));
ipcMain.handle("mobile:test-message", (_event, contactId, content) => sendMobileTestMessage(contactId, content));
ipcMain.handle("mobile:sync-status", syncMobileStatus);
ipcMain.handle("desktop-tasks:list", (_event, limit) => listDesktopTasks(limit));
ipcMain.handle("desktop-tasks:get", (_event, taskId) => getDesktopTask(taskId));
ipcMain.handle("desktop-tasks:stream-config", () => ({
  url: DESKTOP_TASK_STREAM_URL,
  protocols: ["signalasi-task-stream", desktopTaskStreamToken()]
}));
ipcMain.handle("desktop-tasks:start", (_event, payload) => startDesktopTask(payload));
ipcMain.handle("desktop-tasks:cancel", (_event, taskId) => cancelDesktopTask(taskId));
ipcMain.handle("desktop-tasks:retry", (_event, taskId) => retryDesktopTask(taskId));
ipcMain.handle("desktop-conversations:delete", (_event, conversationId) => deleteDesktopConversation(conversationId));
ipcMain.handle("evolution-tasks:list", (_event, limit) => listEvolutionTasks(limit));
ipcMain.handle("evolution-tasks:get", (_event, taskId) => getEvolutionTask(taskId));
ipcMain.handle("evolution-tasks:create", (_event, payload) => createEvolutionTask(payload));
ipcMain.handle("evolution-tasks:cancel", (_event, taskId) => cancelEvolutionTask(taskId));
ipcMain.handle("evolution-tasks:rollback", (_event, taskId) => rollbackEvolutionTask(taskId));
ipcMain.handle("evolution-tasks:publish", (_event, taskId, approvalHash) =>
  publishEvolutionTask(taskId, approvalHash));
ipcMain.handle("evolution-v2:request", (_event, method, pathname, body) =>
  evolutionV2Request(method, pathname, body));
ipcMain.handle("proactive-tasks:list", (_event, limit) => listProactiveTasks(limit));
ipcMain.handle("proactive-tasks:create", (_event, payload) => createProactiveTask(payload));
ipcMain.handle("proactive-tasks:update", (_event, taskId, payload) => updateProactiveTask(taskId, payload));
ipcMain.handle("proactive-tasks:delete", (_event, taskId) => deleteProactiveTask(taskId));
ipcMain.handle("proactive-tasks:trigger", (_event, taskId) => triggerProactiveTask(taskId));
ipcMain.handle("proactive-runs:list", (_event, taskId, limit) => listProactiveRuns(taskId, limit));
ipcMain.handle("proactive-runs:cancel", (_event, runId) => cancelProactiveRun(runId));
ipcMain.handle("desktop-control:get", getDesktopControl);
ipcMain.handle("desktop-memory:list", (_event, query, limit) => getDesktopMemory(query, limit));
ipcMain.handle("desktop-memory:remember", (_event, payload) => rememberDesktopMemory(payload));
ipcMain.handle("desktop-memory:forget", (_event, memoryId) => forgetDesktopMemory(memoryId));
ipcMain.handle("desktop-skills:list", getDesktopSkills);
ipcMain.handle("desktop-skills:save", (_event, payload) => saveDesktopSkill(payload));
ipcMain.handle("desktop-skills:enabled", (_event, skillId, enabled) => setDesktopSkillEnabled(skillId, enabled));
ipcMain.handle("desktop-skills:delete", (_event, skillId) => deleteDesktopSkill(skillId));
ipcMain.handle("desktop-mcp:list", getDesktopMcp);
ipcMain.handle("desktop-mcp:save", (_event, payload) => saveDesktopMcp(payload));
ipcMain.handle("desktop-mcp:probe", (_event, connectionId) => probeDesktopMcp(connectionId));
ipcMain.handle("desktop-mcp:delete", (_event, connectionId) => deleteDesktopMcp(connectionId));
ipcMain.handle("files:choose", chooseAttachments);
ipcMain.handle("task-artifact:open", (_event, taskId, relativePath) => openTaskArtifact(taskId, relativePath));
ipcMain.handle("task-workspace:reveal", (_event, taskId) => revealTaskWorkspace(taskId));
ipcMain.handle("i18n:load", (_event, language) => loadLocale(language));
ipcMain.handle("pairing:url", () => PAIRING_URL);
ipcMain.handle("open:external", (_event, url) => shell.openExternal(url));
ipcMain.handle("clipboard:write", (_event, text) => {
  clipboard.writeText(String(text || ""));
  return { ok: true };
});

app.whenReady().then(async () => {
  if (!hasSingleInstanceLock) return;
  createWindow();
  startBackend();
});

app.on("second-instance", () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => {
  appIsQuitting = true;
  if (backendRestartTimer) {
    clearTimeout(backendRestartTimer);
    backendRestartTimer = undefined;
  }
  if (backendProcess && !backendProcess.killed) {
    if (process.platform === "win32" && backendProcess.pid) {
      spawnSync("taskkill", ["/pid", String(backendProcess.pid), "/T", "/F"], {
        windowsHide: true,
        stdio: "ignore"
      });
    } else {
      backendProcess.kill();
    }
  }
});
