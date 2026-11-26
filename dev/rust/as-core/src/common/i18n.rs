use crate::common::io::read_json;
use crate::common::paths::style_vars_path;
use serde_json::{Map, Value};
use std::env;

/// Langues supportées par l'interface et le backend.
pub const SUPPORTED_LANGS: &[&str] = &["fr", "en", "es", "de"];

/// Normalise un code de langue ou de locale (`en_US.UTF-8` -> `en`), repli `fr`.
pub fn normalize_lang(raw: &str) -> &'static str {
    let base = raw
        .trim()
        .to_ascii_lowercase()
        .split(['_', '-', '.'])
        .next()
        .unwrap_or("")
        .to_string();
    for &lang in SUPPORTED_LANGS {
        if lang == base {
            return lang;
        }
    }
    "fr"
}

/// Détecte la langue par défaut depuis `LC_ALL` / `LANG` (repli `fr`).
pub fn default_lang() -> &'static str {
    for var in ["LC_ALL", "LANG"] {
        if let Ok(val) = env::var(var) {
            if !val.trim().is_empty() && !val.starts_with('C') {
                return normalize_lang(&val);
            }
        }
    }
    "fr"
}

/// Langue active lue depuis `style_vars.json` (`langue`), sinon `default_lang()`.
pub fn active_lang() -> &'static str {
    if let Some(map) = read_json::<Map<String, Value>>(&style_vars_path()) {
        if let Some(v) = map.get("langue").and_then(|v| v.as_str()) {
            if !v.trim().is_empty() {
                return normalize_lang(v);
            }
        }
    }
    default_lang()
}

/// Sélectionne la chaîne correspondant à `lang` (`fr` par défaut).
pub fn tr<'a>(lang: &str, fr: &'a str, en: &'a str, es: &'a str, de: &'a str) -> &'a str {
    match normalize_lang(lang) {
        "en" => en,
        "es" => es,
        "de" => de,
        _ => fr,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_locale_codes() {
        assert_eq!(normalize_lang("en_US.UTF-8"), "en");
        assert_eq!(normalize_lang("es-ES"), "es");
        assert_eq!(normalize_lang("DE"), "de");
        assert_eq!(normalize_lang("unknown"), "fr");
    }

    #[test]
    fn selects_expected_translation() {
        assert_eq!(tr("fr", "Bonjour", "Hello", "Hola", "Hallo"), "Bonjour");
        assert_eq!(tr("en", "Bonjour", "Hello", "Hola", "Hallo"), "Hello");
        assert_eq!(tr("es", "Bonjour", "Hello", "Hola", "Hallo"), "Hola");
        assert_eq!(tr("de", "Bonjour", "Hello", "Hola", "Hallo"), "Hallo");
    }
}
