import assert from 'node:assert/strict';
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readlinkSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { buildRuntimeImage, validateRuntimeImageSource } from './runtime-image.mjs';

function fixture(packId = 'python-uv') {
  const root = mkdtempSync(join(tmpdir(), 'galaxyssi-runtime-image-test-'));
  const source = join(root, 'source');
  mkdirSync(join(source, 'bin'), { recursive: true });
  const names = {
    'python-uv': ['python3', 'uv'],
    'node-js': ['node', 'tsx'],
    'browser-automation': ['galaxyssi-browser', 'playwright'],
    gradle: ['gradle'],
    'android-sdk': ['aapt2', 'aidl', 'zipalign', 'apksigner', 'd8'],
    ffmpeg: ['ffmpeg', 'ffprobe'],
  }[packId];
  for (const name of names) {
    const path = join(source, 'bin', name);
    writeFileSync(path, '#!/bin/sh\nexit 0\n', 'utf8');
    chmodSync(path, 0o755);
  }
  return { root, source };
}

test('runtime image validation requires every pack entrypoint', () => {
  const { root, source } = fixture();
  try {
    rmSync(join(source, 'bin', 'uv'));
    assert.throws(
      () => validateRuntimeImageSource('python-uv', '1.0.0', source),
      /entrypoint/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('runtime image validation accepts a contained symbolic link', (context) => {
  if (process.platform === 'win32') {
    context.skip('Windows symlink creation requires host policy support');
    return;
  }
  const { root, source } = fixture('node-js');
  try {
    mkdirSync(join(source, 'lib'), { recursive: true });
    writeFileSync(join(source, 'lib', 'npm.js'), 'export {};\n', 'utf8');
    symlinkSync('../lib/npm.js', join(source, 'bin', 'npm'));
    assert.doesNotThrow(
      () => validateRuntimeImageSource('node-js', '24.18.0', source, [], 'linux'),
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('runtime image validation rejects a symbolic link outside the image', (context) => {
  if (process.platform === 'win32') {
    context.skip('Windows symlink creation requires host policy support');
    return;
  }
  const { root, source } = fixture('node-js');
  try {
    const outside = join(root, 'outside.js');
    writeFileSync(outside, 'export {};\n', 'utf8');
    symlinkSync(outside, join(source, 'bin', 'outside'));
    assert.throws(
      () => validateRuntimeImageSource('node-js', '24.18.0', source, [], 'linux'),
      /escapes its source root/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('runtime image builder emits a matching descriptor and signing config', () => {
  const { root, source } = fixture('ffmpeg');
  const output = join(root, 'ffmpeg.img');
  let descriptor;
  try {
    const result = buildRuntimeImage({
      packId: 'ffmpeg',
      version: '8.0.1',
      sourceRoot: source,
      outputPath: output,
      license: 'GPL-2.0-or-later',
      platform: 'win32',
      squashfsBuilder: (stagedRoot, stagedImage) => {
        descriptor = JSON.parse(readFileSync(join(stagedRoot, 'galaxyssi-pack.json'), 'utf8'));
        copyFileSync(join(stagedRoot, 'bin', 'ffmpeg'), stagedImage);
      },
    });

    assert.deepEqual(descriptor.capabilities, ['ffmpeg.execute', 'ffprobe.inspect']);
    assert.equal(result.config.id, 'ffmpeg');
    assert.deepEqual(result.config.dependencies, ['linux-base']);
    assert.equal(JSON.parse(readFileSync(`${output}.config.json`, 'utf8')).version, '8.0.1');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('runtime image builder preserves relative symbolic links verbatim', (context) => {
  if (process.platform === 'win32') {
    context.skip('Windows symlink creation requires host policy support');
    return;
  }
  const { root, source } = fixture('node-js');
  try {
    mkdirSync(join(source, 'lib'), { recursive: true });
    writeFileSync(join(source, 'lib', 'node-real'), '#!/bin/sh\nexit 0\n', 'utf8');
    chmodSync(join(source, 'lib', 'node-real'), 0o755);
    rmSync(join(source, 'bin', 'node'));
    symlinkSync('../lib/node-real', join(source, 'bin', 'node'));

    buildRuntimeImage({
      packId: 'node-js',
      version: '24.18.0',
      sourceRoot: source,
      outputPath: join(root, 'node.img'),
      license: 'MIT',
      platform: 'linux',
      squashfsBuilder: (stagedRoot, stagedImage) => {
        assert.equal(readlinkSync(join(stagedRoot, 'bin', 'node')), '../lib/node-real');
        copyFileSync(join(stagedRoot, 'lib', 'node-real'), stagedImage);
      },
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('runtime image builder normalizes and validates explicit dependencies', () => {
  const { root, source } = fixture('ffmpeg');
  try {
    const result = buildRuntimeImage({
      packId: 'ffmpeg',
      version: '8.0.1',
      sourceRoot: source,
      outputPath: join(root, 'ffmpeg.img'),
      license: 'GPL-2.0-or-later',
      dependencies: ['cpp', 'linux-base', 'cpp'],
      platform: 'win32',
      squashfsBuilder: (stagedRoot, stagedImage) => {
        copyFileSync(join(stagedRoot, 'bin', 'ffmpeg'), stagedImage);
      },
    });
    assert.deepEqual(result.config.dependencies, ['cpp', 'linux-base']);
    assert.throws(
      () => buildRuntimeImage({
        packId: 'ffmpeg',
        version: '8.0.1',
        sourceRoot: source,
        outputPath: join(root, 'invalid.img'),
        license: 'GPL-2.0-or-later',
        dependencies: ['ffmpeg'],
        platform: 'win32',
        squashfsBuilder: () => {},
      }),
      /dependency/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('browser automation pack requires its launcher and Playwright CLI', () => {
  const { root, source } = fixture('browser-automation');
  try {
    const result = buildRuntimeImage({
      packId: 'browser-automation',
      version: '1.61.0',
      sourceRoot: source,
      outputPath: join(root, 'browser.img'),
      license: 'Apache-2.0 AND BSD-3-Clause',
      dependencies: ['node-js'],
      platform: 'win32',
      squashfsBuilder: (stagedRoot, stagedImage) => {
        copyFileSync(join(stagedRoot, 'bin', 'galaxyssi-browser'), stagedImage);
      },
    });
    assert.deepEqual(result.config.capabilities, ['browser.automation.execute']);
    assert.deepEqual(result.config.dependencies, ['linux-base', 'node-js']);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Gradle pack requires Java and exposes only the Gradle launcher', () => {
  const { root, source } = fixture('gradle');
  try {
    const result = buildRuntimeImage({
      packId: 'gradle',
      version: '8.14.5',
      sourceRoot: source,
      outputPath: join(root, 'gradle.img'),
      license: 'Apache-2.0',
      dependencies: ['java'],
      platform: 'win32',
      squashfsBuilder: (stagedRoot, stagedImage) => {
        copyFileSync(join(stagedRoot, 'bin', 'gradle'), stagedImage);
      },
    });
    assert.deepEqual(result.config.capabilities, ['gradle.execute']);
    assert.deepEqual(result.config.dependencies, ['java', 'linux-base']);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Android SDK pack requires Java and exposes native packaging tools', () => {
  const { root, source } = fixture('android-sdk');
  try {
    const result = buildRuntimeImage({
      packId: 'android-sdk',
      version: '36.0.0',
      sourceRoot: source,
      outputPath: join(root, 'android-sdk.img'),
      license: 'Apache-2.0',
      dependencies: ['java'],
      platform: 'win32',
      squashfsBuilder: (stagedRoot, stagedImage) => {
        copyFileSync(join(stagedRoot, 'bin', 'aapt2'), stagedImage);
      },
    });
    assert.deepEqual(result.config.capabilities, ['android.build', 'android.package', 'android.sign']);
    assert.deepEqual(result.config.dependencies, ['java', 'linux-base']);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
