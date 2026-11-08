// Single process of the fili-shell (Quickshell), started by FiliShell.qml: `bar-stats PIPE`. A single thread that sleeps
// in poll() between two deadlines; reads /proc and /sys directly, without running top, ps, awk or udevadm. One line per
// update on the standard output:
// stat cpu|mem|temp|disk|net|remote|air|vpn|backup JSON   fili-bar modules (protocol of the custom Waybar modules)
// stat display JSON                                       brightness (at start and on `bar refresh 23`), screen and kbd fields in %
// ac 0|1                                                  charger plugged in or not (at start, then at every event)
// info TOPIC JSON                                         card requested on the standard input (`info network|power|monitor`, see info.rs)
// any line written in PIPE (fili-shell client, scripts), copied as is
// Kernel events (netlink uevent) for the charger, airplane mode and network interfaces: nothing is polled
// for them. Ends when the bar closes the output or dies.
mod i18n;
mod info;

use i18n::{num, tr, trf};
use info::js;

use std::{
    collections::HashMap,
    env,
    ffi::CStr,
    fs,
    io::{Read, Write},
    net::Ipv4Addr,
    os::{
        fd::AsRawFd,
        unix::fs::{MetadataExt, OpenOptionsExt},
    },
    process,
    time::{Duration, Instant},
};

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
        // name between the first "(" and the last ")" (it can contain spaces or parentheses)
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

// (busy, total) in ticks since boot; "id" alone counts as idle (like top)
fn cpu_times() -> (u64, u64) {
    let s = fs::read_to_string("/proc/stat").unwrap_or_default();
    let v: Vec<u64> = s.lines().next().unwrap_or("").split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
    let total: u64 = v.iter().take(8).sum();
    (total - v.get(3).copied().unwrap_or(0), total)
}

// Pango and JSON: remove what would break either, like the old script
fn clean(s: &str) -> String {
    s.chars().filter(|c| !matches!(c, '&' | '<' | '>' | '"' | '\\')).take(22).collect()
}

fn emit(line: &str) {
    let mut out = std::io::stdout().lock();
    if writeln!(out, "{line}").and_then(|_| out.flush()).is_err() {
        process::exit(0);
    }
}

fn stat(name: &str, json: &str) {
    emit(&format!("stat {name} {json}"));
}

// CPU and memory: a single walk of /proc for both (top 5 of each in the tooltip)
struct Usage {
    page_kb: u64,
    hz: f64,
    prev: HashMap<u32, Proc>,
    prev_cpu: (u64, u64),
    prev_t: Instant,
    // Biggest CPU consumers of the last interval (name, %), for the monitor card
    top: Vec<(String, f64)>,
}

impl Usage {
    fn new(page_kb: u64, hz: f64) -> Self {
        Usage { page_kb, hz, prev: procs(page_kb), prev_cpu: cpu_times(), prev_t: Instant::now(), top: Vec::new() }
    }

    // % of a CPU used by the process since the previous reading (same pid and same name)
    fn pct(&self, pid: u32, p: &Proc, secs: f64) -> f64 {
        let d = p.ticks.saturating_sub(self.prev.get(&pid).filter(|q| q.name == p.name).map_or(p.ticks, |q| q.ticks));
        d as f64 / self.hz / secs * 100.0
    }

    // Ranking only, writing nothing (bar-stats info monitor)
    fn top_only(&mut self) {
        let now = procs(self.page_kb);
        let secs = self.prev_t.elapsed().as_secs_f64();
        let mut top: Vec<(f64, &Proc)> = now.iter().map(|(pid, p)| (self.pct(*pid, p, secs), p)).collect();
        top.sort_by(|a, b| b.0.total_cmp(&a.0));
        self.top = top.iter().take(5).map(|(pct, p)| (clean(&p.name), *pct)).collect();
    }

    fn step(&mut self) {
        let now = procs(self.page_kb);
        let cur_cpu = cpu_times();
        let secs = self.prev_t.elapsed().as_secs_f64();
        self.prev_t = Instant::now();
        let (busy, total) = (cur_cpu.0 - self.prev_cpu.0, cur_cpu.1 - self.prev_cpu.1);
        let usage = (busy * 100).checked_div(total).unwrap_or(0);
        let mut top: Vec<(f64, &Proc)> = now.iter().map(|(pid, p)| (self.pct(*pid, p, secs), p)).collect();
        top.sort_by(|a, b| b.0.total_cmp(&a.0));
        self.top = top.iter().take(5).map(|(pct, p)| (clean(&p.name), *pct)).collect();
        let tip: Vec<String> = top
            .iter()
            .take(5)
            .map(|(pct, p)| {
                let mem = if p.rss_kb >= 1_048_576 {
                    format!("{:.1}G", p.rss_kb as f64 / 1_048_576.0)
                } else {
                    format!("{}M", p.rss_kb / 1024)
                };
                format!("{:<22} {pct:5.1}%  {mem}", clean(&p.name))
            })
            .collect();
        stat("cpu", &format!(r#"{{"text":"{usage}%","tooltip":"<tt>{}</tt>"}}"#, tip.join("\\n")));

        let info = fs::read_to_string("/proc/meminfo").unwrap_or_default();
        let field = |k: &str| {
            info.lines()
                .find(|l| l.starts_with(k))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(0)
        };
        let used = field("MemTotal:").saturating_sub(field("MemAvailable:")) as f64 / 1_048_576.0;
        // RSS summed by process name
        let mut by_name: HashMap<&str, u64> = HashMap::new();
        for p in now.values() {
            *by_name.entry(&p.name).or_default() += p.rss_kb;
        }
        let mut top: Vec<(&str, u64)> = by_name.into_iter().collect();
        top.sort_by_key(|a| std::cmp::Reverse(a.1));
        let tip: Vec<String> = top
            .iter()
            .take(5)
            .map(|(n, kb)| {
                let v = if *kb >= 1_048_576 {
                    trf("%1 GiB", &[&num(*kb as f64 / 1_048_576.0, 1)])
                } else {
                    trf("%1 MiB", &[&(kb / 1024)])
                };
                format!("{:<22} {v}", clean(n))
            })
            .collect();
        stat("mem", &format!(r#"{{"text":"{used:.1}G","tooltip":"<tt>{}</tt>"}}"#, tip.join("\\n")));

        self.prev = now;
        self.prev_cpu = cur_cpu;
    }
}

// CPU probe: hwmon coretemp (Intel), k10temp/zenpower (AMD) or cpu_thermal (ARM), then zone x86_pkg_temp; failing that the
// first available probe (hwmon*/temp1_input then thermal_zone*/temp); nothing in a VM. The first hwmon is often the NVMe.
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

// Shown only when the temperature is high: from 50 °C, hidden again below 45 °C (hysteresis)
struct Temp {
    path: Option<String>,
    shown: bool,
}

impl Temp {
    fn step(&mut self) {
        match self.path.as_ref().and_then(|p| fs::read_to_string(p).ok()).and_then(|s| s.trim().parse::<i64>().ok()) {
            Some(t) if (self.shown && t / 1000 >= 45) || t / 1000 >= 50 => {
                self.shown = true;
                let c = t / 1000;
                let class = if c >= 90 { "critical" } else { "" };
                stat(
                    "temp",
                    &format!(r#"{{"text":" {c}°","class":"{class}","tooltip":{}}}"#, js(&trf("CPU temperature: %1 °C", &[&c]))),
                );
            }
            _ => {
                self.shown = false;
                stat("temp", r#"{"text":""}"#);
            }
        }
    }
}

// Taille lisible en octets (base 1024, comme Waybar)
fn human(b: f64) -> String {
    let units = [tr("B"), tr("KiB"), tr("MiB"), tr("GiB"), tr("TiB")];
    let mut v = b;
    let mut i = 0;
    while v >= 1024.0 && i < units.len() - 1 {
        v /= 1024.0;
        i += 1;
    }
    format!("{} {}", num(v, if i == 0 { 0 } else { 1 }), units[i])
}

// Disk space of / (statvfs), like the Waybar disk module
// Shown only when almost full: from 90 %, hidden again below 88 % (hysteresis)
fn disk(shown: &mut bool) {
    // SAFETY: statvfs fills a zero-initialised structure, valid C path
    let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c"/".as_ptr(), &mut s) } != 0 {
        return;
    }
    let f = s.f_frsize as f64;
    let (total, free, avail) = (s.f_blocks as f64 * f, s.f_bfree as f64 * f, s.f_bavail as f64 * f);
    let used = total - free;
    let pct = (used * 100.0 / (used + avail)).round();
    *shown = (*shown && pct >= 88.0) || pct >= 90.0;
    if !*shown {
        stat("disk", r#"{"text":""}"#);
        return;
    }
    let class = if pct >= 95.0 { "critical" } else { "" };
    stat(
        "disk",
        &format!(
            r#"{{"text":" {pct}%","class":"{class}","tooltip":{}}}"#,
            js(&trf("%1 / %2 (%3 free)", &[&human(used), &human(total), &human(avail)]))
        ),
    );
}

// Interface of the default route (/proc/net/route, destination 0)
fn default_iface() -> Option<String> {
    fs::read_to_string("/proc/net/route").ok()?.lines().skip(1).find_map(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        (f.len() > 1 && f[1] == "00000000").then(|| f[0].to_string())
    })
}

// First IPv4 address of the interface and the length of its prefix (getifaddrs)
fn ipv4(iface: &str) -> Option<(Ipv4Addr, u32)> {
    let mut list: *mut libc::ifaddrs = std::ptr::null_mut();
    // SAFETY: list allocated by getifaddrs, walked read-only then freed by freeifaddrs
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
                let mask = if a.ifa_netmask.is_null() {
                    0
                } else {
                    (*(a.ifa_netmask as *const libc::sockaddr_in)).sin_addr.s_addr.count_ones()
                };
                found = Some((Ipv4Addr::from(u32::from_be(sin.sin_addr.s_addr)), mask));
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

// Network, like the Waybar network module: only writes when the state changes (rates refreshed every 30 s);
// SSID and frequency through `iw` only when the link changes (iwd exposes nothing in /sys)
#[derive(Default)]
struct Net {
    last_key: String,
    last_level: i64,
    ssid: String,
    freq: String,
    prev: Option<(String, u64, u64, Instant)>,
    rates: (f64, f64),
    since: Option<Instant>,
}

impl Net {
    fn step(&mut self) {
        let iface = default_iface();
        let ip = iface.as_deref().and_then(ipv4).map(|(a, _)| a);
        let key = format!("{iface:?} {ip:?}");
        let wifi = iface.as_deref().is_some_and(|i| fs::metadata(format!("/sys/class/net/{i}/wireless")).is_ok());
        let changed = key != self.last_key;
        // Wi-Fi link quality in % (/proc/net/wireless: out of 70) and icon step: 0 to 3
        let q = if wifi {
            iface
                .as_deref()
                .and_then(|i| {
                    fs::read_to_string("/proc/net/wireless")
                        .ok()?
                        .lines()
                        .find(|l| l.trim_start().starts_with(&format!("{i}:")))
                        .and_then(|l| l.split_whitespace().nth(2).and_then(|v| v.trim_end_matches('.').parse::<f64>().ok()))
                        .map(|v| (v * 100.0 / 70.0).round() as i64)
                })
                .unwrap_or(0)
        } else {
            0
        };
        let level = if !wifi {
            -1
        } else if q >= 70 {
            3
        } else if q >= 45 {
            2
        } else if q >= 20 {
            1
        } else {
            0
        };
        if changed && wifi {
            let out = process::Command::new("iw").args(["dev", iface.as_deref().unwrap_or(""), "link"]).output();
            let text = out.map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default();
            let field =
                |k: &str| text.lines().find_map(|l| l.trim().strip_prefix(k).map(|v| v.trim().to_string())).unwrap_or_default();
            self.ssid = field("SSID:");
            self.freq = field("freq:").split('.').next().unwrap_or("").to_string();
        }
        if !(changed || level != self.last_level || self.since.is_none_or(|t| t.elapsed() >= Duration::from_secs(30))) {
            return;
        }
        if let Some(i) = iface.as_deref() {
            let (rx, tx, now) = (counter(i, "rx_bytes"), counter(i, "tx_bytes"), Instant::now());
            if let Some((pi, prx, ptx, pt)) = &self.prev {
                let secs = now.duration_since(*pt).as_secs_f64();
                if pi == i && secs > 0.0 {
                    self.rates = (rx.saturating_sub(*prx) as f64 / secs, tx.saturating_sub(*ptx) as f64 / secs);
                }
            }
            self.prev = Some((i.to_string(), rx, tx, now));
        }
        self.since = Some(Instant::now());
        self.last_key = key;
        self.last_level = level;
        let ipt = ip.map(|a| a.to_string()).unwrap_or_else(|| tr("no IPv4").into());
        let bw = format!("↓ {}/s  ↑ {}/s", human(self.rates.0), human(self.rates.1));
        let line = match iface.as_deref() {
            None => format!(
                r#"{{"text":{},"class":"disconnected","tooltip":{}}}"#,
                js(&format!(" {}", tr("offline"))),
                js(tr("No connection (click: Wi-Fi)"))
            ),
            Some(_) if wifi => {
                // Icon by quality (codes md-wifi_strength_1..4, Fili Icons font): solid stroke = good signal
                let glyph = ['\u{F091F}', '\u{F0922}', '\u{F0925}', '\u{F0928}'][level as usize];
                let ghz = self.freq.parse::<f64>().map(|f| num(f / 1000.0, 1)).unwrap_or_default();
                let full = clean(&self.ssid);
                let name = if full.chars().count() > 16 {
                    format!("{}…", full.chars().take(15).collect::<String>())
                } else {
                    full.clone()
                };
                format!(r#"{{"text":"{glyph} {name}","class":"wifi","tooltip":"{full} ({q}%)  {ghz} GHz\n{ipt}\n{bw}"}}"#)
            }
            Some(i) => format!(r#"{{"text":" {i}","class":"ethernet","tooltip":"{i}: {ipt}\n{bw}"}}"#),
        };
        stat("net", &line);
    }
}

// Established incoming SSH sessions (local port 22), like `ss -Htn state established '( sport = :22 )'`
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

// Airplane mode: a software-blocked radio (`rfkill list` "Soft blocked: yes")
fn airplane() -> bool {
    fs::read_dir("/sys/class/rfkill")
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| fs::read_to_string(e.path().join("soft")).is_ok_and(|s| s.trim() == "1"))
}

// VPN interfaces that are up (IFF_UP)
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

// flock lock held (backup running), read from /proc/locks: testing it with flock could make watch-backup fail
fn locked(path: &str) -> bool {
    let Ok(ino) = fs::metadata(path).map(|m| m.ino().to_string()) else { return false };
    fs::read_to_string("/proc/locks")
        .unwrap_or_default()
        .lines()
        .any(|l| l.split_whitespace().any(|t| t.matches(':').count() == 2 && t.rsplit(':').next() == Some(ino.as_str())))
}

// Charger plugged in: mains power supply (type Mains) online; None without a known mains supply (VM, desktop)
fn ac_online() -> Option<bool> {
    let mut found = None;
    for e in fs::read_dir("/sys/class/power_supply").into_iter().flatten().flatten() {
        if fs::read_to_string(e.path().join("type")).is_ok_and(|t| t.trim() == "Mains") {
            let on = fs::read_to_string(e.path().join("online")).is_ok_and(|s| s.trim() == "1");
            found = Some(found.unwrap_or(false) || on);
        }
    }
    found
}

// Date locale d'un instant (strftime)
fn local_time(t: i64, fmt: &CStr) -> String {
    // SAFETY: zero-initialised local structures, buffer of the given size, valid C format
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let mut buf = [0u8; 64];
        let n = libc::strftime(buf.as_mut_ptr().cast(), buf.len(), fmt.as_ptr(), &tm);
        String::from_utf8_lossy(&buf[..n]).into_owned()
    }
}

// restic backup (watch-backup): hidden without configuration (distribution without a NAS), active during the backup
// (lock held), failed if the last attempt failed, idle otherwise; the drawer (BarState.qml) hides it at rest
fn backup(dir: &str, env: &str) -> String {
    if fs::metadata(env).is_err() {
        return r#"{"text":""}"#.into();
    }
    let g = '\u{f0ee}';
    if locked(&format!("{dir}/backup.lock")) {
        return format!(r#"{{"text":"{g}","class":"active","tooltip":{}}}"#, js(tr("NAS backup running...")));
    }
    let last = fs::metadata(format!("{dir}/backup.stamp")).map_or(tr("never").into(), |m| local_time(m.mtime(), c"%d/%m %H:%M"));
    if fs::read_to_string(format!("{dir}/backup.status")).is_ok_and(|s| s.trim() == "fail") {
        let tip = trf("Last backup failed (last success: %1). Click: retry", &[&last]);
        format!(r#"{{"text":"{g}","class":"failed","tooltip":{}}}"#, js(&tip))
    } else {
        let tip = trf("NAS backup (last: %1). Click: back up now", &[&last]);
        format!(r#"{{"text":"{g}","class":"idle","tooltip":{}}}"#, js(&tip))
    }
}

// Slow-changing indicators, without polling by the bar: read from /proc and /sys without running anything, written only
// when they change (stat): incoming SSH, airplane mode, VPN, backup.
struct Watch {
    seen: HashMap<&'static str, String>,
    state: String,
    restic: String,
    batwatch: String,
    low: bool,
    bat_seen: String,
    tick: u64,
    ac: Option<bool>,
}

const BAT: &str = "/sys/class/power_supply/BAT0";

impl Watch {
    fn new() -> Self {
        let home = env::var("HOME").unwrap_or_default();
        Watch {
            seen: HashMap::new(),
            state: format!("{home}/.local/state/watch"),
            restic: format!("{home}/.config/restic/env"),
            batwatch: format!("{home}/.local/bin/bar-status"),
            low: false,
            bat_seen: String::new(),
            tick: 0,
            ac: None,
        }
    }

    fn put(&mut self, name: &'static str, json: String) {
        if self.seen.get(name) != Some(&json) {
            stat(name, &json);
            self.seen.insert(name, json);
        }
    }

    // Modules written directly: at start, at every round, and right after a click or watch-backup (bar
    // refresh) or a kernel event (rfkill, network interface)
    fn indicators(&mut self, ssh: bool) {
        let j = backup(&self.state, &self.restic);
        self.put("backup", j);
        if ssh || !self.seen.contains_key("remote") {
            let n = ssh_in();
            let j = if n > 0 {
                format!(r#"{{"text":"","class":"active","tooltip":{}}}"#, js(&trf("%1 incoming SSH session(s)", &[&n])))
            } else {
                r#"{"text":""}"#.into()
            };
            self.put("remote", j);
        }
        let j = if airplane() {
            format!(r#"{{"text":"","class":"active","tooltip":{}}}"#, js(tr("Airplane mode (click: turn off)")))
        } else {
            r#"{"text":""}"#.into()
        };
        self.put("air", j);
        let v = vpn();
        let j = if v.is_empty() {
            r#"{"text":""}"#.into()
        } else {
            format!(r#"{{"text":" VPN","class":"active","tooltip":{}}}"#, js(&trf("VPN on: %1", &[&v])))
        };
        self.put("vpn", j);
    }

    fn ac(&mut self) {
        let a = ac_online();
        if a.is_some() && a != self.ac {
            emit(if a == Some(true) { "ac 1" } else { "ac 0" });
        }
        self.ac = a;
    }

    fn step(&mut self) {
        self.tick += 1;
        // /proc/net/tcp* costs more (sockets walked): one round out of three
        self.indicators(self.tick.is_multiple_of(3));
        // Low battery: alert and shutdown stay in `bar-status batwatch`, started only when the state
        // moves below 10 % on battery, and once on return (charger plugged in) to re-arm the alert.
        // status queries the hardware (~1 ms, against a few µs for capacity): read only below 10 %
        let cap = fs::read_to_string(format!("{BAT}/capacity")).ok().and_then(|s| s.trim().parse::<u8>().ok()).unwrap_or(100);
        let status =
            if cap <= 10 || self.low { fs::read_to_string(format!("{BAT}/status")).unwrap_or_default() } else { String::new() };
        let now_low = status.trim() == "Discharging" && cap <= 10;
        let fp = format!("{} {cap}", status.trim());
        if (now_low || self.low) && fp != self.bat_seen {
            let _ = process::Command::new(&self.batwatch).arg("batwatch").stdout(process::Stdio::null()).status();
        }
        (self.low, self.bat_seen) = (now_low, fp);
    }
}

// Kernel events (like `udevadm monitor --kernel`): netlink socket, group 1
fn uevent_socket() -> Option<i32> {
    // SAFETY: system calls on a zero-initialised structure; the descriptor stays open until the end
    unsafe {
        let fd = libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_DGRAM | libc::SOCK_CLOEXEC | libc::SOCK_NONBLOCK,
            libc::NETLINK_KOBJECT_UEVENT,
        );
        if fd < 0 {
            return None;
        }
        let mut sa: libc::sockaddr_nl = std::mem::zeroed();
        sa.nl_family = libc::AF_NETLINK as u16;
        sa.nl_groups = 1;
        if libc::bind(fd, &sa as *const _ as *const libc::sockaddr, size_of::<libc::sockaddr_nl>() as u32) != 0 {
            libc::close(fd);
            return None;
        }
        Some(fd)
    }
}

// Subsystems of the pending events (SUBSYSTEM=...), without blocking
fn uevents(fd: i32) -> Vec<String> {
    let mut out = Vec::new();
    let mut buf = [0u8; 8192];
    loop {
        // SAFETY: read into a local buffer of the given size
        let n = unsafe { libc::recv(fd, buf.as_mut_ptr().cast(), buf.len(), 0) };
        if n <= 0 {
            return out;
        }
        for kv in buf[..n as usize].split(|&b| b == 0) {
            if let Some(s) = kv.strip_prefix(b"SUBSYSTEM=") {
                out.push(String::from_utf8_lossy(s).into_owned());
            }
        }
    }
}

// Complete lines read from a non-blocking descriptor (the rest is kept in buf); None at the end of the stream
fn lines(fd: i32, buf: &mut Vec<u8>) -> Option<Vec<String>> {
    let mut chunk = [0u8; 4096];
    loop {
        // SAFETY: read into a local buffer of the given size
        let n = unsafe { libc::read(fd, chunk.as_mut_ptr().cast(), chunk.len()) };
        if n == 0 {
            return None;
        }
        if n < 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n as usize]);
    }
    let mut out = Vec::new();
    while let Some(i) = buf.iter().position(|&b| b == b'\n') {
        let l: Vec<u8> = buf.drain(..=i).collect();
        out.push(String::from_utf8_lossy(&l[..i]).into_owned());
    }
    Some(out)
}

fn nonblock(fd: i32) {
    // SAFETY: flags of a descriptor opened by this process
    unsafe { libc::fcntl(fd, libc::F_SETFL, libc::fcntl(fd, libc::F_GETFL) | libc::O_NONBLOCK) };
}

// `bar-stats info TOPIC`: a card on the standard output (network with the ping, monitor over 1 s)
fn info_cli(topic: &str, page_kb: u64, hz: f64) {
    let json = match topic {
        "network" => {
            let gw = default_iface().and_then(|i| info::gateway(&i));
            let ping = gw
                .and_then(|g| info::ping_cmd(g).output().ok())
                .map(|o| info::ping_time(&String::from_utf8_lossy(&o.stdout)))
                .unwrap_or_default();
            info::network(&ping)
        }
        "power" => info::power(),
        "display" => info::display(),
        "monitor" => {
            let mut usage = Usage::new(page_kb, hz);
            std::thread::sleep(Duration::from_secs(1));
            // Sortie de step (stat cpu/mem) inutile ici: seul le classement compte
            usage.top_only();
            info::monitor(&usage)
        }
        _ => {
            eprintln!("usage: bar-stats info network|power|display|monitor");
            process::exit(2);
        }
    };
    println!("{json}");
}

fn main() {
    // SAFETY: sysconf n'a pas d'effet de bord
    let (page_kb, hz) = unsafe { (libc::sysconf(libc::_SC_PAGESIZE) as u64 / 1024, libc::sysconf(libc::_SC_CLK_TCK) as f64) };
    let args: Vec<String> = env::args().collect();
    if args.get(1).map(String::as_str) == Some("info") {
        return info_cli(args.get(2).map_or("", String::as_str), page_kb, hz);
    }
    let Some(fifo) = args.get(1) else {
        eprintln!("usage: bar-stats FIFO   (started by the fili-shell, see FiliShell.qml) | bar-stats info TOPIC");
        process::exit(2);
    };
    // Started by `exec` from the bar: stops with it
    // SAFETY: prctl only touches the attributes of this process
    unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) };
    // Read-write: never an end of file when a client closes the pipe (like `cat 0<>pipe`)
    let pipe = fs::OpenOptions::new().read(true).write(true).custom_flags(libc::O_NONBLOCK).open(fifo).unwrap_or_else(|e| {
        eprintln!("bar-stats: {fifo}: {e}");
        process::exit(1);
    });
    let uev = uevent_socket();
    // Requests of the bar on the standard input; ignored once closed
    let mut stdin_fd = 0;
    nonblock(stdin_fd);

    let mut usage = Usage::new(page_kb, hz);
    let mut temp = Temp { path: temp_path(), shown: false };
    let mut disk_shown = false;
    let mut net = Net::default();
    let mut watch = Watch::new();
    watch.ac();
    watch.indicators(true);
    stat("display", &info::display());
    // Gateway ping in progress for the network card (sent a second time with its result)
    let mut ping: Option<process::Child> = None;

    // Deadlines: CPU and memory 10 s (quick first display), temperature 15 s, disk 5 min, network and indicators 5 s
    let t0 = Instant::now();
    let mut next = [t0 + Duration::from_millis(500), t0, t0, t0, t0 + Duration::from_secs(5)];
    let every = [10, 15, 300, 5, 5].map(Duration::from_secs);
    let (mut pipe_buf, mut stdin_buf) = (Vec::new(), Vec::new());
    loop {
        let now = Instant::now();
        for (i, due) in next.iter_mut().enumerate() {
            if *due > now {
                continue;
            }
            match i {
                0 => usage.step(),
                1 => temp.step(),
                2 => disk(&mut disk_shown),
                3 => net.step(),
                _ => watch.step(),
            }
            *due = now + every[i];
        }
        let wait = next.iter().min().map_or(Duration::ZERO, |d| d.saturating_duration_since(Instant::now()));

        let ping_fd = ping.as_ref().and_then(|c| c.stdout.as_ref()).map_or(-1, |o| o.as_raw_fd());
        let mut fds = [
            libc::pollfd { fd: pipe.as_raw_fd(), events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: uev.unwrap_or(-1), events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: stdin_fd, events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: ping_fd, events: libc::POLLIN, revents: 0 },
        ];
        // SAFETY: local array of valid pollfd (negative fd ignored by poll)
        let r =
            unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, wait.as_millis().min(i32::MAX as u128) as i32 + 1) };
        if r <= 0 {
            continue;
        }
        if fds[0].revents & libc::POLLIN != 0 {
            for l in lines(pipe.as_raw_fd(), &mut pipe_buf).unwrap_or_default() {
                // Click on airplane, SSH or VPN (bar-toggle...), start or end of a backup (watch-backup): state re-read at once
                if l.starts_with("bar refresh") {
                    if l.split_whitespace().any(|n| matches!(n, "14" | "18" | "21" | "22")) {
                        watch.indicators(true);
                    }
                    if l.split_whitespace().any(|n| n == "23") {
                        stat("display", &info::display());
                    }
                }
                emit(&l);
            }
        }
        if let Some(fd) = uev.filter(|_| fds[1].revents & libc::POLLIN != 0) {
            let subs = uevents(fd);
            if subs.iter().any(|s| s == "power_supply") {
                watch.ac();
            }
            if subs.iter().any(|s| s == "rfkill" || s == "net") {
                watch.indicators(false);
            }
        }
        if fds[2].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            match lines(stdin_fd, &mut stdin_buf) {
                None => stdin_fd = -1,
                Some(reqs) => {
                    for topic in reqs.iter().filter_map(|l| l.strip_prefix("info ")) {
                        let json = match topic.trim() {
                            "network" => {
                                // Card at once, then again with the gateway ping
                                if ping.is_none() {
                                    let gw = default_iface().and_then(|i| info::gateway(&i));
                                    ping = gw.and_then(|g| {
                                        info::ping_cmd(g)
                                            .stdout(process::Stdio::piped())
                                            .stderr(process::Stdio::null())
                                            .spawn()
                                            .ok()
                                    });
                                    if let Some(o) = ping.as_ref().and_then(|c| c.stdout.as_ref()) {
                                        nonblock(o.as_raw_fd());
                                    }
                                }
                                info::network("")
                            }
                            "power" => info::power(),
                            "monitor" => info::monitor(&usage),
                            _ => continue,
                        };
                        emit(&format!("info {} {json}", topic.trim()));
                    }
                }
            }
        }
        if fds[3].revents & (libc::POLLIN | libc::POLLHUP) != 0
            && let Some(mut child) = ping.take()
        {
            let mut out = String::new();
            if let Some(o) = child.stdout.as_mut() {
                let _ = o.read_to_string(&mut out);
            }
            let _ = child.wait();
            emit(&format!("info network {}", info::network(&info::ping_time(&out))));
        }
    }
}
