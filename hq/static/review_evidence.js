/* Evidence shown in both the Decisions pane and a direct work review. The
   deliverable record names the version under review; attachments are display
   material and do not silently become proof of that version. */
"use strict";

/* hq/README.md documents a card's `links` field as plain references, separate
   from `attachments` (image/audio/sprite/video/look). Q-122 and Q-123
   (2026-09-25) put evidence images there instead, in the same {type, src,
   caption} shape attachments use, and nothing rendered them: the decision
   pane showed the recommendation and a paragraph promising "the attached
   boards" with no board in sight. Split `links` by shape, not by field name,
   so a media-typed entry always reaches the same visible-by-default evidence
   display an attachment would (§4), and a plain reference still renders as a
   link, however it arrived. */
function linkEvidenceAttachments(links) {
  return (links || []).filter(l => l && typeof l === "object" && ["image", "audio", "video"].includes(l.type));
}

function linkReferenceEntries(links) {
  return (links || []).filter(l => !(l && typeof l === "object" && ["image", "audio", "video"].includes(l.type)));
}

function renderReferenceLinks(links) {
  const refs = linkReferenceEntries(links);
  if (!refs.length) return "";
  return refs.map(raw => {
    const l = typeof raw === "string" ? { label: raw, href: raw } : (raw || {});
    const href = String(l.href || "");
    return `<a class="plain small" href="${esc(href)}" ${href.startsWith("http") ? 'target="_blank" rel="noopener"' : ""}>🔗 ${esc(l.label || href)}</a>`;
  }).join(" · ");
}

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
  return {href: `/assets/anim/${match[1]}/sheet.png`,
    label: `Open the current ${match[1].replaceAll("_", " ")} animation sheet`,
    labHref: `#/design/anim/${match[1]}`,
    slug: match[1], legacy: true};
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
  const comparison = item && (item.deliverable && item.deliverable.comparison || item.comparison);
  const rows = comparison && Array.isArray(comparison.rows) ? comparison.rows : [];
  const copy = comparison && Array.isArray(comparison.copy) ? comparison.copy : [];
  if (!entries.length && !display.length && !legacy && !rows.length && !copy.length) return "";
  const version = item && item.deliverable && (item.deliverable.reviewed_version ||
    entries.find(e => e.sha256 || e.version)?.sha256 || entries.find(e => e.version)?.version);
  const versionLabel = version ? `Reviewed version: ${esc(version)}` : "Reviewed version was not pinned in this card.";
  const creation = item && item.deliverable && item.deliverable.created_at;
  const evidenceLinks = entries.filter(e => e.kind === "link").map(e =>
    `<a href="${esc(e.href)}">${esc(e.label)}</a>`).join(" · ");
  return `<section class="review-evidence" aria-label="Result evidence">
    <h4>Result to review</h4>
    <p class="review-provenance">${creation ? `Created: ${esc(creation)} · ` : ""}Displayed here: ${media.length ? "playable or readable evidence" : "linked artifact"} · ${versionLabel}</p>
    ${legacy ? `<p class="review-version-gap">This older card does not identify the exact render originally reviewed. <a href="${esc(legacy.labHref)}">Open the Animation Lab</a> for the original review controls.</p>
      <div class="review-export"><b>Currently exported game animation</b><p>This is the sheet available in the game code today. It may differ from the original review.</p>
        <canvas data-review-slug="${esc(legacy.slug)}" aria-label="Currently exported ${esc(legacy.slug.replaceAll("_", " "))} animation at game scale"></canvas>
        <a href="/assets/anim/${esc(legacy.slug)}/sheet.png">Open exported sheet</a></div>` : ""}
    ${media.length ? [...new Set(media.map(e => e.group || ""))].map(name =>
      `<div class="review-media-group">${name ? `<h5>${esc(name)}</h5>` : ""}<div class="review-media-grid">${media.filter(e => (e.group || "") === name).map(e => reviewMediaCard(e)).join("")}</div></div>`).join("") : ""}
    ${copy.length ? `<div class="review-copy-grid">${copy.map(e => `<div><h5>${esc(e.label || "Version")}</h5><div class="review-copy">${esc(e.text || "")}</div></div>`).join("")}</div>` : ""}
    ${rows.length ? reviewNumberTable(rows) : ""}
    ${evidenceLinks ? `<p class="review-links">${evidenceLinks}</p>` : ""}
  </section>`;
}

function reviewMountPreviews(root = document) {
  for (const canvas of root.querySelectorAll("canvas[data-review-slug]:not([data-review-mounted])")) {
    const slug = canvas.dataset.reviewSlug;
    if (!/^[a-z0-9_]{1,64}$/.test(slug)) continue;
    canvas.dataset.reviewMounted = "true";
    Promise.all([
      fetch(`/assets/anim/${slug}/manifest.json`).then(r => { if (!r.ok) throw Error("No export"); return r.json(); }),
      new Promise((resolve, reject) => { const img = new Image(); img.onload = () => resolve(img);
        img.onerror = reject; img.src = `/assets/anim/${slug}/sheet.png`; }),
    ]).then(([manifest, sheet]) => {
      const width = Number(manifest.cell_width), height = Number(manifest.cell_height);
      const count = Number(manifest.frame_count), delay = Number(manifest.ms_per_frame);
      if (!Number.isInteger(width) || !Number.isInteger(height) || !Number.isInteger(count)
          || width < 1 || height < 1 || count < 1 || width * count > sheet.width
          || height > sheet.height || !Number.isFinite(delay) || delay < 16) throw Error("Invalid export");
      canvas.width = width; canvas.height = height;
      const ctx = canvas.getContext("2d");
      let frame = 0;
      const draw = () => { if (!canvas.isConnected) return;
        ctx.clearRect(0, 0, width, height);
        ctx.drawImage(sheet, frame * width, 0, width, height, 0, 0, width, height);
        frame = (frame + 1) % count;
        setTimeout(draw, delay);
      };
      draw();
    }).catch(() => {
      canvas.replaceWith(Object.assign(document.createElement("span"), {
        textContent: "The exported preview is unavailable. Open the linked sheet to inspect it."}));
    });
  }
}

if (typeof document !== "undefined" && document.body && typeof MutationObserver !== "undefined") {
  const observer = new MutationObserver(() => reviewMountPreviews());
  observer.observe(document.body, {childList: true, subtree: true});
  reviewMountPreviews();
}
