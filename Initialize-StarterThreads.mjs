import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const manifestPath = process.argv[2] || join(root, 'starter-thread-manifest.json');
const stateRoot = join(process.env.LOCALAPPDATA, 'WorkSystemRecovery');
const registryPath = join(stateRoot, 'starter-thread-registry.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
mkdirSync(stateRoot, { recursive: true });
const registry = existsSync(registryPath)
  ? JSON.parse(readFileSync(registryPath, 'utf8'))
  : { schema_version: 1, machine: process.env.COMPUTERNAME, created_at: new Date().toISOString(), threads: {} };

function promptFor(item) {
  const tasks = item.task_ids.length ? item.task_ids.join(', ') : 'no task selected yet';
  return [
    'Initialization only. Do not execute the task, modify files, send messages, publish, deploy, or change external systems in this turn.',
    `This is a continuation chat for ${item.direction_id} / ${item.project_id}.`,
    `Role: ${item.role}`,
    `Related tasks: ${tasks}.`,
    `Sources of truth: ${item.source_of_truth}`,
    `Current checkpoint: ${item.checkpoint}`,
    `Next action when the user explicitly resumes work: ${item.next_action}`,
    'At the start of future work, reread the live tracker row and named Obsidian/current-state sources. Never infer Done or external approval.',
    `For this initialization turn respond only: READY - ${item.direction_id} / ${item.project_id}.`,
  ].join('\n');
}

for (const item of manifest.threads) {
  if (registry.threads[item.key]?.thread_id) {
    process.stdout.write(`SKIP ${item.key} ${registry.threads[item.key].thread_id}\n`);
    continue;
  }
  if (!existsSync(item.cwd)) throw new Error(`Missing working directory for ${item.key}: ${item.cwd}`);
  const result = spawnSync('codex.exe', [
    'exec', '--json', '-m', manifest.model || 'gpt-5.6-sol',
    '-C', item.cwd, '--skip-git-repo-check', '-s', 'read-only', promptFor(item),
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024 });
  const events = result.stdout.split(/\r?\n/).filter(Boolean).flatMap((line) => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
  const threadId = events.find((event) => event.type === 'thread.started')?.thread_id;
  if (!threadId) throw new Error(`Codex did not create ${item.key}: ${result.stderr || result.stdout}`);
  registry.threads[item.key] = {
    thread_id: threadId,
    title: item.title,
    direction_id: item.direction_id,
    project_id: item.project_id,
    task_ids: item.task_ids,
    cwd: item.cwd,
    initialized_at: new Date().toISOString(),
    turn_exit_code: result.status,
  };
  registry.updated_at = new Date().toISOString();
  writeFileSync(registryPath, `${JSON.stringify(registry, null, 2)}\n`, 'utf8');
  process.stdout.write(`CREATED ${item.key} ${threadId} exit=${result.status}\n`);
}

process.stdout.write(`${registryPath}\n`);
