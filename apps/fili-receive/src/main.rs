// fili-receive: file reception through LocalSend and Bluetooth, with the interface of the bar (notifications with
// buttons). Started by `fili-share receive PROTO on` (which also starts localsendd or obexd), stopped by `off`.
// fili-receive localsend         incoming requests and end of transfer of localsendd
// fili-receive bluetooth         OBEX agent of obexd: accept/decline each file
// fili-receive settings          resolved settings: dir=, confirm=ask|always, minutes=, name=
// fili-receive received [N]      the last N received files, as JSON (journal ~/.local/state/filigrane/received.tsv)
// Optional settings: ~/.config/filigrane/fili-file.toml (receive_dir, receive_confirm, receive_minutes, receive_name).
mod bluetooth;
mod common;
#[allow(dead_code)]
#[path = "../../bar-stats/src/i18n.rs"]
mod i18n;
mod json;
mod localsend;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let s = common::settings();
    match args.get(1).map(String::as_str) {
        Some("localsend") => localsend::run(s.dir, s.always),
        Some("bluetooth") => bluetooth::run(s.dir, s.always),
        Some("settings") => {
            println!(
                "dir={}\nconfirm={}\nminutes={}\nname={}",
                s.dir,
                if s.always { "always" } else { "ask" },
                s.minutes,
                s.name
            );
        }
        Some("received") => {
            let n = args.get(2).and_then(|n| n.parse().ok()).unwrap_or(20);
            println!("{}", common::received_json(n));
        }
        _ => {
            eprintln!("usage: fili-receive localsend | bluetooth | settings | received [N]");
            std::process::exit(2);
        }
    }
}
