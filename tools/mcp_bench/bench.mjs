// Times two Godot MCP servers through ONE logical task battery.
//
// The question this answers is architectural, not cosmetic. @coding-solo/godot-mcp spawns a
// headless Godot per operation (`--headless --path X --script godot_operations.gd`, verified
// in its build/index.js, not in its README). @satelliteoflove/godot-mcp keeps a WebSocket
// bridge into a RUNNING editor, so a call is a message rather than a process. Whether that
// difference is worth an always-open editor is a number, and this produces the number.
//
//     npm install && node bench.mjs                 # both servers
//     node bench.mjs --only=coding-solo             # one
//     node bench.mjs --only=coding-solo --repeat=2  # instrument self-check
//
// It is dev tooling and is never wired into check.sh: the repo's rule is that the MCP is an
// accelerator for interactive work, never a dependency of the build. A benchmark that gated
// the build would make it one.
//
// Every run happens in a TEMP COPY of fixture/, so a server that writes files cannot touch
// the repo and the two servers cannot contaminate each other.

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { cp, mkdtemp, readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE = join(HERE, 'fixture');
const GODOT = process.env.GODOT_BIN || '/Applications/Godot.app/Contents/MacOS/Godot';

const argv = process.argv.slice(2);
const arg = (name, fallback) => {
  // --flag=value only. The space form binds nothing for optional-value flags and lands the
  // value in a positional slot, which is a silent misconfiguration rather than an error.
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const ONLY = arg('only', '');
const REPEAT = Number(arg('repeat', '1'));

// ---------------------------------------------------------------------------------------
// The servers. Tool NAMES differ between them, so the battery is written in terms of
// logical steps and each server maps them - comparing "create a scene" to "create a scene",
// never one server's tool to another's.
// ---------------------------------------------------------------------------------------

const SERVERS = {
  'coding-solo': {
    pkg: '@coding-solo/godot-mcp',
    args: ['-y', '@coding-solo/godot-mcp'],
    env: { GODOT_PATH: GODOT, DEBUG: 'false' },
    needsEditor: false,
    map: {
      version: () => ['get_godot_version', {}],
      project_info: (p) => ['get_project_info', { projectPath: p }],
      // NOT "res://bench.tscn". create_scene routes the path through godot_operations.gd,
      // which prepends res:// itself - but add_node and save_scene do a naive JS
      // join(projectPath, scenePath) in index.js (~line 1307), so a res:// prefix becomes
      // "<project>/res:/bench.tscn" and they report the scene as missing. One server, two
      // path conventions across its own tools. The bare form is what both accept.
      create_scene: (p) => ['create_scene', { projectPath: p, scenePath: 'bench.tscn', rootNodeType: 'Node2D' }],
      add_node: (p, i) => ['add_node', { projectPath: p, scenePath: 'bench.tscn', parentNodePath: 'root', nodeType: 'Node2D', nodeName: `Bench${i}` }],
      save_scene: (p) => ['save_scene', { projectPath: p, scenePath: 'bench.tscn' }],
    },
  },
  satelliteoflove: {
    pkg: '@satelliteoflove/godot-mcp',
    args: ['-y', '@satelliteoflove/godot-mcp'],
    env: {},
    // Needs an editor already listening on 127.0.0.1:6550 with the addon enabled. Note the
    // target is THAT editor's project - this server takes no projectPath, so the temp copy
    // the harness makes is irrelevant to it. Launch with:
    //   npx -y @satelliteoflove/godot-mcp --install-addon <proj>
    //   (enable res://addons/godot_mcp/plugin.cfg in project.godot)
    //   Godot --headless --editor --path <proj>
    // Headless works: the bridge comes up without a visible editor window.
    needsEditor: true,
    // Tools are VERB-GROUPED (godot_scene + action:"open"), not one tool per operation, so
    // no name-matching heuristic can find them - these come from the server's own schemas.
    // A guessed action name returns an error in ~3ms, which would look like a blazing fast
    // success in a latency table. That is why timedCall records isError.
    map: {
      // NOT addon_status: proven by control (editor killed, it still answers in ~4ms with
      // connected:false) to be answered locally by the Node server without touching the
      // editor. Timing it measures the server's own reply loop and reports ~0ms, which
      // reads as a spectacular win for a call that never leaves the process. get_info is
      // the cheapest call that provably crosses the bridge - it returns the live editor's
      // Godot version and project path, and errors outright when the editor is gone.
      version: () => ['godot_project', { action: 'get_info' }],
      project_info: () => ['godot_project', { action: 'get_info' }],
      scene_tree: () => ['godot_node_read', { action: 'get_scene_tree' }],
      editor_state: () => ['godot_editor_read', { action: 'get_state' }],
      // No create_scene / add_node exists on this server at all: it opens, saves and
      // reloads scenes that already exist and edits nodes that are already there. Recorded
      // as a capability gap rather than faked with a near-equivalent.
    },
  },
};

// Which logical steps each server is asked to do, and how many samples. A step a server
// cannot express is reported as an explicit gap - never substituted with something adjacent,
// which would compare two different operations and call it a race.
const BATTERY = [
  ['version', 10],
  ['project_info', 3],
  ['scene_tree', 3],
  ['editor_state', 3],
  ['create_scene', 1],
  ['add_node', 3],
  ['save_scene', 1],
];

// ---------------------------------------------------------------------------------------

const ms = (start) => Number(process.hrtime.bigint() - start) / 1e6;

function stats(samples) {
  if (!samples.length) return null;
  const s = [...samples].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return {
    n: s.length,
    median: s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2,
    min: s[0],
    max: s[s.length - 1],
  };
}

async function timedCall(client, name, args) {
  const start = process.hrtime.bigint();
  let ok = true;
  let text = '';
  try {
    const res = await client.callTool({ name, arguments: args });
    // An MCP error result is a normal-looking response. Timing one is timing the failure
    // path, so it is recorded as a failure rather than as a fast success.
    ok = !res.isError;
    text = (res.content ?? []).map((c) => c.text ?? '').join('\n');
  } catch (err) {
    ok = false;
    text = String(err?.message ?? err);
  }
  return { elapsed: ms(start), ok, text };
}

async function runBattery(projectPath, client, map) {
  const results = [];
  for (const [step, samples] of BATTERY) {
    const fn = map[step];
    if (!fn) {
      results.push({ step, unsupported: true });
      continue;
    }
    // Repeated deliberately: one sample of a cheap read measures the machine's mood. The
    // MEDIAN of the cheapest call is the per-call architectural overhead, which is the
    // number the whole comparison turns on.
    for (let i = 0; i < samples; i++) {
      const [name, args] = fn(projectPath, i);
      const r = await timedCall(client, name, args);
      results.push({ step, tool: name, ...r });
    }
  }
  return results;
}

// What create_scene + 3x add_node must leave behind. A latency table for a server that
// wrote the WRONG scene is not a comparison, it is a race between two different jobs.
const EXPECTED_NODES = ['root', 'Bench0', 'Bench1', 'Bench2'];

/** What the battery actually WROTE, and whether it is what was asked for. */
async function inspectArtifact(projectPath) {
  const scene = join(projectPath, 'bench.tscn');
  if (!existsSync(scene)) return { exists: false, nodes: [], missing: EXPECTED_NODES, correct: false };
  const text = await readFile(scene, 'utf8');
  const nodes = [...text.matchAll(/\[node name="([^"]+)"/g)].map((m) => m[1]);
  const missing = EXPECTED_NODES.filter((n) => !nodes.includes(n));
  return { exists: true, nodes, bytes: text.length, missing, correct: missing.length === 0 };
}

async function benchOne(key) {
  const cfg = SERVERS[key];
  const projectPath = await mkdtemp(join(tmpdir(), `mcpbench-${key}-`));
  await cp(FIXTURE, projectPath, { recursive: true });

  const transport = new StdioClientTransport({
    command: 'npx',
    args: cfg.args,
    env: { ...process.env, ...cfg.env },
  });
  const client = new Client({ name: 'mcp-bench', version: '1.0.0' }, { capabilities: {} });

  const connectStart = process.hrtime.bigint();
  await client.connect(transport);
  const connectMs = ms(connectStart);

  const listed = await client.listTools();
  const toolNames = listed.tools.map((t) => t.name);
  // Every action this server advertises, so the capability delta is read off the schemas
  // rather than off a README that may describe a different version.
  const actions = listed.tools.map((t) => {
    const e = t.inputSchema?.properties?.action?.enum;
    return e ? `${t.name}: ${e.join(', ')}` : t.name;
  });

  const results = await runBattery(projectPath, client, cfg.map);
  const artifact = await inspectArtifact(projectPath);
  await client.close();

  return { key, pkg: cfg.pkg, connectMs, toolCount: toolNames.length, toolNames, actions, results, artifact, projectPath };
}

function summarise(run) {
  const byStep = new Map();
  for (const r of run.results) {
    if (r.unsupported || !r.ok) continue;
    if (!byStep.has(r.step)) byStep.set(r.step, []);
    byStep.get(r.step).push(r.elapsed);
  }
  const out = {};
  for (const [step, samples] of byStep) out[step] = stats(samples);
  const failures = run.results.filter((r) => r.unsupported || !r.ok);
  return { ...run, summary: out, failures };
}

function report(runs) {
  const steps = BATTERY.map(([s]) => s);
  const lines = [];
  lines.push('# Godot MCP benchmark', '');
  lines.push(`Engine: \`${GODOT}\`  ·  Node: ${process.version}  ·  ${new Date().toISOString()}`, '');
  lines.push('| step | ' + runs.map((r) => `${r.key} median ms`).join(' | ') + ' |');
  lines.push('|---|' + runs.map(() => '---|').join(''));
  lines.push('| connect (session start) | ' + runs.map((r) => r.connectMs.toFixed(0)).join(' | ') + ' |');
  for (const step of steps) {
    const cells = runs.map((r) => {
      const s = r.summary[step];
      return s ? `${s.median.toFixed(0)} (${s.min.toFixed(0)}–${s.max.toFixed(0)}, n=${s.n})` : '—';
    });
    lines.push(`| ${step} | ${cells.join(' | ')} |`);
  }
  lines.push('');
  lines.push('## Artifact (correctness, not speed)', '');
  for (const r of runs) {
    const claimed = r.results.some((x) => x.step === 'add_node' && !x.unsupported);
    const verdict = !claimed
      ? 'n/a — server has no scene-authoring tools'
      : r.artifact.correct
        ? 'CORRECT'
        : `WRONG — missing ${JSON.stringify(r.artifact.missing)}`;
    lines.push(`- **${r.key}** — ${verdict}; nodes written: ${JSON.stringify(r.artifact.nodes)}`);
  }
  lines.push('');
  lines.push('## Tool surface', '');
  for (const r of runs) lines.push(`- **${r.key}** (${r.pkg}) — ${r.toolCount} tools`);
  if (runs.length === 2) {
    const [a, b] = runs;
    const onlyA = a.toolNames.filter((t) => !b.toolNames.includes(t));
    const onlyB = b.toolNames.filter((t) => !a.toolNames.includes(t));
    lines.push('', `- only in **${a.key}**: ${onlyA.join(', ') || '(none)'}`);
    lines.push(`- only in **${b.key}**: ${onlyB.join(', ') || '(none)'}`);
    lines.push('', '### Every action, from the servers\u2019 own schemas', '');
    for (const r of runs) {
      lines.push('', `**${r.key}**`, '', '```');
      for (const a of r.actions) lines.push(a);
      lines.push('```');
    }
  }
  const anyFail = runs.some((r) => r.failures.length);
  if (anyFail) {
    lines.push('', '## Failures / skips', '');
    for (const r of runs) {
      for (const f of r.failures) {
        lines.push(`- **${r.key}** ${f.step}: ${f.unsupported ? 'no such capability on this server' : (f.text || '').slice(0, 160)}`);
      }
    }
  }
  return lines.join('\n');
}

const keys = Object.keys(SERVERS).filter((k) => !ONLY || k === ONLY);
if (!keys.length) {
  console.error(`no server matches --only=${ONLY}; known: ${Object.keys(SERVERS).join(', ')}`);
  process.exit(2);
}

const runs = [];
for (const key of keys) {
  for (let pass = 0; pass < REPEAT; pass++) {
    process.stderr.write(`running ${key}${REPEAT > 1 ? ` (pass ${pass + 1}/${REPEAT})` : ''}...\n`);
    const run = summarise(await benchOne(key));
    runs.push(REPEAT > 1 ? { ...run, key: `${key}#${pass + 1}` } : run);
  }
}

const md = report(runs);
console.log(md);
await mkdir(join(HERE, 'results'), { recursive: true });
await writeFile(join(HERE, 'results', 'latest.md'), md + '\n');
process.stderr.write(`\nwrote ${join(HERE, 'results', 'latest.md')}\n`);

// Exit non-zero when a server that ran the editing steps produced the wrong scene. Without
// this the harness could report a beautiful table about work that never happened.
const wrong = runs.filter(
  (r) => r.results.some((x) => x.step === 'add_node' && !x.unsupported) && !r.artifact.correct,
);
if (wrong.length) {
  process.stderr.write(`ARTIFACT CHECK FAILED: ${wrong.map((r) => r.key).join(', ')}\n`);
  process.exit(1);
}
