import { spawnSync } from 'node:child_process';
import { cpSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { androidBuildEnvironment } from './android-build-env.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
const tools=path.join(root,'.tools/media-android');
const bundledGradle=path.join(tools,'gradle-8.11.1/bin/gradle');
const env=androidBuildEnvironment();
const bundled=existsSync(bundledGradle);
const command=env.GRADLE_BIN||(bundled?bundledGradle:'gradle');
const result=spawnSync(command,['-p',path.join(root,'apps/godot/android-plugin'),'packageGodotAddon','--console=plain'],{cwd:root,env,stdio:'inherit'});
if(result.error){console.error('Install JDK 17, Gradle 8.11.1 and Android SDK 35, or set JAVA_HOME, ANDROID_HOME and GRADLE_BIN.');process.exit(1);}
if(result.status!==0)process.exit(result.status??1);
cpSync(path.join(root,'apps/godot/android-plugin/build/godot-addon/addons/rally_media'),path.join(root,'apps/godot/addons/rally_media'),{recursive:true});
console.log('RallyMedia debug/release plugin installed in the Godot project.');
