const { spawn } = require("node:child_process");
const path = require("node:path");
const readline = require("node:readline");

// One hidden helper; at most one in-flight update and one newest pending count.
class WindowsTaskbarBadge {
  constructor() {
    this.sequence = 0;
    this.child = null;
    this.ready = false;
    this.active = null;
    this.queued = null;
    this.disposed = false;
  }

  update(window, count) {
    if (this.disposed || window.isDestroyed()) return Promise.reject(new Error("Taskbar window unavailable"));
    if (!Number.isSafeInteger(count) || count < 0) return Promise.reject(new Error("Invalid unread count"));
    this.count = count;
    const buffer = window.getNativeWindowHandle();
    const handle = buffer.length >= 8 ? buffer.readBigUInt64LE().toString() : String(buffer.readUInt32LE());
    return new Promise((resolve, reject) => {
      this.queued?.resolve(true);
      this.queued = { id: ++this.sequence, handle, count, resolve, reject };
      if (!this.child) this.start();
      this.flush();
    });
  }

  start() {
    const source = path.join(__dirname, "windows_taskbar_badge.cs").replace(/'/g, "''");
    const script = `$ErrorActionPreference='Stop'; Add-Type -Path '${source}' -ReferencedAssemblies System.Drawing; [GalaxyTaskbarBadge]::Run()`;
    const child = spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script],
      { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
    this.child = child;
    this.timer = setTimeout(() => this.fail(new Error("Taskbar helper startup timeout")), 15000);
    this.timer.unref?.();
    child.on("error", error => { if (this.child === child) this.fail(error); });
    child.on("exit", () => { if (this.child === child) this.fail(new Error("Taskbar helper exited")); });
    child.stdin.on("error", error => { if (this.child === child) this.fail(error); });
    child.stderr.on("data", chunk => { this.lastError = String(chunk).slice(0, 500); });
    const lines = readline.createInterface({ input: child.stdout });
    lines.on("line", line => {
      if (this.child !== child) return;
      if (line === "READY") {
        clearTimeout(this.timer);
        this.ready = true;
        this.flush();
        return;
      }
      const [status, id, detail] = line.split("|");
      if (!this.active || String(this.active.id) !== id) return;
      clearTimeout(this.timer);
      const active = this.active;
      this.active = null;
      if (status === "OK") {
        this.lastPixelSize = Number(detail);
        this.lastCount = active.count;
        active.resolve(true);
      } else active.reject(new Error(`Native taskbar update failed: ${detail}`));
      this.flush();
    });
  }

  flush() {
    if (!this.ready || this.active || !this.queued) return;
    this.active = this.queued;
    this.queued = null;
    const { id, handle, count } = this.active;
    this.timer = setTimeout(() => this.fail(new Error("Taskbar update timeout")), 5000);
    this.timer.unref?.();
    this.child.stdin.write(`${id}|${handle}|${count}\n`);
  }

  fail(error) {
    clearTimeout(this.timer);
    const child = this.child;
    this.child = null;
    this.ready = false;
    this.active?.reject(error);
    this.queued?.reject(error);
    this.active = this.queued = null;
    child?.kill();
  }

  dispose() {
    this.disposed = true;
    clearTimeout(this.refreshTimer);
    this.fail(new Error("Taskbar helper closed"));
  }

  refresh(window) {
    if (this.disposed || this.count === undefined) return;
    clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(() => {
      this.update(window, this.count).catch(error => console.warn("Taskbar DPI refresh failed", error));
    }, 200);
    this.refreshTimer.unref?.();
  }
}

module.exports = { WindowsTaskbarBadge };
