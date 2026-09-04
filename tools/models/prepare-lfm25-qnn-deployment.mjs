import { readdir, stat } from 'node:fs/promises';
import { resolve, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  lengthPrefixed,
  sha256File,
  signPayload,
  signingIdentity,
  writeJsonAtomic,
} from '../runtime/runtime-signing.mjs';

export const MODEL_ID = 'lfm2-5-2-6b-qnn-w4a8-sm8850';
export const MAX_PROFILED_PEAK_BYTES = (3 * 1024 * 1024 * 1024) - (256 * 1024 * 1024);

export function deploymentSigningPayload(manifest) {
  const values = [
    manifest.format_version,
    manifest.model_id,
    manifest.display_name,
    manifest.target_chipset.toUpperCase(),
    manifest.precision.toUpperCase(),
    manifest.default_context_tokens,
    manifest.maximum_context_tokens,
    manifest.runtime_id,
    manifest.model_path,
    manifest.tokenizer_path,
    manifest.profiled_peak_bytes,
    manifest.spill_fill_buffer_bytes,
    manifest.qairt_version,
  ];
  for (const file of [...manifest.files].sort((left, right) => compareAscii(left.path, right.path))) {
    values.push(file.path, file.size_bytes, file.sha256);
  }
  values.push(manifest.signature_key_id.toLowerCase());
  return Buffer.from(lengthPrefixed(values), 'utf8');
}

export async function prepareDeployment(options) {
  const inputRoot = resolve(options.input);
  const modelPath = safeRelative(options.modelPath);
  const tokenizerPath = safeRelative(options.tokenizerPath);
  const profiledPeakBytes = positiveInteger(options.profiledPeakBytes, 'profiled peak bytes');
  const spillFillBufferBytes = nonNegativeInteger(options.spillFillBufferBytes, 'spill-fill bytes');
  if (profiledPeakBytes > MAX_PROFILED_PEAK_BYTES) {
    throw new Error(`Profiled peak exceeds the ${MAX_PROFILED_PEAK_BYTES}-byte signed-package limit`);
  }
  if (spillFillBufferBytes > profiledPeakBytes) {
    throw new Error('Spill-fill bytes cannot exceed the measured process peak');
  }
  await requirePathInside(inputRoot, modelPath);
  const tokenizer = await requirePathInside(inputRoot, tokenizerPath);
  if (!tokenizer.isFile()) throw new Error('The tokenizer path must identify a file');

  const identity = signingIdentity(options.certificate, options.privateKey);
  const files = await collectFiles(inputRoot);
  const manifest = {
    format_version: 1,
    model_id: MODEL_ID,
    display_name: 'LFM2.5 2.6B QNN',
    target_chipset: 'SM8850',
    precision: 'W4A8',
    default_context_tokens: 2048,
    maximum_context_tokens: 4096,
    runtime_id: 'qairt',
    model_path: modelPath,
    tokenizer_path: tokenizerPath,
    profiled_peak_bytes: profiledPeakBytes,
    spill_fill_buffer_bytes: spillFillBufferBytes,
    qairt_version: requiredString(options.qairtVersion, 'QAIRT version'),
    files,
    signature_key_id: identity.keyId,
    signature: '',
  };
  manifest.signature = signPayload(deploymentSigningPayload(manifest), identity);
  const destination = resolve(inputRoot, 'galaxyssi-qnn-deployment.json');
  writeJsonAtomic(destination, manifest);
  return { destination, manifest };
}

async function collectFiles(root) {
  const files = [];
  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = resolve(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`Symbolic links are not allowed: ${path}`);
      if (entry.isDirectory()) {
        await visit(path);
      } else if (entry.isFile()) {
        const relativePath = relative(root, path).split(sep).join('/');
        if (relativePath === 'galaxyssi-qnn-deployment.json') continue;
        const info = await stat(path);
        if (info.size <= 0) throw new Error(`Deployment files must not be empty: ${relativePath}`);
        files.push({
          path: safeRelative(relativePath),
          size_bytes: info.size,
          sha256: await sha256File(path),
        });
      }
    }
  }
  await visit(root);
  if (files.length === 0 || files.length > 64) throw new Error('The deployment must contain 1-64 files');
  return files.sort((left, right) => compareAscii(left.path, right.path));
}

async function requirePathInside(root, relativePath) {
  const candidate = resolve(root, relativePath);
  if (!(candidate === root || candidate.startsWith(`${root}${sep}`))) {
    throw new Error('Deployment path escapes the input directory');
  }
  return stat(candidate);
}

function safeRelative(value) {
  const text = requiredString(value, 'relative path').replaceAll('\\', '/');
  if (!/^[A-Za-z0-9._/-]+$/.test(text) || text.startsWith('/') || text.includes(':') ||
      text.split('/').some((part) => !part || part === '.' || part === '..')) {
    throw new Error(`Unsafe relative path: ${text}`);
  }
  return text;
}

function compareAscii(left, right) {
  return Buffer.compare(Buffer.from(left, 'ascii'), Buffer.from(right, 'ascii'));
}

function requiredString(value, name) {
  if (typeof value !== 'string' || value.trim().length === 0) throw new Error(`${name} is required`);
  return value.trim();
}

function positiveInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

function nonNegativeInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`${name} must be a non-negative integer`);
  return parsed;
}

function parseArguments(values) {
  const options = {};
  for (let index = 0; index < values.length; index += 2) {
    const name = values[index];
    const value = values[index + 1];
    if (!name?.startsWith('--') || value == null) throw new Error(`Invalid argument near ${name ?? '<end>'}`);
    options[name.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
  }
  return options;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  prepareDeployment(parseArguments(process.argv.slice(2)))
    .then(({ destination, manifest }) => {
      process.stdout.write(`${JSON.stringify({
        manifest: destination,
        files: manifest.files.length,
        installed_bytes: manifest.files.reduce((total, file) => total + file.size_bytes, 0),
        profiled_peak_bytes: manifest.profiled_peak_bytes,
      })}\n`);
    })
    .catch((error) => {
      process.stderr.write(`${error.stack ?? error.message}\n`);
      process.exitCode = 1;
    });
}
