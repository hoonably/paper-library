import assert from "node:assert/strict";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { fetchCodexModels, validateModelSelection, validModelID, validReasoning, RECOMMENDED_MODEL, RECOMMENDED_REASONING } from "../../Sources/PaperLibrary/Resources/LibrarySeed/Automation/codex-models.mjs";

const fixture = fileURLToPath(new URL("./mock-app-server.mjs", import.meta.url));
const fetchFixture = (mode, timeoutMs = 2000) => fetchCodexModels(process.execPath, { args: [fixture, mode], timeoutMs });

test("defaults are Luna Extra High, independent of the CLI default", () => {
  assert.equal(RECOMMENDED_MODEL, "gpt-6-luna");
  assert.equal(RECOMMENDED_REASONING, "xhigh");
  assert.ok(validModelID("future/model-v2"));
  assert.ok(!validModelID("--unsafe"));
  assert.ok(!validModelID("bad model"));
  assert.ok(validReasoning("ultra"));
  assert.ok(!validReasoning("--high"));
});

test("catalog handshake, pagination, chunking, hidden rows, deduplication and model-specific reasoning", async () => {
  const catalog = await fetchFixture("normal");
  assert.deepEqual(catalog.models.map(model => model.id), ["gpt-6-sol", "gpt-6-luna", "future/model-v2"]);
  assert.equal(catalog.codexPath, process.execPath);
  assert.ok(!Number.isNaN(Date.parse(catalog.fetchedAt)));
  assert.equal(catalog.models[2].defaultReasoningEffort, "none");
  validateModelSelection(catalog, RECOMMENDED_MODEL, RECOMMENDED_REASONING);
  validateModelSelection(catalog, "future/model-v2", "ultra");
  assert.throws(() => validateModelSelection(catalog, "missing-model", "xhigh"), /not available/);
  assert.throws(() => validateModelSelection(catalog, "gpt-6-luna", "ultra"), /does not support/);
});

for (const [mode, pattern] of [
  ["malformed", /invalid/], ["exit", /exited/], ["empty", /No selectable/],
  ["cycle", /pagination/], ["rpc-error", /could not list/], ["oversized", /oversized/],
]) {
  test(`catalog lookup rejects ${mode}`, async () => {
    await assert.rejects(fetchFixture(mode), pattern);
  });
}

test("catalog lookup has a bounded timeout", async () => {
  await assert.rejects(fetchFixture("timeout", 100), /timed out/);
});

test("catalog lookup reports a missing CLI", async () => {
  await assert.rejects(fetchCodexModels("/nonexistent/paper-library-test-codex"), /could not be started/);
});
