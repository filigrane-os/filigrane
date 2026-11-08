// File watched with inotify (even absent at the start): exists and content follow it. printErrors is off since a missing
// file is a normal state.
import QtQuick
import Quickshell.Io

FileView {
    property bool exists: false
    property string content: ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
        exists = true;
        content = text();
    }
    onLoadFailed: {
        exists = false;
        content = "";
    }
}
