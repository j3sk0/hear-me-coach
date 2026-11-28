// Adds the Firebase config for Android push notifications once google-services.json exists.
const fs = require('fs');
const path = require('path');

module.exports = ({ config }) => {
  const gs = path.join(__dirname, 'google-services.json');
  if (fs.existsSync(gs)) config.android = { ...config.android, googleServicesFile: './google-services.json' };
  return config;
};
