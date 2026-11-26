use crate::common::io::run_cmd;
use crate::common::paths::runtime_dir;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

static CURRENT_TRANSFORM: AtomicI32 = AtomicI32::new(0);
static HIDE_GEN: AtomicU64 = AtomicU64::new(0);

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct InputEvent {
    tv_sec: i64,
    tv_usec: i64,
    type_: u16,
    code: u16,
    value: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct InputAbsInfo {
    value: i32,
    minimum: i32,
    maximum: i32,
    fuzz: i32,
    flat: i32,
    resolution: i32,
}

#[repr(C)]
struct UinputSetup {
    id_bustype: u16,
    id_vendor: u16,
    id_product: u16,
    id_version: u16,
    name: [u8; 80],
    ff_effects_max: u32,
}

const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const EV_ABS: u16 = 0x03;
const EV_SW: u16 = 0x05;

const SYN_REPORT: u16 = 0x00;
const SW_TABLET_MODE: u16 = 0x01;
const ABS_MT_SLOT: u16 = 0x2f;
const ABS_MT_POSITION_X: u16 = 0x35;
const ABS_MT_POSITION_Y: u16 = 0x36;
const ABS_MT_TRACKING_ID: u16 = 0x39;

const UI_DEV_CREATE: libc::c_ulong = 0x5501;
const UI_DEV_DESTROY: libc::c_ulong = 0x5502;
const UI_DEV_SETUP: libc::c_ulong = 0x405c5503;
const UI_SET_EVBIT: libc::c_ulong = 0x40045564;
const UI_SET_KEYBIT: libc::c_ulong = 0x40045565;
const EVIOCGABS_BASE: libc::c_ulong = 0x80184540;

fn session_dir() -> PathBuf {
    let dir = runtime_dir().join("quickshell-session");
    if !dir.exists() {
        let mut builder = fs::DirBuilder::new();
        builder.recursive(true).mode(0o700);
        let _ = builder.create(&dir);
    }
    dir
}

fn state_file() -> PathBuf {
    session_dir().join("tablet_mode")
}

fn lock_file() -> PathBuf {
    session_dir().join("tablet_rotation_lock")
}

fn kbd_state_file() -> PathBuf {
    session_dir().join("tablet_kbd_open")
}

pub fn ensure_wayland_hypr_env() {
    let xdg = runtime_dir();
    if env::var_os("XDG_RUNTIME_DIR").is_none() {
        env::set_var("XDG_RUNTIME_DIR", &xdg);
    }
    if env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default().is_empty() {
        let hypr_dir = xdg.join("hypr");
        if let Ok(rd) = fs::read_dir(&hypr_dir) {
            let mut entries: Vec<(SystemTime, String)> = rd
                .flatten()
                .filter_map(|e| {
                    let p = e.path();
                    if p.is_dir() {
                        let mtime = e
                            .metadata()
                            .and_then(|m| m.modified())
                            .unwrap_or(UNIX_EPOCH);
                        let name = e.file_name().to_string_lossy().to_string();
                        Some((mtime, name))
                    } else {
                        None
                    }
                })
                .collect();
            entries.sort_by(|a, b| b.0.cmp(&a.0));
            if let Some((_, sig)) = entries.first() {
                env::set_var("HYPRLAND_INSTANCE_SIGNATURE", sig);
            }
        }
    }
    if env::var("WAYLAND_DISPLAY").unwrap_or_default().is_empty() {
        for cand in ["wayland-1", "wayland-0"] {
            if xdg.join(cand).exists() {
                env::set_var("WAYLAND_DISPLAY", cand);
                break;
            }
        }
    }
}

pub fn is_rotation_locked() -> bool {
    lock_file().exists()
}

pub fn set_rotation_lock(locked: bool) -> Value {
    let lf = lock_file();
    if locked {
        let _ = fs::write(&lf, "1");
    } else {
        let _ = fs::remove_file(&lf);
    }
    json!({ "rotation_locked": is_rotation_locked() })
}

pub fn set_kbd_open(is_open: bool) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);
    let val = if is_open { "1" } else { "0" };
    let _ = fs::write(kbd_state_file(), format!("{val} {now:.3}\n"));
}

pub fn mode_for_transform(transform: i32) -> &'static str {
    if transform.rem_euclid(4) == 0 {
        "laptop"
    } else {
        "tablet"
    }
}

pub fn get_current_mode() -> String {
    fs::read_to_string(state_file())
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "laptop".to_string())
}

fn hyprctl_eval(lua: &str) {
    ensure_wayland_hypr_env();
    let _ = Command::new("hyprctl")
        .args(["eval", lua])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn apply_monitor_transform(output_name: &str, transform: i32, only_if_active: bool) -> bool {
    ensure_wayland_hypr_env();
    let Some(out) = run_cmd("hyprctl", &["monitors", "-j"]) else {
        return false;
    };
    let Ok(arr) = serde_json::from_slice::<Value>(&out.stdout) else {
        return false;
    };
    let Some(list) = arr.as_array() else {
        return false;
    };
    let cur = list
        .iter()
        .find(|m| m.get("name").and_then(|v| v.as_str()) == Some(output_name));
    if only_if_active && cur.is_none() {
        return false;
    }
    let cur_tf = cur
        .and_then(|m| m.get("transform"))
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let position = cur
        .and_then(|m| {
            let x = m.get("x")?.as_i64()?;
            let y = m.get("y")?.as_i64()?;
            Some(format!("{x}x{y}"))
        })
        .unwrap_or_else(|| "auto".to_string());
    let scale = cur
        .and_then(|m| m.get("scale"))
        .and_then(|v| v.as_f64())
        .unwrap_or(1.0);
    let mode = cur
        .and_then(|m| {
            if cur_tf.rem_euclid(2) != 0 {
                return None;
            }
            let w = m.get("width")?.as_i64()?;
            let h = m.get("height")?.as_i64()?;
            let rate = m.get("refreshRate").and_then(|v| v.as_f64()).unwrap_or(60.0);
            Some(format!("{w}x{h}@{rate:.2}"))
        })
        .unwrap_or_else(|| "preferred".to_string());
    let tf = transform.rem_euclid(4);
    let lua = format!(
        "hl.monitor({{ output = \"{output_name}\", mode = \"{mode}\", position = \"{position}\", scale = {scale}, transform = {tf} }})"
    );
    hyprctl_eval(&lua);
    true
}

fn sync_touch_transform(transform: i32) {
    let tf = transform.rem_euclid(4);
    let lua = format!(
        "hl.config({{ input = {{ touchdevice = {{ transform = {tf} }}, tablet = {{ transform = {tf} }} }} }})"
    );
    hyprctl_eval(&lua);
}

fn sync_window_ergonomics(clean_mode: &str) {
    let lua = if clean_mode == "tablet" {
        "hl.config({ general = { gaps_in = 1, gaps_out = 2 } })"
    } else {
        "hl.config({ general = { gaps_in = 2, gaps_out = 8 } })"
    };
    hyprctl_eval(lua);
    if let Some(out) = run_cmd("hyprctl", &["activewindow", "-j"]) {
        if let Ok(aw) = serde_json::from_slice::<Value>(&out.stdout) {
            let fs = aw.get("fullscreen").and_then(|v| v.as_i64()).unwrap_or(0);
            let floating = aw.get("floating").and_then(|v| v.as_bool()).unwrap_or(false);
            if (clean_mode == "tablet" && fs == 0 && !floating)
                || (clean_mode == "laptop" && fs == 1)
            {
                let _ = Command::new("hyprctl")
                    .args(["dispatch", "fullscreen", "1"])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        }
    }
}

fn sync_a11y_osk(enabled: bool) {
    let val = if enabled { "true" } else { "false" };
    let _ = Command::new("gsettings")
        .args([
            "set",
            "org.gnome.desktop.a11y.applications",
            "screen-keyboard-enabled",
            val,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

pub fn sync_initial_transform_from_hypr() {
    ensure_wayland_hypr_env();
    if let Some(out) = run_cmd("hyprctl", &["monitors", "-j"]) {
        if let Ok(arr) = serde_json::from_slice::<Value>(&out.stdout) {
            if let Some(list) = arr.as_array() {
                if let Some(edp) = list
                    .iter()
                    .find(|m| m.get("name").and_then(|v| v.as_str()) == Some("eDP-1"))
                {
                    let tf = edp
                        .get("transform")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(0) as i32;
                    CURRENT_TRANSFORM.store(tf.rem_euclid(4), Ordering::Relaxed);
                }
            }
        }
    }
}

pub fn set_mode(mode: &str, transform: Option<i32>, respect_lock: bool) -> Value {
    ensure_wayland_hypr_env();
    let tf = transform
        .unwrap_or_else(|| if mode == "tablet" { 2 } else { 0 })
        .rem_euclid(4);
    let clean_mode = mode_for_transform(tf);

    if !(respect_lock && is_rotation_locked()) {
        if apply_monitor_transform("eDP-1", tf, true) {
            sync_touch_transform(tf);
            sync_window_ergonomics(clean_mode);
            CURRENT_TRANSFORM.store(tf, Ordering::Relaxed);
        }
    } else {
        sync_initial_transform_from_hypr();
    }

    let _ = fs::write(state_file(), clean_mode);
    if clean_mode == "tablet" {
        sync_a11y_osk(true);
    } else {
        set_kbd_open(false);
    }
    json!({
        "mode": clean_mode,
        "transform": tf,
        "rotation_locked": is_rotation_locked(),
    })
}

fn sysfs_bit_set(event_name: &str, rel_path: &str, bit: u32) -> bool {
    let p = PathBuf::from("/sys/class/input")
        .join(event_name)
        .join("device")
        .join(rel_path);
    let Ok(txt) = fs::read_to_string(p) else {
        return false;
    };
    let words: Vec<&str> = txt.split_whitespace().collect();
    if words.is_empty() {
        return false;
    }
    let word_idx = (bit / 64) as usize;
    let bit_in_word = bit % 64;
    if word_idx >= words.len() {
        return false;
    }
    let w_str = words[words.len() - 1 - word_idx];
    let val = u64::from_str_radix(w_str, 16).unwrap_or(0);
    (val & (1u64 << bit_in_word)) != 0
}

fn watch_sw_tablet_mode() {
    let Ok(rd) = fs::read_dir("/sys/class/input") else {
        return;
    };
    let mut target_dev: Option<PathBuf> = None;
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        if !name.starts_with("event") {
            continue;
        }
        if sysfs_bit_set(&name, "capabilities/sw", SW_TABLET_MODE as u32) {
            let cand = PathBuf::from("/dev/input").join(&name);
            if cand.exists() {
                target_dev = Some(cand);
                break;
            }
        }
    }
    let Some(dev_path) = target_dev else {
        return;
    };
    let Ok(mut file) = File::open(&dev_path) else {
        return;
    };
    let mut buf = [0u8; std::mem::size_of::<InputEvent>()];
    while file.read_exact(&mut buf).is_ok() {
        let ev: InputEvent = unsafe { std::ptr::read_unaligned(buf.as_ptr() as *const InputEvent) };
        if ev.type_ == EV_SW && ev.code == SW_TABLET_MODE {
            if ev.value == 1 {
                set_mode("tablet", Some(2), false);
            } else {
                set_mode("laptop", Some(0), false);
            }
        }
    }
}

fn get_abs_max(fd: i32, code: u16, fallback: f64) -> f64 {
    let mut info = InputAbsInfo::default();
    let rc = unsafe {
        libc::ioctl(
            fd,
            (EVIOCGABS_BASE + code as libc::c_ulong) as _,
            &mut info as *mut InputAbsInfo,
        )
    };
    if rc == 0 && info.maximum > 0 {
        info.maximum as f64
    } else {
        fallback
    }
}

fn watch_touchscreen_gestures() {
    let Ok(rd) = fs::read_dir("/sys/class/input") else {
        return;
    };
    let mut touch_dev: Option<PathBuf> = None;
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        if !name.starts_with("event") {
            continue;
        }
        // INPUT_PROP_DIRECT == 1 (bit 1) + ABS_MT_POSITION_X == 0x35 (53)
        if sysfs_bit_set(&name, "properties", 1)
            && sysfs_bit_set(&name, "capabilities/abs", ABS_MT_POSITION_X as u32)
        {
            let cand = PathBuf::from("/dev/input").join(&name);
            if cand.exists() {
                touch_dev = Some(cand);
                break;
            }
        }
    }
    let Some(dev_path) = touch_dev else {
        return;
    };
    let Ok(mut file) = File::open(&dev_path) else {
        return;
    };
    let fd = file.as_raw_fd();
    let max_x = get_abs_max(fd, ABS_MT_POSITION_X, 4096.0);
    let max_y = get_abs_max(fd, ABS_MT_POSITION_Y, 4096.0);

    #[derive(Clone, Default)]
    struct SlotState {
        active: bool,
        x: Option<f64>,
        y: Option<f64>,
        sx: Option<f64>,
        sy: Option<f64>,
    }

    let mut slots: HashMap<i32, SlotState> = HashMap::new();
    let mut cur_slot: i32 = 0;
    let mut fired = false;

    let mut buf = [0u8; std::mem::size_of::<InputEvent>()];
    while file.read_exact(&mut buf).is_ok() {
        let ev: InputEvent = unsafe { std::ptr::read_unaligned(buf.as_ptr() as *const InputEvent) };
        if ev.type_ == EV_ABS {
            if ev.code == ABS_MT_SLOT {
                cur_slot = ev.value;
            } else if ev.code == ABS_MT_TRACKING_ID {
                if ev.value >= 0 {
                    slots.insert(
                        cur_slot,
                        SlotState {
                            active: true,
                            ..Default::default()
                        },
                    );
                } else {
                    if let Some(st) = slots.get_mut(&cur_slot) {
                        st.active = false;
                    }
                    if !slots.values().any(|s| s.active) {
                        slots.clear();
                        fired = false;
                    }
                }
            } else if ev.code == ABS_MT_POSITION_X {
                let st = slots.entry(cur_slot).or_insert_with(|| SlotState {
                    active: true,
                    ..Default::default()
                });
                let v = ev.value as f64;
                st.x = Some(v);
                if st.sx.is_none() {
                    st.sx = Some(v);
                }
            } else if ev.code == ABS_MT_POSITION_Y {
                let st = slots.entry(cur_slot).or_insert_with(|| SlotState {
                    active: true,
                    ..Default::default()
                });
                let v = ev.value as f64;
                st.y = Some(v);
                if st.sy.is_none() {
                    st.sy = Some(v);
                }
            }
        } else if ev.type_ == EV_SYN && ev.code == SYN_REPORT && !fired {
            let active: Vec<&SlotState> = slots
                .values()
                .filter(|s| {
                    s.active
                        && s.x.is_some()
                        && s.y.is_some()
                        && s.sx.is_some()
                        && s.sy.is_some()
                })
                .collect();
            if active.len() >= 3 {
                let n = active.len() as f64;
                let mut dx: f64 = active
                    .iter()
                    .map(|s| (s.x.unwrap() - s.sx.unwrap()) / max_x)
                    .sum::<f64>()
                    / n;
                let mut dy: f64 = active
                    .iter()
                    .map(|s| (s.y.unwrap() - s.sy.unwrap()) / max_y)
                    .sum::<f64>()
                    / n;
                let tf = CURRENT_TRANSFORM.load(Ordering::Relaxed).rem_euclid(4);
                if tf == 2 {
                    dx = -dx;
                    dy = -dy;
                } else if tf == 1 {
                    let (odx, ody) = (dx, dy);
                    dx = -ody;
                    dy = odx;
                } else if tf == 3 {
                    let (odx, ody) = (dx, dy);
                    dx = ody;
                    dy = -odx;
                }
                if dx.abs() > 0.08 || dy.abs() > 0.08 {
                    fired = true;
                    ensure_wayland_hypr_env();
                    if dx.abs() > dy.abs() {
                        let ws = if dx > 0.0 { "r+1" } else { "r-1" };
                        let lua = format!("hl.dispatch(hl.dsp.focus({{ workspace = \"{ws}\" }}))");
                        let _ = Command::new("hyprctl")
                            .args(["eval", &lua])
                            .stdout(Stdio::null())
                            .stderr(Stdio::null())
                            .spawn();
                    } else {
                        let _ = Command::new("quickshell")
                            .args(["ipc", "-n", "call", "shell", "toggleOverview"])
                            .stdout(Stdio::null())
                            .stderr(Stdio::null())
                            .spawn();
                    }
                }
            }
        }
    }
}

fn wl_pack_str(s: &str) -> Vec<u8> {
    let mut b = s.as_bytes().to_vec();
    b.push(0);
    let pad = (4 - (b.len() % 4)) % 4;
    let mut out = (b.len() as u32).to_le_bytes().to_vec();
    out.extend_from_slice(&b);
    out.resize(out.len() + pad, 0);
    out
}

fn wl_msg(obj: u32, op: u16, payload: &[u8]) -> Vec<u8> {
    let size = (8 + payload.len()) as u32;
    let size_op = (size << 16) | (op as u32);
    let mut out = Vec::with_capacity(8 + payload.len());
    out.extend_from_slice(&obj.to_le_bytes());
    out.extend_from_slice(&size_op.to_le_bytes());
    out.extend_from_slice(payload);
    out
}

fn schedule_kbd_hide() {
    let gen = HIDE_GEN.fetch_add(1, Ordering::SeqCst) + 1;
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(180));
        if HIDE_GEN.load(Ordering::SeqCst) == gen {
            set_kbd_open(false);
        }
    });
}

fn cancel_kbd_hide() {
    HIDE_GEN.fetch_add(1, Ordering::SeqCst);
}

fn watch_input_method() {
    sync_a11y_osk(true);
    set_kbd_open(false);

    loop {
        ensure_wayland_hypr_env();
        let xdg = runtime_dir();
        let wdisp = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-1".to_string());
        let sock_path = xdg.join(wdisp);
        if !sock_path.exists() {
            thread::sleep(Duration::from_secs(2));
            continue;
        }
        let Ok(mut stream) = UnixStream::connect(&sock_path) else {
            thread::sleep(Duration::from_secs(2));
            continue;
        };

        let mut init_pkt = wl_msg(1, 1, &2u32.to_le_bytes());
        init_pkt.extend_from_slice(&wl_msg(1, 0, &3u32.to_le_bytes()));
        if stream.write_all(&init_pkt).is_err() {
            thread::sleep(Duration::from_secs(2));
            continue;
        }

        let mut buf: Vec<u8> = Vec::with_capacity(4096);
        let mut tmp = [0u8; 4096];
        let mut seat_name: Option<u32> = None;
        let mut imm_name: Option<u32> = None;
        let mut sync_done = false;
        let mut io_err = false;

        while !sync_done {
            match stream.read(&mut tmp) {
                Ok(0) | Err(_) => {
                    io_err = true;
                    break;
                }
                Ok(n) => buf.extend_from_slice(&tmp[..n]),
            }
            while buf.len() >= 8 {
                let obj = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
                let size_op = u32::from_le_bytes([buf[4], buf[5], buf[6], buf[7]]);
                let size = (size_op >> 16) as usize;
                let op = (size_op & 0xffff) as u16;
                if size < 8 || buf.len() < size {
                    break;
                }
                let payload = &buf[8..size];
                if obj == 2 && op == 0 && payload.len() >= 8 {
                    let name = u32::from_le_bytes([payload[0], payload[1], payload[2], payload[3]]);
                    let slen = u32::from_le_bytes([payload[4], payload[5], payload[6], payload[7]])
                        as usize;
                    if slen > 0 && payload.len() >= 8 + slen - 1 {
                        let iface = String::from_utf8_lossy(&payload[8..8 + slen - 1]);
                        if iface == "wl_seat" && seat_name.is_none() {
                            seat_name = Some(name);
                        } else if iface == "zwp_input_method_manager_v2" {
                            imm_name = Some(name);
                        }
                    }
                } else if obj == 3 && op == 0 {
                    sync_done = true;
                }
                buf.drain(..size);
            }
        }

        if io_err {
            thread::sleep(Duration::from_secs(2));
            continue;
        }
        let (Some(sn), Some(imn)) = (seat_name, imm_name) else {
            thread::sleep(Duration::from_secs(5));
            continue;
        };

        let mut bind_seat = sn.to_le_bytes().to_vec();
        bind_seat.extend_from_slice(&wl_pack_str("wl_seat"));
        bind_seat.extend_from_slice(&1u32.to_le_bytes());
        bind_seat.extend_from_slice(&4u32.to_le_bytes());

        let mut bind_imm = imn.to_le_bytes().to_vec();
        bind_imm.extend_from_slice(&wl_pack_str("zwp_input_method_manager_v2"));
        bind_imm.extend_from_slice(&1u32.to_le_bytes());
        bind_imm.extend_from_slice(&5u32.to_le_bytes());

        let mut get_im = 4u32.to_le_bytes().to_vec();
        get_im.extend_from_slice(&6u32.to_le_bytes());

        let mut pkt = wl_msg(2, 0, &bind_seat);
        pkt.extend_from_slice(&wl_msg(2, 0, &bind_imm));
        pkt.extend_from_slice(&wl_msg(5, 0, &get_im));
        if stream.write_all(&pkt).is_err() {
            thread::sleep(Duration::from_secs(2));
            continue;
        }

        let mut pending_active = false;
        let mut current_active = false;
        let mut saw_activate = false;
        let mut saw_deactivate = false;
        let mut last_open_write = Instant::now() - Duration::from_secs(10);
        let mut unavailable = false;

        while !unavailable {
            match stream.read(&mut tmp) {
                Ok(0) | Err(_) => break,
                Ok(n) => buf.extend_from_slice(&tmp[..n]),
            }
            while buf.len() >= 8 {
                let obj = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
                let size_op = u32::from_le_bytes([buf[4], buf[5], buf[6], buf[7]]);
                let size = (size_op >> 16) as usize;
                let op = (size_op & 0xffff) as u16;
                if size < 8 || buf.len() < size {
                    break;
                }
                buf.drain(..size);
                if obj == 6 {
                    if op == 0 {
                        pending_active = true;
                        saw_activate = true;
                    } else if op == 1 {
                        pending_active = false;
                        saw_deactivate = true;
                    } else if op == 5 {
                        let now = Instant::now();
                        if pending_active {
                            cancel_kbd_hide();
                            if !current_active
                                || saw_activate
                                || now.duration_since(last_open_write) > Duration::from_millis(350)
                            {
                                current_active = true;
                                last_open_write = now;
                                if get_current_mode() == "tablet" {
                                    set_kbd_open(true);
                                }
                            }
                        } else if current_active || saw_deactivate {
                            current_active = false;
                            schedule_kbd_hide();
                        }
                        saw_activate = false;
                        saw_deactivate = false;
                    } else if op == 6 {
                        unavailable = true;
                        break;
                    }
                }
            }
        }
        if unavailable {
            thread::sleep(Duration::from_secs(5));
        } else {
            thread::sleep(Duration::from_secs(2));
        }
    }
}

fn parse_orient(orient: &str) -> Option<(&'static str, i32)> {
    match orient.trim().trim_end_matches(')') {
        "normal" => Some(("laptop", 0)),
        "bottom-up" => Some(("tablet", 2)),
        "left-up" => Some(("tablet", 1)),
        "right-up" => Some(("tablet", 3)),
        _ => None,
    }
}

fn watch_once() -> bool {
    let Ok(mut child) = Command::new("monitor-sensor")
        .arg("--accel")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let mut has_accel = false;
    if let Some(stdout) = child.stdout.take() {
        let reader = BufReader::new(stdout);
        for line in reader.lines().map_while(Result::ok) {
            if line.contains("Accelerometer mounted") || line.contains("=== Has accelerometer") {
                has_accel = true;
                if let Some((_, rest)) = line.split_once("orientation:") {
                    if let Some((m, tf)) = parse_orient(rest) {
                        set_mode(m, Some(tf), true);
                    }
                }
            } else if line.contains("Failed to claim accelerometer")
                || line.contains("No iio-sensor-proxy")
            {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            } else if let Some((_, rest)) = line.split_once("Accelerometer orientation changed:") {
                has_accel = true;
                if let Some((m, tf)) = parse_orient(rest) {
                    set_mode(m, Some(tf), true);
                }
            }
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    has_accel
}

fn watch_accelerometer() {
    let mut delay = 3u64;
    let mut quick_failures = 0u32;
    loop {
        let t0 = Instant::now();
        let claimed = watch_once();
        let elapsed = t0.elapsed();
        if !claimed {
            quick_failures += 1;
            if quick_failures >= 5 {
                loop {
                    thread::sleep(Duration::from_secs(3600));
                }
            }
        } else {
            quick_failures = 0;
        }
        if elapsed >= Duration::from_secs(30) {
            delay = 3;
        } else {
            delay = (delay * 2).min(120);
        }
        thread::sleep(Duration::from_secs(delay));
    }
}

pub fn keycode_from_name(name: &str) -> Option<u16> {
    match name {
        "KEY_ESC" => Some(1),
        "KEY_1" => Some(2),
        "KEY_2" => Some(3),
        "KEY_3" => Some(4),
        "KEY_4" => Some(5),
        "KEY_5" => Some(6),
        "KEY_6" => Some(7),
        "KEY_7" => Some(8),
        "KEY_8" => Some(9),
        "KEY_9" => Some(10),
        "KEY_0" => Some(11),
        "KEY_MINUS" => Some(12),
        "KEY_EQUAL" => Some(13),
        "KEY_BACKSPACE" => Some(14),
        "KEY_TAB" => Some(15),
        "KEY_Q" => Some(16),
        "KEY_W" => Some(17),
        "KEY_E" => Some(18),
        "KEY_R" => Some(19),
        "KEY_T" => Some(20),
        "KEY_Y" => Some(21),
        "KEY_U" => Some(22),
        "KEY_I" => Some(23),
        "KEY_O" => Some(24),
        "KEY_P" => Some(25),
        "KEY_LEFTBRACE" => Some(26),
        "KEY_RIGHTBRACE" => Some(27),
        "KEY_ENTER" => Some(28),
        "KEY_LEFTCTRL" | "CTRL" => Some(29),
        "KEY_A" => Some(30),
        "KEY_S" => Some(31),
        "KEY_D" => Some(32),
        "KEY_F" => Some(33),
        "KEY_G" => Some(34),
        "KEY_H" => Some(35),
        "KEY_J" => Some(36),
        "KEY_K" => Some(37),
        "KEY_L" => Some(38),
        "KEY_SEMICOLON" => Some(39),
        "KEY_APOSTROPHE" => Some(40),
        "KEY_GRAVE" => Some(41),
        "KEY_LEFTSHIFT" | "SHIFT" => Some(42),
        "KEY_BACKSLASH" => Some(43),
        "KEY_Z" => Some(44),
        "KEY_X" => Some(45),
        "KEY_C" => Some(46),
        "KEY_V" => Some(47),
        "KEY_B" => Some(48),
        "KEY_N" => Some(49),
        "KEY_M" => Some(50),
        "KEY_COMMA" => Some(51),
        "KEY_DOT" => Some(52),
        "KEY_SLASH" => Some(53),
        "KEY_RIGHTSHIFT" => Some(54),
        "KEY_LEFTALT" | "ALT" => Some(56),
        "KEY_SPACE" => Some(57),
        "KEY_102ND" => Some(86),
        "KEY_RIGHTCTRL" => Some(97),
        "KEY_RIGHTALT" | "RALT" | "ALTGR" => Some(100),
        "KEY_UP" => Some(103),
        "KEY_LEFT" => Some(105),
        "KEY_RIGHT" => Some(106),
        "KEY_DOWN" => Some(108),
        "KEY_DELETE" => Some(111),
        _ => None,
    }
}

pub fn parse_key_spec(line: &str) -> Option<(Vec<u16>, u16)> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }
    let parts: Vec<&str> = trimmed.split('+').collect();
    let key_code = keycode_from_name(parts.last()?)?;
    let mut mods = Vec::new();
    for p in &parts[..parts.len() - 1] {
        if let Some(m) = keycode_from_name(p) {
            mods.push(m);
        }
    }
    Some((mods, key_code))
}

fn write_uinput_event(file: &mut File, type_: u16, code: u16, value: i32) {
    let ev = InputEvent {
        tv_sec: 0,
        tv_usec: 0,
        type_,
        code,
        value,
    };
    let bytes: &[u8] = unsafe {
        std::slice::from_raw_parts(
            &ev as *const InputEvent as *const u8,
            std::mem::size_of::<InputEvent>(),
        )
    };
    let _ = file.write_all(bytes);
}

fn send_single_chord(uinput: &mut File, mods: &[u16], key_code: u16) {
    for &m in mods {
        write_uinput_event(uinput, EV_KEY, m, 1);
    }
    write_uinput_event(uinput, EV_KEY, key_code, 1);
    write_uinput_event(uinput, EV_SYN, SYN_REPORT, 0);
    let _ = uinput.flush();
    thread::sleep(Duration::from_millis(10));
    write_uinput_event(uinput, EV_KEY, key_code, 0);
    for &m in mods.iter().rev() {
        write_uinput_event(uinput, EV_KEY, m, 0);
    }
    write_uinput_event(uinput, EV_SYN, SYN_REPORT, 0);
    let _ = uinput.flush();
}

fn hex_char_to_azerty_chord(c: char) -> Option<(&'static [u16], u16)> {
    const SHIFT: &[u16] = &[42];
    const NONE: &[u16] = &[];
    match c.to_ascii_lowercase() {
        '1' => Some((SHIFT, 2)),
        '2' => Some((SHIFT, 3)),
        '3' => Some((SHIFT, 4)),
        '4' => Some((SHIFT, 5)),
        '5' => Some((SHIFT, 6)),
        '6' => Some((SHIFT, 7)),
        '7' => Some((SHIFT, 8)),
        '8' => Some((SHIFT, 9)),
        '9' => Some((SHIFT, 10)),
        '0' => Some((SHIFT, 11)),
        'a' => Some((NONE, 16)), // Q on physical = A on AZERTY
        'b' => Some((NONE, 48)),
        'c' => Some((NONE, 46)),
        'd' => Some((NONE, 32)),
        'e' => Some((NONE, 18)),
        'f' => Some((NONE, 33)),
        _ => None,
    }
}

fn run_kbd_pipe() -> i32 {
    let Ok(mut uinput) = OpenOptions::new().write(true).open("/dev/uinput") else {
        return 1;
    };
    let fd = uinput.as_raw_fd();
    unsafe {
        if libc::ioctl(fd, UI_SET_EVBIT as _, EV_KEY as libc::c_int) < 0 {
            return 1;
        }
        for k in 1..249 {
            libc::ioctl(fd, UI_SET_KEYBIT as _, k as libc::c_int);
        }
        let mut setup = UinputSetup {
            id_bustype: 0x03, // BUS_USB
            id_vendor: 0x1209,
            id_product: 0xae70,
            id_version: 1,
            name: [0u8; 80],
            ff_effects_max: 0,
        };
        let dev_name = b"AetherShell Virtual Keyboard";
        setup.name[..dev_name.len()].copy_from_slice(dev_name);
        if libc::ioctl(fd, UI_DEV_SETUP as _, &setup as *const UinputSetup) < 0 {
            return 1;
        }
        if libc::ioctl(fd, UI_DEV_CREATE as _) < 0 {
            return 1;
        }
    }

    let stdin = io::stdin();
    for raw in stdin.lock().lines().map_while(Result::ok) {
        for step in raw.trim().split(',') {
            let step = step.trim();
            if step.is_empty() {
                continue;
            }
            if let Some(hex) = step.strip_prefix("UNICODE+") {
                // GTK / Qt / Firefox IBus/Wayland Unicode compose: Ctrl+Shift+U, hex digits, Enter
                send_single_chord(&mut uinput, &[29, 42], 22); // CTRL+SHIFT+KEY_U
                thread::sleep(Duration::from_millis(8));
                for hc in hex.chars() {
                    if let Some((mods, kc)) = hex_char_to_azerty_chord(hc) {
                        send_single_chord(&mut uinput, mods, kc);
                        thread::sleep(Duration::from_millis(6));
                    }
                }
                send_single_chord(&mut uinput, &[], 28); // KEY_ENTER
            } else if let Some((mods, key_code)) = parse_key_spec(step) {
                send_single_chord(&mut uinput, &mods, key_code);
                thread::sleep(Duration::from_millis(6));
            }
        }
    }

    unsafe {
        libc::ioctl(fd, UI_DEV_DESTROY as _);
    }
    0
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("status");
    match action {
        "laptop" | "tablet" => {
            println!("{}", set_mode(action, None, false));
            0
        }
        "toggle" => {
            let next = if get_current_mode() == "tablet" {
                "laptop"
            } else {
                "tablet"
            };
            println!("{}", set_mode(next, None, false));
            0
        }
        "lock" => {
            println!("{}", set_rotation_lock(true));
            0
        }
        "unlock" => {
            println!("{}", set_rotation_lock(false));
            0
        }
        "lock-toggle" => {
            println!("{}", set_rotation_lock(!is_rotation_locked()));
            0
        }
        "kbd-pipe" => run_kbd_pipe(),
        "daemon" => {
            ensure_wayland_hypr_env();
            sync_initial_transform_from_hypr();
            thread::spawn(watch_sw_tablet_mode);
            thread::spawn(watch_touchscreen_gestures);
            thread::spawn(watch_input_method);
            watch_accelerometer();
            0
        }
        _ => {
            println!(
                "{}",
                json!({
                    "mode": get_current_mode(),
                    "rotation_locked": is_rotation_locked(),
                })
            );
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_transforms_to_expected_mode() {
        assert_eq!(mode_for_transform(0), "laptop");
        assert_eq!(mode_for_transform(4), "laptop");
        assert_eq!(mode_for_transform(1), "tablet");
        assert_eq!(mode_for_transform(2), "tablet");
        assert_eq!(mode_for_transform(3), "tablet");
    }

    #[test]
    fn parses_key_specs_with_modifiers() {
        assert_eq!(
            parse_key_spec("KEY_SPACE"),
            Some((vec![], 57))
        );
        assert_eq!(
            parse_key_spec("SHIFT+KEY_LEFT"),
            Some((vec![42], 105))
        );
        assert_eq!(
            parse_key_spec("CTRL+SHIFT+KEY_RIGHT"),
            Some((vec![29, 42], 106))
        );
        assert_eq!(
            parse_key_spec("RALT+KEY_E"),
            Some((vec![100], 18))
        );
    }
}
