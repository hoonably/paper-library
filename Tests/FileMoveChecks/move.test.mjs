import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("../../Sources/PaperLibrary/Resources/LibrarySeed/Automation/paper-organizer.mjs", import.meta.url));

function place(root, from, to) {
  return spawnSync(process.execPath, [script, "place", "--root", root, "--file", from, "--to", to], {
    encoding: "utf8",
  });
}

test("places a waiting PDF at its final title in one move", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "paper-library-move-"));
  try {
    fs.mkdirSync(path.join(root, "Waiting"));
    fs.mkdirSync(path.join(root, "Papers"));
    const source = path.join(root, "Waiting", "2603.04733v3.pdf");
    const relative = "Papers/Computer Vision/FOZO： Forward-Only Zeroth-Order Prompt Optimization.pdf";
    const destination = path.join(root, ...relative.split("/"));
    fs.writeFileSync(source, "%PDF-1.4 fixture");

    const result = place(root, "Waiting/2603.04733v3.pdf", relative);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).moved, relative);
    assert.equal(fs.existsSync(source), false);
    assert.equal(fs.readFileSync(destination, "utf8"), "%PDF-1.4 fixture");
    assert.deepEqual(fs.readdirSync(path.dirname(destination)), [path.basename(destination)]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("a destination collision never deletes or renames the source", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "paper-library-move-"));
  try {
    fs.mkdirSync(path.join(root, "Waiting"));
    fs.mkdirSync(path.join(root, "Papers", "Systems"), { recursive: true });
    const source = path.join(root, "Waiting", "original.pdf");
    const destination = path.join(root, "Papers", "Systems", "Final.pdf");
    fs.writeFileSync(source, "source");
    fs.writeFileSync(destination, "existing");

    const result = place(root, "Waiting/original.pdf", "Papers/Systems/Final.pdf");
    assert.notEqual(result.status, 0);
    assert.equal(fs.readFileSync(source, "utf8"), "source");
    assert.equal(fs.readFileSync(destination, "utf8"), "existing");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("reclassifies an existing PDF directly and rejects paths outside Papers", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "paper-library-move-"));
  try {
    const sourceDirectory = path.join(root, "Papers", "Language Models");
    fs.mkdirSync(sourceDirectory, { recursive: true });
    const source = path.join(sourceDirectory, "Paper.pdf");
    const relative = "Papers/Specdec/Speculative Decoding/Paper.pdf";
    fs.writeFileSync(source, "paper bytes");

    const outside = place(root, "Papers/Language Models/Paper.pdf", "../outside.pdf");
    assert.notEqual(outside.status, 0);
    assert.equal(fs.existsSync(source), true);

    const result = place(root, "Papers/Language Models/Paper.pdf", relative);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(source), false);
    assert.equal(fs.readFileSync(path.join(root, ...relative.split("/")), "utf8"), "paper bytes");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("moves through the managed Papers link and blocks nested links outside it", () => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), "paper-library-public-move-"));
  try {
    const root = path.join(base, "Application Support");
    const documents = path.join(base, "Documents", "Papers");
    fs.mkdirSync(path.join(root, "Waiting"), { recursive: true });
    fs.mkdirSync(documents, { recursive: true });
    fs.symlinkSync(documents, path.join(root, "Papers"), "dir");
    fs.writeFileSync(path.join(root, "Waiting", "arxiv.pdf"), "original PDF bytes");

    const result = place(root, "Waiting/arxiv.pdf", "Papers/Systems/Final.pdf");
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).moved, "Papers/Systems/Final.pdf");
    assert.equal(fs.readFileSync(path.join(documents, "Systems", "Final.pdf"), "utf8"), "original PDF bytes");

    const outside = path.join(base, "outside");
    fs.mkdirSync(outside);
    fs.symlinkSync(outside, path.join(documents, "Escape"), "dir");
    fs.writeFileSync(path.join(root, "Waiting", "blocked.pdf"), "preserved");
    const blocked = place(root, "Waiting/blocked.pdf", "Papers/Escape/New/Blocked.pdf");
    assert.notEqual(blocked.status, 0);
    assert.equal(fs.existsSync(path.join(root, "Waiting", "blocked.pdf")), true);
    assert.deepEqual(fs.readdirSync(outside), []);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});
