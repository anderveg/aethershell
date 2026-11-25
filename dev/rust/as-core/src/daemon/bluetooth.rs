use crate::common::contrat::sortir;
use crate::common::io::run_cmd_stdout;
use regex::Regex;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::sync::OnceLock;
use std::thread;
use std::time::{Duration, Instant};

fn ctl(args: &[&str]) -> String {
    run_cmd_stdout("bluetoothctl", args).unwrap_or_default()
}

fn re_powered() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?m)^\s*Powered:\s*yes").unwrap())
}

fn parse_device_line(line: &str) -> Option<(String, String)> {
    static RE: OnceLock<Regex> = OnceLock::new();
    let re = RE.get_or_init(|| Regex::new(r"^Device\s+([0-9A-Fa-f:]{17})\s*(.*)$").unwrap());
    let cap = re.captures(line.trim())?;
    let mac = cap[1].to_ascii_uppercase();
    let nom = cap[2].trim();
    Some((mac.clone(), if nom.is_empty() { mac } else { nom.to_string() }))
}

fn devices(sub: &str) -> Vec<(String, String)> {
    ctl(&["devices", sub])
        .lines()
        .filter_map(parse_device_line)
        .collect()
}

fn powered_now() -> bool {
    re_powered().is_match(&ctl(&["show"]))
}

fn devices_all() -> Vec<(String, String)> {
    ctl(&["devices"])
        .lines()
        .filter_map(parse_device_line)
        .collect()
}

fn nearby_devices(connus: &HashSet<String>) -> Vec<Value> {
    let mut list: Vec<(bool, String, String)> = devices_all()
        .into_iter()
        .filter(|(mac, _)| !connus.contains(mac))
        .map(|(mac, nom)| {
            // Les périphériques avec un vrai nom avant ceux identifiés par leur MAC.
            let sans_nom = nom.eq_ignore_ascii_case(&mac)
                || nom.replace('-', ":").eq_ignore_ascii_case(&mac);
            (sans_nom, nom, mac)
        })
        .collect();
    list.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.to_lowercase().cmp(&b.1.to_lowercase())));
    list.into_iter()
        .map(|(_, nom, mac)| json!({ "mac": mac, "nom": nom }))
        .collect()
}

pub fn etat() -> Value {
    etat_avec_scan(false)
}

fn etat_avec_scan(inclure_portee: bool) -> Value {
    let show = ctl(&["show"]);
    if show.is_empty() && run_cmd_stdout("which", &["bluetoothctl"]).is_none() {
        return json!({ "present": false });
    }
    if !show.contains("Controller") {
        return json!({ "present": false, "erreur": "aucun adaptateur" });
    }
    static RE_CTRL: OnceLock<Regex> = OnceLock::new();
    let allume = re_powered().is_match(&show);
    let adresse = RE_CTRL
        .get_or_init(|| Regex::new(r"Controller\s+([0-9A-Fa-f:]{17})").unwrap())
        .captures(&show)
        .map(|c| c[1].to_ascii_uppercase())
        .unwrap_or_default();

    let connectes_list = devices("Connected");
    let mut connectes_map: BTreeMap<String, String> = BTreeMap::new();
    for (m, n) in &connectes_list {
        connectes_map.insert(m.clone(), n.clone());
    }

    let mut appaires = Vec::new();
    let mut connus = HashSet::new();
    for (mac, nom) in devices("Paired") {
        connus.insert(mac.clone());
        let conn = connectes_map.contains_key(&mac);
        appaires.push(json!({ "mac": mac, "nom": nom, "connecte": conn }));
    }
    for (mac, nom) in &connectes_map {
        if !connus.contains(mac) {
            connus.insert(mac.clone());
            appaires.push(json!({ "mac": mac, "nom": nom, "connecte": true }));
        }
    }

    let connectes: Vec<Value> = connectes_map
        .into_iter()
        .map(|(m, n)| json!({ "mac": m, "nom": n }))
        .collect();

    let mut out = json!({
        "present": true,
        "allume": allume,
        "adresse": adresse,
        "connectes": connectes,
        "appaires": appaires,
    });
    if inclure_portee {
        let a_portee = if allume { nearby_devices(&connus) } else { Vec::new() };
        if let Value::Object(ref mut m) = out {
            m.insert("a_portee".into(), Value::Array(a_portee));
        }
    }
    out
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.trim()).unwrap_or("etat");
    match action {
        "etat" => sortir(&etat()),
        "basculer" | "activer" | "desactiver" => {
            let e = etat();
            if !e.get("present").and_then(|v| v.as_bool()).unwrap_or(false) {
                return sortir(&e);
            }
            let cur = e.get("allume").and_then(|v| v.as_bool()).unwrap_or(false);
            let cible = match action {
                "basculer" => !cur,
                "activer" => true,
                _ => false,
            };
            let _ = ctl(&["power", if cible { "on" } else { "off" }]);
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline {
                if powered_now() == cible {
                    break;
                }
                thread::sleep(Duration::from_millis(100));
            }
            sortir(&etat())
        }
        "connecter" | "deconnecter" if args.len() > 1 => {
            let mac = args[1].trim();
            let sub = if action == "connecter" { "connect" } else { "disconnect" };
            let _ = ctl(&[sub, mac]);
            sortir(&etat())
        }
        "scanner" | "scan" => {
            let secs = args
                .get(1)
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(5)
                .clamp(2, 15);
            let secs_s = secs.to_string();
            let _ = ctl(&["--timeout", &secs_s, "scan", "on"]);
            sortir(&etat_avec_scan(true))
        }
        "appairer" if args.len() > 1 => {
            let mac = args[1].trim();
            let _ = ctl(&["pair", mac]);
            let _ = ctl(&["trust", mac]);
            let _ = ctl(&["connect", mac]);
            sortir(&etat_avec_scan(true))
        }
        _ => {
            sortir(&json!({ "erreur": "action inconnue" }));
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bluetoothctl_device_lines() {
        assert_eq!(
            parse_device_line("Device aa:bb:cc:dd:ee:ff Casque Audio"),
            Some(("AA:BB:CC:DD:EE:FF".to_string(), "Casque Audio".to_string()))
        );
        assert_eq!(
            parse_device_line("Device 11:22:33:44:55:66"),
            Some(("11:22:33:44:55:66".to_string(), "11:22:33:44:55:66".to_string()))
        );
        assert_eq!(parse_device_line("Controller 00:11:22:33:44:55"), None);
    }
}
