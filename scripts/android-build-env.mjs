import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const tools = path.join(root, '.tools/media-android');

// Both build processes need the same SDK/JDK; child environment changes do not
// carry over from the plugin build to the subsequent Godot export.
export function androidBuildEnvironment() {
  const env = { ...process.env };
  const java = path.join(tools, 'jdk/usr/lib/jvm/java-17-openjdk-amd64');
  if (!env.JAVA_HOME && existsSync(java)) env.JAVA_HOME = java;
  if (!env.ANDROID_HOME) {
    if (env.ANDROID_SDK_ROOT) env.ANDROID_HOME = env.ANDROID_SDK_ROOT;
    else if (existsSync(path.join(tools, 'sdk'))) env.ANDROID_HOME = path.join(tools, 'sdk');
  }
  if (!env.GRADLE_USER_HOME && existsSync(path.join(tools, 'gradle-8.11.1'))) {
    env.GRADLE_USER_HOME = path.join(tools, 'gradle-cache');
  }
  return env;
}

export function configureGodotAndroid(env) {
  const executable = process.platform === 'win32' ? '.exe' : '';
  if (!env.JAVA_HOME || !existsSync(path.join(env.JAVA_HOME, `bin/java${executable}`))) {
    throw new Error('Android export needs a valid JAVA_HOME pointing to JDK 17.');
  }
  if (!env.ANDROID_HOME || !existsSync(path.join(env.ANDROID_HOME, `platform-tools/adb${executable}`)) || !existsSync(path.join(env.ANDROID_HOME, 'build-tools'))) {
    throw new Error('Android export needs ANDROID_HOME pointing to an SDK containing platform-tools and build-tools.');
  }
  // Use project-local editor settings rather than changing the user's editor.
  env.XDG_CONFIG_HOME ||= path.join(root, '.tools/godot-config');
  const directory = path.join(env.XDG_CONFIG_HOME, 'godot');
  mkdirSync(directory, { recursive: true });
  const filename = path.join(directory, 'editor_settings-4.6.tres');
  let settings = existsSync(filename) ? readFileSync(filename, 'utf8') : '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n';
  function set(key, value) {
    const line = `${key} = ${JSON.stringify(value)}`;
    const previous = settings.split('\n').find(entry => entry.startsWith(`${key} = `));
    settings = previous ? settings.replace(previous, line) : `${settings.trimEnd()}\n${line}\n`;
  }
  set('export/android/java_sdk_path', env.JAVA_HOME);
  set('export/android/android_sdk_path', env.ANDROID_HOME);
  const keystore = path.join(tools, 'debug.keystore');
  if (existsSync(keystore)) {
    set('export/android/debug_keystore', keystore);
    set('export/android/debug_keystore_pass', 'android');
  }
  writeFileSync(filename, settings);
}
