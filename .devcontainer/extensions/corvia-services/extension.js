const vscode = require("vscode");

let statusBarItem;
let panel;
let pollTimer;

const POLL_INTERVAL = 3000;
const API_BASE = "http://localhost:8020";
const DASHBOARD_URL = "http://localhost:8021";

function activate(context) {
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 50);
    statusBarItem.command = "corvia.openDashboard";
    statusBarItem.text = "$(loading~spin) Corvia";
    statusBarItem.show();
    context.subscriptions.push(statusBarItem);

    context.subscriptions.push(
        vscode.commands.registerCommand("corvia.openDashboard", () => openDashboard(context))
    );

    pollStatus();
    pollTimer = setInterval(pollStatus, POLL_INTERVAL);
    context.subscriptions.push({ dispose: () => clearInterval(pollTimer) });
}

async function pollStatus() {
    try {
        const resp = await fetch(`${API_BASE}/api/dashboard/status`);
        const data = await resp.json();
        const allHealthy = (data.services || []).every(s => s.state === "healthy");
        const anyDown = (data.services || []).some(s => s.state !== "healthy");

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
            .map(s => `${s.name}: ${s.state}`)
            .join(" | ");
        statusBarItem.tooltip = svcSummary;
    } catch {
        statusBarItem.text = "$(error) Corvia";
        statusBarItem.backgroundColor = new vscode.ThemeColor("statusBarItem.errorBackground");
        statusBarItem.tooltip = "corvia-server not responding";
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

    panel.webview.html = getWebviewContent();
    panel.onDidDispose(() => { panel = undefined; }, null, context.subscriptions);
}

function getWebviewContent() {
    return `<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Security-Policy"
        content="default-src 'none'; frame-src ${DASHBOARD_URL}; style-src 'unsafe-inline';" />
  <style>
    body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; }
    iframe { width: 100%; height: 100%; border: none; }
  </style>
</head>
<body>
  <iframe src="${DASHBOARD_URL}" />
</body>
</html>`;
}

function deactivate() {
    if (pollTimer) clearInterval(pollTimer);
}

module.exports = { activate, deactivate };
