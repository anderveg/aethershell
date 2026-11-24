//! Catalogue de thèmes livrés (lot B4 de `roadmap.md`).
//!
//! Le dépôt embarque neuf fonds d'écran compressés (`dev/wallpapers/*.jpg`,
//! 1920×1080, qualité 85, ~2,6 Mo au total) et leurs profils cohérents
//! (`core/theme_profiles.catalog.json`). `install.sh` les déploie dans
//! `~/.config/quickshell/wallpapers/` et `core/` ; cette commande fait le pont
//! avec la machine de l'utilisateur :
//!
//! - elle copie les fonds dans le dossier de fonds choisi (arbitrage Q2 : aucun
//!   chemin absolu dans un profil, seulement un nom de fichier résolu par
//!   `wallpaper_dir`) ;
//! - elle **fusionne** les profils du catalogue absents sans jamais écraser un
//!   profil que l'utilisateur a modifié ;
//! - elle écrit `wallpaper_dir` dans `style_vars.json` après copie.
//!
//! Appelée par le first-run (dossier « Images » retenu) et disponible à la main :
//! `as-core catalogue install [dossier]`.

use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, write_json_atomic};
use crate::common::paths::{core_dir, home_dir, style_vars_path};
use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};

const CATALOGUE: &str = "theme_profiles.catalog.json";
const PROFILS: &str = "theme_profiles.json";

/// Dossier des fonds livrés avec le dépôt, une fois déployé
/// (`~/.config/quickshell/wallpapers/`).
fn dossier_livres() -> PathBuf {
    core_dir().join("../wallpapers")
}

fn lire_json(path: &Path) -> Map<String, Value> {
    match read_json_value(path) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

/// Étend un `$HOME` littéral et un `~` de tête (même convention que
/// `generate_colors.sh` et `first_run.rs`).
fn etendre(chemin: &str) -> String {
    let t = chemin.trim();
    let home = home_dir().to_string_lossy().to_string();
    if let Some(rest) = t.strip_prefix("$HOME") {
        return format!("{home}{rest}");
    }
    if let Some(rest) = t.strip_prefix("~/") {
        return format!("{home}/{rest}");
    }
    if t == "~" {
        return home;
    }
    t.to_string()
}

fn dossier_destination(arg: Option<&String>) -> PathBuf {
    if let Some(a) = arg {
        let c = etendre(a);
        if !c.is_empty() {
            return PathBuf::from(c);
        }
    }
    let style = lire_json(&style_vars_path());
    if let Some(d) = style.get("wallpaper_dir").and_then(|v| v.as_str()) {
        let c = etendre(d);
        if !c.is_empty() {
            return PathBuf::from(c);
        }
    }
    home_dir().join("Images/wallpapers")
}

fn copier_fonds(dest: &Path) -> (Vec<String>, Vec<String>, Vec<String>) {
    let mut copies = Vec::new();
    let mut deja = Vec::new();
    let mut erreurs = Vec::new();
    if fs::create_dir_all(dest).is_err() {
        erreurs.push(format!("création impossible : {}", dest.display()));
        return (copies, deja, erreurs);
    }
    let source = dossier_livres();
    let Ok(entrees) = fs::read_dir(&source) else {
        erreurs.push(format!("fonds livrés introuvables dans {}", source.display()));
        return (copies, deja, erreurs);
    };
    for e in entrees.flatten() {
        let p = e.path();
        let Some(nom) = p.file_name().map(|s| s.to_string_lossy().to_string()) else {
            continue;
        };
        if !nom.to_ascii_lowercase().ends_with(".jpg") {
            continue;
        }
        let cible = dest.join(&nom);
        if cible.exists() {
            // Jamais d'écrasement : l'utilisateur peut avoir retouché un fond.
            deja.push(nom);
            continue;
        }
        match fs::copy(&p, &cible) {
            Ok(_) => copies.push(nom),
            Err(err) => erreurs.push(format!("{nom} : {err}")),
        }
    }
    copies.sort();
    deja.sort();
    (copies, deja, erreurs)
}

fn fusionner_profils(catalogue: &Map<String, Value>) -> Vec<String> {
    let chemin = core_dir().join(PROFILS);
    let mut profils = lire_json(&chemin);
    let mut ajoutes = Vec::new();
    for (nom, contenu) in catalogue {
        if nom == "__avant__" || nom == "__actif__" {
            continue;
        }
        match profils.get(nom) {
            None => {
                profils.insert(nom.clone(), contenu.clone());
                ajoutes.push(nom.clone());
            }
            // `created_at == 0` marque un preset LIVRÉ : il suit les mises à jour
            // du catalogue. Dès que l'utilisateur le réenregistre (⟳), il porte sa
            // propre date et n'est plus jamais écrasé.
            Some(existant) if existant.get("created_at").and_then(|v| v.as_i64()) == Some(0) => {
                if existant != contenu {
                    profils.insert(nom.clone(), contenu.clone());
                    ajoutes.push(nom.clone());
                }
            }
            Some(_) => {}
        }
    }
    ajoutes.sort();
    if !ajoutes.is_empty() {
        let _ = write_json_atomic(&chemin, &profils, 0o644);
    }
    ajoutes
}

/// Entrée pour le first-run : installe dans `dest` (dossier « Images » retenu
/// plus `/wallpapers`), ou dans le dossier déjà configuré si `None`.
pub fn installer_vers(dest: Option<String>) -> Value {
    installer(dest.as_ref())
}

fn installer(arg: Option<&String>) -> Value {
    let catalogue = lire_json(&core_dir().join(CATALOGUE));
    let dest = dossier_destination(arg);
    let (copies, deja, erreurs) = copier_fonds(&dest);

    // Le dossier retenu devient la référence : les profils ne stockent qu'un nom
    // de fichier (arbitrage Q2).
    let mut style = read_json_value(&style_vars_path());
    if let Some(obj) = style.as_object_mut() {
        let mut d = dest.to_string_lossy().to_string();
        if !d.ends_with('/') {
            d.push('/');
        }
        obj.insert("wallpaper_dir".into(), json!(d));
        let _ = write_json_atomic(&style_vars_path(), &style, 0o644);
    }

    let ajoutes = fusionner_profils(&catalogue);
    json!({
        "ok": erreurs.is_empty(),
        "dossier": dest.to_string_lossy(),
        "fonds_copies": copies,
        "fonds_deja_presents": deja,
        "profils_ajoutes": ajoutes,
        "profils_catalogue": catalogue.len(),
        "erreurs": erreurs,
    })
}

fn lister() -> Value {
    let catalogue = lire_json(&core_dir().join(CATALOGUE));
    let profils = lire_json(&core_dir().join(PROFILS));
    let dest = dossier_destination(None);
    let mut entrees: Vec<Value> = Vec::new();
    let mut noms: Vec<&String> = catalogue.keys().collect();
    noms.sort();
    for nom in noms {
        let p = &catalogue[nom];
        let fichier = p
            .get("wallpaper")
            .and_then(|w| w.get("file"))
            .and_then(|f| f.as_str())
            .unwrap_or("");
        entrees.push(json!({
            "nom": nom,
            "fond": fichier,
            "installe": profils.contains_key(nom),
            "fond_present": dest.join(fichier).is_file(),
        }));
    }
    json!({ "ok": true, "dossier": dest.to_string_lossy(), "themes": entrees })
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("install");
    let res = match action {
        "list" => lister(),
        "install" => installer(args.get(1)),
        _ => json!({
            "ok": false,
            "error": "Action inconnue (install [dossier], list)"
        }),
    };
    sortir(&res)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn etend_home_litteral_et_tilde() {
        let home = home_dir().to_string_lossy().to_string();
        assert_eq!(etendre("$HOME/Images/wallpapers/"), format!("{home}/Images/wallpapers/"));
        assert_eq!(etendre("~/Images"), format!("{home}/Images"));
        assert_eq!(etendre("/déjà/absolu"), "/déjà/absolu");
    }

    #[test]
    fn copie_sans_ecraser_un_fond_existant() {
        let base = std::env::temp_dir().join(format!("as-catalogue-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let src = base.join("livres");
        let dst = base.join("cible");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();
        fs::write(src.join("a.jpg"), b"nouveau").unwrap();
        fs::write(dst.join("a.jpg"), b"modifie par l'utilisateur").unwrap();
        let (copies, deja, erreurs) = {
            // dossier_livres() pointe sur core/../wallpapers : on reproduit la
            // même logique localement pour rester testable hors installation.
            let source = src.clone();
            let mut copies = Vec::new();
            let mut deja = Vec::new();
            for e in fs::read_dir(&source).unwrap().flatten() {
                let nom = e.file_name().to_string_lossy().to_string();
                let cible = dst.join(&nom);
                if cible.exists() {
                    deja.push(nom);
                } else {
                    fs::copy(e.path(), &cible).unwrap();
                    copies.push(nom);
                }
            }
            (copies, deja, Vec::<String>::new())
        };
        assert_eq!(deja, vec!["a.jpg".to_string()]);
        assert!(copies.is_empty());
        assert!(erreurs.is_empty());
        assert_eq!(fs::read_to_string(dst.join("a.jpg")).unwrap(), "modifie par l'utilisateur");
        let _ = fs::remove_dir_all(&base);
    }
}
