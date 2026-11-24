use serde_json::{json, Map, Value};

pub const PRESET_STYLE_KEYS: &[&str] = &[
    "active_theme",
    "global_radius",
    "global_opacity",
    "shell_opacity",
    "bar_style",
    "bar_height",
    "bar_border",
    "bar_gaps_transparent",
    "blur_enabled",
    "blur_size",
    "blur_passes",
    "blur_vibrancy",
    "shell_blur_enabled",
    "shell_blur_alpha",
    "shell_blur_popups",
    "ilot_applets_mode",
    "ilot_applets_order",
    "ilot_applets_corner",
    "ilot_coins_groupes",
    "ilot_show_media",
    "ilot_show_planka",
    "ilot_show_live_activity",
    "ilot_show_vpn",
    "ilot_show_capture",
    "ilot_show_workspaces",
    "ilot_show_clock",
    "palette",
];

/// Environnement appliqué par un profil : les modes qui ne sont pas du style pur.
/// `power_profile` vient de `powerprofilesctl`, pas de `style_vars.json`, et
/// n'est donc jamais réécrit dans le style.
pub const PRESET_ENV_KEYS: &[&str] = &[
    "do_not_disturb",
    "night_mode",
    "night_temp",
    "night_from",
    "night_to",
    "caffeine_actif",
    "widgets_bureau_visibles",
];

pub fn capture_env(style: &Map<String, Value>, power_profile: &str) -> Value {
    let mut snap = Map::new();
    // Valeurs par défaut alignées sur celles du shell (ConfigStore / Theme) : sans
    // elles, un profil enregistré avant la première écriture de la clé partait
    // sans `caffeine_actif` ni `widgets_bureau_visibles`, donc ne les restaurait
    // jamais.
    let defauts: &[(&str, Value)] = &[
        ("do_not_disturb", json!(false)),
        ("night_mode", json!(false)),
        ("night_temp", json!(4000)),
        ("night_from", json!("")),
        ("night_to", json!("")),
        ("caffeine_actif", json!(false)),
        ("widgets_bureau_visibles", json!(true)),
    ];
    for &k in PRESET_ENV_KEYS {
        let v = style
            .get(k)
            .cloned()
            .or_else(|| defauts.iter().find(|(d, _)| *d == k).map(|(_, v)| v.clone()));
        if let Some(v) = v {
            snap.insert(k.to_string(), v);
        }
    }
    let p = power_profile.trim();
    if !p.is_empty() {
        snap.insert("power_profile".into(), json!(p));
    }
    Value::Object(snap)
}

/// Écrit les clés d'environnement d'un profil dans le style et renvoie le bloc
/// `env` effectivement appliqué (pour les effets de bord : démon de nuit, profil
/// d'énergie).
///
/// Profil antérieur à la v2 (pas de bloc `env`) : on remet les **modes au repos**
/// au lieu de ne rien faire. Constat utilisateur : après « nuit », appliquer un
/// ancien profil laissait l'écran chaud et le DND actifs, donc le profil
/// semblait ne pas s'appliquer du tout. Les valeurs non booléennes (température,
/// plages horaires) sont laissées intactes — le mode étant éteint, elles ne
/// jouent pas.
pub fn apply_env_into(preset: &Value, style: &mut Map<String, Value>) -> Option<Value> {
    let obj = preset.as_object()?;
    let env = match obj.get("env").and_then(|v| v.as_object()) {
        Some(e) => e.clone(),
        None => {
            let mut repos = Map::new();
            repos.insert("do_not_disturb".into(), json!(false));
            repos.insert("caffeine_actif".into(), json!(false));
            repos.insert("widgets_bureau_visibles".into(), json!(true));
            repos.insert("night_mode".into(), json!(false));
            repos
        }
    };
    for (k, v) in &env {
        if PRESET_ENV_KEYS.contains(&k.as_str()) {
            style.insert(k.clone(), v.clone());
        }
    }
    Some(Value::Object(env))
}

pub fn capture_preset(
    style: &Map<String, Value>,
    widgets: &[Value],
    env: &Value,
    ts: i64,
) -> Value {
    let mut snap = Map::new();
    for &k in PRESET_STYLE_KEYS {
        if let Some(v) = style.get(k) {
            snap.insert(k.to_string(), v.clone());
        }
    }
    json!({
        "style": Value::Object(snap),
        "widgets": Value::Array(widgets.to_vec()),
        "env": env.clone(),
        "created_at": ts,
    })
}

pub fn apply_preset_into(
    preset: &Value,
    style: &mut Map<String, Value>,
) -> Option<Vec<Value>> {
    let obj = preset.as_object()?;
    if let Some(st) = obj.get("style").and_then(|v| v.as_object()) {
        for (k, v) in st {
            if PRESET_STYLE_KEYS.contains(&k.as_str()) {
                style.insert(k.clone(), v.clone());
            }
        }
    }
    let widgets = obj
        .get("widgets")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    Some(widgets)
}

pub fn summarize_presets(presets: &Map<String, Value>) -> Vec<Value> {
    let mut keys: Vec<&String> = presets.keys().collect();
    keys.sort();
    keys.into_iter()
        .map(|name| {
            let entry = &presets[name];
            let style = entry.get("style").and_then(|v| v.as_object());
            let theme = style
                .and_then(|s| s.get("active_theme"))
                .and_then(|v| v.as_str())
                .unwrap_or("dynamic");
            let bar_style = style
                .and_then(|s| s.get("bar_style"))
                .and_then(|v| v.as_str())
                .unwrap_or("classic");
            let widgets_count = entry
                .get("widgets")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0);
            json!({
                "name": name,
                "theme": theme,
                "bar_style": bar_style,
                "widgets_count": widgets_count,
                // v2 = le profil enregistre aussi les modes (caféine, nuit, DND,
                // énergie, widgets) ; l'UI le signale pour les profils antérieurs.
                "env_v2": entry.get("env").is_some(),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_and_applies_only_preset_keys() {
        let mut style = Map::new();
        style.insert("active_theme".into(), json!("catppuccin"));
        style.insert("bar_style".into(), json!("island"));
        style.insert("unrelated_secret".into(), json!("ignore-me"));
        let widgets = vec![json!({"id": "horloge-1", "type": "horloge"})];

        let preset = capture_preset(&style, &widgets, &json!({"do_not_disturb": true}), 12345);
        assert!(preset["style"].get("unrelated_secret").is_none());
        assert_eq!(preset["env"]["do_not_disturb"], json!(true));

        let mut target_style = Map::new();
        target_style.insert("active_theme".into(), json!("dynamic"));
        let restored_widgets = apply_preset_into(&preset, &mut target_style).expect("apply");
        assert_eq!(target_style["active_theme"], "catppuccin");
        assert_eq!(target_style["bar_style"], "island");
        assert_eq!(restored_widgets.len(), 1);

        // env : écrit seulement les clés connues, ne recopie pas power_profile
        let mut style_v2 = Map::new();
        style_v2.insert("do_not_disturb".into(), json!(false));
        let env = apply_env_into(&preset, &mut style_v2).expect("env");
        assert_eq!(style_v2["do_not_disturb"], json!(true));
        assert_eq!(env["do_not_disturb"], json!(true));
        assert!(style_v2.get("power_profile").is_none());
    }

    #[test]
    fn legacy_preset_resets_modes_instead_of_leaving_them() {
        // Profil v1 : on applique le style ET on remet les modes au repos, sinon
        // l'écran reste chaud / le DND actif et le profil paraît inopérant.
        let preset = json!({"style": {"active_theme": "nord"}, "widgets": []});
        let mut style = Map::new();
        style.insert("night_mode".into(), json!(true));
        style.insert("night_temp".into(), json!(3800));
        style.insert("do_not_disturb".into(), json!(true));
        let env = apply_env_into(&preset, &mut style).expect("env de repli");
        assert_eq!(style["night_mode"], json!(false));
        assert_eq!(style["do_not_disturb"], json!(false));
        assert_eq!(style["widgets_bureau_visibles"], json!(true));
        // la température choisie par l'utilisateur n'est pas écrasée
        assert_eq!(style["night_temp"], json!(3800));
        assert_eq!(env["night_mode"], json!(false));
        assert!(apply_preset_into(&preset, &mut style).is_some());
    }

    #[test]
    fn summarizes_presets_sorted_by_name() {
        let mut presets = Map::new();
        presets.insert(
            "Travail".into(),
            json!({"style": {"active_theme": "nord", "bar_style": "island"}, "widgets": [1, 2]}),
        );
        presets.insert(
            "Minimal".into(),
            json!({"style": {"active_theme": "mono", "bar_style": "classic"}, "widgets": []}),
        );
        let list = summarize_presets(&presets);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0]["name"], "Minimal");
        assert_eq!(list[1]["name"], "Travail");
        assert_eq!(list[1]["widgets_count"], 2);
    }
}
