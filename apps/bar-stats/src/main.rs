// Modules de la barre (Quickshell, protocole JSON des modules custom de Waybar) CPU, mémoire et température, résidents:
// `bar-stats cpu|mem|temp` écrit une ligne JSON par intervalle. Lit /proc et /sys directement, sans lancer top, ps ni awk.
// `bar-stats watch` surveille les indicateurs à changement rare et réveille leur module par signal (voir watch).
// `bar-stats net|disk`: réseau et espace disque, comme les anciens modules intégrés de Waybar.
// Se termine quand la barre ferme le tuyau.
use std::{collections::HashMap, env, ffi::CStr, fs, io::Write, net::Ipv4Addr, os::unix::fs::{MetadataExt, OpenOptionsExt}, process, thread, time::{Duration, Instant}};

struct Proc {
    name: String,
    ticks: u64, // utime + stime
    rss_kb: u64,
}

fn procs(page_kb: u64) -> HashMap<u32, Proc> {
    let mut out = HashMap::new();
    let Ok(dir) = fs::read_dir("/proc") else { return out };
    for e in dir.flatten() {
        let Some(pid) = e.file_name().to_str().and_then(|s| s.parse::<u32>().ok()) else { continue };
        let Ok(stat) = fs::read_to_string(format!("/proc/{pid}/stat")) else { continue };
        // nom entre la première « ( » et la dernière « ) » (il peut contenir des espaces ou des parenthèses)
        let (Some(a), Some(b)) = (stat.find('('), stat.rfind(')')) else { continue };
        let f: Vec<&str> = stat[b + 2..].split_whitespace().collect();
        if f.len() < 22 {
            continue;
        }
        let n = |i: usize| f[i].parse::<u64>().unwrap_or(0);
        out.insert(pid, Proc { name: stat[a + 1..b].to_string(), ticks: n(11) + n(12), rss_kb: n(21) * page_kb });
    }
    out
}

// (occupé, total) en ticks depuis le démarrage; « id » seul compte comme repos (comme top)
fn cpu_times() -> (u64, u64) {
    let s = fs::read_to_string("/proc/stat").unwrap_or_default();
    let v: Vec<u64> = s.lines().next().unwrap_or("").split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
    let total: u64 = v.iter().take(8).sum();
    (total - v.get(3).copied().unwrap_or(0), total)
}

// Pango et JSON: on retire ce qui casserait l'un ou l'autre, comme l'ancien script
fn clean(s: &str) -> String {
    s.chars().filter(|c| !matches!(c, '&' | '<' | '>' | '"' | '\\')).take(22).collect()
}

fn emit(line: String) {
    let mut out = std::io::stdout().lock();
    if writeln!(out, "{line}").and_then(|_| out.flush()).is_err() {
        process::exit(0);
    }
}

fn cpu(every: Duration, page_kb: u64, hz: f64) {
    let mut prev = procs(page_kb);
    let mut prev_cpu = cpu_times();
    let mut prev_t = Instant::now();
    let mut wait = Duration::from_millis(500); // premier affichage rapide
    loop {
        thread::sleep(wait);
        wait = every;
        let now = procs(page_kb);
        let cur_cpu = cpu_times();
        let secs = prev_t.elapsed().as_secs_f64();
        prev_t = Instant::now();
        let (busy, total) = (cur_cpu.0 - prev_cpu.0, cur_cpu.1 - prev_cpu.1);
        let usage = if total > 0 { busy * 100 / total } else { 0 };
        let mut top: Vec<(f64, &Proc)> = now
            .iter()
            .map(|(pid, p)| {
                let d = p.ticks.saturating_sub(prev.get(pid).filter(|q| q.name == p.name).map_or(p.ticks, |q| q.ticks));
                (d as f64 / hz / secs * 100.0, p)
            })
            .collect();
        top.sort_by(|a, b| b.0.total_cmp(&a.0));
        let tip: Vec<String> = top
            .iter()
            .take(5)
            .map(|(pct, p)| {
                let mem = if p.rss_kb >= 1_048_576 { format!("{:.1}G", p.rss_kb as f64 / 1_048_576.0) } else { format!("{}M", p.rss_kb / 1024) };
                format!("{:<22} {pct:5.1}%  {mem}", clean(&p.name))
            })
            .collect();
        emit(format!(r#"{{"text":"{usage}%","tooltip":"<tt>Top CPU\n{}</tt>"}}"#, tip.join("\\n")));
        prev = now;
        prev_cpu = cur_cpu;
    }
}

fn mem(every: Duration, page_kb: u64) {
    loop {
        let info = fs::read_to_string("/proc/meminfo").unwrap_or_default();
        let field = |k: &str| {
            info.lines().find(|l| l.starts_with(k)).and_then(|l| l.split_whitespace().nth(1)).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0)
        };
        let used = field("MemTotal:").saturating_sub(field("MemAvailable:")) as f64 / 1_048_576.0;
        // RSS cumulé par nom de processus
        let mut by_name: HashMap<String, u64> = HashMap::new();
        for p in procs(page_kb).into_values() {
            *by_name.entry(p.name).or_default() += p.rss_kb;
        }
        let mut top: Vec<(String, u64)> = by_name.into_iter().collect();
        top.sort_by(|a, b| b.1.cmp(&a.1));
        let tip: Vec<String> = top
            .iter()
            .take(5)
            .map(|(n, kb)| {
                let v = if *kb >= 1_048_576 { format!("{:.1} Go", *kb as f64 / 1_048_576.0) } else { format!("{} Mo", kb / 1024) };
                format!("{:<22} {v}", clean(n))
            })
            .collect();
        emit(format!(r#"{{"text":"{used:.1}G","tooltip":"<tt>Top RAM\n{}</tt>"}}"#, tip.join("\\n")));
        thread::sleep(every);
    }
}

// Sonde du CPU: hwmon coretemp (Intel), k10temp/zenpower (AMD) ou cpu_thermal (ARM), puis zone x86_pkg_temp; à défaut la
// première sonde disponible (hwmon*/temp1_input puis thermal_zone*/temp); rien dans une VM. Le premier hwmon est souvent le NVMe.
fn temp_path() -> Option<String> {
    for dir in fs::read_dir("/sys/class/hwmon").into_iter().flatten().flatten() {
        let name = fs::read_to_string(dir.path().join("name")).unwrap_or_default();
        let p = dir.path().join("temp1_input");
        if matches!(name.trim(), "coretemp" | "k10temp" | "zenpower" | "cpu_thermal") && fs::metadata(&p).is_ok() {
            return p.to_str().map(String::from);
        }
    }
    for (dir, prefix, file) in [("/sys/class/hwmon", "hwmon", "temp1_input"), ("/sys/class/thermal", "thermal_zone", "temp")] {
        let mut names: Vec<String> = fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|e| e.file_name().into_string().ok())
            .filter(|n| n.starts_with(prefix))
            .collect();
        names.sort();
        if let Some(p) = names.iter().map(|n| format!("{dir}/{n}/{file}")).find(|p| fs::metadata(p).is_ok()) {
            return Some(p);
        }
    }
    None
}

// Affichée seulement quand la température est élevée: dès 50 °C, masquée de nouveau sous 45 °C (hystérésis)
fn temp(every: Duration) {
    let path = temp_path();
    let mut shown = false;
    loop {
        match path.as_ref().and_then(|p| fs::read_to_string(p).ok()).and_then(|s| s.trim().parse::<i64>().ok()) {
            Some(t) if (shown && t / 1000 >= 45) || t / 1000 >= 50 => {
                shown = true;
                let c = t / 1000;
                let class = if c >= 90 { "critical" } else { "" };
                emit(format!(r#"{{"text":" {c}°","class":"{class}","tooltip":"Température CPU: {c}°C"}}"#));
            }
            _ => {
                shown = false;
                emit(r#"{"text":""}"#.into());
            }
        }
        thread::sleep(every);
    }
}

// Ligne de commande pour le fili-shell (Quickshell): tuyau nommé lu par FiliShell.qml; ignorée s'il ne tourne pas
// (ouverture non bloquante: ENXIO sans lecteur)
fn shell_cmd(line: &str) {
    let run = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    if let Ok(mut f) = fs::OpenOptions::new().write(true).custom_flags(libc::O_NONBLOCK).open(format!("{run}/fili-shell")) {
        let _ = writeln!(f, "{line}");
    }
}

// Rafraîchit un module de la fili-bar (`bar refresh N` dans le tuyau) ou de Waybar (signal temps réel, comme `pkill -RTMIN+n waybar`);
// /proc n'est parcouru que lorsqu'un état change
fn refresh(sig: i32) {
    shell_cmd(&format!("bar refresh {sig}"));
    let Ok(dir) = fs::read_dir("/proc") else { return };
    for e in dir.flatten() {
        let Some(pid) = e.file_name().to_str().and_then(|s| s.parse::<i32>().ok()) else { continue };
        if fs::read_to_string(format!("/proc/{pid}/comm")).is_ok_and(|c| c.trim_end() == "waybar") {
            // SAFETY: envoi d'un signal, sans effet sur ce processus
            unsafe { libc::kill(pid, libc::SIGRTMIN() + sig) };
        }
    }
}

// Sessions SSH entrantes établies (port local 22), comme `ss -Htn state established '( sport = :22 )'`
fn ssh_in() -> usize {
    ["/proc/net/tcp", "/proc/net/tcp6"]
        .iter()
        .filter_map(|p| fs::read_to_string(p).ok())
        .map(|s| {
            s.lines()
                .skip(1)
                .filter(|l| {
                    let f: Vec<&str> = l.split_whitespace().collect();
                    f.len() > 3 && f[3] == "01" && f[1].ends_with(":0016")
                })
                .count()
        })
        .sum()
}

// Mode avion: une radio bloquée par logiciel (`rfkill list` « Soft blocked: yes »)
fn airplane() -> bool {
    fs::read_dir("/sys/class/rfkill")
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| fs::read_to_string(e.path().join("soft")).is_ok_and(|s| s.trim() == "1"))
}

// Interfaces VPN levées (IFF_UP), mêmes préfixes que bar-status vpn
fn vpn() -> String {
    let mut up: Vec<String> = fs::read_dir("/sys/class/net")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| ["tun", "tap", "wg", "tailscale", "proton", "nordlynx"].iter().any(|p| n.starts_with(p)))
        .filter(|n| {
            fs::read_to_string(format!("/sys/class/net/{n}/flags"))
                .ok()
                .and_then(|f| u32::from_str_radix(f.trim().trim_start_matches("0x"), 16).ok())
                .is_some_and(|f| f & 1 != 0)
        })
        .collect();
    up.sort();
    up.join(" ")
}

// Verrou flock tenu (sauvegarde en cours), lu dans /proc/locks: le tester avec flock pourrait faire échouer watch-backup
fn locked(path: &str) -> bool {
    let Ok(ino) = fs::metadata(path).map(|m| m.ino().to_string()) else { return false };
    fs::read_to_string("/proc/locks")
        .unwrap_or_default()
        .lines()
        .any(|l| l.split_whitespace().any(|t| t.matches(':').count() == 2 && t.rsplit(':').next() == Some(ino.as_str())))
}

// Indicateurs à changement rare, sans sondage de la barre: `bar-stats watch` lit /proc et /sys à chaque intervalle
// sans rien lancer et ne réveille un module (signal) que si son état a changé. Remplace les "interval" de 10 à 120 s
// de remote, air, vpn, night, backup, cal et batwatch, qui lançaient chacun un shell et ses commandes.
fn watch(every: Duration) {
    // Lancé par `exec` depuis la barre: s'arrête avec elle
    // SAFETY: prctl ne touche qu'aux attributs de ce processus
    unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) };
    emit(r#"{"text":""}"#.into());
    let home = env::var("HOME").unwrap_or_default();
    let run = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let night = format!("{run}/wlsunset.log");
    let lock = format!("{home}/.local/state/watch/backup.lock");
    let cal = format!("{home}/.local/state/alerts/cal");
    let batwatch = format!("{home}/.local/bin/bar-status");
    let bat = "/sys/class/power_supply/BAT0";
    // (signal du module, empreinte de son état); /proc/net/tcp* coûte plus cher (sockets parcourues): un tour sur trois
    let mut tick = 0u64;
    let probes: [(i32, Box<dyn Fn(u64) -> Option<String>>); 5] = [
        (21, Box::new(|t| (t % 3 == 0).then(|| ssh_in().to_string()))),
        (14, Box::new(|_| Some(airplane().to_string()))),
        (22, Box::new(|_| Some(vpn()))),
        // wlsunset écrit une ligne à chaque changement de température (bar-status night la lit)
        (10, Box::new(move |_| Some(format!("{:?}", fs::metadata(&night).map(|m| (m.len(), m.modified().ok())).ok())))),
        (18, Box::new(move |_| Some(locked(&lock).to_string()))),
    ];
    let mut seen: Vec<String> = probes.iter().map(|(_, f)| f(0).unwrap_or_default()).collect();
    let (mut low, mut bat_seen) = (false, String::new());
    let mut cal_t = Instant::now();
    loop {
        thread::sleep(every);
        tick += 1;
        for ((sig, f), old) in probes.iter().zip(seen.iter_mut()) {
            let Some(v) = f(tick) else { continue };
            if v != *old {
                refresh(*sig);
                *old = v;
            }
        }
        // Agenda: l'événement affiché disparaît 5 min après son début, rafraîchi chaque minute tant qu'il y en a un
        if cal_t.elapsed() >= Duration::from_secs(60) {
            cal_t = Instant::now();
            if fs::metadata(&cal).is_ok_and(|m| m.len() > 0) {
                refresh(17);
            }
        }
        // Batterie faible: alerte et extinction restent dans `bar-status batwatch`, lancé seulement quand l'état
        // bouge sous 10 % sur batterie, et une fois au retour (chargeur branché) pour réarmer l'alerte.
        // status interroge le matériel (~1 ms, contre quelques µs pour capacity): lu seulement sous 10 %
        let cap = fs::read_to_string(format!("{bat}/capacity")).ok().and_then(|s| s.trim().parse::<u8>().ok()).unwrap_or(100);
        let status = if cap <= 10 || low { fs::read_to_string(format!("{bat}/status")).unwrap_or_default() } else { String::new() };
        let now_low = status.trim() == "Discharging" && cap <= 10;
        let fp = format!("{} {cap}", status.trim());
        if (now_low || low) && fp != bat_seen {
            let _ = process::Command::new(&batwatch).arg("batwatch").stdout(process::Stdio::null()).status();
        }
        (low, bat_seen) = (now_low, fp);
    }
}

// Taille lisible en octets (base 1024, comme Waybar)
fn human(b: f64) -> String {
    let units = ["o", "Kio", "Mio", "Gio", "Tio"];
    let mut v = b;
    let mut i = 0;
    while v >= 1024.0 && i < units.len() - 1 {
        v /= 1024.0;
        i += 1;
    }
    if i == 0 { format!("{v:.0} {}", units[i]) } else { format!("{v:.1} {}", units[i]) }
}

// Espace disque de / (statvfs), comme le module disk de Waybar
// Affiché seulement quand presque plein: dès 90 %, masqué de nouveau sous 88 % (hystérésis)
fn disk(every: Duration) {
    let mut shown = false;
    loop {
        // SAFETY: statvfs remplit une structure initialisée à zéro, chemin C valide
        let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
        if unsafe { libc::statvfs(c"/".as_ptr(), &mut s) } == 0 {
            let f = s.f_frsize as f64;
            let (total, free, avail) = (s.f_blocks as f64 * f, s.f_bfree as f64 * f, s.f_bavail as f64 * f);
            let used = total - free;
            let pct = (used * 100.0 / (used + avail)).round();
            shown = (shown && pct >= 88.0) || pct >= 90.0;
            if !shown {
                emit(r#"{"text":""}"#.into());
                thread::sleep(every);
                continue;
            }
            let class = if pct >= 95.0 { "critical" } else { "" };
            emit(format!(
                r#"{{"text":"\uf0a0 {pct}%","class":"{class}","tooltip":"{} / {} ({} libres)"}}"#,
                human(used),
                human(total),
                human(avail)
            ));
        }
        thread::sleep(every);
    }
}

// Interface de la route par défaut (/proc/net/route, destination 0)
fn default_iface() -> Option<String> {
    fs::read_to_string("/proc/net/route").ok()?.lines().skip(1).find_map(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        (f.len() > 1 && f[1] == "00000000").then(|| f[0].to_string())
    })
}

// Première adresse IPv4 de l'interface (getifaddrs)
fn ipv4(iface: &str) -> Option<Ipv4Addr> {
    let mut list: *mut libc::ifaddrs = std::ptr::null_mut();
    // SAFETY: liste allouée par getifaddrs, parcourue en lecture puis libérée par freeifaddrs
    unsafe {
        if libc::getifaddrs(&mut list) != 0 {
            return None;
        }
        let mut cur = list;
        let mut found = None;
        while !cur.is_null() {
            let a = &*cur;
            if !a.ifa_addr.is_null()
                && i32::from((*a.ifa_addr).sa_family) == libc::AF_INET
                && CStr::from_ptr(a.ifa_name).to_str() == Ok(iface)
            {
                let sin = &*(a.ifa_addr as *const libc::sockaddr_in);
                found = Some(Ipv4Addr::from(u32::from_be(sin.sin_addr.s_addr)));
                break;
            }
            cur = a.ifa_next;
        }
        libc::freeifaddrs(list);
        found
    }
}

fn counter(iface: &str, name: &str) -> u64 {
    fs::read_to_string(format!("/sys/class/net/{iface}/statistics/{name}")).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0)
}

// Réseau, comme le module network de Waybar: lit /proc et /sys toutes les 5 s, n'écrit que si l'état change
// (débits rafraîchis toutes les 30 s); SSID et fréquence via `iw` seulement quand le lien change (iwd n'expose rien dans /sys)
fn net(every: Duration) {
    let mut last_key = String::new();
    let mut last_level = -1;
    let (mut ssid, mut freq) = (String::new(), String::new());
    let mut prev: Option<(String, u64, u64, Instant)> = None;
    let mut rates = (0.0, 0.0);
    let mut since = Instant::now() - Duration::from_secs(3600);
    loop {
        let iface = default_iface();
        let ip = iface.as_deref().and_then(ipv4);
        let key = format!("{iface:?} {ip:?}");
        let wifi = iface.as_deref().is_some_and(|i| fs::metadata(format!("/sys/class/net/{i}/wireless")).is_ok());
        let changed = key != last_key;
        // Qualité du lien Wi-Fi en % (/proc/net/wireless: sur 70) et palier d'icône: 0 à 3
        let q = if wifi {
            iface.as_deref().and_then(|i| {
                fs::read_to_string("/proc/net/wireless").ok()?.lines()
                    .find(|l| l.trim_start().starts_with(&format!("{i}:")))
                    .and_then(|l| l.split_whitespace().nth(2).and_then(|v| v.trim_end_matches('.').parse::<f64>().ok()))
                    .map(|v| (v * 100.0 / 70.0).round() as i64)
            }).unwrap_or(0)
        } else {
            0
        };
        let level = if !wifi { -1 } else if q >= 70 { 3 } else if q >= 45 { 2 } else if q >= 20 { 1 } else { 0 };
        if changed && wifi {
            let out = process::Command::new("iw").args(["dev", iface.as_deref().unwrap_or(""), "link"]).output();
            let text = out.map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default();
            let field = |k: &str| text.lines().find_map(|l| l.trim().strip_prefix(k).map(|v| v.trim().to_string())).unwrap_or_default();
            ssid = field("SSID:");
            freq = field("freq:").split('.').next().unwrap_or("").to_string();
        }
        if changed || level != last_level || since.elapsed() >= Duration::from_secs(30) {
            if let Some(i) = iface.as_deref() {
                let (rx, tx, now) = (counter(i, "rx_bytes"), counter(i, "tx_bytes"), Instant::now());
                if let Some((pi, prx, ptx, pt)) = &prev {
                    let secs = now.duration_since(*pt).as_secs_f64();
                    if pi == i && secs > 0.0 {
                        rates = (rx.saturating_sub(*prx) as f64 / secs, tx.saturating_sub(*ptx) as f64 / secs);
                    }
                }
                prev = Some((i.to_string(), rx, tx, now));
            }
            since = Instant::now();
            last_key = key;
            last_level = level;
            let ipt = ip.map(|a| a.to_string()).unwrap_or_else(|| "pas d'IPv4".into());
            let bw = format!("↓ {}/s  ↑ {}/s", human(rates.0), human(rates.1));
            let line = match iface.as_deref() {
                None => r#"{"text":"\uf071 hors ligne","class":"disconnected","tooltip":"Aucune connexion (clic: Wi-Fi)"}"#.to_string(),
                Some(_) if wifi => {
                    // Icône selon la qualité (codes md-wifi_strength_1..4, police Fili Icons): trait plein = bon signal
                    let glyph = ['\u{F091F}', '\u{F0922}', '\u{F0925}', '\u{F0928}'][level as usize];
                    let ghz = freq.parse::<f64>().map(|f| format!("{:.1}", f / 1000.0)).unwrap_or_default();
                    let full = clean(&ssid);
                    let name = if full.chars().count() > 16 { format!("{}…", full.chars().take(15).collect::<String>()) } else { full.clone() };
                    format!(r#"{{"text":"{glyph} {name}","class":"wifi","tooltip":"{full} ({q}%)  {ghz} GHz\n{ipt}\n{bw}"}}"#)
                }
                Some(i) => format!(r#"{{"text":"\uf796 {i}","class":"ethernet","tooltip":"{i}: {ipt}\n{bw}"}}"#),
            };
            emit(line);
        }
        thread::sleep(every);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let secs = |default: u64| Duration::from_secs(args.get(2).and_then(|s| s.parse().ok()).unwrap_or(default));
    // SAFETY: sysconf n'a pas d'effet de bord
    let (page_kb, hz) = unsafe { (libc::sysconf(libc::_SC_PAGESIZE) as u64 / 1024, libc::sysconf(libc::_SC_CLK_TCK) as f64) };
    match args.get(1).map(String::as_str) {
        Some("cpu") => cpu(secs(10), page_kb, hz),
        Some("mem") => mem(secs(15), page_kb),
        Some("temp") => temp(secs(15)),
        Some("watch") => watch(secs(5)),
        Some("net") => net(secs(5)),
        Some("disk") => disk(secs(300)),
        _ => {
            eprintln!("usage: bar-stats cpu|mem|temp|watch|net|disk [intervalle en s]");
            process::exit(2);
        }
    }
}
