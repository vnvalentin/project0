const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {execFileSync, spawnSync} = require('node:child_process');

const root = '/data/code/project0';
const mode = process.argv[2];
if (!['red', 'green', 'focused', 'static'].includes(mode)) throw new Error('Expected red, green, focused, or static');
const artifact = fs.mkdtempSync(path.join(root, '.scratch/1181/p2-' + mode + '-'));
const snapshot = fs.mkdtempSync(path.join(os.tmpdir(), 'project0-1181-p2-'));
const container = 'project0-1181-p2-' + crypto.randomBytes(6).toString('hex');
const overlayCommit = '9f14587c5ec9d2a3c340f36595d5f36c71c7c6a8';
const overlays = {
  'gui/arrow.png': '7f5a2f25d0cc68b8281bda24cdcd1d816e718d11fa0d050ede6cbad9033d17ed',
  'gui/play.png': 'd4280462a7940ebaf184e2b92bd01a69cf09ae1c97b175ac92e1410d16ecf278',
  'icon.png': '17186e5c117662f093554ade93529a8f2927750362004e133acf3ded0afba45d',
  'images/green.png': '9137132eda912531252c215d698a604c401f2e59f8b29005117d72fef625ed75',
  'images/red.png': 'e85d15987192029471051afc3b5de797629b95a5e02024fc5d14d81fdaf599bd',
  'images/yellow.png': 'd3e42a49cde1baf9dd2647d62ca58399efeb94c2eec39b2b62450021532c08c3',
};
const ownedFiles = [
  'server/jit_presentation_ack_tracker.gd', 'server/journey_registry.gd',
  'server/sector_boundary_detector.gd', 'server/server_main.gd', 'server/server_player_state.gd',
  'tests/unit/test_server_main_jit_orchestration.gd', 'tests/unit/test_server_player_state_collision.gd',
];
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const exec = (command, args, options = {}) => execFileSync(command, args, {cwd: root, maxBuffer: 256 * 1024 * 1024, timeout: 120000, ...options});
const git = args => exec('git', args);
const evidence = {mode, artifact, snapshot, container, started_at: new Date().toISOString(), steps: [], overlays: {}, passed: false};
let created = false;
let sourceBefore;
function run(name, args, timeout = 90000) {
  const result = spawnSync('docker', ['exec', container, '/workspace/.runner/godot', '--headless', '--path', '/workspace', ...args],
    {cwd: root, encoding: 'utf8', timeout, maxBuffer: 32 * 1024 * 1024});
  const output = (result.stdout || '') + (result.stderr || '');
  fs.writeFileSync(path.join(artifact, name + '.log'), output);
  const diagnosticLines = output.split('\n').filter(line => /SCRIPT ERROR:|(?:^|\s)ERROR:|Parse Error|Orphan|leaked|still in use|RID allocations|Skipping|\[Pending\]/i.test(line));
  const warnings = output.split('\n').filter(line => /WARNING:/.test(line));
  const unexpectedWarnings = warnings.filter(line => !/ext_resource, invalid UID:.*using text path instead/.test(line));
  const step = {name, command: ['godot', '--headless', '--path', '/workspace', ...args], exit: result.status, error: result.error?.message,
    diagnostics: diagnosticLines, warnings, unexpectedWarnings, log_sha256: sha(output)};
  evidence.steps.push(step);
  console.log(JSON.stringify({artifact, name, exit: step.exit, diagnostics: diagnosticLines.length}));
  return {step, output};
}
function requireClean(result) {
  if (result.step.exit !== 0 || result.step.diagnostics.length || result.step.unexpectedWarnings.length) throw new Error(result.step.name + ' failed strict validation');
}
try {
  if (git(['branch', '--show-current']).toString().trim() !== 'slice/1181-frontier-readiness') throw new Error('Wrong branch');
  evidence.base = git(['rev-parse', 'HEAD']).toString().trim();
  sourceBefore = git(['diff', 'HEAD', '--binary']);
  evidence.source_diff_sha256 = sha(sourceBefore);
  fs.writeFileSync(path.join(artifact, 'source.patch'), sourceBefore);
  const dirty = git(['diff', 'HEAD', '--name-only']).toString().trim().split('\n').filter(Boolean);
  if (dirty.some(file => !ownedFiles.includes(file))) throw new Error('Unknown tracked change: refusing snapshot');
  exec('tar', ['-xf', '-', '-C', snapshot], {input: git(['archive', 'HEAD'])});
  evidence.source_files = {};
  for (const file of ownedFiles) {
    const bytes = fs.readFileSync(path.join(root, file));
    fs.writeFileSync(path.join(snapshot, file), bytes);
    evidence.source_files[file] = sha(bytes);
  }
  if (fs.existsSync(path.join(snapshot, '.godot'))) throw new Error('Snapshot contains generated cache');
  for (const [relative, expected] of Object.entries(overlays)) {
    const file = 'addons/gut/' + relative;
    const bytes = git(['show', overlayCommit + ':' + file]);
    if (sha(bytes) !== expected) throw new Error('Dependency hash mismatch: ' + file);
    fs.writeFileSync(path.join(snapshot, file), bytes);
    evidence.overlays[file] = {commit: overlayCommit, sha256: expected};
  }
  fs.mkdirSync(path.join(snapshot, '.runner'));
  fs.copyFileSync('/usr/local/bin/godot', path.join(snapshot, '.runner/godot'));
  fs.chmodSync(path.join(snapshot, '.runner/godot'), 0o755);
  evidence.godot_sha256 = sha(fs.readFileSync('/usr/local/bin/godot'));
  const image = JSON.parse(exec('docker', ['image', 'inspect', 'ghcr.io/vnvalentin/project0-godot:main']).toString())[0];
  if (Object.keys(image.Config.Volumes || {}).length) throw new Error('Image declares volumes');
  evidence.image = image.Id;
  exec('docker', ['create', '--name', container, '--network', 'none', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
    '--pids-limit', '256', '--memory', '2g', '--cpus', '2', '--user', `${process.getuid()}:${process.getgid()}`,
    '--tmpfs', '/tmp:rw,mode=1777,size=512m', '--mount', `type=bind,src=${snapshot},dst=/workspace`,
    '--mount', `type=bind,src=${artifact},dst=/evidence`, '--workdir', '/workspace', '--env', 'HOME=/tmp/1181-home',
    '--label', 'project0.validation=1181-p2', '--entrypoint', '/usr/bin/tail', image.Id, '-f', '/dev/null']);
  created = true;
  exec('docker', ['start', container]);
  const inspection = JSON.parse(exec('docker', ['inspect', container]).toString())[0];
  evidence.isolation = {network: inspection.HostConfig.NetworkMode, ports: inspection.HostConfig.PortBindings, mounts: inspection.Mounts.map(mount => ({source: mount.Source, destination: mount.Destination}))};
  if (inspection.HostConfig.NetworkMode !== 'none' || Object.keys(inspection.HostConfig.PortBindings || {}).length) throw new Error('Isolation failed');
  run('import-first', ['--editor', '--import', '--quit']);
  requireClean(run('import-second', ['--editor', '--import', '--quit']));
  if (mode === 'static') {
    for (const file of ownedFiles) requireClean(run('parse-' + path.basename(file), ['--check-only', '-s', file]));
  } else {
    const suites = mode === 'focused' ? [
      'test_server_main_jit_orchestration.gd', 'test_server_player_state_collision.gd',
      'test_jit_presentation_ack_tracker.gd', 'test_sector_boundary_detector.gd',
      'test_journey_registry.gd', 'test_canon_generation_coordinator.gd',
    ] : ['test_server_main_jit_orchestration.gd'];
    for (const suite of suites) {
      const args = ['-s', 'addons/gut/gut_cmdln.gd', '-gdir=res://tests/unit', '-gselect=' + suite,
        '-gjunit_xml_file=/evidence/' + suite + '.xml', '-gdisable_colors', '-gexit'];
      if (mode !== 'focused') args.push('-gunit_test_name=test_initial_canon_write_failure_recovers_without_regeneration');
      const result = run(suite, args);
      if (mode === 'red') {
        if (result.step.exit !== 1 || result.step.diagnostics.length || result.step.unexpectedWarnings.length ||
          !result.output.includes('cooldown retries initial Canon persistence') || !/Tests\s+1\s/.test(result.output)) throw new Error('Not the expected clean assertion RED');
      } else {
        requireClean(result);
        if (!result.output.includes('All tests passed!') || !/Tests\s+[1-9]\d*\s/.test(result.output)) throw new Error('No passing tests');
      }
    }
  }
  evidence.passed = true;
} catch (error) {
  evidence.failure = error.stack;
  process.exitCode = 1;
} finally {
  if (created) {
    try { exec('docker', ['rm', '-f', container]); evidence.container_removed = true; }
    catch (error) { evidence.cleanup_error = error.message; process.exitCode = 1; }
  }
  fs.rmSync(snapshot, {recursive: true, force: true});
  evidence.snapshot_removed = !fs.existsSync(snapshot);
  evidence.source_unchanged = sourceBefore ? sha(git(['diff', 'HEAD', '--binary'])) === sha(sourceBefore) : null;
  if (evidence.source_unchanged === false) { evidence.passed = false; process.exitCode = 1; }
  evidence.finished_at = new Date().toISOString();
  fs.writeFileSync(path.join(artifact, 'run.json'), JSON.stringify(evidence, null, 2) + '\n');
  console.log(JSON.stringify({artifact, passed: evidence.passed, failure: evidence.failure, snapshot_removed: evidence.snapshot_removed, source_unchanged: evidence.source_unchanged}));
}