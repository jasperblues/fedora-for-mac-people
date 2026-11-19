#!/usr/bin/env bash
# Make Fedora GNOME look and feel like macOS. See README.md for what each step does.
# Asks before every step and is safe to run again. Only "dnf install" uses sudo.
set -euo pipefail
cd "$(dirname "$0")"
repo=$(pwd)
ext_dir="$HOME/.local/share/gnome-shell/extensions"
shell_major=$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask() {
    local reply
    read -r -p "$1 [Y/n] " reply
    [[ -z $reply || $reply =~ ^[Yy] ]]
}

# Add an extension to the enabled list. Works for extensions installed this session
# (gnome-extensions enable doesn't, on Wayland, until you log in again).
enable_ext() {
    python3 -I - "$1" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True, check=True).stdout.strip()
cur = cur.removeprefix("@as ")
exts = ast.literal_eval(cur)
if uuid not in exts:
    exts.append(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(exts)], check=True)
PY
}

# Install an extension from extensions.gnome.org for this GNOME version.
ego_install() {
    local uuid=$1 url
    url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell_major" |
        python3 -I -c 'import json, sys; print(json.load(sys.stdin)["download_url"])')
    curl -fsSL "https://extensions.gnome.org$url" -o "$tmp/$uuid.zip"
    gnome-extensions install --force "$tmp/$uuid.zip"
    enable_ext "$uuid"
    echo "  installed $uuid"
}

# Clone or update one of the extensions hosted on GitHub.
git_ext() {
    local uuid=$1 url=$2 dest="$ext_dir/$1"
    if [[ -d $dest/.git ]]; then
        git -C "$dest" pull --ff-only -q
    else
        git clone -q "$url" "$dest"
    fi
    [[ -d $dest/schemas ]] && glib-compile-schemas "$dest/schemas"
    enable_ext "$uuid"
    echo "  installed $uuid"
}

bold "Fedora for Mac people: GNOME $shell_major"

bold "1. Packages from Fedora (dnf; asks for your password)"
echo "  Dash to Dock, tray icons, dark GTK3 theme, Quick Look (sushi)"
if ask "Install them?"; then
    sudo dnf install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
        adw-gtk3-theme sushi git curl
    enable_ext dash-to-dock@micxgx.gmail.com
    enable_ext appindicatorsupport@rgcjonas.gmail.com
fi

bold "2. Extensions from extensions.gnome.org"
echo "  Blur my Shell (dock glass), magic lamp (genie minimise), Focused Window D-Bus (needed by Toshy)"
if ask "Install them into ~/.local?"; then
    ego_install blur-my-shell@aunetx
    ego_install compiz-alike-magic-lamp-effect@hermes83.github.com
    ego_install focused-window-dbus@flexagoon.com
fi

bold "3. Roomy Panel (macOS-style top bar spacing, clock on the right)"
if ask "Install it?"; then
    mkdir -p "$ext_dir"
    git_ext roomy-panel@jasperblues.github.io https://github.com/jasperblues/gnome-roomy-panel.git
fi

bold "4. Polite Focus (windows asking for attention come to the front, like macOS) - optional"
if ask "Install it?"; then
    mkdir -p "$ext_dir"
    git_ext polite-focus@jasperblues.github.io https://github.com/jasperblues/gnome-polite-focus.git
fi

bold "5. macOS cursor theme (github.com/ful1e5/apple_cursor)"
if ask "Install it into ~/.local/share/icons?"; then
    mkdir -p ~/.local/share/icons
    curl -fsSL https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.xz | tar -xJ -C ~/.local/share/icons
    echo "  installed"
fi

bold "6. Settings: dark mode, dock, top bar, touchpad, shortcuts"
settings="$repo/settings/mac-like.dconf"
if ask "Apply settings/mac-like.dconf?"; then
    dconf load / < "$settings"
    mkdir -p ~/.config/gtk-3.0
    ini=~/.config/gtk-3.0/settings.ini
    if ! grep -q gtk-application-prefer-dark-theme "$ini" 2>/dev/null; then
        grep -q '^\[Settings\]' "$ini" 2>/dev/null || echo '[Settings]' >> "$ini"
        echo 'gtk-application-prefer-dark-theme=1' >> "$ini"
    fi
    echo "  applied"
fi

bold "7. Cmd+Option+D toggles dock auto-hide"
if ask "Install the shortcut?"; then
    mkdir -p ~/.local/bin
    install -m 755 "$repo/extras/toggle-dock-autohide" ~/.local/bin/toggle-dock-autohide
    base=/org/gnome/settings-daemon/plugins/media-keys
    path=$base/custom-keybindings/toggle-dock/
    dconf write "$path"name "'Toggle dock auto-hide'"
    dconf write "$path"command "'$HOME/.local/bin/toggle-dock-autohide'"
    dconf write "$path"binding "'<Control><Alt>d'"
    python3 -I - "$path" <<'PY'
import ast, subprocess, sys
key = ["gsettings", "get", "org.gnome.settings-daemon.plugins.media-keys", "custom-keybindings"]
cur = subprocess.run(key, capture_output=True, text=True, check=True).stdout.strip().removeprefix("@as ")
paths = ast.literal_eval(cur)
if sys.argv[1] not in paths:
    paths.append(sys.argv[1])
    subprocess.run(["gsettings", "set", *key[2:], str(paths)], check=True)
PY
    echo "  bound to Ctrl+Alt+D (Cmd+Option+D once Toshy is running)"
fi

bold "8. Magic Mouse gestures and momentum scrolling - optional"
if ask "Install github.com/jasperblues/magic-mouse-gestures into ~/projects?"; then
    sudo dnf install -y python3-libevdev python3-gobject
    dest=~/projects/magic-mouse-gestures   # the service file expects this path
    mkdir -p ~/projects
    if [[ -d $dest/.git ]]; then git -C "$dest" pull --ff-only -q; else git clone -q https://github.com/jasperblues/magic-mouse-gestures "$dest"; fi
    systemctl --user enable --now "$dest/magic-mouse-gestures.service"
    echo "  running. It needs your user in the input group (Toshy's installer does this; otherwise see its README)."
fi

bold "Done. Next:"
cat <<EOF
  1. Log out and back in, so GNOME loads the new extensions.
  2. Install Toshy for Mac keyboard shortcuts:
       git clone https://github.com/RedBearAK/toshy.git ~/toshy && cd ~/toshy && ./setup_toshy.py install
  3. Optional: paste extras/toshy-user-keymaps.py into Toshy's user_apps section.
EOF
