#!/usr/bin/env node

import fs from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const catalogDir = path.join(rootDir, ".catalog");
const csvPath = path.join(catalogDir, "papers.csv");
const templatePath = path.join(catalogDir, "viewer-template.html");
const outputPath = path.join(rootDir, "papers.html");
const repositoryId = createHash("sha256").update(
  process.platform === "win32" ? rootDir.toLocaleLowerCase() : rootDir
).digest("hex").slice(0, 12);
const viewerPort = 18_000 + (Number.parseInt(repositoryId.slice(0, 8), 16) % 10_000);
const viewerUrl = `http://127.0.0.1:${viewerPort}/papers.html`;
const headers = [
  "category",
  "subcategory",
  "venue",
  "year",
  "track",
  "workshop",
  "presentation",
  "title",
  "authors",
  "affiliation",
  "summary",
  "novelty",
  "site",
  "added_at",
  "file",
];
const withLegacyStatus = (sourceHeaders) => {
  const copy = [...sourceHeaders];
  copy.splice(copy.indexOf("presentation") + 1, 0, "status");
  return copy;
};
const legacyHeaderVariants = [
  withLegacyStatus(headers),
  withLegacyStatus(headers.filter((header) => header !== "added_at")),
  withLegacyStatus(headers.filter((header) => !["novelty", "added_at"].includes(header))),
  withLegacyStatus(headers.filter((header) => !["subcategory", "novelty", "added_at"].includes(header))),
];

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }

  if (quoted) throw new Error("CSV contains an unterminated quoted field.");
  if (field.length || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows.filter((item) => item.some((value) => value.length));
}

await fs.mkdir(catalogDir, { recursive: true });
try {
  await fs.access(csvPath);
} catch {
  await fs.writeFile(csvPath, headers.join(",") + "\n", "utf8");
}

const csvText = await fs.readFile(csvPath, "utf8");
const rows = parseCsv(csvText);
const actualHeaders = rows.shift() || [];
const sourceHeaders = [headers, ...legacyHeaderVariants].find(
  (candidate) => actualHeaders.join(",") === candidate.join(",")
);
if (!sourceHeaders) {
  throw new Error(`Unexpected CSV headers: ${actualHeaders.join(",")}`);
}

const isLegacyCatalog = sourceHeaders !== headers;
const localTimestamp = (date) => {
  const parts = new Intl.DateTimeFormat("sv-SE", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day} ${value.hour}:${value.minute}:${value.second}`;
};
const migrationTimestamp = localTimestamp(new Date());
const records = rows.map((values, rowIndex) => {
  if (values.length !== sourceHeaders.length) {
    throw new Error(`CSV row ${rowIndex + 2} has ${values.length} fields; expected ${sourceHeaders.length}.`);
  }
  const source = Object.fromEntries(sourceHeaders.map((header, index) => [header, values[index]]));
  const presentation = ["Preprint", "Poster", "Spotlight", "Oral"].includes(source.presentation)
    ? source.presentation
    : String(source.status).includes("Preprint") || source.venue === "Technical Report"
      ? "Preprint"
      : source.venue === "OSDI" ? "Oral" : "Poster";
  return Object.fromEntries(headers.map((header) => [
    header,
    header === "added_at"
      ? (source[header] || migrationTimestamp)
      : header === "presentation" ? presentation : (source[header] ?? ""),
  ]));
});

if (isLegacyCatalog) {
  const quote = (value) => `"${String(value ?? "").replaceAll('"', '""').replace(/\r?\n/g, " ")}"`;
  const migratedRows = records.map((record) =>
    headers.map((header) => header === "year" ? record[header] : quote(record[header])).join(",")
  );
  await fs.writeFile(
    csvPath,
    headers.join(",") + "\n" + (migratedRows.length ? migratedRows.join("\n") + "\n" : ""),
    "utf8"
  );
}

const template = await fs.readFile(templatePath, "utf8");
if (
  !template.includes("__PAPER_CATALOG_JSON__") ||
  !template.includes("__GENERATED_AT__") ||
  !template.includes("__PAPER_VIEWER_URL__") ||
  !template.includes("/* CATALOG_DATA_START */") ||
  !template.includes("/* CATALOG_DATA_END */")
) {
  throw new Error("Viewer template markers are missing.");
}

const safeJson = JSON.stringify(records)
  .replaceAll("<", "\\u003c")
  .replaceAll("\u2028", "\\u2028")
  .replaceAll("\u2029", "\\u2029");
const generatedAt = new Intl.DateTimeFormat("ko-KR", {
  dateStyle: "medium",
  timeStyle: "short",
}).format(new Date()).replaceAll('"', '\\"');

const output = template
  .replace("__PAPER_CATALOG_JSON__", safeJson)
  .replace("__GENERATED_AT__", generatedAt)
  .replace("__PAPER_VIEWER_URL__", viewerUrl);
const tempPath = outputPath + ".tmp";
await fs.writeFile(tempPath, output, "utf8");
await fs.rename(tempPath, outputPath);

console.log(`Generated ${path.relative(rootDir, outputPath)} with ${records.length} paper(s).`);
