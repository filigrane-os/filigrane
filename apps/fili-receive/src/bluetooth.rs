// Bluetooth (OBEX Object Push): agent D-Bus de obexd (org.bluez.obex.Agent1). obexd, lancé sans -a, appelle
// AuthorizePush pour chaque fichier entrant: on demande par notification « Accepter / Refuser », puis on suit le
// transfert jusqu'à sa fin pour l'annoncer. obexd enregistre dans son dossier racine (voir fili-share receive).
use crate::{
    common::{announce, ask, journal, notify, summary},
    i18n::{tr, trf},
};
use std::{process::Command, thread, time::Duration};
use zbus::{
    blocking::{Connection, Proxy},
    interface,
    zvariant::{ObjectPath, OwnedObjectPath},
};

const ASK_MS: u32 = 30000;
const AGENT_PATH: &str = "/org/filigrane/receive/agent";

#[derive(zbus::DBusError, Debug)]
#[zbus(prefix = "org.bluez.obex.Error")]
enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
}

struct Agent {
    // Seconde connexion pour interroger obexd depuis une méthode (la première sert la réponse)
    query: Connection,
    dir: String,
    always: bool,
}

fn prop<T>(c: &Connection, path: &str, iface: &str, name: &str) -> Option<T>
where
    T: TryFrom<zbus::zvariant::OwnedValue>,
    T::Error: Into<zbus::Error>,
{
    Proxy::new(c, "org.bluez.obex", path.to_string(), iface.to_string()).ok()?.get_property::<T>(name).ok()
}

// Nom de l'appareil: « Alias » de bluetoothctl info; sinon l'adresse
fn device_name(mac: &str) -> String {
    let out = Command::new("bluetoothctl").args(["info", mac]).output().ok();
    let text = out.map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default();
    text.lines()
        .find_map(|l| l.trim().strip_prefix("Alias:").map(|a| a.trim().to_string()))
        .filter(|a| !a.is_empty())
        .unwrap_or_else(|| mac.to_string())
}

#[interface(name = "org.bluez.obex.Agent1")]
impl Agent {
    fn authorize_push(&self, transfer: ObjectPath<'_>) -> Result<String, AgentError> {
        let tpath = transfer.as_str().to_string();
        let name: String = prop(&self.query, &tpath, "org.bluez.obex.Transfer1", "Name").unwrap_or_else(|| "file".into());
        let size: u64 = prop(&self.query, &tpath, "org.bluez.obex.Transfer1", "Size").unwrap_or(0);
        let session: Option<OwnedObjectPath> = prop(&self.query, &tpath, "org.bluez.obex.Transfer1", "Session");
        let mac: String = session
            .and_then(|s| prop(&self.query, s.as_str(), "org.bluez.obex.Session1", "Destination"))
            .unwrap_or_default();
        let sender = if mac.is_empty() { "Bluetooth".to_string() } else { device_name(&mac) };
        let names = vec![name.clone()];
        if !self.always {
            let choice = ask(
                &trf("%1 wants to send you a file", &[&sender]),
                &summary(&names, size),
                &[("accept", tr("Accept").to_string()), ("reject", tr("Decline").to_string())],
                ASK_MS,
            );
            if choice.as_deref() != Some("accept") {
                return Err(AgentError::Rejected("Declined".into()));
            }
        }
        // Suivi jusqu'à la fin (hors de la méthode: obexd attend notre réponse pour démarrer)
        let (c, dir, ret) = (self.query.clone(), self.dir.clone(), name.clone());
        thread::spawn(move || {
            for _ in 0..3600 {
                thread::sleep(Duration::from_millis(500));
                let status: Option<String> = prop(&c, &tpath, "org.bluez.obex.Transfer1", "Status");
                match status.as_deref() {
                    Some("complete") => {
                        journal("bluetooth", &sender, &format!("{dir}/{name}"), size);
                        announce(&trf("Received from %1", &[&sender]), &summary(std::slice::from_ref(&name), size), &dir, &[format!("{dir}/{name}")]);
                        return;
                    }
                    Some("error") => {
                        notify(&format!("✕ {}", trf("Reception from %1 failed", &[&sender])), &name);
                        return;
                    }
                    // Objet disparu: transfert terminé ou annulé sans état final lisible
                    None => return,
                    _ => {}
                }
            }
        });
        Ok(ret)
    }

    fn cancel(&self) {}
}

pub fn run(dir: String, always: bool) {
    let query = match Connection::session() {
        Ok(c) => c,
        Err(e) => return eprintln!("fili-receive: D-Bus: {e}"),
    };
    let agent = Agent { query, dir, always };
    let conn = match zbus::blocking::connection::Builder::session().and_then(|b| b.serve_at(AGENT_PATH, agent)).and_then(|b| b.build()) {
        Ok(c) => c,
        Err(e) => return eprintln!("fili-receive: agent: {e}"),
    };
    // obexd vient d'être lancé: on attend qu'il prenne son nom
    let mut registered = false;
    for _ in 0..40 {
        let manager = Proxy::new(&conn, "org.bluez.obex", "/org/bluez/obex", "org.bluez.obex.AgentManager1");
        let path = ObjectPath::try_from(AGENT_PATH).unwrap();
        if manager.and_then(|m| m.call_method("RegisterAgent", &(path,))).is_ok() {
            registered = true;
            break;
        }
        thread::sleep(Duration::from_millis(500));
    }
    if !registered {
        return eprintln!("fili-receive: obexd n'a pas accepté l'agent");
    }
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}
