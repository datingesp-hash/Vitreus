-- Which monitor a desktop widget is on: shared by the desktop widgets (desktopclock/, desktopsysmon/: a link to this file in each folder).
--
-- The widget is one surface (`surface face { screens: scr }`), on one monitor: the one its settings name (`monitor`), or, while that one is not
-- plugged in, the first there is (it goes back when it is plugged in again). It used to be a copy of the whole scene on every monitor, a full-screen
-- surface each (~27 MB on the card per 1080p monitor, drawing or not), with the card drawn by one copy and the others empty; and dragging it to
-- another monitor handed the drag from one copy to another halfway, which is where it got stuck.
--
-- Now a drag never leaves its surface. To move the widget to another monitor it is pushed against the edge that monitor is behind, in Edit mode
-- (the scene says which edge with `es` while it is pushed there; held there a moment, it goes over and comes in by the opposite edge), or chosen in
-- Settings > Widgets (`text mon_name`, as before).
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

    -- Puts it on its monitor, or on the first one while that is not plugged in. Nothing known yet: left as it is. While it is hidden (`shown` false,
    -- and not in Edit mode) it has no surface at all: a hidden widget kept a full-screen one on the card all the same.
    local hidden = false
    local function place()
        local m = find(cfg.monitor) or mons[1]
        if not m then return end
        if cfg.monitor == "" then cfg.monitor = m.name; save() end
        local want = hidden and "" or m.name
        local moved = text.scr ~= want and want ~= ""
        if text.scr ~= want then text.scr = want end
        if text.mon_name ~= m.name then text.mon_name = m.name end
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
            if hidden then hidden = false; place() end
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
            text.mon_name = text.scr
        end
    end)

    -- Pushed against an edge with a monitor behind it (`es`: 1 left, 2 right, 3 top, 4 bottom, 0 none), and held there a moment: it goes over, and
    -- comes in by the opposite edge, at the same row (or column). The drag ends here: its surface is now on the other monitor.
    local push_n = 0
    on("fact:es", function(v)
        push_n = push_n + 1
        local mine, side = push_n, SIDES[math.floor((tonumber(v) or 0) + 0.5)]
        if not side or not nb[side] then return end
        after(450, function()
            if mine ~= push_n or not fact.dragging then return end
            local to = nb[side]
            if not find(to) then return end
            fact.dragging = false
            fact.es = 0
            -- the far edge: the scene's rule keeps a cell it cannot take inside the grid (`gx` past the last column comes back to the last it fits in)
            if side == "l" then fact.gx = 99 elseif side == "r" then fact.gx = 0 end
            if side == "t" then fact.gy = 99 elseif side == "b" then fact.gy = 0 end
            cfg.monitor = to
            if w.moved then w.moved(fact.gx, fact.gy) end
            save()
            place()
        end)
    end)

    return { refresh = refresh, place = place }
end
