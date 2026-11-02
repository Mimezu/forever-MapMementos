local ADDON, ns = ...
local HBD = LibStub("HereBeDragons-2.0")
local Pins = LibStub("MapMementos-MinimapPins-1.0")
local db, journal, refreshList, edit, draft, selected
local positionLauncher, squareMinimap
local pinFrames, freePins = {}, {}
local worldProvider
local icons = {
    {"Camp", "Spell_Fire_Fire"}, {"Home", "INV_Misc_Rune_01"},
    {"Treasure", "INV_Misc_Coin_01"}, {"Danger", "INV_Misc_Bone_HumanSkull_01"},
    {"Herbs", "INV_Misc_Herb_01"}, {"Ore", "INV_Ore_Copper_01"},
    {"Fishing", "INV_Fishingpole_02"}, {"Memory", "INV_Misc_Book_09"},
}
local function texture(index) return "Interface\\Icons\\" .. icons[index or 1][2] end
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function say(s) DEFAULT_CHAT_FRAME:AddMessage("|cffd8b879Map Mementos:|r " .. s) end
local function location(m) return string.format("%s  /  %.1f, %.1f", m.zone or "Unknown", m.x * 100, m.y * 100) end
local function capture()
    local map = C_Map.GetBestMapForUnit("player")
    local p = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if p then x, y = p:GetXY() end
    if not x or not y then x, y, map = HBD:GetPlayerZonePosition() end
    if not map or not x or not y or x ~= x or y ~= y or x < 0 or y < 0 or x > 1 or y > 1 then
        return nil, "Your location is unavailable here. Try again outside or after the map finishes loading."
    end
    local info = C_Map.GetMapInfo(map)
    local wx, wy, instance = HBD:GetPlayerWorldPosition()
    return {map = map, x = x, y = y, wx = wx, wy = wy, instance = instance,
        zone = info and info.name or GetZoneText(), icon = 1,
        name = GetSubZoneText() ~= "" and GetSubZoneText() or GetZoneText(), description = ""}
end
local function tip(frame, m)
    if frame:GetEffectiveAlpha() < .05 then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(m.name, 1, .83, .5)
    if m.description ~= "" then GameTooltip:AddLine(m.description, .92, .88, .79, true) end
    GameTooltip:AddLine(location(m), .6, .65, .64)
    GameTooltip:AddLine("Click to open this journal entry", .55, .75, .68)
    GameTooltip:Show()
end
local function watchTooltip(self, elapsed)
    self.tooltipElapsed = (self.tooltipElapsed or 0) + elapsed
    if self.tooltipElapsed < .1 then return end
    self.tooltipElapsed = 0
    if not GameTooltip:IsOwned(self) then self:SetScript("OnUpdate", nil); return end
    if self:GetEffectiveAlpha() < .05 then GameTooltip:Hide() end
end
-- The fade watcher only runs while its pin owns the tooltip.
local function showPinTip(self)
    local m = db.markers[self.markerID]
    if not m then return end
    tip(self, m)
    if GameTooltip:IsOwned(self) then self.tooltipElapsed = 0; self:SetScript("OnUpdate", watchTooltip) end
end
local function hidePinTip(self)
    self:SetScript("OnUpdate", nil)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
-- Use normalized coordinates directly: custom zones need not be present in
-- HereBeDragons' precomputed world-coordinate database to have world-map pins.
local function mapPositionUncached(m, target)
    if target == m.map then return m.x, m.y end
    local source, x, y = m.map, m.x, m.y
    for _ = 1, 16 do
        local info = C_Map.GetMapInfo(source)
        local parent = info and info.parentMapID
        if not parent or parent == 0 or parent == source then break end
        local left, right, top, bottom = C_Map.GetMapRectOnMap(source, parent)
        if not left or not right or not top or not bottom or right <= left or bottom <= top then break end
        x, y = left + x * (right - left), top + y * (bottom - top)
        if parent == target then return x, y end
        source = parent
    end
end
-- Saved markers never move (edits save a new table), so a marker's position on
-- a given map is computed once instead of walking the map tree on every refresh.
local positionCache = setmetatable({}, {__mode = "k"})
local function mapPosition(m, target)
    local byMap = positionCache[m]
    if not byMap then byMap = {}; positionCache[m] = byMap end
    local cached = byMap[target]
    if cached == nil then
        local x, y = mapPositionUncached(m, target)
        cached = x and y and {x, y} or false
        byMap[target] = cached
    end
    if cached then return cached[1], cached[2] end
end
-- Keep marker state outside Blizzard's pin pools and gamepad navigation tables.
local function installWorldProvider()
    -- The world map can load on demand; ADDON_LOADED installs the overlay then.
    if not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
    local canvas = WorldMapFrame:GetCanvas()
    local overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints()
    local frames = {}
    -- Blizzard's gamepad navigation hooks CreateFrame. A button created under
    -- the open map runs that hook under this addon's taint and re-reads the
    -- map's buttons into Blizzard's navigation state; later map opens and
    -- closes can then fail (jump/back stop working until /reload). So marker
    -- buttons are made only while the map is closed or in keyboard/mouse mode.
    local function canCreate()
        if not WorldMapFrame:IsShown() then return true end
        return not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled())
    end
    local function newWorldPin()
        local b = CreateFrame("Button", nil, overlay)
        b:SetSize(20, 20)
        b.art = b:CreateTexture(nil, "ARTWORK")
        b.art:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        b:SetScript("OnEnter", showPinTip)
        b:SetScript("OnLeave", hidePinTip)
        b:SetScript("OnHide", hidePinTip)
        b:SetScript("OnClick", function(self) edit(self.markerID) end)
        b:Hide()
        return b
    end
    -- One button per saved marker, so the open map never needs a new one.
    -- Markers added while the gamepad map is open wait for it to close.
    local short = false
    local function grow()
        local need = 0
        for _ in pairs(db.markers) do need = need + 1 end
        while #frames < need and canCreate() do frames[#frames + 1] = newWorldPin() end
        short = #frames < need
    end
    local function refresh()
        grow()
        -- Reading the native draw level is safe; only our own frames are changed.
        -- Default child levels sit underneath exploration/detail map artwork.
        local levels = WorldMapFrame:GetPinFrameLevelsManager()
        local pinLevel = levels:GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
        overlay:SetFrameLevel(pinLevel)
        local target = WorldMapFrame:GetMapID()
        local count = 0
        if target then
            for id, m in pairs(db.markers) do
                local x, y = mapPosition(m, target)
                local b = frames[count + 1]
                if b and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    count = count + 1
                    b.markerID = id
                    b:SetFrameLevel(pinLevel + 1)
                    b.art:SetTexture(texture(m.icon))
                    b:ClearAllPoints()
                    b:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
                    b:Show()
                end
            end
        end
        for i = count + 1, #frames do frames[i]:Hide() end
    end
    worldProvider = { RefreshAllData = refresh }
    -- Rebuild only when the displayed map or canvas size changes. Comparing two
    -- values is all the open map costs per check; marker edits refresh directly.
    local elapsed, shownMap, shownWidth = 0, nil, nil
    local function refreshIfChanged(force)
        local mapID, width = WorldMapFrame:GetMapID(), canvas:GetWidth()
        if force or mapID ~= shownMap or width ~= shownWidth then
            shownMap, shownWidth = mapID, width
            refresh()
        end
    end
    -- Build 70009's gamepad world map has a soft cursor that only probes
    -- Blizzard's own pins. Show a marker's note while that cursor rests on it,
    -- using Blizzard's 12 px reach. Read-only: the cursor's position and our
    -- own buttons; nothing is registered with the map or its navigation.
    local cursorPin
    local function gamepadHover()
        local cursor, target = _G.SoftCursor, nil
        if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
            and cursor and cursor:IsShown() then
            local cx, cy = cursor:GetCenter()
            local cursorScale = cursor:GetEffectiveScale()
            if cx and cy and cursorScale then
                cx, cy = cx * cursorScale, cy * cursorScale
                local best
                for _, b in ipairs(frames) do
                    local bx, by
                    if b:IsShown() then bx, by = b:GetCenter() end
                    local scale = bx and b:GetEffectiveScale()
                    if bx and by and scale then
                        local dx, dy, reach = bx * scale - cx, by * scale - cy, 12 * scale
                        local distance = dx * dx + dy * dy
                        if distance <= reach * reach and (not best or distance < best) then best, target = distance, b end
                    end
                end
            end
        end
        if target ~= cursorPin then
            if cursorPin then hidePinTip(cursorPin) end
            cursorPin = target
            if target then showPinTip(target) end
        end
    end
    overlay:SetScript("OnShow", function() refreshIfChanged(true) end)
    overlay:SetScript("OnHide", function()
        if cursorPin then hidePinTip(cursorPin); cursorPin = nil end
        -- Catch up once Blizzard has finished closing the map.
        if short and C_Timer and C_Timer.After then C_Timer.After(0, grow) end
    end)
    overlay:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < .1 then return end
        elapsed = 0
        refreshIfChanged(false)
        gamepadHover()
    end)
    grow()
end
local function newPin()
    local b = table.remove(freePins) or CreateFrame("Button", nil, Minimap)
    if not b.art then
        b:SetSize(18, 18)
        b.art = b:CreateTexture(nil, "ARTWORK")
        b.art:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        b:SetScript("OnEnter", showPinTip)
        b:SetScript("OnLeave", hidePinTip)
        b:SetScript("OnHide", hidePinTip)
        b:SetScript("OnClick", function(self) if self:GetEffectiveAlpha() >= .05 then edit(self.markerID) end end)
    end
    -- Ordinary children inherit the map's opacity, including Frame Gambit fades.
    if b.SetIgnoreParentAlpha then b:SetIgnoreParentAlpha(false) end
    return b
end
local function syncPins()
    Pins:RemoveAllMinimapIcons(ADDON)

    for _, b in ipairs(pinFrames) do b:Hide(); freePins[#freePins + 1] = b end
    wipe(pinFrames)
    for id, m in pairs(db.markers) do
        local mini = newPin()
        mini.markerID = id
        mini.art:SetTexture(texture(m.icon)); mini:SetSize(18, 18)
        pinFrames[#pinFrames + 1] = mini
        if m.wx and m.wy and m.instance then
            Pins:AddMinimapIconWorld(ADDON, mini, m.instance, m.wx, m.wy, false)
        elseif not Pins:AddMinimapIconMap(ADDON, mini, m.map, m.x, m.y, true, false) then
            -- Recover older entries from the client's map API, without moving
            -- them to the player's current position.
            local instance, p = C_Map.GetWorldPosFromMapPos(m.map, CreateVector2D(m.x, m.y))
            if p and instance then
                local wy, wx = p:GetXY()
                Pins:AddMinimapIconWorld(ADDON, mini, instance, wx, wy, false)
            end
        end
    end
    if worldProvider then worldProvider:RefreshAllData() end
end
local function save(m, id)
    m.name = trim(m.name)
    if m.name == "" then return nil, "Give this place a name first." end
    if not id then id = db.nextID; db.nextID = id + 1 end
    db.markers[id] = m
    syncPins()
    return id
end
local function skin(f, r, g, b)
    f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
        edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
    f:SetBackdropColor(r or .08, g or .07, b or .06, 1)
    f:SetBackdropBorderColor(.65, .65, .65, 1)
end
local function label(parent, text, x, y, font)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    l:SetPoint("TOPLEFT", x, y); l:SetText(text); l:SetTextColor(.86, .74, .52)
    return l
end
local function button(parent, text, x, y, width, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y); b:SetSize(width, 26)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER"); b.text:SetText(text)
    b:HookScript("OnEnable", function(self) self.text:SetTextColor(1, .82, 0) end)
    b:HookScript("OnDisable", function(self) self.text:SetTextColor(.5, .5, .5) end)
    b:SetScript("OnClick", fn)
    return b
end
local function input(parent, x, y, width, height, multiline)
    if not multiline then
        local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", x + 6, y); box:SetSize(width - 12, height)
        box:SetAutoFocus(false); box:SetMaxLetters(64); box:SetFontObject(ChatFontNormal)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        return box
    end
    local surround = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    surround:SetPoint("TOPLEFT", x, y); surround:SetSize(width, height); skin(surround, .035, .03, .025)
    local scroll = CreateFrame("ScrollFrame", nil, surround, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -7); scroll:SetPoint("BOTTOMRIGHT", -28, 7)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetWidth(width - 40); box:SetHeight(height - 14); box:SetMultiLine(multiline)
    box:SetFontObject(ChatFontNormal); box:SetTextColor(.92, .88, .78); box:SetAutoFocus(false)
    box:SetMaxLetters(multiline and 1200 or 64)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if not multiline then box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) end
    scroll:SetScrollChild(box)
    surround:EnableMouse(true); surround:SetScript("OnMouseDown", function() box:SetFocus() end)
    return box
end
local function createJournal()
    if journal then return end
    journal = CreateFrame("Frame", "MapMementosJournal", UIParent, "PortraitFrameTemplate")
    -- This is a standalone addon window, not a registered Blizzard UIPanel.
    -- The template's HideParentPanel calls HideUIPanel, which broadcasts into
    -- this client's protected gamepad binding manager even for addon frames.
    journal.CloseButton:SetScript("OnClick", function() journal:Hide() end)
    journal:SetSize(600, 448); journal:SetPoint("CENTER")
    journal:SetTitle("Map Mementos")
    if journal.SetPortraitToAsset then journal:SetPortraitToAsset(texture(8)) end
    local background = journal:CreateTexture(nil, "BACKGROUND", nil, -1)
    background:SetPoint("TOPLEFT", 3, -22); background:SetPoint("BOTTOMRIGHT", -3, 3)
    background:SetAtlas("Legacy-Challenge-BG")
    local inset = CreateFrame("Frame", nil, journal, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 12, -104); inset:SetPoint("BOTTOMRIGHT", -374, 46)
    inset:EnableMouse(false)
    journal:SetFrameStrata("DIALOG"); journal:SetClampedToScreen(true)
    journal:EnableMouse(true); journal:SetMovable(true); journal:RegisterForDrag("LeftButton")
    journal:SetScript("OnDragStart", journal.StartMoving); journal:SetScript("OnDragStop", journal.StopMovingOrSizing)
    tinsert(UISpecialFrames, "MapMementosJournal")
    if FrameGambitAPI and FrameGambitAPI.RegisterCinematicWindow then FrameGambitAPI.RegisterCinematicWindow(journal) end
    label(journal, "A field journal of places worth remembering", 76, -42, "GameFontHighlightSmall")
    button(journal, "+ Remember here", 18, -72, 196, function() edit(nil) end)
    local list = CreateFrame("ScrollFrame", nil, journal, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", 18, -112); list:SetSize(174, 274)
    local child = CreateFrame("Frame", nil, list); child:SetSize(174, 274); list:SetScrollChild(child)
    local rows = {}
    refreshList = function()
        local ids = {}; for id in pairs(db.markers) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return a > b end)
        -- A visible, unsaved row distinguishes creating from editing.
        if not selected and draft then table.insert(ids, 1, 0) end
        for i, id in ipairs(ids) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, child)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 49); row:SetSize(174, 44)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.selection = row:CreateTexture(nil, "BACKGROUND")
                row.selection:SetAllPoints(); row.selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                row.selection:SetVertexColor(1, .78, .25, .45)
                row:SetScript("OnClick", function(self) if self.markerID ~= 0 then edit(self.markerID) end end)
                row.text = label(row, "", 33, -7)
                row.text:SetWidth(132); row.text:SetJustifyH("LEFT")
                row.art = row:CreateTexture(nil, "ARTWORK"); row.art:SetSize(22,22); row.art:SetPoint("LEFT", 6, 0)
                row.zone = label(row, "", 33, -27, "GameFontHighlightSmall"); row.zone:SetWidth(134); row.zone:SetJustifyH("LEFT")
                rows[i] = row
            end
            local m = id == 0 and draft or db.markers[id]
            row.markerID = id; row.text:SetText(id == 0 and "New entry" or m.name)
            row.zone:SetText(id == 0 and "Unsaved" or m.zone)
            row.art:SetTexture(texture(m.icon)); row.selection:SetShown(id == selected or (id == 0 and not selected)); row:Show()
        end
        for i = #ids + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(274, #ids * 49))
        if not selected then list:SetVerticalScroll(0) end
    end
    journal.heading = label(journal, "Remember this place", 238, -76)
    journal.where = label(journal, "", 238, -100, "GameFontHighlightSmall")
    journal.where:SetWidth(330); journal.where:SetJustifyH("LEFT")
    label(journal, "Symbol", 238, -132)
    journal.symbols = {}
    for i, icon in ipairs(icons) do
        local b = CreateFrame("CheckButton", nil, journal)
        b:SetPoint("TOPLEFT", 238 + (i - 1) * 41, -153); b:SetWidth(34)
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        -- This client renders the native checked texture with an opaque center.
        -- Four thin edges cannot cover the symbol, regardless of blend mode.
        b.selection = b:CreateTexture(nil, "BACKGROUND")
        b.selection:SetAllPoints(); b.selection:SetColorTexture(1, .82, 0, 1)
        local backing = b:CreateTexture(nil, "BORDER")
        backing:SetPoint("TOPLEFT", 2, -2); backing:SetPoint("BOTTOMRIGHT", -2, 2)
        backing:SetColorTexture(.06, .04, .02, 1)
        b:SetScript("OnClick", function() draft.icon = i; journal.paintSymbols(); refreshList() end)
        b:SetHeight(34); b.art = b:CreateTexture(nil, "ARTWORK"); b.art:SetPoint("CENTER"); b.art:SetSize(26,26); b.art:SetTexture(texture(i))
        b:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(icon[1]); GameTooltip:Show() end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        journal.symbols[i] = b
    end
    journal.paintSymbols = function()
        for i, b in ipairs(journal.symbols) do b:SetChecked(false); b.selection:SetShown(i == draft.icon) end
    end
    label(journal, "Name", 238, -202); journal.name = input(journal, 238, -223, 332, 34, false)
    label(journal, "Notes", 238, -270); journal.notes = input(journal, 238, -291, 332, 78, true)
    journal.status = label(journal, "", 18, -422, "GameFontHighlightSmall"); journal.status:SetWidth(552); journal.status:SetJustifyH("LEFT")
    button(journal, "Save entry", 454, -378, 116, function()
        if not draft then return end
        draft.name, draft.description = journal.name:GetText(), journal.notes:GetText()
        local id, err = save(draft, selected)
        if not id then journal.status:SetText(err); return end
        edit(id); journal.status:SetText("Saved. This place will be here when you return.")
    end)
    journal.delete = button(journal, "Delete", 238, -378, 92, function()
        if not selected then return end
        if journal.deleteID ~= selected then journal.deleteID = selected; journal.delete.text:SetText("Confirm?"); return end
        db.markers[selected] = nil; selected = nil; syncPins(); edit(nil)
        journal.status:SetText("Entry removed.")
    end)
    journal:SetScript("OnHide", function() journal.name:ClearFocus(); journal.notes:ClearFocus(); GameTooltip:Hide() end)
end
edit = function(id)
    createJournal()
    local m, err
    if id and db.markers[id] then m = {}; for k, v in pairs(db.markers[id]) do m[k] = v end
    else id = nil; m, err = capture() end
    if not m then
        say(err)
        -- Existing entries remain editable even when location APIs are unavailable.
        local existing = next(db.markers)
        if existing then return edit(existing) end
        journal:Hide(); return
    end
    if not id then m.name, m.description = "", "" end
    selected, draft = id, m
    journal.heading:SetText(id and "A place remembered" or "New entry")
    journal.where:SetText(location(m)); journal.name:SetText(m.name); journal.notes:SetText(m.description)
    journal.name:ClearFocus(); journal.notes:ClearFocus(); journal.paintSymbols()
    journal.deleteID = nil; journal.delete.text:SetText("Delete"); journal.delete:SetEnabled(id ~= nil)
    journal.status:SetText(id and "Editing preserves the original location." or "New unsaved entry. Location captured here; enter a name, then Save entry.")
    refreshList(); journal:Show()
end
local function command(message)
    local verb, rest = trim(message):match("^(%S*)%s*(.-)$")
    if verb:lower() == "add" then
        if rest == "" then edit(nil); return end
        local m, err = capture(); if not m then say(err); return end
        local name, description = rest:match("^(.-)%s*;%s*(.*)$")
        m.name, m.description = name or rest, description or ""
        m.name, m.description = m.name:sub(1, 64), m.description:sub(1, 1200)
        local id; id, err = save(m); if id then say("Remembered " .. m.name .. "."); if journal and journal:IsShown() then edit(id) end else say(err) end
    elseif verb == "" or verb:lower() == "list" then edit(selected or next(db.markers))
    elseif verb:lower() == "button" then
        local shape = rest:lower()
        if shape == "round" or shape == "square" then db.minimapShape = shape
        elseif shape == "auto" then db.minimapShape = nil
        else say("/memento button round, square or auto sets the book button's path around the minimap."); return end
        if MapMementosMinimapButton then positionLauncher(MapMementosMinimapButton) end
        say("Book button follows a " .. (squareMinimap() and "square" or "round") .. " minimap.")
    else say("/memento opens your journal. /memento add opens a new entry here. /memento add Name ; Description saves immediately. /memento button round|square|auto.") end
end
local events = CreateFrame("Frame")
-- "square" when the player chose it (/memento button square) or another addon
-- reports a square minimap through the conventional GetMinimapShape().
squareMinimap = function()
    local shape = db.minimapShape
    if shape == "square" then return true elseif shape == "round" then return false end
    return type(GetMinimapShape) == "function" and tostring(GetMinimapShape()):upper() == "SQUARE"
end
positionLauncher = function(button)
    local angle = math.rad(db.minimapAngle or 225)
    local rx, ry = Minimap:GetWidth() / 2 + 2, Minimap:GetHeight() / 2 + 2
    local x, y = math.cos(angle) * rx, math.sin(angle) * ry
    if squareMinimap() then
        -- Follow the square edge: stretch the circle outward, then clamp to the rim.
        x = math.max(-rx, math.min(rx, x * 1.4142))
        y = math.max(-ry, math.min(ry, y * 1.4142))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
local function dragLauncher(button)
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    if not cx or not cy then return end
    db.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
    positionLauncher(button)
end
events:RegisterEvent("ADDON_LOADED"); events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_ACTION_BLOCKED"); events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, name, blockedFunction)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if name ~= ADDON or not db then return end
        -- The popup omits the protected function. Keep a bounded diagnostic so
        -- this client's gamepad path can be identified without guessing.
        db.lastBlockedAction = {
            event = event, action = tostring(blockedFunction),
            gamepad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false,
            journalShown = journal and journal:IsShown() or false,
            mapShown = WorldMapFrame and WorldMapFrame:IsShown() or false,
            stack = debugstack and debugstack(2, 20, 0):sub(1, 6000) or nil,
        }
        db.blockedActions = type(db.blockedActions) == "table" and db.blockedActions or {}
        db.blockedActions[#db.blockedActions + 1] = db.lastBlockedAction
        while #db.blockedActions > 5 do table.remove(db.blockedActions, 1) end
        say("Blocked action: " .. tostring(blockedFunction) .. ". Please report this line and what you were doing.")
    elseif event == "ADDON_LOADED" and name == ADDON then
        MapMementosDB = type(MapMementosDB) == "table" and MapMementosDB or {}
        db = MapMementosDB; db.version = 1; db.markers = db.markers or {}; db.nextID = db.nextID or 1
        for id, m in pairs(db.markers) do
            if type(id) == "number" then db.nextID = math.max(db.nextID, id + 1) end
            if not icons[m.icon] then m.icon = 1 end
        end
        SLASH_MAPMEMENTOS1 = "/memento"; SLASH_MAPMEMENTOS2 = "/mmemo"
        SlashCmdList.MAPMEMENTOS = command
    elseif event == "PLAYER_LOGIN" then
        installWorldProvider()
        syncPins()
        local launcher = CreateFrame("Button", "MapMementosMinimapButton", Minimap)
        if launcher.SetIgnoreParentAlpha then launcher:SetIgnoreParentAlpha(false) end
        launcher:SetSize(32, 32); positionLauncher(launcher)
        launcher:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        local art = launcher:CreateTexture(nil, "ARTWORK"); art:SetPoint("CENTER"); art:SetSize(20,20); art:SetTexture(texture(8))
        local mask = launcher:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(art); art:AddMaskTexture(mask)
        local border = launcher:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(54, 54); border:SetPoint("TOPLEFT", 0, 0)
        launcher:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        launcher:RegisterForDrag("LeftButton")
        -- Per-frame work only while dragging or while the tooltip is up.
        local function launcherUpdate(self, elapsed)
            if self.dragging then dragLauncher(self); return end
            watchTooltip(self, elapsed)
        end
        launcher:SetScript("OnDragStart", function(self)
            self.dragging = true; self.suppressClick = true; GameTooltip:Hide()
            self:SetScript("OnUpdate", launcherUpdate)
        end)
        launcher:SetScript("OnDragStop", function(self)
            self.dragging = false; self:SetScript("OnUpdate", nil); positionLauncher(self)
        end)
        launcher:SetScript("OnMouseDown", function(self) self.suppressClick = false end)
        launcher:SetScript("OnClick", function(self, mouse) if self.suppressClick then self.suppressClick = false; return end; if mouse == "RightButton" then edit(nil) else command("") end end)
        launcher:SetScript("OnEnter", function(self)
            if self.dragging or self:GetEffectiveAlpha() < .05 then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Map Mementos")
            GameTooltip:AddLine("Left click: field journal\nRight click: remember here\nDrag: move around the minimap", .9, .85, .7)
            GameTooltip:Show()
            self.tooltipElapsed = 0; self:SetScript("OnUpdate", launcherUpdate)
        end)
        launcher:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if not self.dragging then self:SetScript("OnUpdate", nil) end
        end)
        -- Follow minimap resizes (skins such as EllesmereUI change its size).
        Minimap:HookScript("OnSizeChanged", function() positionLauncher(launcher) end)
    elseif event == "ADDON_LOADED" and name == "Blizzard_WorldMap" and db and not worldProvider then
        installWorldProvider()
        if worldProvider then worldProvider:RefreshAllData() end
    end
end)
-- Exposed only to the offline regression harness through the addon namespace.
ns.capture, ns.save, ns.command = capture, save, command
ns.mapPosition, ns.positionLauncher = mapPosition, positionLauncher

