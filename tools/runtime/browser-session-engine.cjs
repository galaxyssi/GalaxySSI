'use strict';

const { randomUUID, randomBytes, timingSafeEqual, createHash } = require('node:crypto');
const { existsSync, mkdirSync, writeFileSync, renameSync, rmSync } = require('node:fs');
const path = require('node:path');
const os = require('node:os');

class BrowserOperationError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function checkBrowserNativeDependencies({ platform = process.platform, arch = process.arch,
  libraryPath = process.env.LD_LIBRARY_PATH || '', exists = existsSync } = {}) {
  if (platform !== 'linux') return;
  const triple = { arm64: 'aarch64-linux-gnu', x64: 'x86_64-linux-gnu' }[arch];
  const roots = [...libraryPath.split(':').filter(Boolean), '/usr/lib', '/lib', '/usr/lib64', '/lib64',
    ...(triple ? [`/usr/lib/${triple}`, `/lib/${triple}`] : [])];
  for (const library of ['libsoftokn3.so', 'libfreeblpriv3.so', 'libnssckbi.so']) {
    if (!roots.some(root => exists(path.posix.join(root, library)))) {
      throw new BrowserOperationError('browser_native_library_missing',
        `Chromium HTTPS dependency ${library} is missing. Install the distribution NSS package ` +
        '(Debian/Ubuntu: libnss3) using runtime.execute, or update the browser pack; then run browser readiness ' +
        'and continue the original task. Do not disable TLS certificate validation.',
        { library, executed: false, goal_terminal: false });
    }
  }
}

function browserRuntimeLaunchOptions({ platform = process.platform, env = process.env,
  stateRoot = env.GALAXYSSI_BROWSER_STATE_ROOT || path.join(os.homedir(), '.local/state/galaxyssi-browser') } = {}) {
  if (platform !== 'linux' || !env.FONTCONFIG_FILE || !env.PLAYWRIGHT_BROWSERS_PATH) return {};
  const fonts = path.resolve(env.PLAYWRIGHT_BROWSERS_PATH, '../../share/fonts');
  if (!existsSync(fonts) || !existsSync(env.FONTCONFIG_FILE)) return {};
  const xml = value => value.replace(/[<>&"']/g, char => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[char]));
  // Published images relocate fonts but retain /usr/share/fonts in their immutable Fontconfig file.
  const content = '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">' +
    `<fontconfig><dir>${xml(fonts)}</dir><include ignore_missing="yes">${xml(env.FONTCONFIG_FILE)}</include></fontconfig>`;
  const file = path.join(stateRoot, `runtime-fonts-${createHash('sha256').update(content).digest('hex')}.conf`);
  mkdirSync(stateRoot, { recursive: true, mode: 0o700 });
  if (!existsSync(file)) {
    const temporary = `${file}.${randomUUID()}.tmp`;
    try {
      writeFileSync(temporary, content, { mode: 0o600, flag: 'wx' });
      renameSync(temporary, file);
    } finally { rmSync(temporary, { force: true }); }
  }
  return { env: { ...env, FONTCONFIG_FILE: file } };
}

function websiteUrl(value) {
  let url;
  try { url = new URL(value); } catch {
    throw new BrowserOperationError('invalid_url', 'Provide an absolute HTTP or HTTPS URL.');
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new BrowserOperationError('invalid_url', 'Use HTTP or HTTPS without credentials in the URL.');
  }
  return url.href;
}

function publicUrl(value) {
  try {
    const url = new URL(value);
    url.username = ''; url.password = ''; url.hash = '';
    for (const key of url.searchParams.keys()) {
      if (/token|secret|password|code|credential|session/i.test(key)) url.searchParams.set(key, '[redacted]');
    }
    return url.href;
  } catch { return ''; }
}

function browserFailure(error, operation) {
  if (error instanceof BrowserOperationError) return error;
  const message = String(error?.message || '');
  let code = 'browser_operation_failed';
  const details = { error_type: error?.name || 'Error',
    outcome_unknown: !['create', 'observe', 'pages', 'screenshot', 'snapshot'].includes(operation) };
  const network = message.match(/\b(?:net::)?(ERR_[A-Z0-9_]+)\b/);
  const library = message.match(/error while loading shared libraries:\s*([A-Za-z0-9_.-]+)/);
  if (network) { code = 'browser_network_error'; details.network_error = network[1]; }
  else if (library) { code = 'browser_native_library_missing'; details.library = library[1]; }
  else if (message.includes("Executable doesn't exist")) code = 'browser_executable_missing';
  else if (error?.name === 'TimeoutError') code = ['navigate', 'create', 'back'].includes(operation)
    ? 'browser_navigation_timeout' : 'browser_action_timeout';
  else if (/has been closed|Target closed/.test(message)) code = 'browser_target_closed';
  return new BrowserOperationError(code,
    'Browser operation did not produce a confirmed outcome. Inspect the current page or runtime diagnostic before choosing the next action.', details);
}

// References live in the observed document, not in model-authored CSS selectors.
function installObservationState() {
  const key = '__galaxyssiInteractiveBrowser';
  if (Object.hasOwn(window, key)) return;
  const state = { documentId: `${Date.now()}-${Math.random()}`, revision: 0, sequence: 0, nodes: new Map() };
  const observer = new MutationObserver(() => { state.revision++; });
  observer.observe(document, { subtree: true, childList: true, characterData: true, attributes: true });
  state.flush = () => { if (observer.takeRecords().length) state.revision++; };
  Object.defineProperty(window, key, { value: state });
}

class BrowserSessions {
  constructor(chromium, { launchOptions = {}, timeoutMs = 15000 } = {}) {
    this.chromium = chromium;
    this.launchOptions = launchOptions;
    this.timeoutMs = timeoutMs;
    this.sessions = new Map();
    this.opening = null;
    this.browser = null;
    this.closing = false;
    this.lossObservers = new Set();
  }

  subscribeSessionLoss(listener) {
    this.lossObservers.add(listener);
    return () => this.lossObservers.delete(listener);
  }

  isSessionLive(id) {
    const session = this.sessions.get(id);
    return !!session && !session.lost;
  }

  markLost(session) {
    if (session.lost) return;
    session.lost = true;
    for (const listener of this.lossObservers) {
      try { listener(session.id); } catch {}
    }
  }

  async getBrowser() {
    if (this.closing) throw new BrowserOperationError('browser_closed', 'Browser service is stopping.');
    if (this.browser?.isConnected()) return this.browser;
    checkBrowserNativeDependencies();
    this.opening ??= this.chromium.launch({ headless: true, ...browserRuntimeLaunchOptions(), ...this.launchOptions }).then(browser => {
      this.browser = browser;
      browser.on('disconnected', () => {
        for (const session of this.sessions.values()) this.markLost(session);
        if (this.browser === browser) this.browser = null;
      });
      return browser;
    }).catch(error => { throw browserFailure(error, 'create'); }).finally(() => { this.opening = null; });
    return this.opening;
  }

  async execute(input, signal) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) {
      throw new BrowserOperationError('invalid_request', 'Provide a browser operation object.');
    }
    if (signal?.aborted) throw new BrowserOperationError('browser_operation_cancelled', 'Browser operation was cancelled.', { executed: false });
    if (input.operation === 'create') return this.create(input, signal);
    return this.inSession(input, signal, session => {
      if (session.humanControl) throw new BrowserOperationError('browser_user_control_active',
        'The user controls this browser. Wait for control to be returned, then observe the page before continuing.',
        { executed: false, goal_terminal: false, control_owner: 'user' });
      return this.operate(session, input);
    });
  }

  async inSession(input, signal, operation) {
    const session = this.sessions.get(input.session_id);
    if (!session) throw new BrowserOperationError('session_not_found',
      'This browser session is not live. Create a session or resume authentication; do not assume the previous action failed.');
    // A queue belongs to one context; different contexts can proceed independently.
    const previous = session.tail;
    let release;
    session.tail = new Promise(resolve => { release = resolve; });
    await previous;
    const cancel = () => {
      if (['observe', 'pages', 'screenshot', 'snapshot'].includes(input.operation)) return;
      this.markLost(session);
      void session.context.close().catch(() => {});
    };
    try {
      if (signal?.aborted) throw new BrowserOperationError('browser_operation_cancelled', 'Queued browser operation was cancelled.', { executed: false });
      signal?.addEventListener('abort', cancel, { once: true });
      if (session.lost) throw new BrowserOperationError('session_lost',
        'The browser process was lost. Observe external state before repeating a submitted operation.');
      if (!this.sessions.has(input.session_id)) throw new BrowserOperationError('session_closed', 'Session was closed.');
      return await operation(session);
    } catch (error) {
      if (error instanceof BrowserOperationError && error.details.executed === false) throw error;
      if (signal?.aborted) throw new BrowserOperationError('browser_operation_cancelled',
        'Browser operation was cancelled. Inspect external state before repeating a submitted operation.',
        { outcome_unknown: true });
      // Raw Playwright messages can include typed values and page text.
      throw browserFailure(error, input.operation);
    } finally { signal?.removeEventListener('abort', cancel); release(); }
  }

  // Host-only entry points. Neither the lease nor these methods is a model tool.
  async beginHumanControl(input, signal) {
    return this.inSession({ ...input, operation: 'human_control_begin' }, signal, session => {
      if (session.humanControl) throw new BrowserOperationError('browser_user_control_active',
        'A user control lease already exists.', { executed: false, goal_terminal: false });
      const page = session.pages.get(input.page_id);
      if (!page || page.isClosed()) throw new BrowserOperationError('page_not_found', 'Choose a live page in this session.', { executed: false });
      session.controlEpoch = (session.controlEpoch || 0) + 1;
      session.humanControl = randomBytes(32).toString('hex');
      return { session_id: session.id, page_id: input.page_id, control_owner: 'user',
        control_token: session.humanControl, business_success_verified: false };
    });
  }

  requireHumanControl(session, token) {
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token) || !session.humanControl ||
        !timingSafeEqual(Buffer.from(token, 'hex'), Buffer.from(session.humanControl, 'hex'))) {
      throw new BrowserOperationError('browser_user_control_invalid',
        'This user control lease is not active in this browser session.', { executed: false, goal_terminal: false });
    }
  }

  async executeHuman(input, token, signal) {
    return this.inSession(input, signal, async session => {
      this.requireHumanControl(session, token);
      if (!['pages', 'observe', 'screenshot', 'navigate', 'back', 'click', 'fill', 'select', 'dialog',
        'snapshot', 'pointer', 'scroll', 'insert_text', 'press'].includes(input.operation)) {
        throw new BrowserOperationError('invalid_user_browser_operation',
          'Use an existing page operation during user control.', { executed: false });
      }
      const result = ['snapshot', 'pointer', 'scroll', 'insert_text', 'press'].includes(input.operation)
        ? await this.operateHumanSurface(session, input) : await this.operate(session, input);
      return { ...result, control_owner: 'user', business_success_verified: false };
    });
  }

  async operateHumanSurface(session, input) {
    const page = session.pages.get(input.page_id);
    if (!page || page.isClosed()) throw new BrowserOperationError('page_not_found', 'Choose a live page.', { executed: false });
    if (input.operation === 'snapshot') {
      if (input.width !== undefined || input.height !== undefined) {
        if (![input.width, input.height].every(value => Number.isInteger(value) && value >= 240 && value <= 2560)) {
          throw new BrowserOperationError('invalid_user_viewport', 'Choose a supported user viewport.', { executed: false });
        }
        const viewport = page.viewportSize();
        if (viewport?.width !== input.width || viewport?.height !== input.height) {
          await page.setViewportSize({ width: input.width, height: input.height });
        }
      }
      const observed = await this.operate(session, { ...input, operation: 'observe' });
      if (observed.dialog) return observed;
      let data;
      for (const quality of [60, 35, 20, 10]) {
        data = await page.screenshot({ type: 'jpeg', quality, fullPage: false, scale: 'css' });
        if (data.length <= 256 * 1024) break;
      }
      if (data.length > 256 * 1024) throw new BrowserOperationError('browser_user_preview_too_large',
        'Choose a smaller user viewport before refreshing.', { executed: false, goal_terminal: false });
      const screenshot = { session_id: session.id, page_id: input.page_id, mime_type: 'image/jpeg', data_b64: data.toString('base64') };
      // Chromium's capture temporarily changes caret styles; establish references after it restores them.
      const current = await this.operate(session, { ...input, operation: 'observe' });
      if (current.dialog) return current;
      return { ...current, ...screenshot, viewport: page.viewportSize() };
    }
    const prefix = `${session.controlEpoch || 0}:`;
    const fresh = typeof input.revision === 'string' && input.revision.startsWith(prefix) &&
      await page.evaluate(revision => {
        const state = window.__galaxyssiInteractiveBrowser;
        if (!state) return false;
        state.flush();
        return state.observation === revision && state.observedMutation === state.revision;
      }, input.revision.slice(prefix.length));
    if (!fresh) throw new BrowserOperationError('page_observation_stale', 'Refresh the user page before acting.', { executed: false });
    if (input.operation === 'pointer') {
      const viewport = page.viewportSize();
      if (!viewport || ![input.x, input.y].every(Number.isFinite) || input.x < 0 || input.y < 0 ||
          input.x >= viewport.width || input.y >= viewport.height) throw new BrowserOperationError('invalid_user_pointer',
        'Choose a point inside the displayed page.', { executed: false });
      await this.dispatch(page, () => page.mouse.click(input.x, input.y));
    } else if (input.operation === 'scroll') {
      if (!Number.isFinite(input.delta_y) || Math.abs(input.delta_y) > 2560) throw new BrowserOperationError('invalid_user_scroll',
        'Choose a bounded user scroll distance.', { executed: false });
      await page.mouse.wheel(0, input.delta_y);
    } else if (input.operation === 'insert_text') {
      if (typeof input.value !== 'string' || input.value.length > 65536) throw new BrowserOperationError('invalid_value',
        'Provide bounded user input.', { executed: false });
      const editable = await Promise.all(page.frames().map(frame => frame.evaluate(() => {
        const node = document.activeElement;
        return document.hasFocus() && node && (node.isContentEditable || ['INPUT', 'TEXTAREA'].includes(node.tagName)) &&
          !node.disabled && !node.readOnly;
      }).catch(() => false)));
      if (!editable.some(Boolean)) throw new BrowserOperationError('browser_text_target_missing',
        'Select an editable page field before entering text.', { executed: false });
      if (input.replace !== false) await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.insertText(input.value);
    } else if (input.operation === 'press') {
      if (!['Enter', 'Tab', 'Escape', 'Backspace', 'ArrowUp', 'ArrowDown'].includes(input.key)) throw new BrowserOperationError(
        'invalid_user_key', 'Choose a supported user key.', { executed: false });
      await this.dispatch(page, () => page.keyboard.press(input.key));
    }
    return { session_id: session.id, page_id: input.page_id, action_dispatched: true, next_action: 'observe' };
  }

  async finishHumanControl(input, token, signal) {
    return this.inSession({ ...input, operation: 'human_control_finish' }, signal, session => {
      this.requireHumanControl(session, token);
      session.humanControl = null;
      session.controlEpoch = (session.controlEpoch || 0) + 1;
      return { session_id: session.id, control_owner: 'agent', business_success_verified: false,
        next_action: 'observe', authentication_verified: false };
    });
  }

  async create(input, signal) {
    const url = input.url ? websiteUrl(input.url) : null;
    const browser = await this.getBrowser();
    if (signal?.aborted) throw new BrowserOperationError('browser_operation_cancelled', 'Browser creation was cancelled.', { executed: false });
    const context = await browser.newContext({ acceptDownloads: false, ignoreHTTPSErrors: false });
    const cancel = () => { void context.close().catch(() => {}); };
    signal?.addEventListener('abort', cancel, { once: true });
    const session = { id: randomUUID(), context, pages: new Map(), frames: new Map(), dialogs: new Map(),
      tail: Promise.resolve(), lost: false };
    try {
      if (signal?.aborted) { await context.close(); throw new BrowserOperationError('browser_operation_cancelled', 'Browser creation was cancelled.', { executed: false }); }
      context.setDefaultTimeout(this.timeoutMs);
      context.setDefaultNavigationTimeout(this.timeoutMs);
      await context.addInitScript(installObservationState);
      context.on('page', page => this.registerPage(session, page));
      this.sessions.set(session.id, session);
      context.on('close', () => this.markLost(session));
      const page = await context.newPage();
      const pageId = this.registerPage(session, page);
      if (url) await page.goto(url, { waitUntil: 'domcontentloaded' });
      return { session_id: session.id, page_id: pageId, ...(await this.observe(session, page)),
        cookies_persist: true, storage_scope: 'live_isolated_context', business_success_verified: false };
    } catch (error) {
      if (signal?.aborted) {
        await context.close().catch(() => {});
        this.sessions.delete(session.id);
        throw new BrowserOperationError('browser_operation_cancelled', 'Browser creation was cancelled.',
          error instanceof BrowserOperationError && error.details.executed === false ? { executed: false } : { outcome_unknown: true });
      }
      if (!this.sessions.has(session.id)) { await context.close().catch(() => {}); throw browserFailure(error, 'create'); }
      // Navigation may time out after a useful document or login redirect arrived.
      return { session_id: session.id, pages: this.pages(session), navigation_completed: false,
        error: { code: browserFailure(error, 'create').code, details: browserFailure(error, 'create').details,
          message: 'Inspect this live session before retrying navigation.' },
        business_success_verified: false };
    } finally { signal?.removeEventListener('abort', cancel); }
  }

  registerPage(session, page) {
    const existing = [...session.pages].find(([, value]) => value === page);
    if (existing) return existing[0];
    const id = randomUUID();
    session.pages.set(id, page);
    page.on('dialog', dialog => session.dialogs.set(id, dialog));
    page.on('close', () => { session.pages.delete(id); session.dialogs.delete(id); });
    return id;
  }

  pages(session) {
    return [...session.pages].filter(([, page]) => !page.isClosed())
      .map(([page_id, page]) => ({ page_id, url: publicUrl(page.url()) }));
  }

  async observe(session, page, target = page, options = {}) {
    const textOffset = options.text_offset ?? 0;
    const controlOffset = options.control_offset ?? 0;
    if (![textOffset, controlOffset].every(value => Number.isSafeInteger(value) && value >= 0)) {
      throw new BrowserOperationError('invalid_observation_offset', 'Observation offsets must be nonnegative integers.');
    }
    await target.evaluate(installObservationState);
    const observation = await target.evaluate(({ textOffset, controlOffset }) => {
      const state = window.__galaxyssiInteractiveBrowser;
      state.flush(); state.nodes.clear();
      const controls = [];
      const candidates = document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"],[contenteditable="true"]');
      let visibleCount = 0;
      for (const node of candidates) {
        if (!node.getClientRects().length || getComputedStyle(node).visibility === 'hidden' || node.type === 'hidden') continue;
        visibleCount++;
        if (visibleCount <= controlOffset) continue;
        if (controls.length >= 200) continue;
        const ref = `node-${++state.sequence}`;
        state.nodes.set(ref, node);
        controls.push({ node_id: ref, tag: node.tagName.toLowerCase(), role: node.getAttribute('role') || '',
          type: node.type || '', label: (node.getAttribute('aria-label') || node.labels?.[0]?.innerText ||
            node.getAttribute('placeholder') || node.innerText || node.title || '').slice(0, 300),
          disabled: !!node.disabled, password: node.type === 'password' });
      }
      const text = document.body?.innerText || '';
      const revision = `${state.documentId}:${state.revision}:${state.sequence}`;
      state.observation = revision;
      state.observedMutation = state.revision;
      const nextText = textOffset + 16000 < text.length ? textOffset + 16000 : null;
      const nextControls = controlOffset + controls.length < visibleCount ? controlOffset + controls.length : null;
      return { title: document.title, text: text.slice(textOffset, textOffset + 16000), text_offset: textOffset,
        text_truncated: nextText !== null, next_text_offset: nextText,
        controls, control_offset: controlOffset, controls_truncated: nextControls !== null,
        next_control_offset: nextControls, revision };
    }, { textOffset, controlOffset });
    const frames = page.frames().slice(1).map(frame => {
      let id = [...session.frames].find(([, value]) => value === frame)?.[0];
      if (!id) { id = randomUUID(); session.frames.set(id, frame); }
      return { frame_id: id, url: publicUrl(frame.url()) };
    });
    for (const [id, frame] of session.frames) { if (frame.isDetached()) session.frames.delete(id); }
    return { ...observation, revision: `${session.controlEpoch || 0}:${observation.revision}`,
      url: publicUrl(target.url()), frames,
      evidence_trust: 'untrusted_page_content' };
  }

  async referencedNode(session, page, input) {
    if (typeof input.revision !== 'string' || typeof input.node_id !== 'string') {
      throw new BrowserOperationError('observation_required', 'Observe this page and use its revision and node_id.');
    }
    const prefix = `${session.controlEpoch || 0}:`;
    if (!input.revision.startsWith(prefix)) throw new BrowserOperationError('page_observation_stale',
      'Browser control changed. Observe again before acting.', { executed: false, goal_terminal: false });
    const handle = await page.evaluateHandle(({ revision, nodeId }) => {
      const state = window.__galaxyssiInteractiveBrowser;
      if (!state) return null;
      state.flush();
      if (state.observation !== revision || state.observedMutation !== state.revision) return null;
      const node = state.nodes.get(nodeId);
      return node?.isConnected ? node : null;
    }, { revision: input.revision.slice(prefix.length), nodeId: input.node_id });
    const node = handle.asElement();
    if (!node) {
      await handle.dispose();
      throw new BrowserOperationError('page_observation_stale', 'Page or controls changed. Observe again before acting.',
        { executed: false, goal_terminal: false });
    }
    return node;
  }

  async dispatch(page, action) {
    let listener;
    const dialog = new Promise(resolve => { listener = resolve; page.once('dialog', listener); });
    try { await Promise.race([Promise.resolve().then(action), dialog]); }
    finally { page.off('dialog', listener); }
  }

  async operate(session, input) {
    if (input.operation === 'close') {
      await session.context.close();
      this.sessions.delete(session.id);
      return { session_id: session.id, closed: true };
    }
    if (input.operation === 'pages') return { session_id: session.id, pages: this.pages(session) };
    const page = session.pages.get(input.page_id);
    if (!page || page.isClosed()) throw new BrowserOperationError('page_not_found', 'List the live pages and choose a page_id.');
    const dialog = session.dialogs.get(input.page_id);
    if (input.operation === 'dialog') {
      if (!dialog) throw new BrowserOperationError('dialog_not_found', 'No pending dialog on this page.');
      if (typeof input.accept !== 'boolean') throw new BrowserOperationError('invalid_dialog_decision', 'Provide accept as a boolean.');
      if (input.accept) await dialog.accept(typeof input.value === 'string' ? input.value : undefined);
      else await dialog.dismiss();
      session.dialogs.delete(input.page_id);
      return { action_dispatched: true, business_success_verified: false, next_action: 'observe' };
    }
    if (dialog) return { session_id: session.id, page_id: input.page_id,
      dialog: { type: dialog.type(), message: dialog.message().slice(0, 2000) },
      action_dispatched: false, next_action: 'dialog', evidence_trust: 'untrusted_page_content' };
    const target = input.frame_id ? session.frames.get(input.frame_id) : page;
    if (!target || (input.frame_id && (target.isDetached() || target.page() !== page))) {
      throw new BrowserOperationError('frame_not_found', 'Observe the page to get its live frame IDs.');
    }
    if (input.operation === 'observe') return { session_id: session.id, page_id: input.page_id,
      ...(input.frame_id ? { frame_id: input.frame_id } : {}), ...(await this.observe(session, page, target, input)) };
    if (input.operation === 'navigate') {
      await page.goto(websiteUrl(input.url), { waitUntil: 'domcontentloaded' });
    } else if (input.operation === 'back') {
      await page.goBack({ waitUntil: 'domcontentloaded' });
    } else if (input.operation === 'screenshot') {
      const data = await page.screenshot({ type: 'jpeg', quality: 70, fullPage: false });
      return { session_id: session.id, page_id: input.page_id, mime_type: 'image/jpeg', data_b64: data.toString('base64') };
    } else if (['click', 'fill', 'select'].includes(input.operation)) {
      if (['fill', 'select'].includes(input.operation) && typeof input.value !== 'string') {
        throw new BrowserOperationError('invalid_value', 'Provide a string value.');
      }
      const node = await this.referencedNode(session, target, input);
      try {
        await this.dispatch(page, () => input.operation === 'click' ? node.click()
          : input.operation === 'fill' ? node.fill(input.value) : node.selectOption(input.value));
      } finally { await node.dispose(); }
    } else {
      throw new BrowserOperationError('unknown_operation', 'Use create, pages, observe, navigate, back, click, fill, select, dialog, screenshot or close.');
    }
    // A tool dispatch or successful click is not proof of login or task completion.
    return { session_id: session.id, page_id: input.page_id, action_dispatched: true,
      business_success_verified: false, pages: this.pages(session), next_action: 'observe' };
  }

  async close() {
    this.closing = true;
    const browser = this.browser || await this.opening?.catch(() => null);
    if (browser) await browser.close();
    this.sessions.clear();
  }
}

module.exports = { BrowserSessions, BrowserOperationError, websiteUrl, publicUrl, browserFailure,
  checkBrowserNativeDependencies, browserRuntimeLaunchOptions };
