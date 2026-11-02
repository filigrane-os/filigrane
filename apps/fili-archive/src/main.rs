// fili-archive: compresser et décompresser un ou plusieurs fichiers, sans fenêtre. Délègue à tar, zip, 7z (déjà installés).
//
//   fili-archive pack [-f FORMAT] [-l fast|normal|best] [--no-hidden] [-q] [-o SORTIE] FICHIER...
//                                                          crée une archive à côté des fichiers (zip par défaut)
//     -q: ni transaction ni notification (fili-file, qui a son panneau, son annulation et son propre « défaire »)
//   fili-archive unpack [-o DOSSIER] ARCHIVE...            extrait à côté de l'archive (ou dans DOSSIER)
//   fili-archive open ARCHIVE...                           comme unpack (association de fichiers, fili-archive.desktop)
//   fili-archive list ARCHIVE                              contenu de l'archive
//
// Formats d'écriture: zip (défaut), 7z, tar.gz, tar.xz, tar.zst; lecture: tout ce que tar et 7z ouvrent (zip, 7z, rar, iso...).
// Règles: jamais d'écrasement (« Archive 2.zip », « dossier 2 »); l'archive ou le dossier n'apparaît qu'une fois fini
// (écrit sous un nom caché puis renommé: un échec ou une interruption ne laisse rien d'à moitié fait); extraction dans
// un dossier à part (un seul élément au sommet de l'archive: il est posé tel quel, sinon un dossier au nom de l'archive).
// Chaque appel est une transaction fili-tx: « fili-tx undo » met le résultat à la corbeille. Sortie: un chemin créé par ligne;
// en dehors d'un terminal (menu, association de fichiers) le résultat s'annonce par notification.
use std::{
    env,
    ffi::OsString,
    fs,
    io::{IsTerminal, Read},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
};

// Extensions d'archive reconnues (composées d'abord). tar: lisible par tar; sinon 7z.
const EXTS: [&str; 19] = [
    "tar.gz", "tar.xz", "tar.bz2", "tar.zst", "tgz", "txz", "tbz2", "tzst", "tar", "zip", "7z", "rar", "iso", "gz", "xz", "bz2",
    "zst", "cab", "jar",
];

// (nom sans extension d'archive, extension en minuscules)
fn split_ext(name: &str) -> Option<(String, &'static str)> {
    let lower = name.to_lowercase();
    EXTS.iter()
        .find(|e| lower.ends_with(&format!(".{e}")) && name.len() > e.len() + 1)
        .map(|e| (name[..name.len() - e.len() - 1].to_string(), *e))
}

fn is_tar(ext: &str) -> bool {
    ext.starts_with("tar") || matches!(ext, "tgz" | "txz" | "tbz2" | "tzst")
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "Archive".into())
}

fn exists(p: &Path) -> bool {
    fs::symlink_metadata(p).is_ok()
}

// Premier nom libre dans `dir`: « nom.ext », « nom 2.ext », « nom 3.ext »...
fn unique(dir: &Path, stem: &str, ext: &str) -> PathBuf {
    let make = |n: u32| {
        let s = if n == 1 { stem.to_string() } else { format!("{stem} {n}") };
        dir.join(if ext.is_empty() { s } else { format!("{s}.{ext}") })
    };
    (1..).map(make).find(|p| !exists(p)).unwrap()
}

// Lance un programme, stdin fermé (pas de question de mot de passe qui bloque); l'erreur porte la fin de sa sortie d'erreur
fn run(program: &str, args: &[OsString], cwd: &Path, envs: &[(&str, String)]) -> Result<(), String> {
    let mut child = Command::new(program)
        .args(args)
        .current_dir(cwd)
        .envs(envs.iter().map(|(k, v)| (*k, v.as_str())))
        .env("ZSTD_NBTHREADS", "0")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(
            |e| if e.kind() == std::io::ErrorKind::NotFound { format!("{program} is not installed") } else { e.to_string() },
        )?;
    let mut err = String::new();
    if let Some(mut s) = child.stderr.take() {
        let _ = s.read_to_string(&mut err);
    }
    let status = child.wait().map_err(|e| e.to_string())?;
    if status.success() {
        return Ok(());
    }
    let tail: Vec<&str> = err.lines().filter(|l| !l.trim().is_empty()).collect();
    let tail = tail[tail.len().saturating_sub(2)..].join(" ");
    let lower = tail.to_lowercase();
    Err(if lower.contains("password") || lower.contains("encrypted") {
        "the archive is protected by a password (not supported yet)".into()
    } else if tail.is_empty() {
        format!("{program} failed")
    } else {
        tail
    })
}

fn os(s: &str) -> OsString {
    OsString::from(s)
}

const USAGE_PACK: &str = "usage: fili-archive pack [-f zip|7z|tar.gz|tar.xz|tar.zst] [-l fast|normal|best] [--no-hidden] [-q] [-o OUT] FILE...";

// ---- pack ----------------------------------------------------------------------------------------------

fn pack(args: &[String]) -> Result<Vec<PathBuf>, String> {
    let (mut format, mut out, mut items) = (None::<String>, None::<PathBuf>, Vec::new());
    let (mut level, mut skip_hidden) = ("normal".to_string(), false);
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "-f" | "--format" => format = Some(it.next().ok_or("-f needs a format")?.to_lowercase()),
            "-o" | "--output" => out = Some(PathBuf::from(it.next().ok_or("-o needs a file name")?)),
            "-l" | "--level" => {
                level = it.next().ok_or("-l needs a level")?.to_lowercase();
                if !matches!(level.as_str(), "fast" | "normal" | "best") {
                    return Err(format!("unknown level “{level}” (fast, normal, best)"));
                }
            }
            "--no-hidden" => skip_hidden = true,
            "-q" | "--quiet" => {} // lu par main
            "--" => items.extend(it.by_ref().map(PathBuf::from)),
            s if s.starts_with('-') && s.len() > 1 => return Err(format!("unknown option {s}")),
            s => items.push(PathBuf::from(s)),
        }
    }
    if items.is_empty() {
        return Err(USAGE_PACK.into());
    }
    let items: Vec<PathBuf> =
        items.iter().map(|p| std::path::absolute(p).map_err(|e| e.to_string())).collect::<Result<_, _>>()?;
    for p in &items {
        if !exists(p) {
            return Err(format!("“{}” does not exist", file_name(p)));
        }
    }
    // Dossier commun: les noms dans l'archive sont relatifs à lui
    let base = {
        let mut c: Vec<Component> = items[0].parent().unwrap_or(Path::new("/")).components().collect();
        for p in &items[1..] {
            let q: Vec<Component> = p.parent().unwrap_or(Path::new("/")).components().collect();
            let n = c.iter().zip(&q).take_while(|(a, b)| a == b).count();
            c.truncate(n);
        }
        c.iter().collect::<PathBuf>()
    };
    let rels: Vec<String> = items.iter().map(|p| p.strip_prefix(&base).unwrap().to_string_lossy().into_owned()).collect();
    if rels.iter().any(|r| r.is_empty()) {
        return Err("cannot compress the root folder".into());
    }
    // Sortie: -o (fichier exact, format déduit de son extension), sinon à côté, nommée d'après l'élément (ou « Archive »)
    let default = env::var("FILI_ARCHIVE_FORMAT").unwrap_or_else(|_| "zip".into());
    let fmt_of = |f: &str| -> Result<String, String> {
        Ok(match f {
            "zip" | "7z" | "tar.gz" | "tar.xz" | "tar.zst" => f.into(),
            "tgz" => "tar.gz".into(),
            "txz" => "tar.xz".into(),
            "tzst" | "zst" => "tar.zst".into(),
            other => return Err(format!("unknown format “{other}” (zip, 7z, tar.gz, tar.xz, tar.zst)")),
        })
    };
    let (dest, fmt) = match &out {
        Some(o) => {
            let o = std::path::absolute(o).map_err(|e| e.to_string())?;
            let (o, fmt) = match (format.as_deref(), split_ext(&file_name(&o))) {
                (None, Some((_, e))) => (o, fmt_of(e)?),
                (f, _) => {
                    let fmt = fmt_of(f.unwrap_or(&default))?;
                    (o.with_file_name(format!("{}.{fmt}", file_name(&o))), fmt)
                }
            };
            if exists(&o) {
                return Err(format!("“{}” already exists", file_name(&o)));
            }
            (o, fmt)
        }
        None => {
            let stem = if items.len() == 1 {
                let n = file_name(&items[0]);
                // un fichier perd son extension (photo.jpg -> photo.zip), un dossier garde son nom
                match (fs::symlink_metadata(&items[0]).map(|m| m.is_dir()), n.rsplit_once('.')) {
                    (Ok(false), Some((s, _))) if !s.is_empty() => s.to_string(),
                    _ => n,
                }
            } else {
                "Archive".into()
            };
            let fmt = fmt_of(format.as_deref().unwrap_or(&default))?;
            (unique(&base, &stem, &fmt), fmt)
        }
    };
    let dir = dest.parent().unwrap().to_path_buf();
    if !dir.is_dir() {
        return Err(format!("“{}” is not a folder", dir.display()));
    }
    // Écrit sous un nom caché qui garde l'extension (zip ajoute sinon la sienne), puis renomme
    let tmp = dir.join(format!(".{}.{}.part.{fmt}", file_name(&dest), std::process::id()));
    let result = (|| {
        let mut a: Vec<OsString> = Vec::new();
        let mut envs: Vec<(&str, String)> = Vec::new();
        let lv = |fast: &str, normal: &str, best: &str| match level.as_str() {
            "fast" => fast.to_string(),
            "best" => best.to_string(),
            _ => normal.to_string(),
        };
        let program = match fmt.as_str() {
            "zip" => {
                a.extend([os("-q"), os("-r"), os("-y"), os(&lv("-1", "-6", "-9")), tmp.clone().into_os_string()]);
                a.extend(rels.iter().map(|r| os(&format!("./{r}"))));
                if skip_hidden {
                    a.extend([os("-x"), os("*/.*")]);
                }
                "zip"
            }
            "7z" => {
                a.extend([os("a"), os("-y"), os("-bd"), os("-snl"), os(&lv("-mx=1", "-mx=5", "-mx=9"))]);
                if skip_hidden {
                    a.push(os("-xr!.*"));
                }
                a.push(tmp.clone().into_os_string());
                a.extend(rels.iter().map(|r| os(&format!("./{r}"))));
                "7z"
            }
            _ => {
                let flag = match fmt.as_str() {
                    "tar.gz" => "-czf",
                    "tar.xz" => "-cJf",
                    _ => "--zstd",
                };
                if skip_hidden {
                    a.push(os("--exclude=.*"));
                }
                a.push(os(flag));
                if flag == "--zstd" {
                    a.push(os("-cf"));
                }
                match fmt.as_str() {
                    "tar.gz" => envs.push(("GZIP", lv("-1", "-6", "-9"))),
                    "tar.xz" => envs.push(("XZ_OPT", lv("-1", "-6", "-9"))),
                    _ => envs.push(("ZSTD_CLEVEL", lv("1", "3", "19"))),
                }
                a.extend([tmp.clone().into_os_string(), os("--")]);
                a.extend(rels.iter().map(|r| os(r)));
                "tar"
            }
        };
        run(program, &a, &base, &envs)?;
        fs::rename(&tmp, &dest).map_err(|e| e.to_string())
    })();
    if let Err(e) = result {
        let _ = fs::remove_file(&tmp);
        return Err(format!("cannot compress: {e}"));
    }
    Ok(vec![dest])
}

// ---- unpack --------------------------------------------------------------------------------------------

fn unpack_one(archive: &Path, into: Option<&Path>) -> Result<PathBuf, String> {
    let archive = std::path::absolute(archive).map_err(|e| e.to_string())?;
    let name = file_name(&archive);
    if !archive.is_file() {
        return Err(format!("“{name}” is not a file"));
    }
    let (stem, ext) = split_ext(&name).map(|(s, e)| (s, e)).unwrap_or_else(|| (name.clone(), ""));
    let dir = into.map(Path::to_path_buf).unwrap_or_else(|| archive.parent().unwrap().to_path_buf());
    if !dir.is_dir() {
        return Err(format!("“{}” is not a folder", dir.display()));
    }
    // Extraction dans un dossier caché à côté du résultat; le résultat n'apparaît qu'à la fin
    let tmp = dir.join(format!(".{stem}.{}.part", std::process::id()));
    fs::create_dir(&tmp).map_err(|e| format!("cannot write in “{}”: {e}", dir.display()))?;
    let args: Vec<OsString> = if is_tar(ext) {
        vec![os("-xf"), archive.clone().into_os_string(), os("-C"), tmp.clone().into_os_string()]
    } else {
        vec![
            os("x"),
            os("-y"),
            os("-bd"),
            os("-snl"),
            os(&format!("-o{}", tmp.display())),
            os("--"),
            archive.clone().into_os_string(),
        ]
    };
    let program = if is_tar(ext) { "tar" } else { "7z" };
    let done = run(program, &args, &dir, &[]).and_then(|()| {
        let mut top: Vec<PathBuf> =
            fs::read_dir(&tmp).map_err(|e| e.to_string())?.filter_map(|e| e.ok()).map(|e| e.path()).collect();
        if top.is_empty() {
            return Err("the archive is empty".into());
        }
        let (src, dest) = if top.len() == 1 {
            let only = top.remove(0);
            let n = file_name(&only);
            let (s, e) = match n.rsplit_once('.') {
                Some((s, e)) if !s.is_empty() && !only.is_dir() => (s.to_string(), e.to_string()),
                _ => (n.clone(), String::new()),
            };
            let dest = unique(&dir, &s, &e);
            (only, dest)
        } else {
            (tmp.clone(), unique(&dir, &stem, ""))
        };
        fs::rename(&src, &dest).map_err(|e| e.to_string())?;
        Ok(dest)
    });
    let _ = fs::remove_dir_all(&tmp);
    done.map_err(|e| format!("cannot extract “{name}”: {e}"))
}

fn unpack(args: &[String]) -> (Vec<PathBuf>, Vec<String>) {
    let (mut into, mut archives) = (None::<PathBuf>, Vec::new());
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "-o" | "--output" => match it.next() {
                Some(d) => into = Some(PathBuf::from(d)),
                None => return (vec![], vec!["-o needs a folder".into()]),
            },
            "--" => archives.extend(it.by_ref().map(PathBuf::from)),
            s if s.starts_with('-') && s.len() > 1 => return (vec![], vec![format!("unknown option {s}")]),
            s => archives.push(PathBuf::from(s)),
        }
    }
    if archives.is_empty() {
        return (vec![], vec!["no archive given (usage: fili-archive unpack [-o FOLDER] ARCHIVE...)".into()]);
    }
    let (mut done, mut errors) = (Vec::new(), Vec::new());
    for a in &archives {
        match unpack_one(a, into.as_deref()) {
            Ok(p) => done.push(p),
            Err(e) => errors.push(e),
        }
    }
    (done, errors)
}

fn list(args: &[String]) -> Result<(), String> {
    let [a] = args else { return Err("usage: fili-archive list ARCHIVE".into()) };
    let name = file_name(Path::new(a));
    let tar = split_ext(&name).map(|(_, e)| is_tar(e)).unwrap_or(false);
    let st = if tar {
        Command::new("tar").args(["-tvf", a]).status()
    } else {
        Command::new("7z").args(["l", "-bd", "--", a]).status()
    }
    .map_err(|e| e.to_string())?;
    if st.success() { Ok(()) } else { Err(format!("cannot read “{name}”")) }
}

// ---- transaction et annonce ----------------------------------------------------------------------------

fn tx_made(paths: &[PathBuf], label: &str) {
    let tx = format!("{}/.local/bin/fili-tx", env::var("HOME").unwrap_or_default());
    let tx = if Path::new(&tx).exists() { tx } else { "fili-tx".into() };
    let quiet = |args: &[OsString]| {
        Command::new(&tx).args(args).stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok_and(|s| s.success())
    };
    if quiet(&[os("begin"), os(label)]) {
        let mut a = vec![os("made")];
        a.extend(paths.iter().map(|p| p.clone().into_os_string()));
        quiet(&a);
    }
}

fn size_of(p: &Path) -> String {
    let n = fs::metadata(p).map(|m| m.len()).unwrap_or(0) as f64;
    match n {
        n if n >= 1e9 => format!("{:.1} GB", n / 1e9),
        n if n >= 1e6 => format!("{:.1} MB", n / 1e6),
        n if n >= 1e3 => format!("{:.0} kB", n / 1e3),
        n => format!("{n:.0} B"),
    }
}

fn notify(title: &str, body: &str, urgent: bool) {
    let _ = Command::new("notify-send")
        .args(["-a", "fili-archive", "-u", if urgent { "critical" } else { "normal" }, title, body])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let Some(cmd) = args.first().map(String::as_str) else {
        eprintln!("usage: fili-archive pack|unpack|open|list ... (voir l'en-tête de apps/fili-archive/src/main.rs)");
        std::process::exit(2);
    };
    let rest = &args[1..];
    let quiet = rest.iter().any(|a| a == "-q" || a == "--quiet");
    let tty = quiet || std::io::stdout().is_terminal();
    let (done, errors, label, verb) = match cmd {
        "pack" | "compress" => match pack(rest) {
            Ok(p) => (p, vec![], "Compress", "Archive created"),
            Err(e) => (vec![], vec![e], "Compress", ""),
        },
        "unpack" | "extract" | "open" => {
            let (d, e) = unpack(rest);
            (d, e, "Extract", "Extracted")
        }
        "list" => match list(rest) {
            Ok(()) => return,
            Err(e) => {
                eprintln!("fili-archive: {e}");
                std::process::exit(1);
            }
        },
        "-h" | "--help" | "help" => {
            println!(
                "fili-archive pack [-f zip|7z|tar.gz|tar.xz|tar.zst] [-l fast|normal|best] [--no-hidden] [-q] [-o OUT] FILE...\nfili-archive unpack [-o FOLDER] ARCHIVE...\nfili-archive open ARCHIVE...\nfili-archive list ARCHIVE"
            );
            return;
        }
        _ => {
            eprintln!("fili-archive: unknown command “{cmd}”");
            std::process::exit(2);
        }
    };
    if !done.is_empty() {
        if !quiet {
            tx_made(&done, label);
        }
        for p in &done {
            println!("{}", p.display());
        }
        if !tty {
            let body = if done.len() == 1 {
                format!("{} ({})", file_name(&done[0]), size_of(&done[0]))
            } else {
                format!("{} items", done.len())
            };
            notify(verb, &body, false);
        }
    }
    for e in &errors {
        eprintln!("fili-archive: {e}");
        if !tty {
            notify(&format!("{label} failed"), e, true);
        }
    }
    if !errors.is_empty() {
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extensions() {
        assert_eq!(split_ext("a.tar.gz"), Some(("a".into(), "tar.gz")));
        assert_eq!(split_ext("Photos.ZIP"), Some(("Photos".into(), "zip")));
        assert_eq!(split_ext("a.b.7z"), Some(("a.b".into(), "7z")));
        assert_eq!(split_ext(".zip"), None);
        assert_eq!(split_ext("notes.txt"), None);
        assert!(is_tar("tgz") && is_tar("tar.zst") && !is_tar("zip"));
    }
}
