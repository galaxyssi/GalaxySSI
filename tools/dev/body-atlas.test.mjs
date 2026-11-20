import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const catalogue = JSON.parse(readFileSync(new URL('../../apps/android/app/src/main/assets/health/body-atlas.json', import.meta.url), 'utf8'));

function validate(data) {
  assert.equal(data.schema, 1);
  const entries = new Map(data.entries.map(item => [item.id, item]));
  const mechanisms = new Map(data.mechanisms.map(item => [item.id, item]));
  assert.equal(entries.size, data.entries.length, 'Duplicate atlas identity');
  assert.equal(mechanisms.size, data.mechanisms.length, 'Duplicate mechanism identity');
  const resources = new Set();
  for (const item of data.entries) {
    assert.match(item.id, /^[a-z0-9]+(?:-[a-z0-9]+)*$/);
    assert.ok(['system', 'organ', 'cell', 'fragment'].includes(item.kind), item.id);
    assert.ok(item.systems.length > 0, item.id);
    for (const system of item.systems) assert.equal(entries.get(system)?.kind, 'system', `${item.id}: ${system}`);
    for (const related of item.related) {
      assert.ok(entries.has(related), `${item.id}: missing ${related}`);
      assert.notEqual(related, item.id, `${item.id}: self-reference`);
    }
    assert.ok(mechanisms.has(item.mechanism), `${item.id}: missing mechanism`);
    for (const field of ['name', 'description', 'aliases']) {
      assert.match(item[field], /^health_atlas_[a-z0-9_]+$/);
      assert.ok(!resources.has(item[field]), `Shared resource key: ${item[field]}`);
      resources.add(item[field]);
    }
  }
  for (const model of data.mechanisms) {
    assert.equal(model.stages.length, 4, model.id);
    assert.match(model.chapter, /^[a-z0-9-]+$/);
  }
}

test('bundled atlas is a complete canonical graph', () => {
  validate(catalogue);
  for (const [kind, count] of [['system', 14], ['organ', 161], ['cell', 105], ['fragment', 1]]) {
    assert.equal(catalogue.entries.filter(item => item.kind === kind).length, count);
  }
  const skin = catalogue.entries.find(item => item.id === 'skin');
  assert.equal(skin.kind, 'system');
  assert.ok(skin.related.includes('skin-organ'));
});

test('cross-kind duplicate identities are rejected before packaging', () => {
  const invalid = structuredClone(catalogue);
  invalid.entries.find(item => item.id === 'skin-organ').id = 'skin';
  assert.throws(() => validate(invalid), /Duplicate atlas identity/);
});

test('missing structures and category-as-organ mixups are rejected', () => {
  const missing = structuredClone(catalogue);
  missing.entries[0].related.push('missing-organ');
  assert.throws(() => validate(missing), /missing-organ/);
  const wrongKind = structuredClone(catalogue);
  wrongKind.entries.find(item => item.id === 'brain').systems = ['skin-organ'];
  assert.throws(() => validate(wrongKind), /skin-organ/);
});

test('resource identity collisions are rejected', () => {
  const invalid = structuredClone(catalogue);
  invalid.entries[1].name = invalid.entries[0].name;
  assert.throws(() => validate(invalid), /Shared resource key/);
});
