#!/usr/bin/env python3
# Removes the password of the "Default keyring" (gnome-keyring), like Omarchy.
# The disk is encrypted (LUKS) and the session opens with autologin: the keyring cannot be
# unlocked by PAM, and a password would only add the "Authentication required" prompt.
# Asks for the old password (not displayed, never written to disk) and replaces it with an empty one.
# Prerequisite: python3-gobject. The internal call requires a Secret Service session open on the same
# D-Bus connection, hence Python rather than busctl.
import getpass, os, shutil, sys, time
from gi.repository import Gio, GLib

NAME = "org.freedesktop.secrets"
COLL = "/org/freedesktop/secrets/collection/Default_5fkeyring"
KEYRINGS = os.path.expanduser("~/.local/share/keyrings")

if not os.path.isdir(KEYRINGS):
    sys.exit("pas de trousseau dans ~/.local/share/keyrings")
shutil.copytree(KEYRINGS, f"{KEYRINGS}.bak-{time.strftime('%Y%m%d-%H%M%S')}")

old = getpass.getpass("Ancien mot de passe du trousseau: ").encode()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

def call(path, iface, method, args, sig):
    return bus.call_sync(NAME, path, iface, method, GLib.Variant(sig, args), None,
                         Gio.DBusCallFlags.NONE, -1, None)

# "plain" session: the secrets go in clear over the session bus (local to the user)
_, session = call("/org/freedesktop/secrets", "org.freedesktop.Secret.Service", "OpenSession",
                  ("plain", GLib.Variant("s", "")), "(sv)").unpack()
try:
    call("/org/freedesktop/secrets", "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
         "ChangeWithMasterPassword",
         (COLL, (session, b"", old, "text/plain"), (session, b"", b"", "text/plain")),
         "(o(oayays)(oayays))")
except GLib.Error as e:
    sys.exit(f"échec: {e.message} (ancien mot de passe incorrect?)")
finally:
    call(session, "org.freedesktop.Secret.Session", "Close", (), "()")

locked = bus.call_sync(NAME, COLL, "org.freedesktop.DBus.Properties", "Get",
                       GLib.Variant("(ss)", ("org.freedesktop.Secret.Collection", "Locked")),
                       None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
print(f"Mot de passe retiré. Trousseau verrouillé: {locked}")
