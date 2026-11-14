local ADDON, ns = ...
-- Key bindings (Bindings.xml) and the settings block shared by the journal's
-- Settings panel and the page in Esc > Options > AddOns.

BINDING_CATEGORY_MAPMEMENTOS = "Map Mementos"
BINDING_NAME_MAPMEMENTOS_TOGGLE = "Field journal"
BINDING_NAME_MAPMEMENTOS_ADD = "Remember here"
function MapMementos_ToggleJournal() ns.toggle() end
function MapMementos_RememberHere() ns.rememberHere() end

local KEYS = {
    {"MAPMEMENTOS_TOGGLE", "Journal"},
    {"MAPMEMENTOS_ADD", "Remember here"},
}
local MODIFIERS = {LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true}
local COMBAT = "Not in combat."

local function keyText(action)
    local key = GetBindingKey(action)
    if not key then return "Not set" end
    return GetBindingText and GetBindingText(key) or key
end
-- The key pressed, with its modifiers, as the bindings write it.
local function combo(key)
    local mods = ""
    if IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then mods = mods .. "META-" end
    return mods .. key
end
-- key nil clears. Returns ok, and what the key did before (or a refusal).
function ns.bindKey(action, key)
    if InCombatLockdown() then return false, COMBAT end
    local previous = key and GetBindingAction(key)
    for _, old in ipairs({GetBindingKey(action)}) do SetBinding(old) end
    if key then SetBinding(key, action) end
    SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
    if previous and previous ~= "" and previous ~= action then
        return true, "Replaced " .. (_G["BINDING_NAME_" .. previous] or previous)
    end
    return true, ""
end

local blocks, listening = {}, nil
function ns.RefreshSettings()
    for _, block in ipairs(blocks) do
        for _, cap in ipairs(block.caps) do
            cap.text:SetText(cap == listening and "Press a key" or keyText(cap.action))
        end
        block.minimap:SetChecked(not ns.db().minimapHidden)
    end
end
local function stopListening()
    local cap = listening
    if not cap then return end
    listening = nil
    cap:SetScript("OnKeyDown", nil); cap:EnableKeyboard(false)
    ns.RefreshSettings()
end
ns.stopListening = stopListening
local function listen(cap)
    stopListening()
    if InCombatLockdown() then cap.status:SetText(COMBAT); return end
    listening = cap
    cap:EnableKeyboard(true)
    if cap.SetPropagateKeyboardInput then cap:SetPropagateKeyboardInput(false) end
    cap:SetScript("OnKeyDown", function(self, key)
        if MODIFIERS[key] then return end
        stopListening()
        if key == "ESCAPE" then self.status:SetText(""); return end
        local _, note = ns.bindKey(self.action, combo(key))
        self.status:SetText(note); ns.RefreshSettings()
    end)
    cap.status:SetText("Esc cancels")
    ns.RefreshSettings()
end

-- Keys and the minimap icon, 216 x 170, placed at x, y in parent.
function ns.BuildSettings(parent, x, y)
    local block = CreateFrame("Frame", nil, parent)
    block:SetPoint("TOPLEFT", x, y); block:SetSize(216, 170)
    block.caps = {}
    ns.label(block, "Keys", 0, 0)
    local status = ns.label(block, "", 0, -88, "GameFontHighlightSmall")
    status:SetWidth(216); status:SetJustifyH("LEFT")
    for i, entry in ipairs(KEYS) do
        local rowY = -24 - (i - 1) * 30
        ns.label(block, entry[2], 0, rowY - 6, "GameFontHighlight")
        local cap = ns.button(block, "", 108, rowY, 108, function(self, mouse)
            if mouse == "RightButton" then
                stopListening()
                local _, note = ns.bindKey(self.action, nil)
                status:SetText(note); ns.RefreshSettings()
            elseif listening == self then stopListening(); status:SetText("")
            else listen(self) end
        end)
        cap:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cap.action, cap.status = entry[1], status
        cap:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(entry[2])
            GameTooltip:AddLine("Right click: clear", .9, .85, .7); GameTooltip:Show()
        end)
        cap:SetScript("OnLeave", function() GameTooltip:Hide() end)
        block.caps[i] = cap
    end
    local check = CreateFrame("CheckButton", nil, block, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", -4, -120); check:SetSize(26, 26)
    ns.label(block, "Minimap icon", 26, -126, "GameFontHighlight")
    check:SetScript("OnClick", function(self) ns.setLauncherShown(self:GetChecked() and true or false) end)
    block.minimap = check
    block:SetScript("OnShow", function() ns.RefreshSettings() end)
    block:SetScript("OnHide", function() stopListening(); status:SetText("") end)
    blocks[#blocks + 1] = block
    ns.RefreshSettings()
    return block
end

-- Esc > Options > AddOns > Map Mementos.
function ns.RegisterSettings()
    if ns.settingsRegistered then return end
    ns.settingsRegistered = true
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("UPDATE_BINDINGS"); watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then stopListening() else ns.RefreshSettings() end
    end)
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16); heading:SetText("Map Mementos")
    ns.button(panel, "Open", 16, -44, 120, function()
        -- Closing Blizzard's panel from addon code taints the gamepad window
        -- manager, so in the gamepad interface Settings stays open behind.
        local gamepad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
        if SettingsPanel and SettingsPanel:IsShown() and not gamepad then HideUIPanel(SettingsPanel) end
        ns.openJournal()
    end)
    ns.label(panel, "/memento", 148, -50, "GameFontHighlightSmall"):SetTextColor(.6, .6, .6)
    ns.BuildSettings(panel, 16, -90)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Map Mementos")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category); ns.settingsCategory = category end
end
