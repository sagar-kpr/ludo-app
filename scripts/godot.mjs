import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
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
else if (mode === 'test:captures') args.push('--headless', '--script', 'res://tests/captures.gd');
else if (mode === 'test:lives') args.push('--headless', '--script', 'res://tests/timeout_lives.gd');
else if (mode === 'test:leaving') args.push('--headless', '--script', 'res://tests/leaving.gd');
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
  console.error('Use run, editor, check, test, test:captures, build:web or build:android.');
  process.exit(1);
}
if (extra.length) args.push('--', ...extra);
const result = spawnSync(binary, args, { cwd: root, stdio: 'inherit' });
if (result.error) console.error('Godot could not start. Install Godot 4.6.1 or set GODOT_BIN to its executable.');
if (mode === 'build:web' && result.status === 0) {
  const htmlPath = path.join(project, 'dist/index.html');
  const html = readFileSync(htmlPath, 'utf8');
  const nativeInputs = readFileSync(path.join(project, 'web/native_inputs.js'), 'utf8').replace(/<\/script/gi, '<\\/script');
  const branded = html
    .replace('const engine = new Engine(GODOT_CONFIG);', `${nativeInputs}\nconst engine = new Engine(GODOT_CONFIG);`)
    .replace(
      '<img id="status-splash" class="show-image--true fullsize--true use-filter--true" src="index.png" alt="">',
      '<div id="status-splash" class="rally-splash"><div class="rally-splash-mark">✦</div><strong>RALLY <span>LUDO</span></strong><small>Loading your table…</small></div>',
    )
    .replace(
      '</style>',
      `
.rally-splash { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.7rem; color: #f5f6ff; font-family: Arial, sans-serif; background: radial-gradient(circle at 50% 42%, #252943 0%, #0d1021 52%, #080b18 100%); }
.rally-splash-mark { width: 4rem; height: 4rem; border-radius: 1.25rem; display: grid; place-items: center; color: #fff; background: linear-gradient(135deg, #3da8dc, #16355c); font-size: 2.2rem; box-shadow: 0 1rem 2.5rem rgba(20, 75, 120, 0.45); animation: rally-float 2.4s ease-in-out infinite, rally-glow 2.4s ease-in-out infinite; }
.rally-splash strong { font-size: 1.15rem; letter-spacing: 0.16rem; animation: rally-rise 0.8s ease both; }
.rally-splash strong span { color: #ffbf4b; }
.rally-splash small { color: #969ab7; font-size: 0.78rem; letter-spacing: 0.04rem; animation: rally-rise 0.8s 0.12s ease both; }
@keyframes rally-float { 0%, 100% { transform: translateY(0) rotate(0deg); } 50% { transform: translateY(-0.45rem) rotate(3deg); } }
@keyframes rally-glow { 50% { box-shadow: 0 0 2.2rem rgba(61, 168, 220, 0.42), 0 1rem 2.5rem rgba(20, 75, 120, 0.45); } }
@keyframes rally-rise { from { opacity: 0; transform: translateY(0.5rem); } to { opacity: 1; transform: translateY(0); } }
</style>`,
    );
  writeFileSync(htmlPath, branded);
}
process.exit(result.status ?? 1);
