//! Donne le focus à l'invite d'authentification polkit dès qu'elle apparaît.
//!
//! Port de `core/polkit_focus.py`. Hyprland empêche le vol de focus : une
//! fenêtre ouverte par un service en arrière-plan (l'agent polkit, lancé par
//! systemd) peut s'afficher sans recevoir le clavier — l'invite reste alors
//! invisible à l'usage, on tape dans la fenêtre du dessous.
//!
//! Ce veilleur écoute le flux d'événements de Hyprland (`socket2`) et, à chaque
//! `openwindow` d'une classe connue, force le focus dessus.

use crate::common::io::run_cmd;
use crate::common::paths::runtime_dir;
use serde_json::Value;
use std::io::{BufRead, BufReader};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

/// Classes dont l'ouverture doit amener le clavier. L'invite polkit d'abord ;
/// le gestionnaire de disques ensuite, car il est lancé depuis un popup de la
/// barre qui garde un attrapeur de clavier : sa fenêtre s'ouvre parfois derrière.
const MOTIFS: &[&str] = &["polkit", "policykit", "partitionmanager", "gparted"];

fn base_hypr() -> PathBuf {
    runtime_dir().join("hypr")
}

/// Les signatures à essayer, du socket le plus récent au plus ancien.
///
/// Trier les noms de dossier est un tri alphabétique : la « dernière » signature
/// n'était pas la vivante. Et garder `HYPRLAND_INSTANCE_SIGNATURE` en tête est un
/// piège quand le service est né d'une unité systemd qui la fige : après un
/// redémarrage de Hyprland, la variable désigne une session morte.
fn candidats() -> Vec<String> {
    let base = base_hypr();
    let mut entrees: Vec<(std::time::SystemTime, String)> = Vec::new();
    if let Ok(rd) = std::fs::read_dir(&base) {
        for e in rd.flatten() {
            let nom = e.file_name().to_string_lossy().to_string();
            let sock = base.join(&nom).join(".socket2.sock");
            if let Ok(md) = std::fs::metadata(&sock) {
                let mtime = md.modified().unwrap_or(std::time::UNIX_EPOCH);
                entrees.push((mtime, nom));
            }
        }
    }
    entrees.sort_by(|a, b| b.0.cmp(&a.0));
    let mut ordre: Vec<String> = Vec::new();
    for (_, nom) in entrees {
        if !ordre.contains(&nom) {
            ordre.push(nom);
        }
    }
    if let Ok(env) = std::env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        if !env.is_empty() && !ordre.contains(&env) {
            ordre.push(env);
        }
    }
    ordre
}

fn hyprctl(args: &[&str]) -> String {
    run_cmd("hyprctl", args)
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn fenetre_courante() -> Value {
    let brut = hyprctl(&["activewindow", "-j"]);
    serde_json::from_str(&brut).unwrap_or(Value::Null)
}

fn adresse_active() -> String {
    fenetre_courante()
        .get("address")
        .and_then(|a| a.as_str())
        .unwrap_or("")
        .to_lowercase()
}

/// Force le focus, puis vérifie que la fenêtre active a bien changé.
///
/// Hyprland 0.57 (config Lua) réévalue l'argument de `hyprctl dispatch` comme du
/// Lua : `dispatch focuswindow address:0x…` échoue au parsing (« ')' expected
/// near 'address' ») et ne faisait donc jamais rien. Le dispatcher passe par
/// `repl` ; la forme historique reste en repli. Trois essais : la fenêtre peut
/// n'être pas encore mappée.
fn concentrer(adresse: &str) -> bool {
    let cible = adresse.to_lowercase();
    let repl = format!("hl.dispatch(hl.dsp.focus({{ window = \"address:{adresse}\" }}))");
    let dispatch = format!("address:{adresse}");
    for _ in 0..3 {
        hyprctl(&["repl", &repl]);
        std::thread::sleep(Duration::from_millis(120));
        if adresse_active() == cible {
            return true;
        }
        hyprctl(&["dispatch", "focuswindow", &dispatch]);
        std::thread::sleep(Duration::from_millis(120));
        if adresse_active() == cible {
            return true;
        }
    }
    false
}

/// Lit le flux d'événements jusqu'à ce que Hyprland le referme.
fn suivre(flux: UnixStream) {
    let lecteur = BufReader::new(flux);
    for ligne in lecteur.lines() {
        let ligne = match ligne {
            Ok(l) => l,
            Err(_) => return,
        };
        // openwindow>>0x55d3…,1,classe,titre
        let reste = match ligne.strip_prefix("openwindow>>") {
            Some(r) => r,
            None => continue,
        };
        let morceaux: Vec<&str> = reste.split(',').collect();
        if morceaux.len() < 3 {
            continue;
        }
        let adresse = morceaux[0].trim().to_string();
        let classe = morceaux[2].trim().to_lowercase();
        if MOTIFS.iter().any(|m| classe.contains(m)) {
            concentrer(&adresse);
        }
    }
}

/// Suit la session Hyprland vivante.
///
/// La signature est relue à chaque tour : après un redémarrage du compositeur,
/// l'ancien socket est mort et le service tournait en boucle dessus sans jamais
/// accrocher la nouvelle session.
fn veiller() -> ! {
    loop {
        for sig in candidats() {
            let chemin = base_hypr().join(&sig).join(".socket2.sock");
            if !chemin.exists() {
                continue;
            }
            if let Ok(flux) = UnixStream::connect(&chemin) {
                suivre(flux);
            }
        }
        // Aucun socket joignable, ou le flux s'est fermé : on retente.
        std::thread::sleep(Duration::from_secs(1));
    }
}

pub fn run() -> i32 {
    if candidats().is_empty() {
        eprintln!("pas de session Hyprland");
        return 1;
    }
    veiller()
}
