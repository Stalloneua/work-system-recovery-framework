import { createHash } from 'node:crypto';
import { createReadStream, existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

function timestamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function fileHash(path, algorithm) {
  return new Promise((resolveHash, reject) => {
    const hash = createHash(algorithm);
    const stream = createReadStream(path);
    stream.on('error', reject);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolveHash(hash.digest('hex')));
  });
}

const profile = argument('--profile', 'Foundation');
const maxArchiveBytes = Number(argument('--max-archive-bytes', String(80 * 1024 * 1024)));
if (!['Critical', 'Foundation', 'Full'].includes(profile)) throw new Error(`Unsupported profile: ${profile}`);
if (!Number.isFinite(maxArchiveBytes) || maxArchiveBytes < 1024 * 1024) throw new Error('Invalid max archive size.');

const documents = resolve(process.env.USERPROFILE, 'Documents');
const scratchRoot = resolve(process.env.LOCALAPPDATA, 'WorkSystemScratch');
const outputRoot = resolve(argument('--output-root', join(scratchRoot, 'ConnectorSnapshots')));
const backupId = argument('--backup-id', timestamp());
if (!outputRoot.toLowerCase().startsWith(scratchRoot.toLowerCase())) {
  throw new Error(`Output root must be inside ${scratchRoot}`);
}

const snapshotRoot = join(outputRoot, backupId);
if (existsSync(snapshotRoot)) throw new Error(`Snapshot already exists: ${snapshotRoot}`);
const archiveRoot = join(snapshotRoot, 'archives');
mkdirSync(archiveRoot, { recursive: true });

const scriptRoot = dirname(fileURLToPath(import.meta.url));
const sourceConfig = JSON.parse(readFileSync(join(scriptRoot, 'backup-sources.json'), 'utf8'));
const key = profile.toLowerCase();
const sources = [...new Set(sourceConfig[key]
  .map((p) => resolve(p.replace('%DOCUMENTS%', documents)))
  .filter(existsSync))];
if (!sources.length) throw new Error('No backup sources resolved.');

const exclusionFiles = [join(scriptRoot, 'backup-excludes.txt')];
if (profile === 'Foundation') {
  exclusionFiles.push(join(scriptRoot, 'foundation-excludes.txt'));
  const local = join(scriptRoot, 'foundation-excludes.local.txt');
  if (existsSync(local)) exclusionFiles.push(local);
}
const patterns = exclusionFiles.flatMap((file) => readFileSync(file, 'utf8').split(/\r?\n/))
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'));

function globRegex(pattern) {
  let source = pattern.replaceAll('\\', '/');
  const leadingAny = source.startsWith('**/');
  const trailingAny = source.endsWith('/**');
  if (leadingAny) source = source.slice(3);
  if (trailingAny) source = source.slice(0, -3);
  source = source.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  source = source.replaceAll('**', '\u0000').replaceAll('*', '[^/]*');
  source = source.replaceAll('?', '[^/]').replaceAll('\u0000', '.*');
  return new RegExp(`^${leadingAny ? '(?:.*/)?' : ''}${source}${trailingAny ? '(?:/.*)?' : ''}$`, 'i');
}

const excludes = patterns.map(globRegex);
const isExcluded = (path) => excludes.some((regex) => regex.test(path.replaceAll('\\', '/')));

function sourceFiles(source) {
  const sourceStat = statSync(source);
  if (sourceStat.isFile()) return [{ path: relative(documents, source), size: sourceStat.size }];
  const files = [];
  function walk(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const full = join(directory, entry.name);
      const relSource = relative(source, full).replaceAll('\\', '/');
      if (isExcluded(relSource) || entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile()) files.push({ path: relative(documents, full), size: statSync(full).size });
    }
  }
  walk(source);
  files.sort((a, b) => a.path.localeCompare(b.path));
  return files;
}

const sevenZip = existsSync(join(process.env.ProgramFiles, '7-Zip', '7z.exe'))
  ? join(process.env.ProgramFiles, '7-Zip', '7z.exe')
  : '7z.exe';
const archives = [];
const listRoot = join(snapshotRoot, '.lists');
mkdirSync(listRoot, { recursive: true });

for (let i = 0; i < sources.length; i += 1) {
  const source = sources[i];
  const rel = relative(documents, source);
  if (!rel || rel.startsWith('..') || isAbsolute(rel)) throw new Error(`Non-portable source: ${source}`);
  const safeName = basename(rel).replace(/[^A-Za-z0-9._-]/g, '_') || 'source';
  const files = sourceFiles(source);
  const chunks = [];
  let chunk = [];
  let chunkBytes = 0;
  for (const file of files) {
    if (file.size > maxArchiveBytes) {
      if (chunk.length) chunks.push(chunk);
      chunks.push([file]);
      chunk = [];
      chunkBytes = 0;
      continue;
    }
    if (chunk.length && chunkBytes + file.size > maxArchiveBytes) {
      chunks.push(chunk);
      chunk = [];
      chunkBytes = 0;
    }
    chunk.push(file);
    chunkBytes += file.size;
  }
  if (chunk.length) chunks.push(chunk);

  for (let part = 0; part < chunks.length; part += 1) {
    const suffix = chunks.length > 1 ? `-part${String(part + 1).padStart(3, '0')}` : '';
    const archive = `${String(i + 1).padStart(2, '0')}-${safeName}${suffix}.zip`;
    const archivePath = join(archiveRoot, archive);
    const listPath = join(listRoot, `${archive}.txt`);
    writeFileSync(listPath, `${chunks[part].map((file) => file.path).join('\n')}\n`, 'utf8');
    const uncompressedBytes = chunks[part].reduce((sum, file) => sum + file.size, 0);
    const isVolumeSet = uncompressedBytes > maxArchiveBytes;
    const volumeArg = isVolumeSet ? [`-v${maxArchiveBytes}b`] : [];
    const result = spawnSync(sevenZip, ['a', '-tzip', archivePath, `@${listPath}`, '-scsUTF-8', '-mx=5', '-bb0', ...volumeArg], {
      cwd: documents,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const produced = isVolumeSet
      ? readdirSync(archiveRoot).filter((name) => name.startsWith(`${archive}.`)).sort()
      : [archive];
    if (result.status !== 0 || !produced.length || produced.some((name) => !existsSync(join(archiveRoot, name)))) {
      throw new Error(`Archive creation failed for ${rel}: ${result.stderr || result.stdout}`);
    }
    for (const producedName of produced) {
      const producedPath = join(archiveRoot, producedName);
      const sha256 = (await fileHash(producedPath, 'sha256')).toUpperCase();
      const md5 = await fileHash(producedPath, 'md5');
      const bytes = statSync(producedPath).size;
      if (bytes > 100 * 1024 * 1024) throw new Error(`Connector-safe archive limit exceeded: ${producedName}`);
      archives.push({
        relative_path: rel.replaceAll('\\', '/'),
        archive: producedName,
        remote_path: `snapshots/${backupId}/archives/${producedName}`,
        bytes,
        sha256,
        md5,
        ...(isVolumeSet ? { archive_set: archive, extract_from: `${archive}.001` } : {}),
      });
      process.stdout.write(`${archives.length} ${producedName} ${bytes}\n`);
    }
    unlinkSync(listPath);
  }
}

const manifest = {
  schema_version: 2,
  backup_mode: 'plain-rclone',
  layout: 'snapshot-archives',
  backup_id: backupId,
  started_by: process.env.USERNAME,
  source_machine: process.env.COMPUTERNAME,
  created_at: new Date().toISOString(),
  profile,
  source_count: archives.length,
  archives,
};
const manifestPath = join(snapshotRoot, 'manifest.json');
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
process.stdout.write(`${JSON.stringify({ backup_id: backupId, profile, source_count: archives.length, snapshot_root: snapshotRoot, manifest: manifestPath, result: 'PASS' })}\n`);
