# Additions for Toshy (https://github.com/RedBearAK/toshy).
# Paste these between the "SLICE_MARK_START: user_apps" and "SLICE_MARK_END: user_apps"
# lines in ~/.config/toshy/toshy_config.py (edits there survive Toshy upgrades), then
# restart Toshy: systemctl --user restart toshy-config.service

# Cmd+; opens overview search too: a second Spotlight key alongside Cmd+Space.
keymap("User: Cmd+; opens GNOME overview search (Spotlight)", {
    C("RC-Semicolon"):          C("Shift-C-Space"),             # = toggle-overview (set by Toshy GNOME tweaks)
}, when = lambda ctx:
    cnfg.screen_has_focus and
    not ctx_app_is_remote
)

keymap("User: Cmd+W closes window in GNOME apps without Ctrl+W", {
    C("RC-W"):                  C("Alt-F4"),                    # macOS-like close window
}, when = lambda ctx:
    cnfg.screen_has_focus and
    not ctx_app_is_remote and
    matchProps(clas="^org\\.gnome\\.(Software|Settings)$")(ctx)
)

# Cmd+V in terminals with an image-only clipboard: send Ctrl+V so TUIs like Claude Code
# read the image themselves. On macOS the terminal sends an empty paste that Claude Code
# picks up; Linux terminals send nothing when the clipboard has no text.
def _user_terminal_paste():
    try:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True,
                               text=True, timeout=0.3).stdout.split()
    except Exception:
        types = []
    has_text = any(t.startswith("text/plain") or t in ("UTF8_STRING", "STRING", "TEXT") for t in types)
    has_image = any(t.startswith("image/") for t in types)
    return C("C-v") if has_image and not has_text else C("C-Shift-v")

keymap("User: terminals - Cmd+V pastes images too", {
    C("RC-v"):                  _user_terminal_paste,
}, when = lambda ctx:
    cnfg.screen_has_focus and
    hmp_is_terminal(ctx)
)
