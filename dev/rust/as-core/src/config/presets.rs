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

pub fn capture_preset(style: &Map<String, Value>, widgets: &[Value], ts: i64) -> Value {
    let mut snap = Map::new();
    for &k in PRESET_STYLE_KEYS {
        if let Some(v) = style.get(k) {
            snap.insert(k.to_string(), v.clone());
        }
    }
    json!({
        "style": Value::Object(snap),
        "widgets": Value::Array(widgets.to_vec()),
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

        let preset = capture_preset(&style, &widgets, 12345);
        assert!(preset["style"].get("unrelated_secret").is_none());

        let mut target_style = Map::new();
        target_style.insert("active_theme".into(), json!("dynamic"));
        let restored_widgets = apply_preset_into(&preset, &mut target_style).expect("apply");
        assert_eq!(target_style["active_theme"], "catppuccin");
        assert_eq!(target_style["bar_style"], "island");
        assert_eq!(restored_widgets.len(), 1);
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
