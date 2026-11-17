#!/usr/bin/env bash
# Installs Bytez (bytez.js) into ~/bytez-tools and the /bytez skill into ~/.claude/skills/bytez
set -euo pipefail
command -v node >/dev/null || { echo "Node.js 18+ is required: brew install node"; exit 1; }
mkdir -p ~/bytez-tools ~/.claude/skills/bytez && cd ~/bytez-tools
[ -f package.json ] || npm init -y >/dev/null
npm install bytez.js
cat > ~/bytez-tools/bytez.mjs <<'BYTEZ_EOF'
#!/usr/bin/env node
// Bytez CLI wrapper for bytez.js v3 (new Bytez(key) / list.models / list.tasks / model(id).run)
// The key is read ONLY from the BYTEZ_KEY env var and is never printed.
import Bytez from "bytez.js";
import { writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const [cmd, ...rest] = process.argv.slice(2);
const flags = {}; const args = [];
for (let i = 0; i < rest.length; i++) {
  if (rest[i].startsWith("--")) { flags[rest[i].slice(2)] = rest[i + 1]; i++; } else args.push(rest[i]);
}
const usage = `Usage:
  bytez.mjs check                         verify key + catalog access
  bytez.mjs tasks                         list tasks
  bytez.mjs models <task> [--limit N]     list models for a task (text-to-image | text-to-speech | text-to-audio | text-to-video ...)
  bytez.mjs run <modelId> "<input>" [--params '{json}'] [--out path]`;

if (!cmd || cmd === "help") { console.log(usage); process.exit(0); }
const key = process.env.BYTEZ_KEY;
if (!key) {
  console.error("BYTEZ_KEY is not set. Run: ~/bytez-tools/set-key.sh   (then: source ~/.bytez_env)");
  process.exit(2);
}
const client = new Bytez(key);
const die = (e) => { console.error("Error:", typeof e === "string" ? e : JSON.stringify(e)); process.exit(1); };

async function save(output, out, modelId) {
  const ext = (t) => ({ "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "audio/wav": "wav", "audio/x-wav": "wav", "audio/mpeg": "mp3", "audio/flac": "flac", "video/mp4": "mp4", "video/webm": "webm" }[t?.split(";")[0]] || "bin");
  let buf, type;
  if (typeof output === "string" && /^https?:\/\//.test(output)) {
    const r = await fetch(output); if (!r.ok) die(`download failed ${r.status}`);
    type = r.headers.get("content-type"); buf = Buffer.from(await r.arrayBuffer());
  } else if (typeof output === "string" && output.startsWith("data:")) {
    const m = output.match(/^data:([^;]+);base64,(.*)$/s); type = m[1]; buf = Buffer.from(m[2], "base64");
  } else if (typeof output === "string" && output.length > 200 && /^[A-Za-z0-9+/=\s]+$/.test(output)) {
    buf = Buffer.from(output, "base64");
  } else { return null; }
  const path = resolve(out || `bytez-${modelId.split("/").pop()}-${Date.now()}.${ext(type)}`);
  await mkdir(dirname(path), { recursive: true }); await writeFile(path, buf);
  return path;
}

if (cmd === "check") {
  const { error, output } = await client.list.models({ task: "text-to-image" });
  if (error) die(error);
  console.log(`OK: connected to Bytez. text-to-image models in catalog: ${output?.length ?? 0}`);
} else if (cmd === "tasks") {
  const { error, output } = await client.list.tasks(); if (error) die(error);
  console.log(JSON.stringify(output, null, 2));
} else if (cmd === "models") {
  if (!args[0]) die("missing <task>");
  const { error, output } = await client.list.models({ task: args[0] }); if (error) die(error);
  const lim = Number(flags.limit || 30);
  for (const m of (output || []).slice(0, lim)) console.log(`${m.modelId}\t${m.ramRequired ?? "?"}GB\t${m.params ?? ""}`);
  console.log(`(${output?.length ?? 0} total)`);
} else if (cmd === "run") {
  const [modelId, input] = args; if (!modelId || input === undefined) die("usage: run <modelId> <input>");
  const params = flags.params ? JSON.parse(flags.params) : undefined;
  const { error, output } = await client.model(modelId).run(input, params);
  if (error) die(error);
  const path = await save(output, flags.out, modelId);
  console.log(path ? `Saved: ${path}` : JSON.stringify(output, null, 2));
} else { console.log(usage); process.exit(1); }
BYTEZ_EOF
cat > ~/bytez-tools/set-key.sh <<'BYTEZ_EOF'
#!/usr/bin/env bash
# Prompts for the Bytez key with hidden input and stores it in ~/.bytez_env (chmod 600).
set -euo pipefail
read -rsp "Bytez API key (hidden): " K; echo
[ -n "$K" ] || { echo "empty key, aborting"; exit 1; }
umask 077
printf 'export BYTEZ_KEY=%q\n' "$K" > "$HOME/.bytez_env"
unset K
chmod 600 "$HOME/.bytez_env"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || [ "$rc" = "$HOME/.zshrc" ] || continue
  grep -q '.bytez_env' "$rc" 2>/dev/null || echo '[ -f ~/.bytez_env ] && source ~/.bytez_env' >> "$rc"
done
echo "Saved to ~/.bytez_env. Run: source ~/.bytez_env && node ~/bytez-tools/bytez.mjs check"
BYTEZ_EOF
cat > ~/.claude/skills/bytez/SKILL.md <<'BYTEZ_EOF'
---
name: bytez
description: Generate images, voiceover/speech and video with Bytez models (bytez.js v3 installed in ~/bytez-tools). Use when the user runs /bytez or asks to create an image, narration/TTS or a video clip via Bytez, or to browse the Bytez model catalog.
---

# Bytez: image, voiceover and video generation

Local install: `~/bytez-tools` (bytez.js v3, wrapper `~/bytez-tools/bytez.mjs`).
The API key comes ONLY from the `BYTEZ_KEY` env var, loaded from `~/.bytez_env`.
Never print, echo, or ask the user to paste the key in chat.

Prefix every command with: `[ -f ~/.bytez_env ] && source ~/.bytez_env;`

## 1. Check the key / connection
```bash
[ -f ~/.bytez_env ] && source ~/.bytez_env; node ~/bytez-tools/bytez.mjs check
```
If it reports BYTEZ_KEY is not set, tell the user to run in their own terminal:
`~/bytez-tools/set-key.sh` (hidden input), then retry. Do not proceed without it.

## 2. Pick a model (always from the live catalog, never from memory)
Map the request to a task:
- image -> `text-to-image`
- voiceover / narration / TTS -> `text-to-speech` (music/sfx -> `text-to-audio`)
- video -> `text-to-video`

```bash
[ -f ~/.bytez_env ] && source ~/.bytez_env; node ~/bytez-tools/bytez.mjs models text-to-image --limit 30
```
Choose one model that fits (prefer well-known families and lower RAM for speed), say which you picked and why.
If the user named a model, use it.

## 3. Run it
```bash
[ -f ~/.bytez_env ] && source ~/.bytez_env; node ~/bytez-tools/bytez.mjs run "<modelId>" "<prompt or text>" --out ./bytez-output/<name>.<ext>
```
- Optional model params: `--params '{"num_inference_steps":25}'`
- Media outputs (URL / base64) are downloaded and saved; the saved path is printed.
- Write the prompt in English for image/video models unless the model supports the user's language; for TTS keep the user's text as-is and pick a model that supports that language (say so if none does).
- If a model errors (cold start / unavailable), try once more, then switch to another model from the list and tell the user.

## 4. Report
Give the saved file path, the model used, and the prompt. Offer a variation or a different model.
BYTEZ_EOF
chmod +x ~/bytez-tools/bytez.mjs ~/bytez-tools/set-key.sh
node -e "import(\"bytez.js\").then(m=>console.log(\"bytez.js\", require(\"bytez.js/package.json\").version, \"loaded OK\"))" 2>/dev/null || node --input-type=module -e "import B from \"bytez.js\"; new B(\"x\"); console.log(\"bytez.js loaded OK\")"
test -f ~/.claude/skills/bytez/SKILL.md && echo "Skill installed: ~/.claude/skills/bytez/SKILL.md"
[ -f ~/.bytez_env ] && source ~/.bytez_env || true
if [ -n "${BYTEZ_KEY:-}" ]; then node ~/bytez-tools/bytez.mjs check; else echo; echo "BYTEZ_KEY not set. Next step (hidden input):  ~/bytez-tools/set-key.sh"; fi
