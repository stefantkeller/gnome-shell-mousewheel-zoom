// gnome-shell-mousewheel-zoom

// (c) Mar 2012, Tobias Quinn <tobias@tobiasquinn.com>
// GPLv3

// vala ref man: http://www.masella.name/~andre/libgit2/x11/X.html

using X;
using GLib;

// to find key (keyboard)/button (mouse) encryption:
// google for documentation 'Xlib − C Language X Interface'
// less /usr/share/X11/xkb/keycodes/evdev
// xev

const int MOUSEWHEEL_UP   = 4;
const int MOUSEWHEEL_DOWN = 5;

// panic button: once one has zoomed in and wants zoom back out click (while still pressing chosen modifier-key (alt as default)) right.
// TODO: make it selectable in settings
const int ESC_BUTTON = 3; // right mouse button (according to xev...)

const int[] BUTTONS = { MOUSEWHEEL_UP, MOUSEWHEEL_DOWN, ESC_BUTTON };
const int[] MASKS = { 0, X.KeyMask.Mod2Mask, X.KeyMask.LockMask , X.KeyMask.LockMask | X.KeyMask.Mod2Mask };

[DBus (name = "org.gnome.Magnifier")]
interface Magnifier : Object {
    public abstract bool isActive() throws IOError;
    public abstract void setActive(bool active) throws IOError;
    public abstract GLib.ObjectPath[] getZoomRegions() throws IOError;
}

[DBus (name = "org.gnome.Magnifier.ZoomRegion")]
interface ZoomRegion : Object {
    public abstract void setMagFactor(double xMagFactor, double yMagFactor) throws IOError;
    public abstract double getMagFactor() throws IOError;
}

class Zoomer : GLib.Object {
    // DBus proxy objects
    private Magnifier mag;
    private ZoomRegion zoom;

    // Zoom state
    private const double incr = 0.1;
    private double current_zoom;
    private bool zoom_active;
    private bool interfaces_active;

    public Zoomer() {
        interfaces_active = false;
        mag = Bus.get_proxy_sync(BusType.SESSION,
                "org.gnome.Magnifier",
                "/org/gnome/Magnifier");
        do {
            refresh_dbus();
        } while (!interfaces_active);
        // get current zoom state
        zoom_active = mag.isActive();
        if (zoom_active) {
            current_zoom = zoom.getMagFactor();
        } else {
            current_zoom = 1;
        }
    }

    private void refresh_dbus() {
        try {
            // refresh zoom regions (exposes ZoomRegion interface)
            mag.getZoomRegions();
            zoom = Bus.get_proxy_sync(BusType.SESSION,
                    "org.gnome.Magnifier",
                    "/org/gnome/Magnifier/ZoomRegion/zoomer0");
            interfaces_active = true;
        } catch (Error e) {
        }
    }

    public void zoomIn() {
        if (zoom_active) {
            current_zoom *= (1 + incr);
        } else {
            current_zoom *= (1 + incr);
            mag.setActive(true);
            zoom_active = true;
        }
        try {
            zoom.setMagFactor(current_zoom, current_zoom);
        } catch (Error e) {
            refresh_dbus();
        }
    }

    public void zoomOut() {
        if (zoom_active) {
            current_zoom *= (1.0 - incr);
            if (current_zoom <= 1) {
                current_zoom = 1;
                mag.setActive(false);
                zoom_active = false;
            } else {
                try {
                    zoom.setMagFactor(current_zoom, current_zoom);
                } catch (Error e) {
                    refresh_dbus();
                }
            }
        }
    }
    
    public void zoomEsc() {
        current_zoom = 1;
        if (zoom_active) {
            mag.setActive(false);
            zoom_active = false;
        }
        try {
            zoom.setMagFactor(current_zoom, current_zoom);
        } catch (Error e) {
            refresh_dbus();
        }
    }
}

class WatchForMagnifier : GLib.Object {
    private MainLoop loop;

    public WatchForMagnifier() {
        // for now this blocks till the interface appears
        DBusConnection conn = Bus.get_sync(BusType.SESSION);
        Bus.watch_name_on_connection(conn,
                "org.gnome.Magnifier",
                BusNameWatcherFlags.NONE,
                on_name_appeared,
                on_name_vanished);
        this.loop = new MainLoop();
        this.loop.run();
    }

    private void on_name_appeared() {
        message("name appeared\n");
        this.loop.quit();
    }

    private void on_name_vanished() {
        message("name vanished\n");
    }
}

void main(string[] arg) {
    // wait for the magnifier interface to appear
    WatchForMagnifier wfm = new WatchForMagnifier();

    // load appropriate key from dconf configuration (dconf-editor)
    var settings = new Settings("com.tobiasquinn.mousewheelzoom");
    string key = settings.get_string("modifier-key");
    // default to ALT as modifier
    int keymask = X.KeyMask.Mod1Mask;
    switch (key) {
        case "ctrl":
            keymask = X.KeyMask.ControlMask;
            break;
        case "shift":
            keymask = X.KeyMask.ShiftMask;
            break;
    }
    // grab the chosen key and scrollwheel
    X.Display disp = new X.Display();
    X.Window root = disp.default_root_window();
    foreach (int button in BUTTONS) {
        foreach (int mask in MASKS) {
            disp.grab_button(button,
                    keymask | mask,
                    root,
                    false,
                    0,
                    X.GrabMode.Async,
                    X.GrabMode.Async,
                    0,
                    0);
        }
    }

    // process the X events
    X.Event evt = Event();
    Zoomer zoom = new Zoomer();
    while (true) {
        disp.next_event(ref evt);
        switch(evt.xbutton.button) {
            case MOUSEWHEEL_UP:
                zoom.zoomIn();
                break;

            case MOUSEWHEEL_DOWN:
                zoom.zoomOut();
                break;

            case ESC_BUTTON: // panic mode
                zoom.zoomEsc();
                break;

            default:
                stdout.printf("mousewheelzoom (vala) uncaught event\n");
                break;
        }
    }
}
