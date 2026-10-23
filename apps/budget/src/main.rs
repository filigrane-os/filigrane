// Budget ressources de l'OS: ce que le système garde pour lui, hors travail de l'utilisateur (navigateur, agents,
// conteneurs, tout ce qu'ils lancent et tout ce qui est lancé depuis un shell de terminal), comparé à une référence
// ou à des plafonds. Lit /proc directement.
//   budget [secondes]         instantané: mémoire système / applications, plus gros résidents, CPU sur l'intervalle (2 s)
//   budget save [nom]         enregistre la référence (~/.local/state/budget/<nom>, défaut "reference")
//   budget diff [nom]         écart du système à la référence, total et par programme (à lancer après une installation)
//   budget check [--notify]   plafonds de ~/.config/budget/limits; code 1 si dépassés (--notify: notification, code 0)
use std::{collections::HashMap, env, fs, path::PathBuf, process, thread, time::Duration};

struct Proc {
    name: String,
    ppid: u32,
    ticks: u64, // utime + stime
    kb: u64,    // PSS si lisible (processus de l'utilisateur), sinon RSS
    container: bool,
}

#[derive(Default)]
struct Group {
    kb: u64,
    ticks: u64,
    count: u32,
}

struct Limits {
    system_mb: u64,
    process_mb: u64,
    apps: Vec<String>,
    terminals: Vec<String>,
    per: HashMap<String, u64>,
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
        let rss = n(21) * page_kb;
        if rss == 0 {
            continue; // thread noyau
        }
        let pss = fs::read_to_string(format!("/proc/{pid}/smaps_rollup"))
            .ok()
            .and_then(|s| s.lines().find(|l| l.starts_with("Pss:")).and_then(|l| l.split_whitespace().nth(1)?.parse().ok()));
        let container = fs::read_to_string(format!("/proc/{pid}/cgroup")).is_ok_and(|c| c.contains("libpod"));
        out.insert(pid, Proc { name: stat[a + 1..b].to_string(), ppid: n(1) as u32, ticks: n(11) + n(12), kb: pss.unwrap_or(rss), container });
    }
    out
}

fn ticks_of(procs: &HashMap<u32, Proc>) -> HashMap<u32, (String, u64)> {
    procs.iter().map(|(pid, p)| (*pid, (p.name.clone(), p.ticks))).collect()
}

fn meminfo() -> (u64, u64, u64) {
    let info = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let field = |k: &str| info.lines().find(|l| l.starts_with(k)).and_then(|l| l.split_whitespace().nth(1)?.parse::<u64>().ok()).unwrap_or(0);
    (field("MemTotal:"), field("MemAvailable:"), field("SwapTotal:").saturating_sub(field("SwapFree:")))
}

// Utilisé sans appartenir à un processus: noyau (slab non récupérable, piles, tables de pages) et swap compressé
// en RAM (zram, mm_stat: 3e champ en octets). Le reste non attribué: tmpfs, mémoire partagée que plus personne ne mappe.
fn hidden_kb() -> (u64, u64) {
    let info = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let field = |k: &str| info.lines().find(|l| l.starts_with(k)).and_then(|l| l.split_whitespace().nth(1)?.parse::<u64>().ok()).unwrap_or(0);
    let zram: u64 = fs::read_dir("/sys/block")
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with("zram"))
        .filter_map(|e| fs::read_to_string(e.path().join("mm_stat")).ok()?.split_whitespace().nth(2)?.parse::<u64>().ok())
        .sum::<u64>()
        / 1024;
    (field("SUnreclaim:") + field("KernelStack:") + field("PageTables:"), zram)
}

fn cpu_total() -> u64 {
    let s = fs::read_to_string("/proc/stat").unwrap_or_default();
    s.lines().next().unwrap_or("").split_whitespace().skip(1).take(8).filter_map(|x| x.parse::<u64>().ok()).sum()
}

fn home() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| "/".into()))
}

fn limits() -> Limits {
    let mut l = Limits {
        system_mb: 1024,
        process_mb: 150,
        apps: ["chrome", "chromium", "firefox", "claude", "node", "podman", "conmon", "qemu"].map(String::from).to_vec(),
        terminals: ["foot", "alacritty"].map(String::from).to_vec(),
        per: HashMap::new(),
    };
    let dir = env::var("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|_| home().join(".config"));
    let Ok(text) = fs::read_to_string(dir.join("budget/limits")) else { return l };
    let (mut apps_set, mut terms_set) = (false, false);
    for line in text.lines() {
        let w: Vec<&str> = line.split('#').next().unwrap_or("").split_whitespace().collect();
        let num = |i: usize| w.get(i).and_then(|v| v.parse::<u64>().ok());
        match w.first().copied() {
            Some("system") => l.system_mb = num(1).unwrap_or(l.system_mb),
            Some("process") => l.process_mb = num(1).unwrap_or(l.process_mb),
            Some("apps") => {
                if !apps_set {
                    l.apps.clear();
                    apps_set = true;
                }
                l.apps.extend(w[1..].iter().map(|s| s.to_string()));
            }
            Some("terminals") => {
                if !terms_set {
                    l.terminals.clear();
                    terms_set = true;
                }
                l.terminals.extend(w[1..].iter().map(|s| s.to_string()));
            }
            Some("limit") => {
                if let (Some(name), Some(mb)) = (w.get(1), num(2)) {
                    l.per.insert(name.to_string(), mb);
                }
            }
            _ => {}
        }
    }
    l
}

// Travail de l'utilisateur: une application (nom commençant par un préfixe de "apps", ou dans un conteneur), ce
// qu'elle lance, et ce qui est lancé depuis le shell d'un terminal (le terminal et son shell restent du système).
// budget lui-même est ignoré.
fn app_pids(procs: &HashMap<u32, Proc>, lim: &Limits) -> Vec<u32> {
    let is_app = |p: &Proc| p.container || lim.apps.iter().any(|a| p.name.starts_with(a.as_str()));
    let is_term = |pid: u32| procs.get(&pid).is_some_and(|p| lim.terminals.iter().any(|t| p.name == *t));
    let me = process::id();
    procs
        .keys()
        .copied()
        .filter(|&pid| {
            let mut cur = pid;
            for _ in 0..64 {
                let Some(p) = procs.get(&cur) else { return false };
                if cur == me || is_app(p) || (cur != pid && is_term(p.ppid)) {
                    return true;
                }
                if p.ppid <= 1 {
                    return false;
                }
                cur = p.ppid;
            }
            false
        })
        .collect()
}

struct Snapshot {
    used_kb: u64,
    swap_kb: u64,
    apps_kb: u64,
    system: HashMap<String, Group>,
    apps: HashMap<String, Group>,
}

fn snapshot(procs: &HashMap<u32, Proc>, lim: &Limits) -> Snapshot {
    let (total, avail, swap_kb) = meminfo();
    let app: std::collections::HashSet<u32> = app_pids(procs, lim).into_iter().collect();
    let (mut system, mut apps): (HashMap<String, Group>, HashMap<String, Group>) = Default::default();
    for (pid, p) in procs {
        let map = if app.contains(pid) { &mut apps } else { &mut system };
        let g = map.entry(p.name.clone()).or_default();
        g.kb += p.kb;
        g.count += 1;
    }
    let apps_kb = apps.values().map(|g| g.kb).sum();
    Snapshot { used_kb: total.saturating_sub(avail), swap_kb, apps_kb, system, apps }
}

impl Snapshot {
    // Le système = mémoire utilisée (comme free) moins les applications: noyau, caches non récupérables et démons compris
    fn system_kb(&self) -> u64 {
        self.used_kb.saturating_sub(self.apps_kb)
    }
}

fn size(kb: u64) -> String {
    if kb >= 1_048_576 { format!("{:.1} Go", kb as f64 / 1_048_576.0).replace('.', ",") } else { format!("{} Mo", kb / 1024) }
}

fn pct_fr(v: f64) -> String {
    format!("{v:.1} %").replace('.', ",")
}

fn signed(kb: i64) -> String {
    format!("{}{}", if kb < 0 { "-" } else { "+" }, size(kb.unsigned_abs()))
}

fn sorted(map: &HashMap<String, Group>) -> Vec<(&String, &Group)> {
    let mut v: Vec<_> = map.iter().collect();
    v.sort_by(|a, b| b.1.kb.cmp(&a.1.kb));
    v
}

fn label(name: &str, g: &Group) -> String {
    if g.count > 1 { format!("{name} ×{}", g.count) } else { name.to_string() }
}

fn show(secs: u64, page_kb: u64, hz: f64) {
    let lim = limits();
    let before = ticks_of(&procs(page_kb));
    let cpu0 = cpu_total();
    thread::sleep(Duration::from_secs(secs));
    let now = procs(page_kb);
    let cpu1 = cpu_total();
    let mut snap = snapshot(&now, &lim);
    let app: std::collections::HashSet<u32> = app_pids(&now, &lim).into_iter().collect();
    for (pid, p) in &now {
        let d = p.ticks.saturating_sub(before.get(pid).filter(|q| q.0 == p.name).map_or(p.ticks, |q| q.1));
        let map = if app.contains(pid) { &mut snap.apps } else { &mut snap.system };
        if let Some(g) = map.get_mut(&p.name) {
            g.ticks += d;
        }
    }
    let ncpu = (cpu1.saturating_sub(cpu0)) as f64 / hz / secs as f64; // cœurs × intervalle
    let pct = |t: u64| if ncpu > 0.0 { t as f64 / hz / secs as f64 * 100.0 / ncpu } else { 0.0 };
    let sys_ticks: u64 = snap.system.values().map(|g| g.ticks).sum();
    let app_ticks: u64 = snap.apps.values().map(|g| g.ticks).sum();
    let over = snap.system_kb() > lim.system_mb * 1024;
    println!(
        "Mémoire utilisée {}: système {} (budget {}{}), travail {}{}",
        size(snap.used_kb),
        size(snap.system_kb()),
        size(lim.system_mb * 1024),
        if over { ", DÉPASSÉ" } else { "" },
        size(snap.apps_kb),
        if snap.swap_kb > 0 { format!(", swap {}", size(snap.swap_kb)) } else { String::new() }
    );
    let (kernel, zram) = hidden_kb();
    let procs_kb: u64 = snap.system.values().map(|g| g.kb).sum();
    println!(
        "  système = processus {}, noyau {}{}, non attribué (tmpfs, mémoire partagée, caches) {}",
        size(procs_kb),
        size(kernel),
        if zram > 0 { format!(", zram {}", size(zram)) } else { String::new() },
        size(snap.system_kb().saturating_sub(procs_kb + kernel + zram))
    );
    println!("CPU sur {secs} s (tous cœurs): système {}, travail {}", pct_fr(pct(sys_ticks)), pct_fr(pct(app_ticks)));
    println!("\nTravail: applications, agents, conteneurs, commandes des terminaux (hors budget):");
    for (name, g) in sorted(&snap.apps).into_iter().take(8) {
        println!("  {:<24} {:>8}  {:>7}", label(name, g), size(g.kb), pct_fr(pct(g.ticks)));
    }
    println!("\nSystème, plus gros résidents (PSS, RSS pour les processus d'autres utilisateurs):");
    for (name, g) in sorted(&snap.system).into_iter().take(12) {
        println!("  {:<24} {:>8}  {:>7}", label(name, g), size(g.kb), pct_fr(pct(g.ticks)));
    }
    let mut busy: Vec<_> = snap.system.iter().filter(|(_, g)| pct(g.ticks) >= 0.5).collect();
    busy.sort_by(|a, b| b.1.ticks.cmp(&a.1.ticks));
    if !busy.is_empty() {
        println!("\nSystème actif pendant la mesure (>= 0,5 %: à surveiller s'il ne se passe rien):");
        for (name, g) in busy {
            println!("  {:<24} {:>7}", label(name, g), pct_fr(pct(g.ticks)));
        }
    }
    for v in violations(&snap, &lim).into_iter().skip(usize::from(over)) {
        println!("Plafond: {v}");
    }
}

fn state_file(name: &str) -> PathBuf {
    let dir = env::var("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|_| home().join(".local/state")).join("budget");
    let _ = fs::create_dir_all(&dir);
    dir.join(name)
}

fn save(name: &str, page_kb: u64) {
    let snap = snapshot(&procs(page_kb), &limits());
    let mut out = format!("#system\t{}\n", snap.system_kb());
    for (n, g) in sorted(&snap.system) {
        out += &format!("{n}\t{}\n", g.kb);
    }
    let path = state_file(name);
    if let Err(e) = fs::write(&path, out) {
        eprintln!("budget: écriture de {} impossible: {e}", path.display());
        process::exit(1);
    }
    println!("Référence « {name} » enregistrée: système {} ({})", size(snap.system_kb()), path.display());
}

fn diff(name: &str, page_kb: u64) {
    let Ok(text) = fs::read_to_string(state_file(name)) else {
        eprintln!("budget: pas de référence « {name} » (budget save {name})");
        process::exit(1);
    };
    let mut base: HashMap<String, u64> = HashMap::new();
    let mut base_sys = 0;
    for line in text.lines() {
        let Some((n, kb)) = line.split_once('\t') else { continue };
        let kb = kb.parse().unwrap_or(0);
        if n == "#system" { base_sys = kb } else { base.insert(n.to_string(), kb); }
    }
    let snap = snapshot(&procs(page_kb), &limits());
    println!("Système: {} → {} ({})", size(base_sys), size(snap.system_kb()), signed(snap.system_kb() as i64 - base_sys as i64));
    let mut rows: Vec<(String, i64, &str)> = Vec::new();
    for (n, g) in &snap.system {
        match base.get(n) {
            Some(&b) => rows.push((n.clone(), g.kb as i64 - b as i64, "")),
            None => rows.push((n.clone(), g.kb as i64, " (nouveau)")),
        }
    }
    for (n, &b) in &base {
        if !snap.system.contains_key(n) {
            rows.push((n.clone(), -(b as i64), " (disparu)"));
        }
    }
    rows.retain(|r| r.1.unsigned_abs() >= 1024);
    rows.sort_by(|a, b| b.1.abs().cmp(&a.1.abs()));
    for (n, d, tag) in rows.iter().take(20) {
        println!("  {n:<24} {:>10}{tag}", signed(*d));
    }
}

fn violations(snap: &Snapshot, lim: &Limits) -> Vec<String> {
    let mut v = Vec::new();
    if snap.system_kb() > lim.system_mb * 1024 {
        v.push(format!("système {} Mo > {} Mo", snap.system_kb() / 1024, lim.system_mb));
    }
    for (n, g) in sorted(&snap.system) {
        let max = lim.per.get(n.as_str()).copied().unwrap_or(lim.process_mb);
        if g.kb > max * 1024 {
            v.push(format!("{} {} Mo > {max} Mo", label(n, g), g.kb / 1024));
        }
    }
    v
}

fn check(notify: bool, page_kb: u64) {
    let v = violations(&snapshot(&procs(page_kb), &limits()), &limits());
    if v.is_empty() {
        println!("Budget respecté");
        return;
    }
    for line in &v {
        println!("{line}");
    }
    if notify {
        let _ = process::Command::new("notify-send").args(["-a", "budget", "Budget ressources dépassé", &v.join("\n")]).status();
        return;
    }
    process::exit(1);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    // SAFETY: SIGPIPE par défaut (sortie silencieuse dans un tuyau fermé, `budget | head`); sysconf sans effet de bord
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
    let (page_kb, hz) = unsafe { (libc::sysconf(libc::_SC_PAGESIZE) as u64 / 1024, libc::sysconf(libc::_SC_CLK_TCK) as f64) };
    let name = || args.get(2).cloned().unwrap_or_else(|| "reference".into());
    match args.get(1).map(String::as_str) {
        None => show(2, page_kb, hz),
        Some(s) if s.parse::<u64>().is_ok_and(|n| n > 0) => show(s.parse().unwrap_or(2), page_kb, hz),
        Some("save") => save(&name(), page_kb),
        Some("diff") => diff(&name(), page_kb),
        Some("check") => check(args.get(2).is_some_and(|a| a == "--notify"), page_kb),
        _ => {
            eprintln!("usage: budget [secondes] | save [nom] | diff [nom] | check [--notify]");
            process::exit(2);
        }
    }
}
