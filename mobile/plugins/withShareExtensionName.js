// Shows the share extension as "Hear Me Coach" in the iOS share sheet.
// expo-share-intent uses one string for both the Xcode target name and the display name, and the
// target name must differ from the app target, so we rewrite only the display name afterwards.
const { withXcodeProject } = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

module.exports = function withShareExtensionName(config, name = 'Hear Me Coach') {
  return withXcodeProject(config, async cfg => {
    const plist = path.join(cfg.modRequest.platformProjectRoot, 'ShareExtension', 'ShareExtension-Info.plist');
    if (fs.existsSync(plist)) {
      fs.writeFileSync(plist, fs.readFileSync(plist, 'utf8').replace(
        /(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*(<\/string>)/, `$1${name}$2`));
    }
    return cfg;
  });
};
