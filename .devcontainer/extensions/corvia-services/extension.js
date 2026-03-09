const vscode = require("vscode");
const { exec } = require("child_process");
const http = require("http");

const SERVICES = ["coding-llm", "ollama", "surrealdb"];
const WORKSPACE_ROOT =
    process.env.CORVIA_WORKSPACE || "/workspaces/corvia-workspace";

let statusBarItem;
let dashboardPanel;

function activate(context) {
    statusBarItem = vscode.window.createStatusBarItem(
        vscode.StatusBarAlignment.Right,
        50
    );
    statusBarItem.command = "corvia.openDashboard";
    context.subscriptions.push(statusBarItem);

    context.subscriptions.push(
        vscode.commands.registerCommand("corvia.toggleServices", showServiceMenu)
    );
    context.subscriptions.push(
        vscode.commands.registerCommand("corvia.openDashboard", () =>
            openDashboard(context)
        )
    );

    refreshStatus();
    const interval = setInterval(refreshStatus, 15000);
    context.subscriptions.push({ dispose: () => clearInterval(interval) });
}

// --- Data ---

function run(cmd) {
    return new Promise((resolve) => {
        exec(
            cmd,
            { cwd: WORKSPACE_ROOT, timeout: 10000 },
            (err, stdout, stderr) => resolve((stdout || "").trim())
        );
    });
}

function httpCheck(port, path) {
    return new Promise((resolve) => {
        const start = Date.now();
        const req = http.get(
            { hostname: "127.0.0.1", port, path, timeout: 3000 },
            (res) => {
                let data = "";
                res.on("data", (c) => (data += c));
                res.on("end", () =>
                    resolve({ healthy: true, latency: Date.now() - start, raw: data })
                );
            }
        );
        req.on("error", () => resolve({ healthy: false, latency: -1, raw: null }));
        req.on("timeout", () => {
            req.destroy();
            resolve({ healthy: false, latency: -1, raw: null });
        });
    });
}

async function collectAll() {
    const [workspaceStatus, serviceStatus, server, inference, agentList, supervisorLog] =
        await Promise.all([
            run("corvia workspace status"),
            run("corvia-workspace status"),
            httpCheck(8020, "/health"),
            httpCheck(8030, "/health"),
            run("corvia agent list"),
            run("tail -20 /tmp/corvia-supervisor.log 2>/dev/null"),
        ]);

    return {
        workspace: parseWorkspaceStatus(workspaceStatus),
        services: parseServiceStatus(serviceStatus),
        server,
        inference,
        agents: agentList || "No registered agents.",
        supervisorLog: supervisorLog || "",
        timestamp: new Date().toISOString(),
    };
}

function parseWorkspaceStatus(raw) {
    if (!raw) return null;
    const result = { name: "", scope: "", store: "", embedding: "", repos: [] };
    const wsMatch = raw.match(/Workspace:\s+(\S+)\s+\(scope:\s+(\S+)\)/);
    if (wsMatch) { result.name = wsMatch[1]; result.scope = wsMatch[2]; }
    const storeMatch = raw.match(/Store:\s+(.+)/);
    if (storeMatch) result.store = storeMatch[1].trim();
    const embMatch = raw.match(/Embedding:\s+(.+)/);
    if (embMatch) result.embedding = embMatch[1].trim();
    const repoRegex = /^\s+(\S+)\s+\[(\S+)\]\s+namespace:(\S+)/gm;
    let m;
    while ((m = repoRegex.exec(raw)) !== null) {
        const repo = { name: m[1], status: m[2], namespace: m[3] };
        const block = raw.slice(m.index);
        const urlMatch = block.match(/url:\s+(\S+)/);
        const pathMatch = block.match(/path:\s+(\S+)/);
        if (urlMatch) repo.url = urlMatch[1];
        if (pathMatch) repo.path = pathMatch[1];
        result.repos.push(repo);
    }
    return result;
}

function parseServiceStatus(raw) {
    const result = {};
    for (const svc of SERVICES) {
        const match = raw.match(new RegExp(`${svc}\\s+enabled=(\\S+)(?:\\s+running=(\\S+))?`));
        result[svc] = match
            ? { enabled: match[1] === "enabled", running: match[2] === "yes" }
            : { enabled: false, running: false };
    }
    return result;
}

// --- Status Bar ---

function refreshStatus() {
    collectAll().then((data) => {
        const enabledSvcs = SERVICES.filter((s) => data.services[s]?.enabled);
        const ok = data.server.healthy;
        const icon = ok ? "$(pass)" : "$(error)";
        const svcText = enabledSvcs.length > 0
            ? enabledSvcs.map((s) => ({ "coding-llm": "LLM", ollama: "Ollama", surrealdb: "Surreal" }[s] || s)).join(" ")
            : "no extras";
        statusBarItem.text = `${icon} Corvia | ${svcText}`;
        statusBarItem.backgroundColor = ok
            ? undefined
            : new vscode.ThemeColor("statusBarItem.errorBackground");
        const lines = [];
        if (data.workspace) {
            lines.push(`${data.workspace.name} (${data.workspace.scope})`);
            lines.push(`Store: ${data.workspace.store}`);
        }
        lines.push(`Server: ${ok ? "healthy" : "DOWN"} | Inference: ${data.inference.healthy ? "healthy" : "DOWN"}`);
        lines.push("", "Click to open dashboard");
        statusBarItem.tooltip = lines.join("\n");
        statusBarItem.show();

        if (dashboardPanel) {
            dashboardPanel.webview.postMessage({ type: "update", data });
        }
    });
}

// --- Dashboard ---

function openDashboard(context) {
    if (dashboardPanel) { dashboardPanel.reveal(); return; }

    dashboardPanel = vscode.window.createWebviewPanel(
        "corviaDashboard",
        "Corvia Dashboard",
        vscode.ViewColumn.One,
        { enableScripts: true, retainContextWhenHidden: true }
    );

    dashboardPanel.webview.html = getDashboardHtml();

    dashboardPanel.webview.onDidReceiveMessage(
        async (msg) => {
            if (msg.type === "toggle") {
                const action = msg.enable ? "enable" : "disable";
                const terminal = vscode.window.createTerminal({ name: `Corvia: ${action} ${msg.service}` });
                terminal.show();
                terminal.sendText(`corvia-workspace ${action} ${msg.service}`);
                setTimeout(refreshStatus, 8000);
            } else if (msg.type === "refresh") {
                refreshStatus();
            } else if (msg.type === "command") {
                const terminal = vscode.window.createTerminal({ name: `Corvia` });
                terminal.show();
                terminal.sendText(msg.cmd);
            }
        },
        undefined,
        context.subscriptions
    );

    dashboardPanel.onDidDispose(() => { dashboardPanel = null; });
    refreshStatus();
}

function getDashboardHtml() {
    return /*html*/ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
/* ===== Reset & Tokens ===== */
:root {
  --bg:       var(--vscode-editor-background);
  --fg:       var(--vscode-editor-foreground);
  --fg-muted: var(--vscode-descriptionForeground, #888);
  --border:   var(--vscode-panel-border, rgba(128,128,128,.2));
  --surface:  var(--vscode-sideBar-background, rgba(255,255,255,.03));
  --surface2: var(--vscode-input-background, rgba(255,255,255,.06));
  --accent:   var(--vscode-textLink-foreground, #3794ff);
  --green:    #4ec9b0;
  --red:      #f14c4c;
  --orange:   #cca700;
  --radius:   10px;
  --radius-sm: 6px;
  --shadow:   0 1px 3px rgba(0,0,0,.12), 0 1px 2px rgba(0,0,0,.08);
  --shadow-lg: 0 4px 16px rgba(0,0,0,.15);
  --transition: .2s cubic-bezier(.4,0,.2,1);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: var(--vscode-font-family, -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif);
  font-size: 13px;
  color: var(--fg);
  background: var(--bg);
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}

/* ===== Layout ===== */
.container { max-width: 960px; margin: 0 auto; padding: 24px 20px; }

/* ===== Header ===== */
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--border);
}
.header-left { display: flex; align-items: center; gap: 12px; }
.logo {
  width: 32px; height: 32px; border-radius: 8px;
  background: linear-gradient(135deg, var(--accent), var(--green));
  display: flex; align-items: center; justify-content: center;
  font-weight: 700; font-size: 16px; color: #fff;
  flex-shrink: 0;
}
.header-title { font-size: 18px; font-weight: 600; letter-spacing: -.01em; }
.header-scope {
  font-size: 11px; color: var(--fg-muted); font-weight: 500;
  background: var(--surface2); padding: 2px 8px; border-radius: 99px;
  margin-left: 4px;
}
.header-right { display: flex; align-items: center; gap: 10px; }
.updated-text { font-size: 11px; color: var(--fg-muted); }
.refresh-btn {
  display: flex; align-items: center; gap: 4px;
  padding: 5px 12px; border: 1px solid var(--border); border-radius: var(--radius-sm);
  background: transparent; color: var(--fg); cursor: pointer;
  font-size: 12px; font-family: inherit; transition: all var(--transition);
}
.refresh-btn:hover { border-color: var(--accent); color: var(--accent); }
.refresh-btn svg { transition: transform .4s ease; }
.refresh-btn:active svg { transform: rotate(180deg); }

/* ===== Health Banner ===== */
.health-banner {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 12px;
  margin-bottom: 20px;
}
.health-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 16px;
  display: flex;
  align-items: center;
  gap: 12px;
  transition: all var(--transition);
}
.health-card:hover { border-color: var(--accent); box-shadow: var(--shadow); }
.health-beacon {
  position: relative;
  width: 12px; height: 12px;
  border-radius: 50%;
  flex-shrink: 0;
}
.health-beacon.ok { background: var(--green); }
.health-beacon.down { background: var(--red); }
.health-beacon::after {
  content: '';
  position: absolute;
  inset: -3px;
  border-radius: 50%;
  border: 2px solid transparent;
  animation: none;
}
.health-beacon.ok::after {
  border-color: var(--green);
  opacity: .3;
  animation: pulse 2s ease-in-out infinite;
}
.health-beacon.down::after {
  border-color: var(--red);
  opacity: .4;
  animation: pulse 1.5s ease-in-out infinite;
}
@keyframes pulse {
  0%, 100% { transform: scale(1); opacity: .3; }
  50% { transform: scale(1.5); opacity: 0; }
}
.health-info { flex: 1; min-width: 0; }
.health-label { font-size: 11px; color: var(--fg-muted); text-transform: uppercase; letter-spacing: .05em; font-weight: 600; }
.health-value { font-size: 14px; font-weight: 600; margin-top: 1px; }
.health-meta { font-size: 11px; color: var(--fg-muted); font-variant-numeric: tabular-nums; }

/* ===== Section ===== */
.section { margin-bottom: 20px; }
.section-title {
  font-size: 11px; text-transform: uppercase; letter-spacing: .06em;
  color: var(--fg-muted); font-weight: 600; margin-bottom: 10px;
  display: flex; align-items: center; gap: 6px;
}
.section-title svg { opacity: .5; }

/* ===== Card ===== */
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
  transition: border-color var(--transition);
}
.card:hover { border-color: color-mix(in srgb, var(--accent) 40%, transparent); }

/* ===== Services ===== */
.svc-row {
  display: flex;
  align-items: center;
  padding: 12px 16px;
  border-bottom: 1px solid var(--border);
  transition: background var(--transition);
}
.svc-row:last-child { border-bottom: none; }
.svc-row:hover { background: var(--surface2); }
.svc-icon { width: 32px; height: 32px; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 15px; flex-shrink: 0; margin-right: 12px; }
.svc-icon.coding-llm { background: rgba(78, 201, 176, .12); color: var(--green); }
.svc-icon.ollama { background: rgba(55, 148, 255, .12); color: var(--accent); }
.svc-icon.surrealdb { background: rgba(204, 167, 0, .12); color: var(--orange); }
.svc-info { flex: 1; min-width: 0; }
.svc-name { font-weight: 600; font-size: 13px; }
.svc-desc { font-size: 11px; color: var(--fg-muted); margin-top: 1px; }
.svc-right { display: flex; align-items: center; gap: 10px; }
.svc-badge {
  font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: .04em;
  padding: 2px 8px; border-radius: 99px;
}
.svc-badge.on { background: rgba(78, 201, 176, .12); color: var(--green); }
.svc-badge.off { background: var(--surface2); color: var(--fg-muted); }

/* Toggle Switch */
.toggle {
  position: relative;
  width: 36px; height: 20px;
  background: var(--surface2);
  border: 1px solid var(--border);
  border-radius: 99px;
  cursor: pointer;
  transition: all var(--transition);
  flex-shrink: 0;
}
.toggle.on { background: var(--green); border-color: var(--green); }
.toggle::after {
  content: '';
  position: absolute;
  top: 2px; left: 2px;
  width: 14px; height: 14px;
  background: #fff;
  border-radius: 50%;
  transition: transform var(--transition);
  box-shadow: 0 1px 3px rgba(0,0,0,.2);
}
.toggle.on::after { transform: translateX(16px); }
.toggle:hover { border-color: var(--accent); }

/* ===== Info Grid ===== */
.info-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.info-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 16px;
  transition: border-color var(--transition);
}
.info-card:hover { border-color: color-mix(in srgb, var(--accent) 40%, transparent); }
.info-card h3 {
  font-size: 11px; text-transform: uppercase; letter-spacing: .05em;
  color: var(--fg-muted); font-weight: 600; margin-bottom: 10px;
}
.info-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 5px 0;
  border-bottom: 1px solid rgba(128,128,128,.08);
  font-size: 12px;
}
.info-row:last-child { border-bottom: none; }
.info-label { color: var(--fg-muted); }
.info-value { font-weight: 500; font-variant-numeric: tabular-nums; text-align: right; word-break: break-all; }

/* ===== Repos ===== */
.repo-card {
  padding: 14px 16px;
  border-bottom: 1px solid var(--border);
  transition: background var(--transition);
}
.repo-card:last-child { border-bottom: none; }
.repo-card:hover { background: var(--surface2); }
.repo-header { display: flex; align-items: center; gap: 8px; }
.repo-name { font-weight: 600; }
.repo-badge {
  font-size: 10px; font-weight: 600; padding: 1px 7px; border-radius: 99px;
  background: rgba(78, 201, 176, .12); color: var(--green);
}
.repo-ns {
  font-size: 10px; padding: 1px 7px; border-radius: 99px;
  background: rgba(55, 148, 255, .1); color: var(--accent); font-weight: 500;
}
.repo-meta { font-size: 11px; color: var(--fg-muted); margin-top: 4px; }
.repo-meta a { color: var(--accent); text-decoration: none; }
.repo-meta a:hover { text-decoration: underline; }

/* ===== Quick Actions ===== */
.actions-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 8px;
}
.action-btn {
  display: flex; align-items: center; gap: 8px;
  padding: 10px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--fg);
  font-size: 12px; font-family: inherit; font-weight: 500;
  cursor: pointer;
  transition: all var(--transition);
}
.action-btn:hover {
  border-color: var(--accent);
  color: var(--accent);
  background: rgba(55, 148, 255, .06);
  box-shadow: var(--shadow);
  transform: translateY(-1px);
}
.action-btn:active { transform: translateY(0); }
.action-btn svg { opacity: .6; flex-shrink: 0; }
.action-btn:hover svg { opacity: 1; }

/* ===== Toast ===== */
.toast-container {
  position: fixed; bottom: 20px; right: 20px;
  display: flex; flex-direction: column; gap: 8px;
  z-index: 999; pointer-events: none;
}
.toast {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 10px 16px;
  font-size: 12px;
  box-shadow: var(--shadow-lg);
  animation: toastIn .3s ease, toastOut .3s ease 2.7s forwards;
  pointer-events: auto;
}
@keyframes toastIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
@keyframes toastOut { from { opacity: 1; } to { opacity: 0; transform: translateY(-5px); } }

/* ===== Skeleton ===== */
.skeleton {
  background: linear-gradient(90deg, var(--surface2) 25%, var(--surface) 50%, var(--surface2) 75%);
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
  border-radius: 4px;
  height: 14px;
  width: 80%;
}
@keyframes shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }

/* ===== Log ===== */
.log-area {
  font-family: var(--vscode-editor-font-family, 'Cascadia Code', 'Fira Code', monospace);
  font-size: 11px;
  line-height: 1.6;
  color: var(--fg-muted);
  padding: 12px 16px;
  max-height: 160px;
  overflow-y: auto;
  white-space: pre-wrap;
  word-break: break-all;
}

/* ===== Responsive ===== */
@media (max-width: 600px) {
  .info-grid { grid-template-columns: 1fr; }
  .health-banner { grid-template-columns: 1fr; }
  .actions-grid { grid-template-columns: 1fr 1fr; }
}
</style>
</head>
<body>

<div class="container">

  <!-- Header -->
  <div class="header">
    <div class="header-left">
      <div class="logo">C</div>
      <div>
        <div class="header-title" id="headerTitle">Corvia</div>
      </div>
      <span class="header-scope" id="headerScope">loading</span>
    </div>
    <div class="header-right">
      <span class="updated-text" id="lastUpdated"></span>
      <button class="refresh-btn" onclick="refresh()">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M13.5 2.5a.5.5 0 0 0-1 0v2.05A6.48 6.48 0 0 0 8 2.5a6.5 6.5 0 1 0 6.5 6.5.5.5 0 0 0-1 0A5.5 5.5 0 1 1 8 3.5a5.48 5.48 0 0 1 3.94 1.66h-1.94a.5.5 0 0 0 0 1h3a.5.5 0 0 0 .5-.5v-3.16z"/></svg>
        Refresh
      </button>
    </div>
  </div>

  <!-- Health Banner -->
  <div class="health-banner" id="healthBanner">
    <div class="health-card">
      <div class="health-beacon" id="serverBeacon"></div>
      <div class="health-info">
        <div class="health-label">API Server</div>
        <div class="health-value" id="serverStatus"><div class="skeleton"></div></div>
        <div class="health-meta" id="serverMeta">port 8020</div>
      </div>
    </div>
    <div class="health-card">
      <div class="health-beacon" id="inferenceBeacon"></div>
      <div class="health-info">
        <div class="health-label">Inference</div>
        <div class="health-value" id="inferenceStatus"><div class="skeleton"></div></div>
        <div class="health-meta" id="inferenceMeta">port 8030</div>
      </div>
    </div>
  </div>

  <!-- Services -->
  <div class="section">
    <div class="section-title">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M2.5 4a.5.5 0 0 1 .5-.5h10a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5V4zm0 3.5a.5.5 0 0 1 .5-.5h10a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5v-1zm0 3.5a.5.5 0 0 1 .5-.5h10a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5v-1z"/></svg>
      Services
    </div>
    <div class="card" id="servicesCard">
      <div class="svc-row"><div class="skeleton" style="width:60%"></div></div>
      <div class="svc-row"><div class="skeleton" style="width:50%"></div></div>
      <div class="svc-row"><div class="skeleton" style="width:55%"></div></div>
    </div>
  </div>

  <!-- Info Grid -->
  <div class="section">
    <div class="info-grid">
      <div class="info-card" id="workspaceCard">
        <h3>Workspace</h3>
        <div class="skeleton" style="margin-bottom:8px"></div>
        <div class="skeleton" style="width:60%"></div>
      </div>
      <div class="info-card" id="agentsCard">
        <h3>Agents</h3>
        <div class="skeleton" style="width:70%"></div>
      </div>
    </div>
  </div>

  <!-- Repos -->
  <div class="section">
    <div class="section-title">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 1 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 0 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5v-9zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8V1.5z"/></svg>
      Repositories
    </div>
    <div class="card" id="reposCard">
      <div class="repo-card"><div class="skeleton" style="width:40%"></div></div>
    </div>
  </div>

  <!-- Quick Actions -->
  <div class="section">
    <div class="section-title">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M11.251.068a.5.5 0 0 1 .227.58L9.677 6.5H13a.5.5 0 0 1 .364.843l-8 8.5a.5.5 0 0 1-.842-.49L6.323 9.5H3a.5.5 0 0 1-.364-.843l8-8.5a.5.5 0 0 1 .615-.089z"/></svg>
      Quick Actions
    </div>
    <div class="actions-grid">
      <button class="action-btn" onclick="runCmd('corvia workspace status')">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 16A8 8 0 1 0 8 0a8 8 0 0 0 0 16zm.93-9.412l-1 4.705c-.07.34.029.533.304.533.194 0 .487-.07.686-.246l-.088.416c-.287.346-.92.598-1.465.598-.703 0-1.002-.422-.808-1.319l.738-3.468c.064-.293.006-.399-.287-.399l-.298-.004.088-.416h2.13zM8 5.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2z"/></svg>
        Status
      </button>
      <button class="action-btn" onclick="runCmd('corvia workspace ingest')">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M.5 9.9a.5.5 0 0 1 .5.5v2.5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-2.5a.5.5 0 0 1 1 0v2.5a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2v-2.5a.5.5 0 0 1 .5-.5z"/><path d="M7.646 1.146a.5.5 0 0 1 .708 0l3 3a.5.5 0 0 1-.708.708L8.5 2.707V11.5a.5.5 0 0 1-1 0V2.707L5.354 4.854a.5.5 0 1 1-.708-.708l3-3z"/></svg>
        Ingest All
      </button>
      <button class="action-btn" onclick="runCmd('corvia workspace ingest --fresh')">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2v1z"/><path d="M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466z"/></svg>
        Fresh Ingest
      </button>
      <button class="action-btn" onclick="runCmd('corvia reason')">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 15A7 7 0 1 1 8 1a7 7 0 0 1 0 14zm0 1A8 8 0 1 0 8 0a8 8 0 0 0 0 16z"/><path d="M5.255 5.786a.237.237 0 0 0 .241.247h.825c.138 0 .248-.113.266-.25.09-.656.54-1.134 1.342-1.134.686 0 1.314.343 1.314 1.168 0 .635-.374.927-.965 1.371-.673.489-1.206 1.06-1.168 1.987l.003.217a.25.25 0 0 0 .25.246h.811a.25.25 0 0 0 .25-.25v-.105c0-.718.273-.927 1.01-1.486.609-.463 1.244-.977 1.244-2.056 0-1.511-1.276-2.241-2.673-2.241-1.267 0-2.655.59-2.75 2.286zm1.557 5.763c0 .533.425.927 1.01.927.609 0 1.028-.394 1.028-.927 0-.552-.42-.94-1.029-.94-.584 0-1.009.388-1.009.94z"/></svg>
        Reasoning
      </button>
      <button class="action-btn" onclick="runCmd('corvia agent list')">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M7 14s-1 0-1-1 1-4 5-4 5 3 5 4-1 1-1 1H7zm4-6a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"/><path fill-rule="evenodd" d="M5.216 14A2.238 2.238 0 0 1 5 13c0-1.355.68-2.75 1.936-3.72A6.325 6.325 0 0 0 5 9c-4 0-5 3-5 4s1 1 1 1h4.216z"/><path d="M4.5 8a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/></svg>
        Agents
      </button>
      <button class="action-btn" onclick="runCmd('corvia-workspace rebuild')">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M1 0L0 1l2.313 9.014L.706 11.42a.5.5 0 0 0 0 .708l3.172 3.17a.5.5 0 0 0 .708 0l1.406-1.406L15 16l1-1-6.313-9.014 1.406-1.406a.5.5 0 0 0 0-.708L7.92.7a.5.5 0 0 0-.708 0L5.808 2.106 1 0z"/></svg>
        Rebuild
      </button>
    </div>
  </div>

  <!-- Supervisor Log -->
  <div class="section">
    <div class="section-title">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M5 4a.5.5 0 0 0 0 1h6a.5.5 0 0 0 0-1H5zm-.5 2.5A.5.5 0 0 1 5 6h6a.5.5 0 0 1 0 1H5a.5.5 0 0 1-.5-.5zM5 8a.5.5 0 0 0 0 1h6a.5.5 0 0 0 0-1H5zm0 2a.5.5 0 0 0 0 1h3a.5.5 0 0 0 0-1H5z"/><path d="M2 2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2zm10-1H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V2a1 1 0 0 0-1-1z"/></svg>
      Supervisor Log
    </div>
    <div class="card">
      <div class="log-area" id="logArea">Loading...</div>
    </div>
  </div>

</div>

<!-- Toast Container -->
<div class="toast-container" id="toasts"></div>

<script>
const vscode = acquireVsCodeApi();

const SVC_META = {
  'coding-llm':  { icon: '🤖', desc: 'Local coding LLM via Ollama + Continue' },
  'ollama':      { icon: '🦙', desc: 'Ollama inference server for embeddings' },
  'surrealdb':   { icon: '🗄️', desc: 'SurrealDB storage backend (Docker)' },
};

function refresh() {
  toast('Refreshing...');
  vscode.postMessage({ type: 'refresh' });
}

function toggle(svc, enable) {
  toast((enable ? 'Enabling ' : 'Disabling ') + svc + '...');
  vscode.postMessage({ type: 'toggle', service: svc, enable: enable });
}

function runCmd(cmd) {
  toast('Running: ' + cmd);
  vscode.postMessage({ type: 'command', cmd: cmd });
}

function toast(msg) {
  const container = document.getElementById('toasts');
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = msg;
  container.appendChild(el);
  setTimeout(function() { el.remove(); }, 3000);
}

function render(data) {
  // Header
  var ws = data.workspace;
  if (ws) {
    document.getElementById('headerTitle').textContent = ws.name || 'Corvia';
    document.getElementById('headerScope').textContent = 'scope: ' + (ws.scope || '—');
  }
  document.getElementById('lastUpdated').textContent = 'Updated ' + new Date().toLocaleTimeString();

  // Health
  var sb = document.getElementById('serverBeacon');
  sb.className = 'health-beacon ' + (data.server.healthy ? 'ok' : 'down');
  document.getElementById('serverStatus').textContent = data.server.healthy ? 'Healthy' : 'Unreachable';
  document.getElementById('serverMeta').textContent = data.server.healthy
    ? 'port 8020 · ' + data.server.latency + 'ms'
    : 'port 8020 · no response';

  var ib = document.getElementById('inferenceBeacon');
  ib.className = 'health-beacon ' + (data.inference.healthy ? 'ok' : 'down');
  document.getElementById('inferenceStatus').textContent = data.inference.healthy ? 'Healthy' : 'Unreachable';
  document.getElementById('inferenceMeta').textContent = data.inference.healthy
    ? 'port 8030 · ' + data.inference.latency + 'ms'
    : 'port 8030 · no response';

  // Services
  var svcsHtml = '';
  var svcs = Object.keys(data.services);
  for (var i = 0; i < svcs.length; i++) {
    var svc = svcs[i];
    var s = data.services[svc];
    var meta = SVC_META[svc] || { icon: '⚙️', desc: svc };
    var badgeClass = s.enabled ? 'on' : 'off';
    var badgeText = s.enabled ? (s.running ? 'running' : 'enabled') : 'disabled';
    var toggleClass = s.enabled ? 'on' : '';
    svcsHtml += '<div class="svc-row">' +
      '<div class="svc-icon ' + svc + '">' + meta.icon + '</div>' +
      '<div class="svc-info"><div class="svc-name">' + svc + '</div>' +
      '<div class="svc-desc">' + meta.desc + '</div></div>' +
      '<div class="svc-right">' +
      '<span class="svc-badge ' + badgeClass + '">' + badgeText + '</span>' +
      '<div class="toggle ' + toggleClass + '" onclick="toggle(\'' + svc + '\', ' + !s.enabled + ')"></div>' +
      '</div></div>';
  }
  document.getElementById('servicesCard').innerHTML = svcsHtml;

  // Workspace
  if (ws) {
    document.getElementById('workspaceCard').innerHTML =
      '<h3>Workspace</h3>' +
      infoRow('Name', ws.name) +
      infoRow('Scope', ws.scope) +
      infoRow('Store', ws.store) +
      infoRow('Embedding', ws.embedding);
  }

  // Agents
  document.getElementById('agentsCard').innerHTML =
    '<h3>Agents</h3>' +
    '<div style="font-size:12px;color:var(--fg-muted);padding:4px 0">' +
    escHtml(data.agents) + '</div>';

  // Repos
  if (ws && ws.repos && ws.repos.length) {
    var reposHtml = '';
    for (var j = 0; j < ws.repos.length; j++) {
      var r = ws.repos[j];
      reposHtml += '<div class="repo-card">' +
        '<div class="repo-header">' +
        '<span class="repo-name">' + escHtml(r.name) + '</span>' +
        '<span class="repo-badge">' + escHtml(r.status) + '</span>' +
        '<span class="repo-ns">' + escHtml(r.namespace) + '</span>' +
        '</div>' +
        '<div class="repo-meta">' +
        (r.url ? '<a href="' + escHtml(r.url) + '">' + escHtml(r.url) + '</a>' : '') +
        (r.path ? '<br>' + escHtml(r.path) : '') +
        '</div></div>';
    }
    document.getElementById('reposCard').innerHTML = reposHtml;
  }

  // Log
  document.getElementById('logArea').textContent = data.supervisorLog || 'No log data.';
}

function infoRow(label, value) {
  return '<div class="info-row"><span class="info-label">' + escHtml(label) +
    '</span><span class="info-value">' + escHtml(value || '—') + '</span></div>';
}

function escHtml(s) {
  if (!s) return '';
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

window.addEventListener('message', function(event) {
  if (event.data.type === 'update') render(event.data.data);
});
</script>

</body>
</html>`;
}

// --- Quick Pick ---

async function showServiceMenu() {
    const status = await run("corvia-workspace status");
    const services = parseServiceStatus(status);
    const items = SERVICES.map((svc) => {
        const s = services[svc];
        return {
            label: `${s.enabled ? "$(check)" : "$(circle-outline)"} ${svc}`,
            description: s.enabled ? (s.running ? "running" : "enabled") : "disabled",
            service: svc,
            enabled: s.enabled,
        };
    });
    items.push(
        { label: "", kind: vscode.QuickPickItemKind.Separator },
        { label: "$(refresh) Refresh", service: "__refresh", enabled: false },
        { label: "$(dashboard) Dashboard", service: "__dashboard", enabled: false }
    );
    const picked = await vscode.window.showQuickPick(items, { placeHolder: "Toggle a service" });
    if (!picked) return;
    if (picked.service === "__refresh") refreshStatus();
    else if (picked.service === "__dashboard") vscode.commands.executeCommand("corvia.openDashboard");
    else {
        const action = picked.enabled ? "disable" : "enable";
        const terminal = vscode.window.createTerminal({ name: `Corvia: ${action} ${picked.service}` });
        terminal.show();
        terminal.sendText(`corvia-workspace ${action} ${picked.service}`);
        setTimeout(refreshStatus, 8000);
    }
}

function deactivate() {}

module.exports = { activate, deactivate };
