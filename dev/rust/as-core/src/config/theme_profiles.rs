//! Profils de thème (lot B1 de `roadmap.md`).
//!
//! Un profil est **atomique et cohérent** : fond d'écran, palette, ambiance du
//! shell (les 28 clés de `presets::PRESET_STYLE_KEYS`), icônes, curseur, plus
//! une **référence** (`env_ref`) à un profil d'environnement du lot A — jamais
//! une copie des modes : corriger « Focus » une fois profite à tous les thèmes
//! qui le référencent (arbitrage Q1, option C).
//!
//! `apply` est transactionnel : l'état courant est d'abord archivé dans
//! `"__avant__"`, et une étape fatale (écriture du style, palette) restaure le
//! style d'avant. Les canaux non fatals (icônes, curseur, DND) sont rapportés
//! séparément pour que l'UI n'annonce jamais un succès partiel.
//!
//! Le fichier `core/theme_profiles.json` vit à côté de `style_vars.json` : même
//! règle de déploiement (préservé), même écriture atomique.

use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd, write_json_atomic};
use crate::common::paths::{core_dir, home_dir, quickshell_cache_dir, style_vars_path};
use crate::config::presets::PRESET_STYLE_KEYS;
use serde_json::{json, Map, Value};
use std::fs;
use std::path::PathBuf;

const FICHIER: &str = "theme_profiles.json";
/// Clé réservée : état d'avant le dernier `apply`, pour `undo`.
const CLE_AVANT: &str = "__avant__";
/// Clé réservée : dernier profil appliqué. Persistée pour que le panneau
/// retrouve la surbrillance après un redémarrage du shell — l'état QML, lui, ne
/// survit pas.
const CLE_ACTIF: &str = "__actif__";

fn chemin_profils() -> PathBuf {
    core_dir().join(FICHIER)
}

fn lire_profils() -> Map<String, Value> {
    match read_json_value(&chemin_profils()) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

fn ecrire_profils(profils: &Map<String, Value>) -> Result<(), String> {
    write_json_atomic(&chemin_profils(), profils, 0o644)
        .map_err(|e| format!("écriture {} : {e}", chemin_profils().display()))
}

fn style_actuel() -> Map<String, Value> {
    match read_json_value(&style_vars_path()) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

/// Chemin du binaire en cours : les canaux icônes / curseur / profils
/// d'environnement sont des sous-commandes d'`as-core`, appelées en
/// sous-processus pour ne pas empiler les verrous (`FileLock`) dans le même
/// processus.
fn exe() -> String {
    std::env::current_exe()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| "as-core".to_string())
}

fn wallpaper_affiche() -> Option<String> {
    let out = run_cmd("awww", &["query"])?;
    let txt = String::from_utf8_lossy(&out.stdout).to_string();
    for ligne in txt.lines() {
        if let Some(idx) = ligne.find("currently displaying:") {
            let reste = &ligne[idx + "currently displaying:".len()..];
            let chemin = reste.trim().trim_start_matches("image:").trim();
            if !chemin.is_empty() {
                return Some(chemin.to_string());
            }
        }
    }
    None
}

/// Clé d'un INI (`[section]` ignorée volontairement : on ne lit qu'une clé
/// unique, présente une seule fois dans les fichiers GTK).
fn lire_ini_key(path: &PathBuf, cle: &str) -> Option<String> {
    let txt = fs::read_to_string(path).ok()?;
    for ligne in txt.lines() {
        if let Some(v) = ligne.trim().strip_prefix(&format!("{cle}=")) {
            let v = v.trim();
            if !v.is_empty() {
                return Some(v.to_string());
            }
        }
    }
    None
}

fn icones_actives() -> String {
    lire_ini_key(&home_dir().join(".config/gtk-4.0/settings.ini"), "gtk-icon-theme-name")
        .or_else(|| lire_ini_key(&home_dir().join(".config/gtk-3.0/settings.ini"), "gtk-icon-theme-name"))
        .unwrap_or_default()
}

fn curseur_actif(style: &Map<String, Value>) -> (String, u32) {
    let theme = style
        .get("cursor_theme")
        .and_then(|v| v.as_str())
        .unwrap_or("Vimix-cursors")
        .to_string();
    let taille = style
        .get("cursor_size")
        .and_then(|v| v.as_u64())
        .unwrap_or(24) as u32;
    (theme, taille)
}

fn palette_du_style(style: &Map<String, Value>) -> Value {
    let actif = style
        .get("active_theme")
        .and_then(|v| v.as_str())
        .unwrap_or("dynamic");
    if actif == "dynamic" {
        json!({
            "mode": "matugen",
            "scheme": style.get("matugen_scheme").cloned().unwrap_or(json!("scheme-tonal-spot")),
            "contrast": style.get("matugen_contrast").cloned().unwrap_or(json!(0)),
        })
    } else {
        json!({ "mode": "kde", "colors": actif })
    }
}

/// Capture de l'état courant, au format d'un profil.
fn capturer(style: &Map<String, Value>, env_ref: Option<String>) -> Value {
    let mut cles = Map::new();
    for &k in PRESET_STYLE_KEYS {
        if let Some(v) = style.get(k) {
            cles.insert(k.to_string(), v.clone());
        }
    }

    let wallpaper = wallpaper_affiche().map(|source| {
        let nom = PathBuf::from(&source)
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| source.clone());
        json!({ "file": nom, "source": source })
    });

    let (cursor_theme, cursor_size) = curseur_actif(style);
    let mut profil = Map::new();
    profil.insert("created_at".into(), json!(horodatage()));
    profil.insert("style".into(), Value::Object(cles));
    profil.insert("palette".into(), palette_du_style(style));
    if let Some(w) = wallpaper {
        profil.insert("wallpaper".into(), w);
    }
    profil.insert("icons".into(), json!({ "theme": icones_actives() }));
    profil.insert(
        "cursor".into(),
        json!({ "theme": cursor_theme, "size": cursor_size }),
    );
    // Axe clair/sombre : un profil peut le FIXER (presets livrés) ou le laisser
    // libre (`auto`). L'archive `__avant__` le mémorise aussi pour `undo`.
    profil.insert(
        "theme_mode".into(),
        json!(style.get("theme_mode").and_then(|v| v.as_str()).unwrap_or("auto")),
    );
    profil.insert(
        "env_ref".into(),
        env_ref.map(Value::String).unwrap_or(Value::Null),
    );
    Value::Object(profil)
}

fn horodatage() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Résumé lisible d'un profil pour la liste du panneau.
fn resume(nom: &str, p: &Value) -> Value {
    let palette = p.get("palette");
    let mode = palette
        .and_then(|x| x.get("mode"))
        .and_then(|x| x.as_str())
        .unwrap_or("current");
    let palette_label = if mode == "kde" {
        palette
            .and_then(|x| x.get("colors"))
            .and_then(|x| x.as_str())
            .unwrap_or("")
            .to_string()
    } else {
        palette
            .and_then(|x| x.get("scheme"))
            .and_then(|x| x.as_str())
            .unwrap_or(mode)
            .to_string()
    };
    json!({
        "name": nom,
        "created_at": p.get("created_at").cloned().unwrap_or(json!(0)),
        "wallpaper": p.get("wallpaper").and_then(|w| w.get("file")).cloned().unwrap_or(Value::Null),
        "palette_mode": mode,
        "palette_label": palette_label,
        "icons": p.get("icons").and_then(|i| i.get("theme")).cloned().unwrap_or(json!("")),
        "cursor": p.get("cursor").and_then(|c| c.get("theme")).cloned().unwrap_or(json!("")),
        "cursor_size": p.get("cursor").and_then(|c| c.get("size")).cloned().unwrap_or(json!(24)),
        "env_ref": p.get("env_ref").cloned().unwrap_or(Value::Null),
        "theme_mode": p.get("theme_mode").cloned().unwrap_or(json!("auto")),
    })
}

fn lister() -> Value {
    let profils = lire_profils();
    let mut noms: Vec<&String> = profils
        .keys()
        .filter(|k| k.as_str() != CLE_AVANT && k.as_str() != CLE_ACTIF)
        .collect();
    noms.sort();
    let liste: Vec<Value> = noms
        .into_iter()
        .map(|n| resume(n, &profils[n]))
        .collect();
    let avant = profils
        .get(CLE_AVANT)
        .map(|p| resume(CLE_AVANT, p))
        .unwrap_or(Value::Null);
    let actif = profils.get(CLE_ACTIF).cloned().unwrap_or(Value::Null);
    json!({ "ok": true, "profils": liste, "avant": avant, "actif": actif })
}

/// Diff lisible entre le style courant et celui qu'un profil appliquerait :
/// sert à `--dry-run` et à l'affichage « ce profil n'a rien changé ».
fn diff_style(style: &Map<String, Value>, profil: &Value) -> Vec<Value> {
    let Some(clés) = profil.get("style").and_then(|v| v.as_object()) else {
        return Vec::new();
    };
    let mut diff = Vec::new();
    for &k in PRESET_STYLE_KEYS {
        let Some(apres) = clés.get(k) else { continue };
        let avant = style.get(k).cloned().unwrap_or(Value::Null);
        if &avant != apres {
            diff.push(json!({ "cle": k, "avant": avant, "apres": apres }));
        }
    }
    // L'axe clair/sombre n'est pas dans `style` : on l'annonce à part.
    if let Some(m) = profil.get("theme_mode").and_then(|v| v.as_str()) {
        if (m == "light" || m == "dark")
            && style.get("theme_mode").and_then(|v| v.as_str()) != Some(m)
        {
            diff.push(json!({
                "cle": "theme_mode",
                "avant": style.get("theme_mode").cloned().unwrap_or(json!("auto")),
                "apres": m,
            }));
        }
    }

    // La palette n'est pas une clé de style pour matugen : on l'annonce à part.
    if let Some(pal) = profil.get("palette") {
        let mode = pal.get("mode").and_then(|m| m.as_str()).unwrap_or("");
        if mode == "matugen" {
            let scheme = pal.get("scheme").cloned().unwrap_or(json!(""));
            if style.get("matugen_scheme") != Some(&scheme) {
                diff.push(json!({ "cle": "matugen_scheme", "avant": style.get("matugen_scheme").cloned().unwrap_or(Value::Null), "apres": scheme }));
            }
        }
    }
    diff
}

/// Chemin réel du fond : d'abord `<wallpaper_dir>/<file>` (règle portable), puis
/// le chemin absolu capturé. Absent = canal sauté, jamais une erreur fatale.
fn resoudre_wallpaper(profil: &Value, style: &Map<String, Value>) -> Option<PathBuf> {
    let w = profil.get("wallpaper")?;
    let fichier = w.get("file").and_then(|f| f.as_str()).unwrap_or("").trim();
    let dossier = style
        .get("wallpaper_dir")
        .and_then(|d| d.as_str())
        .unwrap_or("")
        .trim_end_matches('/')
        .to_string();
    if !fichier.is_empty() && !dossier.is_empty() {
        let candidat = PathBuf::from(format!("{dossier}/{fichier}"));
        if candidat.is_file() {
            return Some(candidat);
        }
    }
    if let Some(src) = w.get("source").and_then(|s| s.as_str()) {
        let p = PathBuf::from(src);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

fn ecrire_wallpaper_courant(path: &PathBuf) {
    let cache = quickshell_cache_dir().join("hyprquickpaper");
    let _ = fs::create_dir_all(&cache);
    let _ = fs::write(cache.join(".current"), format!("{}\n", path.display()));
}

/// Applique le style d'un profil et renvoie le style d'avant (pour restauration).
fn ecrire_style_du_profil(
    profil: &Value,
    style: &Map<String, Value>,
) -> Result<Map<String, Value>, String> {
    let avant = style.clone();
    let mut nouveau = style.clone();
    if let Some(cles) = profil.get("style").and_then(|v| v.as_object()) {
        for &k in PRESET_STYLE_KEYS {
            if let Some(v) = cles.get(k) {
                nouveau.insert(k.to_string(), v.clone());
            }
        }
    }
    if let Some(pal) = profil.get("palette") {
        match pal.get("mode").and_then(|m| m.as_str()).unwrap_or("") {
            "matugen" => {
                nouveau.insert("active_theme".into(), json!("dynamic"));
                if let Some(s) = pal.get("scheme") {
                    nouveau.insert("matugen_scheme".into(), s.clone());
                }
                if let Some(c) = pal.get("contrast") {
                    nouveau.insert("matugen_contrast".into(), c.clone());
                }
            }
            "kde" => {
                if let Some(c) = pal.get("colors") {
                    nouveau.insert("active_theme".into(), c.clone());
                }
            }
            _ => {}
        }
    }
    // `auto` laisse l'axe tel quel : un preset ne doit pas défaire un choix
    // explicite de l'utilisateur quand il ne se prononce pas.
    if let Some(m) = profil.get("theme_mode").and_then(|v| v.as_str()) {
        if m == "light" || m == "dark" {
            nouveau.insert("theme_mode".into(), json!(m));
        }
    }
    write_json_atomic(&style_vars_path(), &nouveau, 0o644)
        .map_err(|e| format!("écriture style_vars : {e}"))?;
    Ok(avant)
}

fn restorer_style(avant: &Map<String, Value>) -> Result<(), String> {
    write_json_atomic(&style_vars_path(), avant, 0o644)
        .map_err(|e| format!("restauration du style impossible : {e}"))
}

fn action_sur_profil(nom: &str) -> Option<Value> {
    lire_profils().get(nom).cloned()
}

fn enregistrer(nom: &str, env_ref: Option<String>) -> Value {
    let nom = nom.trim();
    if nom.is_empty() || nom == CLE_AVANT || nom == CLE_ACTIF {
        return json!({ "ok": false, "error": "Nom de profil vide ou réservé" });
    }
    let style = style_actuel();
    // Un profil existant conserve sa référence d'environnement sauf si une
    // nouvelle est fournie : mettre à jour les couleurs ne doit pas casser le
    // lien vers « Focus » / « nuit ».
    let ref_finale = match env_ref {
        Some(r) => Some(r),
        None => action_sur_profil(nom)
            .and_then(|p| p.get("env_ref").and_then(|v| v.as_str()).map(|s| s.to_string())),
    };
    let profil = capturer(&style, ref_finale);
    let mut profils = lire_profils();
    profils.insert(nom.to_string(), profil.clone());
    if let Err(e) = ecrire_profils(&profils) {
        return json!({ "ok": false, "error": e });
    }
    json!({
        "ok": true,
        "message": format!("Profil « {nom} » enregistré"),
        "profil": resume(nom, &profil),
    })
}

fn appliquer(nom: &str, seche: bool) -> Value {
    let nom = nom.trim();
    let Some(profil) = action_sur_profil(nom) else {
        return json!({ "ok": false, "error": format!("Profil « {nom} » introuvable") });
    };
    let style = style_actuel();

    if seche {
        return json!({
            "ok": true,
            "dry_run": true,
            "profil": resume(nom, &profil),
            "diff": diff_style(&style, &profil),
        });
    }

    // 1. Archive de l'état courant : c'est ce que `undo` restaurera.
    let mut profils = lire_profils();
    profils.insert(CLE_AVANT.to_string(), capturer(&style, None));
    if let Err(e) = ecrire_profils(&profils) {
        return json!({ "ok": false, "error": e });
    }

    // 2. Style : seule étape réellement fatale (une palette peut échouer, pas le
    //    style). En cas d'échec, rien d'autre n'est tenté.
    let avant = match ecrire_style_du_profil(&profil, &style) {
        Ok(a) => a,
        Err(e) => return json!({ "ok": false, "error": e }),
    };
    let mut canaux: Vec<Value> = Vec::new();

    // 3. Fond d'écran (non fatal : sans `awww-daemon` c'est un no-op silencieux).
    let wallpaper = resoudre_wallpaper(&profil, &style);
    if let Some(path) = &wallpaper {
        let ok = run_cmd("awww", &["img", &path.to_string_lossy(), "-t", "fade", "--transition-duration", "1"])
            .map(|o| o.status.success())
            .unwrap_or(false);
        if ok {
            ecrire_wallpaper_courant(path);
        }
        canaux.push(json!({ "canal": "wallpaper", "ok": ok, "detail": path.to_string_lossy() }));
    } else if profil.get("wallpaper").is_some() {
        canaux.push(json!({
            "canal": "wallpaper", "ok": false,
            "detail": "fichier absent du dossier des fonds : re-copier depuis ~/.config/quickshell/wallpapers/"
        }));
    }

    // 4. Palette.
    let mode = profil
        .get("palette")
        .and_then(|p| p.get("mode"))
        .and_then(|m| m.as_str())
        .unwrap_or("current")
        .to_string();
    match mode.as_str() {
        "matugen" => {
            let script = core_dir().join("generate_colors.sh");
            let cible = wallpaper.clone();
            let ok = if script.is_file() {
                match &cible {
                    Some(p) => run_cmd("bash", &[&script.to_string_lossy(), &p.to_string_lossy()]),
                    None => run_cmd("bash", &[&script.to_string_lossy()]),
                }
                .map(|o| o.status.success())
                .unwrap_or(false)
            } else {
                false
            };
            canaux.push(json!({
                "canal": "palette-matugen", "ok": ok,
                "detail": if ok { "palette régénérée".to_string() } else { "matugen ou generate_colors.sh indisponible".to_string() }
            }));
        }
        "kde" => {
            let couleurs = profil
                .get("palette")
                .and_then(|p| p.get("colors"))
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            let ok = !couleurs.is_empty()
                && run_cmd(&exe(), &["theme-manager", &couleurs])
                    .map(|o| o.status.success())
                    .unwrap_or(false);
            canaux.push(json!({
                "canal": "palette-kde", "ok": ok,
                "detail": if ok { couleurs } else { format!("palette « {couleurs} » introuvable sur cette machine") }
            }));
        }
        _ => canaux.push(json!({ "canal": "palette", "ok": true, "detail": "inchangée" })),
    }

    // 5. Échec fatal de palette : arrêt AVANT les icônes et le curseur, sinon un
    //    thème refusé laisserait quand même un autre jeu d'icônes et un autre
    //    pointeur derrière lui. Le style est restauré, les canaux déjà tentés
    //    (fond uniquement) sont rapportés.
    let palette_ok = canaux
        .iter()
        .find(|c| {
            c.get("canal")
                .and_then(|n| n.as_str())
                .map(|n| n.starts_with("palette"))
                .unwrap_or(false)
        })
        .and_then(|c| c.get("ok").and_then(|o| o.as_bool()))
        .unwrap_or(true);
    if !palette_ok {
        let restauration = restorer_style(&avant).is_ok();
        return json!({
            "ok": false,
            "error": "palette non appliquée : style d'avant restauré, icônes et curseur non touchés",
            "restaure": restauration,
            "canaux": canaux,
        });
    }

    // 6. Icônes et curseur : filtrables par les interrupteurs globaux Q4.
    let appliquer_icones = style.get("theme_apply_icons").and_then(|v| v.as_bool()).unwrap_or(true);
    let icones = profil
        .get("icons")
        .and_then(|i| i.get("theme"))
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_string();
    if !icones.is_empty() {
        if appliquer_icones {
            let ok = run_cmd(&exe(), &["icones", "apply", &icones])
                .map(|o| o.status.success())
                .unwrap_or(false);
            canaux.push(json!({ "canal": "icones", "ok": ok, "detail": icones }));
        } else {
            canaux.push(json!({ "canal": "icones", "ok": true, "detail": "désactivé par theme_apply_icons" }));
        }
    }

    let appliquer_curseur = style.get("theme_apply_cursor").and_then(|v| v.as_bool()).unwrap_or(true);
    let (curseur, taille) = {
        let c = profil.get("cursor");
        (
            c.and_then(|x| x.get("theme")).and_then(|t| t.as_str()).unwrap_or("").to_string(),
            c.and_then(|x| x.get("size")).and_then(|s| s.as_u64()).unwrap_or(24),
        )
    };
    if !curseur.is_empty() {
        if appliquer_curseur {
            let ok = run_cmd(&exe(), &["curseurs", "apply", &curseur, &taille.to_string()])
                .map(|o| o.status.success())
                .unwrap_or(false);
            canaux.push(json!({ "canal": "curseur", "ok": ok, "detail": format!("{curseur} {taille} px") }));
        } else {
            canaux.push(json!({ "canal": "curseur", "ok": true, "detail": "désactivé par theme_apply_cursor" }));
        }
    }

    // 7. Profil d'environnement référencé : une référence cassée n'échoue jamais
    //    l'application visuelle (arbitrage Q1).
    if let Some(r) = profil.get("env_ref").and_then(|v| v.as_str()) {
        if !r.trim().is_empty() {
            let ok = run_cmd(&exe(), &["config", "preset_apply", r])
                .map(|o| o.status.success())
                .unwrap_or(false);
            canaux.push(json!({
                "canal": "env_ref", "ok": ok,
                "detail": if ok { r.to_string() } else { format!("profil d'environnement « {r} » introuvable") }
            }));
        }
    }

    // Le profil appliqué est noté dans le fichier : le panneau le surligne
    // encore après un redémarrage, sans rejouer quoi que ce soit.
    let mut apres = lire_profils();
    apres.insert(CLE_ACTIF.to_string(), json!(nom));
    let _ = ecrire_profils(&apres);

    json!({
        "ok": true,
        "message": format!("Profil « {nom} » appliqué"),
        "profil": resume(nom, &profil),
        "canaux": canaux,
    })
}

fn supprimer(nom: &str) -> Value {
    let mut profils = lire_profils();
    if profils.remove(nom).is_none() {
        return json!({ "ok": false, "error": format!("Profil « {nom} » introuvable") });
    }
    if profils.get(CLE_ACTIF).and_then(|v| v.as_str()) == Some(nom) {
        profils.remove(CLE_ACTIF);
    }
    if let Err(e) = ecrire_profils(&profils) {
        return json!({ "ok": false, "error": e });
    }
    json!({ "ok": true, "message": format!("Profil « {nom} » supprimé") })
}

fn annuler() -> Value {
    let profils = lire_profils();
    let Some(avant) = profils.get(CLE_AVANT).cloned() else {
        return json!({ "ok": false, "error": "Aucun état d'avant enregistré" });
    };
    let style = style_actuel();
    match ecrire_style_du_profil(&avant, &style) {
        Ok(_) => {
            // L'état d'avant n'est pas un profil : plus aucun n'est « appliqué ».
            let mut apres = lire_profils();
            apres.remove(CLE_ACTIF);
            let _ = ecrire_profils(&apres);
            json!({ "ok": true, "message": "État d'avant restauré (style ; relancer un thème pour le reste)" })
        }
        Err(e) => json!({ "ok": false, "error": e }),
    }
}

/// Luminance relative approximative d'une couleur `#rrggbb` (formule WCAG).
fn luminance(hex: &str) -> Option<f64> {
    let h = hex.trim().trim_start_matches('#');
    if h.len() < 6 {
        return None;
    }
    let composante = |i: usize| -> Option<f64> {
        let v = u8::from_str_radix(&h[i..i + 2], 16).ok()? as f64 / 255.0;
        Some(if v <= 0.03928 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) })
    };
    let (r, g, b) = (composante(0)?, composante(2)?, composante(4)?);
    Some(0.2126 * r + 0.7152 * g + 0.0722 * b)
}

/// Contrôle de cohérence : avertit (jamais ne bloque) quand le fond et les
/// icônes/curseur se contredisent.
fn verifier(nom: &str) -> Value {
    let Some(profil) = action_sur_profil(nom) else {
        return json!({ "ok": false, "error": format!("Profil « {nom} » introuvable") });
    };
    let mut alertes: Vec<String> = Vec::new();
    let icones = profil
        .get("icons")
        .and_then(|i| i.get("theme"))
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let curseur = profil
        .get("cursor")
        .and_then(|c| c.get("theme"))
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    // Le fond du profil n'est pas analysable sans image : on se rabat sur la
    // palette du style capturé (`palette.<active_theme>.bg`).
    let style = profil.get("style").and_then(|s| s.as_object());
    let theme = style
        .and_then(|s| s.get("active_theme"))
        .and_then(|t| t.as_str())
        .unwrap_or("dynamic");
    let bg = style
        .and_then(|s| s.get("palette"))
        .and_then(|p| p.get(theme))
        .and_then(|t| t.get("bg"))
        .and_then(|b| b.as_str())
        .unwrap_or("");
    let sombre = luminance(bg).map(|l| l < 0.5);

    if let Some(sombre) = sombre {
        let icones_claires = icones.contains("light");
        let icones_sombres = icones.contains("dark");
        if sombre && icones_claires {
            alertes.push(format!("fond sombre ({bg}) avec un jeu d'icônes clair ({icones})"));
        }
        if !sombre && icones_sombres {
            alertes.push(format!("fond clair ({bg}) avec un jeu d'icônes sombre ({icones})"));
        }
        if sombre && curseur.contains("white") {
            alertes.push(format!("fond sombre avec un curseur clair ({curseur}) : contraste faible"));
        }
        if !sombre && curseur.contains("black") {
            alertes.push(format!("fond clair avec un curseur sombre ({curseur}) : contraste faible"));
        }
    }
    if profil.get("wallpaper").is_none() {
        alertes.push("aucun fond d'écran : le profil ne change pas l'arrière-plan".to_string());
    }
    json!({ "ok": true, "profil": nom, "alertes": alertes, "coherent": alertes.is_empty() })
}

fn exporter(nom: &str, chemin: &str) -> Value {
    let Some(profil) = action_sur_profil(nom) else {
        return json!({ "ok": false, "error": format!("Profil « {nom} » introuvable") });
    };
    let charge = json!({
        "_type": "aethershell.theme_profile/1",
        "name": nom,
        "profil": profil,
    });
    let texte = serde_json::to_string_pretty(&charge).unwrap_or_default();
    match fs::write(chemin, texte + "\n") {
        Ok(()) => json!({ "ok": true, "message": format!("Exporté vers {chemin}") }),
        Err(e) => json!({ "ok": false, "error": format!("écriture {chemin} : {e}") }),
    }
}

fn importer(chemin: &str, ecraser: bool) -> Value {
    let Ok(txt) = fs::read_to_string(chemin) else {
        return json!({ "ok": false, "error": format!("Fichier illisible : {chemin}") });
    };
    let Ok(charge) = serde_json::from_str::<Value>(&txt) else {
        return json!({ "ok": false, "error": "JSON invalide" });
    };
    if charge.get("_type").and_then(|t| t.as_str()) != Some("aethershell.theme_profile/1") {
        return json!({ "ok": false, "error": "Ce fichier n'est pas un profil de thème AetherShell" });
    }
    let nom = charge.get("name").and_then(|n| n.as_str()).unwrap_or("").trim().to_string();
    let Some(profil) = charge.get("profil").cloned() else {
        return json!({ "ok": false, "error": "Profil absent du fichier" });
    };
    if nom.is_empty() {
        return json!({ "ok": false, "error": "Nom de profil absent" });
    }
    let mut profils = lire_profils();
    if profils.contains_key(&nom) && !ecraser {
        return json!({ "ok": false, "error": format!("« {nom} » existe déjà (utiliser --force pour remplacer)") });
    }
    profils.insert(nom.clone(), profil);
    match ecrire_profils(&profils) {
        Ok(()) => json!({ "ok": true, "message": format!("Profil « {nom} » importé") }),
        Err(e) => json!({ "ok": false, "error": e }),
    }
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("list");
    let drapeau = |f: &str| args.iter().any(|a| a == f);
    let res = match action {
        "list" => lister(),
        "save" if args.len() > 1 => {
            let env_ref = args.iter().skip(2).find(|a| !a.starts_with("--")).cloned();
            enregistrer(&args[1], env_ref)
        }
        "apply" if args.len() > 1 => appliquer(&args[1], drapeau("--dry-run")),
        "delete" if args.len() > 1 => supprimer(&args[1]),
        "undo" => annuler(),
        "check" if args.len() > 1 => verifier(&args[1]),
        "export" if args.len() > 2 => exporter(&args[1], &args[2]),
        "import" if args.len() > 1 => importer(&args[1], drapeau("--force")),
        _ => json!({
            "ok": false,
            "error": "Action inconnue (list, save <nom> [env_ref], apply <nom> [--dry-run], delete <nom>, undo, check <nom>, export <nom> <chemin>, import <chemin> [--force])"
        }),
    };
    sortir(&res)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn style_vide() -> Map<String, Value> {
        Map::new()
    }

    #[test]
    fn diff_ne_rend_que_les_cles_qui_changent() {
        let mut style = style_vide();
        style.insert("bar_style".into(), json!("classic"));
        style.insert("global_opacity".into(), json!(0.9));
        let profil = json!({
            "style": { "bar_style": "island", "global_opacity": 0.9 },
            "palette": { "mode": "current" }
        });
        let d = diff_style(&style, &profil);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0]["cle"], "bar_style");
        assert_eq!(d[0]["apres"], "island");
    }

    #[test]
    fn palette_matugen_annoncee_dans_le_diff() {
        let mut style = style_vide();
        style.insert("matugen_scheme".into(), json!("scheme-vibrant"));
        let profil = json!({ "style": {}, "palette": { "mode": "matugen", "scheme": "scheme-neutral" } });
        let d = diff_style(&style, &profil);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0]["cle"], "matugen_scheme");
    }

    #[test]
    fn luminance_distingue_clair_et_sombre() {
        assert!(luminance("#000000").unwrap() < 0.01);
        assert!(luminance("#ffffff").unwrap() > 0.99);
        assert!(luminance("#1e1e2e").unwrap() < 0.1);
        assert!(luminance("pas-une-couleur").is_none());
    }

    #[test]
    fn resume_extrait_palette_et_env_ref() {
        let p = json!({
            "created_at": 42,
            "style": {},
            "palette": { "mode": "kde", "colors": "CatppuccinMocha" },
            "icons": { "theme": "Papirus-Dark" },
            "cursor": { "theme": "Vimix-cursors", "size": 28 },
            "env_ref": "nuit"
        });
        let r = resume("Test", &p);
        assert_eq!(r["palette_label"], "CatppuccinMocha");
        assert_eq!(r["cursor_size"], 28);
        assert_eq!(r["env_ref"], "nuit");
    }
}
