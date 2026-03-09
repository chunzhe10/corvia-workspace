const vscode = require("vscode");
const { exec } = require("child_process");

let statusBarItem;
let panel;
let pollTimer;

const POLL_INTERVAL = 10000;

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
        { enableScripts: true }
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
    return `<!DOCTYPE html>
<html>
<head>
<style>
    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); padding: 16px; }
    .card { border: 1px solid var(--vscode-panel-border); border-radius: 6px; padding: 12px; margin: 8px 0; }
    .healthy { border-left: 4px solid #4caf50; }
    .unhealthy, .crashed { border-left: 4px solid #f44336; }
    .stopped { border-left: 4px solid #666; }
    .starting { border-left: 4px solid #ff9800; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 8px; }
    .name { font-weight: bold; }
    .state { opacity: 0.8; font-size: 0.9em; }
    .actions { margin-top: 16px; }
    button {
        background: var(--vscode-button-background); color: var(--vscode-button-foreground);
        border: none; padding: 6px 14px; border-radius: 4px; cursor: pointer; margin: 4px;
    }
    button:hover { background: var(--vscode-button-hoverBackground); }
    .config { opacity: 0.8; margin-top: 12px; }
    .logs { margin-top: 12px; font-family: monospace; font-size: 0.85em; white-space: pre-wrap; max-height: 200px; overflow-y: auto; }
    h2 { margin: 16px 0 8px; }
    .none { opacity: 0.5; }
</style>
</head>
<body>
<h1>Corvia Dashboard</h1>
<div id="content"><p class="none">Loading...</p></div>
<script>
    const vscode = acquireVsCodeApi();

    window.addEventListener("message", (e) => {
        if (e.data.type === "status") render(e.data.data);
    });

    function render(data) {
        const el = document.getElementById("content");
        if (!data) { el.innerHTML = '<p class="none">corvia-dev not responding</p>'; return; }

        let html = "<h2>Services</h2><div class='grid'>";
        for (const svc of data.services || []) {
            const port = svc.port ? ":" + svc.port : "";
            const pid = svc.pid ? " pid " + svc.pid : "";
            html += '<div class="card ' + svc.state + '">';
            html += '<div class="name">' + svc.name + port + '</div>';
            html += '<div class="state">' + svc.state + pid + '</div>';
            html += "</div>";
        }
        html += "</div>";

        html += '<h2>Config</h2><div class="config">';
        html += "Embedding: " + data.config.embedding_provider + "<br>";
        html += "Merge: " + data.config.merge_provider + "<br>";
        html += "Storage: " + data.config.storage + "</div>";

        html += '<h2>Actions</h2><div class="actions">';
        html += btn("Status", "corvia-dev status");
        html += btn("Use Ollama", "corvia-dev use ollama");
        html += btn("Use Corvia-Inference", "corvia-dev use corvia-inference");
        html += btn("Enable coding-llm", "corvia-dev enable coding-llm");
        html += btn("Restart", "corvia-dev restart");
        html += btn("Refresh", null, "refresh");
        html += "</div>";

        if (data.logs && data.logs.length) {
            html += '<h2>Logs</h2><div class="logs">' + data.logs.join("\\n") + "</div>";
        }

        el.innerHTML = html;
        el.querySelectorAll("[data-cmd]").forEach((b) => {
            b.onclick = () => vscode.postMessage({ type: "command", command: b.dataset.cmd });
        });
        el.querySelectorAll("[data-action]").forEach((b) => {
            b.onclick = () => vscode.postMessage({ type: b.dataset.action });
        });
    }

    function btn(label, cmd, action) {
        if (action) return '<button data-action="' + action + '">' + label + "</button>";
        return '<button data-cmd="' + cmd + '">' + label + "</button>";
    }
</script>
</body>
</html>`;
}

function deactivate() {
    if (pollTimer) clearInterval(pollTimer);
}

module.exports = { activate, deactivate };
