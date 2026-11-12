-- Which monitor a desktop widget is on: shared by the desktop widgets (desktopclock/, desktopsysmon/: a link to this file in each folder).
--
-- The widget is one surface (`surface face { screens: scr }`), on one monitor: the one its settings name (`monitor`). While that one is not plugged
-- in the widget is not shown anywhere (it does not move in with another monitor's widgets), and it is back when it is; only in Edit mode is it shown,
-- on the first monitor and marked as without one (`orphan`), so that a widget whose monitor is gone for good can still be found and placed: dragged
-- there, that is its monitor from then on. It used to be a copy of the whole scene on every monitor, a full-screen
-- surface each (~27 MB on the card per 1080p monitor, drawing or not), with the card drawn by one copy and the others empty; and dragging it to
-- another monitor handed the drag from one copy to another halfway, which is where it got stuck.
--
-- To move it to another monitor it is dragged over there, in Edit mode, and let go where it should go. With a mouse the drag itself ends at the edge
-- (the compositor lets go of it as the pointer goes on to the other monitor, and the scene is not told when the button comes up there), so from the
-- edge on the widget is carried: it follows the pointer on a second surface, `ghost`, put on that monitor as the drag began, while bin/vitreus-btnwait
-- listens for the button; let go, it is put in the cell under it, on the monitor it is over. Surfaces are put on and taken off monitors only while
-- they draw nothing (the compositor fades a layer in and out), which was the flicker. Without access to the input devices it slides over to the
-- edge instead. Or Settings > Widgets (`text mon_name`).
--
-- The monitors are learnt from `hyprctl monitors` (Hyprland's JSON, or pleamar-wm's text): names, and where they lie, which says which monitor is
-- behind each edge (`nb_l`, `nb_r`, `nb_t`, `nb_b`, and their names in `nbn_*` for the hint). Where it does not answer (niri without the wrapper),
-- the names the scene's 1 x 1 copies report (`screen.K.name`) are enough to place it; pushing over an edge then does nothing, Settings still does.
--
-- `w`: { scene = its socket's name, cfg = its settings table (`monitor` is read and written), save = function, moved = function(gx, gy) (pushed over an
-- edge: the cell it comes in at), placed = function(name) (it is on another monitor now) }.
return function(w)
    local cfg, save = w.cfg, w.save
    local mons = {}                 -- { name, x, y, w, h } (x and the rest nil when only the name is known), in the compositor's order
    local nb = {}                   -- side -> monitor name: "l", "r", "t", "b"
    local SIDES = { "l", "r", "t", "b" }

    local function find(name)
        for _, m in ipairs(mons) do if m.name == name then return m end end
        return nil
    end

    -- The monitors behind each edge of `m`: one that touches it along that edge (within 2 px, logical pixels) and overlaps it across.
    local function neighbours(m)
        nb = {}
        if m and m.x then
            for _, o in ipairs(mons) do
                if o ~= m and o.x then
                    local across_v = o.y < m.y + m.h and o.y + o.h > m.y
                    local across_h = o.x < m.x + m.w and o.x + o.w > m.x
                    if across_v and math.abs(o.x + o.w - m.x) <= 2 then nb.l = nb.l or o.name end
                    if across_v and math.abs(m.x + m.w - o.x) <= 2 then nb.r = nb.r or o.name end
                    if across_h and math.abs(o.y + o.h - m.y) <= 2 then nb.t = nb.t or o.name end
                    if across_h and math.abs(m.y + m.h - o.y) <= 2 then nb.b = nb.b or o.name end
                end
            end
        end
        for _, s in ipairs(SIDES) do
            fact["nb_" .. s] = nb[s] ~= nil
            text["nbn_" .. s] = nb[s] or ""
        end
    end

    -- Puts it on its monitor. Nothing known yet: left as it is. No monitor chosen yet: the first one. Its monitor not plugged in: nowhere, but in Edit
    -- mode, where it is on the first one, marked (`orphan`). While it is hidden (`shown` false, and not in Edit mode) it has no surface at all: a hidden
    -- widget kept a full-screen one on the card all the same.
    local hidden = false
    local function editing() return fact.edit == true or fact.edit == 1 end
    local function place()
        if not mons[1] then return end
        if cfg.monitor == "" then cfg.monitor = mons[1].name; save() end
        local m = find(cfg.monitor)
        local orphan = m == nil
        if orphan and editing() then m = mons[1] end
        fact.orphan = orphan
        text.orph = orphan and (cfg.monitor .. " · not connected") or ""
        local want = (hidden or not m) and "" or m.name
        local moved = text.scr ~= want and want ~= ""
        if text.scr ~= want then text.scr = want end
        if text.mon_name ~= cfg.monitor then text.mon_name = cfg.monitor end       -- (its own monitor, plugged in or not: Settings lights that one)
        neighbours(m)
        if moved and w.placed then w.placed(m.name) end
    end

    -- The names the scene's own 1 x 1 copies report: the monitors there are, without where they lie.
    local function from_copies()
        local list, seen = {}, {}
        local n = math.max(1, math.min(4, math.floor((tonumber(fact["screens.count"]) or 4) + 0.5)))
        for k = 0, n - 1 do
            local nm = text["screen." .. k .. ".name"]
            if nm and nm ~= "" and not seen[nm] then seen[nm] = true; list[#list + 1] = { name = nm } end
        end
        return list
    end

    local function refresh()
        run("hyprctl", { "monitors", "-j" }, function(out, code)
            local list = {}
            if code == 0 and out then
                local ok, got = pcall(json.decode, out)
                if ok and type(got) == "table" then
                    table.sort(got, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
                    for _, d in ipairs(got) do
                        if type(d) == "table" and type(d.name) == "string" then
                            local sc = tonumber(d.scale) or 1
                            local mw, mh = (tonumber(d.width) or 0) / sc, (tonumber(d.height) or 0) / sc
                            if (tonumber(d.transform) or 0) % 2 == 1 then mw, mh = mh, mw end
                            list[#list + 1] = { name = d.name, x = tonumber(d.x) or 0, y = tonumber(d.y) or 0, w = math.floor(mw + 0.5), h = math.floor(mh + 0.5) }
                        end
                    end
                else
                    -- pleamar-wm's `hyprctl monitors` is text ("Monitor <name> (ID 1):", "2560x1440@164.83 at 1440x730", "scale: 1.00"), its sizes already turned.
                    local found = {}
                    for name, id, body in (out .. "\n\n"):gmatch("Monitor (%S+) %(ID (%d+)%):\n(.-)\n\n") do
                        local mw, mh, x, y = body:match("(%d+)x(%d+)@[%d%.]+ at (%-?%d+)x(%-?%d+)")
                        if mw then
                            local sc = tonumber(body:match("scale:%s*([%d.]+)")) or 1
                            found[#found + 1] = { id = tonumber(id), name = name, x = tonumber(x), y = tonumber(y), w = math.floor(tonumber(mw) / sc + 0.5), h = math.floor(tonumber(mh) / sc + 0.5) }
                        end
                    end
                    table.sort(found, function(a, b) return a.id < b.id end)
                    for _, d in ipairs(found) do list[#list + 1] = d end
                end
            end
            if #list == 0 then list = from_copies() end
            if #list == 0 then return end
            mons = list
            place()
        end)
    end

    -- Monitors come and go rarely. On Hyprland its event socket says when (added, removed, a config reload that may move one), with a look every
    -- minute for a missed event; elsewhere every five seconds. A copy reporting a new name (a monitor plugged in) is looked at too.
    local events = false
    local function watch()
        run("printenv", { "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE" }, function(out, code)
            local rt, sig = (out or ""):match("^([^\n]+)\n([^\n]+)")
            if code ~= 0 or not rt or not sig then return end
            local ok = pcall(spawn, "socat", { "-u", "UNIX-CONNECT:" .. rt .. "/hypr/" .. sig .. "/.socket2.sock", "-" }, function(line)
                if line:match("^monitoradded") or line:match("^monitorremoved") or line:match("^configreloaded") then after(400, refresh) end
            end, function()
                events = false
                after(5000, watch)
            end)
            events = ok
        end)
    end
    local ticks = 0
    every(5000, function()
        ticks = ticks + 1
        if (not events or ticks % 12 == 0) and not fact.dragging then refresh() end
    end)
    local pending = false
    for k = 0, 3 do
        on("text:screen." .. k .. ".name", function()
            if pending then return end
            pending = true
            after(300, function() pending = false; refresh() end)
        end)
    end
    refresh()
    watch()

    -- Hidden: the surface goes once the face has faded out (`sh`, a calm spring: about a second); shown, or Edit mode, it comes back at once.
    local vis_n = 0
    local function visibility()
        vis_n = vis_n + 1
        local mine = vis_n
        local off = not (fact.shown == true or fact.shown == 1) and not (fact.edit == true or fact.edit == 1)
        if not off then
            hidden = false
            place()                 -- (also: in Edit mode a widget without its monitor shows, and it goes when Edit mode ends)
            return
        end
        after(1500, function()
            if mine ~= vis_n then return end
            hidden = true
            place()
        end)
    end
    on("fact:shown", visibility)
    on("fact:edit", visibility)
    after(2000, visibility)         -- (`shown` is set by the logic when it starts, which fires nothing)

    -- Settings > Widgets, or a theme's pinned widgets: "show it on this monitor", by name. One that is not plugged in is not taken: it stays where
    -- it is, and says so (the text goes back).
    on("text:mon_name", function(t)
        if find(t) then
            cfg.monitor = t
            save()
            place()
        else
            text.mon_name = cfg.monitor
        end
    end)

    -- The ghosts: one surface on each side that has a monitor next door (`gs_<side>`), put there empty as the widget is pressed and drawn on only once
    -- it has faded in (`rd_<side>`, GFADE later: the compositor fades a layer in as it appears, ~0.4 s, and out as it goes); taken off only when they
    -- draw nothing. None is made or moved while the widget goes over: that was the flicker, and moving one mid-drag ended the drag.
    local GFADE = 450
    local ghost_n = 0
    local function busy() return fact.dragging == true or fact.carry == true or fact.sliding == true or fact.landed == true end
    local function ghosts_on()
        local from = find(text.scr)
        if not from or not from.x then return end
        ghost_n = ghost_n + 1
        local mine = ghost_n
        for _, side in ipairs(SIDES) do
            local to = nb[side] and find(nb[side])
            if to and to.x then
                if text["gs_" .. side] ~= to.name then
                    fact["rd_" .. side] = false
                    fact["ox_" .. side] = to.x - from.x
                    fact["oy_" .. side] = to.y - from.y
                    text["gs_" .. side] = to.name
                end
            elseif text["gs_" .. side] ~= "" then
                fact["rd_" .. side] = false
                text["gs_" .. side] = ""
            end
        end
        after(GFADE, function()
            if mine ~= ghost_n then return end
            for _, side in ipairs(SIDES) do if text["gs_" .. side] ~= "" then fact["rd_" .. side] = true end end
        end)
    end
    local function ghosts_off(delay)
        ghost_n = ghost_n + 1
        local mine = ghost_n
        after(delay, function()
            if mine ~= ghost_n or busy() then return end
            for _, side in ipairs(SIDES) do
                fact["rd_" .. side] = false
                if text["gs_" .. side] ~= "" then text["gs_" .. side] = "" end
            end
        end)
    end

    -- It goes to the monitor on `side`, into cell `gx`, `gy`: that side's ghost (already faded in) shows it there (`landed`, `lside`) while `face` is put
    -- on that monitor empty (`fready` false) and fades in; then, in one go, `face` draws it and the ghost stops, and the ghosts are taken off, empty.
    local SIDE_N = { l = 1, r = 2, t = 3, b = 4 }
    local function arrive(side, gx, gy)
        local to = side and nb[side] and find(nb[side])
        fact.carry = false
        fact.sliding = false
        fact.land = 0
        if not to then ghosts_off(0) return end
        fact.fready = false
        fact.lside = SIDE_N[side]
        fact.landed = true
        fact.jump = true
        fact.gx = gx
        fact.gy = gy
        cfg.monitor = to.name
        if w.moved then w.moved(gx, gy) end
        save()
        place()
        after(GFADE, function()
            fact.fready = true
            fact.landed = false
            fact.jump = false
            ghosts_off(120)
        end)
    end
    -- Into the cell under it on the monitor it is over (`cs`: 0 its own, 1 to 4 the one on that side), as the scene works it out (`fgx`, `fgy`).
    local function drop()
        local cs = math.floor((tonumber(fact.cs) or 0) + 0.5)
        if cs >= 1 and cs <= 4 and nb[SIDES[cs]] then
            arrive(SIDES[cs], fact.fgx, fact.fgy)
            return
        end
        fact.gx = fact.fgx
        fact.gy = fact.fgy
        if w.moved then w.moved(fact.gx, fact.gy) end
        save()
        fact.carry = false
        fact.land = 0
        ghosts_off(150)
    end
    -- Carried: where the pointer is, from Hyprland (`hyprctl cursorpos`, the desktop's coordinates), told to the scene in its own (`cpx`, `cpy`) with the
    -- monitor it is over (`cs`), every 30 ms or so, until the button comes up.
    local function follow(from)
        if not fact.carry then return end
        run("hyprctl", { "cursorpos" }, function(out, code)
            if not fact.carry then return end
            local x, y = (out or ""):match("(%-?[%d.]+),%s*(%-?[%d.]+)")
            x, y = tonumber(x), tonumber(y)
            if code == 0 and x and y then
                fact.cpx = x - from.x
                fact.cpy = y - from.y
                local over = nil
                if x >= from.x and x < from.x + from.w and y >= from.y and y < from.y + from.h then over = 0 end
                for i, side in ipairs(SIDES) do
                    local m = nb[side] and find(nb[side])
                    if not over and m and m.x and x >= m.x and x < m.x + m.w and y >= m.y and y < m.y + m.h then over = i end
                end
                if over and over ~= fact.cs then fact.cs = over end
            end
            after(30, function() follow(from) end)
        end)
    end
    local on_hypr = nil
    run("printenv", { "HYPRLAND_INSTANCE_SIGNATURE" }, function(out, code) on_hypr = code == 0 and (out or ""):match("%S") ~= nil end)

    -- Let go over a monitor next door, or at its edge (`land`: which side). Let go over there (`cs` already that side): into the cell under it there. At the
    -- edge, the compositor may have let go of the drag as the pointer went on over: the widget is carried on (the scene's `carry`), following the pointer
    -- (`follow`), until bin/vitreus-btnwait says the button is up, and then goes into the cell under it, on whichever monitor that is. Where the pointer
    -- cannot be followed (not Hyprland) or the button cannot be heard (no access to the input devices), it slides over to that monitor's edge.
    local SLIDE_MS = 330
    local ENTRY = { l = { 99, nil }, r = { 0, nil }, t = { nil, 99 }, b = { nil, 0 } }
    on("fact:land", function(v)
        local side = SIDES[math.floor((tonumber(v) or 0) + 0.5)]
        if not side or not nb[side] then fact.carry = false; fact.land = 0; ghosts_off(0) return end
        local function slide_over()
            fact.nocarry = true
            local e = ENTRY[side]
            after(SLIDE_MS, function() arrive(side, e[1] or fact.gx, e[2] or fact.gy) end)
        end
        if math.floor((tonumber(fact.cs) or 0) + 0.5) > 0 then drop() return end
        local from = find(text.scr)
        if not on_hypr or not from or not from.x then slide_over() return end
        follow(from)
        local ok = pcall(run, "vitreus-btnwait", { "30" }, function(_, code)
            if not fact.carry then return end
            if code == 0 then after(70, drop) else slide_over() end      -- (a moment for the last place of the pointer to come in)
        end)
        if not ok then slide_over() end
    end)
    -- Pressed: the ghosts go next door, empty. Let go without carrying it anywhere: they go. And a widget without its monitor, shown on another in Edit mode
    -- and dragged there: that monitor is its own now.
    on("fact:dragging", function(v)
        if v == true or v == 1 then
            -- pressed again before the last move has settled (`face` still fading in on its new monitor): it is drawn at once, not left invisible
            if fact.fready ~= true or fact.landed == true then fact.fready = true; fact.landed = false; fact.jump = false end
            ghosts_on()
            return
        end
        if not fact.carry and not fact.landed then ghosts_off(150) end
        if fact.orphan and text.scr ~= "" and not fact.carry then
            cfg.monitor = text.scr
            save()
            place()
        end
    end)
    -- Leaving Edit mode puts a widget without its monitor away again (and entering it shows it): see `visibility`.

    return { refresh = refresh, place = place }
end
