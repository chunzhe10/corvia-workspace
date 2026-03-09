const vscode = require("vscode");
const { exec } = require("child_process");

let statusBarItem;
let panel;
let pollTimer;

const POLL_INTERVAL = 3000;

function activate(context) {
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 50);
    statusBarItem.command = "corvia.openDashboard";
    statusBarItem.text = "$(loading~spin) Corvia";
    statusBarItem.show();
    context.subscriptions.push(statusBarItem);

    context.subscriptions.push(
        vscode.commands.registerCommand("corvia.openDashboard", () => openDashboard(context))
    );

    refresh();
    pollTimer = setInterval(refresh, POLL_INTERVAL);
    context.subscriptions.push({ dispose: () => clearInterval(pollTimer) });
}

function run(cmd) {
    return new Promise((resolve) => {
        exec(cmd, { timeout: 8000 }, (err, stdout) => {
            resolve(err ? null : stdout);
        });
    });
}

async function refresh() {
    const raw = await run("corvia-dev status --json");
    if (!raw) {
        statusBarItem.text = "$(error) Corvia";
        statusBarItem.backgroundColor = new vscode.ThemeColor("statusBarItem.errorBackground");
        statusBarItem.tooltip = "corvia-dev not responding";
        if (panel) panel.webview.postMessage({ type: "status", data: null });
        return;
    }

    let data;
    try {
        data = JSON.parse(raw);
    } catch {
        statusBarItem.text = "$(error) Corvia";
        return;
    }

    const tier0 = (data.services || []).filter(
        (s) => ["corvia-inference", "corvia-server"].includes(s.name)
    );
    const allHealthy = tier0.every((s) => s.state === "healthy");
    const anyDown = tier0.some((s) => s.state !== "healthy");

    if (allHealthy) {
        statusBarItem.text = "$(check) Corvia";
        statusBarItem.backgroundColor = undefined;
    } else if (anyDown) {
        statusBarItem.text = "$(error) Corvia";
        statusBarItem.backgroundColor = new vscode.ThemeColor("statusBarItem.errorBackground");
    } else {
        statusBarItem.text = "$(warning) Corvia";
        statusBarItem.backgroundColor = new vscode.ThemeColor("statusBarItem.warningBackground");
    }

    const svcSummary = (data.services || [])
        .map((s) => `${s.name}: ${s.state}`)
        .join(" | ");
    statusBarItem.tooltip = svcSummary;

    if (panel) {
        panel.webview.postMessage({ type: "status", data });
    }
}

function openDashboard(context) {
    if (panel) {
        panel.reveal();
        return;
    }

    panel = vscode.window.createWebviewPanel(
        "corviaDashboard",
        "Corvia Dashboard",
        vscode.ViewColumn.One,
        { enableScripts: true, retainContextWhenHidden: true }
    );

    panel.webview.html = getDashboardHtml();

    panel.webview.onDidReceiveMessage((msg) => {
        if (msg.type === "command") {
            const terminal = vscode.window.createTerminal("corvia-dev");
            terminal.show();
            terminal.sendText(msg.command);
        } else if (msg.type === "refresh") {
            refresh();
        }
    });

    panel.onDidDispose(() => { panel = undefined; });
    refresh();
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
  --purple:   #c586c0;
  --radius:   10px;
  --radius-sm: 6px;
  --shadow:   0 1px 3px rgba(0,0,0,.12), 0 1px 2px rgba(0,0,0,.08);
  --shadow-lg: 0 4px 16px rgba(0,0,0,.15);
  --transition: .2s cubic-bezier(.4,0,.2,1);
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: var(--vscode-font-family, -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif);
  font-size: 13px; color: var(--fg); background: var(--bg);
  line-height: 1.5; -webkit-font-smoothing: antialiased;
}

/* ===== Layout ===== */
.container { max-width: 960px; margin: 0 auto; padding: 24px 20px; }

/* ===== Header ===== */
.header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--border);
}
.header-left { display: flex; align-items: center; gap: 12px; }
.logo {
  width: 32px; height: 32px; border-radius: 8px;
  background: linear-gradient(135deg, var(--accent), var(--green));
  display: flex; align-items: center; justify-content: center;
  font-weight: 700; font-size: 16px; color: #fff; flex-shrink: 0;
}
.header-title { font-size: 18px; font-weight: 600; letter-spacing: -.01em; }
.header-scope {
  font-size: 11px; color: var(--fg-muted); font-weight: 500;
  background: var(--surface2); padding: 2px 8px; border-radius: 99px;
}
.header-right { display: flex; align-items: center; gap: 8px; }
.updated-text { font-size: 11px; color: var(--fg-muted); }

/* ===== Inline Buttons (used everywhere) ===== */
.ibtn {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 4px 10px; border: 1px solid var(--border); border-radius: var(--radius-sm);
  background: transparent; color: var(--fg-muted); cursor: pointer;
  font-size: 11px; font-family: inherit; font-weight: 500;
  transition: all var(--transition); white-space: nowrap;
}
.ibtn:hover { border-color: var(--accent); color: var(--accent); background: rgba(55,148,255,.06); }
.ibtn:active { transform: scale(.97); }
.ibtn svg { width: 12px; height: 12px; }
.ibtn.danger:hover { border-color: var(--red); color: var(--red); background: rgba(241,76,76,.06); }
.ibtn.primary {
  border-color: var(--accent); color: var(--accent); background: rgba(55,148,255,.08);
}
.ibtn.primary:hover { background: rgba(55,148,255,.15); }

/* ===== Health Banner ===== */
.health-banner {
  display: grid; grid-template-columns: 1fr 1fr;
  gap: 12px; margin-bottom: 20px;
}
.health-card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 16px;
  display: flex; align-items: flex-start; gap: 12px;
  transition: all var(--transition);
}
.health-card:hover { border-color: color-mix(in srgb, var(--accent) 40%, transparent); box-shadow: var(--shadow); }
.health-beacon {
  position: relative; width: 12px; height: 12px;
  border-radius: 50%; flex-shrink: 0; margin-top: 3px;
}
.health-beacon.ok { background: var(--green); }
.health-beacon.down { background: var(--red); }
.health-beacon.warn { background: var(--orange); }
.health-beacon::after {
  content: ''; position: absolute; inset: -3px; border-radius: 50%;
  border: 2px solid transparent;
}
.health-beacon.ok::after {
  border-color: var(--green); opacity: .3; animation: pulse 2s ease-in-out infinite;
}
.health-beacon.down::after {
  border-color: var(--red); opacity: .4; animation: pulse 1.5s ease-in-out infinite;
}
.health-beacon.warn::after {
  border-color: var(--orange); opacity: .35; animation: pulse 1.8s ease-in-out infinite;
}
@keyframes pulse {
  0%, 100% { transform: scale(1); opacity: .3; }
  50% { transform: scale(1.5); opacity: 0; }
}
.health-body { flex: 1; min-width: 0; }
.health-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.health-label {
  font-size: 11px; color: var(--fg-muted); text-transform: uppercase;
  letter-spacing: .05em; font-weight: 600;
}
.health-value { font-size: 14px; font-weight: 600; margin-top: 2px; }
.health-meta { font-size: 11px; color: var(--fg-muted); font-variant-numeric: tabular-nums; margin-top: 2px; }

/* ===== Two-Column Middle ===== */
.mid-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 20px; }

/* ===== Section ===== */
.section { margin-bottom: 20px; }
.section-header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 10px;
}
.section-title {
  font-size: 11px; text-transform: uppercase; letter-spacing: .06em;
  color: var(--fg-muted); font-weight: 600;
  display: flex; align-items: center; gap: 6px;
}
.section-title svg { opacity: .5; }

/* ===== Card ===== */
.card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: var(--radius); overflow: hidden;
  transition: border-color var(--transition);
}
.card:hover { border-color: color-mix(in srgb, var(--accent) 40%, transparent); }

/* ===== Services ===== */
.svc-row {
  display: flex; align-items: center; padding: 10px 14px;
  border-bottom: 1px solid var(--border); transition: background var(--transition);
}
.svc-row:last-child { border-bottom: none; }
.svc-row:hover { background: var(--surface2); }
.svc-icon {
  width: 30px; height: 30px; border-radius: 7px;
  display: flex; align-items: center; justify-content: center;
  font-size: 13px; font-weight: 700; flex-shrink: 0; margin-right: 10px;
}
.svc-icon.tier-0 { background: rgba(78, 201, 176, .12); color: var(--green); }
.svc-icon.tier-1 { background: rgba(55, 148, 255, .12); color: var(--accent); }
.svc-icon.tier-2 { background: rgba(197, 134, 192, .12); color: var(--purple); }
.svc-info { flex: 1; min-width: 0; }
.svc-name { font-weight: 600; font-size: 12px; }
.svc-desc { font-size: 10px; color: var(--fg-muted); margin-top: 1px; }
.svc-right { display: flex; align-items: center; gap: 8px; }
.svc-badge {
  font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: .04em;
  padding: 2px 8px; border-radius: 99px;
}
.svc-badge.healthy { background: rgba(78, 201, 176, .12); color: var(--green); }
.svc-badge.starting { background: rgba(204, 167, 0, .12); color: var(--orange); }
.svc-badge.unhealthy, .svc-badge.crashed { background: rgba(241, 76, 76, .12); color: var(--red); }
.svc-badge.stopped { background: var(--surface2); color: var(--fg-muted); }

/* ===== Toggle Switch ===== */
.toggle {
  position: relative; width: 34px; height: 18px;
  background: var(--surface2); border: 1px solid var(--border);
  border-radius: 99px; cursor: pointer; transition: all var(--transition); flex-shrink: 0;
}
.toggle.on { background: var(--green); border-color: var(--green); }
.toggle::after {
  content: ''; position: absolute; top: 2px; left: 2px;
  width: 12px; height: 12px; background: #fff; border-radius: 50%;
  transition: transform var(--transition); box-shadow: 0 1px 3px rgba(0,0,0,.2);
}
.toggle.on::after { transform: translateX(16px); }
.toggle:hover { border-color: var(--accent); }

/* ===== Config Card ===== */
.cfg-section { padding: 14px; border-bottom: 1px solid var(--border); }
.cfg-section:last-child { border-bottom: none; }
.cfg-section h3 {
  font-size: 10px; text-transform: uppercase; letter-spacing: .05em;
  color: var(--fg-muted); font-weight: 600; margin-bottom: 8px;
}
.cfg-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 4px 0; font-size: 12px;
}
.cfg-label { color: var(--fg-muted); }
.cfg-value { font-weight: 500; display: flex; align-items: center; gap: 6px; }
.cfg-active {
  font-size: 10px; font-weight: 600; padding: 1px 6px; border-radius: 99px;
  background: rgba(78,201,176,.12); color: var(--green);
}
.provider-btns { display: flex; gap: 4px; margin-top: 8px; }

/* ===== Log Panel ===== */
.log-panel {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: var(--radius); overflow: hidden;
}
.log-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 14px; border-bottom: 1px solid var(--border);
  cursor: pointer; user-select: none; transition: background var(--transition);
}
.log-header:hover { background: var(--surface2); }
.log-header-left { display: flex; align-items: center; gap: 6px; }
.log-header-left span {
  font-size: 11px; text-transform: uppercase; letter-spacing: .06em;
  color: var(--fg-muted); font-weight: 600;
}
.log-header-left svg { opacity: .5; }
.log-chevron {
  transition: transform var(--transition); color: var(--fg-muted);
}
.log-chevron.open { transform: rotate(180deg); }
.log-body {
  max-height: 0; overflow: hidden; transition: max-height .3s ease;
}
.log-body.open { max-height: 500px; overflow: visible; }
.log-tabs {
  display: flex; gap: 0; border-bottom: 1px solid var(--border);
  padding: 0 14px; overflow-x: auto;
}
.log-tab {
  padding: 7px 14px; font-size: 11px; font-weight: 500; font-family: inherit;
  color: var(--fg-muted); background: none; border: none;
  border-bottom: 2px solid transparent; cursor: pointer;
  transition: all var(--transition); white-space: nowrap;
}
.log-tab:hover { color: var(--fg); }
.log-tab.active { color: var(--accent); border-bottom-color: var(--accent); font-weight: 600; }
.log-tab .tab-count {
  font-size: 9px; font-weight: 600; padding: 0 5px; border-radius: 99px;
  background: var(--surface2); color: var(--fg-muted); margin-left: 4px;
}
.log-area {
  font-family: var(--vscode-editor-font-family, 'Cascadia Code', 'Fira Code', monospace);
  font-size: 11px; line-height: 1.7; color: var(--fg-muted);
  padding: 12px 14px; max-height: 260px; overflow-y: auto;
  white-space: pre-wrap; word-break: break-all;
}
.log-empty {
  padding: 24px 14px; text-align: center;
  font-size: 12px; color: var(--fg-muted); opacity: .6;
}

/* ===== Skeleton ===== */
.skeleton {
  background: linear-gradient(90deg, var(--surface2) 25%, var(--surface) 50%, var(--surface2) 75%);
  background-size: 200% 100%; animation: shimmer 1.5s infinite;
  border-radius: 4px; height: 14px; width: 80%;
}
@keyframes shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }

/* ===== Offline Banner ===== */
.offline-banner { text-align: center; padding: 60px 20px; }
.offline-icon {
  width: 48px; height: 48px; border-radius: 50%; margin: 0 auto 16px;
  background: rgba(241,76,76,.1); display: flex; align-items: center; justify-content: center;
}
.offline-icon svg { color: var(--red); }
.offline-banner .title { font-size: 16px; font-weight: 600; color: var(--fg); margin-bottom: 6px; }
.offline-banner .hint { font-size: 12px; color: var(--fg-muted); margin-bottom: 16px; }
.offline-banner .hint code {
  background: var(--surface2); padding: 2px 6px; border-radius: 3px; font-size: 11px;
}

/* ===== Responsive ===== */
@media (max-width: 640px) {
  .health-banner { grid-template-columns: 1fr; }
  .mid-grid { grid-template-columns: 1fr; }
}
</style>
</head>
<body>

<div class="container">
  <!-- Header -->
  <div class="header">
    <div class="header-left">
      <div class="logo">C</div>
      <div><div class="header-title">Corvia</div></div>
      <span class="header-scope" id="headerScope">loading</span>
    </div>
    <div class="header-right">
      <span class="updated-text" id="lastUpdated"></span>
      <button class="ibtn" data-action="refresh">
        <svg viewBox="0 0 16 16" fill="currentColor"><path d="M13.5 2.5a.5.5 0 0 0-1 0v2.05A6.48 6.48 0 0 0 8 2.5a6.5 6.5 0 1 0 6.5 6.5.5.5 0 0 0-1 0A5.5 5.5 0 1 1 8 3.5a5.48 5.48 0 0 1 3.94 1.66h-1.94a.5.5 0 0 0 0 1h3a.5.5 0 0 0 .5-.5v-3.16z"/></svg>
        Refresh
      </button>
      <button class="ibtn danger" data-cmd="corvia-dev restart">
        <svg viewBox="0 0 16 16" fill="currentColor"><path d="M13.5 2.5a.5.5 0 0 0-1 0v2.05A6.48 6.48 0 0 0 8 2.5a6.5 6.5 0 1 0 6.5 6.5.5.5 0 0 0-1 0A5.5 5.5 0 1 1 8 3.5a5.48 5.48 0 0 1 3.94 1.66h-1.94a.5.5 0 0 0 0 1h3a.5.5 0 0 0 .5-.5v-3.16z"/></svg>
        Restart All
      </button>
    </div>
  </div>

  <!-- Content -->
  <div id="content">
    <div class="health-banner">
      <div class="health-card"><div class="skeleton" style="width:60%"></div></div>
      <div class="health-card"><div class="skeleton" style="width:60%"></div></div>
    </div>
  </div>

  <!-- Logs (persistent, outside #content so it doesn't flash on re-render) -->
  <div class="log-panel" id="logPanel">
    <div class="log-header" id="logToggle">
      <div class="log-header-left">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M2 2a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V2zm1 0v12h10V2H3zm1.5 2h7a.5.5 0 0 1 0 1h-7a.5.5 0 0 1 0-1zm0 2.5h7a.5.5 0 0 1 0 1h-7a.5.5 0 0 1 0-1zm0 2.5h4a.5.5 0 0 1 0 1h-4a.5.5 0 0 1 0-1z"/></svg>
        <span>Logs</span>
      </div>
      <svg class="log-chevron open" id="logChevron" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M4.47 5.97a.75.75 0 0 1 1.06 0L8 8.44l2.47-2.47a.75.75 0 1 1 1.06 1.06l-3 3a.75.75 0 0 1-1.06 0l-3-3a.75.75 0 0 1 0-1.06z"/></svg>
    </div>
    <div class="log-body open" id="logBody">
      <div class="log-tabs" id="logTabs"></div>
      <div id="logContent"><div class="log-empty">No log entries yet</div></div>
    </div>
  </div>

</div>

<script>
const vscode = acquireVsCodeApi();
let logOpen = true;
let activeLogTab = null;  // null = auto-select first, or service name
let lastLogData = {};     // persisted across renders

const SVC_META = {
  'corvia-server':    { icon: 'S', tier: 0, desc: 'REST + MCP API server' },
  'corvia-inference': { icon: 'I', tier: 0, desc: 'ONNX embeddings + chat (gRPC)' },
  'ollama':           { icon: 'O', tier: 1, desc: 'Local LLM runtime' },
  'vllm':             { icon: 'V', tier: 1, desc: 'High-perf LLM serving' },
  'surrealdb':        { icon: 'D', tier: 1, desc: 'SurrealDB storage backend' },
  'postgres':         { icon: 'P', tier: 1, desc: 'PostgreSQL storage backend' },
  'coding-llm':       { icon: 'L', tier: 2, desc: 'Code assistant via Continue' },
};

const PROVIDERS = {
  embedding: [
    { value: 'corvia', label: 'Corvia Inference', cmd: 'corvia-dev use corvia-inference' },
    { value: 'ollama', label: 'Ollama', cmd: 'corvia-dev use ollama' },
  ],
};

function beaconClass(state) {
  if (state === 'healthy') return 'ok';
  if (state === 'starting') return 'warn';
  return 'down';
}

function formatUptime(s) {
  if (!s && s !== 0) return '';
  if (s < 60) return Math.floor(s) + 's';
  if (s < 3600) return Math.floor(s / 60) + 'm';
  return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
}

function esc(str) {
  const d = document.createElement('div');
  d.textContent = str;
  return d.innerHTML;
}

// --- Log panel toggle (survives re-renders) ---
document.getElementById('logToggle').onclick = () => {
  logOpen = !logOpen;
  document.getElementById('logBody').classList.toggle('open', logOpen);
  document.getElementById('logChevron').classList.toggle('open', logOpen);
};

window.addEventListener('message', (e) => {
  if (e.data.type === 'status') render(e.data.data);
});

function render(data) {
  const el = document.getElementById('content');

  if (!data) {
    el.innerHTML =
      '<div class="offline-banner">' +
        '<div class="offline-icon"><svg width="24" height="24" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 13A6 6 0 1 1 8 2a6 6 0 0 1 0 12zm-.5-3h1v1h-1v-1zm0-7h1v5.5h-1V4z"/></svg></div>' +
        '<div class="title">corvia-dev not responding</div>' +
        '<div class="hint">Run <code>corvia-dev up</code> to start services</div>' +
        '<button class="ibtn primary" data-cmd="corvia-dev up" style="margin:0 auto">Start Services</button>' +
      '</div>';
    document.getElementById('headerScope').textContent = 'offline';
    updateLogs([], {});
    bindAll();
    return;
  }

  const svcs = data.services || [];
  const cfg = data.config || {};
  const enabled = new Set(data.enabled_services || []);

  document.getElementById('headerScope').textContent = cfg.workspace || 'corvia';
  document.getElementById('lastUpdated').textContent = new Date().toLocaleTimeString();

  const server = svcs.find(s => s.name === 'corvia-server');
  const inference = svcs.find(s => s.name === 'corvia-inference');
  const optional = svcs.filter(s => !['corvia-server', 'corvia-inference'].includes(s.name));

  let html = '';

  // ---- Health Banner ----
  html += '<div class="health-banner">';
  html += coreCard('API Server', server, 8020, 'corvia-server');
  html += coreCard('Inference', inference, 8030, 'corvia-inference');
  html += '</div>';

  // ---- Two-Column: Services + Config ----
  html += '<div class="mid-grid">';

  // Left: Optional Services
  html += '<div class="section" style="margin-bottom:0">' +
    '<div class="section-header"><div class="section-title">' +
      '<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M2.5 4a.5.5 0 0 1 .5-.5h10a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5V4zm0 3.5a.5.5 0 0 1 .5-.5h10a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5v-1zm0 3.5a.5.5 0 0 1 .5-.5h10a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5v-1z"/></svg>' +
      'Optional Services</div></div>' +
    '<div class="card">';
  if (optional.length === 0) {
    html += '<div style="padding:20px 14px;text-align:center;color:var(--fg-muted);font-size:12px;opacity:.6">' +
      'No optional services configured</div>';
  } else {
    for (const svc of optional) {
      const meta = SVC_META[svc.name] || { icon: '?', tier: 1, desc: '' };
      const isEnabled = enabled.has(svc.name);
      html += '<div class="svc-row">' +
        '<div class="svc-icon tier-' + meta.tier + '">' + meta.icon + '</div>' +
        '<div class="svc-info">' +
          '<div class="svc-name">' + esc(svc.name) + '</div>' +
          '<div class="svc-desc">' + esc(meta.desc) + '</div>' +
        '</div>' +
        '<div class="svc-right">' +
          '<span class="svc-badge ' + svc.state + '">' + svc.state + '</span>' +
          '<div class="toggle ' + (isEnabled ? 'on' : '') + '" data-toggle="' + esc(svc.name) + '" data-enabled="' + (isEnabled ? '1' : '0') + '"></div>' +
        '</div></div>';
    }
  }
  html += '</div></div>';

  // Right: Configuration
  html += '<div class="section" style="margin-bottom:0">' +
    '<div class="section-header"><div class="section-title">' +
      '<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M7.071 2.535a1 1 0 0 1 1.858 0l.638 1.593a1 1 0 0 0 .752.602l1.718.296a1 1 0 0 1 .574 1.665l-1.19 1.248a1 1 0 0 0-.266.816l.203 1.735a1 1 0 0 1-1.42 1.03l-1.585-.752a1 1 0 0 0-.862 0l-1.585.752a1 1 0 0 1-1.42-1.03l.203-1.735a1 1 0 0 0-.266-.816L2.233 6.69a1 1 0 0 1 .574-1.665l1.718-.296a1 1 0 0 0 .752-.602l.638-1.593z"/></svg>' +
      'Configuration</div></div>' +
    '<div class="card">';

  // Embedding provider section with switcher
  html += '<div class="cfg-section"><h3>Embedding Provider</h3>' +
    '<div class="cfg-row"><span class="cfg-label">Active</span>' +
      '<span class="cfg-value"><span class="cfg-active">' + esc(cfg.embedding_provider || '-') + '</span></span></div>' +
    '<div class="provider-btns">';
  for (const p of PROVIDERS.embedding) {
    const isActive = cfg.embedding_provider === p.value;
    html += '<button class="ibtn' + (isActive ? ' primary' : '') + '" data-cmd="' + esc(p.cmd) + '"' +
      (isActive ? ' disabled style="opacity:.5;pointer-events:none"' : '') + '>' + esc(p.label) + '</button>';
  }
  html += '</div></div>';

  // Other config
  html += '<div class="cfg-section"><h3>Merge &amp; Storage</h3>' +
    '<div class="cfg-row"><span class="cfg-label">Merge LLM</span><span class="cfg-value">' + esc(cfg.merge_provider || '-') + '</span></div>' +
    '<div class="cfg-row"><span class="cfg-label">Storage</span><span class="cfg-value">' + esc(cfg.storage || '-') + '</span></div>' +
    '<div class="cfg-row"><span class="cfg-label">Workspace</span><span class="cfg-value">' + esc(cfg.workspace || '-') + '</span></div>' +
  '</div>';

  html += '</div></div>';

  html += '</div>'; // close mid-grid

  el.innerHTML = html;
  updateLogs(data.logs || [], data.service_logs || {});
  bindAll();
}

function coreCard(label, svc, defaultPort, svcName) {
  const state = svc ? svc.state : 'stopped';
  const bc = beaconClass(state);
  const port = (svc && svc.port) || defaultPort;
  const uptime = svc && svc.uptime_s ? 'up ' + formatUptime(svc.uptime_s) : '';
  const pid = svc && svc.pid ? 'pid ' + svc.pid : '';
  const meta = [port ? 'port ' + port : '', pid, uptime].filter(Boolean).join(' &middot; ');

  // Contextual action: restart if running, or show reason if crashed
  let action = '';
  if (state === 'healthy' || state === 'unhealthy' || state === 'starting') {
    action = '<button class="ibtn" data-cmd="corvia-dev restart ' + esc(svcName) + '">Restart</button>';
  } else if (state === 'crashed' || state === 'stopped') {
    action = '<button class="ibtn primary" data-cmd="corvia-dev up">Start</button>';
  }

  return '<div class="health-card">' +
    '<div class="health-beacon ' + bc + '"></div>' +
    '<div class="health-body">' +
      '<div class="health-top">' +
        '<div class="health-label">' + esc(label) + '</div>' +
        action +
      '</div>' +
      '<div class="health-value">' + esc(state) + '</div>' +
      (svc && svc.reason ? '<div class="health-meta" style="color:var(--red)">' + esc(svc.reason) + '</div>' : '') +
      '<div class="health-meta">' + meta + '</div>' +
    '</div></div>';
}

function updateLogs(managerLogs, serviceLogs) {
  // Merge manager logs + per-service logs into tabbed view
  const tabs = {};
  if (managerLogs && managerLogs.length > 0) {
    tabs['manager'] = managerLogs;
  }
  if (serviceLogs) {
    for (const [name, lines] of Object.entries(serviceLogs)) {
      if (lines && lines.length > 0) tabs[name] = lines;
    }
  }
  lastLogData = tabs;

  const tabNames = Object.keys(tabs);
  const tabsEl = document.getElementById('logTabs');
  const contentEl = document.getElementById('logContent');

  if (tabNames.length === 0) {
    tabsEl.innerHTML = '';
    contentEl.innerHTML = '<div class="log-empty">No log output yet</div>';
    return;
  }

  // Select tab
  if (!activeLogTab || !tabs[activeLogTab]) {
    activeLogTab = tabNames[0];
  }

  // Render tabs
  let tabHtml = '';
  for (const name of tabNames) {
    const active = name === activeLogTab ? ' active' : '';
    const count = tabs[name].length;
    tabHtml += '<button class="log-tab' + active + '" data-log-tab="' + esc(name) + '">' +
      esc(name) + '<span class="tab-count">' + count + '</span></button>';
  }
  tabsEl.innerHTML = tabHtml;

  // Render active tab content
  const lines = tabs[activeLogTab] || [];
  contentEl.innerHTML = '<div class="log-area">' + esc(lines.join('\\n')) + '</div>';

  // Auto-scroll
  const area = contentEl.querySelector('.log-area');
  if (area) area.scrollTop = area.scrollHeight;

  // Tab click handlers
  tabsEl.querySelectorAll('[data-log-tab]').forEach(btn => {
    btn.onclick = () => {
      activeLogTab = btn.dataset.logTab;
      updateLogs(managerLogs, serviceLogs);
    };
  });
}

function bindAll() {
  document.querySelectorAll('[data-cmd]').forEach(b => {
    b.onclick = () => vscode.postMessage({ type: 'command', command: b.dataset.cmd });
  });
  document.querySelectorAll('[data-action]').forEach(b => {
    b.onclick = () => vscode.postMessage({ type: b.dataset.action });
  });
  document.querySelectorAll('[data-toggle]').forEach(t => {
    t.onclick = () => {
      const svc = t.dataset.toggle;
      const isEnabled = t.dataset.enabled === '1';
      const cmd = isEnabled ? 'corvia-dev disable ' + svc : 'corvia-dev enable ' + svc;
      vscode.postMessage({ type: 'command', command: cmd });
    };
  });
}

// Initial binding for header buttons (outside #content)
bindAll();
</script>
</body>
</html>`;
}

function deactivate() {
    if (pollTimer) clearInterval(pollTimer);
}

module.exports = { activate, deactivate };
