#!/usr/bin/env node
"use strict";

import { existsSync, readdirSync, statSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { normalizeAndroidElfFile } from "./android-elf-page-normalizer.mjs";

function walk(target) {
  if (!existsSync(target)) return [];
  if (statSync(target).isFile()) return target.endsWith(".so") ? [target] : [];
  return readdirSync(target, { withFileTypes: true }).flatMap((entry) =>
    walk(join(target, entry.name))
  );
}

const targets = process.argv.slice(2).map((target) => resolve(target));
if (!targets.length) throw new Error("Provide at least one merged native-library directory");

let inspected = 0;
let changed = 0;
for (const file of [...new Set(targets.flatMap(walk))].sort()) {
  inspected += 1;
  const result = normalizeAndroidElfFile(file);
  if (!result.changed) continue;
  changed += 1;
  console.log(
    `Normalized ${basename(file)} for 16 KB pages: ` +
    `${result.beforeBytes} -> ${result.afterBytes} bytes, ${result.insertions.length} segment gaps`,
  );
}

if (!inspected) throw new Error("No native libraries were found in the merge output");
console.log(`Android native page-size normalization complete: ${changed}/${inspected} libraries changed.`);
