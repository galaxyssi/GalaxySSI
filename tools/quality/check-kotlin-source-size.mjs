#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..", "..");
const sourceRoot = path.join(
  root,
  "apps",
  "android",
  "app",
  "src",
  "main",
  "java",
);
const defaultLimit = 150 * 1024;
const legacyLimits = new Map([
  // Keep the existing oversized runtime frozen near its current size while new
  // and already-smaller Kotlin sources use the shared 150 KB ceiling.
  ["apps/android/app/src/main/java/com/signalasi/chat/GlobalSuperAgentRuntime.kt", 185 * 1024],
]);

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) return walk(absolute);
    return entry.isFile() && entry.name.endsWith(".kt") ? [absolute] : [];
  });
}

const oversized = [];
for (const absolute of walk(sourceRoot)) {
  const relative = path.relative(root, absolute).replaceAll("\\", "/");
  const size = fs.statSync(absolute).size;
  const limit = legacyLimits.get(relative) ?? defaultLimit;
  if (size > limit) oversized.push({ relative, size, limit });
}

if (oversized.length > 0) {
  console.error("Kotlin source size policy failed:");
  for (const item of oversized) {
    console.error(`- ${item.relative}: ${item.size} bytes (limit ${item.limit})`);
  }
  console.error("Split the file by responsibility instead of raising the limit.");
  process.exit(1);
}

console.log(`Kotlin source size policy passed (${defaultLimit} byte default limit).`);
