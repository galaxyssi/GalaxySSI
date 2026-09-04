const fs = require("node:fs");
const path = require("node:path");
const { createAdb } = require("./android-adb");

const root = path.resolve(__dirname, "..");
const workspaceRoot = path.resolve(root, "..");
const androidDir = path.join(workspaceRoot, "android");
const apkPath = path.join(androidDir, "app", "build", "outputs", "apk", "debug", "app-debug.apk");
const packageName = "com.galaxyssi.chat";
const activityName = `${packageName}/.MainActivity`;
const languagePrefs = "shared_prefs/galaxyssi_language.xml";
const outDir = path.join(root, "ui-smoke");
const defaultDump = path.join(outDir, "android-language-default.xml");
const zhDump = path.join(outDir, "android-language-zh.xml");
const enDump = path.join(outDir, "android-language-en.xml");

function log(message) {
  console.log(`[android-language-smoke] ${message}`);
}

function fail(message) {
  throw new Error(message);
}

const adb = createAdb(root, log);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readAppFile(file) {
  try {
    return adb(["shell", "run-as", packageName, "cat", file]);
  } catch {
    return "";
  }
}

function restoreAppFile(file, snapshot) {
  if (!snapshot) {
    adb(["shell", "run-as", packageName, "rm", "-f", file]);
    return;
  }
  adb(["shell", "run-as", packageName, "mkdir", "-p", "shared_prefs"]);
  adb(["shell", "run-as", packageName, "tee", file], { input: snapshot, stdio: ["pipe", "ignore", "pipe"] });
}

function dumpWindowTo(fileName, remoteName) {
  const remotePath = `/sdcard/${remoteName}`;
  let lastError = null;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    try {
      adb(["shell", "rm", "-f", remotePath]);
      adb(["shell", "input", "keyevent", "KEYCODE_WAKEUP"]);
      adb(["shell", "wm", "dismiss-keyguard"]);
      adb(["shell", "uiautomator", "dump", remotePath]);
      adb(["pull", remotePath, fileName]);
      const xml = fs.readFileSync(fileName, "utf8");
      if (xml.includes("<hierarchy")) return xml;
    } catch (error) {
      lastError = error;
    }
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 400);
  }
  throw lastError || new Error(`Could not capture ${remoteName}`);
}

function requireText(xml, text, label, dumpPath) {
  if (!xml.includes(text)) {
    fail(`Language page did not render ${label}. Dump saved at ${dumpPath}`);
  }
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function tapText(xml, text, label, dumpPath) {
  const pattern = new RegExp(`text="${escapeRegExp(text)}"[^>]*bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"`);
  const match = xml.match(pattern);
  if (!match) {
    fail(`Language page did not expose tappable text for ${label}. Dump saved at ${dumpPath}`);
  }
  const left = Number(match[1]);
  const top = Number(match[2]);
  const right = Number(match[3]);
  const bottom = Number(match[4]);
  const x = Math.round((left + right) / 2);
  const y = Math.round((top + bottom) / 2);
  adb(["shell", "input", "tap", String(x), String(y)]);
}

async function openLanguagePage(dumpPath, remoteName) {
  let xml = "";
  for (let attempt = 0; attempt < 4; attempt += 1) {
    adb(["shell", "am", "force-stop", packageName]);
    adb([
      "shell",
      "am",
      "start",
      "-n",
      activityName,
      "--ez",
      "galaxyssi_debug_open_language_settings",
      "true"
    ]);
    await sleep(3500 + attempt * 500);
    xml = dumpWindowTo(dumpPath, remoteName);
    if (xml.includes("Language") || xml.includes("\u8bed\u8a00")) return xml;
  }
  return xml;
}

function requireEnglish(xml, dumpPath) {
  requireText(xml, "Voice &amp; Language", "English title", dumpPath);
  requireText(xml, "Interface language", "English interface-language section", dumpPath);
  requireText(xml, "Automatic (follow system)", "English automatic option", dumpPath);
  requireText(xml, "Model response language", "English model-language row", dumpPath);
  requireText(xml, "ASR language", "English ASR-language row", dumpPath);
  requireText(xml, "TTS language", "English TTS-language row", dumpPath);
  requireText(xml, "English", "English option", dumpPath);
}

function requireSimplifiedChinese(xml, dumpPath) {
  requireText(xml, "\u8bed\u97f3\u4e0e\u8bed\u8a00", "Simplified Chinese title", dumpPath);
  requireText(xml, "\u754c\u9762\u8bed\u8a00", "Simplified Chinese interface-language section", dumpPath);
  requireText(xml, "\u81ea\u52a8\uff08\u8ddf\u968f\u7cfb\u7edf\uff09", "Simplified Chinese automatic option", dumpPath);
  requireText(xml, "\u5927\u6a21\u578b\u56de\u590d\u8bed\u8a00", "Simplified Chinese model-language row", dumpPath);
  requireText(xml, "ASR \u8bed\u8a00", "Simplified Chinese ASR-language row", dumpPath);
  requireText(xml, "TTS \u8bed\u8a00", "Simplified Chinese TTS-language row", dumpPath);
  requireText(xml, "\u7b80\u4f53\u4e2d\u6587", "Simplified Chinese option", dumpPath);
}

async function main() {
  if (!fs.existsSync(apkPath)) {
    fail(`Android debug APK missing. Build it first: ${apkPath}`);
  }
  fs.mkdirSync(outDir, { recursive: true });

  log("installing debug APK");
  adb(["install", "-r", apkPath], { stdio: "inherit" });
  adb(["shell", "input", "keyevent", "KEYCODE_WAKEUP"]);
  adb(["shell", "am", "force-stop", packageName]);

  const originalLanguagePrefs = readAppFile(languagePrefs);

  try {
    log("clearing language preference and verifying the system-language default");
    restoreAppFile(languagePrefs, "");
    const defaultXml = await openLanguagePage(defaultDump, "galaxyssi-language-default.xml");
    const systemUsesChinese = defaultXml.includes("\u8bed\u97f3\u4e0e\u8bed\u8a00");
    if (systemUsesChinese) {
      requireSimplifiedChinese(defaultXml, defaultDump);
    } else {
      requireEnglish(defaultXml, defaultDump);
    }
    const autoPrefs = readAppFile(languagePrefs);
    if (autoPrefs && !autoPrefs.includes(">auto<")) {
      fail("Cleared language preferences did not remain in automatic mode.");
    }

    let zhXml;
    let enXml;
    if (systemUsesChinese) {
      log("switching from the automatic Chinese UI to English");
      tapText(defaultXml, "English", "English option", defaultDump);
      await sleep(2000);
      const firstEnPrefs = readAppFile(languagePrefs);
      if (!firstEnPrefs.includes(">en<")) {
        fail("Language preference did not persist English after tapping the Settings row.");
      }
      enXml = await openLanguagePage(enDump, "galaxyssi-language-en.xml");
      requireEnglish(enXml, enDump);

      log("switching from English to Simplified Chinese");
      tapText(enXml, "Simplified Chinese", "Simplified Chinese option", enDump);
    } else {
      log("switching from the automatic English UI to Simplified Chinese");
      tapText(defaultXml, "Simplified Chinese", "Simplified Chinese option", defaultDump);
    }
    await sleep(2000);
    const zhPrefs = readAppFile(languagePrefs);
    if (!zhPrefs.includes(">zh-CN<")) {
      fail("Language preference did not persist Simplified Chinese after tapping the Settings row.");
    }
    zhXml = await openLanguagePage(zhDump, "galaxyssi-language-zh.xml");
    requireSimplifiedChinese(zhXml, zhDump);

    log("switching back to English through the Settings UI");
    tapText(zhXml, "English", "English option", zhDump);
    await sleep(2000);
    const enPrefs = readAppFile(languagePrefs);
    if (!enPrefs.includes(">en<")) {
      fail("Language preference did not persist English after tapping the Settings row.");
    }
    enXml = await openLanguagePage(enDump, "galaxyssi-language-en.xml");
    requireEnglish(enXml, enDump);

    const finalPrefs = readAppFile(languagePrefs);
    if (!finalPrefs.includes(">en<")) {
      fail("Language preference did not persist English after switching back.");
    }

    log(`OK: Android language defaults and switching verified. Dumps: ${defaultDump}, ${zhDump}, ${enDump}`);
  } finally {
    adb(["shell", "am", "force-stop", packageName]);
    log("restoring original language preference");
    restoreAppFile(languagePrefs, originalLanguagePrefs);
    adb(["shell", "am", "force-stop", packageName]);
  }
}

main().catch((error) => {
  console.error(`[android-language-smoke] failed: ${error.stack || error.message || error}`);
  process.exit(1);
});
