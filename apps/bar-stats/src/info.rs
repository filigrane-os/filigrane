// Fiches des fili-tooltip et fili-panel (réseau, alimentation, moniteur), en JSON {title, hint, rows: [[libellé, valeur]...]}
// (lignes à valeur vide retirées). Demandées par la barre sur l'entrée standard (`info SUJET`, réponse `info SUJET JSON`)
// ou en ligne de commande (`bar-stats info SUJET`). Lues dans /proc et /sys; seuls `iw` (Wi-Fi) et `ping` sont lancés.
use crate::{ac_online, counter, default_iface, human, ipv4, Usage};
use std::{fs, net::Ipv4Addr, net::Ipv6Addr, process};

// Chaîne JSON échappée
fn js(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

pub fn card(title: &str, hint: &str, rows: &[(&str, String)]) -> String {
    let rows: Vec<String> = rows.iter().filter(|(_, v)| !v.trim().is_empty()).map(|(k, v)| format!("[{},{}]", js(k), js(v))).collect();
    format!(r#"{{"title":{},"hint":{},"rows":[{}]}}"#, js(title), js(hint), rows.join(","))
}

fn read(p: &str) -> String {
    fs::read_to_string(p).map(|s| s.trim().to_string()).unwrap_or_default()
}

// Passerelle de la route par défaut (/proc/net/route: adresse en hexadécimal, octets dans l'ordre de la machine)
pub fn gateway(iface: &str) -> Option<Ipv4Addr> {
    fs::read_to_string("/proc/net/route").ok()?.lines().skip(1).find_map(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        (f.len() > 2 && f[0] == iface && f[1] == "00000000").then(|| u32::from_str_radix(f[2], 16).ok()).flatten().map(|v| Ipv4Addr::from(v.to_le_bytes()))
    })
}

// Première adresse IPv6 globale (/proc/net/if_inet6, portée 00)
fn ipv6(iface: &str) -> String {
    fs::read_to_string("/proc/net/if_inet6")
        .unwrap_or_default()
        .lines()
        .find_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            (f.len() == 6 && f[5] == iface && f[3] == "00").then(|| u128::from_str_radix(f[0], 16).ok()).flatten().map(|v| Ipv6Addr::from(v).to_string())
        })
        .unwrap_or_default()
}

fn dns() -> String {
    let r = fs::read_to_string("/etc/resolv.conf").unwrap_or_default();
    r.lines().filter_map(|l| l.strip_prefix("nameserver")).map(str::trim).collect::<Vec<_>>().join(", ")
}

// `ping -c 1` vers la passerelle: "12.3 ms"
pub fn ping_time(out: &str) -> String {
    out.split("time=").nth(1).and_then(|t| t.split_whitespace().next()).and_then(|t| t.parse::<f64>().ok()).map(|t| format!("{t:.1} ms")).unwrap_or_default()
}
pub fn ping_cmd(gw: Ipv4Addr) -> process::Command {
    let mut c = process::Command::new("ping");
    c.args(["-n", "-c", "1", "-W", "1", &gw.to_string()]);
    c
}

const NET_HINT: &str = "clic: panneau réseau · clic droit: menu réseau";

// Fiche réseau; ping: temps vers la passerelle s'il est déjà mesuré
pub fn network(ping: &str) -> String {
    let Some(iface) = default_iface() else {
        let mut all: Vec<String> = fs::read_dir("/sys/class/net").into_iter().flatten().flatten().filter_map(|e| e.file_name().into_string().ok()).filter(|n| n != "lo").collect();
        all.sort();
        return card("Hors ligne", NET_HINT, &[("Interfaces", all.join(" "))]);
    };
    let gw = gateway(&iface).map(|g| g.to_string()).unwrap_or_default();
    let ip4 = ipv4(&iface).map(|(a, p)| format!("{a}/{p}")).unwrap_or_default();
    let common = |mut rows: Vec<(&'static str, String)>| {
        rows.extend([
            ("Adresse IP", ip4.clone()),
            ("IPv6", ipv6(&iface)),
            ("Passerelle", gw.clone()),
            ("Ping passerelle", ping.to_string()),
            ("DNS", dns()),
            ("Reçu", human(counter(&iface, "rx_bytes") as f64)),
            ("Envoyé", human(counter(&iface, "tx_bytes") as f64)),
        ]);
        rows
    };
    if fs::metadata(format!("/sys/class/net/{iface}/wireless")).is_ok() {
        let out = process::Command::new("iw").args(["dev", &iface, "link"]).output();
        let text = out.map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default();
        let val = |k: &str| text.lines().find_map(|l| l.trim_start().strip_prefix(k).map(|v| v.trim().to_string())).unwrap_or_default();
        let dbm = val("signal:").split_whitespace().next().and_then(|v| v.parse::<i64>().ok());
        let q = dbm.map(|d| format!("{} % ({d} dBm)", (2 * (d + 100)).clamp(0, 100))).unwrap_or_default();
        let freq = val("freq:").split('.').next().and_then(|f| f.parse::<i64>().ok());
        let band = freq
            .map(|f| {
                let (b, c) = if f >= 5925 { ("6 GHz", (f - 5950) / 5) } else if f >= 4900 { ("5 GHz", (f - 5000) / 5) } else { ("2,4 GHz", if f == 2484 { 14 } else { (f - 2407) / 5 }) };
                format!("{b}, canal {c}")
            })
            .unwrap_or_default();
        let two = |k: &str| val(k).split_whitespace().take(2).collect::<Vec<_>>().join(" ");
        let rate = format!("{} ↓  {} ↑", two("rx bitrate:"), two("tx bitrate:"));
        let rows = common(vec![("Signal", q), ("Bande", band), ("Débit du lien", rate), ("Interface", iface.clone())]);
        card(&val("SSID:"), NET_HINT, &rows)
    } else {
        let speed = read(&format!("/sys/class/net/{iface}/speed"));
        let speed = if speed.is_empty() || speed.starts_with('-') { String::new() } else { format!("{speed} Mbit/s") };
        card(&format!("Ethernet {iface}"), NET_HINT, &common(vec![("Vitesse", speed)]))
    }
}

pub fn power() -> String {
    let b = "/sys/class/power_supply/BAT0";
    let r = |f: &str| read(&format!("{b}/{f}"));
    let cap = r("capacity");
    if cap.is_empty() {
        return card("Secteur", "clic: menu système", &[]);
    }
    let st = r("status");
    let num = |f: &str| r(f).parse::<f64>().ok();
    // charge_* (µAh) et current_now (µA), ou energy_* (µWh) et power_now (µW) selon le matériel
    let (now, full, design, cur, volt) = match num("charge_now") {
        Some(n) => (n, num("charge_full"), num("charge_full_design"), num("current_now"), num("voltage_now")),
        None => (num("energy_now").unwrap_or(0.0), num("energy_full"), num("energy_full_design"), num("power_now"), None),
    };
    let c = cur.unwrap_or(0.0).abs();
    let w = match volt { Some(v) => c * v / 1e12, None => c / 1e6 };
    let watts = if w > 0.05 { format!("{w:.1} W") } else { String::new() };
    let full_v = full.unwrap_or(0.0);
    let t = if c > 0.0 && st == "Discharging" { now / c } else if c > 0.0 && st == "Charging" { (full_v - now) / c } else { -1.0 };
    let hours = if t > 0.0 { format!("{} h {:02}", t as i64, ((t - t.trunc()) * 60.0) as i64) } else { String::new() };
    let health = design.filter(|d| *d > 0.0).map(|d| format!("{} %", (full_v * 100.0 / d) as i64)).unwrap_or_default();
    let ac = ac_online() == Some(true);
    let (state, tl) = match st.as_str() {
        "Discharging" => ("Sur batterie".to_string(), "Temps restant"),
        "Charging" => ("En charge".to_string(), "Pleine dans"),
        // "Full" sous 99 %: seuil de charge atteint (batterie préservée), comme "Holding" dans Omarchy
        "Full" => ((if cap.parse::<u8>().unwrap_or(100) < 99 { "Branchée, charge limitée" } else { "Pleine" }).to_string(), "Temps"),
        _ => (if ac { "Branchée, charge en pause".to_string() } else { st.clone() }, "Temps"),
    };
    let model = format!("{} {}", r("manufacturer"), r("model_name"));
    card(
        &format!("Batterie {cap} %"),
        "clic: panneau alimentation · clic droit: menu système",
        &[
            ("État", state),
            (tl, hours),
            ("Consommation", watts),
            ("Alimentation", (if ac { "Secteur" } else { "Batterie" }).into()),
            ("Santé", health),
            ("Cycles", r("cycle_count")),
            ("Modèle", model.trim().to_string()),
        ],
    )
}

// Taille courte façon `df -h`: 9.5G, 234G
fn short(b: f64) -> String {
    let mut v = b / 1024.0;
    let mut u = 'K';
    for n in ['M', 'G', 'T'] {
        if v < 1024.0 {
            break;
        }
        v /= 1024.0;
        u = n;
    }
    // Arrondi au-dessus, comme df
    if v < 10.0 { format!("{:.1}{u}", (v * 10.0).ceil() / 10.0) } else { format!("{:.0}{u}", v.ceil()) }
}

pub fn monitor(usage: &Usage) -> String {
    let load: Vec<String> = read("/proc/loadavg").split_whitespace().take(3).map(String::from).collect();
    let info = read("/proc/meminfo");
    let field = |k: &str| info.lines().find(|l| l.starts_with(k)).and_then(|l| l.split_whitespace().nth(1)).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
    let gio = 1_048_576.0;
    let (mt, ma, st, sf) = (field("MemTotal:"), field("MemAvailable:"), field("SwapTotal:"), field("SwapFree:"));
    let mem = format!("{:.1} / {:.1} Gio", (mt - ma) / gio, mt / gio);
    let swap = if st > 0.0 { format!("{:.1} / {:.1} Gio", (st - sf) / gio, st / gio) } else { String::new() };
    // SAFETY: statvfs remplit une structure initialisée à zéro, chemin C valide
    let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
    let disk = if unsafe { libc::statvfs(c"/".as_ptr(), &mut s) } == 0 {
        let f = s.f_frsize as f64;
        let (total, used, avail) = (s.f_blocks as f64 * f, (s.f_blocks - s.f_bfree) as f64 * f, s.f_bavail as f64 * f);
        format!("{} / {} ({}%)", short(used), short(total), (used * 100.0 / (used + avail)).ceil())
    } else {
        String::new()
    };
    let temp = fs::read_dir("/sys/class/thermal")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| read(&format!("{}/temp", e.path().display())).parse::<i64>().ok())
        .max()
        .filter(|t| *t > 0)
        .map(|t| format!("{} °C", t / 1000))
        .unwrap_or_default();
    let up = read("/proc/uptime").split_whitespace().next().and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0) as u64;
    let (d, h, m) = (up / 86400, up % 86400 / 3600, up % 3600 / 60);
    let up = format!("{}{h} h {m:02}", if d > 0 { format!("{d} j ") } else { String::new() });
    let top: Vec<String> = usage.top.iter().map(|(n, p)| format!("{n} {p:.1} %")).collect();
    card(
        "Système",
        "",
        &[
            ("Charge", load.join("  ")),
            ("Mémoire", mem),
            ("Swap", swap),
            ("Disque /", disk),
            ("Température", temp),
            ("Allumé depuis", up),
            ("Processus", top.join(", ")),
        ],
    )
}

// Luminosité en % (écran: classe backlight hors Touch Bar; clavier: leds *kbd_backlight), -1 si absent
fn level(class: &str, pick: impl Fn(&str) -> bool) -> i64 {
    let mut names: Vec<String> = fs::read_dir(format!("/sys/class/{class}")).into_iter().flatten().flatten().filter_map(|e| e.file_name().into_string().ok()).filter(|n| pick(n)).collect();
    names.sort();
    names
        .iter()
        .find_map(|n| {
            let c = read(&format!("/sys/class/{class}/{n}/brightness")).parse::<f64>().ok()?;
            let m = read(&format!("/sys/class/{class}/{n}/max_brightness")).parse::<f64>().ok().filter(|m| *m > 0.0)?;
            Some((c * 100.0 / m).round() as i64)
        })
        .unwrap_or(-1)
}

// Module écrans de la barre (stat display): luminosité de l'écran, et celle du clavier pour le fili-panel clavier
pub fn display() -> String {
    let screen = level("backlight", |n| !n.contains("appletb"));
    let kbd = level("leds", |n| n.contains("kbd_backlight"));
    let text = if screen >= 0 { format!("\u{f108} {screen}%") } else { "\u{f108}".into() };
    format!(r#"{{"text":{},"screen":{screen},"kbd":{kbd}}}"#, js(&text))
}
