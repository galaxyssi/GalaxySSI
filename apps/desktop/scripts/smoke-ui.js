const { spawn } = require("node:child_process");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { acquireGalaxySSILock } = require("./smoke-lock");

const root = path.resolve(__dirname, "..");
const electronCliCandidates = [
  path.join(root, ".electron-runtime", "node_modules", "electron", "cli.js"),
  path.join(root, "node_modules", "electron", "cli.js")
];
const electronCli = electronCliCandidates.find((candidate) => fs.existsSync(candidate)) || electronCliCandidates[0];
const screenshotDir = path.join(root, "ui-smoke");
const screenshots = [
  path.join(screenshotDir, "desktop-overview.png"),
  path.join(screenshotDir, "desktop-peer-image.png"),
  path.join(screenshotDir, "desktop-peer-image-viewer.png"),
  path.join(screenshotDir, "desktop-composer-attachments.png"),
  path.join(screenshotDir, "desktop-evolution-timeline.png"),
  path.join(screenshotDir, "desktop-language-en.png"),
  path.join(screenshotDir, "desktop-language-zh.png"),
  path.join(screenshotDir, "desktop-setup-guide.png"),
  path.join(screenshotDir, "desktop-status-matrix.png"),
  path.join(screenshotDir, "desktop-agents.png"),
  path.join(screenshotDir, "desktop-memory-overview.png"),
  path.join(screenshotDir, "desktop-memory-inbox.png"),
  path.join(screenshotDir, "desktop-memory-conflicts.png"),
  path.join(screenshotDir, "desktop-mcp-governance.png"),
  path.join(screenshotDir, "desktop-mcp-import.png"),
  path.join(screenshotDir, "desktop-mcp-task-transparency.png"),
  path.join(screenshotDir, "desktop-capabilities.png"),
  path.join(screenshotDir, "desktop-settings.png"),
  path.join(screenshotDir, "desktop-agent-memory.png"),
  path.join(screenshotDir, "desktop-evolution-v2.png"),
  path.join(screenshotDir, "desktop-runtimes.png")
];

if (!fs.existsSync(electronCli)) {
  throw new Error(`Electron CLI missing: ${electronCli}`);
}

const releaseLock = acquireGalaxySSILock("smoke:ui");
const smokeStateDir = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-ui-smoke-"));

fs.rmSync(screenshotDir, { recursive: true, force: true });
fs.mkdirSync(screenshotDir, { recursive: true });

function cleanupSmokeState() {
  const resolved = path.resolve(smokeStateDir);
  const tempRoot = `${path.resolve(os.tmpdir())}${path.sep}`;
  if (!resolved.startsWith(tempRoot) || !path.basename(resolved).startsWith("galaxyssi-ui-smoke-")) {
    throw new Error(`Refusing to remove unexpected smoke state directory: ${resolved}`);
  }
  fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
}

function findFreeLoopbackPort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function main() {
  const backendPort = await findFreeLoopbackPort();
  const child = spawn(process.execPath, [electronCli, "."], {
    cwd: root,
    windowsHide: true,
    stdio: "inherit",
    env: {
      ...process.env,
      GALAXYSSI_UI_SMOKE: "1",
      GALAXYSSI_UI_SMOKE_DIR: screenshotDir,
      GALAXYSSI_STATE_DIR: smokeStateDir,
      GALAXYSSI_BACKEND_PORT: String(backendPort),
      GALAXYSSI_DISABLE_EXTERNAL_SERVICES: "1"
    }
  });

  child.on("exit", (code) => {
    releaseLock();
    cleanupSmokeState();
    if (code !== 0) {
      process.exit(code || 1);
      return;
    }
    for (const screenshotPath of screenshots) {
      if (!fs.existsSync(screenshotPath) || fs.statSync(screenshotPath).size < 1000) {
        console.error(`[ui-smoke] screenshot missing or too small: ${screenshotPath}`);
        process.exit(1);
        return;
      }
    }
    console.log(`[ui-smoke] OK: ${screenshots.join(", ")}`);
  });

  child.on("error", (error) => {
    releaseLock();
    cleanupSmokeState();
    console.error(`[ui-smoke] failed to start Electron: ${error.stack || error.message || error}`);
    process.exit(1);
  });
}

main().catch((error) => {
  releaseLock();
  console.error(`[ui-smoke] setup failed: ${error.stack || error.message || error}`);
  process.exit(1);
});
