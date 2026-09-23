import { spawn } from "node:child_process";

export const RECOMMENDED_MODEL = "gpt-6-luna";
export const RECOMMENDED_REASONING = "xhigh";
export const validModelID = (value) => typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/.test(value);
export const validReasoning = (value) => typeof value === "string" && /^[a-z][a-z0-9_-]{0,31}$/.test(value);

// Only requests catalog metadata. No thread/turn is started and no inference is run.
export function fetchCodexModels(codex, { cwd, timeoutMs = 12_000, args = ["app-server"] } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(codex, args, {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
      shell: process.platform === "win32" && /\.(cmd|bat)$/i.test(codex),
    });
    let buffer = "";
    let totalBytes = 0;
    let requestID = 1;
    let initialized = false;
    let settled = false;
    let killTimer;
    const cursors = new Set();
    const models = new Map();
    const timer = setTimeout(() => finish(new Error("Codex model lookup timed out. Showing the last saved model list.")), timeoutMs);

    function finish(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      child.stdin.end();
      child.kill();
      killTimer = setTimeout(() => child.kill("SIGKILL"), 500);
      killTimer.unref();
      if (error) reject(error);
      else resolve({ version: 1, codexPath: codex, fetchedAt: new Date().toISOString(), models: [...models.values()] });
    }

    function send(message) {
      if (!settled) child.stdin.write(JSON.stringify(message) + "\n");
    }

    function requestPage(cursor) {
      requestID += 1;
      send({ id: requestID, method: "model/list", params: { limit: 100, includeHidden: false, ...(cursor ? { cursor } : {}) } });
    }

    child.on("error", () => finish(new Error("Codex CLI could not be started. Check the automation setup.")));
    child.stdin.on("error", () => finish(new Error("Codex model lookup was interrupted. Update Codex CLI and try again.")));
    child.stderr.on("data", () => {}); // Drain diagnostics without mixing them into JSON output.
    child.on("close", () => {
      clearTimeout(killTimer);
      finish(new Error("Codex exited before returning its model list. Update Codex CLI and try again."));
    });
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      if (settled) return;
      totalBytes += Buffer.byteLength(chunk);
      if (totalBytes > 2_000_000) return finish(new Error("Codex returned an oversized model list."));
      buffer += chunk;
      let boundary;
      while (!settled && (boundary = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 1);
        let message;
        try { message = JSON.parse(line); }
        catch { return finish(new Error("Codex returned an invalid model-list response.")); }
        if (!message || message.id !== requestID || (!("result" in message) && !("error" in message))) continue;
        if (message.error) return finish(new Error("Codex could not list models. Check sign-in and update Codex CLI, then try again."));
        if (!initialized) {
          initialized = true;
          send({ method: "initialized" });
          requestPage();
          continue;
        }
        if (!Array.isArray(message.result?.data)) return finish(new Error("Codex returned an invalid model list."));
        for (const model of message.result.data) {
          if (!model || model.hidden || !validModelID(model.model) || !Array.isArray(model.supportedReasoningEfforts)) continue;
          const efforts = [...new Set(model.supportedReasoningEfforts.map(item => item?.reasoningEffort).filter(validReasoning))];
          if (!efforts.length) continue;
          models.set(model.model, {
            id: model.model,
            displayName: typeof model.displayName === "string" && model.displayName.trim() ? model.displayName.trim() : model.model,
            reasoningEfforts: efforts,
            defaultReasoningEffort: efforts.includes(model.defaultReasoningEffort) ? model.defaultReasoningEffort : efforts[0],
          });
        }
        const cursor = message.result.nextCursor;
        if (cursor != null) {
          if (typeof cursor !== "string" || !cursor || cursors.has(cursor) || cursors.size >= 20) {
            return finish(new Error("Codex returned invalid model-list pagination."));
          }
          cursors.add(cursor);
          requestPage(cursor);
        } else {
          finish(models.size ? null : new Error("No selectable Codex models were returned. Check sign-in and update Codex CLI."));
        }
      }
    });
    send({ id: requestID, method: "initialize", params: { clientInfo: { name: "paper_library", title: "Paper Library", version: "0.4.0" } } });
  });
}

export function validateModelSelection(catalog, model, reasoning) {
  const selected = catalog.models.find(item => item.id === model);
  if (!selected) throw new Error(`${model} is not available in the configured Codex CLI. Update Codex CLI or choose another model.`);
  if (!selected.reasoningEfforts.includes(reasoning)) throw new Error(`${model} does not support ${reasoning} reasoning in this Codex CLI.`);
}
