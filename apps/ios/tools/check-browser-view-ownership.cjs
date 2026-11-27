// Source contracts only: no Swift/native/WebKit execution or device acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
function section(source, first, last) {
  const begin = source.indexOf(first), end = source.indexOf(last, begin + first.length);
  assert(begin >= 0 && end > begin, first); assert.equal(source.split(first).length, 2, first);
  return source.slice(begin, end);
}
function replaceOnce(source, from, to = '') {
  assert.equal(source.split(from).length, 2, from); return source.replace(from, to);
}
function retainedBrowserServices(source) {
  if (!source.includes('  func beginManagedBrowserView(')) return source;
  source = replaceOnce(source, section(source, '  func beginManagedBrowserView(', '  func returnManagedBrowserControl('));
  source = replaceOnce(source, section(source, '  func beginSupervisedBrowserView(', '  private func supervisedBrowserAllowed('));
  source = replaceOnce(source, '  func recordManagedBrowserContentExit(_ request: AgentManagedBrowserPresentation,\n    cause: AgentManagedBrowserHandoff.Interruption = .webContentProcessExited) throws {',
    '  func recordManagedBrowserContentExit(_ request: AgentManagedBrowserPresentation) throws {');
  source = replaceOnce(source, 'recordWebContentExit(request.handoff.ticket, binding: request.binding, cause: cause)',
    'recordWebContentExit(request.handoff.ticket, binding: request.binding)');
  source = replaceOnce(source, '    waiting.browserViewLease = nil\n');
  return replaceOnce(source, '      } else if let lease = task.browserViewLease,\n        !AgentBrowserViewLease.isLive(lease, scope: AgentModelLoopRecoveryIdentity.sha256(wait), processID: AgentOwnedOperationContext.processId) {\n        try? resolveSupervisedBrowser(wait, resolution: .interrupted(.browserViewClosed))\n', '');
}
function retainedBrowserTaskModels(source) {
  if (!source.includes('  var browserViewLease: AgentBrowserViewLease? = nil')) return source;
  for (const hook of ['  var browserViewLease: AgentBrowserViewLease? = nil\n',
    '    case browserViewLease = "browser_view_lease"\n',
    '    browserViewLease = try container.decodeIfPresent(AgentBrowserViewLease.self, forKey: .browserViewLease)\n']) source = replaceOnce(source, hook);
  return source;
}
module.exports = {retainedBrowserServices, retainedBrowserTaskModels};
if (require.main === module) {
  const services = read(app + 'GalaxySSIServices.swift');
  let retained = retainedBrowserServices(services);
  const unplanned = path.join(__dirname, 'check-unplanned-native-dispatch.cjs');
  if (fs.existsSync(unplanned)) retained = require(unplanned).retainedUnplannedDispatchServices(retained);
  assert.equal(retained, old(app + 'GalaxySSIServices.swift'), 'All coordinator code outside declared view-lifetime hooks unchanged');
  assert.equal(retainedBrowserTaskModels(read(app + 'AgentPlanRunModels.swift')), old(app + 'AgentPlanRunModels.swift'));
  assert.equal(read(app + 'AgentManagedBrowserContinuationModels.swift').replace('    case browserViewClosed = "browser_view_closed"\n', ''),
    old(app + 'AgentManagedBrowserContinuationModels.swift'), 'Only an explicitly unverified interruption cause added');
  const lease = read(app + 'AgentBrowserViewLease.swift');
  for (const token of ['existing.scope == scope', 'existing.processID == processID, active[existing.id] == existing',
    'existing.id == id', 'active[id] == nil, active.count < 200', 'try persist(lease)', 'active[id] = lease',
    'if active[lease.id] == lease', 'lock.lock(); defer { lock.unlock() }']) assert(lease.includes(token), token);
  assert(lease.indexOf('try persist(lease)') < lease.indexOf('active[id] = lease'), 'Failed save cannot grant a live view');
  assert(!/URLSession|WKWebView|\.execute\(|grantedPermissions|UserDefaults/.test(lease));
  const store = read(app + 'AgentManagedBrowserContinuationStore.swift');
  for (const token of ['_ = try activeBrowserHost(ticket, record: record)', 'handoff.hostProcessID == nil || handoff.hostProcessID == hostProcessID',
    'existing: record.viewLeases?[ticket.callID]', 'table[ticket.callID] = lease; record.viewLeases = table',
    'AgentModelLoopRecoveryIdentity.sha256(handoff.ticket)', 'cause: .browserViewClosed']) assert(store.includes(token), token);
  let retainedStore = replaceOnce(store, '    var viewLeases: [String: AgentBrowserViewLease]? = nil\n');
  retainedStore = replaceOnce(retainedStore, section(retainedStore, '  func claimView(', '  func saveCookies('));
  retainedStore = replaceOnce(retainedStore, '      record.viewLeases = nil\n');
  retainedStore = replaceOnce(retainedStore, section(retainedStore, '  func reconcileHostProcess(', '  @discardableResult\n  func recordWebContentExit('),
    section(old(app + 'AgentManagedBrowserContinuationStore.swift'), '  func reconcileHostProcess(', '  @discardableResult\n  func recordWebContentExit('));
  retainedStore = replaceOnce(retainedStore, '                            binding: AgentManagedBrowserDispatchBinding,\n                            cause: AgentManagedBrowserHandoff.Interruption = .webContentProcessExited) throws -> Bool {',
    '                            binding: AgentManagedBrowserDispatchBinding) throws -> Bool {');
  retainedStore = replaceOnce(retainedStore, 'return try interrupt(handoff, record: &record, cause: cause)',
    'return try interrupt(handoff, record: &record, cause: .webContentProcessExited)');
  assert.equal(retainedStore, old(app + 'AgentManagedBrowserContinuationStore.swift'), 'Exact control, lease, inbox, recovery, encryption, delivery and cookie logic retained');
  for (const token of ['guard managedBrowserPresentationIsCurrent(request)', 'try managedBrowserContinuations.reconcileHostProcess(request.binding)',
    'guard wait.hostProcessID == AgentOwnedOperationContext.processId', 'existing: context.task.browserViewLease',
    'store.commitSupervisedBrowserState(expected: context.task, updated: task)', 'catch AgentBrowserViewLease.Failure.viewLost',
    'try resolveSupervisedBrowser(wait, resolution: .interrupted(.browserViewClosed))']) assert(services.includes(token), token);
  const view = read(app + 'GalaxySSIManagedBrowserHandoffView.swift');
  for (const token of ['[weak coordinator, weak browser]', 'let lease = browser.lease', 'AgentBrowserViewLease.isLive(lease',
    'guard !browser.closed, isCurrent(coordinator)', 'beginManagedBrowserView(managed, id: browser.id)',
    'beginSupervisedBrowserView(plan, id: browser.id)', '.interactiveDismissDisabled()',
    'if browser.authorize() { try recordViewClosure() }', 'if browser.authorize() { try? recordViewClosure() }',
    'guard browser.authorize() else', 'AgentBrowserViewLease.release(lease)', 'deinit {', 'closed = true']) assert(view.includes(token), token);
  assert(view.indexOf('beginSupervisedBrowserView(plan, id: browser.id)') < view.indexOf('await browser.load(address'), 'No load before saved view ownership');
  const close = section(view, '  private func closeBrowser()', '  private func closeIfRetired()');
  assert(close.includes('if browser.authorize() { try recordViewClosure() }'), 'A failed second sheet cannot retire the first view');
  assert(close.indexOf('try recordViewClosure()') < close.indexOf('presentation.wrappedValue.dismiss()'), 'Explicit close must save before dismissal');
  assert(section(view, '  private func recordViewClosure()', '  private func closeBrowser()').includes('guard browser.authorize() else'));
  for (const [first, last] of [['  private func returnControl()', '  private func t('],
    ['  private var loaded', '  var view: WKWebView']]) assert.equal(section(view, first, last), section(old(app + 'GalaxySSIManagedBrowserHandoffView.swift'), first, last));
  const nav = '  func webView(_ webView: WKWebView, decidePolicyFor action:';
  assert.equal(view.slice(view.indexOf(nav)), old(app + 'GalaxySSIManagedBrowserHandoffView.swift').slice(old(app + 'GalaxySSIManagedBrowserHandoffView.swift').indexOf(nav)),
    'All WebKit URL/DNS/response/cookie/observation policies unchanged');
  for (const name of ['AgentModelToolLoop', 'AgentModelLoopJournal', 'AgentSupervisedBrowserWait', 'GalaxySSIStore', 'AgentPlanNodeJournal', 'AgentActionEffectExecutor'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/AgentBrowserViewLeaseTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 8);
  for (const token of ['testFailedPersistenceLeavesNoActiveAuthorityForTheCandidate', 'testManagedStoreReopensOnlyTheSameLiveViewThenRecordsDurableLoss',
    'testPausedLostViewRemainsUnverifiedAndCannotRunUntilExplicitResume', 'testStoppedOrStaleGenerationCannotClaimOrReturnAView',
    'testSupervisedTaskLeaseIsOptionalForLegacyDataAndDoesNotRewriteItsPlan', '"requires_external_observation"']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentBrowserViewLease', 'AgentBrowserViewLeaseTests']) assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name);
  assert(!/\p{Script=Han}/u.test(lease + tests));
  const reference = cp.execFileSync('git', ['show', '822f73b8d01da5ef6ff950a360f6a1a03923d034:docs/architecture/managed-browser-control-events.md'], {cwd: root, encoding: 'utf8'});
  assert(reference.includes('It does not resume an active human-controlled handoff'));
  assert(reference.includes('Generation checks prevent an old cleanup from removing a replacement request'));
  console.log('Browser view ownership, pre-load persistence, lost-view interruption and retained recovery source contracts passed; eight XCTest methods authored, not executed.');
}
