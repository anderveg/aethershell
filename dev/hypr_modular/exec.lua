-- ~/.config/hypr/exec.lua
-- Autostart & Variables d'environnement (Compatible Arch Linux & Fedora)
--
-- L'autostart est géré depuis le panneau de configuration :
--   core/autostart.json (dev) -> autostart_cmds.txt (généré, lu ci-dessous)
-- Ne pas éditer autostart_cmds.txt à la main.
--
-- NOTE: on utilise un timer one-shot plutôt que hl.on("hyprland.start") :
-- sur Hyprland 0.57.0 l'événement hyprland.start n'est pas émis de façon
-- fiable, alors que hl.timer fonctionne. Le timer ne se déclenche qu'une
-- fois au chargement du fichier (donc au démarrage de session), pas au
-- hyprctl reload (qui re-exécute le fichier mais le timer est déjà passé).

-- Curseur : thème et taille lus dans style_vars.json (posés par le panneau via
-- `as-core curseurs apply`) puis poussés aux applications lancées par le
-- compositeur. `environment.d` couvre celles lancées hors de Hyprland et n'est
-- relu qu'à la connexion : les deux canaux doivent rester alignés.
-- Repli dur (Vimix-cursors / 24) et bornage 16..64 : une valeur absente ou
-- aberrante ne doit jamais empêcher le chargement de la config.
local function read_style_vars_texte()
    local p = os.getenv("HOME") .. "/.config/quickshell/core/style_vars.json"
    local f = io.open(p, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function read_cursor_settings()
    local s = read_style_vars_texte()
    local theme = "Vimix-cursors"
    local size = 24
    if s then
        local t = s:match('"cursor_theme"%s*:%s*"([^"]*)"')
        if t and t ~= "" then theme = t end
        local n = s:match('"cursor_size"%s*:%s*(%d+)')
        local v = tonumber(n)
        if v and v >= 16 and v <= 64 then size = v end
    end
    return theme, tostring(size)
end

local CURSOR_THEME, CURSOR_SIZE = read_cursor_settings()
hl.env("XCURSOR_THEME", CURSOR_THEME)
hl.env("HYPRCURSOR_THEME", CURSOR_THEME)
hl.env("XCURSOR_SIZE", CURSOR_SIZE)
hl.env("HYPRCURSOR_SIZE", CURSOR_SIZE)

local function get_marker_path()
    local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default"
    local run_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    return run_dir .. "/hypr_autostart_" .. sig
end

local function run_cmd_file(path)
    local f = io.open(path, "r")
    if not f then
        return
    end
    for line in f:lines() do
        local cmd = line:match("^%s*(.-)%s*$")
        if cmd ~= "" and cmd:sub(1, 1) ~= "#" then
            hl.exec_cmd(cmd)
        end
    end
    f:close()
end

local function run_autostart_file()
    -- Ne s'exécute qu'une seule fois par session Hyprland.
    -- Évite de relancer l'autostart (et de dupliquer quickshell) lors des
    -- rechargements de configuration déclenchés par Matugen / colors.lua.
    local marker = get_marker_path()
    local mf = io.open(marker, "r")
    if mf then
        mf:close()
        return
    end

    local wf = io.open(marker, "w")
    if wf then
        wf:write(tostring(os.time()))
        wf:close()
    end

    local hypr_dir = os.getenv("HOME") .. "/.config/hypr/"
    run_cmd_file(hypr_dir .. "autostart_cmds.txt")
    run_cmd_file(hypr_dir .. "user/autostart.txt")
end

-- Timer one-shot de 1s : laisse le compositor finir de démarrer,
-- puis exécute l'autostart une seule fois.
local t = hl.timer(function()
    run_autostart_file()
end, { timeout = 1000, type = "oneshot" })
t:set_enabled(true)
