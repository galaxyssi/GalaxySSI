// Electron integration test: fake microphone -> real Opus -> IPC -> local Whisper.
const { app, BrowserWindow, ipcMain } = require("electron");
const { spawn } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");
const os = require("node:os");
const net = require("node:net");
const crypto = require("node:crypto");
const { transcribeComposerSpeech } = require("../src/composer_stt");

const wav = process.env.GALAXYSSI_STT_TEST_WAV;
if (!wav || !fs.existsSync(wav)) throw new Error("Set GALAXYSSI_STT_TEST_WAV to a synthetic speech WAV file");
app.setPath("userData", fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-voice-smoke-")));
app.commandLine.appendSwitch("use-fake-device-for-media-stream");
app.commandLine.appendSwitch("use-fake-ui-for-media-stream");
app.commandLine.appendSwitch("use-file-for-fake-audio-capture", wav);
let backend;
let window;
app.whenReady().then(async () => {
  const port = await new Promise((resolve) => {
    const server = net.createServer().listen(0, "127.0.0.1", () => {
      const selected = server.address().port;
      server.close(() => resolve(selected));
    });
  });
  const token = crypto.randomBytes(24).toString("hex");
  const origin = `http://127.0.0.1:${port}`;
  const script = [
    "import os, uvicorn",
    "from fastapi import FastAPI, HTTPException",
    "from composer_stt import create_router",
    "def authorize(request):",
    "    if request.headers.get('x-galaxyssi-token') != os.environ['VOICE_TEST_TOKEN']: raise HTTPException(401)",
    "app = FastAPI()",
    "app.include_router(create_router(authorize))",
    `uvicorn.run(app, host='127.0.0.1', port=${port}, log_level='warning')`
  ].join("\n");
  backend = spawn(process.env.GALAXYSSI_PYTHON || "python", ["-c", script], {
    cwd: path.resolve(__dirname, "../core/galaxyssi-link/backend"),
    env: { ...process.env, VOICE_TEST_TOKEN: token }, windowsHide: true, stdio: ["ignore", "pipe", "pipe"]
  });
  backend.stderr.on("data", (data) => process.stderr.write(data));
  for (let attempt = 0; ; attempt++) {
    try { await fetch(`${origin}/openapi.json`); break; }
    catch (error) {
      if (attempt >= 100 || backend.exitCode !== null) throw error;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
  }
  ipcMain.handle("test:transcribe", (_event, payload) => transcribeComposerSpeech(payload, {
    startBackend: async () => {}, origin, token: () => token
  }));
  window = new BrowserWindow({ show: false, webPreferences: { nodeIntegration: true, contextIsolation: false } });
  await window.loadFile(path.join(__dirname, "composer-voice-smoke.html"));
  for (const run of ["cold", "warm"]) {
    const result = await window.webContents.executeJavaScript(`runVoiceSmoke(${Number(process.env.GALAXYSSI_STT_TEST_DURATION_MS || 7000)})`);
    console.log(JSON.stringify({ run, ...result }));
    if (!result.text || result.errors.length || !result.tracksEnded || result.phases.at(-1) !== "idle") {
      throw new Error("Composer voice integration failed");
    }
  }
  app.exit(0);
}).catch((error) => { console.error(error); app.exit(1); });
app.on("will-quit", () => backend?.kill());
process.on("exit", () => backend?.kill());
setTimeout(() => { console.error("Voice smoke timed out"); backend?.kill(); app.exit(1); }, 240_000).unref();
