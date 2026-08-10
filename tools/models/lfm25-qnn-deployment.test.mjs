import assert from 'node:assert/strict';
import test from 'node:test';

import {
  deploymentSigningPayload,
  MAX_PROFILED_PEAK_BYTES,
  MODEL_ID,
} from './prepare-lfm25-qnn-deployment.mjs';

test('deployment payload is deterministic and file-order independent', () => {
  const manifest = {
    format_version: 1,
    model_id: MODEL_ID,
    display_name: 'LFM2.5 2.6B QNN',
    target_chipset: 'SM8850',
    precision: 'W4A8',
    default_context_tokens: 2048,
    maximum_context_tokens: 4096,
    runtime_id: 'qairt',
    model_path: 'model.bin',
    tokenizer_path: 'tokenizer.json',
    profiled_peak_bytes: MAX_PROFILED_PEAK_BYTES,
    spill_fill_buffer_bytes: 1,
    qairt_version: '2.45.0',
    files: [
      { path: 'tokenizer.json', size_bytes: 2, sha256: 'b'.repeat(64) },
      { path: 'model.bin', size_bytes: 3, sha256: 'a'.repeat(64) },
    ],
    signature_key_id: 'c'.repeat(64),
  };
  const first = deploymentSigningPayload(manifest);
  const second = deploymentSigningPayload({ ...manifest, files: [...manifest.files].reverse() });
  assert.deepEqual(first, second);
  assert.match(first.toString('utf8'), /lfm2-5-2-6b-qnn-w4a8-sm8850/);
});
