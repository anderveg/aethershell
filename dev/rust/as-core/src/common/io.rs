use crate::common::lock::FileLock;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::{Map, Value};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

pub fn read_json<T: DeserializeOwned>(path: &Path) -> Option<T> {
    let content = fs::read_to_string(path).ok()?;
    serde_json::from_str(&content).ok()
}

pub fn read_json_value(path: &Path) -> Value {
    read_json::<Value>(path).unwrap_or_else(|| Value::Object(Map::new()))
}

fn write_bytes_atomic(path: &Path, bytes: &[u8], trailing_newline: bool, mode: u32) -> io::Result<()> {
    let _lock = FileLock::acquire(path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut tmp_os = path.as_os_str().to_os_string();
    tmp_os.push(format!(".tmp.{}", std::process::id()));
    let tmp_path = PathBuf::from(tmp_os);

    {
        let mut f = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .mode(mode)
            .open(&tmp_path)?;
        f.write_all(bytes)?;
        if trailing_newline && !bytes.ends_with(b"\n") {
            f.write_all(b"\n")?;
        }
        f.sync_all()?;
    }
    fs::rename(&tmp_path, path)?;
    Ok(())
}

pub fn write_text_atomic(path: &Path, content: &str, mode: u32) -> io::Result<()> {
    write_bytes_atomic(path, content.as_bytes(), false, mode)
}

pub fn write_json_atomic<T: Serialize + ?Sized>(path: &Path, data: &T, mode: u32) -> io::Result<()> {
    let json = serde_json::to_string_pretty(data)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    write_bytes_atomic(path, json.as_bytes(), true, mode)
}

pub fn write_private_json<T: Serialize + ?Sized>(path: &Path, data: &T) -> io::Result<()> {
    write_json_atomic(path, data, 0o600)
}

pub fn run_cmd(program: &str, args: &[&str]) -> Option<Output> {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .ok()
}

pub fn run_cmd_stdout(program: &str, args: &[&str]) -> Option<String> {
    let out = run_cmd(program, args)?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Extrait `--options={...}` des arguments CLI passés par `Applet.qml`.
pub fn parse_options_arg(args: &[String]) -> Map<String, Value> {
    for (i, arg) in args.iter().enumerate() {
        if let Some(raw) = arg.strip_prefix("--options=") {
            if let Ok(Value::Object(m)) = serde_json::from_str::<Value>(raw) {
                return m;
            }
        } else if arg == "--options" {
            if let Some(raw) = args.get(i + 1) {
                if let Ok(Value::Object(m)) = serde_json::from_str::<Value>(raw) {
                    return m;
                }
            }
        }
    }
    Map::new()
}

/// Active `PR_SET_PDEATHSIG(SIGTERM)` pour éviter tout démon orphelin si Quickshell meurt.
pub fn tie_to_parent_death() {
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
    }
}

#[allow(dead_code)]
pub fn now_f64() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

#[allow(dead_code)]
pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[allow(dead_code)]
pub fn local_tm(secs: i64) -> libc::tm {
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    let t = secs as libc::time_t;
    unsafe { libc::localtime_r(&t, &mut tm) };
    tm
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_options_arg_formats() {
        let a = vec!["--options={\"k\":1}".to_string()];
        assert_eq!(parse_options_arg(&a).get("k").and_then(|v| v.as_i64()), Some(1));

        let b = vec!["--options".to_string(), "{\"ok\":true}".to_string()];
        assert_eq!(parse_options_arg(&b).get("ok").and_then(|v| v.as_bool()), Some(true));

        let c = vec!["--options=invalid".to_string()];
        assert!(parse_options_arg(&c).is_empty());
    }

    #[test]
    fn writes_and_reads_json_atomically_in_tempdir() {
        let dir = std::env::temp_dir().join(format!("as_core_io_test_{}", std::process::id()));
        let p = dir.join("sample.json");
        let payload = serde_json::json!({"hello": "world", "n": 42});
        write_json_atomic(&p, &payload, 0o644).expect("atomic write");
        let loaded = read_json_value(&p);
        assert_eq!(loaded["hello"], "world");
        assert_eq!(loaded["n"], 42);
        let _ = fs::remove_dir_all(&dir);
    }
}
