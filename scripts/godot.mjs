import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const project = path.join(root, 'apps/godot');
const bundled = path.join(root, '.tools/godot/Godot_v4.6.1-stable_linux.x86_64');
const binary = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : 'godot');
const mode = process.argv[2] || 'run';
const extra = process.argv.slice(3);
let args = ['--path', project];
if (mode === 'editor') args.push('--editor');
else if (mode === 'check') {
  // Godot's editor importer can exit 0 even when a script has parse errors.
  // Check each script explicitly instead of reporting a false success.
  const files = ['scripts', 'tests'].flatMap(directory => readdirSync(path.join(project, directory))
    .filter(name => name.endsWith('.gd')).map(name => `${directory}/${name}`));
  for (const file of files) {
    const result = spawnSync(binary, ['--headless', '--path', project, '--check-only', '--script', `res://${file}`], { cwd: root, encoding: 'utf8' });
    if (result.error || result.status !== 0 || /SCRIPT ERROR|^ERROR:/m.test(result.stderr || '')) {
      console.error(result.stdout || '', result.stderr || '', result.error?.message || '');
      process.exit(1);
    }
  }
  console.log(`Godot parsed ${files.length} scripts successfully.`);
  process.exit(0);
}
else if (mode === 'test') args.push('--headless', '--script', 'res://tests/check.gd');
else if (mode === 'build:web') {
  mkdirSync(path.join(project, 'dist'), { recursive: true });
  writeFileSync(path.join(project, 'dist/.gdignore'), '');
  args.push('--headless', '--export-release', 'Web', path.join(project, 'dist/index.html'));
} else if (mode === 'build:android') {
  mkdirSync(path.join(project, 'dist-android'), { recursive: true });
  writeFileSync(path.join(project, 'dist-android/.gdignore'), '');
  args.push('--headless', '--export-debug', 'Android', path.join(project, 'dist-android/rally-ludo.apk'));
} else if (mode !== 'run') {
  console.error('Use run, editor, check, test, build:web or build:android.');
  process.exit(1);
}
if (extra.length) args.push('--', ...extra);
const result = spawnSync(binary, args, { cwd: root, stdio: 'inherit' });
if (result.error) console.error('Godot could not start. Install Godot 4.6.1 or set GODOT_BIN to its executable.');
process.exit(result.status ?? 1);
