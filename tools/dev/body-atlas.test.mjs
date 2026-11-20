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
    if (['cell', 'fragment'].includes(item.kind)) {
      assert.equal(item.mechanism, item.id, 'Cell mechanism must belong to the microscopic entry');
      assert.equal(mechanisms.get(item.mechanism).kind, item.kind, 'Cell mechanism kind must match');
    }
    for (const field of ['name', 'description', 'aliases']) {
      assert.match(item[field], /^health_atlas_[a-z0-9_]+$/);
      assert.ok(!resources.has(item[field]), `Shared resource key: ${item[field]}`);
      resources.add(item[field]);
    }
  }
  for (const model of data.mechanisms) {
    assert.equal(model.stages.length, 4, model.id);
    assert.match(model.chapter, /^[a-z0-9-]+$/);
    if (model.reference !== undefined) assert.match(model.reference, /^https:\/\/pubmed\.ncbi\.nlm\.nih\.gov\/[1-9][0-9]*\/$/);
    if (['cell', 'fragment'].includes(model.kind)) {
      assert.equal(entries.get(model.id)?.kind, model.kind, model.id);
      assert.equal(entries.get(model.id)?.mechanism, model.id, 'Cell mechanism must match its owner');
      assert.equal(data.entries.filter(item => item.mechanism === model.id).length, 1, 'Cell mechanism cannot leak to another entry');
    }
  }
}

const coreCells = [
  "cell-erythrocyte",
  "cell-neutrophil",
  "cell-eosinophil",
  "cell-basophil",
  "cell-monocyte",
  "cell-macrophage",
  "cell-t-cell",
  "cell-b-cell",
  "cell-plasma-cell",
  "cell-natural-killer-cell",
  "cell-neuron",
  "cell-astrocyte",
  "cell-schwann-cell",
  "cell-skeletal-myocyte",
  "cell-cardiomyocyte",
  "cell-smooth-muscle-cell",
  "cell-keratinocyte",
  "cell-melanocyte",
  "cell-fibroblast",
  "cell-adipocyte",
  "cell-osteoblast",
  "cell-osteocyte",
  "cell-osteoclast",
  "cell-chondrocyte",
  "cell-vascular-endothelial-cell",
  "cell-hepatocyte",
  "cell-pancreatic-beta-cell",
  "cell-enterocyte",
  "cell-spermatozoon",
  "cell-oocyte-or-ovum"
];

test('all thirty core cells have their own sourced, localized mechanism', () => {
  const mechanisms = new Map(catalogue.mechanisms.map(model => [model.id, model]));
  const keys = new Set();
  for (const id of coreCells) {
    const entry = catalogue.entries.find(item => item.id === id);
    assert.equal(entry?.mechanism, id);
    const model = mechanisms.get(id);
    assert.equal(model?.kind, 'cell');
    for (const key of [model.title, ...model.stages]) {
      assert.ok(!keys.has(key), key);
      keys.add(key);
      for (const locale of ['values', 'values-zh']) {
        const resource = readFileSync(new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_cell_processes.xml`, import.meta.url), 'utf8');
        assert.ok(resource.includes(`name="${key}"`), `${locale}: ${key}`);
      }
    }
  }
  assert.equal(coreCells.length, 30);
});

test('each ear structure has a unique localized process rather than a shared sensory sequence', () => {
  const locales = ['values', 'values-zh'].map(locale => readFileSync(
    new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_hearing.xml`, import.meta.url), 'utf8'));
  const names = ['ear', 'external-ear', 'middle-ear', 'inner-ear', 'cochlea', 'vestibular-apparatus'];
  const keys = new Set();
  for (const name of names) {
    const entry = catalogue.entries.find(item => item.id === name);
    assert.equal(entry?.mechanism, name);
    const process = catalogue.mechanisms.find(item => item.id === name);
    assert.equal(process?.kind, 'organ');
    assert.equal(process?.chapter, '14-1-sensory-perception');
    assert.equal(process.stages.length, 4);
    for (const key of [process.title, ...process.stages]) {
      assert.ok(!keys.has(key), key);
      keys.add(key);
      for (const resources of locales) assert.ok(resources.includes(`name="${key}"`), key);
    }
  }
});

test('cell-specific processes cannot be reused for another cell or structure', () => {
  const invalid = structuredClone(catalogue);
  invalid.entries.find(item => item.id === 'cell-neutrophil').mechanism = 'cell-erythrocyte';
  assert.throws(() => validate(invalid), /Cell mechanism/);
});

test('bundled atlas is a complete canonical graph', () => {
  validate(catalogue);
  for (const [kind, count] of [['system', 14], ['organ', 167], ['cell', 105], ['fragment', 1]]) {
    assert.equal(catalogue.entries.filter(item => item.kind === kind).length, count);
  }
  const skin = catalogue.entries.find(item => item.id === 'skin');
  assert.equal(skin.kind, 'system');
  assert.ok(skin.related.includes('skin-organ'));
});

test('nephron segments link to renal cells and seven independent mechanisms', () => {
  const entry = id => catalogue.entries.find(item => item.id === id);
  assert.ok(entry('nephron').related.includes('bowmans-capsule'));
  assert.deepEqual(entry('renal-tubules').related, ['proximal-tubule', 'nephron-loop', 'distal-tubule']);
  for (const part of ['bowmans-capsule', 'proximal-tubule', 'nephron-loop', 'distal-tubule']) {
    assert.equal(entry(part).kind, 'organ');
    assert.deepEqual(entry(part).systems, ['urinary']);
  }
  assert.ok(entry('cell-proximal-tubular-cell').related.includes('proximal-tubule'));
  assert.ok(entry('cell-distal-tubular-cell').related.includes('distal-tubule'));
  for (const name of ['podocyte', 'mesangial-cell', 'proximal-tubular-cell', 'distal-tubular-cell',
    'collecting-duct-principal-cell', 'collecting-duct-intercalated-cell', 'urothelial-cell']) {
    const id = `cell-${name}`;
    assert.equal(entry(id).mechanism, id);
    const mechanism = catalogue.mechanisms.find(item => item.id === id);
    assert.equal(mechanism.kind, 'cell');
    for (const locale of ['values', 'values-zh']) {
      const resources = readFileSync(new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_renal.xml`, import.meta.url), 'utf8');
      for (const key of [mechanism.title, ...mechanism.stages]) assert.ok(resources.includes(`name="${key}"`));
    }
  }
});

test('cross-kind duplicate identities are rejected before packaging', () => {
  const invalid = structuredClone(catalogue);
  invalid.entries.find(item => item.id === 'skin-organ').id = 'skin';
  assert.throws(() => validate(invalid), /Duplicate atlas identity/);
});

test('alveolar structures and five respiratory cells have scoped references', () => {
  const entry = id => catalogue.entries.find(item => item.id === id);
  assert.deepEqual(entry('alveoli').related, ['respiratory-membrane', 'pulmonary-capillaries']);
  assert.equal(entry('alveoli').mechanism, 'gas-exchange');
  assert.ok(entry('cell-type-i-pneumocyte').related.includes('respiratory-membrane'));
  assert.ok(entry('cell-erythrocyte').related.includes('pulmonary-capillaries'));
  for (const name of ['type-i-pneumocyte', 'type-ii-pneumocyte', 'ciliated-airway-cell', 'goblet-cell', 'club-cell']) {
    const id = `cell-${name}`;
    assert.equal(entry(id).mechanism, id);
    const model = catalogue.mechanisms.find(item => item.id === id);
    assert.equal(model.kind, 'cell');
    for (const locale of ['values', 'values-zh']) {
      const resources = readFileSync(new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_respiration.xml`, import.meta.url), 'utf8');
      for (const key of [model.title, ...model.stages]) assert.ok(resources.includes(`name="${key}"`));
    }
  }
  assert.equal(catalogue.mechanisms.find(item => item.id === 'cell-club-cell').reference, 'https://pubmed.ncbi.nlm.nih.gov/29874100/');
});

test('mechanism reference overrides accept only canonical public paper URLs', () => {
  for (const reference of ['http://pubmed.ncbi.nlm.nih.gov/29874100/', 'https://pubmed.ncbi.nlm.nih.gov.evil/29874100/',
    'file:///private', 'https://pubmed.ncbi.nlm.nih.gov/29874100/?data=private', '']) {
    const invalid = structuredClone(catalogue);
    invalid.mechanisms[0].reference = reference;
    assert.throws(() => validate(invalid));
  }
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

test('reproductive cells have independent localized mechanisms and current references', () => {
  const names = ["sertoli-cell","leydig-cell","spermatogonium","spermatocyte","granulosa-cell","theca-cell","ciliated-oviduct-cell","endometrial-epithelial-cell","endometrial-stromal-cell","mammary-luminal-cell","myoepithelial-cell","trophoblast"];
  for (const name of names) {
    const id = `cell-${name}`;
    const entry = catalogue.entries.find(item => item.id === id);
    assert.equal(entry.mechanism, id);
    const model = catalogue.mechanisms.find(item => item.id === id);
    assert.equal(model.kind, 'cell');
    for (const locale of ['values', 'values-zh']) {
      const resource = readFileSync(new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_reproductive_cells.xml`, import.meta.url), 'utf8');
      for (const key of [model.title, ...model.stages]) assert.ok(resource.includes(`name="${key}"`));
    }
  }
  assert.equal(catalogue.mechanisms.filter(item => item.kind === 'cell').length, 105);
  assert.equal(catalogue.mechanisms.find(item => item.id === 'cell-endometrial-stromal-cell').reference,
    'https://pubmed.ncbi.nlm.nih.gov/25141152/');
  assert.ok(catalogue.mechanisms.every(item => !/of-the-(?:male|female)-reproductive-system/.test(item.chapter)));
});

test('every microscopic entry has a distinct four-stage mechanism, including the platelet fragment', () => {
  const entries = catalogue.entries.filter(item => ['cell', 'fragment'].includes(item.kind));
  assert.equal(entries.length, 106);
  const keys = new Set();
  for (const entry of entries) {
    const model = catalogue.mechanisms.find(item => item.id === entry.id);
    assert.equal(entry.mechanism, model.id);
    assert.equal(model.kind, entry.kind);
    for (const key of [model.title, ...model.stages]) {
      assert.ok(!keys.has(key), `Shared microscopic text key: ${key}`);
      keys.add(key);
    }
  }
  assert.equal(catalogue.mechanisms.find(item => item.id === 'fragment-platelet').kind, 'fragment');
});

test('microscopic mechanisms cannot silently regress to inherited system content', () => {
  for (const id of ['cell-dendritic-cell', 'fragment-platelet']) {
    const invalid = structuredClone(catalogue);
    invalid.entries.find(item => item.id === id).mechanism = invalid.entries.find(item => item.kind === 'system').mechanism;
    invalid.mechanisms = invalid.mechanisms.filter(item => item.id !== id);
    assert.throws(() => validate(invalid), /Cell mechanism/);
  }
  for (const kind of ['cell', 'immune']) {
    const invalid = structuredClone(catalogue);
    invalid.mechanisms.find(item => item.id === 'fragment-platelet').kind = kind;
    assert.throws(() => validate(invalid), /Cell mechanism/);
  }
  const invalid = structuredClone(catalogue);
  invalid.entries.find(item => item.id === 'heart').mechanism = 'fragment-platelet';
  assert.throws(() => validate(invalid), /Cell mechanism/);
});

test('all extended cell resources exist in English and Chinese', () => {
  for (const locale of ['values', 'values-zh']) {
    const resource = readFileSync(new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_extended_cells.xml`, import.meta.url), 'utf8');
    const models = catalogue.mechanisms.filter(item => item.title.startsWith('health_atlas_process_') && !coreCells.includes(item.id));
    assert.equal(models.length, 52);
    for (const model of models) for (const key of [model.title, ...model.stages])
      assert.ok(resource.includes(`name="${key}"`), `${locale}: ${key}`);
  }
});
