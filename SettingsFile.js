// The location of OmaDroid's settings file, shared by every Core.Settings.
/** The file:// URL of OmaDroid's own omadroid.ini. A plain function rather
 * than a property passed down, so every Core.Settings has its location when
 * it is constructed: an empty location made QSettings fail to initialize.
 * Example: omadroidIniUrl("", "/home/me") → "file:///home/me/.config/omarchy/omadroid.ini"
 * @param {string} configHome XDG_CONFIG_HOME, or "" when unset
 * @param {string} home HOME
 * @returns {string}
 */
function omadroidIniUrl(configHome, home) {
  return "file://" + encodeURI((configHome || home + "/.config") + "/omarchy/omadroid.ini");
}
