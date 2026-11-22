use crate::common::io::run_cmd_stdout;
use crate::common::paths::{home_dir, runtime_dir};
use crate::config::style_config::StyleConfig;
use serde_json::{json, Value};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn pid_file() -> PathBuf {
    runtime_dir().join("aether_matrix.pid")
}

fn cava_conf_file() -> PathBuf {
    runtime_dir().join("aether_cava_ss.conf")
}

fn write_private_text(path: &Path, content: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut f = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?;
    f.write_all(content.as_bytes())
}

const UNIMATRIX_CMD: &[&str] = &["unimatrix", "-af", "-o", "-l", "aAksS", "-s", "96"];

const SCREENSAVER_CATALOG: &[(&str, &str, &[&str])] = &[
    ("unimatrix", "Matrix (unimatrix)", &["unimatrix", "-af", "-o", "-l", "aAksS", "-s", "96"]),
    ("cmatrix", "Matrix classique (cmatrix)", &["cmatrix", "-ab", "-u", "3"]),
    ("pipes", "Tuyaux 3D (pipes.sh)", &["pipes.sh", "-p", "5", "-t", "1", "-R"]),
    ("cbonsai", "Bonsaï ASCII (cbonsai)", &["cbonsai", "-l", "-i", "-w", "2.5"]),
    ("cava", "Spectre audio (cava)", &["cava"]),
    ("asciiquarium", "Aquarium ASCII", &["asciiquarium"]),
    ("lavat", "Lampe à lave (lavat)", &["lavat", "-g", "-c", "00B4D8", "-k", "7B2CBF", "-G"]),
];

pub fn available_screensaver_apps() -> Vec<Value> {
    SCREENSAVER_CATALOG
        .iter()
        .map(|(id, label, cmd)| {
            json!({
                "id": id,
                "label": label,
                "bin": cmd[0],
                "installed": which_exists(cmd[0]),
            })
        })
        .collect()
}

fn pseudo_rand_usize(salt: u64) -> usize {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(1);
    let pid = std::process::id() as u64;
    let mut x = nanos ^ pid.wrapping_mul(0x9E3779B97F4A7C15) ^ salt.wrapping_mul(0xBF58476D1CE4E5B9);
    x ^= x >> 30;
    x = x.wrapping_mul(0xBF58476D1CE4E5B9);
    x ^= x >> 27;
    x as usize
}

fn resolve_screensaver_cmd(app: &str, random_colors: bool, speed: &str) -> (&'static str, Vec<String>) {
    resolve_screensaver_cmd_with(app, random_colors, speed, which_exists)
}

fn resolve_screensaver_cmd_with<F: Fn(&str) -> bool>(
    app: &str,
    random_colors: bool,
    speed: &str,
    has_bin: F,
) -> (&'static str, Vec<String>) {
    let mut chosen_id = "unimatrix";
    let mut base: &[&str] = UNIMATRIX_CMD;
    let mut found = false;
    for (id, _, cmd) in SCREENSAVER_CATALOG {
        if *id == app && has_bin(cmd[0]) {
            chosen_id = id;
            base = cmd;
            found = true;
            break;
        }
    }
    if !found {
        for (id, _, cmd) in SCREENSAVER_CATALOG {
            if has_bin(cmd[0]) {
                chosen_id = id;
                base = cmd;
                break;
            }
        }
    }

    let uni_speed = match speed {
        "slow" => "85",
        "fast" => "97",
        _ => "93",
    };
    let cmat_delay = match speed {
        "slow" => "6",
        "fast" => "2",
        _ => "4",
    };
    let pipes_fps = match speed {
        "slow" => "25",
        "fast" => "85",
        _ => "50",
    };
    let bonsai_time = match speed {
        "slow" => "0.06",
        "fast" => "0.015",
        _ => "0.03",
    };
    let lavat_speed = match speed {
        "slow" => "3",
        "fast" => "8",
        _ => "5",
    };

    let args = match chosen_id {
        "unimatrix" => {
            let mut v = vec![
                "unimatrix".into(), "-af".into(), "-o".into(), "-l".into(), "aAksS".into(),
                "-s".into(), uni_speed.into(),
            ];
            if random_colors {
                const COLS: &[&str] = &["green", "red", "blue", "white", "yellow", "cyan", "magenta"];
                let c = COLS[pseudo_rand_usize(1) % COLS.len()];
                v.push("-c".into());
                v.push(c.into());
            }
            v
        }
        "cmatrix" => vec!["cmatrix".into(), "-ab".into(), "-u".into(), cmat_delay.into()],
        "pipes" => vec![
            "pipes.sh".into(),
            "-p".into(), if random_colors { "6" } else { "5" }.into(),
            "-t".into(), "1".into(),
            "-f".into(), pipes_fps.into(),
            "-R".into(),
        ],
        "cbonsai" => {
            let mut v = vec![
                "cbonsai".into(), "-l".into(), "-i".into(),
                "-t".into(), bonsai_time.into(), "-w".into(), "2.5".into(),
            ];
            if random_colors {
                const LEAVES: &[u8] = &[46, 82, 118, 196, 202, 208, 214, 226, 51, 45, 201, 213, 177];
                const WOOD: &[u8] = &[94, 130, 136, 137, 172, 178, 138];
                let l1 = LEAVES[pseudo_rand_usize(2) % LEAVES.len()];
                let l2 = LEAVES[pseudo_rand_usize(3) % LEAVES.len()];
                let w1 = WOOD[pseudo_rand_usize(4) % WOOD.len()];
                let w2 = WOOD[pseudo_rand_usize(5) % WOOD.len()];
                v.push("-k".into());
                v.push(format!("{l1},{l2},{w1},{w2}"));
            }
            v
        }
        "lavat" => {
            if random_colors {
                vec![
                    "lavat".into(), "-c".into(), "cyan".into(), "-k".into(), "blue".into(),
                    "-R".into(), "2".into(), "-s".into(), lavat_speed.into(), "-G".into(),
                ]
            } else {
                vec![
                    "lavat".into(), "-g".into(), "-c".into(), "00B4D8".into(),
                    "-k".into(), "7B2CBF".into(), "-s".into(), lavat_speed.into(), "-G".into(),
                ]
            }
        }
        "cava" if random_colors => {
            const GRADS: &[(&str, &str)] = &[
                ("#00f5d4", "#9b5de5"),
                ("#ff006e", "#ffbe0b"),
                ("#00bbf9", "#f15bb5"),
                ("#8ac926", "#1982c4"),
                ("#ff5400", "#ff0054"),
            ];
            let (g1, g2) = GRADS[pseudo_rand_usize(7) % GRADS.len()];
            let cfg_path = cava_conf_file();
            let cfg = format!("[color]\ngradient = 1\ngradient_count = 2\ngradient_color_1 = '{g1}'\ngradient_color_2 = '{g2}'\n");
            if write_private_text(&cfg_path, &cfg).is_ok() {
                vec!["cava".into(), "-p".into(), cfg_path.to_string_lossy().into_owned()]
            } else {
                vec!["cava".into()]
            }
        }
        _ => base.iter().map(|s| s.to_string()).collect(),
    };
    (chosen_id, args)
}

fn which_exists(prog: &str) -> bool {
    if let Some(paths) = env::var_os("PATH") {
        for dir in env::split_paths(&paths) {
            if dir.join(prog).is_file() {
                return true;
            }
        }
    }
    false
}

fn trouver_terminal() -> &'static str {
    for cand in ["ghostty", "kitty", "foot", "alacritty"] {
        if which_exists(cand) {
            return cand;
        }
    }
    "xterm"
}

fn is_screensaver_pid(pid: libc::pid_t) -> bool {
    if pid <= 1 {
        return false;
    }
    let path = format!("/proc/{pid}/cmdline");
    let Ok(bytes) = fs::read(&path) else {
        return false;
    };
    let cmd = String::from_utf8_lossy(&bytes).replace('\0', " ");
    cmd.contains("as-core")
        || cmd.contains("matrix")
        || cmd.contains("org.aether.matrix-")
        || cmd.contains("kitten panel")
}

fn arreter_precedent() {
    let pfile = pid_file();
    if let Ok(txt) = fs::read_to_string(&pfile) {
        if let Ok(pid) = txt.trim().parse::<libc::pid_t>() {
            if is_screensaver_pid(pid) {
                unsafe {
                    if libc::killpg(pid, libc::SIGTERM) != 0 {
                        libc::kill(pid, libc::SIGTERM);
                    }
                }
            }
        }
    }
    let _ = fs::remove_file(&pfile);
}

fn cursor_pos_socket() -> Option<String> {
    let sig = env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    let sock = runtime_dir().join("hypr").join(sig).join(".socket.sock");
    let mut stream = UnixStream::connect(sock).ok()?;
    let _ = stream.set_read_timeout(Some(Duration::from_millis(100)));
    stream.write_all(b"cursorpos").ok()?;
    let mut out = String::new();
    stream.read_to_string(&mut out).ok()?;
    Some(out)
}

fn cursor_pos() -> Option<(i32, i32)> {
    let out = cursor_pos_socket().or_else(|| run_cmd_stdout("hyprctl", &["cursorpos"]))?;
    let (x_s, y_s) = out.trim().split_once(',')?;
    let x = x_s.trim().parse::<i32>().ok()?;
    let y = y_s.trim().parse::<i32>().ok()?;
    Some((x, y))
}

fn sync_winsize(stdout_fd: i32, master_fd: i32) {
    unsafe {
        let mut ws: libc::winsize = std::mem::zeroed();
        if libc::ioctl(stdout_fd, libc::TIOCGWINSZ, &mut ws) == 0 {
            libc::ioctl(master_fd, libc::TIOCSWINSZ, &ws);
        }
    }
}

fn run_screensaver(app: &str) -> i32 {
    let cfg = StyleConfig::load_default();
    let random_colors = cfg.screensaver_random_colors();
    let speed = cfg.screensaver_speed();
    let (chosen_id, anim_cmd) = resolve_screensaver_cmd(app, random_colors, &speed);
    let stdin_fd = std::io::stdin().as_raw_fd();
    let stdout_fd = std::io::stdout().as_raw_fd();
    if unsafe { libc::isatty(stdin_fd) } == 0 {
        let err = Command::new(&anim_cmd[0])
            .args(&anim_cmd[1..])
            .exec();
        eprintln!("{} exec failed: {}", anim_cmd[0], err);
        return 1;
    }

    let mut master_fd: libc::c_int = -1;
    let mut slave_fd: libc::c_int = -1;
    if unsafe {
        libc::openpty(
            &mut master_fd,
            &mut slave_fd,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    } != 0
    {
        return 1;
    }
    let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
    for _ in 0..20 {
        if unsafe { libc::ioctl(stdout_fd, libc::TIOCGWINSZ, &mut ws) } == 0
            && ws.ws_col > 10
            && ws.ws_row > 5
        {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }
    sync_winsize(stdout_fd, master_fd);
    let hide_cursor = b"\x1b[?25l";
    unsafe {
        libc::write(stdout_fd, hide_cursor.as_ptr() as *const _, hide_cursor.len());
    }

    let mut old_tty: libc::termios = unsafe { std::mem::zeroed() };
    let have_tty = unsafe { libc::tcgetattr(stdin_fd, &mut old_tty) } == 0;

    let child = unsafe {
        Command::new(&anim_cmd[0])
            .args(&anim_cmd[1..])
            .env("LC_NUMERIC", "C")
            .stdin(Stdio::from_raw_fd_dup(slave_fd))
            .stdout(Stdio::from_raw_fd_dup(slave_fd))
            .stderr(Stdio::from_raw_fd_dup(slave_fd))
            .pre_exec(|| {
                libc::setsid();
                libc::ioctl(0, libc::TIOCSCTTY, 0);
                Ok(())
            })
            .spawn()
    };
    unsafe { libc::close(slave_fd) };

    let Ok(mut proc_child) = child else {
        unsafe { libc::close(master_fd) };
        return 1;
    };

    let stop = Arc::new(AtomicBool::new(false));
    let stop_mouse = Arc::clone(&stop);
    let _mouse_thread = thread::spawn(move || {
        thread::sleep(Duration::from_millis(450));
        let Some(initial) = cursor_pos() else {
            return;
        };
        while !stop_mouse.load(Ordering::Relaxed) {
            if let Some(cur) = cursor_pos() {
                if (cur.0 - initial.0).abs() > 2 || (cur.1 - initial.1).abs() > 2 {
                    stop_mouse.store(true, Ordering::Relaxed);
                    break;
                }
            }
            thread::sleep(Duration::from_millis(200));
        }
    });

    if have_tty {
        let mut raw = old_tty;
        unsafe {
            libc::cfmakeraw(&mut raw);
            libc::tcsetattr(stdin_fd, libc::TCSADRAIN, &raw);
        }
    }

    let mut buf = [0u8; 4096];
    let mut key_buf = [0u8; 64];
    let started_at = Instant::now();
    let mut last_color_tick = Instant::now();
    let mut color_step: u64 = 1;
    while !stop.load(Ordering::Relaxed) {
        if let Ok(Some(_)) = proc_child.try_wait() {
            break;
        }
        sync_winsize(stdout_fd, master_fd);
        if random_colors
            && (chosen_id == "unimatrix" || chosen_id == "cmatrix" || chosen_id == "lavat")
            && last_color_tick.elapsed() >= Duration::from_secs(10)
        {
            last_color_tick = Instant::now();
            color_step = color_step.wrapping_add(1);
            if chosen_id == "lavat" {
                unsafe {
                    libc::write(master_fd, b"ck".as_ptr() as *const _, 2);
                }
            } else {
                let ch = if chosen_id == "unimatrix" {
                    b'1' + (pseudo_rand_usize(color_step) % 7) as u8
                } else {
                    const CMAT_KEYS: &[u8] = b"!@#$%^&";
                    CMAT_KEYS[pseudo_rand_usize(color_step) % CMAT_KEYS.len()]
                };
                unsafe {
                    libc::write(master_fd, &ch as *const u8 as *const _, 1);
                }
            }
        }
        let mut fds = [
            libc::pollfd {
                fd: master_fd,
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: stdin_fd,
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        let ret = unsafe { libc::poll(fds.as_mut_ptr(), 2, 80) };
        if ret > 0 {
            if fds[0].revents & libc::POLLIN != 0 {
                let n = unsafe { libc::read(master_fd, buf.as_mut_ptr() as *mut _, buf.len()) };
                if n <= 0 {
                    break;
                }
                unsafe {
                    libc::write(stdout_fd, buf.as_ptr() as *const _, n as usize);
                }
            }
            if fds[1].revents & libc::POLLIN != 0 {
                let kn = unsafe {
                    libc::read(stdin_fd, key_buf.as_mut_ptr() as *mut _, key_buf.len())
                };
                if started_at.elapsed() < Duration::from_millis(450) {
                    if kn > 0 {
                        unsafe {
                            libc::write(master_fd, key_buf.as_ptr() as *const _, kn as usize);
                        }
                    }
                } else {
                    stop.store(true, Ordering::Relaxed);
                    break;
                }
            }
            if fds[0].revents & (libc::POLLHUP | libc::POLLERR) != 0 {
                break;
            }
        }
    }

    stop.store(true, Ordering::Relaxed);
    if have_tty {
        unsafe {
            libc::tcsetattr(stdin_fd, libc::TCSADRAIN, &old_tty);
        }
    }
    unsafe {
        libc::close(master_fd);
    }
    if proc_child.try_wait().ok().flatten().is_none() {
        let pid = proc_child.id() as libc::pid_t;
        unsafe {
            libc::killpg(pid, libc::SIGTERM);
        }
        let _ = proc_child.kill();
        let _ = proc_child.wait();
    }
    0
}

trait FromRawFdDup {
    unsafe fn from_raw_fd_dup(fd: libc::c_int) -> Self;
}

impl FromRawFdDup for Stdio {
    unsafe fn from_raw_fd_dup(fd: libc::c_int) -> Self {
        use std::os::unix::io::FromRawFd;
        let dup_fd = libc::dup(fd);
        Stdio::from_raw_fd(dup_fd)
    }
}

fn cmd_terminal(ss: bool, inner_cmd: &[String]) -> Vec<String> {
    if which_exists("kitten") {
        let mut cmd = vec!["kitten".to_string(), "panel".to_string()];
        if ss {
            cmd.extend([
                "--config".to_string(),
                "NONE".to_string(),
                "--edge=center".to_string(),
                "--layer=overlay".to_string(),
                "--exclusive-zone=-1".to_string(),
                "--focus-policy=exclusive".to_string(),
                "--grab-keyboard=yes".to_string(),
                "-o".to_string(),
                "window_padding_width=0".to_string(),
                "-o".to_string(),
                "hide_window_decorations=yes".to_string(),
                "-o".to_string(),
                "background=#000000".to_string(),
                "-o".to_string(),
                "background_opacity=1".to_string(),
                "-o".to_string(),
                "color0=#000000".to_string(),
                "-o".to_string(),
                "cursor=#000000".to_string(),
                "--".to_string(),
            ]);
        } else {
            let kitty_theme = home_dir().join(".config/kitty/aethershell-theme.conf");
            if kitty_theme.is_file() {
                cmd.push("--config".to_string());
                cmd.push(kitty_theme.to_string_lossy().to_string());
            }
            cmd.extend([
                "--edge=background".to_string(),
                "--focus-policy=not-allowed".to_string(),
                "-o".to_string(),
                "window_padding_width=0".to_string(),
                "-o".to_string(),
                "hide_window_decorations=yes".to_string(),
                "--".to_string(),
            ]);
        }
        cmd.extend_from_slice(inner_cmd);
        return cmd;
    }

    let classe = if ss {
        "org.aether.matrix-ss"
    } else {
        "org.aether.matrix-bg"
    };
    let term = trouver_terminal();
    let mut cmd = match term {
        "ghostty" => {
            let mut v = vec![
                "ghostty".to_string(),
                format!("--class={}", classe),
                "--window-decoration=false".to_string(),
            ];
            if ss {
                v.push("--background=#000000".to_string());
                v.push("--background-opacity=1".to_string());
                v.push("--palette=0=#000000".to_string());
            }
            v.push("-e".to_string());
            v
        }
        "kitty" => {
            let mut v = vec![
                "kitty".to_string(),
                "--class".to_string(),
                classe.to_string(),
                "-o".to_string(),
                "hide_window_decorations=yes".to_string(),
            ];
            if ss {
                v.push("-o".to_string());
                v.push("background=#000000".to_string());
                v.push("-o".to_string());
                v.push("background_opacity=1".to_string());
                v.push("-o".to_string());
                v.push("color0=#000000".to_string());
            }
            v
        }
        "foot" => {
            let mut v = vec!["foot".to_string(), "--app-id".to_string(), classe.to_string()];
            if ss {
                v.push("--override=colors.background=000000".to_string());
                v.push("--override=colors.alpha=1.0".to_string());
                v.push("--override=colors.regular0=000000".to_string());
            }
            v
        }
        "alacritty" => {
            let mut v = vec![
                "alacritty".to_string(),
                "--class".to_string(),
                classe.to_string(),
                "-o".to_string(),
                "window.decorations=\"None\"".to_string(),
            ];
            if ss {
                v.push("-o".to_string());
                v.push("colors.primary.background=\"#000000\"".to_string());
                v.push("-o".to_string());
                v.push("colors.normal.black=\"#000000\"".to_string());
                v.push("-o".to_string());
                v.push("window.opacity=1".to_string());
            }
            v.push("-e".to_string());
            v
        }
        other => vec![other.to_string(), "-e".to_string()],
    };
    cmd.extend_from_slice(inner_cmd);
    cmd
}

fn lancer(ss: bool, delay_min: f64, app: &str) -> i32 {
    arreter_precedent();
    if delay_min > 0.0 {
        let pid = unsafe { libc::fork() };
        if pid > 0 {
            return 0;
        }
        unsafe {
            libc::setsid();
        }
        let _ = write_private_text(&pid_file(), &std::process::id().to_string());
        thread::sleep(Duration::from_secs_f64(delay_min * 60.0));
    }

    let inner: Vec<String> = if ss {
        let exe = env::current_exe()
            .ok()
            .and_then(|p| p.to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| Path::new("as-core").to_string_lossy().to_string());
        vec![exe, "matrix".to_string(), "--run-ss".to_string(), "--app".to_string(), app.to_string()]
    } else {
        UNIMATRIX_CMD.iter().map(|s| s.to_string()).collect()
    };

    let cmd = cmd_terminal(ss, &inner);
    let spawn_res = unsafe {
        Command::new(&cmd[0])
            .args(&cmd[1..])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .pre_exec(|| {
                libc::setsid();
                libc::ioctl(0, libc::TIOCSCTTY, 0);
                Ok(())
            })
            .spawn()
    };
    if let Ok(proc_child) = spawn_res {
        let _ = write_private_text(&pid_file(), &proc_child.id().to_string());
    }
    0
}

pub fn run(args: &[String]) -> i32 {
    let mut ss = false;
    let mut stop = false;
    let mut run_ss = false;
    let mut delay = 0.0f64;
    let mut app = String::new();

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--ss" => ss = true,
            "--stop" => stop = true,
            "--run-ss" => run_ss = true,
            "--app" if i + 1 < args.len() => {
                app = args[i + 1].trim().to_string();
                i += 1;
            }
            s if s.starts_with("--app=") => {
                app = s[6..].trim().to_string();
            }
            "--delay" if i + 1 < args.len() => {
                delay = args[i + 1].parse::<f64>().unwrap_or(0.0).max(0.0);
                i += 1;
            }
            s if s.starts_with("--delay=") => {
                delay = s[8..].parse::<f64>().unwrap_or(0.0).max(0.0);
            }
            _ => {}
        }
        i += 1;
    }

    let eff_app = if app.is_empty() { StyleConfig::load_default().screensaver_app() } else { app };

    if run_ss {
        return run_screensaver(&eff_app);
    }
    if stop {
        arreter_precedent();
        return 0;
    }
    lancer(ss, delay, &eff_app)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_requested_app_and_falls_back_when_missing() {
        let (id, args) = resolve_screensaver_cmd_with("cmatrix", false, "fast", |b| b == "cmatrix");
        assert_eq!(id, "cmatrix");
        assert_eq!(args, vec!["cmatrix", "-ab", "-u", "2"]);

        let (fb_id, fb_args) = resolve_screensaver_cmd_with("cmatrix", false, "slow", |b| b == "pipes.sh");
        assert_eq!(fb_id, "pipes");
        assert_eq!(fb_args, vec!["pipes.sh", "-p", "5", "-t", "1", "-f", "25", "-R"]);
    }

    #[test]
    fn applies_random_colors_and_speed_flags() {
        let (id, args) = resolve_screensaver_cmd_with("cbonsai", true, "slow", |b| b == "cbonsai");
        assert_eq!(id, "cbonsai");
        assert!(args.contains(&"-t".to_string()) && args.contains(&"0.06".to_string()));
        assert!(args.contains(&"-k".to_string()));

        let (_, lavat_rand) = resolve_screensaver_cmd_with("lavat", true, "normal", |b| b == "lavat");
        assert!(lavat_rand.contains(&"-R".to_string()));
        let (_, lavat_def) = resolve_screensaver_cmd_with("lavat", false, "normal", |b| b == "lavat");
        assert!(lavat_def.contains(&"-g".to_string()));
    }
}
