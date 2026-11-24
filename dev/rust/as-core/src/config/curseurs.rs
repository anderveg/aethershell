//! Gestionnaire de thèmes de curseur (lot B2 de `roadmap.md`).
//!
//! Un seul `apply` doit écrire les quatre canaux, sinon le bureau montre trois
//! curseurs différents : compositeur (Hyprland), GTK3/GTK4 (INI + gsettings),
//! applications Wayland natives (variables d'environnement au prochain
//! lancement). L'état retenu vit dans `style_vars.json` (`cursor_theme`,
//! `cursor_size`) et `hypr_modular/exec.lua` le repousse via `hl.env()` au
//! chargement de la config.
//!
//! Décalqué d'`icones.rs` volontairement : même structure (list / apply /
//! install / remove), mêmes helpers, pour que les deux gestionnaires se
//! ressemblent.

use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd, write_json_atomic};
use crate::common::paths::{config_dir, home_dir, style_vars_path};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

/// Bornes imposées à la taille du curseur. En dessous de 16 px les curseurs
/// Xcursor n'ont plus d'image utilisable, au-dessus de 64 px Hyprland
/// agrandit l'image avec un rendu flou.
const TAILLE_MIN: u32 = 16;
const TAILLE_MAX: u32 = 64;
const TAILLE_DEFAUT: u32 = 24;

/// Formes utilisées pour l'aperçu, par ordre de préférence : la flèche par
/// défaut d'abord, puis les formes que tous les thèmes possèdent.
const FORMES_APERCU: &[&str] = &[
    "left_ptr",
    "default",
    "pointer",
    "arrow",
    "text",
    "wait",
    "crosshair",
];

/// Dossiers racine à inspecter : utilisateur d'abord (il gagne en cas de
/// doublon de nom, comme dans `icones.rs`).
fn racines_curseurs() -> Vec<(bool, PathBuf)> {
    vec![
        (true, home_dir().join(".local/share/icons")),
        (false, PathBuf::from("/usr/share/icons")),
    ]
}

fn gtk3_ini() -> PathBuf {
    config_dir().join("gtk-3.0/settings.ini")
}

fn gtk4_ini() -> PathBuf {
    config_dir().join("gtk-4.0/settings.ini")
}

fn qt6ct_conf() -> PathBuf {
    config_dir().join("qt6ct/qt6ct.conf")
}

fn env_session_conf() -> PathBuf {
    config_dir().join("environment.d/aethershell.conf")
}

fn cache_apercus() -> PathBuf {
    home_dir().join(".cache/aethershell/curseurs")
}

/// Un thème de curseur est un dossier `icons/<nom>` contenant `cursors/` avec
/// au moins un fichier : un thème qui n'a que des icônes d'applications n'est
/// pas proposé.
fn est_theme_curseur(dir: &Path) -> bool {
    let cursors = dir.join("cursors");
    if !cursors.is_dir() {
        return false;
    }
    fs::read_dir(&cursors)
        .map(|mut it| it.any(|e| e.map(|e| e.path().is_file()).unwrap_or(false)))
        .unwrap_or(false)
}

/// Nom lisible depuis `index.theme` (section `[Icon Theme]`, clé `Name`),
/// repli sur le nom de dossier quand le thème n'en déclare pas.
fn nom_lisible(dir: &Path) -> String {
    let repli = dir
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let Some(txt) = fs::read_to_string(dir.join("index.theme")).ok() else {
        return repli;
    };
    extraire_nom_theme(&txt).unwrap_or(repli)
}

/// Extraction pure (testable) de la clé `Name` d'un `index.theme`.
fn extraire_nom_theme(txt: &str) -> Option<String> {
    let mut dans_section = false;
    for raw in txt.lines() {
        let line = raw.trim();
        if line.starts_with('[') {
            dans_section = line == "[Icon Theme]";
            continue;
        }
        if !dans_section {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            if k.trim() == "Name" && !v.trim().is_empty() {
                return Some(v.trim().to_string());
            }
        }
    }
    None
}

/// Ramène une taille demandée dans les bornes utilisables.
fn bornier_taille(demandee: u32) -> u32 {
    demandee.clamp(TAILLE_MIN, TAILLE_MAX)
}

fn theme_existe(id: &str) -> Option<PathBuf> {
    for (_, racine) in racines_curseurs() {
        let p = racine.join(id);
        if est_theme_curseur(&p) {
            return Some(p);
        }
    }
    None
}

fn lire_style() -> Value {
    let v = read_json_value(&style_vars_path());
    if v.is_object() {
        v
    } else {
        json!({})
    }
}

fn valeur_texte(style: &Value, cle: &str) -> Option<String> {
    style
        .get(cle)
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn valeur_taille(style: &Value, cle: &str) -> Option<u32> {
    style
        .get(cle)
        .and_then(|v| v.as_u64())
        .map(|n| n as u32)
}

/// Thème actif : `style_vars.json` fait foi ; à défaut on lit le canal GTK,
/// puis `gsettings`, pour ne pas afficher un état vide sur une machine qui
/// n'a jamais utilisé le gestionnaire.
fn theme_actif(style: &Value) -> String {
    if let Some(t) = valeur_texte(style, "cursor_theme") {
        return t;
    }
    if let Ok(txt) = fs::read_to_string(gtk3_ini()) {
        for line in txt.lines() {
            if let Some(v) = line.trim().strip_prefix("gtk-cursor-theme-name=") {
                if !v.trim().is_empty() {
                    return v.trim().to_string();
                }
            }
        }
    }
    if let Some(out) = run_cmd("gsettings", &["get", "org.gnome.desktop.interface", "cursor-theme"]) {
        let s = String::from_utf8_lossy(&out.stdout).trim().trim_matches('\'').to_string();
        if !s.is_empty() {
            return s;
        }
    }
    String::new()
}

fn taille_active(style: &Value) -> u32 {
    valeur_taille(style, "cursor_size").unwrap_or(TAILLE_DEFAUT)
}

pub fn lister() -> Value {
    let style = lire_style();
    let actif = theme_actif(&style);
    let taille = taille_active(&style);
    let mut vus: BTreeMap<String, (bool, String, Value)> = BTreeMap::new();
    for (utilisateur, racine) in racines_curseurs() {
        if !racine.is_dir() {
            continue;
        }
        let Ok(entries) = fs::read_dir(&racine) else { continue };
        for ent in entries.flatten() {
            let p = ent.path();
            if !p.is_dir() {
                continue;
            }
            let id = ent.file_name().to_string_lossy().to_string();
            if id.starts_with('.') || vus.contains_key(&id) || !est_theme_curseur(&p) {
                continue;
            }
            let nom = nom_lisible(&p);
            let hyprcursor = p.join("hyprcursors/manifest.hl").is_file();
            vus.insert(
                id.clone(),
                (
                    utilisateur,
                    nom.to_ascii_lowercase(),
                    json!({
                        "id": id,
                        "nom": nom,
                        "chemin": p.to_string_lossy(),
                        "utilisateur": utilisateur,
                        "hyprcursor": hyprcursor,
                    }),
                ),
            );
        }
    }
    // Le thème actif d'abord, puis les thèmes utilisateur, puis l'ordre
    // alphabétique : la liste du panneau reste stable entre deux ouvertures.
    let mut vals: Vec<(bool, bool, String, Value)> = vus
        .into_iter()
        .map(|(id, (utilisateur, nom_l, v))| (id != actif, !utilisateur, nom_l, v))
        .collect();
    vals.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)).then_with(|| a.2.cmp(&b.2)));
    let themes: Vec<Value> = vals.into_iter().map(|(_, _, _, v)| v).collect();
    json!({ "ok": true, "actif": actif, "taille": taille, "themes": themes })
}

/// Met à jour une clé dans un INI en préservant le reste du fichier.
fn maj_ini_key(path: &Path, section: &str, key: &str, value: &str) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut lines: Vec<String> = Vec::new();
    let mut dans_section = false;
    let mut trouve = false;
    if let Ok(txt) = fs::read_to_string(path) {
        for raw in txt.lines() {
            let s = raw.trim();
            if s.starts_with('[') {
                if dans_section && !trouve {
                    lines.push(format!("{key}={value}"));
                    trouve = true;
                }
                dans_section = s == section;
            } else if dans_section && s.starts_with(&format!("{key}=")) {
                lines.push(format!("{key}={value}"));
                trouve = true;
                continue;
            }
            lines.push(raw.to_string());
        }
    }
    if !trouve {
        if !dans_section {
            lines.push(section.to_string());
        }
        lines.push(format!("{key}={value}"));
    }
    let _ = fs::write(path, lines.join("\n") + "\n");
}

/// `qt6ct.conf` seulement quand la clé existe déjà : y écrire une clé
/// inconnue de la version installée ne changerait rien et masquerait le fait
/// que Qt suit les variables d'environnement.
fn maj_ini_key_si_present(path: &Path, section: &str, key: &str, value: &str) -> bool {
    let Ok(txt) = fs::read_to_string(path) else { return false };
    let present = txt.lines().any(|l| l.trim().starts_with(&format!("{key}=")));
    if !present {
        return false;
    }
    maj_ini_key(path, section, key, value);
    true
}

/// Upsert `CLE=valeur` dans `environment.d/aethershell.conf` : ce fichier est
/// celui d'AetherShell (l'ancien fichier de session d'une autre distribution a été
/// retiré avec la purge, lot C) et
/// sert les applications lancées hors du compositeur. Il n'est relu qu'à la
/// connexion : c'est une persistance, pas une application à chaud.
fn maj_env_session(vars: &[(&str, String)]) {
    let path = env_session_conf();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut lines: Vec<String> = match fs::read_to_string(&path) {
        Ok(txt) => txt.lines().map(|l| l.to_string()).collect(),
        Err(_) => Vec::new(),
    };
    for (cle, val) in vars {
        let prefixe = format!("{cle}=");
        let mut remplace = false;
        for line in lines.iter_mut() {
            if line.trim_start().starts_with(&prefixe) {
                *line = format!("{cle}={val}");
                remplace = true;
                break;
            }
        }
        if !remplace {
            lines.push(format!("{cle}={val}"));
        }
    }
    let _ = fs::write(&path, lines.join("\n") + "\n");
}

/// Écrit l'état retenu dans `style_vars.json`. `write_json_atomic` prend déjà
/// le verrou : ne pas en ajouter un second (piège FileLock).
fn ecrire_style(id: &str, taille: u32) -> Result<(), String> {
    let mut style = lire_style();
    if !style.is_object() {
        style = json!({});
    }
    if let Value::Object(ref mut m) = style {
        m.insert("cursor_theme".to_string(), json!(id));
        m.insert("cursor_size".to_string(), json!(taille));
    }
    write_json_atomic(&style_vars_path(), &style, 0o644).map_err(|e| format!("écriture style_vars : {e}"))
}

fn appliquer(theme: &str, taille_demandee: Option<u32>) -> Value {
    let id = theme.trim();
    if id.is_empty() {
        return json!({ "ok": false, "error": "nom de thème vide" });
    }
    let Some(chemin) = theme_existe(id) else {
        return json!({
            "ok": false,
            "error": format!("Thème « {id} » introuvable (aucun dossier cursors/ dans les icônes installées)")
        });
    };
    let style = lire_style();
    let taille = bornier_taille(taille_demandee.unwrap_or_else(|| taille_active(&style)));
    let taille_s = taille.to_string();

    // Macro plutôt que fermeture : plusieurs canaux sont notés dans la même
    // fonction, une fermeture mutable entrerait en conflit d'emprunt avec les
    // `push` faits plus bas.
    let mut canaux: Vec<Value> = Vec::new();
    macro_rules! noter {
        ($canal:expr, $ok:expr, $detail:expr $(,)?) => {{
            let d: Option<String> = $detail;
            canaux.push(json!({ "canal": $canal, "ok": $ok, "detail": d }));
        }};
    }

    // 1. Compositeur : prend effet immédiatement, sans relogin.
    let hypr = run_cmd("hyprctl", &["setcursor", id, &taille_s]);
    let hypr_ok = hypr.as_ref().map(|o| o.status.success()).unwrap_or(false);
    noter!(
        "hyprland",
        hypr_ok,
        hypr_ok.then(|| "hyprctl setcursor".to_string()),
    );

    // 2. GTK4 / libadwaita : gsettings fait foi, les INI servent GTK3 et les
    //    apps qui les lisent encore.
    let gs_t = run_cmd("gsettings", &["set", "org.gnome.desktop.interface", "cursor-theme", id])
        .map(|o| o.status.success())
        .unwrap_or(false);
    let gs_s = run_cmd(
        "gsettings",
        &["set", "org.gnome.desktop.interface", "cursor-size", &taille_s],
    )
    .map(|o| o.status.success())
    .unwrap_or(false);
    noter!("gsettings", gs_t && gs_s, None);

    maj_ini_key(&gtk4_ini(), "[Settings]", "gtk-cursor-theme-name", id);
    maj_ini_key(&gtk4_ini(), "[Settings]", "gtk-cursor-theme-size", &taille_s);
    maj_ini_key(&gtk3_ini(), "[Settings]", "gtk-cursor-theme-name", id);
    maj_ini_key(&gtk3_ini(), "[Settings]", "gtk-cursor-theme-size", &taille_s);
    noter!("gtk3+gtk4", true, None);

    // 3. Qt : uniquement si qt6ct déclare déjà la clé (sinon il suit l'env).
    let qt = maj_ini_key_si_present(&qt6ct_conf(), "[Appearance]", "cursor_theme", id);
    noter!("qt6ct", qt, Some(if qt { "clé écrite" } else { "aucune clé curseur : Qt suit l'environnement" }.to_string()));

    // 4. Persistance des variables (prochain lancement / apps hors compositeur).
    maj_env_session(&[
        ("XCURSOR_THEME", id.to_string()),
        ("XCURSOR_SIZE", taille_s.clone()),
        ("HYPRCURSOR_THEME", id.to_string()),
        ("HYPRCURSOR_SIZE", taille_s.clone()),
    ]);
    noter!("environment.d", true, Some("relu à la connexion".to_string()));

    let style_ok = match ecrire_style(id, taille) {
        Ok(()) => true,
        Err(e) => {
            canaux.push(json!({ "canal": "style_vars", "ok": false, "detail": e }));
            false
        }
    };
    if style_ok {
        noter!("style_vars", true, None);
    }

    // `exec.lua` lit `style_vars.json` au chargement : sans rechargement, le
    // compositeur continuerait d'exporter l'ancien thème aux applications
    // lancées ensuite. Les effets de bord de l'autostart sont neutralisés par
    // le marqueur de session (voir `exec.lua`), le rechargement est donc sûr.
    let reload = run_cmd("hyprctl", &["reload"])
        .map(|o| o.status.success())
        .unwrap_or(false);
    noter!(
        "hyprland-reload",
        reload,
        Some("exec.lua relit style_vars.json ; l'autostart est protégé par son marqueur".to_string())
    );

    // Relecture : pas de succès optimiste, on renvoie l'état relu du disque.
    let mut res = lister();
    if let Value::Object(ref mut m) = res {
        m.insert(
            "message".into(),
            json!(format!("Curseur « {id} » appliqué (taille {taille})")),
        );
        m.insert("canaux".into(), json!(canaux));
        m.insert("chemin".into(), json!(chemin.to_string_lossy()));
    }
    res
}

/// Choisit le PNG d'aperçu dans un dossier de forme extrait par
/// `hyprcursor-util` : le plus grande résolution disponible.
fn choisir_png(dir: &Path) -> Option<PathBuf> {
    let mut best: Option<(u32, PathBuf)> = None;
    for ent in fs::read_dir(dir).ok()?.flatten() {
        let p = ent.path();
        if p.extension().and_then(|s| s.to_str()) != Some("png") {
            continue;
        }
        let idx = p
            .file_stem()
            .and_then(|s| s.to_str())
            .and_then(|s| s.rsplit('_').next())
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0);
        if best.as_ref().map(|(b, _)| idx > *b).unwrap_or(true) {
            best = Some((idx, p));
        }
    }
    best.map(|(_, p)| p)
}

/// Aperçu : `hyprcursor-util --extract` (déjà installé) convertit le thème
/// Xcursor en PNG, puis on garde la forme par défaut à la plus grande taille.
/// En cas d'échec, l'UI retombe sur un glyphe teinté : renvoyer une erreur
/// claire plutôt qu'une vignette trompeuse.
fn apercu(id: &str) -> Value {
    let Some(chemin) = theme_existe(id.trim()) else {
        return json!({ "ok": false, "error": format!("Thème « {id} » introuvable") });
    };
    let cible_dir = cache_apercus().join(id.trim());
    let cible = cible_dir.join("apercu.png");
    if cible.is_file() {
        return json!({ "ok": true, "id": id.trim(), "chemin": cible.to_string_lossy(), "cache": true });
    }
    let _ = fs::create_dir_all(&cible_dir);
    let tmp = cible_dir.join(format!(".extract_{}", std::process::id()));
    let _ = fs::remove_dir_all(&tmp);
    let _ = fs::create_dir_all(&tmp);

    let extraction = run_cmd(
        "hyprcursor-util",
        &["--extract", &chemin.to_string_lossy(), "-o", &tmp.to_string_lossy()],
    );
    let ok = extraction.map(|o| o.status.success()).unwrap_or(false);
    if !ok {
        let _ = fs::remove_dir_all(&tmp);
        return json!({
            "ok": false,
            "error": "hyprcursor-util n'a pas pu convertir ce thème (aperçu indisponible)"
        });
    }

    let racine = fs::read_dir(&tmp)
        .ok()
        .and_then(|it| it.flatten().map(|e| e.path()).find(|p| p.is_dir() && p.join("hyprcursors").is_dir()));
    let Some(racine) = racine else {
        let _ = fs::remove_dir_all(&tmp);
        return json!({ "ok": false, "error": "sortie de hyprcursor-util inattendue" });
    };

    let shapes = racine.join("hyprcursors");
    let mut choix: Option<PathBuf> = None;
    for forme in FORMES_APERCU {
        let d = shapes.join(forme);
        if d.is_dir() {
            if let Some(p) = choisir_png(&d) {
                choix = Some(p);
                break;
            }
        }
    }
    if choix.is_none() {
        // Dernier recours : n'importe quelle forme, ordre alphabétique.
        let mut dirs: Vec<PathBuf> = fs::read_dir(&shapes)
            .map(|it| it.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect())
            .unwrap_or_default();
        dirs.sort();
        choix = dirs.iter().find_map(|d| choisir_png(d));
    }

    let Some(src) = choix else {
        let _ = fs::remove_dir_all(&tmp);
        return json!({ "ok": false, "error": "aucune image PNG extraite de ce thème" });
    };
    let copie = fs::copy(&src, &cible);
    let _ = fs::remove_dir_all(&tmp);
    match copie {
        Ok(_) => json!({ "ok": true, "id": id.trim(), "chemin": cible.to_string_lossy(), "cache": false }),
        Err(e) => json!({ "ok": false, "error": format!("copie de l'aperçu impossible : {e}") }),
    }
}

fn installer_pack(archive: &str) -> Value {
    let arch_path = PathBuf::from(archive.trim());
    if !arch_path.is_file() {
        return json!({ "ok": false, "error": format!("Archive introuvable : {}", arch_path.display()) });
    }
    let udir = home_dir().join(".local/share/icons");
    let _ = fs::create_dir_all(&udir);
    let tmp = udir.join(format!(".tmp_cursor_pack_{}", std::process::id()));
    let _ = fs::create_dir_all(&tmp);
    let lower = arch_path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    let extrait = if lower.ends_with(".zip") {
        run_cmd("unzip", &["-q", &arch_path.to_string_lossy(), "-d", &tmp.to_string_lossy()])
            .map(|o| o.status.success())
            .unwrap_or(false)
    } else if lower.ends_with(".tar.zst") {
        run_cmd("tar", &["--zstd", "-xf", &arch_path.to_string_lossy(), "-C", &tmp.to_string_lossy()])
            .map(|o| o.status.success())
            .unwrap_or(false)
    } else {
        run_cmd("tar", &["-xf", &arch_path.to_string_lossy(), "-C", &tmp.to_string_lossy()])
            .map(|o| o.status.success())
            .unwrap_or(false)
    };

    let mut installes = Vec::new();
    if extrait {
        let mut tous: Vec<PathBuf> = WalkDir::new(&tmp)
            .max_depth(4)
            .into_iter()
            .flatten()
            .filter(|e| e.file_name() == std::ffi::OsStr::new("cursors") && e.path().is_dir())
            .filter_map(|e| e.path().parent().map(|p| p.to_path_buf()))
            .collect();
        tous.sort();
        tous.dedup();
        // Un pack peut contenir `theme/x/cursors` et `theme/x/24/cursors` :
        // on ne garde que le plus haut de chaque branche.
        let mut candidats: Vec<PathBuf> = Vec::new();
        for p in tous {
            if !candidats.iter().any(|d| p.starts_with(d)) {
                candidats.push(p);
            }
        }
        for src in candidats {
            if let Some(nom) = src.file_name() {
                let dst = udir.join(nom);
                if dst.exists() {
                    let _ = fs::remove_dir_all(&dst);
                }
                if fs::rename(&src, &dst).is_ok() {
                    installes.push(nom.to_string_lossy().to_string());
                }
            }
        }
    }
    let _ = fs::remove_dir_all(&tmp);
    if installes.is_empty() {
        return json!({ "ok": false, "error": "Aucun thème de curseur valide (dossier cursors/) dans l'archive." });
    }
    let mut res = lister();
    if let Value::Object(ref mut m) = res {
        m.insert("message".into(), json!(format!("Installé : {}", installes.join(", "))));
        m.insert("installed".into(), json!(installes));
    }
    res
}

fn supprimer_theme(id: &str) -> Value {
    let t = id.trim();
    let udir = home_dir().join(".local/share/icons");
    let cible = udir.join(t);
    if t.is_empty() || cible.parent() != Some(udir.as_path()) || !est_theme_curseur(&cible) {
        return json!({
            "ok": false,
            "error": "Seuls les thèmes de curseur installés dans ~/.local/share/icons peuvent être supprimés."
        });
    }
    let actif = theme_actif(&lire_style());
    if actif == t {
        return json!({
            "ok": false,
            "error": format!("« {t} » est le thème actif : appliquer un autre curseur avant de le supprimer")
        });
    }
    let _ = fs::remove_dir_all(&cible);
    let _ = fs::remove_dir_all(cache_apercus().join(t));
    let mut res = lister();
    if let Value::Object(ref mut m) = res {
        m.insert("message".into(), json!(format!("Thème « {t} » supprimé")));
    }
    res
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("list");
    let res = match action {
        "list" => lister(),
        "etat" => {
            let style = lire_style();
            json!({
                "ok": true,
                "actif": theme_actif(&style),
                "taille": taille_active(&style),
                "style_vars": valeur_texte(&style, "cursor_theme"),
            })
        }
        "apply" if args.len() > 1 => {
            let taille = args.get(2).and_then(|s| s.trim().parse::<u32>().ok());
            appliquer(&args[1], taille)
        }
        "preview" if args.len() > 1 => apercu(&args[1]),
        "install" if args.len() > 1 => installer_pack(&args[1]),
        "remove" if args.len() > 1 => supprimer_theme(&args[1]),
        _ => json!({ "ok": false, "error": "Action inconnue (list, etat, apply, preview, install, remove)" }),
    };
    sortir(&res)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn taille_bornee_dans_les_limites() {
        assert_eq!(bornier_taille(4), TAILLE_MIN);
        assert_eq!(bornier_taille(24), 24);
        assert_eq!(bornier_taille(200), TAILLE_MAX);
    }

    #[test]
    fn nom_lu_dans_index_theme() {
        let txt = "[Icon Theme]\nName=Vimix Cursors\nComment=x\n";
        assert_eq!(extraire_nom_theme(txt), Some("Vimix Cursors".to_string()));
    }

    #[test]
    fn nom_absent_ou_hors_section() {
        assert_eq!(extraire_nom_theme("[Desktop Entry]\nName=Autre\n"), None);
        assert_eq!(extraire_nom_theme(""), None);
    }

    #[test]
    fn apercu_prend_la_plus_grande_resolution() {
        let dir = std::env::temp_dir().join(format!("as_cur_test_{}", std::process::id()));
        let _ = fs::create_dir_all(&dir);
        for n in [0u32, 1, 3] {
            fs::write(dir.join(format!("default_{n:03}.png")), b"x").unwrap();
        }
        let choisi = choisir_png(&dir).expect("un png");
        assert!(choisi.to_string_lossy().ends_with("default_003.png"));
        let _ = fs::remove_dir_all(&dir);
    }
}
