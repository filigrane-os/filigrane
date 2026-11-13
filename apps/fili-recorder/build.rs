// QML interface compiled into the binary (module Fili.Cassette, qrc:/qt/qml/Fili/Cassette/qml/), Rust objects of src/bridge.rs
use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    // Version of the About card: tag or commit of the repository (absent outside a repository)
    if let Ok(o) = std::process::Command::new("git").args(["describe", "--tags", "--always", "--dirty"]).output()
        && o.status.success()
    {
        println!("cargo:rustc-env=FILI_RECORDER_GIT={}", String::from_utf8_lossy(&o.stdout).trim());
    }
    CxxQtBuilder::new_qml_module(
        QmlModule::new("Fili.Cassette")
            .qml_files([
                "qml/Main.qml",
                "qml/SourcePicker.qml",
                "qml/IconButton.qml",
                "qml/TextButton.qml",
                "qml/ViewSwitch.qml",
                "qml/ContextMenu.qml",
                "qml/WindowGlyph.qml",
                "qml/WindowPanel.qml",
                "qml/FocusRing.qml",
                "qml/FiliScrollBar.qml",
                "qml/KineticScroll.qml",
            ])
            .qml_file(QmlFile::from("qml/FiliTheme.qml").singleton(true))
            .depend("QtQuick")
            .depend("QtQuick.Controls"),
    )
    // Fonts of the interface travel with the binary: the application looks the same on any distribution
    .qrc_resources([
        "fonts/Jost-Variable.ttf",
        "fonts/JetBrainsMono-Variable.ttf",
        "fonts/FiliIcons.ttf",
        "icons/fili-recorder.svg",
    ])
    .qt_module("Quick")
    .files(["src/bridge.rs"])
    .build();
}
