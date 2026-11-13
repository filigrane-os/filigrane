// fili-recorder: Cassette (aka k7), the sound recorder and player of Filigrane. Without arguments it opens the window
// (Qt Quick, like Casier); with a command it works without one: start, stop, toggle, status, set, folder (the fili-bar
// module and scripts use them), ctl (commands to an open window).
mod bridge;
mod codec;
mod ctl;
mod i18n;
mod library;
mod player;
mod recorder;
mod theme;
mod window;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("-V" | "--version") => {
            println!("fili-recorder {}", env!("CARGO_PKG_VERSION"));
            return;
        }
        Some("-h" | "--help") => {
            println!(
                "fili-recorder {}: Cassette, the sound recorder and player of Filigrane\n\nUsage: fili-recorder [--no-header] [--no-footer]   open the window\n       fili-recorder start [--input X] [--output Y] | stop | toggle | status [--json|--bar] | set input|output X | folder\n       fili-recorder ctl [--pid PID] action NAME [ARG] | state | actions",
                env!("CARGO_PKG_VERSION")
            );
            return;
        }
        Some("start" | "stop" | "toggle" | "status" | "set" | "folder") => {
            std::process::exit(if recorder::cli(&args[1..]) == std::process::ExitCode::SUCCESS { 0 } else { 1 });
        }
        Some("ctl") => {
            match ctl::client(&args[2..]) {
                Ok(answer) => println!("{answer}"),
                Err(e) => {
                    eprintln!("fili-recorder ctl: {e}");
                    std::process::exit(1);
                }
            }
            return;
        }
        _ => {}
    }
    // One window: a second launch brings the open one to the front
    if let Some(pid) = ctl::windows().first()
        && window::focus_pid(*pid)
    {
        return;
    }
    let mut app = QGuiApplication::new();
    // Wayland app-id (niri rules, fili-recorder.desktop)
    QGuiApplication::set_desktop_file_name(&QString::from("fili-recorder"));
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/Fili/Cassette/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        std::process::exit(app.exec());
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, fs};

    fn read(rel: &str) -> String {
        fs::read_to_string(format!("{}/{rel}", env!("CARGO_MANIFEST_DIR"))).unwrap()
    }

    // A file of the fili-shell (directory FILI_SHELL_DIR). The parity tests below compare the application with the
    // shell: they run from the Filigrane repository (tests/fili-shell/run.sh sets the variable) and are skipped elsewhere.
    fn shell(file: &str) -> Option<String> {
        let dir = std::env::var_os("FILI_SHELL_DIR")?;
        Some(fs::read_to_string(std::path::Path::new(&dir).join(file)).unwrap())
    }

    // "readonly property <type> <name>: <value>" -> value
    fn tokens(qml: &str) -> HashMap<String, String> {
        qml.lines()
            .filter_map(|l| l.trim().strip_prefix("readonly property "))
            .filter_map(|l| {
                let (decl, value) = l.split_once(':')?;
                Some((decl.split_whitespace().last()?.to_string(), value.trim().to_string()))
            })
            .collect()
    }

    // "[section] key = "value" # comment" of theme.toml -> (section, key) = value
    fn defaults() -> HashMap<(String, String), String> {
        let mut out = HashMap::new();
        let mut section = String::new();
        for line in read("theme.toml").lines() {
            let line = line.split(" #").next().unwrap_or("").trim();
            if let Some(n) = line.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
                section = n.to_string();
            } else if let Some((k, v)) = line.split_once('=') {
                out.insert((section.clone(), k.trim().to_string()), v.trim().trim_matches('"').to_string());
            }
        }
        out
    }

    // The defaults of theme.toml are the ones of the fili-shell: a shared token keeps the same value
    #[test]
    fn shell_parity_default_theme() {
        let Some(shell_qml) = shell("FiliTheme.qml") else { return };
        let shell = tokens(&shell_qml);
        let d = defaults();
        let mut common = 0;
        // (shell token, theme.toml key): colors per mode ("light ? light : dark"), the rest shared
        let colors = [
            ("nuit", "background"),
            ("nuitProfond", "background_deep"),
            ("nuit2", "surface"),
            ("nuit3", "surface_hover"),
            ("nuit4", "surface_active"),
            ("ardoise", "muted"),
            ("brume2", "text_secondary"),
            ("brume", "text"),
            ("sable", "warning"),
            ("cendre", "danger"),
            ("sauge", "success"),
            ("border", "border"),
        ];
        for (token, key) in colors {
            let v = &shell[token];
            assert!(v.starts_with(&format!("ov(\"{key}\", ")), "{token}: ov(\"{key}\", ...)");
            let hexes: Vec<&str> = v.split('"').skip(1).step_by(2).filter(|h| h.starts_with('#')).collect();
            let (light, dark) = if hexes.len() == 2 { (hexes[0], hexes[1]) } else { (hexes[0], hexes[0]) };
            assert_eq!(d[&("theme.light".to_string(), key.to_string())], light, "{token} light");
            assert_eq!(d[&("theme.dark".to_string(), key.to_string())], dark, "{token} dark");
            common += 1;
        }
        let plain = [
            ("font", "font"),
            ("mono", "mono"),
            ("size", "size"),
            ("sizeList", "size_list"),
            ("sizeSmall", "size_small"),
            ("sizeLabel", "size_label"),
            ("sizeTitle", "size_title"),
            ("weightAccent", "weight_accent"),
            ("radiusMark", "radius_mark"),
            ("radiusControl", "radius_control"),
            ("radiusWindow", "radius_window"),
            ("space1", "space_1"),
            ("space2", "space_2"),
            ("space3", "space_3"),
            ("space4", "space_4"),
            ("space5", "space_5"),
            ("space6", "space_6"),
            ("borderWidth", "border_width"),
        ];
        for (token, key) in plain {
            let v = &shell[token];
            assert!(v.starts_with(&format!("ov(\"{key}\", ")), "{token}: ov(\"{key}\", ...)");
            let v = v.split_once(", ").unwrap().1.trim_end_matches(')');
            let want = match v {
                "Font.DemiBold" => "600".to_string(),
                v => v.trim_matches('"').to_string(),
            };
            assert_eq!(d[&("theme".to_string(), key.to_string())], want, "token {token}");
            common += 1;
        }
        // Accent tones: each one of theme.toml appears as it is in the shell
        let tones = &shell["accentTones"];
        let toml = read("theme.toml");
        let mut n = 0;
        for line in toml.lines().skip_while(|l| !l.starts_with("[theme.accents]")).skip(1) {
            let Some((name, list)) = line.split_once('=') else { continue };
            assert!(tones.contains(&format!("{}: {}", name.trim(), list.trim())), "accent {}", name.trim());
            n += 1;
        }
        assert!(n >= 7);
        assert!(common >= 25, "{common} shared tokens");
    }

    // A misspelled token does not fail at run time: the item just stays transparent
    #[test]
    fn every_theme_token_used_in_qml_is_defined() {
        let defined: Vec<String> = read("qml/FiliTheme.qml")
            .lines()
            .filter_map(|l| l.trim().strip_prefix("readonly property "))
            .filter_map(|l| Some(l.split(':').next()?.split_whitespace().last()?.to_string()))
            .chain(["alpha".to_string()])
            .collect();
        for entry in fs::read_dir(format!("{}/qml", env!("CARGO_MANIFEST_DIR"))).unwrap() {
            let path = entry.unwrap().path();
            if path.file_name().is_some_and(|n| n == "FiliTheme.qml") {
                continue;
            }
            let text = fs::read_to_string(&path).unwrap();
            for (i, _) in text.match_indices("FiliTheme.") {
                let name: String = text[i + 10..].chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
                assert!(defined.contains(&name), "{}: FiliTheme.{name} is not defined", path.display());
            }
        }
    }

    // A function the QML calls on Fili or cas but that is not exposed (#[qinvokable]) is a run-time TypeError that no
    // other test sees: the button just does nothing
    #[test]
    fn every_function_called_by_the_qml_is_exposed() {
        let bridge = read("src/bridge.rs");
        let lines: Vec<&str> = bridge.lines().map(str::trim).collect();
        // name used from QML -> exposed or not, for every `fn` declared in the bridge's extern block
        let mut exposed: HashMap<String, bool> = HashMap::new();
        for (i, l) in lines.iter().enumerate() {
            // Declarations of the extern block end with ";" (the functions of the impl blocks end with "{")
            let Some(rest) = l.strip_prefix("fn ").filter(|_| l.ends_with(';')) else { continue };
            let rust = rest.split('(').next().unwrap_or("");
            let mut attrs = Vec::new();
            let mut j = i;
            while j > 0 && lines[j - 1].starts_with("#[") {
                j -= 1;
                attrs.push(lines[j]);
            }
            let cxx = attrs.iter().find_map(|a| a.strip_prefix("#[cxx_name = \"").and_then(|r| r.strip_suffix("\"]")));
            let camel = {
                let mut out = String::new();
                let mut up = false;
                for c in rust.chars() {
                    if c == '_' {
                        up = true
                    } else if up {
                        out.extend(c.to_uppercase());
                        up = false
                    } else {
                        out.push(c)
                    }
                }
                out
            };
            let ok = attrs.iter().any(|a| *a == "#[qinvokable]" || a.starts_with("#[qsignal"));
            exposed.insert(cxx.map(String::from).unwrap_or(camel), ok);
        }
        for entry in fs::read_dir(format!("{}/qml", env!("CARGO_MANIFEST_DIR"))).unwrap() {
            let path = entry.unwrap().path();
            let text = fs::read_to_string(&path).unwrap();
            for obj in ["Fili.", "cas."] {
                for (i, _) in text.match_indices(obj) {
                    let name: String = text[i + obj.len()..].chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
                    if text[i + obj.len() + name.len()..].starts_with('(') {
                        if let Some(false) = exposed.get(&name) {
                            panic!("{}: {obj}{name}() is called but not exposed to QML (missing #[qinvokable])", path.display());
                        }
                    }
                }
            }
        }
    }

    // A singleton that is not registered in build.rs is "not defined" at run time, which no other test would notice
    #[test]
    fn every_qml_singleton_is_registered() {
        let build = read("build.rs");
        for entry in fs::read_dir(format!("{}/qml", env!("CARGO_MANIFEST_DIR"))).unwrap() {
            let path = entry.unwrap().path();
            if fs::read_to_string(&path).unwrap().contains("pragma Singleton") {
                let name = path.file_name().unwrap().to_string_lossy().into_owned();
                assert!(
                    build.contains(&format!("\"qml/{name}\").singleton(true)")),
                    "{name} is not registered as a singleton in build.rs"
                );
            }
        }
    }

    #[test]
    fn shell_parity_kinetic_scroll() {
        let Some(shell_qml) = shell("KineticScroll.qml") else { return };
        assert_eq!(read("qml/KineticScroll.qml"), shell_qml);
    }

    // A QML file that build.rs does not list is "type not found" at run time
    #[test]
    fn every_qml_file_is_listed_in_build_rs() {
        let build = read("build.rs");
        for entry in fs::read_dir(format!("{}/qml", env!("CARGO_MANIFEST_DIR"))).unwrap() {
            let name = entry.unwrap().file_name().to_string_lossy().into_owned();
            assert!(build.contains(&format!("\"qml/{name}\"")), "{name} is not listed in build.rs");
        }
    }
}
