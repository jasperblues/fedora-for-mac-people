// Helper for tools/shots.sh. Runs inside a throwaway headless GNOME Shell:
// opens two demo windows, arranges them, and saves desktop + overview screenshots.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(Shell.Screenshot.prototype, 'screenshot');
const OUT = GLib.getenv('SHOT_DIR');
const PREFIX = GLib.getenv('SHOT_PREFIX');
const DEMO = GLib.getenv('SHOT_DEMO');
const wait = ms => new Promise(r => GLib.timeout_add(0, ms, () => { r(); return GLib.SOURCE_REMOVE; }));

async function shot(name) {
    const file = Gio.File.new_for_path(`${OUT}/${PREFIX}-${name}.png`);
    const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null);
    await new Shell.Screenshot().screenshot(false, stream);
    stream.close(null);
}

function launch(desktopId, path) {
    const app = Gio.DesktopAppInfo.new(desktopId);
    if (!app) {
        console.log(`SHOT missing app ${desktopId}`);
        return;
    }
    app.launch_uris([Gio.File.new_for_path(path).get_uri()], global.create_app_launch_context(0, -1));
}

function arrange() {
    const area = Main.layoutManager.getWorkAreaForMonitor(0);
    const pad = Math.round(area.width * 0.05);
    for (const actor of global.get_window_actors()) {
        const w = actor.meta_window;
        const cls = (w.get_wm_class() ?? '').toLowerCase();
        console.log(`SHOT window ${cls}`);
        if (cls.includes('nautilus'))
            w.move_resize_frame(false, area.x + pad, area.y + pad, Math.round(area.width * 0.55), Math.round(area.height * 0.62));
        else if (cls.includes('texteditor'))
            w.move_resize_frame(false, area.x + Math.round(area.width * 0.40), area.y + Math.round(area.height * 0.30),
                Math.round(area.width * 0.50), Math.round(area.height * 0.60));
    }
}

// Type into the focused window with a virtual keyboard.
let keyboard = null;
function press(keyval, mods = []) {
    keyboard ??= global.stage.context.get_backend().get_default_seat().create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
    const t = GLib.get_monotonic_time();
    for (const m of mods) keyboard.notify_keyval(t, m, Clutter.KeyState.PRESSED);
    keyboard.notify_keyval(t, keyval, Clutter.KeyState.PRESSED);
    keyboard.notify_keyval(t, keyval, Clutter.KeyState.RELEASED);
    for (const m of mods.reverse()) keyboard.notify_keyval(t, m, Clutter.KeyState.RELEASED);
}
async function type(text) {
    for (const ch of text) {
        press(Clutter.unicode_to_keysym(ch.codePointAt(0)));
        await wait(30);
    }
    press(Clutter.KEY_Return);
    await wait(400);
}

// Ghostty with four coloured tabs, each in a different folder (only in the "after" run).
async function terminalShot() {
    for (const actor of global.get_window_actors())
        actor.meta_window.minimize();
    // Started directly: its desktop file uses D-Bus activation through systemd, which this throwaway session lacks.
    Gio.AppInfo.create_from_commandline('ghostty --gtk-single-instance=false', null, Gio.AppInfoCreateFlags.NONE)
        .launch([], global.create_app_launch_context(0, -1));
    await wait(5000);
    const dirs = ['Projects', 'Music', 'Garden\\ Plans', 'Invoices'];
    for (let i = 0; i < dirs.length; i++) {
        if (i > 0) {
            press(Clutter.KEY_t, [Clutter.KEY_Control_L, Clutter.KEY_Shift_L]);
            await wait(3500);
        }
        await type(`cd ~/${dirs[i]} && clear`);
    }
    press(Clutter.KEY_1, [Clutter.KEY_Alt_L]);   // back to the first tab
    await wait(500);
    await type('ls');
    const area = Main.layoutManager.getWorkAreaForMonitor(0);
    for (const actor of global.get_window_actors()) {
        const w = actor.meta_window;
        if ((w.get_wm_class() ?? '').toLowerCase().includes('ghostty'))
            w.move_resize_frame(false, area.x + Math.round(area.width * 0.12), area.y + Math.round(area.height * 0.12),
                Math.round(area.width * 0.70), Math.round(area.height * 0.62));
    }
    await wait(1500);
    await shot('terminal');
}

export default class extends Extension {
    enable() {
        (async () => {
            try {
                await wait(6000);
                Main.overview.hide();
                launch('org.gnome.Nautilus.desktop', `${DEMO}/Projects`);
                await wait(2500);
                launch('org.gnome.TextEditor.desktop', `${DEMO}/Projects/notes.md`);
                await wait(5000);
                arrange();
                await wait(2500);
                await shot('desktop');
                Main.overview.show();
                await wait(2500);
                await shot('overview');
                if (PREFIX === 'after') {
                    Main.overview.hide();
                    await wait(1500);
                    await terminalShot();
                }
                console.log('SHOT done');
            } catch (e) {
                console.error('SHOT', e);
            }
        })();
    }

    disable() {}
}
