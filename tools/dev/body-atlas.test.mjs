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
    assert.ok(['system', 'organ', 'tissue', 'cell', 'fragment'].includes(item.kind), item.id);
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
    if (item.kind === 'tissue') {
      assert.ok(item.locatedIn?.length, 'Tissues need example organ locations');
      assert.equal(new Set(item.locatedIn).size, item.locatedIn.length, 'Tissue locations cannot repeat');
      for (const organId of item.locatedIn) {
        const organ = entries.get(organId);
        assert.equal(organ?.kind, 'organ', `${item.id}: ${organId} is not an organ location`);
        assert.ok(organ.systems.some(id => item.systems.includes(id)),
          `${item.id}: ${organId} has unrelated systems (${organ.systems.join(', ')})`);
      }
      assert.ok(item.related.length && item.related.every(id => entries.get(id)?.kind === 'cell'), 'Tissues need canonical cell examples');
      assert.equal(new Set(item.related).size, item.related.length, 'Tissue cell examples cannot repeat');
      assert.equal(item.mechanism, item.id, 'Tissue mechanism must belong to its entry');
      assert.equal(mechanisms.get(item.mechanism).kind, 'tissue', 'Tissue mechanism kind must match');
    } else {
      assert.equal(item.locatedIn?.length ?? 0, 0, 'Only tissues declare example organ locations');
      assert.notEqual(mechanisms.get(item.mechanism).kind, 'tissue', 'Tissue stages cannot leak to other entries');
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
    if (model.kind === 'tissue') assert.equal(entries.get(model.id)?.kind, 'tissue', 'Tissue mechanism requires an owner');
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

test('cardiac cutaway links each chamber, valve and outlet to its own localized mechanism', () => {
  const localized = ['values', 'values-zh'].map(locale => readFileSync(
    new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_heart_section.xml`, import.meta.url), 'utf8'));
  const groups = {
    heart: ['aorta', 'pulmonary-trunk'],
    atria: ['right-atrium', 'left-atrium'],
    ventricles: ['right-ventricle', 'left-ventricle'],
    'heart-valves': ['tricuspid-valve', 'mitral-valve', 'pulmonary-valve', 'aortic-valve'],
  };
  const byId = new Map(catalogue.entries.map(entry => [entry.id, entry]));
  const mechanisms = new Map(catalogue.mechanisms.map(model => [model.id, model]));
  const keys = new Set();
  for (const [parent, ids] of Object.entries(groups)) {
    for (const id of ids) {
      assert.ok(byId.get(parent).related.includes(id));
      const entry = byId.get(id);
      assert.equal(entry.kind, 'organ');
      assert.deepEqual(entry.systems, ['cardio']);
      assert.equal(entry.mechanism, id);
      const mechanism = mechanisms.get(entry.mechanism);
      assert.equal(mechanism.chapter, '19-3-cardiac-cycle');
      for (const key of [entry.name, entry.description, entry.aliases, mechanism.title, ...mechanism.stages]) {
        assert.ok(!keys.has(key), key);
        keys.add(key);
        assert.ok(localized.every(xml => xml.includes(`name="${key}"`)), key);
      }
    }
  }
  assert.equal(byId.get('heart-valves').mechanism, 'heart-valves');
  assert.equal(mechanisms.get('heart-valves').stages.length, 4);
});

test('cell-specific processes cannot be reused for another cell or structure', () => {
  const invalid = structuredClone(catalogue);
  invalid.entries.find(item => item.id === 'cell-neutrophil').mechanism = 'cell-erythrocyte';
  assert.throws(() => validate(invalid), /Cell mechanism/);
});

test('bundled atlas is a complete canonical graph', () => {
  validate(catalogue);
  for (const [kind, count] of [['system', 14], ['organ', 177], ['tissue', 14], ['cell', 107], ['fragment', 1]]) {
    assert.equal(catalogue.entries.filter(item => item.kind === kind).length, count);
  }
  const skin = catalogue.entries.find(item => item.id === 'skin');
  assert.equal(skin.kind, 'system');
  assert.ok(skin.related.includes('skin-organ'));
});

test('tissue examples have unique localized teaching steps and explicit links', () => {
  const tissues = catalogue.entries.filter(entry => entry.kind === 'tissue');
  const touchedOrgans = new Set(tissues.flatMap(entry => entry.locatedIn));
  const cells = new Set(tissues.flatMap(entry => entry.related));
  assert.equal(tissues.length, 14);
  assert.ok(touchedOrgans.size >= 45);
  assert.ok(cells.size >= 20);
  const files = ['values', 'values-zh'].map(locale => readFileSync(
    new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_tissues.xml`, import.meta.url), 'utf8'));
  const keys = new Set();
  for (const item of tissues) {
    const model = catalogue.mechanisms.find(row => row.id === item.id);
    for (const key of [item.name, item.description, item.aliases, model.title, ...model.stages]) {
      assert.ok(!keys.has(key), key);
      keys.add(key);
      for (const file of files) assert.ok(file.includes(`name="${key}"`), key);
    }
  }
});

test('the tissue graph rejects an invalid organ location, cell example or borrowed mechanism', () => {
  const bad = structuredClone(catalogue);
  const heart = bad.entries.find(entry => entry.id === 'tissue-cardiac-muscle');
  heart.locatedIn = ['cell-cardiomyocyte'];
  assert.throws(() => validate(bad), /not an organ location/);
  heart.locatedIn = ['heart'];
  heart.related = ['ventricles'];
  assert.throws(() => validate(bad), /cell examples/);
  heart.related = ['cell-cardiomyocyte'];
  heart.mechanism = 'tissue-skeletal-muscle';
  assert.throws(() => validate(bad), /must belong/);
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
  assert.equal(catalogue.mechanisms.filter(item => item.kind === 'cell').length, 107);
  assert.equal(catalogue.mechanisms.find(item => item.id === 'cell-endometrial-stromal-cell').reference,
    'https://pubmed.ncbi.nlm.nih.gov/25141152/');
  assert.ok(catalogue.mechanisms.every(item => !/of-the-(?:male|female)-reproductive-system/.test(item.chapter)));
});

test('every microscopic entry has a distinct four-stage mechanism, including the platelet fragment', () => {
  const entries = catalogue.entries.filter(item => ['cell', 'fragment'].includes(item.kind));
  assert.equal(entries.length, 108);
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

test('the retina and its two relay cells have separate localized and sourced mechanisms', () => {
  for (const id of ['retina', 'cell-retinal-bipolar-cell', 'cell-retinal-aii-amacrine-cell']) {
    const entry = catalogue.entries.find(item => item.id === id);
    assert.equal(entry.mechanism, id);
    if (entry.kind === 'cell') assert.ok(entry.related.includes('retina'));
    const model = catalogue.mechanisms.find(item => item.id === id);
    assert.equal(model.reference, 'https://pubmed.ncbi.nlm.nih.gov/28856684/');
    for (const locale of ['values', 'values-zh']) {
      const resource = readFileSync(new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_sensory_plates.xml`, import.meta.url), 'utf8');
      for (const key of [model.title, ...model.stages]) assert.ok(resource.includes(`name="${key}"`));
    }
  }
});

test('lymphoid organs have distinct localized lessons and canonical anatomy links', () => {
  const immune = catalogue.entries.find(item => item.id === 'immune');
  const ids = immune.related.filter(id => id !== 'appendix');
  assert.equal(ids.length, 9);
  const seen = new Set();
  const localized = ['values', 'values-zh'].map(locale => readFileSync(
    new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_lymph_organs.xml`, import.meta.url), 'utf8'));
  for (const id of ids) {
    const organ = catalogue.entries.find(item => item.id === id);
    assert.equal(organ.mechanism, id);
    const model = catalogue.mechanisms.find(item => item.id === id);
    assert.equal(model.kind, 'lymphoid-organ');
    assert.ok(organ.related.length > 0);
    for (const key of [model.title, ...model.stages]) {
      assert.ok(!seen.has(key));
      seen.add(key);
      assert.ok(localized.every(source => source.includes(`name="${key}"`)), key);
    }
  }
});

test('alimentary sections have independent bilingual stages and source chapters', () => {
  const ids = ['oral-cavity', 'teeth', 'esophagus', 'stomach', 'small-intestine', 'duodenum', 'jejunum', 'ileum',
    'large-intestine', 'cecum', 'appendix', 'colon', 'rectum', 'anal-canal'];
  const keys = new Set();
  const translations = ['values', 'values-zh'].map(locale => readFileSync(
    new URL(`../../apps/android/app/src/main/res/${locale}/health_atlas_gut_sections.xml`, import.meta.url), 'utf8'));
  for (const id of ids) {
    const item = catalogue.entries.find(entry => entry.id === id);
    assert.equal(item.mechanism, id);
    const model = catalogue.mechanisms.find(value => value.id === id);
    assert.equal(model.kind, 'alimentary-organ');
    assert.match(model.chapter, /^23-[345]-/);
    for (const key of [model.title, ...model.stages]) {
      assert.ok(!keys.has(key));
      keys.add(key);
      assert.ok(translations.every(file => file.includes(`name="${key}"`)), key);
    }
  }
});
