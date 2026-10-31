# Sourced by device-volume.sh and app-labels.sh: the private cache of each
# phone's app names and audio codes.
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/omadroid"
# The cache lists the phone's installed apps, so it is private to this user,
# also when an older version left it readable under a 022 umask.
umask 077
private_cache() {
  mkdir -p -m 700 -- "$cache_root" "$1" &&
    find "$cache_root" -perm /077 \( -type d -o -type f \) -exec chmod go= -- {} +
}

# "APPID PACKAGE LABEL" per package, from `pm` and `scrcpy --list-apps`.
apps_file() {
  printf '%s/apps/%s.tsv' "$cache_root" "$1"
}

# "PACKAGE LABEL" read from the APKs of apps scrcpy doesn't name.
labels_file() {
  printf '%s/app-labels/%s.tsv' "$cache_root" "$1"
}

# Packages whose label couldn't be read; retried once the file is a day old.
failed_labels_file() {
  printf '%s/app-labels/%s.failed' "$cache_root" "$1"
}
