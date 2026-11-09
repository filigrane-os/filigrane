// Removable volumes for fili-automount: lsblk to list them, udisksctl (udisks2, started on demand by D-Bus) to mount.
// A trimmed copy of the volume code of Casier (filigrane-os/fili-file), which no longer lives in this repository.
use crate::i18n::trf;
use std::process::Command;

#[derive(Debug, PartialEq)]
pub struct Volume {
    pub dev: String,
    pub name: String,
    pub mount: Option<String>,
}

// "KEY="value" KEY2="..."" (lsblk -P); special characters of a value are written \xNN
fn pairs(line: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut rest = line.trim();
    while let Some((key, after)) = rest.split_once("=\"") {
        let mut value = String::new();
        let mut chars = after.char_indices();
        let mut end = after.len();
        while let Some((i, c)) = chars.next() {
            match c {
                '"' => {
                    end = i + 1;
                    break;
                }
                '\\' if after[i + 1..].starts_with('x') && after.len() >= i + 4 => {
                    if let Ok(b) = u8::from_str_radix(&after[i + 2..i + 4], 16) {
                        value.push(b as char);
                        chars.nth(2);
                    }
                }
                c => value.push(c),
            }
        }
        out.push((key.trim().to_string(), value));
        rest = after[end..].trim_start();
    }
    out
}

pub fn parse(text: &str) -> Vec<Volume> {
    let mut out = Vec::new();
    for line in text.lines() {
        let f: std::collections::HashMap<String, String> = pairs(line).into_iter().collect();
        let get = |k: &str| f.get(k).map(String::as_str).unwrap_or("");
        let fstype = get("FSTYPE");
        // Removable: USB (HOTPLUG), card reader (RM), SD card of the built-in reader (mmcblk), never the system
        let mount_here = get("MOUNTPOINT");
        let removable = get("HOTPLUG") == "1" || get("RM") == "1" || get("PATH").starts_with("/dev/mmcblk");
        let system =
            mount_here == "/" || mount_here.starts_with("/boot") || mount_here.starts_with("/efi") || mount_here == "[SWAP]";
        if !removable
            || system
            || fstype.is_empty()
            || ["swap", "crypto_LUKS", "LVM2_member", "linux_raid_member"].contains(&fstype)
            || !["part", "disk", "rom"].contains(&get("TYPE"))
        {
            continue;
        }
        let name = if get("LABEL").is_empty() { trf("%1 volume", &[&get("SIZE")]) } else { get("LABEL").to_string() };
        let mount = Some(get("MOUNTPOINT")).filter(|m| !m.is_empty()).map(String::from);
        out.push(Volume { dev: get("PATH").to_string(), name, mount });
    }
    out
}

pub fn list() -> Vec<Volume> {
    match Command::new("lsblk").args(["-P", "-o", "PATH,LABEL,SIZE,HOTPLUG,RM,MOUNTPOINT,TYPE,FSTYPE"]).output() {
        Ok(o) => parse(&String::from_utf8_lossy(&o.stdout)),
        Err(_) => Vec::new(),
    }
}

fn udisks(action: &str, dev: &str) -> Result<String, String> {
    let o = Command::new("udisksctl").args([action, "-b", dev, "--no-user-interaction"]).output().map_err(|e| e.to_string())?;
    if o.status.success() {
        Ok(String::from_utf8_lossy(&o.stdout).into_owned())
    } else {
        // "Error mounting /dev/sdb1: GDBus.Error:...: message"
        let err = String::from_utf8_lossy(&o.stderr);
        Err(err.trim().rsplit(": ").next().unwrap_or("").to_string())
    }
}

// Mounts dev and returns its mount point

// Mounts dev and returns its mount point
pub fn mount(dev: &str) -> Result<String, String> {
    let out = udisks("mount", dev)?;
    out.split_once(" at ").map(|(_, p)| p.trim().trim_end_matches('.').to_string()).ok_or_else(|| out.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_lsblk() {
        let text = "PATH=\"/dev/sdb1\" LABEL=\"KEY\" SIZE=\"8G\" HOTPLUG=\"1\" RM=\"1\" MOUNTPOINT=\"\" TYPE=\"part\" FSTYPE=\"vfat\"\n\
                    PATH=\"/dev/sda2\" LABEL=\"\" SIZE=\"200G\" HOTPLUG=\"0\" RM=\"0\" MOUNTPOINT=\"/\" TYPE=\"part\" FSTYPE=\"ext4\"\n";
        assert_eq!(parse(text), vec![Volume { dev: "/dev/sdb1".into(), name: "KEY".into(), mount: None }]);
    }
}
