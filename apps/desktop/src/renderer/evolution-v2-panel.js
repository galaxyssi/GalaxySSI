(() => {
  "use strict";

  const api = window.signalasi?.evolutionV2Request;
  if (typeof api !== "function") return;

  const state = {
    tab: "preflight",
    latestResearchId: "",
    busy: false,
    renderToken: 0
  };

  const tabs = [
    ["preflight", "Preflight"],
    ["radar", "Technology radar"],
    ["roadmap", "1-5 year roadmap"],
    ["proposals", "Proposals"],
    ["campaigns", "Campaigns"],
    ["audit", "Audit"]
  ];

  let shell;
  let toolbar;
  let content;
  let status;

  function translate(key, params = {}) {
    const translator = window.signalasiDesktopI18n?.translate;
    if (typeof translator === "function") return translator(key, params);
    let value = String(key);
    for (const [name, replacement] of Object.entries(params)) {
      value = value.replaceAll(`{${name}}`, String(replacement));
    }
    return value;
  }

  function request(method, path, body) {
    return api(method, path, body === undefined ? null : body);
  }

  function node(tag, className = "", text = "") {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text) element.textContent = text;
    return element;
  }

  function actionButton(text, handler, primary = false) {
    const element = node("button", primary ? "primary" : "", text);
    element.type = "button";
    element.addEventListener("click", async () => {
      if (state.busy) return;
      state.busy = true;
      element.disabled = true;
      try {
        await handler();
      } catch (error) {
        setStatus(String(error?.message || error), true);
      } finally {
        state.busy = false;
        element.disabled = false;
      }
    });
    return element;
  }

  function chip(text, kind = "") {
    return node("span", `evolution-v2-chip ${kind}`.trim(), text);
  }

  function card(title, description = "") {
    const element = node("article", "evolution-v2-card");
    element.append(node("h4", "", title));
    if (description) element.append(node("p", "", description));
    return element;
  }

  function setStatus(message, failed = false) {
    if (!status) return;
    status.textContent = message || "";
    status.classList.toggle("failed", failed);
  }

  function renderToolbar() {
    toolbar.replaceChildren();
    for (const [id, key] of tabs) {
      const tab = node("button", "evolution-v2-tab", translate(key));
      tab.type = "button";
      tab.dataset.tab = id;
      tab.classList.toggle("active", id === state.tab);
      tab.addEventListener("click", () => {
        state.tab = id;
        render();
      });
      toolbar.append(tab);
    }
  }

  function mount() {
    if (document.querySelector("#evolutionV2Shell")) return;
    const taskList = document.querySelector("#evolutionTaskList");
    if (!taskList) return;

    if (!document.querySelector('link[href="./evolution-v2-panel.css"]')) {
      const stylesheet = document.createElement("link");
      stylesheet.rel = "stylesheet";
      stylesheet.href = "./evolution-v2-panel.css";
      document.head.append(stylesheet);
    }

    shell = node("div", "evolution-v2-shell");
    shell.id = "evolutionV2Shell";
    toolbar = node("div", "evolution-v2-toolbar");
    content = node("div", "evolution-v2-content");
    shell.append(toolbar, content);
    taskList.insertAdjacentElement("afterend", shell);
    renderToolbar();
    render();
  }

  async function render() {
    const renderToken = ++state.renderToken;
    renderToolbar();
    content.replaceChildren();
    status = node("div", "evolution-v2-status");
    const view = node("div", "evolution-v2-view");
    content.append(status);
    try {
      const renderer = {
        preflight: renderPreflight,
        radar: renderRadar,
        roadmap: renderRoadmap,
        proposals: renderProposals,
        campaigns: renderCampaigns,
        audit: renderAudit
      }[state.tab];
      await renderer(view);
      if (renderToken === state.renderToken) content.append(view);
    } catch (error) {
      if (renderToken === state.renderToken) {
        setStatus(String(error?.message || error), true);
      }
    }
  }

  async function renderPreflight(target) {
    const actions = node("div", "evolution-v2-actions");
    actions.append(
      actionButton(translate("Refresh"), render),
      actionButton(translate("Run scheduled research and diagnostics"), async () => {
        setStatus(translate("Running..."));
        const result = await request("POST", "/scheduler/tick?force=true");
        setStatus(JSON.stringify(result));
      }, true)
    );
    target.append(actions);
    const [preflight, health] = await Promise.all([
      request("GET", "/preflight"),
      request("GET", "/health")
    ]);
    const grid = node("div", "evolution-v2-grid");
    const summary = card(
      translate(preflight.ready
        ? "Self-evolution environment is ready"
        : "Environment has blocking items"),
      translate("Repository write access stays in the Desktop gh CLI; the App stores no write token.")
    );
    summary.append(chip(
      translate(preflight.ready ? "Ready" : "Not ready"),
      preflight.ready ? "pass" : "fail"
    ));
    summary.append(chip(
      translate(health.started ? "Runtime on" : "Runtime off"),
      health.started ? "pass" : "warn"
    ));
    grid.append(summary);
    for (const check of preflight.checks || []) {
      const item = card(check.check_id, check.summary || "");
      item.append(chip(
        check.status,
        check.status === "passed" ? "pass" : check.required ? "fail" : "warn"
      ));
      if (!check.required) item.append(chip(translate("Optional")));
      grid.append(item);
    }
    target.append(grid);
  }

  async function renderRadar(target) {
    const query = node("input", "evolution-v2-query");
    query.placeholder = translate("For example: MCP, Agent Skills, multi-Agent, coding agents");
    const actions = node("div", "evolution-v2-actions");
    actions.append(actionButton(
      translate("Scan official and newly popular projects"),
      async () => {
        setStatus(translate("Collecting metadata through the Desktop GitHub CLI..."));
        const result = await request("POST", "/research/runs", {
          query: query.value.trim(),
          trusted_only: false,
          limit: 40,
          create_proposals: true
        });
        state.latestResearchId = result.run?.run_id || "";
        setStatus(translate("Completed: {count} candidates", {
          count: result.run?.items?.length || 0
        }));
        await render();
      },
      true
    ));
    target.append(query, actions);
    const response = await request("GET", "/research/runs?limit=5");
    const grid = node("div", "evolution-v2-grid");
    for (const run of response.runs || []) {
      if (!state.latestResearchId) state.latestResearchId = run.run_id;
      const created = new Date(Number(run.created_at_millis || 0)).toLocaleString();
      const runCard = card(run.query || run.run_id, `${run.status} | ${created}`);
      const meta = node("div", "evolution-v2-meta");
      meta.append(chip(translate("{count} items", {
        count: run.items?.length || 0
      }), "pass"));
      if (run.errors?.length) {
        meta.append(chip(translate("{count} errors", {
          count: run.errors.length
        }), "warn"));
      }
      runCard.append(meta);
      for (const item of (run.items || []).slice(0, 10)) {
        const candidate = card(item.repository, item.description || "");
        const candidateMeta = node("div", "evolution-v2-meta");
        candidateMeta.append(
          chip(translate("Score {score}", { score: item.total_score })),
          chip(item.recommendation, item.recommendation === "adopt"
            ? "pass"
            : item.recommendation === "evaluate"
              ? "warn"
              : ""),
          chip(`* ${item.stars || 0}`),
          chip(item.license || translate("No license information"), item.license ? "" : "warn")
        );
        candidate.append(candidateMeta);
        runCard.append(candidate);
      }
      grid.append(runCard);
    }
    if (!grid.children.length) {
      grid.append(node("div", "evolution-v2-empty", translate("No technology radar results yet.")));
    }
    target.append(grid);
  }

  async function renderRoadmap(target) {
    const actions = node("div", "evolution-v2-actions");
    actions.append(actionButton(
      translate("Generate roadmap from latest radar"),
      async () => {
        const result = await request("POST", "/roadmaps", {
          goal: "Evolve SignalASI into a safe, interoperable, durable personal super Agent.",
          research_run_ids: state.latestResearchId ? [state.latestResearchId] : []
        });
        setStatus(translate("Generated {count} milestones", {
          count: result.items?.length || 0
        }));
        await render();
      },
      true
    ));
    target.append(actions);
    const response = await request("GET", "/roadmaps?limit=5");
    const grid = node("div", "evolution-v2-grid");
    for (const roadmap of response.roadmaps || []) {
      const outer = card(roadmap.title, roadmap.goal);
      for (const item of roadmap.items || []) {
        const row = card(item.title, item.outcome);
        const meta = node("div", "evolution-v2-meta");
        meta.append(
          chip(item.horizon),
          chip(item.strategic_pillar),
          chip(item.risk_level, item.risk_level === "critical" ? "fail" : "warn")
        );
        row.append(meta);
        outer.append(row);
      }
      grid.append(outer);
    }
    if (!grid.children.length) {
      grid.append(node("div", "evolution-v2-empty", translate("No roadmap yet.")));
    }
    target.append(grid);
  }

  async function renderProposals(target) {
    const response = await request("GET", "/proposals?limit=100");
    const grid = node("div", "evolution-v2-grid");
    for (const proposal of response.proposals || []) {
      const item = card(proposal.title, proposal.problem);
      const meta = node("div", "evolution-v2-meta");
      meta.append(
        chip(proposal.origin),
        chip(proposal.risk_level, proposal.risk_level === "critical" ? "fail" : "warn"),
        chip(proposal.status)
      );
      item.append(meta);
      if (!proposal.task_id) {
        const actions = node("div", "evolution-v2-actions");
        actions.append(actionButton(
          translate("Create isolated task"),
          async () => {
            const result = await request(
              "POST",
              `/proposals/${encodeURIComponent(proposal.proposal_id)}/materialize`,
              { agent_id: "codex", max_attempts: 5, start: false }
            );
            setStatus(translate(
              "Created task {taskId}; start it from the task list above.",
              { taskId: result.task?.task_id || "" }
            ));
            await render();
          },
          true
        ));
        item.append(actions);
      } else {
        item.append(node("p", "", `${translate("Task")}: ${proposal.task_id}`));
      }
      grid.append(item);
    }
    if (!grid.children.length) {
      grid.append(node(
        "div",
        "evolution-v2-empty",
        translate("Radar and diagnostic proposals appear here.")
      ));
    }
    target.append(grid);
  }

  async function renderCampaigns(target) {
    const actions = node("div", "evolution-v2-actions");
    actions.append(actionButton(translate("Refresh"), render));
    target.append(actions);
    const response = await request("GET", "/campaigns?limit=100");
    const grid = node("div", "evolution-v2-grid");
    for (const campaign of response.campaigns || []) {
      const item = card(campaign.name, campaign.objective);
      const meta = node("div", "evolution-v2-meta");
      meta.append(
        chip(campaign.status),
        chip(translate("{count} nodes", { count: campaign.nodes?.length || 0 }))
      );
      item.append(meta);
      const nodeList = node("div", "evolution-v2-grid");
      for (const campaignNode of campaign.nodes || []) {
        nodeList.append(card(
          campaignNode.node_id,
          `${campaignNode.status}${campaignNode.task_id ? ` | ${campaignNode.task_id}` : ""}`
        ));
      }
      item.append(nodeList);
      const tickActions = node("div", "evolution-v2-actions");
      tickActions.append(actionButton(
        translate("Advance ready nodes"),
        async () => {
          await request(
            "POST",
            `/campaigns/${encodeURIComponent(campaign.campaign_id)}/tick`,
            { start_ready: true }
          );
          await render();
        },
        true
      ));
      item.append(tickActions);
      grid.append(item);
    }
    if (!grid.children.length) {
      grid.append(node(
        "div",
        "evolution-v2-empty",
        translate("Create DAG evolution campaigns through the API or future roadmap batch actions.")
      ));
    }
    target.append(grid);
  }

  async function renderAudit(target) {
    const response = await request("GET", "/audit?limit=100");
    const integrity = response.integrity || {};
    const summary = card(
      translate(integrity.valid ? "Audit chain is valid" : "Audit chain is invalid"),
      translate("{count} records", { count: integrity.records || 0 })
    );
    if (integrity.head_hash) {
      summary.append(node("p", "evolution-v2-hash", integrity.head_hash));
    }
    summary.append(chip(
      translate(integrity.valid ? "Pass" : "Fail"),
      integrity.valid ? "pass" : "fail"
    ));
    target.append(summary);
    const grid = node("div", "evolution-v2-grid");
    for (const event of response.events || []) {
      const timestamp = new Date(Number(event.timestamp_millis || 0)).toLocaleString();
      const item = card(
        event.event || "event",
        `${timestamp} | ${event.task_id || "desktop"}`
      );
      item.append(node(
        "pre",
        "evolution-v2-output",
        JSON.stringify(event.payload || {}, null, 2)
      ));
      grid.append(item);
    }
    target.append(grid);
  }

  document.addEventListener("signalasi:locale-changed", () => {
    if (!shell) return;
    renderToolbar();
    render();
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount, { once: true });
  } else {
    mount();
  }
})();
