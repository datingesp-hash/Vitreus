-- Settings > Theme > Pin widgets: the desktop widgets that come with a theme, which are on and where they are. With the switch on, the theme in use
-- keeps the widgets as they are now; choosing a theme that has them puts them back as they were (each one shown or hidden, on its cell and monitor), and
-- leaving it keeps them as they were left, so moving a widget while the theme is in use is remembered too. A theme with none leaves the widgets alone,
-- as before. Nothing is pinned until someone pins it.
--   The widgets: the clock, the system monitor, the calendar and the reminders (their own scenes, asked and told over their sockets, as Settings >
--   Widgets and the desktop editor do), and the audio visualiser (the bottom edge, Vitreus's own `fw_on`). The webcam is left out on purpose: a
--   theme switch never turns a camera on. Sticky notes are what is written on them, not a widget to place.
--   Kept in theme-widgets.json in the data folder: { [theme id] = { [scene] = { [fact] = value }, fw_on = bool } }.
-- `w`: what vitreus.luau lends it, as functions (see CLAUDE.md): theme() the theme in use, its id and name; start(scene dir) starts a widget's scene.
return function(w)
    local FILE = "theme-widgets.json"
    -- Each scene, and the facts that say whether it is shown and where (written in this order: the place first, then shown).
    local WIDGETS = {
        { scene = "desktopclock", shown = { "shown" }, facts = { "where", "gx", "gy", "mon", "shown" } },
        { scene = "desktopsysmon", shown = { "shown" }, facts = { "where", "gx", "gy", "mon", "shown" } },
        { scene = "desktopcards", shown = { "cal_shown", "rem_shown" }, facts = { "cal_gx", "cal_gy", "cal_mon", "rem_gx", "rem_gy", "rem_mon", "cal_shown", "rem_shown" } },
    }
    local pins = {}
    local last = nil                 -- the theme the widgets were last put up for (what is kept when it is left)

    local ok, saved = pcall(sys.ask, "files.read", FILE, "json")
    if ok and type(saved) == "table" then
        for id, snap in pairs(saved) do
            if type(id) == "string" and type(snap) == "table" then pins[id] = snap end
        end
    end
    local function save() pcall(sys.call, "files.write", FILE, pins) end
    local function same(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    local function say(scene, cmds, done)
        local args = { "--say", scene }
        for _, c in ipairs(cmds) do args[#args + 1] = c end
        run("pleamar", args, function(out, code) if done then done(out, code) end end)
    end
    local function fw() return fact.fw_on == true or fact.fw_on == 1 end
    local function value(s)
        s = (s or ""):match("^%s*(.-)%s*$")
        if s == "true" then return true elseif s == "false" then return false end
        return tonumber(s) or s
    end

    -- How many of them a snapshot has on the desktop.
    local function count(snap)
        local n = snap.fw_on and 1 or 0
        for _, wd in ipairs(WIDGETS) do
            local s = snap[wd.scene]
            if type(s) == "table" then for _, k in ipairs(wd.shown) do if s[k] == true then n = n + 1 end end end
        end
        return n
    end

    -- The row on the Theme page.
    local function show()
        local id, name = w.theme()
        if not id then return end
        if not last then last = id end
        local p = pins[id]
        fact.twg_on = p ~= nil
        if p then
            local n = count(p)
            text.twg_sub = n == 1 and "1 widget kept" or (n .. " widgets kept")
        else
            text.twg_sub = "Off"
        end
    end

    -- The widgets as they are now: each scene is asked for its facts (one line each). A scene that does not answer has nothing shown, unless `prev`
    -- (the theme's last snapshot) has it: a widget's scene reloads when the theme rewrites the palette, and one caught reloading keeps what it had.
    local function snapshot(prev, done)
        local snap = { fw_on = fw() }
        local left = #WIDGETS
        for _, wd in ipairs(WIDGETS) do
            local cmds = {}
            for _, k in ipairs(wd.facts) do cmds[#cmds + 1] = "get " .. k end
            local tries = 0
            local function ask()
                say(wd.scene, cmds, function(out, code)
                    -- "? the render does not answer": the scene is busy (reloading with a new palette, or drawing a heavy frame); asked again a few times
                    local busy = code == 0 and (out == nil or out:find("?", 1, true) ~= nil)
                    if busy and tries < 4 then tries = tries + 1; after(700, ask) return end
                    local s = {}
                    if code == 0 and not busy then
                        local i = 0
                        for line in (out .. "\n"):gmatch("([^\n]*)\n") do
                            i = i + 1
                            local k = wd.facts[i]
                            if not k then break end
                            local v = value(line)
                            if v ~= "" then s[k] = v end
                        end
                    elseif prev and type(prev[wd.scene]) == "table" then
                        s = prev[wd.scene]        -- not running, or never answered: what it had (a scene caught restarting keeps its place)
                    end
                    for _, k in ipairs(wd.shown) do if s[k] == nil then s[k] = false end end
                    snap[wd.scene] = s
                    left = left - 1
                    if left == 0 then done(snap) end
                end)
            end
            ask()
        end
    end

    -- Put a snapshot back: a widget that should be shown is started if its scene is not running, then given its place and shown; one that should not
    -- be is hidden (a scene that is not running is already hidden).
    local function restore(snap)
        for _, wd in ipairs(WIDGETS) do
            local s = snap[wd.scene]
            if type(s) == "table" then
                local want = false
                for _, k in ipairs(wd.shown) do if s[k] == true then want = true end end
                local cmds = {}
                for _, k in ipairs(wd.facts) do
                    if s[k] ~= nil then cmds[#cmds + 1] = "fact " .. k .. " " .. tostring(s[k]) end
                end
                local tries = 0
                local function go()
                    say(wd.scene, { "get " .. wd.shown[1] }, function(out, code)
                        if code == 0 and (out or ""):find("?", 1, true) and tries < 4 then tries = tries + 1; after(700, go) return end     -- busy: again in a moment
                        if code == 0 then
                            -- a widget that is running slides to its place: `glide` first, the place once the slower spring has taken over, and back
                            say(wd.scene, { "fact glide true" }, function()
                                after(450, function()
                                    say(wd.scene, cmds)
                                    after(2600, function() say(wd.scene, { "fact glide false" }) end)
                                end)
                            end)
                        elseif want then
                            w.start(wd.scene)
                            after(2500, function() say(wd.scene, cmds) end)
                        end
                    end)
                end
                go()
            end
        end
        if type(snap.fw_on) == "boolean" and snap.fw_on ~= fw() then say("vitreus", { "emit fw_toggle" }) end
    end

    -- The switch: on keeps the widgets as they are now for the theme in use; off lets it go back to leaving them alone.
    on("twg_toggle", function()
        local id = w.theme()
        if not id then return end
        if pins[id] then
            pins[id] = nil
            save()
            show()
        else
            snapshot(nil, function(snap)
                pins[id] = snap
                last = id
                save()
                show()
            end)
        end
    end)

    -- While a theme has its widgets pinned, they are looked at now and then and kept as they are (a widget moved, shown or hidden from the desktop
    -- editor, Settings > Widgets or the launcher), so what is kept is how the theme was left. Not in the seconds after a theme switch, when the widgets
    -- are being put back.
    local quiet_until = 0
    every(10000, function()
        local id = last
        if not id or not pins[id] or os.time() < quiet_until then return end
        snapshot(pins[id], function(snap) if last == id and pins[id] and os.time() >= quiet_until and not same(snap, pins[id]) then pins[id] = snap; save(); show() end end)
    end)

    -- A card on the Theme page: the theme being left keeps its widgets as they are (if it has them pinned: asked at once, before the widgets reload
    -- with the new palette), then the new one's are put back once they are back (as `push_look` tells them the look again, a moment later).
    on("theme_pick", function()
        local id = w.theme()                 -- (vitreus.luau's handler has already set it)
        local from = last
        last = id
        show()
        if not id or id == from then return end
        quiet_until = os.time() + 8
        if from and pins[from] then
            local keep = from
            snapshot(pins[keep], function(snap) if pins[keep] then pins[keep] = snap; save() end end)
        end
        if pins[id] then
            -- twice: a widget still reloading with the new palette when the first comes misses it
            after(1800, function() if last == id and pins[id] then restore(pins[id]) end end)
            after(4500, function() if last == id and pins[id] then restore(pins[id]) end end)
        end
    end)
    on("themes_refresh", function() after(800, show) end)
    on("fact:set_page", show)
    after(1500, show)          -- once the themes have been read
end
