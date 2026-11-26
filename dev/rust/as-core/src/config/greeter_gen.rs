//! Génère le thème de connexion de la session (sddm-astronaut re-coloré).
//!
//! Port de `dev/sddm/generate.py`. Sorties, dans `<dev>/sddm/out/` :
//!   `Themes/palette.conf`       — configuration complète du thème (couleurs)
//!   `Backgrounds/wallpaper.png` — wallpaper courant assombri, à la taille de l'écran
//!
//! Sources, jamais dupliquées :
//!   `core/style_vars.json`  (palette active)
//!   `awww query`            (wallpaper réellement affiché)
//!   `hyprctl monitors -j`   (taille logique de l'écran focalisé)
//!
//! Aucun fichier n'est écrit hors de `out/` : poser le thème dans
//! `/usr/share/sddm/themes/` est le rôle de `dev/sddm/install.sh` (polkit).
//!
//! `GREETER_SCREEN=WxH` force la taille d'écran (hors session : ssh, tty).
//! `--no-background` réécrit la conf sans retoucher le fond.

use crate::common::io::{read_json_value, run_cmd};
use crate::common::paths::{config_dir, style_vars_path};
use serde_json::Value;
use std::path::{Path, PathBuf};

const ECRAN_REPLI: (u32, u32) = (1920, 1080);

struct Palette {
    bg: String,
    fg: String,
    accent: String,
    accent_muted: String,
    surface: String,
    surface_variant: String,
    error: String,
}

fn die(msg: &str) -> i32 {
    eprintln!("gen-palette: {msg}");
    1
}

fn texte(v: Option<&Value>, defaut: &str) -> String {
    match v.and_then(|x| x.as_str()) {
        Some(s) if !s.is_empty() => s.to_string(),
        _ => defaut.to_string(),
    }
}

/// Taille logique de l'écran focalisé, pour que le greeter ne soit pas calé sur
/// le moniteur du desktop.
fn taille_ecran() -> (u32, u32) {
    if let Ok(force) = std::env::var("GREETER_SCREEN") {
        let force = force.trim().to_string();
        let parts: Vec<&str> = force.split('x').collect();
        if parts.len() == 2 {
            let ok = |s: &str| (3..=5).contains(&s.len()) && s.chars().all(|c| c.is_ascii_digit());
            if ok(parts[0]) && ok(parts[1]) {
                if let (Ok(w), Ok(h)) = (parts[0].parse(), parts[1].parse()) {
                    return (w, h);
                }
            }
        }
    }
    let brut = match run_cmd("hyprctl", &["monitors", "-j"]) {
        Some(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => return ECRAN_REPLI,
    };
    let monitors: Value = match serde_json::from_str(&brut) {
        Ok(v) => v,
        Err(_) => return ECRAN_REPLI,
    };
    let liste = match monitors.as_array() {
        Some(l) if !l.is_empty() => l,
        _ => return ECRAN_REPLI,
    };
    let mon = liste
        .iter()
        .find(|m| m.get("focused").and_then(|f| f.as_bool()) == Some(true))
        .unwrap_or(&liste[0]);
    let w = mon.get("width").and_then(|v| v.as_i64()).unwrap_or(0);
    let h = mon.get("height").and_then(|v| v.as_i64()).unwrap_or(0);
    if w <= 0 || h <= 0 {
        return ECRAN_REPLI;
    }
    // `width`/`height` sont logiques : le greeter s'affiche hors compositeur et
    // ne reçoit aucun facteur d'échelle, on repasse donc en pixels physiques.
    let scale = mon
        .get("scale")
        .and_then(|v| v.as_f64())
        .filter(|s| *s > 0.0)
        .unwrap_or(1.0);
    (
        arrondi_pair(w as f64 * scale) as u32,
        arrondi_pair(h as f64 * scale) as u32,
    )
}

/// La palette de la **session déployée** fait foi : `generate.py` lisait
/// `~/.config/quickshell/core/style_vars.json` et non la copie du dépôt, pour
/// que l'écran de connexion suive les couleurs réellement actives.
fn style_vars_session() -> PathBuf {
    let deploye = config_dir().join("quickshell/core/style_vars.json");
    if deploye.exists() {
        deploye
    } else {
        style_vars_path()
    }
}

fn charger_palette() -> Result<(String, Palette), String> {
    let chemin = style_vars_session();
    if !chemin.exists() {
        return Err(format!("{} introuvable", chemin.display()));
    }
    let data = read_json_value(&chemin);
    let palettes = data.get("palette").cloned().unwrap_or(Value::Null);
    let nom = texte(data.get("active_theme"), "dynamic");
    let palette = palettes
        .get(&nom)
        .filter(|p| p.is_object())
        .or_else(|| palettes.get("dynamic"))
        .cloned()
        .unwrap_or(Value::Null);
    if !palette.is_object() {
        return Err("aucune palette dans style_vars.json".to_string());
    }
    let champ = |cle: &str| texte(palette.get(cle), "");
    let accent = champ("accent");
    let accent_muted = match palette.get("accent_muted").and_then(|v| v.as_str()) {
        Some(s) if !s.is_empty() => s.to_string(),
        _ => accent.clone(),
    };
    Ok((
        nom,
        Palette {
            bg: champ("bg"),
            fg: champ("fg"),
            accent,
            accent_muted,
            surface: champ("surface"),
            surface_variant: champ("surface_variant"),
            error: champ("error"),
        },
    ))
}

/// Arrondi « au pair » : c'est celui de `round()` en Python, et l'alpha d'une
/// couleur doit rester identique octet pour octet à l'ancienne sortie.
fn arrondi_pair(x: f64) -> f64 {
    let bas = x.floor();
    let frac = x - bas;
    if (frac - 0.5).abs() < 1e-9 {
        if (bas as i64) % 2 == 0 {
            bas
        } else {
            bas + 1.0
        }
    } else {
        x.round()
    }
}

/// `#RRGGBB` + alpha 0..1 → `#AARRGGBB` (format accepté par QML).
fn avec_alpha(hexcolor: &str, alpha: f64) -> String {
    let h = hexcolor.trim_start_matches('#').to_uppercase();
    let a = arrondi_pair(alpha.clamp(0.0, 1.0) * 255.0) as u32;
    format!("#{a:02X}{h}")
}

fn construire_conf(p: &Palette, ecran: (u32, u32)) -> String {
    let fg = &p.fg;
    let accent = &p.accent;
    let colors: Vec<(&str, String)> = vec![
        ("TimeTextColor", fg.clone()),
        ("DateTextColor", avec_alpha(fg, 0.70)),
        ("HeaderTextColor", accent.clone()),
        ("FormBackgroundColor", p.surface.clone()),
        ("BackgroundColor", p.bg.clone()),
        ("DimBackgroundColor", p.bg.clone()),
        ("LoginFieldBackgroundColor", p.accent_muted.clone()),
        ("PasswordFieldBackgroundColor", p.accent_muted.clone()),
        ("LoginFieldTextColor", fg.clone()),
        ("PasswordFieldTextColor", fg.clone()),
        ("UserIconColor", p.accent_muted.clone()),
        ("PasswordIconColor", p.accent_muted.clone()),
        ("PlaceholderTextColor", avec_alpha(fg, 0.55)),
        ("WarningColor", p.error.clone()),
        ("LoginButtonTextColor", p.bg.clone()),
        ("LoginButtonBackgroundColor", accent.clone()),
        ("SystemButtonsIconsColor", avec_alpha(fg, 0.70)),
        ("SessionButtonTextColor", avec_alpha(fg, 0.60)),
        ("VirtualKeyboardButtonTextColor", avec_alpha(fg, 0.60)),
        ("DropdownTextColor", p.bg.clone()),
        ("DropdownSelectedBackgroundColor", accent.clone()),
        ("DropdownBackgroundColor", p.accent_muted.clone()),
        ("HighlightTextColor", p.bg.clone()),
        ("HighlightBackgroundColor", accent.clone()),
        ("HighlightBorderColor", "transparent".to_string()),
        ("HoverUserIconColor", accent.clone()),
        ("HoverPasswordIconColor", accent.clone()),
        ("HoverSystemButtonsIconsColor", accent.clone()),
        ("HoverSessionButtonTextColor", accent.clone()),
        ("HoverVirtualKeyboardButtonTextColor", accent.clone()),
    ];
    let _ = &p.surface_variant; // la variante de surface n'est pas exposée par le thème

    let (w, h) = ecran;
    let mut lignes: Vec<String> = vec![
        "[General]".into(),
        "#################### Généré par as-core greeter gen-palette — ne pas éditer ####################"
            .into(),
        String::new(),
        format!("ScreenWidth=\"{w}\""),
        format!("ScreenHeight=\"{h}\""),
        "ScreenPadding=\"\"".into(),
        String::new(),
        "Font=\"Inter\"".into(),
        "FontSize=\"13\"".into(),
        "KeyboardSize=\"0.4\"".into(),
        "RoundCorners=\"24\"".into(),
        String::new(),
        "Locale=\"fr_FR.UTF-8\"".into(),
        "HourFormat=\"HH:mm\"".into(),
        "DateFormat=\"dddd d\"".into(),
        "HeaderText=\"\"".into(),
        String::new(),
        "#################### Fond ####################".into(),
        String::new(),
        "Background=\"Backgrounds/wallpaper.png\"".into(),
        "BackgroundPlaceholder=\"\"".into(),
        "BackgroundSpeed=\"1.0\"".into(),
        "PauseBackground=\"\"".into(),
        "DimBackground=\"0.20\"".into(),
        "CropBackground=\"true\"".into(),
        "BackgroundHorizontalAlignment=\"center\"".into(),
        "BackgroundVerticalAlignment=\"center\"".into(),
        String::new(),
        "#################### Couleurs ####################".into(),
        String::new(),
    ];
    for (cle, valeur) in colors {
        lignes.push(format!("{cle}=\"{valeur}\""));
    }
    lignes.extend(
        [
            "",
            "#################### Formulaire ####################",
            "",
            "PartialBlur=\"true\"",
            "FullBlur=\"\"",
            "BlurMax=\"32\"",
            "Blur=\"1.6\"",
            "HaveFormBackground=\"true\"",
            "FormPosition=\"center\"",
            "VirtualKeyboardPosition=\"left\"",
            "",
            "#################### Comportement ####################",
            "",
            "HideVirtualKeyboard=\"false\"",
            "HideSystemButtons=\"false\"",
            "HideLoginButton=\"false\"",
            "UseRealName=\"false\"",
            "ForceLastUser=\"true\"",
            "PasswordFocus=\"true\"",
            "HideCompletePassword=\"true\"",
            "AllowEmptyPassword=\"false\"",
            "BypassSystemButtonsChecks=\"false\"",
            "RightToLeftLayout=\"false\"",
            "",
            "#################### Libellés ####################",
            "",
            "TranslatePlaceholderUsername=\"\"",
            "TranslatePlaceholderPassword=\"Mot de passe\"",
            "TranslateLogin=\"Se connecter\"",
            "TranslateLoginFailedWarning=\"Mot de passe incorrect\"",
            "TranslateCapslockWarning=\"Verr. Maj activée\"",
            "TranslateSuspend=\"Veille\"",
            "TranslateHibernate=\"Hiberner\"",
            "TranslateReboot=\"Redémarrer\"",
            "TranslateShutdown=\"Éteindre\"",
            "TranslateSessionSelection=\"Session\"",
            "TranslateVirtualKeyboardButtonOn=\"Clavier\"",
            "TranslateVirtualKeyboardButtonOff=\"Clavier\"",
            "",
        ]
        .iter()
        .map(|s| s.to_string()),
    );
    lignes.join("\n")
}

/// Chemin du wallpaper affiché, via awww ; `None` si le démon est absent.
fn wallpaper() -> Option<PathBuf> {
    let sortie = run_cmd("awww", &["query"])?;
    let texte = String::from_utf8_lossy(&sortie.stdout).to_string();
    let marqueur = "currently displaying: image: ";
    for ligne in texte.lines() {
        if let Some(reste) = ligne.split_once(marqueur).map(|(_, r)| r) {
            return Some(PathBuf::from(reste.trim()));
        }
    }
    None
}

fn construire_fond(out: &Path, ecran: (u32, u32)) {
    let src = match wallpaper() {
        Some(p) if p.exists() => p,
        _ => {
            eprintln!("gen-palette: wallpaper introuvable, fond inchangé");
            return;
        }
    };
    let dst = out.join("Backgrounds/wallpaper.png");
    if let Some(parent) = dst.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let (w, h) = ecran;
    let taille = format!("{w}x{h}");
    let extent = format!("{w}x{h}");
    // Recadré à l'écran puis assombri à ~55 % : le formulaire doit rester lisible.
    let src_s = src.to_string_lossy().to_string();
    let dst_s = dst.to_string_lossy().to_string();
    let ok = run_cmd(
        "magick",
        &[
            &src_s, "-resize", &format!("{taille}^"), "-gravity", "center", "-extent", &extent,
            "-modulate", "55,100,100", &dst_s,
        ],
    )
    .map(|o| o.status.success())
    .unwrap_or(false);
    if !ok {
        eprintln!("gen-palette: magick absent ou en échec, fond inchangé");
        return;
    }
    println!("fond : {} → {dst_s}", src.display());
}

pub fn run(args: &[String]) -> i32 {
    let avec_fond = !args.iter().any(|a| a == "--no-background");
    let (nom, palette) = match charger_palette() {
        Ok(v) => v,
        Err(e) => return die(&e),
    };
    let ecran = taille_ecran();
    let out = crate::config::greeter::get_sddm_dir().join("out");
    let themes = out.join("Themes");
    if let Err(e) = std::fs::create_dir_all(&themes) {
        return die(&format!("{} : {e}", themes.display()));
    }
    let conf = themes.join("palette.conf");
    if let Err(e) = std::fs::write(&conf, construire_conf(&palette, ecran)) {
        return die(&format!("{} : {e}", conf.display()));
    }
    println!("palette : {nom}");
    println!("écran   : {}x{}", ecran.0, ecran.1);
    println!("conf    : out/Themes/palette.conf");
    if avec_fond {
        construire_fond(&out, ecran);
    }
    0
}
