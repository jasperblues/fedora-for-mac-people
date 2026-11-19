#!/usr/bin/env bash
# Take README screenshots in a throwaway headless GNOME Shell. Your real session and settings are not touched.
#
#   tools/shots.sh before   stock Fedora GNOME (no settings, no extra extensions, default fonts)
#   tools/shots.sh after    the setup from this guide (settings/mac-like.dconf + the extensions)
#
# Output: docs/img/<mode>-desktop.png and <mode>-overview.png
# Needs: mutter-devkit (dnf), and for "after" the cursor and extensions from the guide installed in ~/.local.
set -euo pipefail
mode=${1:?usage: tools/shots.sh before|after}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
out="$repo/docs/img"
size=${SHOT_SIZE:-1440x900}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# A fake home, so the windows show demo files and none of your own folders or mounts.
home="$tmp/home"
data="$home/.local/share"
mkdir -p "$out" "$data/gnome-shell/extensions" "$home/.config" "$tmp/runtime"
chmod 700 "$tmp/runtime"
cp -r "$here/demo-files/." "$home/"
ext="$data/gnome-shell/extensions"
ln -s "$here/shot-helper@local" "$ext/shot-helper@local"

if [[ $mode == before ]]; then
    uuids="'background-logo@fedorahosted.org', 'shot-helper@local'"
    load=""
else
    # Cursor theme from ~/.local. Fonts deliberately stay the system ones (the guide uses GNOME's defaults).
    [[ -d $HOME/.local/share/icons ]] && ln -s "$HOME/.local/share/icons" "$data/icons"
    # Extensions installed per-user (system ones in /usr/share are found automatically).
    for d in "$HOME"/.local/share/gnome-shell/extensions/*/; do
        ln -s "${d%/}" "$ext/$(basename "$d")"
    done
    uuids="'dash-to-dock@micxgx.gmail.com', 'appindicatorsupport@rgcjonas.gmail.com', 'blur-my-shell@aunetx',"
    uuids+=" 'compiz-alike-magic-lamp-effect@hermes83.github.com', 'roomy-panel@jasperblues.github.io', 'shot-helper@local'"
    load="dconf load / < '$repo/settings/mac-like.dconf'
dconf write /org/gnome/shell/favorite-apps \"['org.gnome.Nautilus.desktop', 'org.mozilla.firefox.desktop', 'com.mitchellh.ghostty.desktop', 'org.gnome.Calendar.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Software.desktop', 'org.gnome.Settings.desktop']\""
fi

cat > "$tmp/inner.sh" <<INNER
#!/bin/bash
dconf write /org/gnome/shell/enabled-extensions "[$uuids]"
dconf write /org/gnome/shell/welcome-dialog-last-shown-version "'999'"
$load
timeout 40 gnome-shell --headless --virtual-monitor $size --wayland --no-x11 > "$tmp/shell.log" 2>&1
true
INNER
chmod +x "$tmp/inner.sh"
env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME -u XDG_STATE_HOME \
    HOME="$home" XDG_RUNTIME_DIR="$tmp/runtime" SHOT_DIR="$out" SHOT_PREFIX="$mode" SHOT_DEMO="$home" \
    dbus-run-session -- "$tmp/inner.sh" 2>/dev/null
grep -E 'SHOT|JS ERROR' "$tmp/shell.log" || true
ls "$out/$mode"-*.png
