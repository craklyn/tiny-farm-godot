/* Evidence shown in both the Decisions pane and a direct work review. The
   deliverable record names the version under review; attachments are display
   material and do not silently become proof of that version. */
"use strict";

function reviewMediaHref(value) {
  const links = reviewEvidenceLinks({deliverable: {evidence: [{path: value}]}});
  return links.length ? links[0].href : "";
}

function reviewMediaKind(entry, href) {
  const type = String(entry.type || entry.kind || "").toLowerCase();
  if (["animation", "video", "audio", "image", "copy", "numeric"].includes(type)) return type;
  const path = href.split(/[?#]/)[0].toLowerCase();
  if (/\.(gif|apng|webp)$/.test(path)) return "animation";
  if (/\.(mp4|webm|mov)$/.test(path)) return "video";
  if (/\.(ogg|mp3|wav|m4a)$/.test(path)) return "audio";
  if (/\.(png|jpe?g|svg)$/.test(path)) return "image";
  return "link";
}

function reviewArtifactEntries(item) {
  const raw = (item && item.deliverable && item.deliverable.evidence) || [];
  if (!Array.isArray(raw)) return [];
  return raw.flatMap(entry => {
    if (!entry || typeof entry !== "object") return [];
    const links = reviewEvidenceLinks({deliverable: {evidence: [entry]}});
    if (!links.length) return [];
    const href = links[0].href;
    return [{...entry, href, label: links[0].label, kind: reviewMediaKind(entry, href)}];
  });
}

function reviewLegacyAnimation(item) {
  if (!item || item.source !== "anim_lab") return null;
  const match = /^Open #\/design\/anim\/([a-z0-9_]{1,64}) and watch it at both sizes$/.exec(item.first_action || "");
  if (!match) return null;
  return {href: `#/design/anim/${match[1]}`, label: `Open ${match[1].replaceAll("_", " ")} in the Animation Lab`,
    legacy: true};
}

function reviewHeadingArtifact(item) {
  const first = reviewArtifactEntries(item)[0] || reviewLegacyAnimation(item);
  if (!first) return "";
  return ` <a class="review-heading-link" href="${esc(first.href)}">${esc(first.label)}</a>`;
}

function reviewMediaCard(entry, label) {
  const name = label || entry.label || "Result";
  const href = entry.href;
  const role = String(entry.role || "").trim();
  let media = "";
  if (entry.kind === "animation" || entry.kind === "image")
    media = `<img src="${esc(href)}" alt="${esc(name)}" loading="lazy">`;
  else if (entry.kind === "video")
    media = `<video src="${esc(href)}" controls preload="metadata" playsinline aria-label="${esc(name)}"></video>`;
  else if (entry.kind === "audio")
    media = `<audio src="${esc(href)}" controls preload="metadata" aria-label="${esc(name)}"></audio>`;
  else if (entry.kind === "copy")
    media = `<div class="review-copy">${esc(entry.text || "")}</div>`;
  else if (entry.kind === "numeric" && Array.isArray(entry.rows))
    media = reviewNumberTable(entry.rows);
  return `<figure class="review-media"><figcaption>${role ? `<span class="review-role">${esc(role)}</span> ` : ""}${esc(name)}</figcaption>${media}
    <a href="${esc(href)}">Open artifact</a></figure>`;
}

function reviewNumberTable(rows) {
  const valid = rows.filter(r => r && typeof r === "object");
  if (!valid.length) return "";
  return `<table class="review-numbers"><thead><tr><th scope="col">Measure</th><th scope="col">Current</th><th scope="col">Proposed</th></tr></thead><tbody>${valid.map(r =>
    `<tr><th scope="row">${esc(r.label || "")}</th><td>${esc(r.current ?? "—")}</td><td>${esc(r.proposed ?? "—")}</td></tr>`).join("")}</tbody></table>`;
}

function reviewComparison(item, attachments = []) {
  const entries = reviewArtifactEntries(item);
  const legacy = reviewLegacyAnimation(item);
  const display = [];
  let group = "";
  for (const att of attachments || []) {
    if (att && att.type === "heading") { group = String(att.caption || ""); continue; }
    if (!att || !["audio", "video", "image"].includes(att.type)) continue;
    const href = reviewMediaHref(att.src);
    if (href) display.push({href, label: att.caption || "Candidate", kind: reviewMediaKind(att, href),
      role: att.role || att.tag || "", group});
  }
  const media = [...entries.filter(e => e.kind !== "link"), ...display.filter(e => !entries.some(a => a.href === e.href))];
  const comparison = item && item.deliverable && item.deliverable.comparison;
  const rows = comparison && Array.isArray(comparison.rows) ? comparison.rows : [];
  const copy = comparison && Array.isArray(comparison.copy) ? comparison.copy : [];
  if (!entries.length && !display.length && !legacy && !rows.length && !copy.length) return "";
  const version = item && item.deliverable && item.deliverable.reviewed_version;
  const versionLabel = version ? `Reviewed version: ${esc(version)}` : "Reviewed version was not pinned in this card.";
  const creation = item && item.deliverable && item.deliverable.created_at;
  const evidenceLinks = entries.filter(e => e.kind === "link").map(e =>
    `<a href="${esc(e.href)}">${esc(e.label)}</a>`).join(" · ");
  return `<section class="review-evidence" aria-label="Result evidence">
    <h4>Result to review</h4>
    <p class="review-provenance">${creation ? `Created: ${esc(creation)} · ` : ""}Displayed here: ${media.length ? "playable or readable evidence" : "linked artifact"} · ${versionLabel}</p>
    ${legacy ? `<p class="review-version-gap"><a href="${esc(legacy.href)}">${esc(legacy.label)}</a> · This opens the live Lab result; this older card does not identify the exact render originally reviewed.</p>` : ""}
    ${media.length ? [...new Set(media.map(e => e.group || ""))].map(name =>
      `<div class="review-media-group">${name ? `<h5>${esc(name)}</h5>` : ""}<div class="review-media-grid">${media.filter(e => (e.group || "") === name).map(e => reviewMediaCard(e)).join("")}</div></div>`).join("") : ""}
    ${copy.length ? `<div class="review-copy-grid">${copy.map(e => `<div><h5>${esc(e.label || "Version")}</h5><div class="review-copy">${esc(e.text || "")}</div></div>`).join("")}</div>` : ""}
    ${rows.length ? reviewNumberTable(rows) : ""}
    ${evidenceLinks ? `<p class="review-links">${evidenceLinks}</p>` : ""}
  </section>`;
}
