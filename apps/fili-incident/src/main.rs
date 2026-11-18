// fili-incident: the problems the fili-* applications report. An application that meets a bug (a panic, a QML error, "Report a
// problem" of its Debug panel) writes an incident file; this command warns the user, hands the problem to Rob (fili-chat) and
// prepares the GitHub issue, or a +1 on the one that already exists. Nothing leaves the machine without the user's say:
// the issue is created or +1'd only with --yes, and without `gh` (or an account) the prefilled issue form opens in the browser.
//
// fili-incident list [--all]       incidents (the ones still to look at; --all adds ignored and reported)
// fili-incident show ID            one incident: what happened and the last lines of the log
// fili-incident notify ID          notification "<app> had a problem" with the buttons Ask Rob and Ignore (waits for the answer)
// fili-incident ask ID             asks Rob to look at it (fili-chat ask)
// fili-incident check ID           is it already on GitHub? (public search by signature, no account needed)
// fili-incident issue ID           the issue as it would be sent (title and body, with the private details removed)
// fili-incident submit ID [--yes]  existing issue: +1 (with gh and --yes), else opens it; none: creates it (gh and --yes), else
//                                  opens the prefilled form and copies the report
// fili-incident ignore ID | clear  forgets an incident | removes the ignored and reported ones older than 30 days
// An incident is ~/.local/state/filigrane/incidents/<id>.json, written by the application (apps/fili-music/src/logs.rs):
// {id, app, repo, version, kind, signature, message, when, state, log: [lines]}; state: new | notified | ignored | reported.
use std::{
    env, fs,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};

use serde_json::{Value, json};

fn home() -> String {
    env::var("HOME").unwrap_or_default()
}

fn dir() -> PathBuf {
    let state = env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()));
    PathBuf::from(state).join("filigrane/incidents")
}

fn path(id: &str) -> PathBuf {
    // The id comes from the command line: no folder in it
    dir().join(format!("{}.json", id.replace(['/', '\\'], "_")))
}

fn load(id: &str) -> Result<Value, String> {
    let text = fs::read_to_string(path(id)).map_err(|_| format!("no incident {id}"))?;
    serde_json::from_str(&text).map_err(|e| format!("incident {id}: {e}"))
}

fn save(id: &str, incident: &Value) -> Result<(), String> {
    fs::write(path(id), serde_json::to_string_pretty(incident).unwrap_or_default()).map_err(|e| e.to_string())
}

fn set_state(id: &str, state: &str, extra: Option<(&str, &str)>) {
    if let Ok(mut incident) = load(id) {
        incident["state"] = json!(state);
        if let Some((k, v)) = extra {
            incident[k] = json!(v);
        }
        let _ = save(id, &incident);
    }
}

fn text<'a>(incident: &'a Value, key: &str) -> &'a str {
    incident[key].as_str().unwrap_or("")
}

fn first_line(s: &str) -> &str {
    s.lines().next().unwrap_or("")
}

fn shorten(s: &str, n: usize) -> String {
    let s: String = s.chars().take(n + 1).collect();
    if s.chars().count() > n { format!("{}…", s.chars().take(n).collect::<String>()) } else { s }
}

// The incidents, the newest first
fn incidents() -> Vec<(String, Value)> {
    let mut out: Vec<(String, Value)> = fs::read_dir(dir())
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            let id = name.strip_suffix(".json")?.to_string();
            Some((id.clone(), load(&id).ok()?))
        })
        .collect();
    out.sort_by_key(|(_, i)| std::cmp::Reverse(i["when"].as_i64().unwrap_or(0)));
    out
}

// ---- What leaves the machine ---------------------------------------------------------------------------------------------

// The private details of a text removed: the home folder, the user name, e-mail addresses, IP and MAC addresses. A log
// carries paths (album and artist names included) and sometimes addresses; the issue is public.
fn redact(input: &str) -> String {
    let home = home();
    let user = env::var("USER").unwrap_or_default();
    let mut s = input.to_string();
    if home.len() > 1 {
        s = s.replace(&home, "~");
    }
    if user.len() > 2 {
        s = s.replace(&user, "<user>");
    }
    // Words that look like an address, one by one: simple and enough for a log line
    s.split_inclusive(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | '<' | '>' | '(' | ')' | ',' | ';'))
        .map(|chunk| {
            let word = chunk.trim_end_matches(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | '<' | '>' | '(' | ')' | ',' | ';'));
            let tail = &chunk[word.len()..];
            if is_email(word) {
                format!("<email>{tail}")
            } else if is_ipv4(word) || is_mac(word) {
                format!("<address>{tail}")
            } else {
                chunk.to_string()
            }
        })
        .collect()
}

fn is_email(w: &str) -> bool {
    match w.split_once('@') {
        Some((a, b)) => !a.is_empty() && b.contains('.') && !b.starts_with('.') && !b.ends_with('.') && !w.contains('/') && !w.contains(':'),
        None => false,
    }
}

fn is_ipv4(w: &str) -> bool {
    let w = w.split(':').next().unwrap_or(w);
    let parts: Vec<&str> = w.split('.').collect();
    parts.len() == 4 && parts.iter().all(|p| !p.is_empty() && p.len() <= 3 && p.chars().all(|c| c.is_ascii_digit()) && p.parse::<u16>().is_ok_and(|n| n <= 255))
}

fn is_mac(w: &str) -> bool {
    let parts: Vec<&str> = w.split(':').collect();
    parts.len() == 6 && parts.iter().all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()))
}

fn url_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

// Title and body of the issue; the signature in a comment lets the next report of the same problem find it
fn issue(incident: &Value) -> (String, String) {
    let title = format!("[{}] {}", text(incident, "app"), shorten(&redact(first_line(text(incident, "message"))), 90));
    let log: Vec<String> = incident["log"]
        .as_array()
        .map(|a| a.iter().filter_map(Value::as_str).map(redact).collect())
        .unwrap_or_default();
    let tail = log[log.len().saturating_sub(60)..].join("\n");
    let body = format!(
        "<!-- fili-incident:{sig} -->\n**{app}** {version}: {kind}\n\n```\n{message}\n```\n\n<details><summary>Last lines of the log</summary>\n\n```\n{tail}\n```\n\n</details>\n\nSystem: {system}\n\n_Reported with fili-incident; the private details (home folder, user name, e-mail and network addresses) were removed._\n",
        sig = text(incident, "signature"),
        app = text(incident, "app"),
        version = text(incident, "version"),
        kind = text(incident, "kind"),
        message = redact(text(incident, "message")),
        system = redact(text(incident, "system")),
    );
    (title, body)
}

// ---- GitHub ---------------------------------------------------------------------------------------------------------------

fn run(cmd: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(cmd).args(args).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).to_string())
}

fn have(cmd: &str) -> bool {
    Command::new("sh").args(["-c", &format!("command -v {cmd}")]).stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok_and(|s| s.success())
}

// gh installed and logged in
fn gh_ready() -> bool {
    have("gh") && run("gh", &["auth", "status"]).is_some()
}

// The issue that carries this signature, if any: the public search of GitHub needs no account (60 requests an hour)
fn find_existing(incident: &Value) -> Result<Option<Value>, String> {
    let (repo, sig) = (text(incident, "repo"), text(incident, "signature"));
    if repo.is_empty() || sig.is_empty() {
        return Err("this incident has no repository or signature".into());
    }
    let query = format!("repo:{repo} is:issue \"{sig}\" in:body");
    let url = format!("https://api.github.com/search/issues?per_page=1&q={}", url_encode(&query));
    let reply = run("curl", &["-sf", "-m", "15", "-H", "Accept: application/vnd.github+json", "-A", "fili-incident", &url])
        .ok_or("GitHub did not answer (no network, or too many searches: try again later)")?;
    Ok(parse_search(&reply))
}

fn parse_search(reply: &str) -> Option<Value> {
    let v: Value = serde_json::from_str(reply).ok()?;
    let item = v["items"].as_array()?.first()?;
    Some(json!({ "number": item["number"], "url": item["html_url"], "title": item["title"], "state": item["state"] }))
}

fn open(url: &str) {
    let _ = Command::new("xdg-open").arg(url).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
}

fn copy(text: &str) {
    if let Ok(mut c) = Command::new("wl-copy").stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
        if let Some(mut stdin) = c.stdin.take() {
            let _ = stdin.write_all(text.as_bytes());
        }
        let _ = c.wait();
    }
}

fn submit(id: &str, yes: bool) -> Result<(), String> {
    let incident = load(id)?;
    let repo = text(&incident, "repo").to_string();
    match find_existing(&incident)? {
        Some(found) => {
            let (number, url) = (found["number"].as_i64().unwrap_or(0), found["url"].as_str().unwrap_or("").to_string());
            println!("Already reported: #{number} {} ({url})", found["title"].as_str().unwrap_or(""));
            if yes && gh_ready() {
                let api = format!("repos/{repo}/issues/{number}/reactions");
                run("gh", &["api", "-X", "POST", &api, "-f", "content=+1"]).ok_or("gh could not add the +1")?;
                println!("+1 added.");
            } else {
                println!("Add a 👍 on the page (opened); {}.", if yes { "gh is missing or not logged in" } else { "nothing was sent: run again with --yes to +1 with gh" });
                open(&url);
            }
            set_state(id, "reported", Some(("issue", &url)));
        }
        None => {
            let (title, body) = issue(&incident);
            if yes && gh_ready() {
                let mut c = Command::new("gh")
                    .args(["issue", "create", "--repo", &repo, "--title", &title, "--body-file", "-"])
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .spawn()
                    .map_err(|e| e.to_string())?;
                c.stdin.take().ok_or("no stdin")?.write_all(body.as_bytes()).map_err(|e| e.to_string())?;
                let out = c.wait_with_output().map_err(|e| e.to_string())?;
                if !out.status.success() {
                    return Err("gh could not create the issue".into());
                }
                let url = String::from_utf8_lossy(&out.stdout).trim().to_string();
                println!("Issue created: {url}");
                set_state(id, "reported", Some(("issue", &url)));
            } else {
                // No gh or no account: the form of GitHub, filled in; the whole report is in the clipboard (a URL is short)
                copy(&body);
                let short = shorten(&body, 3500);
                let url = format!("https://github.com/{repo}/issues/new?title={}&body={}", url_encode(&title), url_encode(&short));
                open(&url);
                println!("Not reported yet: the issue form is open, filled in (the full report is in the clipboard).\nSend it there with a GitHub account.");
                set_state(id, "reported", Some(("issue", "form opened")));
            }
        }
    }
    Ok(())
}

// ---- Rob and the notification ---------------------------------------------------------------------------------------------

fn ask(id: &str) -> Result<(), String> {
    let incident = load(id)?;
    let prompt = format!(
        "Problem reported by {app}: {msg}. Incident {id}: read it with `fili-incident show {id}`, find the cause and follow the incident procedure of your instructions.",
        app = text(&incident, "app"),
        msg = shorten(first_line(text(&incident, "message")), 120),
    );
    Command::new("fili-chat").args(["ask", &prompt]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(|e| format!("fili-chat: {e}"))?;
    Ok(())
}

fn notify(id: &str) -> Result<(), String> {
    let incident = load(id)?;
    if text(&incident, "state") != "new" {
        return Ok(());
    }
    set_state(id, "notified", None);
    let title = format!("{} had a problem", text(&incident, "app"));
    let body = shorten(&redact(first_line(text(&incident, "message"))), 140);
    // --wait: notify-send stays until a button is pressed and prints its identifier
    let out = Command::new("notify-send")
        .args(["--wait", "-a", text(&incident, "app"), "-A", "ask=Ask Rob", "-A", "ignore=Ignore", &title, &body])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|e| format!("notify-send: {e}"))?;
    match String::from_utf8_lossy(&out.stdout).trim() {
        "ask" => ask(id),
        "ignore" => {
            set_state(id, "ignored", None);
            Ok(())
        }
        _ => Ok(()),
    }
}

fn clear() -> usize {
    let month = 30 * 24 * 3600;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    incidents()
        .into_iter()
        .filter(|(_, i)| matches!(text(i, "state"), "ignored" | "reported") && now - i["when"].as_i64().unwrap_or(now) > month)
        .filter(|(id, _)| fs::remove_file(path(id)).is_ok())
        .count()
}

fn show(id: &str) -> Result<(), String> {
    let i = load(id)?;
    println!("{id}\napp: {} {}\nkind: {}\nstate: {}\nrepository: {}\nsignature: {}\nsystem: {}\n", text(&i, "app"), text(&i, "version"), text(&i, "kind"), text(&i, "state"), text(&i, "repo"), text(&i, "signature"), text(&i, "system"));
    println!("{}\n\n--- last lines of the log ---", text(&i, "message"));
    for line in i["log"].as_array().into_iter().flatten().filter_map(Value::as_str) {
        println!("{line}");
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let yes = args.iter().any(|a| a == "--yes");
    let rest: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--yes").collect();
    let result = match rest.as_slice() {
        ["list", flags @ ..] => {
            let all = flags.contains(&"--all");
            for (id, i) in incidents().iter().filter(|(_, i)| all || matches!(text(i, "state"), "new" | "notified")) {
                println!("{id}\t{}\t{}\t{}", text(i, "state"), text(i, "kind"), shorten(first_line(text(i, "message")), 80));
            }
            Ok(())
        }
        ["show", id] => show(id),
        ["notify", id] => notify(id),
        ["ask", id] => ask(id),
        ["check", id] => load(id).and_then(|i| find_existing(&i)).map(|found| println!("{}", found.unwrap_or(Value::Null))),
        ["issue", id] => load(id).map(|i| {
            let (title, body) = issue(&i);
            println!("{title}\n\n{body}");
        }),
        ["submit", id] => submit(id, yes),
        ["ignore", id] => load(id).map(|_| set_state(id, "ignored", None)),
        ["clear"] => {
            println!("{} removed", clear());
            Ok(())
        }
        ["-V" | "--version"] => {
            println!("fili-incident {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        _ => Err("usage: fili-incident list [--all] | show ID | notify ID | ask ID | check ID | issue ID | submit ID [--yes] | ignore ID | clear".into()),
    };
    if let Err(e) = result {
        eprintln!("fili-incident: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_private_details_are_removed() {
        let home = home();
        let line = format!("open {home}/Music/Artist/a.flac for bob@example.org from 192.168.1.20:445 mac aa:bb:cc:dd:ee:ff ok");
        let out = redact(&line);
        assert!(!out.contains(&home) && out.contains("~/Music/Artist/a.flac"), "{out}");
        assert!(out.contains("<email>") && !out.contains("bob@"), "{out}");
        assert!(out.contains("<address>") && !out.contains("192.168") && !out.contains("aa:bb"), "{out}");
        // Not an address: a version, a time, a QML location
        assert_eq!(redact("v1.2.3 11:56:21.170 Main.qml:12:5"), "v1.2.3 11:56:21.170 Main.qml:12:5");
    }

    #[test]
    fn url_encoding_keeps_only_safe_characters() {
        assert_eq!(url_encode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9");
    }

    #[test]
    fn the_issue_carries_its_signature_and_hides_the_home_folder() {
        let incident = json!({
            "app": "fili-music", "repo": "o/r", "version": "0.1.0", "kind": "qml", "signature": "abc123",
            "message": format!("TypeError in {}/x.qml", home()), "system": "Void", "log": ["line one", "line two"]
        });
        let (title, body) = issue(&incident);
        assert!(title.starts_with("[fili-music] TypeError in "), "{title}");
        assert!(body.starts_with("<!-- fili-incident:abc123 -->"));
        assert!(body.contains("line two") && !body.contains(&home()));
    }

    #[test]
    fn a_github_search_reply_gives_the_issue() {
        let reply = r#"{"total_count":1,"items":[{"number":12,"html_url":"https://github.com/o/r/issues/12","title":"t","state":"open"}]}"#;
        let found = parse_search(reply).unwrap();
        assert_eq!((found["number"].as_i64(), found["state"].as_str()), (Some(12), Some("open")));
        assert!(parse_search(r#"{"total_count":0,"items":[]}"#).is_none());
        assert!(parse_search("not json").is_none());
    }

    #[test]
    fn an_incident_id_cannot_leave_the_folder() {
        assert!(path("../../etc/passwd").starts_with(dir()));
    }
}
