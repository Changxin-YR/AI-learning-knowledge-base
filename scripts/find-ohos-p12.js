const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const Module = require('module');

const load = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === '@ohos/hvigor') {
    return { HvigorLogger: class { static getInstance() { return new this(); } } };
  }
  if (request === '@ohos/hvigor-logger') {
    return { HvigorOhosPluginAdaptor: class {} };
  }
  return load.call(this, request, parent, isMain);
};

const profilePath = process.argv[2];
const configDir = process.argv[3] || path.join(process.env.USERPROFILE, '.ohos', 'config');
const targetP12 = process.argv[4];
if (!profilePath) throw new Error('Usage: node find-ohos-p12.js <build-profile.json5> [config-dir]');

const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
const encrypted = profile.app.signingConfigs[0].material.storePassword;
const { DecipherUtil } = require('C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor-ohos-plugin/src/utils/decipher-util.js');
const password = DecipherUtil.decryptPwd(configDir, encrypted, profilePath);

const candidates = targetP12 ? [path.basename(targetP12)] : fs.readdirSync(configDir).filter((name) => name.endsWith('.p12'));
for (const file of candidates) {
  try {
    execFileSync('keytool', ['-list', '-keystore', path.join(configDir, file), '-storepass', password], { stdio: 'ignore' });
    console.log(file);
  } catch (_) {}
}
