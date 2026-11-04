// fili-receive: réception de fichiers par LocalSend et Bluetooth, avec l'interface de la barre (notifications avec
// boutons). Lancé par `fili-share receive PROTO on` (qui démarre aussi localsendd ou obexd), arrêté par `off`.
//
//   fili-receive localsend         demandes entrantes et fin de transfert de localsendd
//   fili-receive bluetooth         agent OBEX de obexd: accepter/refuser chaque fichier
//   fili-receive settings          réglages résolus: dir=, confirm=ask|always, minutes=, name=
//   fili-receive received [N]      les N derniers fichiers reçus, en JSON (journal ~/.local/state/filigrane/received.tsv)
//
// Réglages facultatifs: ~/.config/filigrane/fili-file.toml (receive_dir, receive_confirm, receive_minutes, receive_name).
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
