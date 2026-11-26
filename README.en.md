# AetherShell

[FR](README.md) · [EN](README.en.md) · [ES](README.es.md) · [DE](README.de.md)

A desktop environment for [Hyprland](https://hyprland.org), featuring an island-style bar, modular panels, desktop widgets, and everyday tools, written in QML/Qt and powered by [Quickshell](https://quickshell.org).

> **Note:** AetherShell does not claim to reinvent the wheel or establish itself as a standard. It is simply a personal desktop environment among others, still young and actively evolving (`0.4.x` cycle with a unified Rust backend), designed to fit a daily workflow and refine over experience.

---

## 1. Overview

Rather than a simple bar theme, AetherShell brings together the visual and utility components of the graphical session:

* **Main Bar & Modular Capsule**: two switchable modes, configurable on the fly:
  * *Classic*: a three-island layout (left, center, right) enclosed in a shared capsule with customizable separation transparency and morphed bar-aligned panels (`PanneauSurface`).
  * *Dynamic Island* (`DynamicIsland`): an all-in-one interactive central pill configurable via its dedicated **Dynamic Island** tab (4-state selector *Hidden / Rest / Expanded / Both* per indicator and applet) — compact at rest (clock, media title, multi-source **Live Activity**, integrated OSD, conditional updates), expanded on hover, featuring **animated inline weather**, **inline wallpaper picker** (`SUPER + W`, `aether-wp` submap), **inline color scheme picker** (`SUPER + C`, `aether-scheme` submap), **app launcher & `as` command bar** (`SUPER + R`), **quick notes** (`SUPER + N`), and a tabbed expanded panel (*Controls* with work contexts `Normal / Focus / Meeting / Chill`, Caffeine, Performance, audio output, and scratchpad; *Alerts & Tasks* with collapsible agenda; *System & Network* with battery charge limiter; *Appearance*; *Planka Projects*), fully keyboard-driven (`SUPER + I` / `SUPER + ALT + H`, `SubmapWhichKey`).
* **Window Overview & Scratchpad**: *Mission Control* overlay ([`OverviewOverlay.qml`](dev/OverviewOverlay.qml), `SUPER + G`) displaying workspace windows with live thumbnails and instant filtering, plus scratchpad management (`SUPER + ,` / `SUPER + SHIFT + ,`).
* **Optional Secondary Bars**: support for a bottom bar and vertical side bars following the same component architecture.
* **Unified Configuration Panel**: accessible via a hotkey (`SUPER + SHIFT + H`, while `SUPER + H` toggles the Dynamic Island panel) or by middle-clicking any applet. Allows tuning appearance (palettes, blurs, corner radii, opacity), favorite applications, displays, idle timeout (`hypridle`), autostart, and local secrets, with live hot-reloading without restarting the session.
* **Dockable Desktop Widgets**: draggable blocks (tasks, system monitor, weather, music, clock, agent...) configurable and filterable by virtual workspace (middle-click to restrict a widget to one or more workspaces).
* **Reactive Audio Visualizer**: discreet integration of a native PipeWire waveform (`pwscope`) or spectral bars (`cava`), with automatic sleep after ten seconds of silence to conserve GPU/CPU resources.
* **Task Tracking & Hermes Integration**: local Markdown checklist management (`- [ ]`) with a graphical file picker and an optional monitoring switch delegating checked tasks to the Hermes agent via a background worker.
* **Integrated Graphical Selectors**: modal sheets drawn directly within the shell surface ([`SelecteurDossier.qml`](dev/SelecteurDossier.qml), [`SelecteurFichier.qml`](dev/SelecteurFichier.qml)), bypassing the limitation of traditional Wayland dialogs that would open beneath the overlay layer surface.
* **Theme Profiles & Shipped Catalog** (`theme_profile`): one gesture applies a whole desktop — wallpaper, Matugen palette, shell ambience (28 style keys), icon pack, cursor and an optional reference to an environment profile (night, focus, cafés…). Nine curated presets ship with their 1920×1080 wallpapers (`dev/wallpapers/`, ~2.6 MB total), copied into the folder chosen during the first-run wizard and referenced by **file name only**. Each application is transactional: the previous state is archived (`__avant__`), a failing palette restores the shell style *before* touching icons or cursor, and "applied" is only announced after re-reading the live state.
* **Cursor Manager** (`curseurs`): lists, previews, installs and applies cursor packs across all five channels at once — compositor (`hyprctl setcursor`), GNOME settings, GTK3/GTK4 INI, `environment.d` and `style_vars.json` — with a size range of 16–64 px.
* **Light / Dark Axis** (`theme_mode: auto | dark | light`): Matugen is called with the matching mode and the variant of each token is read accordingly, so a wallpaper can be forced light or dark. The shell, the bar, the panels and Hyprland switch instantly; GTK and Qt applications only follow at launch (their theme files are read at startup), which the UI states explicitly.
* **Login Screen Manager (SDDM)**: configuration of the Astronaut theme and Qylock variants from the panel, automatic keyboard layout and UTF-8 locale synchronization from the first-run wizard (or Keyboard tab), and a safe preview launcher isolating tests on a dedicated workspace (`workspace 99`) to never freeze the active session.

---

## 2. Deployment & Updates

### One-Line Install or Update

```sh
mkdir -p "$HOME/.cache/quickshell" \
  && curl -fsSL -o "$HOME/.cache/quickshell/install_aethershell.sh" \
     https://raw.githubusercontent.com/anderveg/aethershell/master/install.sh \
  && bash "$HOME/.cache/quickshell/install_aethershell.sh"
```

Le script est **téléchargé puis exécuté**, jamais passé par un tube : il se ré-exécute lui-même
depuis le disque après la préparation du dépôt, et cet `exec` tuerait le `bash` qui lit le tube —
`curl` sortirait alors en erreur 23 (« Failure writing output to destination ») alors que
l'installation continue. Un fichier laisse aussi `stdin` au terminal, donc les invites
(`sudo`, confirmation de désinstallation) fonctionnent.

[`install.sh`](install.sh) handles everything: it detects the distribution from `/etc/os-release` (Arch or Fedora), clones the repository or fast-forwards it if already present, backs up the environment, and deploys the shell. The exact same command serves for initial installation and subsequent updates.

Options: `--dir PATH` (default: `$AETHERSHELL_DIR`, otherwise `~/dev/aethershell` if present, otherwise `~/dev/aethershell`), `--arch` / `--fedora` to override the target instead of reading `/etc/os-release`, `--branche NAME`, `--check` (status only, without deploying), `--no-deploy`, `--help`. With the one-line curl command, pass them after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/anderveg/aethershell/master/install.sh | bash -s -- --check
```

The panel tracks the same version as the script: "Displays & System" → "Shell Updates" displays the deployed version, the version published on GitHub, and available actions (check now, update in a terminal, copy the one-liner for another machine). `core/version.json` is written on every deployment, and `as-core maj-shell` queries GitHub only once every **280 minutes** — between checks, it serves from cache, avoiding unnecessary network calls when opening the panel.

### Manual Deployment

Deployment is handled by [`install.sh`](install.sh), compatible with **Arch Linux** and **Fedora** (auto-detected via `/etc/os-release`):

```sh
# Check required dependencies without installing anything
./install.sh --deps

# Pre-flight diff analysis (Repository ➜ Live system) without modifications
./install.sh --diff

# Full deployment with prior backup (tarball + fine-grained snapshot)
./install.sh --arch    # or ./install.sh --fedora

# Fast deployment without new backup (when the state is already archived)
./install.sh --deploy-only

# Uninstall: removes the shell, its systemd units and resets ~/.config/hypr to a
# minimal configuration (SUPER + Return and SUPER + T open a terminal)
./install.sh --uninstall          # confirmation by typing "uninstall"
./install.sh --uninstall --purge  # same + SDDM themes, caches and backups
```

`--uninstall` first archives `~/.config/quickshell` and `~/.config/hypr` into
`~/.config/backups_env/uninstall_<timestamp>/`, then removes only what the
deployment had installed: the five user systemd units, the shell itself, and on
the system side the `greeter-palette` helper, its polkit rule and the SDDM
drop-ins (root password requested). `--dry-run` lists the actions without touching
anything. System packages are never removed. The same option lives in the config
panel: **System** tab ➜ **Shell update** drawer ➜ *Uninstall AetherShell*.

### Strict Protection of Local Data

Deployment never blindly replaces live files:
* **Protected local states**: `style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `todo.json`, `secrets.json`, `theme_profiles.json` (your own profiles), etc. are never overwritten if they already exist on the target machine. Shipped theme presets carry `created_at: 0` and are refreshed by `as-core catalogue install`; as soon as you re-save one, it takes your own date and is never replaced.
* **Custom Hyprland configuration**: `binds.lua`, `input.lua`, `general.lua`, and hardware profiles remain authoritative. In case of differences with the repository, a comparative `.upstream` copy is created without touching the active file.
* **Granular safety net**: each deployment creates a backup `.tar.gz` archive and an uncompressed mirror snapshot under `~/.config/backups_env/snapshots/<timestamp>/` with a SHA-256 fingerprint table (`manifest.json`), enabling single-file restoration when needed (`./install.sh --restore-file <path>`).

---

### Multi-User and Multi-Machine Support

Nothing in the repository hardcodes a username, personal folder, or machine hostname: AetherShell installs under any user account, and `./install.sh` always writes to the `$HOME` of the user running it.

Paths are constructed using variables, never hardcoded:

| Context | To use |
|---|---|
| shell | `"$HOME"`, `"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"` |
| Rust | `paths::home_dir()`, `paths::runtime_dir()` (`dev/rust/as-core/src/common/paths.rs`) |
| QML | `Quickshell.env("HOME")`, `Quickshell.env("XDG_RUNTIME_DIR")` |
| systemd unit | `%h` (unit directive) |

`dev/core/as-core neutralite` inspects **tracked** files: it flags any `/home/<name>` that is not a placeholder, as well as the username and machine hostname. The deployment pre-flight runs it and displays a warning. A line may include an explicit exception — `neutralite:ok — <reason>` — for intentional compatibility.

---

## 3. Prerequisites

* **Compositor**: [Hyprland](https://hyprland.org) 0.57 or newer (modular Lua configuration);
* **UI Engine**: [Quickshell](https://quickshell.org) 0.3.2 or newer;
* **Icon Font**: `0xProto Nerd Font` (installer provided in `dev/core/install_fonts.sh`);
* **Rust**: `cargo` (`rust` package on Arch) — the `as-core` backend is compiled on deployment; without it, Rust fixes never take effect;
* **System Dependencies**: listed by distribution in [`dev/dependencies.txt`](dev/dependencies.txt) (`matugen`, `wireplumber`, `NetworkManager`, `cava`, etc.).

---

## 4. Project Structure

```
install.sh            # Unified script: install, update, pre-flight checks, deployment, and backups
dev/
├── rust/as-core/     # Unified Rust backend (compiled to dev/core/as-core)
├── core/             # as-core binary, JSON catalogues, caches and shell integration scripts
├── wallpapers/       # Nine 1920×1080 wallpapers shipped with the theme catalog (~2.6 MB)
├── widgets/          # Desktop components (clock, todo, system, weather...)
├── hypr_modular/     # Modular Hyprland configuration in Lua
├── hyprquickpaper/   # Wallpaper engine and palette management
├── sddm/             # Scripts and helpers for SDDM login screen
├── charge-limit/     # polkit action + root helper for the battery charge limit (`aether-charge-limit`)
├── systemd/          # User systemd units (quickshell.service...)
└── *.qml             # Quickshell surfaces (bar, panel, popups, selectors...)
```

---

## 5. Acknowledgments & Code Borrowing

AetherShell did not emerge in a vacuum: it builds upon bricks, concepts, and code snippets from other open source projects with compelling approaches. Many thanks to the following authors for their work shared under open licenses (notably the [Noctalia Community Plugins](https://github.com/noctalia-dev/community-plugins) collection, under the MIT license):

| Component / Concept | Original Author | Description |
|---|---|---|
| [Visualizer+](https://github.com/noctalia-dev/community-plugins/tree/main/visualizerp) | **al3x** | PipeWire capture engine in C (`pwscope.c`), compiled locally to feed the audio waveform. |
| [Agentik](https://github.com/noctalia-dev/community-plugins/tree/main/agentik) | **notfinaldev** | Principles of non-blocking agent status polling, process/session matching, and state management. |
| [USB Manager](https://github.com/noctalia-dev/community-plugins/tree/main/usb-manager) | **Marco Ziliani** | Hardware polling architecture reading directly from `sysfs` and `udev` without requiring a heavy resident daemon. |
| [To Do](https://github.com/noctalia-dev/community-plugins/tree/main/todo) | **nightwatch75** | Initial inspiration for decoupling the bar applet and desktop widget for task lists. |
| [NVTOP](https://github.com/noctalia-dev/community-plugins/tree/main/nvtop) | **tordex** | On-demand system monitoring principle (process spawned only when the view is opened). |
| [Wallpaper Depth](https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth) | **noctalia** | Visual immersion concept for islands using depth maps (Depth Anything V2). |
| [WallpaperFx.qml (`pocket-dots`)](https://github.com/diegoMalagrida/pocket-dots) | **diegoMalagrida** | Shader-based wallpaper transitions (`WallpaperFx.qml` / `wallfx.frag`: organic 4 px cell spread and seamless `awww` handover). |
| **Quickshell & Hyprland** | **outfoxxed & vaxerski** | For these two major projects that make building a modern, performant Wayland shell possible. |

---

## 6. License

AetherShell is distributed under the MIT license — see the [`LICENSE`](LICENSE) file for details.
