//! Palettes : écriture des fichiers de thème et ingestion Matugen.
//!
//! Remplace les heredocs Python de `core/sync_theme.sh` et `core/generate_colors.sh`.
//! `style_vars.json` reste la seule source : la palette active est projetée dans
//! les formats que les autres programmes savent lire — Hyprland (Lua), hyprlock
//! (hyprlang), hyprquickpaper (JSON), terminaux et apps (voir `terminal-theme`).
//!
//! - `as-core theme-sync` : réécrit `colors.lua`, `hyprquickpaper/colors.json`,
//!   `hyprlock-colors.conf` et `hyprlock-bg.conf` depuis la palette active.
//! - `as-core colors-matugen [--file <style_vars>]` : lit la sortie de
//!   `matugen … --json hex` sur l'entrée standard, remplace `palette.dynamic`
//!   et passe `active_theme` à `dynamic` (écriture atomique).

use crate::common::io::{read_json_value, write_json_atomic};
use crate::common::paths::{home_dir, style_vars_path};
use serde_json::{json, Map, Value};
use std::io::Read;
use std::path::PathBuf;

fn style_path_depuis(args: &[String]) -> PathBuf {
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--file" {
            if let Some(p) = args.get(i + 1) {
                return PathBuf::from(p);
            }
        } else if let Some(p) = args[i].strip_prefix("--file=") {
            return PathBuf::from(p);
        }
        i += 1;
    }
    style_vars_path()
}

fn read_map(path: &PathBuf) -> Map<String, Value> {
    match read_json_value(path) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

/// `str(valeur).strip()` comme le faisait Python : un nombre devient son texte.
fn en_texte(v: Option<&Value>, defaut: &str) -> String {
    match v {
        Some(Value::String(s)) => s.trim().to_string(),
        Some(Value::Null) | None => defaut.to_string(),
        Some(autre) => autre.to_string(),
    }
}

fn avec_diese(v: &str) -> String {
    if v.starts_with('#') {
        v.to_string()
    } else {
        format!("#{v}")
    }
}

/// Couleur de la palette active, `#` rétabli (les fichiers historiques en
/// contiennent parfois sans).
fn couleur(p: &Map<String, Value>, cle: &str, defaut: &str) -> String {
    let brut = match p.get(cle) {
        Some(Value::String(s)) if !s.trim().is_empty() => s.trim().to_string(),
        Some(Value::Null) | None => defaut.to_string(),
        Some(autre) => autre.to_string(),
    };
    avec_diese(&brut)
}

fn sans_diese(c: &str) -> &str {
    c.strip_prefix('#').unwrap_or(c)
}

fn palette_active(style: &Map<String, Value>) -> (String, Map<String, Value>) {
    let active = match style.get("active_theme").and_then(|v| v.as_str()) {
        Some(s) if !s.trim().is_empty() => s.trim().to_string(),
        _ => "dynamic".to_string(),
    };
    let palettes = match style.get("palette") {
        Some(Value::Object(m)) => m.clone(),
        _ => Map::new(),
    };
    let choisie = match palettes.get(&active) {
        Some(Value::Object(m)) => m.clone(),
        _ => match palettes.get("dynamic") {
            Some(Value::Object(m)) => m.clone(),
            _ => Map::new(),
        },
    };
    (active, choisie)
}

fn ecrire(chemin: &PathBuf, contenu: &str) {
    if let Some(parent) = chemin.parent() {
        if !parent.is_dir() {
            return;
        }
    }
    let _ = std::fs::write(chemin, contenu);
}

/// Écrit `colors.lua` pour Hyprland : bordures, arrondis et opacité.
fn ecrire_colors_lua(style: &Map<String, Value>, p: &Map<String, Value>) {
    let accent = couleur(p, "accent", "#b4befe");
    let surface_var = couleur(p, "surface_variant", "#45475a");
    let radius = en_texte(style.get("global_radius"), "2");
    let opacity = en_texte(style.get("global_opacity"), "0.85");

    // Le dépôt écrit dans sa propre config Hyprland ; le déploiement écrit dans
    // celle de la session. Même règle que l'ancien script : la racine de la
    // coquille décide.
    let home = home_dir();
    let qs = home.join(".config/quickshell");
    let core = crate::common::paths::core_dir();
    let cible = if core.starts_with(&qs) {
        home.join(".config/hypr/colors.lua")
    } else {
        core.parent()
            .map(|d| d.join("hypr_modular/colors.lua"))
            .unwrap_or_else(|| home.join(".config/hypr/colors.lua"))
    };
    let contenu = format!(
        "-- ~/.config/hypr/colors.lua\n\
         -- Généré automatiquement via Matugen / style_vars.json\n\
         -- Applique la palette active aux bordures, arrondis et à l'opacité de Hyprland\n\
         \n\
         hl.config({{\n    \
             general = {{\n        \
                 col = {{\n            \
                     active_border   = \"rgba({}ee)\",\n            \
                     inactive_border = \"rgba({}aa)\",\n        \
                 }},\n    \
             }},\n    \
             decoration = {{\n        \
                 rounding         = {},\n        \
                 active_opacity   = {},\n        \
                 inactive_opacity = {},\n    \
             }},\n\
         }})\n",
        sans_diese(&accent),
        sans_diese(&surface_var),
        radius,
        opacity,
        opacity
    );
    ecrire(&cible, &contenu);
}

fn ecrire_hyprquickpaper(p: &Map<String, Value>) {
    let accent = couleur(p, "accent", "#b4befe");
    let dir = home_dir().join(".config/quickshell/hyprquickpaper");
    if !dir.is_dir() {
        return;
    }
    let contenu = format!("{{\n    \"border_color\": \"{accent}\"\n}}\n");
    ecrire(&dir.join("colors.json"), &contenu);
}

/// hyprlock ne lit ni le Lua de Hyprland ni le JSON du shell : la palette lui est
/// écrite en variables hyprlang. `hyprlock.conf` ne contient que ces noms, jamais
/// une couleur en dur.
fn ecrire_hyprlock(p: &Map<String, Value>) {
    let dir = home_dir().join(".config/hypr");
    if !dir.is_dir() {
        return;
    }
    let fg = couleur(p, "fg", "#cdd6f4");
    let accent = couleur(p, "accent", "#b4befe");
    let accent_muted = couleur(p, "accent_muted", "#89b4fa");
    let surface = couleur(p, "surface", "#313244");
    let error = couleur(p, "error", "#f38ba8");
    let warn = couleur(p, "warn", "#fab387");
    let bg = couleur(p, "bg", "#1e1e2e");

    let contenu = format!(
        "# Généré par core/sync_theme.sh depuis style_vars.json — ne pas éditer.\n\
         # Lu par hyprlock.conf : source = ~/.config/hypr/hyprlock-colors.conf\n\
         \n\
         $bg = rgb({})\n\
         $fg = rgb({})\n\
         $fg_soft = rgba({}b3)\n\
         $fg_dim = rgba({}80)\n\
         $accent = rgb({})\n\
         $accent_muted = rgb({})\n\
         $surface = rgb({})\n\
         $surface_glass = rgba({}8c)\n\
         $outline = rgba({}59)\n\
         $error = rgb({})\n\
         $warn = rgb({})\n",
        sans_diese(&bg),
        sans_diese(&fg),
        sans_diese(&fg),
        sans_diese(&fg),
        sans_diese(&accent),
        sans_diese(&accent_muted),
        sans_diese(&surface),
        sans_diese(&surface),
        sans_diese(&accent),
        sans_diese(&error),
        sans_diese(&warn)
    );
    ecrire(&dir.join("hyprlock-colors.conf"), &contenu);
}

fn ecrire_hyprlock_bg(style: &Map<String, Value>) {
    let dir = home_dir().join(".config/hypr");
    if !dir.is_dir() {
        return;
    }
    let mode = {
        let m = en_texte(style.get("lock_bg_mode"), "solid");
        if m.is_empty() { "solid".to_string() } else { m }
    };
    let color_raw = en_texte(style.get("lock_bg_color"), "");
    let img_raw = en_texte(style.get("lock_bg_image"), "");

    let mut color_line = "    color = $bg".to_string();
    if !color_raw.is_empty() {
        let c = sans_diese(color_raw.trim());
        if c.len() == 6 {
            color_line = format!("    color = rgb({c})");
        }
    }
    let mut lignes: Vec<String> = vec![
        "# Généré par core/sync_theme.sh depuis style_vars.json — ne pas éditer.".into(),
        "# Lu par hyprlock.conf : source = ~/.config/hypr/hyprlock-bg.conf".into(),
        String::new(),
        "background {".into(),
        "    monitor =".into(),
        color_line,
    ];
    if mode == "image" && !img_raw.is_empty() {
        let chemin = crate::common::paths::expand_home(&img_raw);
        if chemin.is_file() {
            lignes.push(format!("    path = {}", chemin.display()));
        }
    }
    lignes.push("    blur_passes = 0".into());
    lignes.push("}".into());
    lignes.push(String::new());
    ecrire(&dir.join("hyprlock-bg.conf"), &lignes.join("\n"));
}

pub fn run_sync(args: &[String]) -> i32 {
    let chemin = style_path_depuis(args);
    if !chemin.is_file() {
        eprintln!("style_vars.json not found at {}", chemin.display());
        return 1;
    }
    let style = read_map(&chemin);
    let (_active, p) = palette_active(&style);

    ecrire_colors_lua(&style, &p);
    ecrire_hyprquickpaper(&p);
    ecrire_hyprlock(&p);
    ecrire_hyprlock_bg(&style);
    0
}

/// Variante de jeton à lire. Matugen publie le même jeton en `dark`, `light` et
/// `default` ; `default` suit le mode qu'il a résolu. Un mode explicite
/// (`theme_mode` dans `style_vars.json`, sinon `mode`/`is_dark_mode` de la
/// sortie) tranche ; sans indication on lit `default` d'abord, puis `dark`
/// comme avant, pour ne rien changer aux machines existantes.
fn variante_matugen(style: &Map<String, Value>, matugen: &Value) -> String {
    if let Some(m) = style.get("theme_mode").and_then(|v| v.as_str()) {
        if m == "light" || m == "dark" {
            return m.to_string();
        }
    }
    if let Some(m) = matugen.get("mode").and_then(|v| v.as_str()) {
        if m == "light" || m == "dark" {
            return m.to_string();
        }
    }
    match matugen.get("is_dark_mode").and_then(|v| v.as_bool()) {
        Some(true) => "dark".to_string(),
        Some(false) => "light".to_string(),
        None => "default".to_string(),
    }
}

/// Ordre de lecture des variantes pour un jeton.
fn ordre_variantes(variante: &str) -> [&'static str; 3] {
    match variante {
        "light" => ["light", "default", "dark"],
        "dark" => ["dark", "default", "light"],
        _ => ["default", "dark", "light"],
    }
}

/// Couleur d'un jeton Matugen : `{"dark": {"color": "#…"}}`, `{"dark": "#…"}` ou
/// `"#…"`, selon la version de Matugen et le format demandé.
fn jeton(colors: &Map<String, Value>, token: &str, defaut: &str, variante: &str) -> String {
    let val = match colors.get(token) {
        Some(v) => v,
        None => return defaut.to_string(),
    };
    let candidat = match val {
        Value::Object(m) => {
            let mut trouve = None;
            for cle in ordre_variantes(variante) {
                match m.get(cle) {
                    Some(Value::Object(inner)) => {
                        trouve = inner
                            .get("color")
                            .or_else(|| inner.get("hex"))
                            .and_then(|v| v.as_str())
                            .map(str::to_string);
                    }
                    Some(Value::String(s)) => trouve = Some(s.clone()),
                    _ => {}
                }
                if trouve.is_some() {
                    break;
                }
            }
            trouve
        }
        Value::String(s) => Some(s.clone()),
        _ => None,
    };
    match candidat {
        Some(c) => {
            let c = c.trim().to_string();
            if c.is_empty() {
                defaut.to_string()
            } else {
                avec_diese(&c)
            }
        }
        None => defaut.to_string(),
    }
}

pub fn run_matugen(args: &[String]) -> i32 {
    let mut brut = String::new();
    // La sortie de Matugen arrive par l'entrée standard ; un argument JSON reste
    // accepté pour les essais (`--json '<sortie>'`).
    if let Some(pos) = args.iter().position(|a| a == "--json") {
        if let Some(v) = args.get(pos + 1) {
            brut = v.clone();
        }
    }
    if brut.is_empty() {
        if std::io::stdin().read_to_string(&mut brut).is_err() {
            eprintln!("colors-matugen : entrée illisible");
            return 1;
        }
    }
    let matugen: Value = match serde_json::from_str(&brut) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("colors-matugen : JSON Matugen invalide ({e})");
            return 1;
        }
    };
    let vide = Map::new();
    let colors = match matugen.get("colors") {
        Some(Value::Object(m)) => m,
        _ => &vide,
    };

    let chemin = style_path_depuis(args);
    let mut style = read_map(&chemin);
    let variante = variante_matugen(&style, &matugen);
    let mut palette = Map::new();
    palette.insert("bg".into(), json!(jeton(colors, "surface_container_lowest", "#1e1e2e", &variante)));
    palette.insert("fg".into(), json!(jeton(colors, "on_surface", "#cdd6f4", &variante)));
    palette.insert("accent".into(), json!(jeton(colors, "primary", "#b4befe", &variante)));
    palette.insert("accent_muted".into(), json!(jeton(colors, "secondary", "#89b4fa", &variante)));
    palette.insert("surface".into(), json!(jeton(colors, "surface", "#313244", &variante)));
    palette.insert("surface_variant".into(), json!(jeton(colors, "surface_container", "#45475a", &variante)));
    palette.insert("error".into(), json!(jeton(colors, "error", "#f38ba8", &variante)));
    palette.insert("warn".into(), json!(jeton(colors, "tertiary", "#fab387", &variante)));
    palette.insert("info".into(), json!(jeton(colors, "secondary", "#89b4fa", &variante)));
    palette.insert("success".into(), json!(jeton(colors, "tertiary_fixed_dim", "#a6e3a1", &variante)));

    let mut palettes = match style.remove("palette") {
        Some(Value::Object(m)) => m,
        _ => Map::new(),
    };
    palettes.insert("dynamic".into(), Value::Object(palette));
    style.insert("palette".into(), Value::Object(palettes));
    style.insert("active_theme".into(), json!("dynamic"));

    // Écriture atomique : la palette est relue en continu par le shell (FileView).
    // Un fichier tronqué lui ferait perdre toutes ses couleurs.
    if let Err(e) = write_json_atomic(&chemin, &Value::Object(style), 0o644) {
        eprintln!("colors-matugen : écriture impossible ({e})");
        return 1;
    }
    println!("Dynamic palette updated in {}", chemin.display());
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn map(v: Value) -> Map<String, Value> {
        match v {
            Value::Object(m) => m,
            _ => Map::new(),
        }
    }

    #[test]
    fn jeton_lit_les_trois_formes_de_matugen() {
        let colors = map(json!({
            "primary": { "dark": { "color": "#ff0000" } },
            "secondary": { "dark": "#00ff00" },
            "tertiary": "0000ff",
        }));
        assert_eq!(jeton(&colors, "primary", "#111111", "dark"), "#ff0000");
        assert_eq!(jeton(&colors, "secondary", "#111111", "dark"), "#00ff00");
        assert_eq!(jeton(&colors, "tertiary", "#111111", "dark"), "#0000ff");
        assert_eq!(jeton(&colors, "absent", "#111111", "dark"), "#111111");
    }

    #[test]
    fn variante_claire_lit_les_jetons_light() {
        let colors = map(json!({
            "surface": { "dark": { "color": "#1e100d" }, "light": { "color": "#fff8f6" } },
            "primary": { "dark": { "color": "#ffb4a5" }, "light": { "color": "#ba1c00" } },
        }));
        assert_eq!(jeton(&colors, "surface", "#000000", "light"), "#fff8f6");
        assert_eq!(jeton(&colors, "surface", "#000000", "dark"), "#1e100d");
        assert_eq!(jeton(&colors, "primary", "#000000", "auto"), "#ffb4a5");
    }

    #[test]
    fn mode_explicite_prime_sur_la_sortie_matugen() {
        let matugen = json!({ "mode": "light", "is_dark_mode": false });
        let force = map(json!({ "theme_mode": "dark" }));
        assert_eq!(variante_matugen(&force, &matugen), "dark");
        let auto = map(json!({ "theme_mode": "auto" }));
        assert_eq!(variante_matugen(&auto, &matugen), "light");
        let muet = map(json!({}));
        assert_eq!(variante_matugen(&muet, &matugen), "light");
    }

    #[test]
    fn couleur_ajoute_le_diese_absent() {
        let p = map(json!({ "accent": "ffacec", "fg": "#cdd6f4" }));
        assert_eq!(couleur(&p, "accent", "#000000"), "#ffacec");
        assert_eq!(couleur(&p, "fg", "#000000"), "#cdd6f4");
        assert_eq!(couleur(&p, "manquante", "#b4befe"), "#b4befe");
    }

    #[test]
    fn palette_active_retombe_sur_dynamic() {
        let style = map(json!({
            "active_theme": "tokyo-night",
            "palette": { "dynamic": { "accent": "#010203" } }
        }));
        let (nom, p) = palette_active(&style);
        assert_eq!(nom, "tokyo-night");
        assert_eq!(couleur(&p, "accent", "#000000"), "#010203");
    }
}
