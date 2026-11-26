use crate::common::contrat::sortir;
use crate::common::io::{run_cmd, run_cmd_stdout};
use crate::common::paths::{hostname, runtime_dir};
use glob::glob;
use regex::Regex;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

// Le helper est installé par `dev/charge-limit/install.sh` sous le nom
// `aether-charge-limit`. L'ancien nom est gardé en second : une machine qui a
// reçu une version antérieure du helper continue de fonctionner.
const HELPERS_CHARGE: &[&str] = &[
    "/usr/local/bin/aether-charge-limit",
    "/usr/local/bin/aethershell-charge-limit",
];
const HELPER_LENOVO_CONS: &str = "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode";
const SEUIL_CIBLE_PCT: i64 = 80;

fn has_battery_device() -> bool {
    glob("/sys/class/power_supply/BAT*")
        .map(|mut g| g.next().is_some())
        .unwrap_or(false)
}

fn has_backlight_device() -> bool {
    glob("/sys/class/backlight/*")
        .map(|mut g| g.next().is_some())
        .unwrap_or(false)
}

fn read_trim(p: &Path) -> Option<String> {
    fs::read_to_string(p).ok().map(|s| s.trim().to_string())
}

fn get_charge_limit_info() -> (bool, i64, &'static str) {
    if let Ok(paths) = glob("/sys/class/power_supply/BAT*/charge_control_end_threshold") {
        for p in paths.flatten() {
            if let Some(val) = read_trim(&p).and_then(|s| s.parse::<i64>().ok()) {
                return (val <= 80, val, "threshold");
            }
        }
    }
    if let Some(val) = read_trim(Path::new(HELPER_LENOVO_CONS)) {
        let on = val == "1";
        return (on, if on { 60 } else { 100 }, "conservation");
    }
    (false, SEUIL_CIBLE_PCT, "")
}

/// Signal (%) du réseau wifi actif, demandé à NetworkManager.
///
/// Repli indispensable quand `/proc/net/wireless` est absent : les noyaux
/// Fedora récents (et les pilotes mac80211 modernes) ne l'exposent plus, ce qui
/// renvoyait `0` et faisait afficher l'icône « déconnecté » alors que la
/// session était bien liée au réseau.
fn read_nmcli_wifi_signal() -> Option<i64> {
    let out = run_cmd_stdout("nmcli", &["-t", "-f", "IN-USE,SIGNAL", "dev", "wifi"])?;
    for line in out.lines() {
        let Some((drapeau, sig)) = line.split_once(':') else { continue };
        // IN-USE vaut « * » pour le réseau courant, quel que soit la locale.
        if drapeau.trim() == "*" {
            return sig.trim().parse::<i64>().ok().map(|s| s.clamp(0, 100));
        }
    }
    None
}

fn read_proc_wifi_signal(iface: &str) -> i64 {
    let Ok(txt) = fs::read_to_string("/proc/net/wireless") else {
        return 0;
    };
    for line in txt.lines().skip(2) {
        let Some((dev, rest)) = line.split_once(':') else { continue };
        if dev.trim() == iface {
            let cols: Vec<&str> = rest.split_whitespace().collect();
            if let Some(lvl_s) = cols.get(2) {
                if let Ok(dbm) = lvl_s.trim_end_matches('.').parse::<f64>() {
                    if dbm < 0.0 {
                        return (2.0 * (dbm + 100.0)).round().clamp(0.0, 100.0) as i64;
                    }
                    return dbm.round().clamp(0.0, 100.0) as i64;
                }
            }
        }
    }
    0
}

fn split_nmcli_escaped(line: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut cur = String::new();
    let mut esc = false;
    for ch in line.chars() {
        if esc {
            cur.push(ch);
            esc = false;
        } else if ch == '\\' {
            esc = true;
        } else if ch == ':' {
            parts.push(std::mem::take(&mut cur));
        } else {
            cur.push(ch);
        }
    }
    parts.push(cur);
    parts
}

fn active_wifi_ssid(iface: &str, fallback: &str) -> String {
    if let Some(out) = run_cmd_stdout("iwgetid", &["-r", iface]) {
        if !out.is_empty() {
            return out;
        }
    }
    fallback.to_string()
}

fn get_volume_info() -> (i64, bool) {
    use std::sync::OnceLock;
    static RE_WP: OnceLock<Regex> = OnceLock::new();
    static RE_AM: OnceLock<Regex> = OnceLock::new();
    if let Some(wp) = run_cmd_stdout("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"]) {
        let muted = wp.contains("[MUTED]");
        let lvl = RE_WP
            .get_or_init(|| Regex::new(r"([0-9]+(?:\.[0-9]+)?)").unwrap())
            .captures(&wp)
            .and_then(|c| c[1].parse::<f64>().ok())
            .map(|v| (v * 100.0).round() as i64)
            .unwrap_or(0);
        return (lvl, muted);
    }
    if let Some(am) = run_cmd_stdout("amixer", &["sget", "Master"]) {
        let muted = am.contains("[off]");
        let lvl = RE_AM
            .get_or_init(|| Regex::new(r"\[(\d+)%\]").unwrap())
            .captures(&am)
            .and_then(|c| c[1].parse::<i64>().ok())
            .unwrap_or(0);
        return (lvl, muted);
    }
    (0, false)
}

fn get_brightness_pct() -> i64 {
    if let Ok(mut dirs) = glob("/sys/class/backlight/*") {
        if let Some(Ok(dir)) = dirs.next() {
            if let (Some(cur), Some(max)) = (
                read_trim(&dir.join("brightness")).and_then(|s| s.parse::<f64>().ok()),
                read_trim(&dir.join("max_brightness")).and_then(|s| s.parse::<f64>().ok()),
            ) {
                if max > 0.0 {
                    return ((cur / max) * 100.0).round() as i64;
                }
            }
        }
    }
    if let (Some(cur), Some(max)) = (
        run_cmd_stdout("brightnessctl", &["g"]).and_then(|s| s.parse::<f64>().ok()),
        run_cmd_stdout("brightnessctl", &["m"]).and_then(|s| s.parse::<f64>().ok()),
    ) {
        if max > 0.0 {
            return ((cur / max) * 100.0).round() as i64;
        }
    }
    100
}

fn get_system_info() -> Value {
    let host = hostname();
    let has_bat = has_battery_device();
    let has_bri = has_backlight_device();

    let mut bat_cap = 0i64;
    let mut bat_status = "NoBattery".to_string();
    let mut limit_80 = false;
    let mut limit_pct = SEUIL_CIBLE_PCT;
    let mut limit_kind = "";
    if has_bat {
        if let Ok(mut dirs) = glob("/sys/class/power_supply/BAT*") {
            if let Some(Ok(bat_dir)) = dirs.next() {
                bat_cap = read_trim(&bat_dir.join("capacity"))
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
                bat_status = read_trim(&bat_dir.join("status"))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| "Unknown".to_string());
            }
        }
        (limit_80, limit_pct, limit_kind) = get_charge_limit_info();
    }

    let (vol_pct, muted) = get_volume_info();
    let bright_pct = if has_bri { get_brightness_pct() } else { 100 };

    let mut wifi_connected = false;
    let mut wifi_ssid = String::new();
    let mut wifi_signal = 0i64;
    let mut net_type = "none".to_string();
    let mut eth_fallback: Option<String> = None;

    if let Some(dev_status) = run_cmd_stdout("nmcli", &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]) {
        for line in dev_status.lines() {
            let parts = split_nmcli_escaped(line);
            if parts.len() >= 4 && (parts[2] == "connected" || parts[2].starts_with("connected ")) {
                let (dev_name, dev_type, conn_name) = (&parts[0], &parts[1], &parts[3]);
                if dev_type == "wifi" {
                    wifi_connected = true;
                    wifi_ssid = active_wifi_ssid(dev_name, conn_name);
                    wifi_signal = read_proc_wifi_signal(dev_name);
                    if wifi_signal <= 0 {
                        // /proc/net/wireless absent (noyau Fedora) : on demande
                        // la force du signal à NetworkManager. Reste à 0 si nmcli
                        // ne répond pas — l'icône affiche alors « wifi » simple.
                        wifi_signal = read_nmcli_wifi_signal().unwrap_or(0);
                    }
                    net_type = "wifi".to_string();
                    break;
                } else if dev_type == "ethernet" && eth_fallback.is_none() {
                    eth_fallback = Some(if conn_name.is_empty() { "Ethernet".to_string() } else { conn_name.clone() });
                }
            }
        }
    }
    if !wifi_connected && eth_fallback.is_none() {
        // Repli noyau (/sys/class/net) si NetworkManager ne gère pas l'interface
        // (ex. systemd-networkd, dhcpcd ou VM sans profil NM).
        if let Ok(entries) = fs::read_dir("/sys/class/net") {
            for ent in entries.flatten() {
                let name = ent.file_name().to_string_lossy().to_string();
                if name == "lo"
                    || name.starts_with("tun")
                    || name.starts_with("tap")
                    || name.starts_with("wg")
                    || name.starts_with("veth")
                    || name.starts_with("docker")
                    || name.starts_with("br-")
                    || name.starts_with("virbr")
                {
                    continue;
                }
                let p = ent.path();
                if !p.join("wireless").exists()
                    && read_trim(&p.join("operstate")).as_deref() == Some("up")
                {
                    eth_fallback = Some("Ethernet".to_string());
                    break;
                }
            }
        }
    }
    if !wifi_connected {
        if let Some(eth) = eth_fallback {
            wifi_connected = true;
            wifi_ssid = eth;
            wifi_signal = 100;
            net_type = "ethernet".to_string();
        }
    }

    let tablet_mode = if has_bat {
        read_trim(&runtime_dir().join("aethershell_tablet_mode"))
            .map(|s| s == "tablet")
            .unwrap_or(false)
    } else {
        false
    };

    json!({
        "hostname": host,
        "has_battery": has_bat,
        "has_backlight": has_bri,
        "battery": {
            "present": has_bat,
            "level": bat_cap,
            "percent": bat_cap,
            "status": bat_status,
            "charging": bat_status == "Charging",
            "limit_80": limit_80,
            "limit_pct": limit_pct,
            "limit_kind": limit_kind,
        },
        "volume": {
            "level": vol_pct,
            "percent": vol_pct,
            "muted": muted,
        },
        "brightness": bright_pct,
        "wifi": {
            "connected": wifi_connected,
            "ssid": wifi_ssid,
            "signal": wifi_signal,
            "type": net_type,
        },
        "tablet_mode": tablet_mode,
    })
}

fn known_wifi_profiles() -> HashSet<String> {
    let mut set = HashSet::new();
    if let Some(out) = run_cmd_stdout("nmcli", &["-t", "-f", "NAME,TYPE", "connection", "show"]) {
        for line in out.lines() {
            let parts = split_nmcli_escaped(line);
            if parts.len() >= 2 && parts[1] == "802-11-wireless" && !parts[0].is_empty() {
                set.insert(parts[0].clone());
            }
        }
    }
    set
}

fn get_wifi_networks(rescan: bool) -> Value {
    if rescan {
        let _ = run_cmd("nmcli", &["dev", "wifi", "rescan"]);
    }
    let known = known_wifi_profiles();
    let Some(out) = run_cmd_stdout(
        "nmcli",
        &["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"],
    ) else {
        return json!([]);
    };
    let mut list: Vec<(bool, i64, Value)> = Vec::new();
    let mut seen = HashSet::new();
    for line in out.lines() {
        let parts = split_nmcli_escaped(line);
        if parts.len() < 4 { continue; }
        let in_use = parts[0].trim() == "*";
        let ssid = parts[1].trim().to_string();
        if ssid.is_empty() || !seen.insert(ssid.clone()) { continue; }
        let signal = parts[2].trim().parse::<i64>().unwrap_or(0);
        let sec = parts[3].trim().to_string();
        let is_known = in_use || known.contains(&ssid);
        list.push((
            in_use,
            signal,
            json!({
                "ssid": ssid,
                "signal": signal,
                "security": sec,
                "in_use": in_use,
                "known": is_known,
            }),
        ));
    }
    list.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| b.1.cmp(&a.1)));
    Value::Array(list.into_iter().map(|(_, _, v)| v).collect())
}

fn connect_wifi(ssid: &str, password: &str) -> Value {
    let res = if !password.is_empty() {
        run_cmd("nmcli", &["dev", "wifi", "connect", ssid, "password", password])
    } else {
        let up = run_cmd("nmcli", &["connection", "up", ssid]);
        if up.as_ref().map(|o| o.status.success()).unwrap_or(false) {
            up
        } else {
            run_cmd("nmcli", &["dev", "wifi", "connect", ssid])
        }
    };
    let lang = crate::common::i18n::active_lang();
    match res {
        Some(o) if o.status.success() => json!({
            "success": true,
            "ssid": ssid,
            "message": crate::common::i18n::tr(lang, "Connecté", "Connected", "Conectado", "Verbunden")
        }),
        Some(o) => {
            let msg = String::from_utf8_lossy(&o.stderr).trim().to_string();
            let err = if msg.is_empty() {
                String::from_utf8_lossy(&o.stdout).trim().to_string()
            } else {
                msg
            };
            let fallback = crate::common::i18n::tr(lang, "Échec de connexion", "Connection failed", "Error de conexión", "Verbindung fehlgeschlagen");
            json!({ "success": false, "ssid": ssid, "message": if err.is_empty() { fallback.to_string() } else { err } })
        }
        None => json!({
            "success": false,
            "ssid": ssid,
            "message": crate::common::i18n::tr(lang, "nmcli introuvable", "nmcli not found", "nmcli no encontrado", "nmcli nicht gefunden")
        }),
    }
}

/// Premier helper réellement exécutable parmi les chemins proposés.
fn choisir_helper<'a>(chemins: &[&'a str]) -> Option<&'a str> {
    chemins.iter().copied().find(|p| {
        Path::new(p)
            .metadata()
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    })
}

fn set_battery_limit(limit: i64) -> Value {
    let target_pct = if limit <= 80 { 80 } else { 100 };
    let target_str = target_pct.to_string();

    // Chaque cause d'échec a son message : « impossible d'appliquer le seuil »
    // ne disait pas si le helper manquait, si pkexec refusait, ou si la machine
    // n'expose aucun mécanisme — et c'est ce message que l'applet affiche.
    let Some(helper) = choisir_helper(HELPERS_CHARGE) else {
        return json!({
            "ok": false,
            "error": format!(
                "Helper de limite de charge absent ({}). À installer une fois : sudo bash dev/charge-limit/install.sh",
                HELPERS_CHARGE[0]
            ),
        });
    };

    let Some(o) = run_cmd("pkexec", &[helper, &target_str]) else {
        return json!({
            "ok": false,
            "error": "pkexec introuvable : impossible d'élever les droits pour écrire le seuil de charge",
        });
    };

    if o.status.success() {
        let (l80, lpct, lkind) = get_charge_limit_info();
        return json!({ "ok": true, "limit_80": l80, "limit_pct": lpct, "limit_kind": lkind });
    }

    let code = o
        .status
        .code()
        .map(|c| c.to_string())
        .unwrap_or_else(|| "signal".to_string());
    let mut detail = String::from_utf8_lossy(&o.stderr).trim().to_string();
    if detail.is_empty() {
        detail = String::from_utf8_lossy(&o.stdout).trim().to_string();
    }
    if detail.is_empty() {
        detail = "aucun détail renvoyé".to_string();
    }
    json!({
        "ok": false,
        "error": format!("Le helper de limite de charge a échoué (code {code}) : {detail}"),
    })
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("info");
    match action {
        "info" => sortir(&get_system_info()),
        "wifi" => {
            let rescan = !args.iter().any(|a| a == "--no-rescan");
            sortir(&get_wifi_networks(rescan))
        }
        "wifi_connect" if args.len() > 1 => {
            let ssid = &args[1];
            let pwd = args.get(2).map(|s| s.as_str()).unwrap_or("");
            sortir(&connect_wifi(ssid, pwd))
        }
        "limit" => {
            let lim = args.get(1).and_then(|s| s.parse::<i64>().ok()).unwrap_or(80);
            let res = set_battery_limit(lim);
            let ok = res.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
            sortir(&res);
            if ok { 0 } else { 1 }
        }
        "volume" if args.len() > 1 => {
            let pct = args[1].parse::<i64>().unwrap_or(50).clamp(0, 150);
            let arg = format!("{pct}%");
            let _ = run_cmd("wpctl", &["set-volume", "@DEFAULT_AUDIO_SINK@", &arg]);
            0
        }
        "mute" => {
            let _ = run_cmd("wpctl", &["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
            0
        }
        "brightness" if args.len() > 1 => {
            let pct = args[1].parse::<i64>().unwrap_or(50).clamp(1, 100);
            let arg = format!("{pct}%");
            let _ = run_cmd("brightnessctl", &["set", &arg]);
            0
        }
        _ => {
            eprintln!("system-service: action inconnue: {action}");
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn choisit_le_premier_helper_executable() {
        let base = std::env::temp_dir().join(format!("as_helper_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        let inerte = base.join("non_executable");
        let script = base.join("executable");
        fs::write(&inerte, b"x").unwrap();
        let mut f = fs::File::create(&script).unwrap();
        writeln!(f, "#!/bin/sh").unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();

        let a = inerte.to_string_lossy().to_string();
        let b = script.to_string_lossy().to_string();
        let trouve = choisir_helper(&[a.as_str(), b.as_str()]);
        assert_eq!(trouve, Some(b.as_str()), "le non-exécutable doit être ignoré");
        assert_eq!(choisir_helper(&[a.as_str()]), None);
        let _ = fs::remove_dir_all(&base);
    }
}
