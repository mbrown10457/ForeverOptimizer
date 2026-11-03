// Builds docs/FEATURES.md from the add-in data embedded in docs/addins.html, so the page and the markdown never disagree.
//   node scripts/build_features.js docs/addins.html docs/FEATURES.md
const fs = require("fs");
const [,, src, out] = process.argv;
const html = fs.readFileSync(src, "utf8");
const m = html.match(/const ADDINS = (\[[\s\S]*?\n\]);/);
if (!m) { console.error("ADDINS array not found"); process.exit(1); }
const ADDINS = new Function("return " + m[1])();
const ver = (html.match(/id="ver">v([\d.]+)</) || [])[1] || "?";
const AREAS = ["Core","Grinding","Quest","Economy","Character","Classes","Dashboard","Tooling","Open slots"];
const S = { ok:"ready", live:"live check", part:"partial", open:"open slot" };
let md = `# ForeverOptimizer add-ins (v${ver})\n\nGenerated from \`docs/addins.html\` by \`scripts/build_features.js\`. The browsable version with filters and the architecture diagram is at https://mbrown10457.github.io/ForeverOptimizer/addins.html.\n\nStatus: **ready** = built and exercised by the offline harness; **live check** = built, needs the real client to confirm an API; **partial** = works with a stated gap; **open slot** = wanted, not built. Propose one: https://github.com/mbrown10457/ForeverOptimizer/issues/new?template=add-in.yml\n`;
for (const area of AREAS) {
  const rows = ADDINS.filter(x => x.a === area);
  if (!rows.length) continue;
  md += `\n## ${area}\n\n| Add-in | Status | What it does | Commands | Where |\n|---|---|---|---|---|\n`;
  for (const x of rows) {
    const what = x.w + (x.g ? ` *Gap: ${x.g}*` : "");
    const cmds = (x.c || []).map(c => `\`/fo ${c}\``).join(", ");
    const where = [x.f ? `\`${x.f}\`` : "", x.t ? `HUD: ${x.t}` : ""].filter(Boolean).join("; ");
    md += `| ${x.n} | ${S[x.s]} | ${what.replace(/\|/g, "\\|")} | ${cmds} | ${where} |\n`;
  }
}
const n = s => ADDINS.filter(x => x.s === s).length;
md += `\nTotals: ${n("ok")} ready, ${n("live")} live check, ${n("part")} partial, ${n("open")} open slots.\n`;
fs.writeFileSync(out, md);
console.log(`wrote ${out}: ${ADDINS.length} add-ins`);
