//! Thèmes SDDM de qylock, récupérés à la demande — jamais versionnés.
//!
//! Port de `dev/sddm/qylock.py`. Amont : `Darkkal44/qylock` (GPL-3.0) ; ses
//! thèmes pèsent ~595 Mo (fonds vidéo), donc on ne télécharge que les thèmes
//! demandés, dans `~/.local/share/qylock-themes/<nom>/`.
//!
//!   as-core qylock list                     thèmes du dépôt, récupérés ou non
//!   as-core qylock fetch <nom…>             télécharge les thèmes nommés
//!   as-core qylock fetch --static <nom…>    idem, en refusant un fond vidéo
//!   as-core qylock fetch --all              tout le dépôt (demande confirmation)
//!
//! Le cache de l'arbre GitHub vit dans `~/.cache/quickshell/qylock-tree.json` ;
//! `QYLOCK_REFRESH=1` le rafraîchit après une mise à jour amont.

use crate::common::paths::{cache_dir, home_dir};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

const TREE_URL: &str = "https://api.github.com/repos/Darkkal44/qylock/git/trees/main?recursive=1";
const RAW_BASE: &str = "https://raw.githubusercontent.com/Darkkal44/qylock/main/";
const SYS_THEMES: &str = "/usr/share/sddm/themes";

fn cache_themes() -> PathBuf {
    home_dir().join(".local/share/qylock-themes")
}

fn cache_arbre() -> PathBuf {
    cache_dir().join("quickshell/qylock-tree.json")
}

fn die(msg: &str) -> i32 {
    let mut err = std::io::stderr().lock();
    let _ = writeln!(err, "qylock: {msg}");
    1
}

fn humain(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1} Mo", n as f64 / 1e6)
    } else {
        format!("{:.0} ko", n as f64 / 1e3)
    }
}

fn est_video(chemin: &str) -> bool {
    [".mp4", ".webm", ".mkv"]
        .iter()
        .any(|ext| chemin.ends_with(ext))
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(30))
        .user_agent("aethershell-greeter")
        .build()
}

/// Arbre du dépôt amont, mis en cache (une requête par mise à jour).
fn arbre() -> Result<Vec<Value>, String> {
    let cache = cache_arbre();
    if cache.exists() && std::env::var_os("QYLOCK_REFRESH").is_none() {
        if let Ok(texte) = std::fs::read_to_string(&cache) {
            if let Ok(v) = serde_json::from_str::<Value>(&texte) {
                if let Some(liste) = v.get("tree").and_then(|t| t.as_array()) {
                    return Ok(liste.clone());
                }
            }
        }
    }
    let texte = match agent().get(TREE_URL).call() {
        Ok(resp) => match resp.into_string() {
            Ok(t) => t,
            Err(e) => return Err(format!("arbre GitHub illisible : {e}")),
        },
        Err(e) => return Err(format!("arbre GitHub illisible : {e}")),
    };
    let data: Value = match serde_json::from_str(&texte) {
        Ok(v) => v,
        Err(e) => return Err(format!("arbre GitHub illisible : {e}")),
    };
    let liste = match data.get("tree").and_then(|t| t.as_array()) {
        Some(l) => l.clone(),
        None => {
            let extrait: String = texte.trim().chars().take(120).collect();
            return Err(format!("réponse GitHub inattendue : {extrait}"));
        }
    };
    if let Some(parent) = cache.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(&cache, &texte);
    Ok(liste)
}

/// `{nom du thème: [entrées de fichiers]}` depuis `themes/<nom>/…`.
fn index() -> Result<BTreeMap<String, Vec<Value>>, String> {
    let mut out: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for entree in arbre()? {
        if entree.get("type").and_then(|t| t.as_str()) != Some("blob") {
            continue;
        }
        let chemin = entree
            .get("path")
            .and_then(|p| p.as_str())
            .unwrap_or("")
            .to_string();
        let parts: Vec<&str> = chemin.split('/').collect();
        if parts.len() < 3 || parts[0] != "themes" {
            continue;
        }
        out.entry(parts[1].to_string()).or_default().push(entree);
    }
    Ok(out)
}

fn label(name: &str) -> String {
    let brut: String = name
        .chars()
        .map(|c| if c == '-' || c == '_' { ' ' } else { c })
        .collect();
    let brut = brut.trim();
    let mut iter = brut.chars();
    match iter.next() {
        Some(premier) => premier.to_uppercase().collect::<String>() + iter.as_str(),
        None => String::new(),
    }
}

/// Dossiers réellement installables : ceux qui portent un `metadata.desktop`.
fn dossiers_variantes(root: &Path) -> Vec<PathBuf> {
    if !root.is_dir() {
        return Vec::new();
    }
    let mut trouves = Vec::new();
    if root.join("metadata.desktop").exists() {
        trouves.push(root.to_path_buf());
    }
    let mut sous: Vec<PathBuf> = match std::fs::read_dir(root) {
        Ok(rd) => rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect(),
        Err(_) => Vec::new(),
    };
    sous.sort();
    for sub in sous {
        if sub.join("metadata.desktop").exists() {
            trouves.push(sub);
        }
    }
    trouves
}

fn nom_installe(theme: &str, chemin: &Path) -> String {
    let root = cache_themes().join(theme);
    if chemin == root {
        theme.to_string()
    } else {
        format!(
            "{}-{}",
            theme,
            chemin.file_name().and_then(|s| s.to_str()).unwrap_or("")
        )
    }
}

fn etat(name: &str) -> (bool, bool) {
    let dirs = dossiers_variantes(&cache_themes().join(name));
    let recu = !dirs.is_empty();
    let installe = recu
        && dirs
            .iter()
            .all(|d| Path::new(SYS_THEMES).join(nom_installe(name, d)).exists());
    (recu, installe)
}

fn cmd_list() -> i32 {
    let idx = match index() {
        Ok(i) => i,
        Err(e) => return die(&e),
    };
    let mut noms: Vec<&String> = idx.keys().collect();
    noms.sort_by_key(|n| label(n));

    let mut lignes = Vec::new();
    for name in noms {
        let fichiers = &idx[name];
        let mut taille: u64 = 0;
        let mut video = false;
        for f in fichiers {
            taille += f.get("size").and_then(|s| s.as_u64()).unwrap_or(0);
            if est_video(f.get("path").and_then(|p| p.as_str()).unwrap_or("")) {
                video = true;
            }
        }
        let (recu, installe) = etat(name);
        let variantes = dossiers_variantes(&cache_themes().join(name)).len();
        let mut ligne = Map::new();
        ligne.insert("name".into(), json!(name));
        ligne.insert("label".into(), json!(label(name)));
        ligne.insert("size".into(), json!(taille));
        ligne.insert("video".into(), json!(video));
        ligne.insert("fetched".into(), json!(recu));
        ligne.insert("installed".into(), json!(installe));
        ligne.insert("variants".into(), json!(variantes));
        lignes.push(Value::Object(ligne));
    }

    println!(
        "{}",
        json!({
            "ok": true,
            "cache": cache_themes().to_string_lossy(),
            "themes": lignes,
        })
    );
    0
}

/// Encode une URL en gardant les séparateurs de chemin : les noms amont
/// contiennent des espaces et des parenthèses (« A Glow (1).jpg »).
fn encoder_chemin(chemin: &str) -> String {
    let mut out = String::new();
    for octet in chemin.as_bytes() {
        let c = *octet as char;
        let garde = c.is_ascii_alphanumeric()
            || matches!(c, '-' | '_' | '.' | '~' | '/');
        if garde {
            out.push(c);
        } else {
            out.push_str(&format!("%{:02X}", octet));
        }
    }
    out
}

fn fetch(name: &str, entries: &[Value], static_only: bool) -> Result<Vec<String>, i32> {
    if static_only
        && entries
            .iter()
            .any(|e| est_video(e.get("path").and_then(|p| p.as_str()).unwrap_or("")))
    {
        return Err(die(&format!("{name} : fond vidéo, refusé par --static")));
    }
    let total: u64 = entries
        .iter()
        .map(|e| e.get("size").and_then(|s| s.as_u64()).unwrap_or(0))
        .sum();
    println!(
        "▶ {} — {} fichiers, {}",
        label(name),
        entries.len(),
        humain(total)
    );

    let dest = cache_themes().join(name);
    let mut echecs: Vec<String> = Vec::new();
    let client = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(60))
        .user_agent("aethershell-greeter")
        .build();

    for e in entries {
        let chemin = e.get("path").and_then(|p| p.as_str()).unwrap_or("");
        let taille = e.get("size").and_then(|s| s.as_u64()).unwrap_or(0);
        // `themes/<nom>/<relatif>` : on garde le chemin relatif au thème.
        let rel = match chemin.splitn(3, '/').nth(2) {
            Some(r) => r.to_string(),
            None => chemin.to_string(),
        };
        let cible = dest.join(&rel);
        if let Some(parent) = cible.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(md) = std::fs::metadata(&cible) {
            if md.len() == taille {
                continue;
            }
        }

        let url = format!("{RAW_BASE}{}", encoder_chemin(chemin));
        let mut tampon = Vec::new();
        let mut echec: Option<String> = None;
        match client.get(&url).call() {
            Ok(resp) => {
                if let Err(e) = resp.into_reader().read_to_end(&mut tampon) {
                    echec = Some(e.to_string());
                }
            }
            Err(e) => echec = Some(e.to_string()),
        }
        match echec {
            Some(raison) => {
                let mut err = std::io::stderr().lock();
                let _ = writeln!(err, "  ✗ {rel} : {raison}");
                echecs.push(rel);
            }
            None => {
                if let Err(e) = std::fs::write(&cible, &tampon) {
                    let mut err = std::io::stderr().lock();
                    let _ = writeln!(err, "  ✗ {rel} : {e}");
                    echecs.push(rel);
                    continue;
                }
                println!("  {rel} ({})", humain(taille));
            }
        }
    }

    let vdirs = dossiers_variantes(&dest);
    if vdirs.is_empty() {
        for besoin in ["Main.qml", "metadata.desktop"] {
            if !dest.join(besoin).exists() {
                return Err(die(&format!("{name} : {besoin} manquant après téléchargement")));
            }
        }
    } else {
        for d in &vdirs {
            for besoin in ["Main.qml", "metadata.desktop"] {
                if !d.join(besoin).exists() {
                    return Err(die(&format!(
                        "{name} ({}) : {besoin} manquant après téléchargement",
                        d.file_name().and_then(|s| s.to_str()).unwrap_or("")
                    )));
                }
            }
        }
    }
    println!("  → {}", dest.display());
    Ok(echecs)
}

fn est_interactif() -> bool {
    unsafe { libc::isatty(libc::STDIN_FILENO) == 1 }
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("list");
    if action == "-h" || action == "--help" {
        println!("usage: as-core qylock <list|fetch [--static] [--all] <nom…>>");
        return 0;
    }
    if action == "list" {
        return cmd_list();
    }
    if action != "fetch" {
        return die(&format!("action inconnue : {action}"));
    }

    let idx = match index() {
        Ok(i) => i,
        Err(e) => return die(&e),
    };
    let rest = &args[1..];
    let static_only = rest.iter().any(|a| a == "--static");
    let everything = rest.iter().any(|a| a == "--all");
    let mut noms: Vec<String> = rest
        .iter()
        .filter(|a| !a.starts_with("--"))
        .cloned()
        .collect();

    if everything {
        noms = idx.keys().cloned().collect();
        let total: u64 = noms
            .iter()
            .map(|n| {
                idx[n]
                    .iter()
                    .map(|f| f.get("size").and_then(|s| s.as_u64()).unwrap_or(0))
                    .sum::<u64>()
            })
            .sum();
        println!(
            "⚠ {} thèmes, {} au total (dont des fonds vidéo jusqu'à 78 Mo)",
            noms.len(),
            humain(total)
        );
        if est_interactif() {
            print!("continuer ? [o/N] ");
            let _ = std::io::stdout().flush();
            let mut ligne = String::new();
            if std::io::stdin().read_line(&mut ligne).is_err() {
                return die("annulé");
            }
            let r = ligne.trim().to_lowercase();
            if !matches!(r.as_str(), "o" | "oui" | "y") {
                return die("annulé");
            }
        } else {
            return die("--all demande une confirmation interactive");
        }
    }
    if noms.is_empty() {
        return die("aucun thème nommé (voir : as-core qylock list)");
    }

    let inconnus: Vec<&String> = noms.iter().filter(|n| !idx.contains_key(*n)).collect();
    if !inconnus.is_empty() {
        let liste: Vec<String> = inconnus.iter().map(|s| s.to_string()).collect();
        return die(&format!("thème inconnu : {}", liste.join(", ")));
    }

    let mut echecs: Vec<String> = Vec::new();
    for n in &noms {
        match fetch(n, &idx[n], static_only) {
            Ok(mut e) => echecs.append(&mut e),
            Err(code) => return code,
        }
    }
    if !echecs.is_empty() {
        let mut err = std::io::stderr().lock();
        let _ = writeln!(
            err,
            "\n⚠ {} fichier(s) non récupéré(s) — relancer la commande reprend là où ça s'est arrêté.",
            echecs.len()
        );
    }
    println!(
        "\ninstaller : bash dev/sddm/install.sh --qylock {}",
        noms.join(" ")
    );
    0
}
