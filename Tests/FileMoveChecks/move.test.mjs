import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("../../Sources/PaperLibrary/Resources/LibrarySeed/Automation/paper-organizer.mjs", import.meta.url));

test("organizer preserves unknown metadata when normalizing a recovered catalog", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "paper-library-recovered-"));
  try {
    fs.mkdirSync(path.join(root, "Papers", "Systems"), { recursive: true });
    fs.mkdirSync(path.join(root, "Catalog"));
    const catalog = path.join(root, "Catalog", "papers.csv");
    const headers = "category,subcategory,venue,year,track,workshop,presentation,title,authors,affiliation,summary,novelty,site,added_at,file\n";
    const record = '"Systems","","",,"","","","Recovered Title","","","Personal note","","","2026-11-01","Papers/Systems/original.pdf"\n';
    fs.writeFileSync(catalog, headers + record);
    fs.writeFileSync(path.join(root, "Papers", "Systems", "original.pdf"), "original PDF bytes");
    const normalize = () => spawnSync(process.execPath, [script, "normalize", "--root", root], { encoding: "utf8" });
    const result = normalize();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(catalog, "utf8"), headers + record.replace("original.pdf", "Recovered Title.pdf"));
    assert.equal(fs.readFileSync(path.join(root, "Papers", "Systems", "Recovered Title.pdf"), "utf8"), "original PDF bytes");
    assert.equal(normalize().status, 0);
    assert.equal(fs.readFileSync(catalog, "utf8").split("\n").length, 3);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function normalizationFixture(records) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "paper-library-normalize-"));
  fs.mkdirSync(path.join(root, "Papers", "Systems"), { recursive: true });
  fs.mkdirSync(path.join(root, "Catalog"));
  const headers = "category,subcategory,venue,year,track,workshop,presentation,title,authors,affiliation,summary,novelty,site,added_at,file\n";
  const rows = records.map(({ title, name }) =>
    `"Systems","","",,"","","","${title}","","","","","","2026-11-01","Papers/Systems/${name}"\n`
  ).join("");
  const catalog = path.join(root, "Catalog", "papers.csv");
  fs.writeFileSync(catalog, headers + rows);
  return { root, catalog, originalCatalog: headers + rows };
}

test("Finish Setup succeeds and can be repeated without renaming existing PDFs", () => {
  const { root, catalog, originalCatalog } = normalizationFixture([{ title: "New Title", name: "Original Title.pdf" }]);
  try {
    const paper = path.join(root, "Papers", "Systems", "Original Title.pdf");
    fs.writeFileSync(paper, "existing PDF contents");
    fs.mkdirSync(path.join(root, "Automation"));
    fs.writeFileSync(path.join(root, "Automation", "PAPER_ORGANIZER.md"), "Test organizer instructions");
    const mockModels = new URL("../ModelCatalogChecks/mock-app-server.mjs", import.meta.url).href;
    const codex = path.join(root, "mock-codex.mjs");
    fs.writeFileSync(codex, `#!${process.execPath}\nif (process.argv[2] === "app-server") { process.argv[2] = "normal"; await import(${JSON.stringify(mockModels)}); } else { console.log("Codex test CLI is ready"); }\n`, { mode: 0o700 });
    // Scope runtime files and device identity to this fixture, including on macOS.
    const runner = path.join(root, "install-fixture.mjs");
    fs.writeFileSync(runner, `import os from "node:os"; os.homedir = () => ${JSON.stringify(root)}; await import(${JSON.stringify(new URL("../../Sources/PaperLibrary/Resources/LibrarySeed/Automation/paper-organizer.mjs", import.meta.url).href)});`);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const result = spawnSync(process.execPath, [runner, "install", "--root", root, "--codex", codex], { encoding: "utf8", timeout: 15000 });
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /Configured Paper Organizer/);
      assert.equal(fs.readFileSync(catalog, "utf8"), originalCatalog);
      assert.equal(fs.readFileSync(paper, "utf8"), "existing PDF contents");
      assert.deepEqual(fs.readdirSync(path.dirname(paper)), ["Original Title.pdf"]);
      const settings = JSON.parse(fs.readFileSync(path.join(root, "Catalog", "organizer-settings.json"), "utf8"));
      assert.equal(settings.model, "gpt-6-luna");
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("setup normalization preserves a case-insensitive alias of the same PDF", () => {
  const { root, catalog, originalCatalog } = normalizationFixture([{ title: "Medusa", name: "MEDUSA.pdf" }]);
  try {
    const source = path.join(root, "Papers", "Systems", "MEDUSA.pdf");
    const alias = path.join(root, "Papers", "Systems", "Medusa.pdf");
    fs.writeFileSync(source, "original PDF");
    // On case-sensitive test volumes, make the same-file alias explicit.
    if (!fs.existsSync(alias)) fs.linkSync(source, alias);
    const inode = fs.statSync(source).ino;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const result = spawnSync(process.execPath, [script, "normalize", "--root", root], { encoding: "utf8" });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(fs.readFileSync(catalog, "utf8"), originalCatalog);
      assert.equal(fs.statSync(source).ino, inode);
      assert.equal(fs.readFileSync(alias, "utf8"), "original PDF");
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("setup normalization keeps two papers with the same title at their existing paths", () => {
  const { root, catalog, originalCatalog } = normalizationFixture([
    { title: "Shared Title", name: "first.pdf" },
    { title: "Shared Title", name: "second.pdf" },
  ]);
  try {
    fs.writeFileSync(path.join(root, "Papers", "Systems", "first.pdf"), "first PDF");
    fs.writeFileSync(path.join(root, "Papers", "Systems", "second.pdf"), "second PDF");
    const result = spawnSync(process.execPath, [script, "normalize", "--root", root], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(catalog, "utf8"), originalCatalog);
    assert.equal(fs.readFileSync(path.join(root, "Papers", "Systems", "first.pdf"), "utf8"), "first PDF");
    assert.equal(fs.readFileSync(path.join(root, "Papers", "Systems", "second.pdf"), "utf8"), "second PDF");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("setup normalization does not overwrite or adopt an unlisted destination PDF", () => {
  const { root, catalog, originalCatalog } = normalizationFixture([{ title: "Existing", name: "source.pdf" }]);
  try {
    fs.writeFileSync(path.join(root, "Papers", "Systems", "source.pdf"), "catalog PDF");
    fs.writeFileSync(path.join(root, "Papers", "Systems", "Existing.pdf"), "unlisted PDF");
    const result = spawnSync(process.execPath, [script, "normalize", "--root", root], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(catalog, "utf8"), originalCatalog);
    assert.equal(fs.readFileSync(path.join(root, "Papers", "Systems", "source.pdf"), "utf8"), "catalog PDF");
    assert.equal(fs.readFileSync(path.join(root, "Papers", "Systems", "Existing.pdf"), "utf8"), "unlisted PDF");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

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
