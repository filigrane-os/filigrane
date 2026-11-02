// fili-automount: monte tout seul les clés USB, cartes SD et disques externes à leur branchement.
// Écoute les événements udev des disques (`udevadm monitor`, un petit processus, aucune dépendance), puis monte avec
// udisks (comme le fait le clic dans la barre latérale de Casier) et annonce le résultat par une notification.
// Lancé au démarrage de la session par niri. Réglage: `automount = false` dans ~/.config/filigrane/fili-file.toml.
// Ne monte que du neuf: un disque déjà branché au démarrage, ou démonté par l'utilisateur, reste tel quel.
#![allow(dead_code)]
#[path = "../../bar-stats/src/i18n.rs"]
mod i18n;
#[path = "../../fili-file/src/volumes.rs"]
mod volumes;

use i18n::{tr, trf};
use std::{
    env, fs,
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    thread::sleep,
    time::Duration,
};

fn enabled() -> bool {
    let home = env::var("HOME").unwrap_or_default();
    let dir = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
    let text = fs::read_to_string(format!("{dir}/filigrane/fili-file.toml")).unwrap_or_default();
    !text.lines().any(|l| {
        let l = l.split('#').next().unwrap_or("").trim();
        l.split_once('=').is_some_and(|(k, v)| k.trim() == "automount" && v.trim() == "false")
    })
}

fn notify(title: &str, body: &str, urgent: bool) {
    let _ = Command::new("notify-send")
        .args(["-a", "fili-automount", "-u", if urgent { "critical" } else { "normal" }, title, body])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

// Un événement udev (bloc de lignes « CLE=valeur ») qui annonce un volume neuf avec un système de fichiers
fn new_volume(props: &std::collections::HashMap<String, String>) -> Option<String> {
    let get = |k: &str| props.get(k).map(String::as_str).unwrap_or("");
    let fresh = match get("ACTION") {
        "add" => true,
        // lecteur de cartes: la carte arrive par un « change » du disque
        "change" => get("DISK_MEDIA_CHANGE") == "1",
        _ => false,
    };
    if !fresh || get("ID_FS_USAGE") != "filesystem" || get("ID_FS_TYPE").is_empty() || !["partition", "disk"].contains(&get("DEVTYPE")) {
        return None;
    }
    Some(get("DEVNAME").to_string()).filter(|d| !d.is_empty())
}

fn handle(dev: &str) {
    // udisks et lsblk ont besoin d'un instant pour voir le volume
    sleep(Duration::from_millis(800));
    let Some(v) = volumes::list().into_iter().find(|v| v.dev == dev) else { return };
    if v.mount.is_some() || !enabled() {
        return;
    }
    match volumes::mount(dev) {
        Ok(path) => notify(&trf("%1 mounted", &[&v.name]), &path, false),
        Err(e) => notify(&trf("Cannot mount %1", &[&v.name]), if e.is_empty() { tr("the tool reported an error") } else { &e }, true),
    }
}

fn main() {
    loop {
        let child = Command::new("udevadm")
            .args(["monitor", "--udev", "--subsystem-match=block", "--property"])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        if let Ok(mut c) = child {
            let mut props = std::collections::HashMap::new();
            for line in BufReader::new(c.stdout.take().unwrap()).lines().map_while(Result::ok) {
                if line.trim().is_empty() {
                    if let Some(dev) = new_volume(&props) {
                        std::thread::spawn(move || handle(&dev));
                    }
                    props.clear();
                } else if let Some((k, v)) = line.split_once('=') {
                    props.insert(k.to_string(), v.to_string());
                }
            }
            let _ = c.wait();
        }
        // udevadm s'est arrêté (udevd relancé): on réessaie
        sleep(Duration::from_secs(5));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(pairs: &[(&str, &str)]) -> std::collections::HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn detects_new_volumes_only() {
        let usb = [("ACTION", "add"), ("DEVTYPE", "partition"), ("DEVNAME", "/dev/sdb1"), ("ID_FS_USAGE", "filesystem"), ("ID_FS_TYPE", "vfat")];
        assert_eq!(new_volume(&ev(&usb)).as_deref(), Some("/dev/sdb1"));
        // pas de système de fichiers (table de partitions, disque vide) ou événement qui n'est pas un branchement
        assert_eq!(new_volume(&ev(&[("ACTION", "add"), ("DEVTYPE", "disk"), ("DEVNAME", "/dev/sdb")])), None);
        let mut change = usb.to_vec();
        change[0] = ("ACTION", "change");
        assert_eq!(new_volume(&ev(&change)), None, "un change ordinaire (après un démontage) ne remonte pas le disque");
        change.push(("DISK_MEDIA_CHANGE", "1"));
        assert_eq!(new_volume(&ev(&change)).as_deref(), Some("/dev/sdb1"));
        let mut remove = usb.to_vec();
        remove[0] = ("ACTION", "remove");
        assert_eq!(new_volume(&ev(&remove)), None);
    }
}
