import readline from "node:readline";

const mode = process.argv[2];
const model = (id, efforts = ["low", "high", "xhigh"]) => ({
  model: id,
  displayName: id,
  supportedReasoningEfforts: efforts.map(reasoningEffort => ({ reasoningEffort })),
  defaultReasoningEffort: efforts[0],
});
const respond = (id, result) => process.stdout.write(JSON.stringify({ id, result }) + "\n");

readline.createInterface({ input: process.stdin }).on("line", line => {
  const request = JSON.parse(line);
  if (mode === "timeout") return;
  if (mode === "exit") return process.exit(1);
  if (request.method === "initialize") {
    if (mode === "malformed") return process.stdout.write("not json\n");
    respond(request.id, { userAgent: "fixture" });
  } else if (request.method === "initialized") {
    return;
  } else if (request.method === "model/list") {
    if (request.params.includeHidden !== false) process.exit(2);
    if (mode === "rpc-error") return process.stdout.write(JSON.stringify({ id: request.id, error: { code: -1 } }) + "\n");
    if (mode === "empty") return respond(request.id, { data: [], nextCursor: null });
    if (mode === "cycle") return respond(request.id, { data: [model("gpt-future")], nextCursor: "same" });
    if (mode === "oversized") return process.stdout.write("x".repeat(2_000_001));
    if (!request.params.cursor) {
      // Forward-compatible IDs, hidden and malformed rows, and a default unrelated to our recommendation.
      respond(request.id, {
        data: [
          { ...model("gpt-6-sol"), isDefault: true },
          { ...model("gpt-hidden"), hidden: true },
          null, {}, { model: "bad model" }, { model: "bad-efforts", supportedReasoningEfforts: {} },
          { ...model("gpt-6-luna", ["low", "high", "xhigh", "max"]), defaultReasoningEffort: "unsupported" },
        ],
        nextCursor: "page2",
      });
    } else {
      process.stdout.write(JSON.stringify({ method: "notification", params: {} }) + "\n");
      const response = JSON.stringify({ id: request.id, result: {
        data: [model("gpt-6-luna", ["low", "high", "xhigh", "max"]), model("future/model-v2", ["none", "ultra"])], nextCursor: null,
      } }) + "\n";
      process.stdout.write(response.slice(0, 15));
      setTimeout(() => process.stdout.write(response.slice(15)), 5);
    }
  } else {
    // A catalog lookup must never initiate inference.
    process.exit(3);
  }
});
