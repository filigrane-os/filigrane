// Tag editor: one track, an album (its title, artist, year, genres) or several tracks at once (artist, album, year, genres
// shared by all; a field whose values differ shows "Mixed" and is left alone while empty). Artwork can come from an image file or
// MusicBrainz, "Scrape" fills the fields from MusicBrainz. Saving updates the library, then asks whether to write the tags into
// the audio files too. The core does the work (update_*_metadata, write_*_file_tags, scrape_*, set_*_artwork_*).
import QtQuick
import Fili.Baladeur

Rectangle {
    id: ed
    // "track", "album" or "tracks"; the id of the track or album, or the ids of the tracks
    property string mode: "track"
    property var ids: []
    property var genres: []
    property bool mixedArtist: false
    property bool mixedAlbum: false
    property bool mixedYear: false
    property var suggestions: ({ artist: [], genre: [], album: [], year: [] })
    property bool busy: false
    property string error: ""
    property string scrapeError: ""
    property string artError: ""
    // Artwork: an image file chosen, a MusicBrainz release chosen, or removal asked; applied on save
    property string artPath: ""
    property string artMusicBrainz: ""
    property bool artRemoved: false
    property int albumId: -1
    // Candidates of a MusicBrainz search, and what choosing one does ("fields" or "artwork")
    property var candidates: []
    property string pickFor: "fields"
    property bool picking: false
    // After a save: the files of these tracks can be written; errors of that write
    property bool askWrite: false
    property var writeErrors: []
    property int fileCount: 1

    signal closed()

    visible: false
    anchors.fill: parent
    z: 270
    color: FiliTheme.alpha(FiliTheme.background, 0.6)
    focus: visible
    Keys.onEscapePressed: if (!busy && !askWrite)
        close()

    readonly property bool isTrack: mode === "track"
    readonly property bool isAlbum: mode === "album"
    readonly property bool isMulti: mode === "tracks"
    readonly property string heading: isTrack ? Fili.tr("Edit track") : isAlbum ? Fili.tr("Edit album") : Fili.tr("Edit %1 tracks").replace("%1", ids.length)

    function open(m, list) {
        mode = m;
        ids = list;
        genres = [];
        error = scrapeError = artError = "";
        artPath = artMusicBrainz = "";
        artRemoved = false;
        askWrite = false;
        writeErrors = [];
        picking = false;
        mixedArtist = mixedAlbum = mixedYear = false;
        for (const f of [fTitle, fArtist, fAlbum, fAlbumArtist, fYear, fTrack, fDisc, fNewGenre, fImage])
            f.text = "";
        visible = true;
        load();
        ["artist", "genre", "album", "year"].forEach(k => Store.callAsync("get_metadata_suggestions", [k], d => {
            const s = Object.assign({}, ed.suggestions);
            s[k] = d && d.values ? d.values : [];
            ed.suggestions = s;
        }));
    }
    function close() {
        visible = false;
        closed();
    }
    function names(list) {
        return (list || []).map(g => g.name);
    }
    function load() {
        busy = true;
        if (isTrack) {
            Store.callAsync("get_track_by_id", [ids[0]], t => {
                if (!t) {
                    busy = false;
                    error = Fili.tr("Track not found.");
                    return;
                }
                fTitle.text = t.title;
                fArtist.text = Store.trackArtist(t);
                fTrack.text = t.track_number ? String(t.track_number) : "";
                fDisc.text = t.disc_number ? String(t.disc_number) : "";
                fYear.text = t.year ? String(t.year) : "";
                albumId = t.album_id === null || t.album_id === undefined ? -1 : t.album_id;
                if (albumId >= 0)
                    Store.callAsync("get_album_by_id", [albumId], a => {
                        if (a) {
                            fAlbum.text = a.title;
                            fAlbumArtist.text = a.artist_name;
                            if (fYear.text === "" && a.year)
                                fYear.text = String(a.year);
                        }
                    });
                Store.callAsync("get_track_genres", [ids[0]], g => {
                    genres = names(g ? g.genres : []);
                    busy = false;
                });
            });
        } else if (isAlbum) {
            albumId = ids[0];
            Store.callAsync("get_album_by_id", [albumId], a => {
                if (!a) {
                    busy = false;
                    error = Fili.tr("Album not found.");
                    return;
                }
                fTitle.text = a.title;
                fArtist.text = a.artist_name;
                fYear.text = a.year ? String(a.year) : "";
                Store.callAsync("get_album_genres", [albumId], g => {
                    genres = names(g ? g.genres : []);
                    busy = false;
                });
            });
            Store.callAsync("get_album_tracks", [albumId], d => fileCount = d ? d.tracks.length : 1);
        } else {
            fileCount = ids.length;
            Store.callAsync("tracks_by_ids", [JSON.stringify(ids)], list => {
                if (!list || list.length === 0) {
                    busy = false;
                    error = Fili.tr("No tracks found.");
                    return;
                }
                const same = (xs) => xs.length > 0 && xs.every(x => x === xs[0]);
                const artists = list.map(t => Store.trackArtist(t));
                mixedArtist = !same(artists);
                fArtist.text = mixedArtist ? "" : artists[0];
                const years = list.map(t => t.year ? String(t.year) : "").filter(y => y !== "");
                mixedYear = !same(years) && years.length > 0;
                fYear.text = !mixedYear && years.length > 0 ? years[0] : "";
                const albumIds = Array.from(new Set(list.map(t => t.album_id).filter(a => a !== null && a !== undefined)));
                const titles = [];
                let left = albumIds.length;
                const done = () => {
                    mixedAlbum = new Set(titles).size > 1;
                    fAlbum.text = !mixedAlbum && titles.length > 0 ? titles[0] : "";
                };
                if (left === 0)
                    done();
                albumIds.forEach(id => Store.callAsync("get_album_by_id", [id], a => {
                    if (a)
                        titles.push(a.title);
                    if (--left === 0)
                        done();
                }));
                // Genres shared by every track
                let sets = [], pending = ids.length;
                ids.forEach((id, i) => Store.callAsync("get_track_genres", [id], g => {
                    sets[i] = names(g ? g.genres : []);
                    if (--pending === 0) {
                        genres = sets[0].filter(x => sets.every(s => s.indexOf(x) >= 0)).sort();
                        busy = false;
                    }
                }));
            });
        }
    }

    // ---- Genres ----------------------------------------------------------------------------------------------------
    function addGenre() {
        const g = fNewGenre.text.trim();
        if (g !== "" && genres.indexOf(g) < 0)
            genres = genres.concat([g]);
        fNewGenre.text = "";
    }

    // ---- MusicBrainz -------------------------------------------------------------------------------------------------
    function scrape() {
        scrapeError = "";
        let name, args;
        if (isTrack) {
            if (fTitle.text.trim() === "" && fArtist.text.trim() === "") {
                scrapeError = Fili.tr("Enter a title or artist first");
                return;
            }
            name = "scrape_track_by_query";
            args = [fTitle.text.trim(), fArtist.text.trim()];
        } else {
            if (fTitle.text.trim() === "" && fArtist.text.trim() === "") {
                scrapeError = Fili.tr("Enter a title or artist first");
                return;
            }
            name = "scrape_album_by_query";
            args = [fTitle.text.trim(), fArtist.text.trim()];
        }
        search(name, args, "fields");
    }
    function scrapeArtwork() {
        artError = "";
        if (isTrack)
            search("scrape_track_by_query", [fTitle.text.trim(), fArtist.text.trim()], "artwork");
        else if (isAlbum)
            search("scrape_album_by_query", [fTitle.text.trim(), fArtist.text.trim()], "artwork");
        else if (mixedAlbum || fAlbum.text.trim() === "")
            artError = Fili.tr("Artwork search needs all the tracks to share the same album");
        else
            search("scrape_album_by_query", [fAlbum.text.trim(), fArtist.text.trim()], "artwork");
    }
    function search(name, args, forWhat) {
        busy = true;
        Store.callAsyncRaw(name, args, r => {
            busy = false;
            const list = r.success && r.data && r.data.candidates ? r.data.candidates : [];
            const message = r.success ? (list.length === 0 ? Fili.tr("No results found") : "") : Fili.tr("Network error: %1").replace("%1", r.error || "");
            if (message !== "") {
                if (forWhat === "fields")
                    scrapeError = message;
                else
                    artError = message;
                return;
            }
            if (list.length === 1)
                choose(list[0], forWhat);
            else {
                candidates = list;
                pickFor = forWhat;
                picking = true;
            }
        });
    }
    function choose(c, forWhat) {
        picking = false;
        if (forWhat === "artwork") {
            artMusicBrainz = c.musicbrainz_id;
            artPath = "";
            artRemoved = false;
            return;
        }
        fTitle.text = c.title;
        fArtist.text = c.artist;
        if (isTrack) {
            if (c.album_artist)
                fAlbumArtist.text = c.album_artist;
            if (c.album)
                fAlbum.text = c.album;
            if (c.track_number)
                fTrack.text = String(c.track_number);
            if (c.disc_number)
                fDisc.text = String(c.disc_number);
        }
        if (c.year)
            fYear.text = String(c.year);
        if (c.genres && c.genres.length > 0)
            genres = c.genres;
        artMusicBrainz = c.has_artwork ? c.musicbrainz_id : "";
        if (artMusicBrainz !== "") {
            artPath = "";
            artRemoved = false;
        }
    }

    // ---- Save ------------------------------------------------------------------------------------------------------
    function number(text) {
        const t = text.trim();
        return t === "" || isNaN(Number(t)) ? null : Math.round(Number(t));
    }
    function fail(r) {
        busy = false;
        error = (r && r.error) || Store.lastError || Fili.tr("The tags could not be saved");
    }
    function save() {
        error = "";
        busy = true;
        let name, args;
        if (isTrack) {
            name = "update_track_metadata";
            args = [ids[0], JSON.stringify({
                title: fTitle.text.trim(), artist_name: fArtist.text.trim(), album_title: fAlbum.text.trim(),
                album_artist_name: fAlbumArtist.text.trim(), genre_names: genres, year: number(fYear.text),
                track_number: number(fTrack.text), disc_number: number(fDisc.text)
            })];
        } else if (isAlbum) {
            name = "update_album_metadata";
            args = [albumId, JSON.stringify({ title: fTitle.text.trim(), artist_name: fArtist.text.trim(), genre_names: genres, year: number(fYear.text) })];
        } else {
            // A field left out is a field left alone: a mixed one that was not filled in
            const p = { genre_names: genres };
            if (!mixedArtist || fArtist.text.trim() !== "")
                p.artist_name = fArtist.text.trim();
            if (!mixedAlbum || fAlbum.text.trim() !== "")
                p.album_title = fAlbum.text.trim();
            if (!mixedYear || fYear.text.trim() !== "")
                p.year = number(fYear.text);
            name = "update_multiple_tracks_metadata";
            args = [JSON.stringify(ids), JSON.stringify(p)];
        }
        Store.callAsyncRaw(name, args, r => {
            if (!r.success) {
                fail(r);
                return;
            }
            applyArtwork(() => {
                busy = false;
                Store.forget();
                askWrite = true;
            });
        });
    }
    // The pending artwork choice, for the track, the album or each track; then `then`
    function applyArtwork(then) {
        let calls = [];
        const targets = isAlbum ? [albumId] : ids;
        if (artPath !== "")
            calls = targets.map(id => [isAlbum ? "set_album_artwork_from_path" : "set_track_artwork_from_path", [id, artPath]]);
        else if (artMusicBrainz !== "")
            calls = targets.map(id => [isAlbum ? "set_album_artwork_from_scrape" : "set_track_artwork_from_scrape", [id, artMusicBrainz]]);
        else if (artRemoved)
            calls = targets.map(id => [isAlbum ? "remove_album_artwork" : "remove_track_artwork", [id]]);
        if (calls.length === 0) {
            then();
            return;
        }
        let left = calls.length;
        calls.forEach(c => Store.callAsyncRaw(c[0], c[1], r => {
            if (!r.success)
                error = Fili.tr("Artwork: %1").replace("%1", r.error || "");
            if (--left === 0)
                then();
        }));
    }
    // Write the saved tags into the audio files
    function writeFiles() {
        busy = true;
        const name = isTrack ? "write_track_file_tags" : isAlbum ? "write_album_file_tags" : "write_multiple_tracks_file_tags";
        const args = isTrack ? [ids[0]] : isAlbum ? [albumId] : [JSON.stringify(ids)];
        Store.callAsyncRaw(name, args, r => {
            busy = false;
            let errors = r.data && r.data.errors ? r.data.errors : [];
            if (!r.success && errors.length === 0)
                errors = [{ file_path: r.data && r.data.file_path ? r.data.file_path : "", reason: r.error || "" }];
            if (errors.length === 0) {
                askWrite = false;
                close();
            } else {
                writeErrors = errors;
                askWrite = false;
            }
        });
    }

    MouseArea { anchors.fill: parent }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(540, parent.width - 2 * FiliTheme.margin)
        height: Math.min(parent.height - 2 * FiliTheme.margin, 700)
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        clip: true

        Text {
            id: title
            x: FiliTheme.space5
            y: FiliTheme.space4
            width: parent.width - 2 * FiliTheme.space5
            elide: Text.ElideRight
            text: ed.heading
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeTitle + 2
            font.weight: Font.Light
            color: FiliTheme.text
        }
        Flickable {
            id: flick
            anchors { top: title.bottom; topMargin: FiliTheme.space3; bottom: footer.top; left: parent.left; right: parent.right }
            clip: true
            contentHeight: form.height + FiliTheme.space4
            boundsBehavior: Flickable.StopAtBounds
            enabled: !ed.busy
            KineticScroll {}
            Column {
                id: form
                x: FiliTheme.space5
                width: parent.width - 2 * FiliTheme.space5
                spacing: FiliTheme.space2

                // Artwork
                Row {
                    spacing: FiliTheme.space3
                    Artwork {
                        id: preview
                        width: 96
                        height: 96
                        itemId: ed.albumId
                        // A cover chosen but not applied yet hides the current one
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            visible: ed.artPath !== "" || ed.artMusicBrainz !== "" || ed.artRemoved
                            color: FiliTheme.surface
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: ed.artRemoved ? Fili.tr("Removed") : ed.artMusicBrainz !== "" ? "MusicBrainz" : Fili.tr("New image")
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.textSecondary
                            }
                        }
                    }
                    Column {
                        width: form.width - preview.width - FiliTheme.space3
                        spacing: FiliTheme.space1
                        TagField {
                            id: fImage
                            label: Fili.tr("Image file")
                            width: parent.width
                            onEdited: {
                                ed.artPath = text.trim();
                                ed.artMusicBrainz = "";
                                ed.artRemoved = false;
                            }
                        }
                        Row {
                            spacing: FiliTheme.space1
                            TextButton { label: Fili.tr("Find online"); onClicked: ed.scrapeArtwork() }
                            TextButton {
                                label: Fili.tr("Remove")
                                onClicked: {
                                    ed.artRemoved = true;
                                    ed.artPath = ed.artMusicBrainz = "";
                                    fImage.text = "";
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            visible: text !== ""
                            text: ed.artError !== "" ? ed.artError : ed.artMusicBrainz !== "" ? Fili.tr("MusicBrainz artwork will be applied on save") : ""
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            color: ed.artError !== "" ? FiliTheme.danger : FiliTheme.textSecondary
                        }
                    }
                }
                Item { width: 1; height: FiliTheme.space1 }
                TagField { id: fTitle; visible: !ed.isMulti; height: visible ? 28 : 0; label: ed.isAlbum ? Fili.tr("Album") : Fili.tr("Title") }
                TagField { id: fArtist; label: Fili.tr("Artist"); mixed: ed.mixedArtist; suggestions: ed.suggestions.artist }
                TagField { id: fAlbum; visible: !ed.isAlbum; height: visible ? 28 : 0; label: Fili.tr("Album"); mixed: ed.mixedAlbum; suggestions: ed.suggestions.album }
                TagField { id: fAlbumArtist; visible: ed.isTrack; height: visible ? 28 : 0; label: Fili.tr("Album artist"); suggestions: ed.suggestions.artist }
                TagField { id: fYear; label: Fili.tr("Year"); mixed: ed.mixedYear }
                TagField { id: fTrack; visible: ed.isTrack; height: visible ? 28 : 0; label: Fili.tr("Track") }
                TagField { id: fDisc; visible: ed.isTrack; height: visible ? 28 : 0; label: Fili.tr("Disc") }

                // Genres
                Text {
                    topPadding: FiliTheme.space2
                    text: Fili.tr("Genres")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    font.weight: FiliTheme.weightAccent
                    color: FiliTheme.muted
                }
                Flow {
                    width: parent.width
                    spacing: FiliTheme.space1 + 2
                    Repeater {
                        model: ed.genres
                        Rectangle {
                            id: chip
                            required property string modelData
                            width: chipText.implicitWidth + 28
                            height: 22
                            radius: 11
                            color: FiliTheme.alpha(FiliTheme.accentColor, 0.15)
                            border.width: FiliTheme.borderWidth
                            border.color: FiliTheme.alpha(FiliTheme.accentColor, 0.3)
                            Text {
                                id: chipText
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.text
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                                text: "×"
                                font.family: FiliTheme.font
                                font.pixelSize: 14
                                color: FiliTheme.textSecondary
                                MouseArea {
                                    anchors { fill: parent; margins: -4 }
                                    onClicked: ed.genres = ed.genres.filter(g => g !== chip.modelData)
                                }
                                Accessible.name: Fili.tr("Remove %1").replace("%1", chip.modelData)
                            }
                        }
                    }
                }
                Row {
                    width: parent.width
                    spacing: FiliTheme.space2
                    TagField {
                        id: fNewGenre
                        width: parent.width - addGenre.width - FiliTheme.space2
                        label: Fili.tr("Add genre")
                        suggestions: ed.suggestions.genre
                        onSubmitted: ed.addGenre()
                    }
                    TextButton { id: addGenre; anchors.verticalCenter: parent.verticalCenter; label: Fili.tr("Add"); onClicked: ed.addGenre() }
                }

                // Scrape
                Row {
                    visible: !ed.isMulti
                    height: visible ? 30 : 0
                    spacing: FiliTheme.space3
                    TextButton { label: Fili.tr("Scrape metadata"); onClicked: ed.scrape() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ed.scrapeError
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeSmall
                        color: FiliTheme.danger
                    }
                }
            }
        }
        FiliScrollBar { flick: flick; anchors { top: flick.top; bottom: flick.bottom; right: flick.right } }

        // Footer: busy / error, then Cancel and Save
        Rectangle {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 44
            color: FiliTheme.backgroundDeep
            Rectangle { width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            Text {
                anchors { left: parent.left; leftMargin: FiliTheme.space5; right: buttons.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: ed.busy ? Fili.tr("Working…") : ed.error
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: ed.busy ? FiliTheme.textSecondary : FiliTheme.danger
            }
            Row {
                id: buttons
                anchors { right: parent.right; rightMargin: FiliTheme.space4; verticalCenter: parent.verticalCenter }
                spacing: FiliTheme.space1
                TextButton { label: Fili.tr("Cancel"); onClicked: if (!ed.busy) ed.close() }
                TextButton { label: Fili.tr("Save"); primary: true; onClicked: if (!ed.busy) ed.save() }
            }
        }

        // Candidates of a MusicBrainz search
        Rectangle {
            visible: ed.picking
            anchors.fill: parent
            color: FiliTheme.surface
            z: 10
            Text {
                id: pickTitle
                x: FiliTheme.space5
                y: FiliTheme.space4
                text: ed.pickFor === "artwork" ? Fili.tr("Choose a release for the artwork") : Fili.tr("Choose a match")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: Font.Light
                color: FiliTheme.text
            }
            ListView {
                id: pickList
                anchors { top: pickTitle.bottom; topMargin: FiliTheme.space3; bottom: pickFooter.top; left: parent.left; right: parent.right }
                clip: true
                model: ed.candidates
                boundsBehavior: Flickable.StopAtBounds
                KineticScroll {}
                delegate: Rectangle {
                    id: cand
                    required property var modelData
                    width: pickList.width
                    height: 48
                    color: candArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Column {
                        anchors { left: parent.left; leftMargin: FiliTheme.space5; right: score.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: cand.modelData.title
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            font.weight: FiliTheme.weightAccent
                            color: FiliTheme.text
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: [cand.modelData.artist, cand.modelData.album, cand.modelData.year].filter(x => x).join(" · ")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.textSecondary
                        }
                    }
                    Text {
                        id: score
                        anchors { right: parent.right; rightMargin: FiliTheme.space5; verticalCenter: parent.verticalCenter }
                        text: (cand.modelData.has_artwork ? "▣ " : "") + cand.modelData.score + "%"
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeSmall
                        color: FiliTheme.muted
                    }
                    MouseArea { id: candArea; anchors.fill: parent; hoverEnabled: true; onClicked: ed.choose(cand.modelData, ed.pickFor) }
                }
            }
            Rectangle {
                id: pickFooter
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 44
                color: FiliTheme.backgroundDeep
                Rectangle { width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
                TextButton {
                    anchors { right: parent.right; rightMargin: FiliTheme.space4; verticalCenter: parent.verticalCenter }
                    label: Fili.tr("Cancel")
                    onClicked: ed.picking = false
                }
            }
        }

        // After a save: write the tags into the audio files?
        Rectangle {
            visible: ed.askWrite || ed.writeErrors.length > 0
            anchors.fill: parent
            color: FiliTheme.surface
            z: 20
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: FiliTheme.space6 }
                spacing: FiliTheme.space3
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: ed.writeErrors.length > 0 ? Fili.tr("Some files could not be updated") : (ed.isTrack ? Fili.tr("Write the tags to the file?") : Fili.tr("Write the tags to %1 files?").replace("%1", ed.isAlbum ? ed.fileCount : ed.ids.length))
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle
                    font.weight: Font.Light
                    color: FiliTheme.text
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: ed.writeErrors.length > 0
                          ? ed.writeErrors.slice(0, 3).map(e => (e.file_path ? e.file_path.split("/").pop() : e.reason)).join("\n") + (ed.writeErrors.length > 3 ? "\n" + Fili.tr("…and %1 more").replace("%1", ed.writeErrors.length - 3) : "")
                          : (ed.isTrack ? Fili.tr("Apply the changes to the audio file on disk?") : Fili.tr("Apply the changes to the audio files on disk?"))
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.textSecondary
                }
                Row {
                    anchors.right: parent.right
                    spacing: FiliTheme.space2
                    TextButton {
                        visible: ed.writeErrors.length === 0
                        label: Fili.tr("Skip")
                        onClicked: ed.close()
                    }
                    TextButton {
                        label: ed.writeErrors.length > 0 ? Fili.tr("OK") : Fili.tr("Write to file")
                        primary: true
                        onClicked: ed.writeErrors.length > 0 ? ed.close() : ed.writeFiles()
                    }
                }
            }
        }
    }
}
