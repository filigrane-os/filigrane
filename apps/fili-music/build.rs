// QML interface compiled into the binary (module Fili.Baladeur, qrc:/qt/qml/Fili/Baladeur/qml/), Rust objects of src/bridge.rs
use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    // Version of the About card: tag or commit of the repository (absent outside a repository)
    if let Ok(o) = std::process::Command::new("git").args(["describe", "--tags", "--always", "--dirty"]).output()
        && o.status.success()
    {
        println!("cargo:rustc-env=FILI_MUSIC_GIT={}", String::from_utf8_lossy(&o.stdout).trim());
    }
    CxxQtBuilder::new_qml_module(
        QmlModule::new("Fili.Baladeur")
            .qml_files([
                "qml/AlbumCard.qml",
                "qml/AlbumDetail.qml",
                "qml/AlbumGrid.qml",
                "qml/AlbumsView.qml",
                "qml/ArtistsView.qml",
                "qml/Artwork.qml",
                "qml/ContextMenu.qml",
                "qml/FiliScrollBar.qml",
                "qml/FilterBar.qml",
                "qml/FocusRing.qml",
                "qml/GenresView.qml",
                "qml/IconButton.qml",
                "qml/KineticScroll.qml",
                "qml/Main.qml",
                "qml/PlayerControls.qml",
                "qml/PlaylistView.qml",
                "qml/PromptDialog.qml",
                "qml/QueuePanel.qml",
                "qml/ScannerDialog.qml",
                "qml/SearchView.qml",
                "qml/TextButton.qml",
                "qml/TagField.qml",
                "qml/TagEditor.qml",
                "qml/TrackTable.qml",
                "qml/TracksView.qml",
                "qml/VolumeDial.qml",
                "qml/WindowGlyph.qml",
                "qml/WindowPanel.qml",
            ])
            .qml_file(QmlFile::from("qml/FiliTheme.qml").singleton(true))
            .qml_file(QmlFile::from("qml/Store.qml").singleton(true))
            .depend("QtQuick")
            .depend("QtQuick.Controls"),
    )
    // Fonts of the interface travel with the binary: the application looks the same on any distribution
    .qrc_resources(["fonts/Jost-Variable.ttf", "fonts/JetBrainsMono-Variable.ttf", "fonts/FiliIcons.ttf"])
    .qt_module("Quick")
    .files(["src/bridge.rs"])
    .build();
}
