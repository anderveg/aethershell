//! Vérifie que le dépôt ne dépend d'aucun utilisateur ni d'aucune machine.
//!
//! Port de `core/neutralite.py` : mêmes motifs, mêmes messages, mêmes codes de
//! retour. Le programme lit **les fichiers suivis** (`git ls-files`) et signale
//! un chemin personnel en dur (`/home/<nom>`), l'identifiant de la personne qui
//! lance la vérification et le nom d'hôte de la machine — la règle est
//! structurelle, elle ne nomme personne dans le dépôt.
//!
//! `install.sh` l'appelle en préflight : rien ne doit fuir du poste de
//! développement vers la machine de quelqu'un d'autre.

use crate::common::io::run_cmd;
use crate::common::paths::hostname;
use regex::Regex;
use std::path::{Path, PathBuf};

/// Noms de dossier personnel acceptés : des espaces réservés de documentation.
const RESERVES: &[&str] = &[
    "utilisateur",
    "<utilisateur>",
    "user",
    "x",
    "nom",
    "username",
    "you",
    "toi",
    "votre-nom",
    "$user",
    "$home",
];

/// Fichiers où le nom de la personne est légitime : l'attribution de licence.
const ATTRIBUTION: &[&str] = &["LICENSE", "COPYING"];

/// Noms d'hôte trop banals pour être cherchés (« portable », « archlinux »…).
const HOTES_GENERIQUES: &[&str] = &[
    "localhost",
    "portable",
    "laptop",
    "desktop",
    "pc",
    "machine",
    "ordinateur",
    "archlinux",
    "fedora",
    "local",
    "home",
    "host",
];

/// Dérogation explicite portée par une ligne : `neutralite:ok — <raison>`.
const PRAGMA: &str = "neutralite:ok";

const SAUTE: &str =
    r"(?i)\.(png|jpe?g|webp|gif|ico|ttf|otf|woff2?|mp4|webm|pdf|zip|gz|xz|so|pyc)$";

struct Motif {
    nom: String,
    re: Regex,
    remede: &'static str,
    est_chemin: bool,
}

fn utilisateur_courant() -> String {
    for var in ["LOGNAME", "USER", "LNAME", "USERNAME"] {
        if let Ok(v) = std::env::var(var) {
            if !v.trim().is_empty() {
                return v;
            }
        }
    }
    unsafe {
        let uid = libc::geteuid();
        let pw = libc::getpwuid(uid);
        if pw.is_null() {
            return String::new();
        }
        let nom = (*pw).pw_name;
        if nom.is_null() {
            return String::new();
        }
        std::ffi::CStr::from_ptr(nom)
            .to_string_lossy()
            .into_owned()
    }
}

fn racine_depot() -> PathBuf {
    let sortie = run_cmd("git", &["rev-parse", "--show-toplevel"])
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    if sortie.is_empty() {
        PathBuf::from(".")
    } else {
        PathBuf::from(sortie)
    }
}

/// Fichiers suivis, un par entrée (`git ls-files -z`).
fn fichiers_suivis(racine: &Path) -> Vec<PathBuf> {
    let saute = Regex::new(SAUTE).expect("motif SAUTE");
    let racine_s = racine.to_string_lossy().to_string();
    let sortie = match run_cmd("git", &["-C", &racine_s, "ls-files", "-z"]) {
        Some(o) => o,
        None => return Vec::new(),
    };
    let mut out = Vec::new();
    for brut in sortie.stdout.split(|b| *b == 0) {
        if brut.is_empty() {
            continue;
        }
        let nom = String::from_utf8_lossy(brut).to_string();
        if saute.is_match(&nom) {
            continue;
        }
        out.push(racine.join(nom));
    }
    out
}

fn echappe(s: &str) -> String {
    regex::escape(s)
}

fn motifs(utilisateur: &str, hotes: &[String]) -> Vec<Motif> {
    let mut m = Vec::new();
    m.push(Motif {
        nom: "chemin personnel en dur".to_string(),
        re: Regex::new(r"/(?:home|Users)/([A-Za-z0-9._-]+)").expect("motif chemin"),
        remede: "utiliser $HOME / Path.home() / Quickshell.env(\"HOME\")",
        est_chemin: true,
    });
    if !utilisateur.is_empty() && !RESERVES.contains(&utilisateur) {
        if let Ok(re) = Regex::new(&format!(r"(?i)\b{}\b", echappe(utilisateur))) {
            m.push(Motif {
                nom: format!("nom d'utilisateur « {utilisateur} »"),
                re,
                remede: "aucune référence à la personne qui développe",
                est_chemin: false,
            });
        }
    }
    let mut tries: Vec<&String> = hotes.iter().collect();
    tries.sort();
    for hote in tries {
        if hote.is_empty() || hote.chars().count() <= 2 {
            continue;
        }
        if HOTES_GENERIQUES.contains(&hote.to_lowercase().as_str()) {
            continue;
        }
        if let Ok(re) = Regex::new(&format!(r"(?i)\b{}\b", echappe(hote))) {
            m.push(Motif {
                nom: format!("nom d'hôte « {hote} »"),
                re,
                remede: "aucune référence à la machine qui a servi au développement",
                est_chemin: false,
            });
        }
    }
    m
}

struct Trouve {
    chemin: String,
    numero: usize,
    nom: String,
    extrait: String,
    remede: &'static str,
}

pub fn run(args: &[String]) -> i32 {
    let racine = racine_depot();
    let mut utilisateur = utilisateur_courant();
    let hote_complet = hostname();
    let premier = hote_complet.split('.').next().unwrap_or("").to_string();
    let mut hotes: Vec<String> = vec![hote_complet.clone(), premier];

    let liste_seule = args.iter().any(|a| a == "--liste");
    for argument in args {
        if let Some(v) = argument.strip_prefix("--utilisateur=") {
            utilisateur = v.to_string();
        } else if let Some(v) = argument.strip_prefix("--hote=") {
            hotes = vec![v.to_string()];
        }
    }
    hotes.sort();
    hotes.dedup();

    let regles = motifs(&utilisateur, &hotes);
    let mut trouves: Vec<Trouve> = Vec::new();

    for chemin in fichiers_suivis(&racine) {
        let texte = match std::fs::read(&chemin) {
            Ok(b) => match String::from_utf8(b) {
                Ok(t) => t,
                Err(_) => continue,
            },
            Err(_) => continue,
        };
        let relatif = chemin
            .strip_prefix(&racine)
            .unwrap_or(&chemin)
            .to_string_lossy()
            .to_string();
        let nom_fichier = chemin
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        // Le programme lui-même cite les motifs : on l'épargne.
        if relatif.ends_with("neutralite.py") || relatif.ends_with("neutralite.rs") {
            continue;
        }
        if ATTRIBUTION.contains(&nom_fichier.as_str()) {
            continue;
        }

        for (numero, ligne) in texte.lines().enumerate() {
            if ligne.contains(PRAGMA) {
                continue;
            }
            for regle in &regles {
                let m = match regle.re.find(ligne) {
                    Some(m) => m,
                    None => continue,
                };
                if regle.est_chemin {
                    let capture = regle
                        .re
                        .captures(ligne)
                        .and_then(|c| c.get(1))
                        .map(|c| c.as_str().to_lowercase())
                        .unwrap_or_default();
                    if RESERVES.contains(&capture.as_str()) {
                        continue;
                    }
                }
                let complet = m.as_str();
                let extrait: String = complet.chars().take(40).collect();
                trouves.push(Trouve {
                    chemin: relatif.clone(),
                    numero: numero + 1,
                    nom: regle.nom.clone(),
                    extrait,
                    remede: regle.remede,
                });
            }
        }
    }

    if liste_seule {
        for t in &trouves {
            println!("{}:{}: {} — {}", t.chemin, t.numero, t.nom, t.extrait);
        }
        return 0;
    }

    if trouves.is_empty() {
        println!(
            "neutralite : rien à signaler pour « {} » sur « {} ».",
            utilisateur, hote_complet
        );
        return 0;
    }

    println!(
        "neutralite : {} référence(s) à éviter (utilisateur « {} », hôte « {} ») :\n",
        trouves.len(),
        utilisateur,
        hote_complet
    );
    for t in &trouves {
        println!("  {}:{}", t.chemin, t.numero);
        println!("    {} — '{}'", t.nom, t.extrait);
        println!("    à faire : {}", t.remede);
    }
    1
}
