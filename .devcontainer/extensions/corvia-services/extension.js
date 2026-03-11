const vscode = require("vscode");
const { exec } = require("child_process");

let statusBarItem;
let panel;
let pollTimer;
let prevData = null;

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

    // Attach previous poll snapshot for metric trend computation
    data._prev = prevData;
    prevData = { ...data, _prev: undefined };

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
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg-primary: #12141a;
  --bg-elevated: #1a1d26;
  --bg-card: #1e2230;
  --bg-card-hover: #252a3a;
  --bg-input: #282d3e;
  --bg-surface: #2e3447;

  --gold: #f0c94c;
  --gold-bright: #ffe066;
  --gold-soft: rgba(240, 201, 76, 0.10);
  --gold-medium: rgba(240, 201, 76, 0.18);
  --gold-glow: rgba(240, 201, 76, 0.25);

  --mint: #5eead4;
  --mint-soft: rgba(94, 234, 212, 0.10);
  --mint-medium: rgba(94, 234, 212, 0.16);

  --coral: #ff8a80;
  --coral-soft: rgba(255, 138, 128, 0.08);
  --coral-medium: rgba(255, 138, 128, 0.14);

  --peach: #ffb07c;
  --peach-soft: rgba(255, 176, 124, 0.10);
  --peach-medium: rgba(255, 176, 124, 0.16);

  --lavender: #c4b5fd;
  --lavender-soft: rgba(196, 181, 253, 0.10);
  --lavender-medium: rgba(196, 181, 253, 0.16);

  --amber: #fcd34d;
  --amber-soft: rgba(252, 211, 77, 0.10);
  --amber-medium: rgba(252, 211, 77, 0.16);

  --sky: #7dd3fc;
  --sky-soft: rgba(125, 211, 252, 0.10);
  --sky-medium: rgba(125, 211, 252, 0.16);

  --text-bright: #ffffff;
  --text-primary: #e0ddd8;
  --text-muted: #b0a99f;
  --text-dim: #8a8279;

  --border: rgba(80, 75, 68, 0.4);
  --border-bright: rgba(100, 94, 86, 0.45);
  --border-subtle: rgba(65, 60, 54, 0.35);

  --radius-xl: 20px;
  --radius-lg: 16px;
  --radius-md: 12px;
  --radius-sm: 8px;
  --radius-xs: 6px;

  --shadow-card: 0 2px 8px rgba(0,0,0,0.18);
  --shadow-hover: 0 4px 12px rgba(0,0,0,0.25);
  --shadow-gold: 0 2px 8px rgba(240,201,76,0.08);

  --font-ui: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
  --font-mono: 'Cascadia Code', 'JetBrains Mono', 'Fira Code', monospace;
  --transition: 0.25s cubic-bezier(0.4, 0, 0.2, 1);
}

body {
  font-family: var(--font-ui); background: var(--bg-primary);
  color: var(--text-primary); font-size: 13px; line-height: 1.5;
  -webkit-font-smoothing: antialiased; min-height: 100vh;
}

/* ===== Header ===== */
.header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 28px; background: rgba(18,20,26,0.8);
  border-bottom: 1px solid var(--border-subtle);
  position: sticky; top: 0; z-index: 10;
}
.header-left { display: flex; align-items: center; gap: 20px; }
.brand { display: flex; align-items: center; gap: 10px; }
.brand-icon {
  width: 30px; height: 30px; border-radius: var(--radius-sm);
  background: linear-gradient(135deg, var(--gold), #d4a820);
  display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 14px; color: var(--bg-primary);
}
.brand-name { font-size: 17px; font-weight: 700; color: var(--text-bright); letter-spacing: -0.02em; }

.status-pills { display: flex; gap: 8px; }
.pill {
  display: flex; align-items: center; gap: 8px;
  padding: 7px 16px; background: var(--bg-card);
  border: 1px solid var(--border); border-radius: var(--radius-sm);
  font-size: 11px; font-weight: 500; color: var(--text-muted);
  cursor: default; transition: all var(--transition); box-shadow: var(--shadow-card);
}
.pill:hover { background: var(--bg-card-hover); border-color: var(--mint-medium); }
.pill:hover .pill-restart { opacity: 1; }
.pill-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.pill-dot.ok {
  background: var(--mint);
  box-shadow: 0 0 4px rgba(94,234,212,0.5);
}
.pill-dot.down { background: var(--coral); box-shadow: 0 0 4px rgba(255,138,128,0.4); }
.pill-dot.warn { background: var(--amber); box-shadow: 0 0 4px rgba(252,211,77,0.4); }

.pill-label { text-transform: uppercase; letter-spacing: 0.05em; font-size: 10px; font-weight: 600; }
.pill-restart {
  opacity: 0; color: var(--text-dim); cursor: pointer;
  transition: all var(--transition); display: flex;
}
.pill-restart:hover { color: var(--gold); }

.header-right { display: flex; align-items: center; gap: 14px; }
.header-time { font-family: var(--font-mono); font-size: 11px; color: var(--text-dim); }
.scope-badge {
  font-size: 11px; color: var(--text-muted); background: var(--bg-input);
  padding: 4px 16px; border-radius: 99px; font-weight: 500; border: 1px solid var(--border-subtle);
}

/* ===== Metrics ===== */
.metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; padding: 22px 28px; }
.metric-card {
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: var(--radius-lg); padding: 20px 22px;
  transition: all var(--transition); box-shadow: var(--shadow-card);
  position: relative; overflow: hidden;
}
.metric-card::after {
  content: ''; position: absolute; top: 0; left: 16px; right: 16px;
  height: 3px; border-radius: 0 0 3px 3px;
}
.metric-card.gold::after { background: linear-gradient(90deg, var(--gold), var(--gold-bright)); }
.metric-card.mint::after { background: linear-gradient(90deg, var(--mint), #7df4e1); }
.metric-card.peach::after { background: linear-gradient(90deg, var(--peach), #ffc99e); }
.metric-card.lavender::after { background: linear-gradient(90deg, var(--lavender), #d4c5fe); }
.metric-card:hover { border-color: var(--border-bright); }

.metric-icon {
  width: 38px; height: 38px; border-radius: var(--radius-sm);
  display: flex; align-items: center; justify-content: center; margin-bottom: 14px;
}
.metric-icon.gold { background: var(--gold-soft); color: var(--gold); }
.metric-icon.mint { background: var(--mint-soft); color: var(--mint); }
.metric-icon.peach { background: var(--peach-soft); color: var(--peach); }
.metric-icon.lavender { background: var(--lavender-soft); color: var(--lavender); }

.metric-label {
  font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-dim); font-weight: 600; margin-bottom: 4px;
}
.metric-row { display: flex; align-items: baseline; justify-content: space-between; }
.metric-value {
  font-size: 30px; font-weight: 800; color: var(--text-bright);
  letter-spacing: -0.03em; font-variant-numeric: tabular-nums;
}
.metric-trend {
  font-size: 11px; font-weight: 600; padding: 3px 10px; border-radius: 99px;
}
.metric-trend.up { background: var(--mint-soft); color: var(--mint); }
.metric-trend.neutral { background: var(--gold-soft); color: var(--gold); }
.metric-trend.clear { background: var(--mint-medium); color: var(--mint); }

/* ===== Workspace ===== */
.workspace {
  display: grid; grid-template-columns: 7fr 3fr; gap: 16px;
  padding: 0 28px 28px; height: calc(100vh - 195px); min-height: 400px;
}

/* ===== Log Panel ===== */
.log-panel {
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: var(--radius-xl); box-shadow: var(--shadow-card);
  display: flex; flex-direction: column; overflow: hidden;
}

.view-tabs {
  display: flex; gap: 0; padding: 0 24px;
  border-bottom: 1px solid var(--border-subtle);
  background: var(--bg-elevated); border-radius: var(--radius-xl) var(--radius-xl) 0 0;
}
.view-tab {
  padding: 14px 18px; font-size: 12px; font-weight: 500;
  color: var(--text-dim); background: none; border: none;
  border-bottom: 2.5px solid transparent; cursor: pointer;
  font-family: var(--font-ui); transition: all var(--transition);
  display: flex; align-items: center; gap: 8px;
}
.view-tab:hover { color: var(--text-muted); }
.view-tab.active { color: var(--gold); border-bottom-color: var(--gold); font-weight: 600; }
.view-tab-icon { width: 15px; height: 15px; opacity: 0.4; }
.view-tab.active .view-tab-icon { opacity: 1; }

.log-toolbar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 24px; border-bottom: 1px solid var(--border-subtle); gap: 12px;
}
.log-filters {
  display: flex; gap: 3px; background: var(--bg-input);
  border-radius: var(--radius-xs); padding: 3px;
}
.log-filter {
  padding: 5px 14px; border: none; border-radius: var(--radius-xs);
  background: transparent; color: var(--text-dim);
  font-family: var(--font-ui); font-size: 11px; font-weight: 500;
  cursor: pointer; transition: all var(--transition);
}
.log-filter:hover { color: var(--text-muted); }
.log-filter.active { color: var(--gold); background: var(--gold-soft); font-weight: 600; }

.log-actions { display: flex; align-items: center; gap: 8px; }
.log-search {
  background: var(--bg-input); border: 1.5px solid transparent;
  border-radius: var(--radius-xs); padding: 6px 14px;
  color: var(--text-primary); font-family: var(--font-mono);
  font-size: 11px; width: 200px; outline: none; transition: all var(--transition);
}
.log-search::placeholder { color: var(--text-dim); }
.log-search:focus { border-color: var(--gold); }

.log-btn {
  background: var(--bg-input); border: none; color: var(--text-dim);
  cursor: pointer; padding: 6px 12px; border-radius: var(--radius-xs);
  display: flex; align-items: center; gap: 5px;
  transition: all var(--transition); font-size: 11px;
  font-family: var(--font-ui); font-weight: 500;
}
.log-btn:hover { color: var(--gold); background: var(--gold-soft); }
.log-btn.active { color: var(--gold); background: var(--gold-soft); }

.log-source-tabs {
  display: flex; gap: 0; padding: 0 24px; border-bottom: 1px solid var(--border-subtle);
}
.source-tab {
  padding: 8px 16px; font-size: 11px; font-weight: 500;
  color: var(--text-dim); background: none; border: none;
  border-bottom: 2px solid transparent; cursor: pointer;
  font-family: var(--font-ui); transition: all var(--transition);
}
.source-tab:hover { color: var(--text-muted); }
.source-tab.active { color: var(--text-bright); border-bottom-color: var(--gold); }
.source-tab-count {
  font-size: 9px; background: var(--bg-surface); color: var(--text-dim);
  padding: 1px 7px; border-radius: 99px; margin-left: 5px; font-weight: 600;
}

.log-output {
  flex: 1; overflow-y: auto; padding: 10px 0;
  font-family: var(--font-mono); font-size: 11.5px; line-height: 1.9;
}
.log-line {
  display: flex; gap: 12px; padding: 2px 24px;
  transition: background var(--transition); border-left: 3px solid transparent;
}
.log-line:hover { background: rgba(46,52,71,0.4); }
.log-line.hidden { display: none; }
.log-ts {
  color: var(--text-dim); opacity: 0.6; flex-shrink: 0;
  user-select: none; font-variant-numeric: tabular-nums; min-width: 58px;
}
.log-level {
  flex-shrink: 0; font-weight: 700; font-size: 10px;
  text-transform: uppercase; min-width: 34px; padding-top: 1px;
}
.log-level.info { color: var(--mint); }
.log-level.error { color: var(--coral); }
.log-level.warn { color: var(--amber); }
.log-level.debug { color: var(--text-dim); }
.log-msg { color: var(--text-primary); word-break: break-word; }

.log-line.is-error { border-left-color: var(--coral); background: var(--coral-soft); padding-left: 21px; }
.log-line.is-error:hover { background: var(--coral-medium); }
.log-line.is-warn { border-left-color: var(--amber); background: var(--amber-soft); padding-left: 21px; }
.log-line.is-warn:hover { background: var(--amber-medium); }

.log-empty {
  display: flex; align-items: center; justify-content: center;
  height: 100%; font-size: 12px; color: var(--text-dim);
}

/* ===== Sidebar ===== */
.sidebar { display: flex; flex-direction: column; gap: 16px; overflow-y: auto; }
.sidebar-card {
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: var(--radius-lg); box-shadow: var(--shadow-card); overflow: hidden;
}
.sidebar-card-header { padding: 18px 20px 0; }
.sidebar-label {
  font-size: 10px; text-transform: uppercase; letter-spacing: 0.07em;
  color: var(--text-dim); font-weight: 700; margin-bottom: 14px;
}
.sidebar-card-body { padding: 0 20px 18px; }

.toggle-group {
  display: flex; background: var(--bg-input); border-radius: var(--radius-xs);
  padding: 3px; gap: 3px;
}
.toggle-opt {
  flex: 1; padding: 8px 16px; font-size: 11px; font-weight: 500;
  color: var(--text-dim); background: transparent; border: none;
  border-radius: var(--radius-xs); cursor: pointer; text-align: center;
  font-family: var(--font-ui); transition: all var(--transition);
}
.toggle-opt:hover { color: var(--text-muted); }
.toggle-opt.active {
  background: var(--gold-medium); color: var(--gold-bright); font-weight: 700;
}

.cfg-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 9px 0; font-size: 12px; border-bottom: 1px solid var(--border-subtle);
}
.cfg-row:last-child { border-bottom: none; }
.cfg-key { color: var(--text-muted); }
.cfg-val {
  color: var(--text-bright); font-weight: 600;
  display: flex; align-items: center; gap: 8px;
}
.cfg-synced {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 10px; color: var(--mint); font-weight: 700;
  background: var(--mint-medium); padding: 2px 10px; border-radius: 99px;
}

.empty-state {
  border: 1.5px dashed var(--border-bright); border-radius: var(--radius-sm);
  padding: 28px 16px; text-align: center;
  transition: all var(--transition); background: rgba(46,52,71,0.15);
}
.empty-state:hover { border-color: var(--gold); background: var(--gold-soft); }
.empty-state p { font-size: 12px; color: var(--text-dim); margin-bottom: 12px; }
.ghost-btn {
  background: none; border: 1px solid var(--border-bright);
  border-radius: var(--radius-xs); color: var(--text-muted);
  padding: 7px 18px; font-size: 11px; font-family: var(--font-ui); font-weight: 600;
  cursor: pointer; transition: all var(--transition);
}
.ghost-btn:hover {
  border-color: var(--gold); color: var(--gold);
  background: var(--gold-soft);
}

.svc-item {
  display: flex; align-items: center; gap: 10px;
  padding: 10px 0; border-bottom: 1px solid var(--border-subtle);
}
.svc-item:last-child { border-bottom: none; }
.svc-dot { width: 7px; height: 7px; border-radius: 50%; flex-shrink: 0; }
.svc-dot.ok { background: var(--mint); }
.svc-dot.down { background: var(--coral); }
.svc-dot.stopped { background: var(--text-dim); }
.svc-name { flex: 1; font-size: 12px; color: var(--text-primary); font-weight: 500; }
.svc-state { font-size: 10px; color: var(--text-dim); font-family: var(--font-mono); }

.switch {
  width: 32px; height: 16px; border-radius: 99px;
  background: var(--bg-input); border: 1px solid var(--border);
  position: relative; cursor: pointer; flex-shrink: 0; transition: all var(--transition);
}
.switch::after {
  content: ''; position: absolute; top: 2px; left: 2px;
  width: 10px; height: 10px; border-radius: 50%;
  background: var(--text-dim); transition: all var(--transition);
}
.switch.on { background: var(--mint-soft); border-color: var(--mint); }
.switch.on::after { transform: translateX(16px); background: var(--mint); }

/* ===== View placeholders ===== */
.view-placeholder {
  flex: 1; display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: 12px; color: var(--text-dim);
}
.view-placeholder svg { opacity: 0.3; }
.view-placeholder p { font-size: 13px; }

/* ===== Offline ===== */
.offline {
  display: flex; flex-direction: column; align-items: center;
  justify-content: center; padding: 80px 20px; text-align: center;
}
.offline-icon {
  width: 56px; height: 56px; border-radius: 50%; margin-bottom: 20px;
  background: var(--coral-soft); display: flex; align-items: center;
  justify-content: center; color: var(--coral);
}
.offline h2 { font-size: 18px; font-weight: 700; color: var(--text-bright); margin-bottom: 8px; }
.offline p { font-size: 13px; color: var(--text-muted); margin-bottom: 20px; }
.offline code {
  background: var(--bg-input); padding: 2px 8px;
  border-radius: var(--radius-xs); font-size: 12px;
  font-family: var(--font-mono); color: var(--text-primary);
}
.offline-btn {
  background: var(--gold-soft); border: 1px solid var(--gold);
  border-radius: var(--radius-sm); color: var(--gold);
  padding: 8px 24px; font-size: 12px; font-weight: 600;
  font-family: var(--font-ui); cursor: pointer; transition: all var(--transition);
}
.offline-btn:hover { background: var(--gold-medium); }

/* ===== Skeleton ===== */
.skeleton {
  background: var(--bg-surface);
  border-radius: var(--radius-xs); height: 14px;
}

/* ===== Scrollbar ===== */
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--bg-surface); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--text-dim); }

/* ===== Responsive ===== */
@media (max-width: 700px) {
  .workspace { grid-template-columns: 1fr; height: auto; }
  .metrics { grid-template-columns: repeat(2, 1fr); }
  .log-panel { min-height: 50vh; }
}

/* ===== Traces ===== */
.traces-tab-bar {
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: var(--radius-xl); margin: 0 28px;
  box-shadow: var(--shadow-card); overflow: hidden;
}
.traces-workspace {
  display: grid; grid-template-columns: 1fr 280px;
  gap: 16px; padding: 0 28px 28px;
  height: calc(100vh - 310px); min-height: 400px;
  margin-top: 16px;
}
@media (max-width: 700px) {
  .traces-workspace { grid-template-columns: 1fr; height: auto; }
  .graph-panel { min-height: 50vh; }
}
.graph-panel {
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: var(--radius-xl); box-shadow: var(--shadow-card);
  display: flex; flex-direction: column; overflow: hidden;
  position: relative;
}
.graph-toolbar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 12px 20px; border-bottom: 1px solid var(--border-subtle);
}
.mode-switcher {
  display: flex; gap: 3px; background: var(--bg-input);
  border-radius: var(--radius-xs); padding: 3px;
}
.mode-btn {
  padding: 6px 16px; font-size: 11px; font-weight: 500;
  color: var(--text-dim); background: transparent; border: none;
  border-radius: var(--radius-xs); cursor: pointer;
  font-family: var(--font-ui); transition: all var(--transition);
}
.mode-btn:hover { color: var(--text-muted); }
.mode-btn.active { color: var(--gold); background: var(--gold-soft); font-weight: 600; }
.graph-hint { font-size: 10px; color: var(--text-dim); }

.graph-canvas {
  flex: 1; position: relative; overflow: hidden; padding: 20px 80px 20px 10px;
}

/* Nodes */
.tnode {
  position: absolute; background: var(--bg-card);
  border: 1.5px solid var(--border); border-radius: var(--radius-md);
  padding: 14px 18px; cursor: pointer; transition: all var(--transition);
  width: 130px; text-align: center; z-index: 2;
  transform: translate(-50%, 0);
}
.tnode:hover { border-color: var(--border-bright); background: var(--bg-card-hover); }
.tnode.selected { box-shadow: 0 0 0 3px var(--gold-soft); }

.tnode-icon {
  width: 32px; height: 32px; border-radius: var(--radius-sm);
  display: flex; align-items: center; justify-content: center;
  margin: 0 auto 10px; font-size: 14px;
}
.tnode-label {
  font-size: 11px; font-weight: 700; text-transform: uppercase;
  letter-spacing: 0.05em; margin-bottom: 4px;
}
.tnode-stat { font-size: 10px; color: var(--text-dim); }
.tnode-bar {
  margin-top: 8px; height: 3px; border-radius: 2px;
  background: var(--bg-input); overflow: hidden;
}
.tnode-bar-fill { height: 100%; border-radius: 2px; transition: width 0.5s ease; }

/* SVG edges */
.edge-layer { position: absolute; inset: 0; pointer-events: none; z-index: 1; }
.edge-path { stroke: var(--border); stroke-width: 1.5; fill: none; }

/* Heat mode glow */
@keyframes heat-pulse {
  0%, 100% { opacity: 0.6; }
  50% { opacity: 1; }
}
.tnode.heat-cool { box-shadow: 0 0 12px rgba(94,234,212,0.4); animation: heat-pulse 2s ease-in-out infinite; }
.tnode.heat-warm { box-shadow: 0 0 16px rgba(240,201,76,0.5); animation: heat-pulse 2s ease-in-out infinite; }
.tnode.heat-hot { box-shadow: 0 0 20px rgba(255,138,128,0.6); animation: heat-pulse 2s ease-in-out infinite; }
.tnode.selected.heat-cool { box-shadow: 0 0 0 3px var(--gold-soft), 0 0 12px rgba(94,234,212,0.4); }
.tnode.selected.heat-warm { box-shadow: 0 0 0 3px var(--gold-soft), 0 0 16px rgba(240,201,76,0.5); }
.tnode.selected.heat-hot { box-shadow: 0 0 0 3px var(--gold-soft), 0 0 20px rgba(255,138,128,0.6); }

/* Detail panel */
.trace-detail { display: flex; flex-direction: column; gap: 16px; overflow-y: auto; }
.trace-card {
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: var(--radius-lg); box-shadow: var(--shadow-card); overflow: hidden;
}
.trace-card-hdr { padding: 18px 20px 0; }
.trace-card-body { padding: 0 20px 18px; }
.trace-label {
  font-size: 10px; text-transform: uppercase; letter-spacing: 0.07em;
  color: var(--text-dim); font-weight: 700; margin-bottom: 14px;
}

.module-hdr {
  display: flex; align-items: center; gap: 12px;
  padding: 16px 20px; border-bottom: 1px solid var(--border-subtle);
}
.module-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
.module-name { font-size: 13px; font-weight: 700; color: var(--text-bright); }
.module-desc { font-size: 10px; color: var(--text-dim); margin-top: 2px; }

.mini-stats { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; padding: 16px 20px; }
.mini-stat {
  background: var(--bg-input); border-radius: var(--radius-sm);
  padding: 12px; text-align: center;
}
.mini-stat-val { font-size: 18px; font-weight: 800; color: var(--text-bright); }
.mini-stat-lbl {
  font-size: 9px; color: var(--text-dim); text-transform: uppercase;
  letter-spacing: 0.06em; margin-top: 4px; font-weight: 600;
}

.span-row {
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 0; border-bottom: 1px solid var(--border-subtle); font-size: 12px;
}
.span-row:last-child { border-bottom: none; }
.span-name { font-family: var(--font-mono); font-size: 11px; color: var(--text-primary); }
.span-fields { font-size: 10px; color: var(--text-dim); margin-top: 2px; }
.span-pill {
  font-family: var(--font-mono); font-size: 11px; font-weight: 600;
  padding: 2px 8px; border-radius: 99px; flex-shrink: 0;
}
.span-fast { color: var(--mint); background: var(--mint-soft); }
.span-medium { color: var(--peach); background: var(--peach-soft); }
.span-slow { color: var(--coral); background: var(--coral-soft); }

.evt-row { display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 11px; }
.evt-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
.evt-dot.info { background: var(--mint); }
.evt-dot.warn { background: var(--amber); }
.evt-dot.error { background: var(--coral); }
.evt-dot.debug { background: var(--text-dim); }
.evt-msg { color: var(--text-muted); flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.evt-time { color: var(--text-dim); font-family: var(--font-mono); font-size: 10px; flex-shrink: 0; }

.trace-empty {
  display: flex; align-items: center; justify-content: center;
  height: 100%; font-size: 12px; color: var(--text-dim); padding: 40px;
  text-align: center;
}
</style>
</head>
<body>

<!-- Header -->
<div class="header">
  <div class="header-left">
    <div class="brand">
      <div class="brand-icon">C</div>
      <span class="brand-name">Corvia</span>
    </div>
    <div class="status-pills" id="statusPills">
      <div class="pill"><div class="pill-dot"></div><span class="pill-label">API Server</span></div>
      <div class="pill"><div class="pill-dot"></div><span class="pill-label">Inference</span></div>
    </div>
  </div>
  <div class="header-right">
    <span class="header-time" id="headerTime"></span>
    <span class="scope-badge" id="scopeBadge">loading</span>
  </div>
</div>

<!-- Dynamic content -->
<div id="content">
  <div class="metrics">
    <div class="metric-card gold" style="padding:22px"><div class="skeleton" style="width:60%"></div></div>
    <div class="metric-card peach" style="padding:22px"><div class="skeleton" style="width:60%"></div></div>
    <div class="metric-card mint" style="padding:22px"><div class="skeleton" style="width:60%"></div></div>
    <div class="metric-card lavender" style="padding:22px"><div class="skeleton" style="width:60%"></div></div>
  </div>
</div>

<script>
const vscode = acquireVsCodeApi();

// --- State ---
let activeView = 'logs';
let activeLogTab = null;
let activeFilter = 'all';
let autoScroll = true;
let searchQuery = '';
let lastLogData = {};

// --- SVG constants ---
const SVG_RESTART = '<svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor"><path d="M13.5 2.5a.5.5 0 0 0-1 0v2.05A6.48 6.48 0 0 0 8 2.5a6.5 6.5 0 1 0 6.5 6.5.5.5 0 0 0-1 0A5.5 5.5 0 1 1 8 3.5a5.48 5.48 0 0 1 3.94 1.66h-1.94a.5.5 0 0 0 0 1h3a.5.5 0 0 0 .5-.5v-3.16z"/></svg>';
const SVG_CHECK = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.75.75 0 1 1 1.06-1.06L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0z"/></svg>';
const SVG_LOGS = '<svg class="view-tab-icon" viewBox="0 0 16 16" fill="currentColor"><path d="M2 2a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V2zm1 0v12h10V2H3zm1.5 2h7a.5.5 0 0 1 0 1h-7a.5.5 0 0 1 0-1zm0 2.5h7a.5.5 0 0 1 0 1h-7a.5.5 0 0 1 0-1zm0 2.5h4a.5.5 0 0 1 0 1h-4a.5.5 0 0 1 0-1z"/></svg>';
const SVG_GRAPH = '<svg class="view-tab-icon" viewBox="0 0 16 16" fill="currentColor"><path d="M1 1v14h14V1H1zm13 13H2V2h12v12zM3 13V8h2v5H3zm3 0V5h2v8H6zm3 0V9h2v4H9zm3 0V3h1v10h-1z"/></svg>';
const SVG_TRACES = '<svg class="view-tab-icon" viewBox="0 0 16 16" fill="currentColor"><path d="M0 3.5A.5.5 0 0 1 .5 3h15a.5.5 0 0 1 0 1H.5a.5.5 0 0 1-.5-.5zM3 7.5A.5.5 0 0 1 3.5 7h9a.5.5 0 0 1 0 1h-9A.5.5 0 0 1 3 7.5zM6 11.5a.5.5 0 0 1 .5-.5h3a.5.5 0 0 1 0 1h-3a.5.5 0 0 1-.5-.5z"/></svg>';
const SVG_OFFLINE = '<svg width="28" height="28" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 13A6 6 0 1 1 8 2a6 6 0 0 1 0 12zm-.5-3h1v1h-1v-1zm0-7h1v5.5h-1V4z"/></svg>';

const METRIC_ICONS = {
  entries: '<svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor"><path d="M4 0h8a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2a2 2 0 0 1 2-2zm0 1a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V2a1 1 0 0 0-1-1H4zm1.5 3a.5.5 0 0 1 0-1h5a.5.5 0 0 1 0 1h-5zm0 2a.5.5 0 0 1 0-1h5a.5.5 0 0 1 0 1h-5zm0 2a.5.5 0 0 1 0-1h3a.5.5 0 0 1 0 1h-3z"/></svg>',
  agents: '<svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor"><path d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm2-3a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm4 8c0 1-1 1-1 1H3s-1 0-1-1 1-4 6-4 6 3 6 4zm-1-.004c-.001-.246-.154-.986-.832-1.664C11.516 10.68 10.289 10 8 10c-2.29 0-3.516.68-4.168 1.332-.678.678-.83 1.418-.832 1.664h10z"/></svg>',
  queue: '<svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor"><path d="M0 2a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V2zm15 0a1 1 0 0 0-1-1H2a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V2zM4 4h8v1H4V4zm0 2.5h8v1H4v-1zm0 2.5h5v1H4V9z"/></svg>',
  sessions: '<svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor"><path d="M1.5 1a.5.5 0 0 0-.5.5v3a.5.5 0 0 1-1 0v-3A1.5 1.5 0 0 1 1.5 0h3a.5.5 0 0 1 0 1h-3zM11 .5a.5.5 0 0 1 .5-.5h3A1.5 1.5 0 0 1 16 1.5v3a.5.5 0 0 1-1 0v-3a.5.5 0 0 0-.5-.5h-3a.5.5 0 0 1-.5-.5zM.5 11a.5.5 0 0 1 .5.5v3a.5.5 0 0 0 .5.5h3a.5.5 0 0 1 0 1h-3A1.5 1.5 0 0 1 0 14.5v-3a.5.5 0 0 1 .5-.5zm15 0a.5.5 0 0 1 .5.5v3a1.5 1.5 0 0 1-1.5 1.5h-3a.5.5 0 0 1 0-1h3a.5.5 0 0 0 .5-.5v-3a.5.5 0 0 1 .5-.5z"/><path d="M3 14s-1 0-1-1 1-4 6-4 6 3 6 4-1 1-1 1H3zm8-9a3 3 0 1 1-6 0 3 3 0 0 1 6 0z"/></svg>',
};

const SVC_META = {
  'corvia-server':    { desc: 'REST + MCP API server' },
  'corvia-inference': { desc: 'ONNX embeddings + chat (gRPC)' },
  'ollama':           { desc: 'Local LLM runtime' },
  'vllm':             { desc: 'High-perf LLM serving' },
  'surrealdb':        { desc: 'SurrealDB storage backend' },
  'postgres':         { desc: 'PostgreSQL storage backend' },
  'coding-llm':       { desc: 'Code assistant via Continue' },
};

const PROVIDERS = {
  embedding: [
    { value: 'corvia', label: 'Corvia', cmd: 'corvia-dev use corvia-inference' },
    { value: 'ollama', label: 'Ollama', cmd: 'corvia-dev use ollama' },
  ],
};

// --- Traces: module topology ---
// pos: [x%, y%] — x centers node horizontally (transform: -50%), y is top offset
const MODULES = {
  agent:     { label: 'Agent',     color: 'peach',    desc: 'Agent registration & session lifecycle',
               icon: '\u{1F916}', pos: [18, 6] },
  entry:     { label: 'Entry',     color: 'gold',     desc: 'Write, embed, insert pipeline',
               icon: '\u{1F4DD}', pos: [50, 4] },
  merge:     { label: 'Merge',     color: 'mint',     desc: 'Conflict detection & resolution',
               icon: '\u{1F500}', pos: [50, 50] },
  storage:   { label: 'Storage',   color: 'lavender', desc: 'LiteStore / Postgres persistence',
               icon: '\u{1F4BE}', pos: [82, 4] },
  rag:       { label: 'RAG',       color: 'sky',      desc: 'Retrieval-augmented generation',
               icon: '\u{1F50E}', pos: [82, 50] },
  inference: { label: 'Inference', color: 'coral',    desc: 'ONNX embedding via gRPC',
               icon: '\u26A1',    pos: [18, 50] },
  gc:        { label: 'GC',        color: 'amber',    desc: 'Garbage collection sweeps',
               icon: '\u{1F9F9}', pos: [50, 72] },
};

// Edges: [from, to] — data flow direction
const EDGES = [
  ['agent', 'entry'],
  ['entry', 'inference'], ['entry', 'storage'], ['entry', 'merge'],
  ['merge', 'storage'],
  ['storage', 'rag'],
  ['agent', 'gc'], ['gc', 'storage'],
];

const SPAN_MODULE_SPECIFIC = { 'corvia.entry.embed': 'inference' };
const SPAN_MODULE_PREFIX = [
  ['corvia.agent.', 'agent'], ['corvia.session.', 'agent'],
  ['corvia.entry.', 'entry'], ['corvia.merge.', 'merge'],
  ['corvia.store.', 'storage'], ['corvia.rag.', 'rag'],
  ['corvia.gc.', 'gc'],
];

const SPAN_FIELDS = {
  'corvia.agent.register': 'display_name',
  'corvia.session.create': 'agent_id, with_staging',
  'corvia.session.commit': 'session_id',
  'corvia.entry.write': 'session_id',
  'corvia.entry.embed': 'gRPC / Ollama',
  'corvia.entry.insert': 'entry_id, scope_id',
  'corvia.merge.process': '',
  'corvia.merge.process_entry': 'entry_id',
  'corvia.merge.conflict': 'entry_id, scope_id',
  'corvia.merge.llm_resolve': 'new_id, existing_id',
  'corvia.store.insert': 'entry_id, scope_id',
  'corvia.store.search': 'scope_id',
  'corvia.store.get': '',
  'corvia.rag.context': 'scope_id',
  'corvia.rag.ask': 'scope_id',
  'corvia.gc.run': '',
};

function spanToModule(name) {
  if (SPAN_MODULE_SPECIFIC[name]) return SPAN_MODULE_SPECIFIC[name];
  for (var i = 0; i < SPAN_MODULE_PREFIX.length; i++) {
    if (name.startsWith(SPAN_MODULE_PREFIX[i][0])) return SPAN_MODULE_PREFIX[i][1];
  }
  return 'unknown';
}

let traceMode = 'map';
let selectedModule = null;
let lastTraceModStats = {};

// --- Helpers ---
function esc(str) {
  const d = document.createElement('div');
  d.textContent = str;
  return d.innerHTML;
}

function dotClass(state) {
  if (state === 'healthy') return 'ok';
  if (state === 'starting') return 'warn';
  return 'down';
}

function formatNum(n) {
  if (n == null) return '-';
  return Number(n).toLocaleString();
}

function trend(current, prev) {
  if (prev == null || current == null) return { label: '-', cls: 'neutral' };
  const delta = current - prev;
  if (delta > 0) return { label: '\u2191 ' + delta, cls: 'up' };
  if (delta === 0) return { label: 'stable', cls: 'neutral' };
  return { label: '\u2193 ' + Math.abs(delta), cls: 'neutral' };
}

// --- Message handler ---
window.addEventListener('message', (e) => {
  if (e.data.type === 'status') render(e.data.data);
});

// --- Main render ---
let lastRenderedJson = '';

function render(data) {
  const el = document.getElementById('content');

  document.getElementById('headerTime').textContent = new Date().toLocaleTimeString();

  // Skip full re-render if data and view state haven't changed
  const dataJson = JSON.stringify(data) + '|' + activeView + '|' + activeFilter + '|' + activeLogTab + '|' + traceMode + '|' + selectedModule;
  if (dataJson === lastRenderedJson) return;
  lastRenderedJson = dataJson;

  if (!data) {
    document.getElementById('scopeBadge').textContent = 'offline';
    updatePills(null, null);
    el.innerHTML =
      '<div class="offline">' +
        '<div class="offline-icon">' + SVG_OFFLINE + '</div>' +
        '<h2>corvia-dev not responding</h2>' +
        '<p>Run <code>corvia-dev up</code> to start services</p>' +
        '<button class="offline-btn" data-cmd="corvia-dev up">Start Services</button>' +
      '</div>';
    bindAll();
    return;
  }

  const svcs = data.services || [];
  const cfg = data.config || {};
  const enabled = new Set(data.enabled_services || []);
  const prev = data._prev || {};

  const server = svcs.find(s => s.name === 'corvia-server');
  const inference = svcs.find(s => s.name === 'corvia-inference');
  const optional = svcs.filter(s => !['corvia-server', 'corvia-inference'].includes(s.name));

  document.getElementById('scopeBadge').textContent = cfg.workspace || 'corvia';
  updatePills(server, inference);

  // --- Metrics ---
  const entries = data.entry_count ?? data.entries ?? null;
  const agents = data.agent_count ?? data.agents ?? null;
  const queue = data.merge_queue_depth ?? data.queue_depth ?? null;
  const sessions = data.session_count ?? data.sessions ?? null;
  const pEntries = prev.entry_count ?? prev.entries ?? null;
  const pAgents = prev.agent_count ?? prev.agents ?? null;
  const pQueue = prev.merge_queue_depth ?? prev.queue_depth ?? null;
  const pSessions = prev.session_count ?? prev.sessions ?? null;

  const tEntries = trend(entries, pEntries);
  const tAgents = trend(agents, pAgents);
  const tQueue = queue === 0 ? { label: 'clear', cls: 'clear' } : trend(queue, pQueue);
  const tSessions = sessions != null ? { label: 'active', cls: 'neutral' } : { label: '-', cls: 'neutral' };

  let html = '';

  // Metrics row
  html += '<div class="metrics">';
  html += metricCard('gold', METRIC_ICONS.entries, 'Entries', formatNum(entries), tEntries, '');
  html += metricCard('peach', METRIC_ICONS.agents, 'Active Agents', formatNum(agents), tAgents, '');
  html += metricCard('mint', METRIC_ICONS.queue, 'Merge Queue', formatNum(queue), tQueue,
    queue === 0 ? ' style="color:var(--mint)"' : '');
  html += metricCard('lavender', METRIC_ICONS.sessions, 'Sessions', formatNum(sessions), tSessions, '');
  html += '</div>';

  // Traces view uses a different layout (no sidebar, full-width graph)
  if (activeView === 'traces') {
    html += '<div class="traces-tab-bar">';
    html += '<div class="view-tabs">';
    html += viewTab('logs', SVG_LOGS, 'Logs');
    html += viewTab('graph', SVG_GRAPH, 'Graph');
    html += viewTab('traces', SVG_TRACES, 'Traces');
    html += '</div></div>';
    html += renderTraces(data);
    el.innerHTML = html;
    bindAll();
    bindTraces();
    drawEdges();
    return;
  }

  // Workspace
  html += '<div class="workspace">';

  // --- Log panel ---
  html += '<div class="log-panel">';

  // View tabs
  html += '<div class="view-tabs">';
  html += viewTab('logs', SVG_LOGS, 'Logs');
  html += viewTab('graph', SVG_GRAPH, 'Graph');
  html += viewTab('traces', SVG_TRACES, 'Traces');
  html += '</div>';

  if (activeView === 'logs') {
    // Toolbar
    html += '<div class="log-toolbar">';
    html += '<div class="log-filters">';
    for (const f of ['all', 'info', 'warn', 'error']) {
      html += '<button class="log-filter' + (activeFilter === f ? ' active' : '') + '" data-filter="' + f + '">' +
        f.charAt(0).toUpperCase() + f.slice(1) + '</button>';
    }
    html += '</div>';
    html += '<div class="log-actions">' +
      '<input class="log-search" type="text" placeholder="Search logs..." value="' + esc(searchQuery) + '" id="logSearchInput">' +
      '<button class="log-btn' + (autoScroll ? ' active' : '') + '" id="autoScrollBtn">\u2193 Auto</button>' +
      '<button class="log-btn" data-action="clear-logs">Clear</button>' +
    '</div></div>';

    // Source tabs
    const tabs = buildLogTabs(data.logs || [], data.service_logs || {});
    const tabNames = Object.keys(tabs);
    if (tabNames.length > 0 && (!activeLogTab || !tabs[activeLogTab])) {
      activeLogTab = tabNames[0];
    }

    html += '<div class="log-source-tabs">';
    for (const name of tabNames) {
      html += '<button class="source-tab' + (name === activeLogTab ? ' active' : '') + '" data-log-tab="' + esc(name) + '">' +
        esc(name) + '<span class="source-tab-count">' + tabs[name].length + '</span></button>';
    }
    html += '</div>';

    // Log output
    html += '<div class="log-output" id="logOutput">';
    const lines = tabs[activeLogTab] || [];
    if (lines.length === 0) {
      html += '<div class="log-empty">No log output yet</div>';
    } else {
      for (const line of lines) {
        const parsed = parseLine(line);
        const levelMatch = activeFilter === 'all' || parsed.level === activeFilter;
        const searchMatch = !searchQuery || line.toLowerCase().includes(searchQuery.toLowerCase());
        const hidden = (!levelMatch || !searchMatch) ? ' hidden' : '';
        const errClass = parsed.level === 'error' ? ' is-error' : parsed.level === 'warn' ? ' is-warn' : '';
        html += '<div class="log-line' + errClass + hidden + '">' +
          '<span class="log-ts">' + esc(parsed.ts) + '</span>' +
          '<span class="log-level ' + parsed.level + '">' + esc(parsed.levelLabel) + '</span>' +
          '<span class="log-msg">' + esc(parsed.msg) + '</span>' +
        '</div>';
      }
    }
    html += '</div>';
  } else {
    // Placeholder for Graph
    html += '<div class="view-placeholder">' +
      '<svg width="48" height="48" viewBox="0 0 16 16" fill="currentColor"><path d="M1 1v14h14V1H1zm13 13H2V2h12v12zM3 13V8h2v5H3zm3 0V5h2v8H6zm3 0V9h2v4H9zm3 0V3h1v10h-1z"/></svg>' +
      '<p>Graph view coming soon</p>' +
    '</div>';
  }

  html += '</div>'; // close log-panel

  // --- Sidebar ---
  html += '<div class="sidebar">';

  // Embedding provider
  html += '<div class="sidebar-card"><div class="sidebar-card-header"><div class="sidebar-label">Embedding Provider</div></div>' +
    '<div class="sidebar-card-body"><div class="toggle-group">';
  for (const p of PROVIDERS.embedding) {
    const isActive = cfg.embedding_provider === p.value;
    html += '<button class="toggle-opt' + (isActive ? ' active' : '') + '"' +
      (isActive ? '' : ' data-cmd="' + esc(p.cmd) + '"') + '>' + esc(p.label) + '</button>';
  }
  html += '</div></div></div>';

  // Configuration
  html += '<div class="sidebar-card"><div class="sidebar-card-header"><div class="sidebar-label">Configuration</div></div>' +
    '<div class="sidebar-card-body">' +
    cfgRow('Storage', esc(cfg.storage || '-')) +
    cfgRow('Merge LLM', cfg.merge_provider ? esc(cfg.merge_provider) : '<span style="color:var(--text-dim)">&mdash;</span>') +
    cfgRow('Workspace', esc(cfg.workspace || '-') +
      ' <span class="cfg-synced">' + SVG_CHECK + ' Synced</span>') +
    cfgRow('Telemetry', esc(cfg.telemetry_exporter || cfg.telemetry || 'stdout')) +
  '</div></div>';

  // Optional services
  html += '<div class="sidebar-card"><div class="sidebar-card-header"><div class="sidebar-label">Optional Services</div></div>' +
    '<div class="sidebar-card-body">';
  if (optional.length === 0) {
    html += '<div class="empty-state"><p>No optional services configured</p>' +
      '<button class="ghost-btn" data-cmd="corvia-dev enable ollama">Configure Services</button></div>';
  } else {
    for (const svc of optional) {
      const isEnabled = enabled.has(svc.name);
      const dc = svc.state === 'healthy' ? 'ok' : svc.state === 'stopped' ? 'stopped' : 'down';
      html += '<div class="svc-item">' +
        '<div class="svc-dot ' + dc + '"></div>' +
        '<span class="svc-name">' + esc(svc.name) + '</span>' +
        '<span class="svc-state">' + esc(svc.state) + '</span>' +
        '<div class="switch' + (isEnabled ? ' on' : '') + '" data-toggle="' + esc(svc.name) + '" data-enabled="' + (isEnabled ? '1' : '0') + '"></div>' +
      '</div>';
    }
  }
  html += '</div></div>';

  html += '</div>'; // close sidebar
  html += '</div>'; // close workspace

  el.innerHTML = html;

  // Post-render
  bindAll();
  if (autoScroll) {
    const output = document.getElementById('logOutput');
    if (output) output.scrollTop = output.scrollHeight;
  }
}

// --- Component builders ---
function metricCard(color, icon, label, value, trendObj, valueAttr) {
  return '<div class="metric-card ' + color + '">' +
    '<div class="metric-icon ' + color + '">' + icon + '</div>' +
    '<div class="metric-label">' + esc(label) + '</div>' +
    '<div class="metric-row">' +
      '<span class="metric-value"' + valueAttr + '>' + value + '</span>' +
      '<span class="metric-trend ' + trendObj.cls + '">' + esc(trendObj.label) + '</span>' +
    '</div></div>';
}

function viewTab(id, icon, label) {
  return '<button class="view-tab' + (activeView === id ? ' active' : '') + '" data-view="' + id + '">' +
    icon + ' ' + esc(label) + '</button>';
}

function cfgRow(key, valueHtml) {
  return '<div class="cfg-row"><span class="cfg-key">' + esc(key) + '</span>' +
    '<span class="cfg-val">' + valueHtml + '</span></div>';
}

// --- Update header pills ---
function updatePills(server, inference) {
  const pills = document.getElementById('statusPills');
  if (!pills) return;
  const sState = server ? server.state : 'stopped';
  const iState = inference ? inference.state : 'stopped';

  pills.innerHTML = pill('API Server', sState, 'corvia-server') + pill('Inference', iState, 'corvia-inference');

  pills.querySelectorAll('.pill-restart').forEach(function(btn) {
    btn.onclick = function(e) {
      e.stopPropagation();
      vscode.postMessage({ type: 'command', command: btn.dataset.cmd });
    };
  });
}

function pill(label, state, svcName) {
  const dc = dotClass(state);
  const action = (state === 'healthy' || state === 'starting' || state === 'unhealthy')
    ? 'corvia-dev restart ' + svcName
    : 'corvia-dev up';
  return '<div class="pill">' +
    '<div class="pill-dot ' + dc + '"></div>' +
    '<span class="pill-label">' + esc(label) + '</span>' +
    '<span class="pill-restart" data-cmd="' + esc(action) + '">' + SVG_RESTART + '</span>' +
  '</div>';
}

// --- Log helpers ---
function buildLogTabs(managerLogs, serviceLogs) {
  const tabs = {};
  if (managerLogs && managerLogs.length > 0) tabs['manager'] = managerLogs;
  if (serviceLogs) {
    for (const [name, lines] of Object.entries(serviceLogs)) {
      if (lines && lines.length > 0) tabs[name] = lines;
    }
  }
  lastLogData = tabs;
  return tabs;
}

function parseLine(line) {
  let ts = '', level = 'info', levelLabel = 'INFO', msg = line;

  const m = line.match(/^(\d{2}:\d{2}:\d{2}|\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s+(\w+)\s+(.*)/);
  if (m) {
    ts = m[1].includes('T') ? m[1].split('T')[1] : m[1];
    const lvl = m[2].toUpperCase();
    if (lvl === 'ERROR' || lvl === 'ERR') { level = 'error'; levelLabel = 'ERR'; }
    else if (lvl === 'WARN' || lvl === 'WARNING') { level = 'warn'; levelLabel = 'WARN'; }
    else if (lvl === 'DEBUG' || lvl === 'DBUG' || lvl === 'TRACE') { level = 'debug'; levelLabel = 'DBUG'; }
    else { level = 'info'; levelLabel = 'INFO'; }
    msg = m[3];
  } else {
    const m2 = line.match(/^(\w+):\s+(.*)/);
    if (m2) {
      const lvl = m2[1].toUpperCase();
      if (['ERROR', 'ERR', 'WARN', 'WARNING', 'DEBUG', 'INFO'].includes(lvl)) {
        if (lvl === 'ERROR' || lvl === 'ERR') { level = 'error'; levelLabel = 'ERR'; }
        else if (lvl === 'WARN' || lvl === 'WARNING') { level = 'warn'; levelLabel = 'WARN'; }
        else if (lvl === 'DEBUG') { level = 'debug'; levelLabel = 'DBUG'; }
        msg = m2[2];
      }
    }
  }

  return { ts, level, levelLabel, msg };
}

// --- Bind all interactive elements ---
function bindAll() {
  document.querySelectorAll('[data-cmd]').forEach(function(b) {
    b.onclick = function() { vscode.postMessage({ type: 'command', command: b.dataset.cmd }); };
  });

  document.querySelectorAll('[data-action="refresh"]').forEach(function(b) {
    b.onclick = function() { vscode.postMessage({ type: 'refresh' }); };
  });

  document.querySelectorAll('[data-view]').forEach(function(b) {
    b.onclick = function() {
      activeView = b.dataset.view;
      vscode.postMessage({ type: 'refresh' });
    };
  });

  document.querySelectorAll('[data-filter]').forEach(function(b) {
    b.onclick = function() {
      activeFilter = b.dataset.filter;
      applyLogFilters();
      document.querySelectorAll('.log-filter').forEach(function(f) {
        f.classList.toggle('active', f.dataset.filter === activeFilter);
      });
    };
  });

  document.querySelectorAll('[data-log-tab]').forEach(function(b) {
    b.onclick = function() {
      activeLogTab = b.dataset.logTab;
      vscode.postMessage({ type: 'refresh' });
    };
  });

  var searchInput = document.getElementById('logSearchInput');
  if (searchInput) {
    searchInput.oninput = function() {
      searchQuery = searchInput.value;
      applyLogFilters();
    };
  }

  var autoBtn = document.getElementById('autoScrollBtn');
  if (autoBtn) {
    autoBtn.onclick = function() {
      autoScroll = !autoScroll;
      autoBtn.classList.toggle('active', autoScroll);
      if (autoScroll) {
        var output = document.getElementById('logOutput');
        if (output) output.scrollTop = output.scrollHeight;
      }
    };
  }

  document.querySelectorAll('[data-action="clear-logs"]').forEach(function(b) {
    b.onclick = function() {
      var output = document.getElementById('logOutput');
      if (output) output.innerHTML = '<div class="log-empty">Logs cleared</div>';
    };
  });

  document.querySelectorAll('[data-toggle]').forEach(function(t) {
    t.onclick = function() {
      var svc = t.dataset.toggle;
      var isEnabled = t.dataset.enabled === '1';
      var cmd = isEnabled ? 'corvia-dev disable ' + svc : 'corvia-dev enable ' + svc;
      vscode.postMessage({ type: 'command', command: cmd });
    };
  });
}

// --- Filter log lines in-place ---
function applyLogFilters() {
  var lines = document.querySelectorAll('.log-line');
  var q = searchQuery.toLowerCase();
  lines.forEach(function(line) {
    var level = line.querySelector('.log-level');
    var msg = line.querySelector('.log-msg');
    if (!level || !msg) return;
    var lvl = level.textContent.trim().toLowerCase();
    var levelMap = { info: 'info', err: 'error', warn: 'warn', dbug: 'debug' };
    var normalizedLevel = levelMap[lvl] || 'info';
    var levelMatch = activeFilter === 'all' || normalizedLevel === activeFilter;
    var searchMatch = !q || line.textContent.toLowerCase().indexOf(q) !== -1;
    line.classList.toggle('hidden', !levelMatch || !searchMatch);
  });
}

// --- Traces rendering ---
function renderTraces(data) {
  var traces = (data && data.traces) || { spans: {}, recent_events: [] };
  var spans = traces.spans || {};

  // Aggregate per-module stats
  var modStats = {};
  for (var mod in MODULES) { modStats[mod] = { count: 0, count_1h: 0, avg_ms: 0, errors: 0, spanCount: 0 }; }
  var maxCount = 1;
  for (var sname in spans) {
    var m = spanToModule(sname);
    if (!modStats[m]) continue;
    var s = spans[sname];
    modStats[m].count += s.count;
    modStats[m].count_1h += (s.count_1h || 0);
    modStats[m].avg_ms += s.avg_ms * s.count;
    modStats[m].errors += s.errors;
    modStats[m].spanCount++;
  }
  for (var mod in modStats) {
    var ms = modStats[mod];
    ms.avg_ms = ms.count > 0 ? Math.round(ms.avg_ms / ms.count) : 0;
    if (ms.count > maxCount) maxCount = ms.count;
  }
  lastTraceModStats = modStats;
  lastTraceModStats._maxCount = maxCount;

  var html = '<div class="traces-workspace">';

  // Graph panel
  html += '<div class="graph-panel">';
  html += '<div class="graph-toolbar">';
  html += '<div class="mode-switcher">';
  for (var mi = 0; mi < 3; mi++) {
    var modes = ['map', 'dataflow', 'heat'];
    var labels = ['Map', 'Data Flow', 'Heat'];
    html += '<button class="mode-btn' + (traceMode === modes[mi] ? ' active' : '') + '" data-trace-mode="' + modes[mi] + '">' + labels[mi] + '</button>';
  }
  html += '</div>';
  html += '<span class="graph-hint">Click a module to inspect</span>';
  html += '</div>';

  // Canvas
  html += '<div class="graph-canvas" id="graphCanvas">';
  html += '<svg class="edge-layer" id="edgeLayer" style="width:100%;height:100%;position:absolute;top:0;left:0;"></svg>';

  // Nodes
  for (var id in MODULES) {
    var mod = MODULES[id];
    var st = modStats[id] || {};
    var barW = maxCount > 0 ? Math.max(5, Math.round((st.count / maxCount) * 100)) : 5;
    var sel = selectedModule === id ? ' selected' : '';

    var heatCls = '';
    if (traceMode === 'heat') {
      var heatScore = (st.count / maxCount) * 0.6 + (st.errors > 0 ? 0.4 : 0);
      if (heatScore > 0.7) heatCls = ' heat-hot';
      else if (heatScore > 0.3) heatCls = ' heat-warm';
      else heatCls = ' heat-cool';
    }

    var selStyle = selectedModule === id ? 'border-color:var(--' + mod.color + ');' : '';

    html += '<div class="tnode' + sel + heatCls + '" style="left:' + mod.pos[0] + '%;top:' + mod.pos[1] + '%;' + selStyle + '" data-tnode="' + id + '">';
    html += '<div class="tnode-icon" style="background:var(--' + mod.color + '-soft);color:var(--' + mod.color + ');">' + mod.icon + '</div>';
    html += '<div class="tnode-label" style="color:var(--' + mod.color + ');">' + esc(mod.label) + '</div>';
    html += '<div class="tnode-stat">' + formatNum(st.count) + ' ops &middot; ' + st.spanCount + ' spans</div>';
    html += '<div class="tnode-bar"><div class="tnode-bar-fill" style="width:' + barW + '%;background:var(--' + mod.color + ');"></div></div>';
    html += '</div>';
  }

  html += '</div>'; // close graph-canvas
  html += '</div>'; // close graph-panel

  // Detail panel
  html += '<div class="trace-detail">';
  if (!selectedModule) {
    html += '<div class="trace-card"><div class="trace-empty">Select a module to inspect its telemetry</div></div>';
  } else {
    var sm = MODULES[selectedModule];
    var ss = modStats[selectedModule] || {};
    var modColor = sm.color;

    // Module summary card
    html += '<div class="trace-card">';
    html += '<div class="module-hdr">';
    html += '<div class="module-dot" style="background:var(--' + modColor + ');box-shadow:0 0 6px var(--' + modColor + '-soft);"></div>';
    html += '<div><div class="module-name">' + esc(sm.label) + '</div>';
    html += '<div class="module-desc">' + esc(sm.desc) + '</div></div>';
    html += '</div>';
    html += '<div class="mini-stats">';
    html += miniStat(formatNum(ss.count), 'Total');
    html += miniStat(formatNum(ss.count_1h), 'Last hour');
    var avgColor = ss.avg_ms < 50 ? 'var(--mint)' : ss.avg_ms < 150 ? 'var(--peach)' : 'var(--coral)';
    html += miniStat('<span style="color:' + avgColor + '">' + ss.avg_ms + '<span style="font-size:11px;font-weight:500">ms</span></span>', 'Avg latency');
    var errColor = ss.errors === 0 ? 'var(--mint)' : 'var(--coral)';
    html += miniStat('<span style="color:' + errColor + '">' + ss.errors + '</span>', 'Errors');
    html += '</div></div>';

    // Spans card
    var moduleSpans = [];
    for (var sn in spans) {
      if (spanToModule(sn) === selectedModule) {
        moduleSpans.push({ name: sn, stats: spans[sn] });
      }
    }

    html += '<div class="trace-card"><div class="trace-card-hdr"><div class="trace-label">Instrumented Spans</div></div>';
    html += '<div class="trace-card-body">';
    if (moduleSpans.length === 0) {
      html += '<div style="font-size:12px;color:var(--text-dim);padding:8px 0;">No span data available</div>';
    } else {
      for (var si = 0; si < moduleSpans.length; si++) {
        var sp = moduleSpans[si];
        var shortName = sp.name.replace('corvia.', '');
        var fields = SPAN_FIELDS[sp.name] || '';
        var spMs = sp.stats.avg_ms;
        var pillCls = spMs < 50 ? 'span-fast' : spMs < 150 ? 'span-medium' : 'span-slow';
        html += '<div class="span-row"><div>';
        html += '<div class="span-name">' + esc(shortName) + '</div>';
        if (fields) html += '<div class="span-fields">' + esc(fields) + '</div>';
        html += '</div><span class="span-pill ' + pillCls + '">' + Math.round(spMs) + 'ms</span></div>';
      }
    }
    html += '</div></div>';

    // Events card
    var modEvents = (traces.recent_events || []).filter(function(ev) { return ev.module === selectedModule; }).slice(0, 10);
    html += '<div class="trace-card"><div class="trace-card-hdr"><div class="trace-label">Recent Events</div></div>';
    html += '<div class="trace-card-body">';
    if (modEvents.length === 0) {
      html += '<div style="font-size:12px;color:var(--text-dim);padding:8px 0;">No recent events</div>';
    } else {
      for (var ei = 0; ei < modEvents.length; ei++) {
        var ev = modEvents[ei];
        html += '<div class="evt-row">';
        html += '<div class="evt-dot ' + ev.level + '"></div>';
        html += '<span class="evt-msg">' + esc(ev.msg) + '</span>';
        html += '<span class="evt-time">' + esc(ev.ts) + '</span>';
        html += '</div>';
      }
    }
    html += '</div></div>';
  }
  html += '</div>'; // close trace-detail
  html += '</div>'; // close traces-workspace

  return html;
}

function miniStat(valueHtml, label) {
  return '<div class="mini-stat"><div class="mini-stat-val">' + valueHtml + '</div>' +
    '<div class="mini-stat-lbl">' + esc(label) + '</div></div>';
}

function bindTraces() {
  document.querySelectorAll('[data-tnode]').forEach(function(n) {
    n.onclick = function() {
      selectedModule = n.dataset.tnode;
      vscode.postMessage({ type: 'refresh' });
    };
  });

  document.querySelectorAll('[data-trace-mode]').forEach(function(b) {
    b.onclick = function() {
      traceMode = b.dataset.traceMode;
      vscode.postMessage({ type: 'refresh' });
    };
  });
}

function drawEdges() {
  var svg = document.getElementById('edgeLayer');
  var canvas = document.getElementById('graphCanvas');
  if (!svg || !canvas) return;

  var cw = canvas.offsetWidth;
  var ch = canvas.offsetHeight;
  svg.setAttribute('viewBox', '0 0 ' + cw + ' ' + ch);

  // Node center: x is at pos[0]% of canvas (node is centered via CSS transform),
  // y is at pos[1]% + ~55px (half estimated node height)
  var nodeH = 55;
  var paths = '';
  var animations = '';
  for (var i = 0; i < EDGES.length; i++) {
    var e = EDGES[i];
    var fromMod = MODULES[e[0]];
    var toMod = MODULES[e[1]];
    if (!fromMod || !toMod) continue;

    var x1 = (fromMod.pos[0] / 100) * cw;
    var y1 = (fromMod.pos[1] / 100) * ch + nodeH;
    var x2 = (toMod.pos[0] / 100) * cw;
    var y2 = (toMod.pos[1] / 100) * ch + nodeH;
    var mx = (x1 + x2) / 2;

    var pathId = 'edge-' + e[0] + '-' + e[1];
    var d = 'M' + x1 + ',' + y1 + ' C' + mx + ',' + y1 + ' ' + mx + ',' + y2 + ' ' + x2 + ',' + y2;
    paths += '<path id="' + pathId + '" class="edge-path" d="' + d + '"/>';

    if (traceMode === 'dataflow') {
      var color = 'var(--' + fromMod.color + ')';
      // Dynamic duration: busier edges animate faster (1s-6s range)
      var srcStats = lastTraceModStats[e[0]] || {};
      var maxC = lastTraceModStats._maxCount || 1;
      var ratio = (srcStats.count || 0) / maxC;
      var dur = Math.max(1, Math.round(6 - ratio * 5));
      animations += '<circle r="3" fill="' + color + '" style="filter:drop-shadow(0 0 3px ' + color + ')">' +
        '<animateMotion dur="' + dur + 's" repeatCount="indefinite"><mpath href="#' + pathId + '"/></animateMotion>' +
        '</circle>';
    }
  }

  svg.innerHTML = paths + animations;
}

// Initial binding
bindAll();
</script>
</body>
</html>`;
}

function deactivate() {
    if (pollTimer) clearInterval(pollTimer);
}

module.exports = { activate, deactivate };
