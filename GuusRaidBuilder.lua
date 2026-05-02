-- GuusRaidBuilder.lua
-- Standalone raid composition builder for vanilla WoW (no SuperMacro dependency)
-- /grb to open

GuusRaidBuilder = GuusRaidBuilder or {}
GuusRaidBuilder_Config = GuusRaidBuilder_Config or {}

-- ============================================================
-- DATA TABLES
-- ============================================================

local TIERS = { "t1r", "t2r", "t3r", "t4r", "t5r", "t1d", "t2d", "t3d", "t4d", "t5d" }

local CLASSES = {
    "warrior", "mage", "warlock", "priest", "druid",
    "paladin", "shaman", "hunter", "rogue"
}

local ROLES = { "tank", "healer", "rdps", "mdps" }

-- Only classes with meaningful spec choice; all others get {"default"}
local SPECS = {
    mage    = { "frost", "fire", "arcane" },
    paladin = { "might", "magic" },
}

-- Valid roles per class (mirrors GuusLegacyManager)
local CLASS_ROLES = {
    warrior = { "tank", "mdps" },
    mage    = { "rdps" },
    warlock = { "rdps" },
    priest  = { "healer", "rdps" },
    druid   = { "tank", "healer", "mdps", "rdps" },
    paladin = { "tank", "healer", "mdps" },
    shaman  = { "tank", "healer", "mdps", "rdps" },
    hunter  = { "rdps" },
    rogue   = { "mdps" },
}

local HORDE_RACES   = { "orc", "undead", "tauren", "troll" }
local ALLIANCE_RACES = { "human", "gnome", "nightelf", "dwarf" }
local RACES = { "orc", "undead", "tauren", "troll", "human", "gnome", "nightelf", "dwarf" } -- fallback only

-- Valid races per class in vanilla WoW 1.12
local CLASS_RACES = {
    warrior = { "orc", "undead", "tauren", "troll", "human", "gnome", "nightelf", "dwarf" },
    mage    = { "undead", "troll", "human", "gnome" },
    warlock = { "orc", "undead", "human", "gnome" },
    priest  = { "undead", "troll", "human", "nightelf", "dwarf" },
    druid   = { "tauren", "nightelf" },
    paladin = { "human", "dwarf" },
    shaman  = { "orc", "tauren", "troll" },
    hunter  = { "orc", "tauren", "troll", "nightelf", "dwarf" },
    rogue   = { "orc", "undead", "troll", "human", "gnome", "nightelf", "dwarf" },
}

local function GetSpecs(class)
    return SPECS[string.lower(class or "")] or { "default" }
end

local function GetClassRoles(class)
    return CLASS_ROLES[string.lower(class or "")] or ROLES
end

-- Returns races valid for the given account faction, optionally filtered by class
local function GetRacesForAccount(accountName, class)
    local f = GuusRaidBuilder_Config.accountFactions
    local factionRaces
    if f and f[accountName] == "Alliance" then
        factionRaces = ALLIANCE_RACES
    else
        factionRaces = HORDE_RACES
    end
    if not class then return factionRaces end
    local classRaces = CLASS_RACES[string.lower(class)] or factionRaces
    -- intersect
    local result = {}
    for i = 1, table.getn(factionRaces) do
        local r = factionRaces[i]
        for j = 1, table.getn(classRaces) do
            if classRaces[j] == r then
                table.insert(result, r)
                break
            end
        end
    end
    if table.getn(result) == 0 then return { factionRaces[1] } end
    return result
end

-- Returns classes valid for the given account's faction
-- Horde cannot be Paladin; Alliance cannot be Shaman
local function GetClassesForAccount(accountName)
    local f = GuusRaidBuilder_Config.accountFactions
    local faction = f and f[accountName]
    if faction == "Alliance" then
        local result = {}
        for i = 1, table.getn(CLASSES) do
            if CLASSES[i] ~= "shaman" then
                table.insert(result, CLASSES[i])
            end
        end
        return result
    elseif faction == "Horde" then
        local result = {}
        for i = 1, table.getn(CLASSES) do
            if CLASSES[i] ~= "paladin" then
                table.insert(result, CLASSES[i])
            end
        end
        return result
    end
    -- Unknown faction: allow all
    return CLASSES
end

local function IsClassValidForAccount(class, accountName)
    local valid = GetClassesForAccount(accountName)
    local lc = string.lower(class or "")
    for i = 1, table.getn(valid) do
        if valid[i] == lc then return true end
    end
    return false
end

local function IsRoleValidForClass(role, class)
    local valid = GetClassRoles(class)
    local lr = string.lower(role or "")
    for i = 1, table.getn(valid) do
        if valid[i] == lr then return true end
    end
    return false
end

local function IsRaceValidForAccount(race, accountName, class)
    local list = GetRacesForAccount(accountName, class)
    local lr = string.lower(race or "")
    for i = 1, table.getn(list) do
        if list[i] == lr then return true end
    end
    return false
end

local GENDERS = { "male", "female" }

local ROLE_BG = {
    tank   = { 0.35, 0.08, 0.08, 0.85 },
    healer = { 0.08, 0.28, 0.08, 0.85 },
    rdps   = { 0.08, 0.14, 0.35, 0.85 },
    mdps   = { 0.30, 0.24, 0.04, 0.85 },
}



-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================

local ROW_HEIGHT   = 26
local LEFT_WIDTH   = 155
local RIGHT_WIDTH  = 590
local WINDOW_WIDTH = LEFT_WIDTH + RIGHT_WIDTH + 42
local WINDOW_HEIGHT = 590
local SCROLL_HEIGHT = 445

-- Column layout for right panel slot rows
local COL_X = { 2,  96, 134, 182, 226, 284, 338, 392 }
local COL_W = { 90,  36,  46,  42,  56,  52,  52,  26 }
-- Cols:        acc tier class role spec race gender X

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function countTableElements(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

local function findIndex(tbl, val)
    local lval = string.lower(tostring(val or ""))
    for i = 1, table.getn(tbl) do
        if string.lower(tbl[i]) == lval then return i end
    end
    return 1
end

local function cycleNext(tbl, current)
    local idx = findIndex(tbl, current) + 1
    if idx > table.getn(tbl) then idx = 1 end
    return tbl[idx]
end

local function trim(s)
    s = string.gsub(s or "", "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

-- ============================================================
-- CONFIG / DATA ACCESS
-- ============================================================

local function EnsureConfig()
    if not GuusRaidBuilder_Config then GuusRaidBuilder_Config = {} end
    if not GuusRaidBuilder_Config.presets then GuusRaidBuilder_Config.presets = {} end
    if not GuusRaidBuilder_Config.accounts then
        GuusRaidBuilder_Config.accounts = {}
    end
    if not GuusRaidBuilder_Config.accountFactions then
        GuusRaidBuilder_Config.accountFactions = {}
    end
    if GuusRaidBuilder_Config.currentPreset == nil then
        GuusRaidBuilder_Config.currentPreset = nil
    end
end

local function GetPresetSlots(presetName)
    EnsureConfig()
    if not presetName or not GuusRaidBuilder_Config.presets[presetName] then return {} end
    local p = GuusRaidBuilder_Config.presets[presetName]
    if not p.slots then p.slots = {} end
    return p.slots
end

local function GetPresetNames()
    EnsureConfig()
    local names = {}
    for k in pairs(GuusRaidBuilder_Config.presets) do
        table.insert(names, k)
    end
    table.sort(names)
    return names
end

local function GetAccountSlotCount(presetName, accountName)
    local slots = GetPresetSlots(presetName)
    local count = 0
    local acc = string.lower(accountName)
    for i = 1, table.getn(slots) do
        if string.lower(slots[i].account or "") == acc then
            count = count + 1
        end
    end
    return count
end

local function GetRoleSummary(presetName)
    local slots = GetPresetSlots(presetName)
    local s = { tank = 0, healer = 0, rdps = 0, mdps = 0, total = 0 }
    for i = 1, table.getn(slots) do
        local role = string.lower(slots[i].role or "mdps")
        if s[role] ~= nil then s[role] = s[role] + 1 end
        s.total = s.total + 1
    end
    return s
end

local function BuildCommand(slot)
    return ".z addinvite "
        .. (slot.account or "?") .. " "
        .. (slot.tier    or "t2r") .. " "
        .. (slot.class   or "warrior") .. " "
        .. (slot.role    or "mdps") .. " "
        .. (slot.spec    or "default") .. " "
        .. (slot.race    or "orc") .. " "
        .. (slot.gender  or "male")
end

local function NewDefaultSlot(accountName)
    local faction = GuusRaidBuilder_Config.accountFactions and GuusRaidBuilder_Config.accountFactions[accountName]
    local defaultRace = (faction == "Alliance") and "human" or "orc"
    return {
        account = accountName,
        tier    = "t2r",
        class   = "warrior",
        role    = "tank",
        spec    = "default",
        race    = defaultRace,
        gender  = "male",
    }
end

-- ============================================================
-- EXECUTE LOGIC (hire() equivalent, no SuperMacro needed)
-- ============================================================

local GRB_executeFrame  = nil
local GRB_executing     = false
local GRB_stopRequested = false
local GRB_stopButton    = nil

local function ExecuteRaid(presetName)
    local slots = GetPresetSlots(presetName)
    local total = table.getn(slots)
    if total == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r No slots in preset '" .. presetName .. "'!")
        return
    end
    if GRB_executing then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Already running. Press Stop first.")
        return
    end

    GRB_executing     = true
    GRB_stopRequested = false
    if GRB_stopButton then GRB_stopButton:Show() end

    local delay   = 500
    local index   = 0
    local elapsed = 0

    if GRB_executeFrame then GRB_executeFrame:SetScript("OnUpdate", nil) end
    GRB_executeFrame = CreateFrame("Frame")
    GRB_executeFrame:SetScript("OnUpdate", function()
        if GRB_stopRequested then
            GRB_executing = false
            GRB_stopRequested = false
            if GRB_stopButton then GRB_stopButton:Hide() end
            GRB_executeFrame:SetScript("OnUpdate", nil)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff6600GuusRaidBuilder:|r Stopped at " .. index .. "/" .. total)
            return
        end
        elapsed = elapsed + 1
        if elapsed >= delay or index == 0 then
            index = index + 1
            if index <= total then
                SendChatMessage(BuildCommand(slots[index]), "SAY")
                elapsed = 0
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00GuusRaidBuilder:|r " .. index .. "/" .. total
                    .. " -> " .. (slots[index].account or "?")
                )
            else
                GRB_executing = false
                if GRB_stopButton then GRB_stopButton:Hide() end
                GRB_executeFrame:SetScript("OnUpdate", nil)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GuusRaidBuilder:|r Done! Sent " .. total .. " invites.")
            end
        end
    end)
end

-- ============================================================
-- GUI STATE
-- ============================================================

local mainFrame         = nil
local leftScrollFrame   = nil
local leftScrollContent = nil
local rightScrollFrame  = nil
local rightScrollContent = nil
local summaryText       = nil
local presetCycleBtn    = nil
local exportFrame       = nil
local exportEditBox     = nil

-- Tracks y-position of each account's header in the right panel (for scroll-to)
local GRB_accountTopY = {}

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================

local RefreshAll
local RefreshSummary
local RefreshPresetButton
local RefreshLeftPanel
local RefreshRightPanel

-- ============================================================
-- CYCLE BUTTON FACTORY
-- ============================================================

local function MakeCycleBtn(parent, name, w, h, options, currentVal, onChange)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(w)
    btn:SetHeight(h)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.12, 0.12, 0.18, 0.92)
    btn:SetBackdropBorderColor(0.45, 0.45, 0.55, 0.8)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    lbl:SetText(currentVal or options[1])
    lbl:SetTextColor(1, 1, 1)
    btn.lbl = lbl

    btn:SetScript("OnEnter", function() btn:SetBackdropColor(0.22, 0.22, 0.32, 0.95) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropColor(0.12, 0.12, 0.18, 0.92) end)
    btn:SetScript("OnClick", function()
        local newVal = cycleNext(options, btn.lbl:GetText())
        btn.lbl:SetText(newVal)
        if onChange then onChange(newVal) end
    end)

    return btn
end

-- ============================================================
-- EXPORT FRAME
-- ============================================================

local function BuildExportText(presetName)
    local slots = GetPresetSlots(presetName)
    if table.getn(slots) == 0 then
        return "-- No slots in preset '" .. presetName .. "'"
    end

    local lines = {}
    table.insert(lines, '["' .. presetName .. '"] = {')

    local lastAcc = nil
    for i = 1, table.getn(slots) do
        local s = slots[i]
        if s.account ~= lastAcc then
            if lastAcc then table.insert(lines, "") end
            table.insert(lines, "    -- " .. s.account)
            lastAcc = s.account
        end
        table.insert(lines, '    "' .. BuildCommand(s) .. '",')
    end
    table.insert(lines, "},")

    local result = ""
    for i = 1, table.getn(lines) do
        result = result .. lines[i] .. "\n"
    end
    return result
end

local function ShowExportFrame(presetName)
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "GRBExportFrame", UIParent)
        exportFrame:SetWidth(600)
        exportFrame:SetHeight(430)
        exportFrame:SetPoint("CENTER", UIParent, "CENTER", 40, 0)
        exportFrame:SetFrameStrata("DIALOG")
        exportFrame:SetMovable(true)
        exportFrame:EnableMouse(true)
        exportFrame:EnableMouseWheel(true)
        exportFrame:SetScript("OnMouseDown", function() exportFrame:StartMoving() end)
        exportFrame:SetScript("OnMouseUp",   function() exportFrame:StopMovingOrSizing() end)
        exportFrame:SetScript("OnMouseWheel", function() end)
        exportFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })

        local etitle = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        etitle:SetPoint("TOP", exportFrame, "TOP", 0, -13)
        etitle:SetText("Export Preset")

        local hint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOP", exportFrame, "TOP", 0, -30)
        hint:SetText("Paste this block into SM_Extend.lua inside the presets table, then /script hire(\"name\")")
        hint:SetTextColor(0.8, 0.8, 0.5)

        -- Scroll frame for the editbox
        local esf = CreateFrame("ScrollFrame", "GRBExportScroll", exportFrame, "UIPanelScrollFrameTemplate")
        esf:SetWidth(548)
        esf:SetHeight(330)
        esf:SetPoint("TOP", exportFrame, "TOP", -8, -55)

        exportEditBox = CreateFrame("EditBox", "GRBExportEditBox", esf)
        exportEditBox:SetWidth(540)
        exportEditBox:SetHeight(4000)
        exportEditBox:SetMultiLine(true)
        exportEditBox:SetAutoFocus(false)
        exportEditBox:SetFontObject(GameFontNormalSmall)
        exportEditBox:SetTextColor(0.9, 0.95, 0.7)
        esf:SetScrollChild(exportEditBox)

        -- Select All button
        local selBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
        selBtn:SetWidth(90)
        selBtn:SetHeight(22)
        selBtn:SetPoint("BOTTOMLEFT", exportFrame, "BOTTOMLEFT", 15, 14)
        selBtn:SetText("Select All")
        selBtn:SetScript("OnClick", function()
            exportEditBox:SetFocus()
            exportEditBox:HighlightText()
        end)

        -- Close button
        local ecBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
        ecBtn:SetWidth(70)
        ecBtn:SetHeight(22)
        ecBtn:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -15, 14)
        ecBtn:SetText("Close")
        ecBtn:SetScript("OnClick", function() exportFrame:Hide() end)
    end

    exportEditBox:SetText(BuildExportText(presetName))
    exportFrame:Show()
    exportEditBox:SetFocus()
    exportEditBox:HighlightText()
end

-- ============================================================
-- IMPORT FRAME
-- ============================================================

-- Parses the export text block and returns presetName, slots[], errors[]
-- Expected format (one or more presets, we import the first one found):
--   ["presetName"] = {
--       ".z addinvite account tier class role spec race gender",
--   },
local function ParseImportText(text)
    if not text or trim(text) == "" then
        return nil, nil, { "Nothing to import." }
    end

    -- Find preset name: matches ["presetName"] = {
    local presetName = string.match(text, '%["(.-)"%]%s*=%s*{')
    if not presetName or trim(presetName) == "" then
        return nil, nil, { 'Could not find preset name. Expected: ["name"] = {' }
    end
    presetName = trim(presetName)

    local slots  = {}
    local errors = {}

    -- Match every quoted .z addinvite line
    for line in string.gfind(text, '"(.-)"') do
        line = trim(line)
        -- Match: .z addinvite account tier class role spec race gender
        local acc, tier, class, role, spec, race, gender =
            string.match(line, "^%.z%s+addinvite%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
        if acc then
            table.insert(slots, {
                account = acc,
                tier    = tier,
                class   = string.lower(class),
                role    = string.lower(role),
                spec    = string.lower(spec),
                race    = string.lower(race),
                gender  = string.lower(gender),
            })
        else
            -- Not a .z addinvite line — skip silently (could be a comment or empty)
        end
    end

    if table.getn(slots) == 0 then
        table.insert(errors, "No valid '.z addinvite ...' lines found.")
        return presetName, nil, errors
    end

    return presetName, slots, errors
end

local importFrame    = nil
local importEditBox  = nil

local function ShowImportFrame()
    if not importFrame then
        importFrame = CreateFrame("Frame", "GRBImportFrame", UIParent)
        importFrame:SetWidth(600)
        importFrame:SetHeight(470)
        importFrame:SetPoint("CENTER", UIParent, "CENTER", -40, 0)
        importFrame:SetFrameStrata("DIALOG")
        importFrame:SetMovable(true)
        importFrame:EnableMouse(true)
        importFrame:EnableMouseWheel(true)
        importFrame:SetScript("OnMouseDown", function() importFrame:StartMoving() end)
        importFrame:SetScript("OnMouseUp",   function() importFrame:StopMovingOrSizing() end)
        importFrame:SetScript("OnMouseWheel", function() end)
        importFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })

        local ititle = importFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ititle:SetPoint("TOP", importFrame, "TOP", 0, -13)
        ititle:SetText("Import Preset")

        local hint = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOP", importFrame, "TOP", 0, -30)
        hint:SetText('Format: ["name"] = { ".z addinvite acc tier class role spec race gender", }  (-- comments optional)')
        hint:SetTextColor(0.8, 0.8, 0.5)

        -- Status line
        local statusTxt = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusTxt:SetPoint("BOTTOM", importFrame, "BOTTOM", 0, 40)
        statusTxt:SetText("")
        statusTxt:SetTextColor(0.8, 0.8, 0.8)
        importFrame.statusTxt = statusTxt

        -- Scroll frame for editbox
        local isf = CreateFrame("ScrollFrame", "GRBImportScroll", importFrame, "UIPanelScrollFrameTemplate")
        isf:SetWidth(548)
        isf:SetHeight(350)
        isf:SetPoint("TOP", importFrame, "TOP", -8, -55)

        importEditBox = CreateFrame("EditBox", "GRBImportEditBox", isf)
        importEditBox:SetWidth(540)
        importEditBox:SetHeight(4000)
        importEditBox:SetMultiLine(true)
        importEditBox:SetAutoFocus(false)
        importEditBox:SetFontObject(GameFontNormalSmall)
        importEditBox:SetTextColor(0.9, 0.95, 0.7)
        isf:SetScrollChild(importEditBox)

        -- [Import] action button
        local doImport = function()
            local text = importEditBox:GetText()
            local presetName, slots, errors = ParseImportText(text)

            if table.getn(errors) > 0 then
                local msg = ""
                for ei = 1, table.getn(errors) do
                    msg = msg .. errors[ei] .. "  "
                end
                importFrame.statusTxt:SetText("|cffff6666" .. msg .. "|r")
                return
            end

            -- Register any new accounts found in the slots
            EnsureConfig()
            local accSet = {}
            local existingAccounts = GuusRaidBuilder_Config.accounts or {}
            for ai = 1, table.getn(existingAccounts) do
                accSet[string.lower(existingAccounts[ai])] = true
            end
            for si = 1, table.getn(slots) do
                local la = string.lower(slots[si].account)
                if not accSet[la] then
                    table.insert(GuusRaidBuilder_Config.accounts, slots[si].account)
                    accSet[la] = true
                end
            end

            -- Create or overwrite the preset
            if not GuusRaidBuilder_Config.presets[presetName] then
                GuusRaidBuilder_Config.presets[presetName] = {}
            end
            GuusRaidBuilder_Config.presets[presetName].slots = slots
            GuusRaidBuilder_Config.currentPreset = presetName

            importFrame.statusTxt:SetText(
                "|cff66ff66Imported '" .. presetName .. "' with "
                .. table.getn(slots) .. " slot(s).|r"
            )
            RefreshAll()
        end

        local impBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
        impBtn:SetWidth(80)
        impBtn:SetHeight(22)
        impBtn:SetPoint("BOTTOMLEFT", importFrame, "BOTTOMLEFT", 15, 14)
        impBtn:SetText("Import")
        impBtn:SetScript("OnClick", doImport)
        importEditBox:SetScript("OnChar", function() importFrame.statusTxt:SetText("") end)

        -- Clear button
        local clrBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
        clrBtn:SetWidth(60)
        clrBtn:SetHeight(22)
        clrBtn:SetPoint("BOTTOMLEFT", impBtn, "BOTTOMRIGHT", 4, 0)
        clrBtn:SetText("Clear")
        clrBtn:SetScript("OnClick", function()
            importEditBox:SetText("")
            importFrame.statusTxt:SetText("")
        end)

        -- Close button
        local icBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
        icBtn:SetWidth(70)
        icBtn:SetHeight(22)
        icBtn:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -15, 14)
        icBtn:SetText("Close")
        icBtn:SetScript("OnClick", function() importFrame:Hide() end)
    end

    importEditBox:SetText("")
    importFrame.statusTxt:SetText("")
    importFrame:Show()
    importEditBox:SetFocus()
end

-- ============================================================
-- SUMMARY BAR
-- ============================================================

RefreshSummary = function()
    if not summaryText then return end
    local name = GuusRaidBuilder_Config.currentPreset
    if not name then
        summaryText:SetText("No preset selected — create one with [New]")
        summaryText:SetTextColor(0.6, 0.6, 0.6)
        return
    end
    local s = GetRoleSummary(name)
    summaryText:SetText(
        "|cffff6666Tanks: "   .. s.tank   .. "|r  "
        .. "|cff66ff66Healers: " .. s.healer .. "|r  "
        .. "|cff6699ffRDPS: "    .. s.rdps   .. "|r  "
        .. "|cffffff66MDPS: "    .. s.mdps   .. "|r  "
        .. "|cffffffffTotal: "   .. s.total  .. "/40|r"
    )
end

-- ============================================================
-- PRESET CYCLE BUTTON
-- ============================================================

RefreshPresetButton = function()
    if not presetCycleBtn then return end
    local name = GuusRaidBuilder_Config.currentPreset
    presetCycleBtn.lbl:SetText(name or "(none)")
end

-- ============================================================
-- LEFT PANEL
-- ============================================================

local GRBLeftRows = {}

RefreshLeftPanel = function()
    if not leftScrollContent then return end

    -- Clear old rows
    for i = 1, table.getn(GRBLeftRows) do
        GRBLeftRows[i]:Hide()
        GRBLeftRows[i]:SetParent(nil)
    end
    GRBLeftRows = {}

    local accounts   = GuusRaidBuilder_Config.accounts or {}
    local presetName = GuusRaidBuilder_Config.currentPreset
    local prevRow    = nil

    for i = 1, table.getn(accounts) do
        local accName = accounts[i]
        local count   = presetName and GetAccountSlotCount(presetName, accName) or 0

        local row = CreateFrame("Button", "GRBLeftRow" .. i, leftScrollContent)
        row:SetWidth(LEFT_WIDTH - 22)
        row:SetHeight(ROW_HEIGHT)
        if prevRow then
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -2)
        else
            row:SetPoint("TOPLEFT", leftScrollContent, "TOPLEFT", 2, -2)
        end
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        if count > 0 then
            row:SetBackdropColor(0.12, 0.20, 0.12, 0.9)
            row:SetBackdropBorderColor(0.3, 0.65, 0.3, 0.8)
        else
            row:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
            row:SetBackdropBorderColor(0.32, 0.32, 0.38, 0.7)
        end

        row:SetScript("OnEnter", function() row:SetBackdropColor(0.20, 0.22, 0.32, 0.95) end)
        row:SetScript("OnLeave", function()
            if count > 0 then
                row:SetBackdropColor(0.12, 0.20, 0.12, 0.9)
            else
                row:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
            end
        end)

        -- Faction toggle button [?]/[H]/[A]
        local factions = GuusRaidBuilder_Config.accountFactions or {}
        local curFaction = factions[accName]  -- nil=unknown, "Horde", "Alliance"

        local fBtn = CreateFrame("Button", "GRBFaction" .. i, row)
        fBtn:SetWidth(22)
        fBtn:SetHeight(ROW_HEIGHT - 6)
        fBtn:SetPoint("LEFT", row, "LEFT", 5, 0)

        local nameTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameTxt:SetPoint("LEFT", row, "LEFT", 30, 0)
        nameTxt:SetText(accName)
        nameTxt:SetTextColor(0.9, 0.9, 1.0)
        nameTxt:SetWidth(75)
        fBtn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        local function ApplyFactionStyle(btn, f)
            if f == "Horde" then
                btn:SetBackdropColor(0.30, 0.05, 0.05, 0.95)
                btn:SetBackdropBorderColor(0.85, 0.25, 0.25, 0.9)
                btn.lbl:SetText("H")
                btn.lbl:SetTextColor(1.0, 0.35, 0.35)
            elseif f == "Alliance" then
                btn:SetBackdropColor(0.05, 0.10, 0.30, 0.95)
                btn:SetBackdropBorderColor(0.25, 0.45, 0.85, 0.9)
                btn.lbl:SetText("A")
                btn.lbl:SetTextColor(0.45, 0.70, 1.0)
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 0.85)
                btn:SetBackdropBorderColor(0.40, 0.40, 0.40, 0.7)
                btn.lbl:SetText("?")
                btn.lbl:SetTextColor(0.55, 0.55, 0.55)
            end
        end
        fBtn.lbl = fBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fBtn.lbl:SetPoint("CENTER", fBtn, "CENTER", 0, 0)
        ApplyFactionStyle(fBtn, curFaction)

        local capturedFBtn = fBtn
        local capturedAccF = accName
        fBtn:SetScript("OnClick", function()
            EnsureConfig()
            local f = GuusRaidBuilder_Config.accountFactions[capturedAccF]
            if f == "Horde" then
                GuusRaidBuilder_Config.accountFactions[capturedAccF] = "Alliance"
            else
                GuusRaidBuilder_Config.accountFactions[capturedAccF] = "Horde"
            end
            ApplyFactionStyle(capturedFBtn, GuusRaidBuilder_Config.accountFactions[capturedAccF])
            RefreshRightPanel()
        end)
        fBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(fBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Faction", 1, 1, 1)
            GameTooltip:AddLine("Click to toggle Horde / Alliance.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Determines available races.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        fBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(GRBLeftRows, fBtn)

        local badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        if count > 0 then
            badge:SetText("[" .. count .. "]")
            badge:SetTextColor(0.3, 1.0, 0.4)
        else
            badge:SetText("[0]")
            badge:SetTextColor(0.45, 0.45, 0.45)
        end

        -- Click: add a slot for this account, then jump right panel to their group
        local capturedAcc = accName
        row:SetScript("OnClick", function()
            if not presetName then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Select or create a preset first.")
                return
            end
            local slots = GuusRaidBuilder_Config.presets[presetName].slots
            local count = 0
            for si = 1, table.getn(slots) do
                if slots[si].account == capturedAcc then count = count + 1 end
            end
            if count >= 4 then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r " .. capturedAcc .. " already has 4 slots (max).")
                return
            end
            table.insert(slots, NewDefaultSlot(capturedAcc))
            RefreshAll()
            -- Scroll right panel to this account's group
            local targetY = GRB_accountTopY[string.lower(capturedAcc)] or 0
            local scrollBar = getglobal("GRBRightScrollFrameScrollBar")
            if scrollBar then
                local minVal, maxVal = scrollBar:GetMinMaxValues()
                if minVal and maxVal then
                    scrollBar:SetValue(math.min(maxVal, math.max(minVal, targetY)))
                end
            end
        end)

        prevRow = row
        table.insert(GRBLeftRows, row)
    end

    -- Add Account button
    local addBtn = CreateFrame("Button", "GRBAddAccountBtn", leftScrollContent)
    addBtn:SetWidth(LEFT_WIDTH - 22)
    addBtn:SetHeight(22)
    if prevRow then
        addBtn:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -5)
    else
        addBtn:SetPoint("TOPLEFT", leftScrollContent, "TOPLEFT", 2, -2)
    end
    addBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    addBtn:SetBackdropColor(0.08, 0.20, 0.08, 0.9)
    addBtn:SetBackdropBorderColor(0.25, 0.6, 0.25, 0.7)
    local addBtnTxt = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addBtnTxt:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
    addBtnTxt:SetText("+ Add Account")
    addBtnTxt:SetTextColor(0.35, 1.0, 0.35)
    addBtn:SetScript("OnEnter", function() addBtn:SetBackdropColor(0.14, 0.30, 0.14, 0.95) end)
    addBtn:SetScript("OnLeave", function() addBtn:SetBackdropColor(0.08, 0.20, 0.08, 0.9) end)
    addBtn:SetScript("OnClick", function()
        -- Simple inline popup
        if not GRB_AccPopupFrame then
            GRB_AccPopupFrame = CreateFrame("Frame", "GRBAccPopupFrame", mainFrame)
            GRB_AccPopupFrame:SetWidth(210)
            GRB_AccPopupFrame:SetHeight(78)
            GRB_AccPopupFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 60)
            GRB_AccPopupFrame:SetFrameStrata("DIALOG")
            GRB_AccPopupFrame:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 }
            })
            local lbl = GRB_AccPopupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOP", GRB_AccPopupFrame, "TOP", 0, -14)
            lbl:SetText("Account name:")
            GRB_AccEdit = CreateFrame("EditBox", "GRBAccEdit", GRB_AccPopupFrame, "InputBoxTemplate")
            GRB_AccEdit:SetWidth(140)
            GRB_AccEdit:SetHeight(20)
            GRB_AccEdit:SetPoint("TOP", GRB_AccPopupFrame, "TOP", 0, -30)
            GRB_AccEdit:SetAutoFocus(true)
            local doAdd = function()
                local name = trim(GRB_AccEdit:GetText())
                if name ~= "" then
                    table.insert(GuusRaidBuilder_Config.accounts, name)
                    RefreshLeftPanel()
                end
                GRB_AccPopupFrame:Hide()
            end
            GRB_AccEdit:SetScript("OnEnterPressed", doAdd)
            GRB_AccEdit:SetScript("OnEscapePressed", function() GRB_AccPopupFrame:Hide() end)
            local ok = CreateFrame("Button", nil, GRB_AccPopupFrame, "UIPanelButtonTemplate")
            ok:SetWidth(50)
            ok:SetHeight(18)
            ok:SetPoint("BOTTOMRIGHT", GRB_AccPopupFrame, "BOTTOMRIGHT", -10, 9)
            ok:SetText("Add")
            ok:SetScript("OnClick", doAdd)
            local cancel = CreateFrame("Button", nil, GRB_AccPopupFrame, "UIPanelButtonTemplate")
            cancel:SetWidth(58)
            cancel:SetHeight(18)
            cancel:SetPoint("BOTTOMRIGHT", ok, "BOTTOMLEFT", -4, 0)
            cancel:SetText("Cancel")
            cancel:SetScript("OnClick", function() GRB_AccPopupFrame:Hide() end)
        end
        GRB_AccEdit:SetText("")
        GRB_AccPopupFrame:Show()
        GRB_AccEdit:SetFocus()
    end)
    table.insert(GRBLeftRows, addBtn)

    -- Update scroll content height
    local rowCount = table.getn(accounts)
    leftScrollContent:SetHeight(math.max(400, rowCount * (ROW_HEIGHT + 2) + 60))

    local lsb = getglobal("GRBLeftScrollFrameScrollBar")
    if lsb then
        local maxScroll = math.max(0, rowCount * (ROW_HEIGHT + 2) + 60 - SCROLL_HEIGHT)
        lsb:SetMinMaxValues(0, maxScroll)
    end
end

-- ============================================================
-- RIGHT PANEL
-- ============================================================

local GRBRightRows = {}
local GRB_sortKey  = nil   -- "account","tier","class","role","spec","race","gender", or nil
local GRB_sortDir  = "asc" -- "asc" or "desc"

RefreshRightPanel = function()
    if not rightScrollContent then return end

    -- Clear old content
    for i = 1, table.getn(GRBRightRows) do
        GRBRightRows[i]:Hide()
        GRBRightRows[i]:SetParent(nil)
    end
    GRBRightRows = {}
    GRB_accountTopY = {}

    local presetName = GuusRaidBuilder_Config.currentPreset

    if not presetName or not GuusRaidBuilder_Config.presets[presetName] then
        local noFrame = CreateFrame("Frame", nil, rightScrollContent)
        noFrame:SetWidth(RIGHT_WIDTH - 22)
        noFrame:SetHeight(24)
        noFrame:SetPoint("TOP", rightScrollContent, "TOP", 0, -30)
        local noTxt = noFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noTxt:SetPoint("CENTER", noFrame, "CENTER", 0, 0)
        noTxt:SetText("No preset selected. Click [New] to create one.")
        noTxt:SetTextColor(0.55, 0.55, 0.55)
        table.insert(GRBRightRows, noFrame)
        return
    end

    local slots = GuusRaidBuilder_Config.presets[presetName].slots
    local yOffset = -4

    -- Column headers (click to sort; click active column again to reverse; third click clears sort)
    local headerRow = CreateFrame("Frame", nil, rightScrollContent)
    headerRow:SetWidth(RIGHT_WIDTH - 22)
    headerRow:SetHeight(18)
    headerRow:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
    local hdrKeys   = { "account", "tier", "class", "role", "spec", "race", "gender" }
    local hdrLabels = { "Account", "Tier", "Class", "Role", "Spec", "Race", "Gender" }
    for h = 1, 7 do
        local key   = hdrKeys[h]
        local label = hdrLabels[h]
        local hBtn = CreateFrame("Button", nil, headerRow)
        hBtn:SetWidth(COL_W[h])
        hBtn:SetHeight(18)
        hBtn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", COL_X[h], 0)
        local ht = hBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("TOPLEFT", hBtn, "TOPLEFT", 0, 0)
        local function UpdateHdr()
            if GRB_sortKey == key then
                ht:SetText(label .. (GRB_sortDir == "asc" and " ^" or " v"))
                ht:SetTextColor(1.0, 0.9, 0.35)
            else
                ht:SetText(label)
                ht:SetTextColor(0.55, 0.55, 0.65)
            end
        end
        UpdateHdr()
        hBtn:SetScript("OnClick", function()
            if GRB_sortKey == key then
                if GRB_sortDir == "asc" then
                    GRB_sortDir = "desc"
                else
                    GRB_sortKey = nil
                    GRB_sortDir = "asc"
                end
            else
                GRB_sortKey = key
                GRB_sortDir = "asc"
            end
            RefreshRightPanel()
        end)
        hBtn:SetScript("OnEnter", function() ht:SetTextColor(1.0, 1.0, 0.6) end)
        hBtn:SetScript("OnLeave", function() UpdateHdr() end)
    end
    table.insert(GRBRightRows, headerRow)
    yOffset = yOffset - 20

    -- Build sorted display order (preserves original slot indices for editing)
    local displayOrder = {}
    for i = 1, table.getn(slots) do
        table.insert(displayOrder, i)
    end
    if GRB_sortKey then
        local sk = GRB_sortKey
        local sd = GRB_sortDir
        table.sort(displayOrder, function(a, b)
            local va = string.lower(tostring(slots[a][sk] or ""))
            local vb = string.lower(tostring(slots[b][sk] or ""))
            if sd == "asc" then return va < vb else return va > vb end
        end)
    end

    local lastAccount = nil

    for di = 1, table.getn(displayOrder) do
        local i = displayOrder[di]
        local slot = slots[i]
        local acc  = slot.account or "?"

        -- Account group divider
        if acc ~= lastAccount then
            -- Store the scroll position for this account (distance from top)
            GRB_accountTopY[string.lower(acc)] = -yOffset

            local div = CreateFrame("Frame", nil, rightScrollContent)
            div:SetWidth(RIGHT_WIDTH - 22)
            div:SetHeight(17)
            div:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
            div:SetBackdrop({
                bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            div:SetBackdropColor(0.07, 0.07, 0.10, 0.97)
            div:SetBackdropBorderColor(0.38, 0.38, 0.48, 0.55)
            local divTxt = div:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            divTxt:SetPoint("LEFT", div, "LEFT", 6, 0)
            divTxt:SetText(acc)
            divTxt:SetTextColor(0.95, 0.88, 0.45)
            table.insert(GRBRightRows, div)
            yOffset = yOffset - 19
            lastAccount = acc
        end

        -- Role-coloured slot row background
        local role  = string.lower(slot.role or "mdps")
        local bg    = ROLE_BG[role] or ROLE_BG.mdps

        local row = CreateFrame("Frame", "GRBSlotRow" .. i, rightScrollContent)
        row:SetWidth(RIGHT_WIDTH - 22)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        row:SetBackdropBorderColor(0.38, 0.38, 0.48, 0.55)
        table.insert(GRBRightRows, row)

        -- Account label (dim)
        local accLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        accLbl:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[1] + 3, -6)
        accLbl:SetWidth(COL_W[1] - 3)
        accLbl:SetText(acc)
        accLbl:SetTextColor(0.55, 0.55, 0.65)

        local capturedI = i

        -- Tier
        local tierBtn = MakeCycleBtn(row, "GRBTier" .. i, COL_W[2], ROW_HEIGHT - 4,
            TIERS, slot.tier or "t2r",
            function(v) slots[capturedI].tier = v end)
        tierBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[2], -2)

        -- Class (faction-restricted; resets role+spec to valid values for new class)
        local classOpts = GetClassesForAccount(acc)
        -- Sanitize stored class against faction
        if not IsClassValidForAccount(slot.class, acc) then
            slot.class = classOpts[1]
            if not IsRoleValidForClass(slot.role, slot.class) then
                slot.role = GetClassRoles(slot.class)[1]
            end
            slot.spec = GetSpecs(slot.class)[1]
        end
        local classBtn = MakeCycleBtn(row, "GRBClass" .. i, COL_W[3], ROW_HEIGHT - 4,
            classOpts, slot.class or classOpts[1],
            function(v)
                slots[capturedI].class = v
                -- Reset role if no longer valid
                if not IsRoleValidForClass(slots[capturedI].role, v) then
                    slots[capturedI].role = GetClassRoles(v)[1]
                end
                -- Reset spec to first valid
                slots[capturedI].spec = GetSpecs(v)[1]
                RefreshRightPanel()
            end)
        classBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[3], -2)

        -- Role (only valid roles for this class)
        local roleOpts = GetClassRoles(slot.class or "warrior")
        -- Sanitize stored role
        if not IsRoleValidForClass(slot.role, slot.class) then
            slot.role = roleOpts[1]
        end
        local roleBtn = MakeCycleBtn(row, "GRBRole" .. i, COL_W[4], ROW_HEIGHT - 4,
            roleOpts, slot.role,
            function(v)
                slots[capturedI].role = v
                RefreshSummary()
                RefreshRightPanel()
            end)
        roleBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[4], -2)

        -- Spec (class-dependent, restricted options)
        local specOpts = GetSpecs(slot.class or "warrior")
        -- Sanitize stored spec
        local specValid = false
        for si = 1, table.getn(specOpts) do
            if specOpts[si] == slot.spec then specValid = true; break end
        end
        if not specValid then slot.spec = specOpts[1] end
        local specBtn = MakeCycleBtn(row, "GRBSpec" .. i, COL_W[5], ROW_HEIGHT - 4,
            specOpts, slot.spec,
            function(v) slots[capturedI].spec = v end)
        specBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[5], -2)

        -- Race (faction + class restricted)
        local raceOpts = GetRacesForAccount(acc, slot.class)
        -- Sanitize stored race
        if not IsRaceValidForAccount(slot.race, acc, slot.class) then
            slot.race = raceOpts[1]
        end
        local raceBtn = MakeCycleBtn(row, "GRBRace" .. i, COL_W[6], ROW_HEIGHT - 4,
            raceOpts, slot.race,
            function(v) slots[capturedI].race = v end)
        raceBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[6], -2)

        -- Gender
        local genderBtn = MakeCycleBtn(row, "GRBGender" .. i, COL_W[7], ROW_HEIGHT - 4,
            GENDERS, slot.gender or "male",
            function(v) slots[capturedI].gender = v end)
        genderBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[7], -2)

        -- Remove [X]
        local remBtn = CreateFrame("Button", "GRBRem" .. i, row)
        remBtn:SetWidth(COL_W[8])
        remBtn:SetHeight(ROW_HEIGHT - 4)
        remBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[8], -2)
        remBtn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        remBtn:SetBackdropColor(0.40, 0.08, 0.08, 0.9)
        remBtn:SetBackdropBorderColor(0.70, 0.20, 0.20, 0.8)
        local remTxt = remBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        remTxt:SetPoint("CENTER", remBtn, "CENTER", 0, 0)
        remTxt:SetText("X")
        remTxt:SetTextColor(1, 0.35, 0.35)
        remBtn:SetScript("OnEnter", function() remBtn:SetBackdropColor(0.60, 0.15, 0.15, 0.95) end)
        remBtn:SetScript("OnLeave", function() remBtn:SetBackdropColor(0.40, 0.08, 0.08, 0.9) end)
        remBtn:SetScript("OnClick", function()
            table.remove(slots, capturedI)
            RefreshAll()
        end)

        yOffset = yOffset - ROW_HEIGHT - 2
    end

    -- Add-slot buttons (one per account), laid out in rows
    yOffset = yOffset - 10
    local labelFrame = CreateFrame("Frame", nil, rightScrollContent)
    labelFrame:SetWidth(RIGHT_WIDTH - 22)
    labelFrame:SetHeight(18)
    labelFrame:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
    local labelTxt = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelTxt:SetPoint("TOPLEFT", labelFrame, "TOPLEFT", 2, 0)
    labelTxt:SetText("Add slot for:")
    labelTxt:SetTextColor(0.55, 0.55, 0.55)
    table.insert(GRBRightRows, labelFrame)
    yOffset = yOffset - 22

    local accounts = GuusRaidBuilder_Config.accounts or {}
    local xBtn = 4
    for ai = 1, table.getn(accounts) do
        local accName = accounts[ai]
        local ab = CreateFrame("Button", "GRBAddSlot" .. ai, rightScrollContent)
        ab:SetWidth(90)
        ab:SetHeight(20)
        ab:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", xBtn, yOffset)
        ab:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        ab:SetBackdropColor(0.08, 0.18, 0.08, 0.9)
        ab:SetBackdropBorderColor(0.25, 0.55, 0.25, 0.7)
        local abt = ab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        abt:SetPoint("CENTER", ab, "CENTER", 0, 0)
        abt:SetText("+ " .. accName)
        abt:SetTextColor(0.35, 1.0, 0.35)
        ab:SetScript("OnEnter", function() ab:SetBackdropColor(0.14, 0.28, 0.14, 0.95) end)
        ab:SetScript("OnLeave", function() ab:SetBackdropColor(0.08, 0.18, 0.08, 0.9) end)

        local capturedAcc = accName
        ab:SetScript("OnClick", function()
            local count = 0
            for si = 1, table.getn(slots) do
                if slots[si].account == capturedAcc then count = count + 1 end
            end
            if count >= 4 then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r " .. capturedAcc .. " already has 4 slots (max).")
                return
            end
            table.insert(slots, NewDefaultSlot(capturedAcc))
            RefreshAll()
        end)
        table.insert(GRBRightRows, ab)

        xBtn = xBtn + 94
        if xBtn + 90 > RIGHT_WIDTH - 22 then
            xBtn = 4
            yOffset = yOffset - 24
        end
    end

    yOffset = yOffset - 30

    -- Update scroll content height and scrollbar range
    local totalH = math.max(SCROLL_HEIGHT, -yOffset + 20)
    rightScrollContent:SetHeight(totalH)
    local rsb = getglobal("GRBRightScrollFrameScrollBar")
    if rsb then
        rsb:SetMinMaxValues(0, math.max(0, totalH - SCROLL_HEIGHT))
    end
end

-- ============================================================
-- REFRESH ALL
-- ============================================================

RefreshAll = function()
    RefreshPresetButton()
    RefreshSummary()
    RefreshLeftPanel()
    RefreshRightPanel()
end

-- ============================================================
-- PRESET MANAGEMENT
-- ============================================================

local function SwitchPreset(name)
    GuusRaidBuilder_Config.currentPreset = name
    RefreshAll()
end

local function CreatePreset(name)
    name = trim(name)
    if name == "" then return end
    EnsureConfig()
    if not GuusRaidBuilder_Config.presets[name] then
        GuusRaidBuilder_Config.presets[name] = { slots = {} }
    end
    SwitchPreset(name)
end

-- ============================================================
-- MAIN GUI
-- ============================================================

local function CreateMainGUI()
    if mainFrame then mainFrame:Show(); RefreshAll(); return end

    mainFrame = CreateFrame("Frame", "GuusRaidBuilderFrame", UIParent)
    mainFrame:SetWidth(WINDOW_WIDTH)
    mainFrame:SetHeight(WINDOW_HEIGHT)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseDown", function() mainFrame:StartMoving() end)
    mainFrame:SetScript("OnMouseUp",   function() mainFrame:StopMovingOrSizing() end)
    mainFrame:SetScript("OnMouseWheel", function() end)
    mainFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    mainFrame:SetFrameStrata("MEDIUM")

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", mainFrame, "TOP", 0, -13)
    title:SetText("Guus Raid Builder")

    -- Close
    local closeBtn = CreateFrame("Button", nil, mainFrame)
    closeBtn:SetWidth(20); closeBtn:SetHeight(20)
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -6)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- ===== TOP BAR Y = -32 =====
    local TOP_Y = -32

    -- "Preset:" label
    local pLbl = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pLbl:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, TOP_Y)
    pLbl:SetText("Preset:")

    -- Preset cycle button
    presetCycleBtn = CreateFrame("Button", "GRBPresetCycleBtn", mainFrame)
    presetCycleBtn:SetWidth(100)
    presetCycleBtn:SetHeight(22)
    presetCycleBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 63, TOP_Y)
    presetCycleBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    presetCycleBtn:SetBackdropColor(0.12, 0.12, 0.22, 0.9)
    presetCycleBtn:SetBackdropBorderColor(0.48, 0.48, 0.70, 0.8)
    presetCycleBtn.lbl = presetCycleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presetCycleBtn.lbl:SetPoint("CENTER", presetCycleBtn, "CENTER", 0, 0)
    presetCycleBtn.lbl:SetText("(none)")
    presetCycleBtn.lbl:SetTextColor(1, 1, 0.65)
    presetCycleBtn:SetScript("OnEnter", function() presetCycleBtn:SetBackdropColor(0.22, 0.22, 0.36, 0.95) end)
    presetCycleBtn:SetScript("OnLeave", function() presetCycleBtn:SetBackdropColor(0.12, 0.12, 0.22, 0.9) end)
    presetCycleBtn:SetScript("OnClick", function()
        local names = GetPresetNames()
        if table.getn(names) == 0 then return end
        local cur = GuusRaidBuilder_Config.currentPreset
        SwitchPreset(cycleNext(names, cur or names[1]))
    end)

    -- [New]
    local newBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    newBtn:SetWidth(42); newBtn:SetHeight(20)
    newBtn:SetPoint("TOPLEFT", presetCycleBtn, "TOPRIGHT", 4, 0)
    newBtn:SetText("New")
    newBtn:SetScript("OnClick", function()
        if not GRB_NewPopupFrame then
            GRB_NewPopupFrame = CreateFrame("Frame", "GRBNewPopupFrame", mainFrame)
            GRB_NewPopupFrame:SetWidth(220); GRB_NewPopupFrame:SetHeight(78)
            GRB_NewPopupFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 60)
            GRB_NewPopupFrame:SetFrameStrata("DIALOG")
            GRB_NewPopupFrame:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 }
            })
            local nl = GRB_NewPopupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nl:SetPoint("TOP", GRB_NewPopupFrame, "TOP", 0, -14)
            nl:SetText("New preset name:")
            GRB_NewEdit = CreateFrame("EditBox", "GRBNewEdit", GRB_NewPopupFrame, "InputBoxTemplate")
            GRB_NewEdit:SetWidth(150); GRB_NewEdit:SetHeight(20)
            GRB_NewEdit:SetPoint("TOP", GRB_NewPopupFrame, "TOP", 0, -30)
            GRB_NewEdit:SetAutoFocus(true)
            local doCreate = function()
                CreatePreset(GRB_NewEdit:GetText())
                GRB_NewPopupFrame:Hide()
            end
            GRB_NewEdit:SetScript("OnEnterPressed", doCreate)
            GRB_NewEdit:SetScript("OnEscapePressed", function() GRB_NewPopupFrame:Hide() end)
            local ok = CreateFrame("Button", nil, GRB_NewPopupFrame, "UIPanelButtonTemplate")
            ok:SetWidth(55); ok:SetHeight(18)
            ok:SetPoint("BOTTOMRIGHT", GRB_NewPopupFrame, "BOTTOMRIGHT", -10, 9)
            ok:SetText("Create")
            ok:SetScript("OnClick", doCreate)
            local cancel = CreateFrame("Button", nil, GRB_NewPopupFrame, "UIPanelButtonTemplate")
            cancel:SetWidth(58); cancel:SetHeight(18)
            cancel:SetPoint("BOTTOMRIGHT", ok, "BOTTOMLEFT", -4, 0)
            cancel:SetText("Cancel")
            cancel:SetScript("OnClick", function() GRB_NewPopupFrame:Hide() end)
        end
        GRB_NewEdit:SetText("")
        GRB_NewPopupFrame:Show()
        GRB_NewEdit:SetFocus()
    end)

    -- [Delete]
    local delBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    delBtn:SetWidth(48); delBtn:SetHeight(20)
    delBtn:SetPoint("TOPLEFT", newBtn, "TOPRIGHT", 3, 0)
    delBtn:SetText("Delete")
    delBtn:SetScript("OnClick", function()
        local name = GuusRaidBuilder_Config.currentPreset
        if not name then return end
        GuusRaidBuilder_Config.presets[name] = nil
        local names = GetPresetNames()
        if table.getn(names) > 0 then
            SwitchPreset(names[1])
        else
            GuusRaidBuilder_Config.currentPreset = nil
            RefreshAll()
        end
    end)

    -- [Export]
    local exportBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    exportBtn:SetWidth(52); exportBtn:SetHeight(20)
    exportBtn:SetPoint("TOPLEFT", delBtn, "TOPRIGHT", 3, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local name = GuusRaidBuilder_Config.currentPreset
        if not name then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r No preset selected.")
            return
        end
        ShowExportFrame(name)
    end)

    -- [Import]
    local importBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    importBtn:SetWidth(52); importBtn:SetHeight(20)
    importBtn:SetPoint("TOPLEFT", exportBtn, "TOPRIGHT", 3, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        ShowImportFrame()
    end)

    -- [Stop] (hidden until executing)
    local stopBtn = CreateFrame("Button", "GRBStopBtn", mainFrame)
    stopBtn:SetWidth(50); stopBtn:SetHeight(26)
    stopBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -35, TOP_Y - 2)
    stopBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    stopBtn:SetBackdropColor(0.50, 0.08, 0.08, 0.95)
    stopBtn:SetBackdropBorderColor(1.0, 0.30, 0.30, 1.0)
    local stopTxt = stopBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stopTxt:SetPoint("CENTER", stopBtn, "CENTER", 0, 0)
    stopTxt:SetText("Stop")
    stopTxt:SetTextColor(1.0, 0.4, 0.4)
    stopBtn:SetScript("OnClick", function() GRB_stopRequested = true end)
    stopBtn:Hide()
    GRB_stopButton = stopBtn

    -- [Execute Raid] (gold button)
    local execBtn = CreateFrame("Button", "GRBExecBtn", mainFrame)
    execBtn:SetWidth(112); execBtn:SetHeight(26)
    execBtn:SetPoint("TOPRIGHT", stopBtn, "TOPLEFT", -5, 0)
    execBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    execBtn:SetBackdropColor(0.35, 0.27, 0.0, 0.95)
    execBtn:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
    local execTxt = execBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    execTxt:SetPoint("CENTER", execBtn, "CENTER", 0, 0)
    execTxt:SetText("Execute Raid")
    execTxt:SetTextColor(1.0, 0.9, 0.1)
    execBtn:SetScript("OnEnter", function() execBtn:SetBackdropColor(0.50, 0.40, 0.0, 0.95) end)
    execBtn:SetScript("OnLeave", function() execBtn:SetBackdropColor(0.35, 0.27, 0.0, 0.95) end)
    execBtn:SetScript("OnClick", function()
        local name = GuusRaidBuilder_Config.currentPreset
        if name then ExecuteRaid(name) end
    end)

    -- ===== SUMMARY BAR =====
    summaryText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, TOP_Y - 28)
    summaryText:SetText("No preset selected")
    summaryText:SetTextColor(0.7, 0.7, 0.7)

    -- Separator line
    local sep = mainFrame:CreateTexture(nil, "BACKGROUND")
    sep:SetWidth(WINDOW_WIDTH - 28); sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 13, TOP_Y - 50)
    sep:SetTexture(0.35, 0.35, 0.45, 0.55)

    local PANEL_TOP = TOP_Y - 54

    -- ===== LEFT PANEL =====
    local leftHdr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    leftHdr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, PANEL_TOP)
    leftHdr:SetText("Accounts")
    leftHdr:SetTextColor(0.92, 0.87, 0.45)

    leftScrollFrame = CreateFrame("ScrollFrame", "GRBLeftScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    leftScrollFrame:SetWidth(LEFT_WIDTH - 5)
    leftScrollFrame:SetHeight(SCROLL_HEIGHT)
    leftScrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 13, PANEL_TOP - 18)
    leftScrollFrame:EnableMouseWheel(true)
    leftScrollFrame:SetScript("OnMouseWheel", function()
        local d = arg1
        if not d then return end
        local sb = getglobal("GRBLeftScrollFrameScrollBar")
        if sb then
            local mn, mx = sb:GetMinMaxValues()
            local cv = sb:GetValue()
            if mn and mx and cv then sb:SetValue(math.min(mx, math.max(mn, cv - d * 28))) end
        end
    end)
    leftScrollContent = CreateFrame("Frame", "GRBLeftScrollContent", leftScrollFrame)
    leftScrollContent:SetWidth(LEFT_WIDTH - 25)
    leftScrollContent:SetHeight(800)
    leftScrollFrame:SetScrollChild(leftScrollContent)

    -- Vertical separator
    local vSep = mainFrame:CreateTexture(nil, "BACKGROUND")
    vSep:SetWidth(1); vSep:SetHeight(SCROLL_HEIGHT + 20)
    vSep:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", LEFT_WIDTH + 14, PANEL_TOP)
    vSep:SetTexture(0.35, 0.35, 0.45, 0.50)

    -- ===== RIGHT PANEL =====
    local rightHdr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rightHdr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", LEFT_WIDTH + 20, PANEL_TOP)
    rightHdr:SetText("Raid Composition")
    rightHdr:SetTextColor(0.92, 0.87, 0.45)

    rightScrollFrame = CreateFrame("ScrollFrame", "GRBRightScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    rightScrollFrame:SetWidth(RIGHT_WIDTH - 5)
    rightScrollFrame:SetHeight(SCROLL_HEIGHT)
    rightScrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", LEFT_WIDTH + 19, PANEL_TOP - 18)
    rightScrollFrame:EnableMouseWheel(true)
    rightScrollFrame:SetScript("OnMouseWheel", function()
        local d = arg1
        if not d then return end
        local sb = getglobal("GRBRightScrollFrameScrollBar")
        if sb then
            local mn, mx = sb:GetMinMaxValues()
            local cv = sb:GetValue()
            if mn and mx and cv then sb:SetValue(math.min(mx, math.max(mn, cv - d * 28))) end
        end
    end)
    rightScrollContent = CreateFrame("Frame", "GRBRightScrollContent", rightScrollFrame)
    rightScrollContent:SetWidth(RIGHT_WIDTH - 25)
    rightScrollContent:SetHeight(2000)
    rightScrollFrame:SetScrollChild(rightScrollContent)

    RefreshAll()
    mainFrame:Show()
end

GuusRaidBuilder.CreateGUI = CreateMainGUI

-- ============================================================
-- MINIMAP ICON
-- ============================================================

local GRB_LDB, GRB_DBIcon, GRB_ldb

local function GRB_InitMinimapIcon()
    if not LibStub then return false end

    local ok = pcall(function()
        GRB_LDB   = LibStub("LibDataBroker-1.1", true)
        GRB_DBIcon = LibStub("LibDBIcon-1.0", true)
    end)
    if not ok then return false end
    if not GRB_LDB or not GRB_DBIcon then return false end

    local ok2 = pcall(function()
        GRB_ldb = GRB_LDB:NewDataObject("GuusRaidBuilder", {
            type = "launcher",
            text = "GRB",
            icon = "Interface\\Icons\\Spell_Nature_Bloodlust",
            OnClick = function(self, button)
                if button == "LeftButton" then
                    if mainFrame and mainFrame:IsShown() then
                        mainFrame:Hide()
                    else
                        if mainFrame then
                            mainFrame:Show()
                            RefreshAll()
                        else
                            CreateMainGUI()
                        end
                    end
                end
            end,
            OnTooltipShow = function(tooltip)
                if tooltip and tooltip.AddLine then
                    tooltip:AddLine("GuusRaidBuilder")
                    tooltip:AddLine("Click to open/close.")
                end
            end,
        })
    end)
    if not ok2 or not GRB_ldb then return false end

    pcall(function()
        GRB_DBIcon:Register("GuusRaidBuilder", GRB_ldb, GuusRaidBuilder_Config.minimap)
        GRB_DBIcon:Show("GuusRaidBuilder")
    end)
    return true
end

local GRB_iconAttempts = 0
local GRB_iconRetryFrame = CreateFrame("Frame")
local GRB_iconRetrySeconds = 0
GRB_iconRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    if not elapsed then return end
    GRB_iconRetrySeconds = GRB_iconRetrySeconds + elapsed
    if GRB_iconRetrySeconds < 2 then return end
    GRB_iconRetrySeconds = 0
    GRB_iconAttempts = GRB_iconAttempts + 1
    if GRB_InitMinimapIcon() or GRB_iconAttempts >= 5 then
        GRB_iconRetryFrame:SetScript("OnUpdate", nil)
    end
end)
GRB_iconRetryFrame:SetScript("OnUpdate", nil) -- disabled until VARIABLES_LOADED

-- ============================================================
-- INITIALIZATION
-- ============================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("VARIABLES_LOADED")
initFrame:SetScript("OnEvent", function()
    EnsureConfig()
    if not GuusRaidBuilder_Config.minimap then
        GuusRaidBuilder_Config.minimap = { hide = false, minimapPos = 200, radius = 80 }
    end
    initFrame:UnregisterEvent("VARIABLES_LOADED")
    -- Kick off minimap icon retry loop
    GRB_iconRetrySeconds = 0
    GRB_iconAttempts = 0
    if not GRB_InitMinimapIcon() then
        GRB_iconRetryFrame:SetScript("OnUpdate", function(self, elapsed)
            if not elapsed then return end
            GRB_iconRetrySeconds = GRB_iconRetrySeconds + elapsed
            if GRB_iconRetrySeconds < 2 then return end
            GRB_iconRetrySeconds = 0
            GRB_iconAttempts = GRB_iconAttempts + 1
            if GRB_InitMinimapIcon() or GRB_iconAttempts >= 5 then
                GRB_iconRetryFrame:SetScript("OnUpdate", nil)
            end
        end)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GuusRaidBuilder:|r Loaded. Type /grb to open.")
end)

-- ============================================================
-- AUTO-ADD ACCOUNT ON LOGIN
-- ============================================================

local function GRB_TryAddCurrentAccount()
    local name    = UnitName("player")
    local level   = UnitLevel("player")
    local faction = UnitFactionGroup("player")
    if not name or name == "" then return false end
    if not level or level == 0 then return false end
    if level < 60 then return true end -- not 60, skip but stop retrying

    EnsureConfig()
    -- Save/update faction for this account name
    if faction and faction ~= "" then
        GuusRaidBuilder_Config.accountFactions[name] = faction
    end
    local accounts = GuusRaidBuilder_Config.accounts
    -- Check if already in list (case-insensitive)
    local lname = string.lower(name)
    for i = 1, table.getn(accounts) do
        if string.lower(accounts[i]) == lname then return true end
    end
    -- Not found — add it
    table.insert(accounts, name)
    -- Refresh left panel if the window is already open
    if leftScrollContent then RefreshLeftPanel() end
    return true
end

local GRB_loginFrame = CreateFrame("Frame")
GRB_loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GRB_loginFrame:RegisterEvent("PLAYER_LOGIN")
local GRB_loginAttempts = 0
local GRB_loginRetryElapsed = 0
GRB_loginFrame:SetScript("OnEvent", function()
    GRB_loginAttempts = 0
    GRB_loginRetryElapsed = 0
    if not GRB_TryAddCurrentAccount() then
        GRB_loginFrame:SetScript("OnUpdate", function(self, elapsed)
            if not elapsed then return end
            GRB_loginRetryElapsed = GRB_loginRetryElapsed + elapsed
            if GRB_loginRetryElapsed < 2 then return end
            GRB_loginRetryElapsed = 0
            GRB_loginAttempts = GRB_loginAttempts + 1
            if GRB_TryAddCurrentAccount() or GRB_loginAttempts >= 10 then
                GRB_loginFrame:SetScript("OnUpdate", nil)
            end
        end)
    end
end)

SLASH_GUUSRAIDBUILDER1 = "/grb"
SLASH_GUUSRAIDBUILDER2 = "/raidbuilder"
SlashCmdList["GUUSRAIDBUILDER"] = function(msg)
    local cmd = trim(string.lower(msg or ""))
    if cmd == "" or cmd == "show" then
        if not mainFrame then
            CreateMainGUI()
        elseif mainFrame:IsShown() then
            mainFrame:Hide()
        else
            mainFrame:Show()
            RefreshAll()
        end
    elseif string.sub(cmd, 1, 4) == "hire" then
        local name = trim(string.sub(cmd, 5))
        if name == "" then name = GuusRaidBuilder_Config.currentPreset end
        if name then ExecuteRaid(name)
        else DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r No preset specified.") end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GuusRaidBuilder:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  /grb          - Open/close window")
        DEFAULT_CHAT_FRAME:AddMessage("  /grb hire mc  - Execute preset 'mc'")
    end
end
