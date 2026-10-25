import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

export function configureAndroidReleaseSigning(env) {
  const keys = ['GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD'];
  const provided = keys.filter(key => env[key]);
  if (provided.length && provided.length !== keys.length) throw new Error(`Set all three signing variables: ${keys.join(', ')}.`);
  const keytool = path.join(env.JAVA_HOME, 'bin', process.platform === 'win32' ? 'keytool.exe' : 'keytool');
  if (!provided.length) {
    const directory = path.join(root, 'private/android-signing');
    const configPath = path.join(directory, 'release-signing.json');
    const keystore = path.join(directory, 'rally-ludo-release.keystore');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    chmodSync(directory, 0o700);
    let config;
    if (existsSync(configPath)) {
      config = JSON.parse(readFileSync(configPath, 'utf8'));
      if (!config.alias || !config.password || !existsSync(keystore)) throw new Error('Release signing files are incomplete. Restore the original signing backup; do not replace the key.');
    } else {
      if (existsSync(keystore)) throw new Error('An existing release key has no password file. Restore its original configuration before building.');
      config = { alias: 'rally-ludo-release', password: randomBytes(32).toString('hex') };
      // Save recovery information before key generation, with owner-only access.
      writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
      const generated = spawnSync(keytool, ['-genkeypair', '-noprompt', '-keystore', keystore,
        '-alias', config.alias, '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-dname', 'CN=Rally Ludo, OU=Android Release, O=Rally Ludo',
        '-storepass:env', 'RALLY_SIGNING_PASSWORD', '-keypass:env', 'RALLY_SIGNING_PASSWORD'],
      { env: { ...env, RALLY_SIGNING_PASSWORD: config.password }, encoding: 'utf8' });
      if (generated.error || generated.status !== 0) throw new Error('Could not generate release key. Preserve the signing folder and inspect the local Java/keytool setup.');
      console.log('Created release signing key. Back up private/android-signing securely for future updates.');
    }
    chmodSync(configPath, 0o600);
    chmodSync(keystore, 0o600);
    env[keys[0]] = keystore;
    env[keys[1]] = config.alias;
    env[keys[2]] = config.password;
  }
  const checked = spawnSync(keytool, ['-list', '-keystore', env[keys[0]], '-alias', env[keys[1]],
    '-storepass:env', keys[2]], { env, encoding: 'utf8' });
  if (checked.error || checked.status !== 0) throw new Error('Release signing key validation failed. Check the configured key, alias and password.');
}
