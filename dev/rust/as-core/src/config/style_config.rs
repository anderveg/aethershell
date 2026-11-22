use crate::common::io::read_json_value;
use crate::common::paths::style_vars_path;
use serde_json::{Map, Value};
use std::path::Path;

/// Vue typée sur `style_vars.json` centralisant les clés, valeurs par défaut et bornages.
#[derive(Debug, Clone, Default)]
pub struct StyleConfig {
    raw: Map<String, Value>,
}

impl StyleConfig {
    pub fn load_default() -> Self {
        Self::load_from(&style_vars_path())
    }

    pub fn load_from(path: &Path) -> Self {
        let raw = match read_json_value(path) {
            Value::Object(m) => m,
            _ => Map::new(),
        };
        Self { raw }
    }

    pub fn from_json_str(txt: &str) -> Self {
        let raw = match serde_json::from_str::<Value>(txt) {
            Ok(Value::Object(m)) => m,
            _ => Map::new(),
        };
        Self { raw }
    }

    pub fn screensaver_app(&self) -> String {
        self.raw
            .get("screensaver_app")
            .and_then(|x| x.as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or("unimatrix")
            .to_string()
    }

    pub fn screensaver_random_colors(&self) -> bool {
        self.raw
            .get("screensaver_random_colors")
            .and_then(|x| x.as_bool())
            .unwrap_or(false)
    }

    pub fn screensaver_speed(&self) -> String {
        let clean = self
            .raw
            .get("screensaver_speed")
            .and_then(|x| x.as_str())
            .map(str::trim)
            .unwrap_or("normal");
        if matches!(clean, "slow" | "normal" | "fast") {
            clean.to_string()
        } else {
            "normal".to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_when_empty_or_invalid() {
        let cfg = StyleConfig::from_json_str("not json");
        assert_eq!(cfg.screensaver_app(), "unimatrix");
        assert!(!cfg.screensaver_random_colors());
        assert_eq!(cfg.screensaver_speed(), "normal");
    }

    #[test]
    fn parses_and_validates_screensaver_fields() {
        let cfg = StyleConfig::from_json_str(
            r#"{
                "screensaver_app": "  cbonsai ",
                "screensaver_random_colors": true,
                "screensaver_speed": "fast"
            }"#,
        );
        assert_eq!(cfg.screensaver_app(), "cbonsai");
        assert!(cfg.screensaver_random_colors());
        assert_eq!(cfg.screensaver_speed(), "fast");

        let invalid = StyleConfig::from_json_str(
            r#"{"screensaver_app": "   ", "screensaver_speed": "turbo"}"#,
        );
        assert_eq!(invalid.screensaver_app(), "unimatrix");
        assert_eq!(invalid.screensaver_speed(), "normal");
    }
}
