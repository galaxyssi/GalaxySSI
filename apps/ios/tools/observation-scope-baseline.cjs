// Immutable source baseline and exact pending-delta composition; not native acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), reviewed = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const snapshots = new Map();
function snapshot(file) {
  if (!snapshots.has(file)) snapshots.set(file, cp.execFileSync('git', ['show', `${reviewed}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return snapshots.get(file);
}
function optional(name, method, file, source) {
  const location = path.join(__dirname, name + '.cjs');
  if (!fs.existsSync(location)) return source;
  const guard = require(location);
  return method === 'retained' ? guard[method](file, source) : guard[method](source);
}
function normalizePending(file, source) {
  for (const name of ['check-connector-deadline-checkpoint', 'check-scoped-member-recall',
    'check-native-recovery-query-ownership']) source = optional(name, 'retained', file, source);
  if (file.endsWith('/GalaxySSIServices.swift')) {
    for (const [name, method] of [['check-pinned-desktop-team', 'retainedServices'],
      ['check-browser-view-ownership', 'retainedBrowserServices'],
      ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
      ['check-pairing-history', 'retainedPairingServices']]) source = optional(name, method, file, source);
  }
  return source;
}
module.exports = {reviewed, snapshot, normalizePending};
