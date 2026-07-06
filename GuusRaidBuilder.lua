-- GuusRaidBuilder.lua
-- Standalone raid composition builder for vanilla WoW (no SuperMacro dependency)
-- /grb to open

GuusRaidBuilder = GuusRaidBuilder or {}
GuusRaidBuilder_Config = GuusRaidBuilder_Config or {}

-- ============================================================
-- DATA TABLES
-- ============================================================

local TIERS = { "t0", "t1r", "t2r", "t3r", "t4r", "t5r", "t1d", "t2d", "t3d", "t4d", "t5d" }

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

-- Valid roles per class
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

-- Case-insensitive faction lookup (handles "aguus" vs "Aguus" mismatch)
local function GetAccountFaction(accountName)
    local f = GuusRaidBuilder_Config.accountFactions
    if not f then return nil end
    if f[accountName] then return f[accountName] end
    local lname = string.lower(accountName or "")
    for k, v in pairs(f) do
        if string.lower(k) == lname then return v end
    end
    return nil
end

-- Case-insensitive class lookup
local function GetAccountClass(accountName)
    local c = GuusRaidBuilder_Config.accountClasses
    if not c then return nil end
    if c[accountName] then return c[accountName] end
    local lname = string.lower(accountName or "")
    for k, v in pairs(c) do
        if string.lower(k) == lname then return v end
    end
    return nil
end

-- Case-insensitive accountClassAuto lookup
local function GetAccountClassAuto(accountName)
    local a = GuusRaidBuilder_Config.accountClassAuto
    if not a then return nil end
    if a[accountName] then return a[accountName] end
    local lname = string.lower(accountName or "")
    for k, v in pairs(a) do
        if string.lower(k) == lname then return v end
    end
    return nil
end

-- Returns races valid for the given account faction, optionally filtered by class
local function GetRacesForAccount(accountName, class)
    local faction = GetAccountFaction(accountName)
    local factionRaces
    if faction == "Alliance" then
        factionRaces = ALLIANCE_RACES
    elseif faction == "Horde" then
        factionRaces = HORDE_RACES
    else
        factionRaces = RACES  -- faction unknown: allow all
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
    local faction = GetAccountFaction(accountName)
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

local ROW_HEIGHT   = 22
local LEFT_WIDTH   = 200
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

local function cyclePrev(tbl, current)
    local idx = findIndex(tbl, current) - 1
    if idx < 1 then idx = table.getn(tbl) end
    return tbl[idx]
end

local function trim(s)
    s = string.gsub(s or "", "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function FormatMoneyText(copper)
    local amount = tonumber(copper) or 0
    local negative = amount < 0
    if negative then amount = -amount end

    local gold = math.floor(amount / 10000)
    local silver = math.floor(math.mod(amount, 10000) / 100)
    local copperOnly = math.mod(amount, 100)
    local text = gold .. "g " .. silver .. "s " .. copperOnly .. "c"

    if negative then
        return "-" .. text
    end
    return text
end

local function ReportExecuteMoneyChange(startMoney)
    if type(GetMoney) ~= "function" then return end

    local beforeMoney = tonumber(startMoney) or 0
    local afterMoney = GetMoney() or beforeMoney
    local delta = afterMoney - beforeMoney

    if delta < 0 then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffff00GuusRaidBuilder:|r Total cost " .. FormatMoneyText(-delta)
            .. " (before " .. FormatMoneyText(beforeMoney)
            .. ", after " .. FormatMoneyText(afterMoney) .. ")"
        )
    elseif delta > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffff00GuusRaidBuilder:|r Total gain " .. FormatMoneyText(delta)
            .. " (before " .. FormatMoneyText(beforeMoney)
            .. ", after " .. FormatMoneyText(afterMoney) .. ")"
        )
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffff00GuusRaidBuilder:|r No money change"
            .. " (before " .. FormatMoneyText(beforeMoney)
            .. ", after " .. FormatMoneyText(afterMoney) .. ")"
        )
    end
end

local SELF_SPAWN_TOKEN = "p:self"
local GRBRightRows = {}

local SyncSpawnOrder
local TogglePresetPicker
local RefreshExecuteStartButton
local GetPresetSpawnOrder
local MakeCycleBtn
local RefreshAll
local RefreshSummary
local RefreshPresetButton
local HidePresetPicker
local RefreshLeftPanel
local RefreshRightPanel
local OpenLegacyPicker
local GRB_CLASS_COLORS
local GetPresetSlots
local GetAccountSlotCount
local NewDefaultSlot
local GetPresetTotalCount

local function MoveSpawnToken(presetName, token, delta)
    local so = GetPresetSpawnOrder(presetName)
    for index = 1, table.getn(so) do
        if so[index] == token then
            local target = index + delta
            if target >= 1 and target <= table.getn(so) then
                so[index] = so[target]
                so[target] = token
            end
            break
        end
    end
end

local function GRB_SpawnMoveUp_OnClick()
    if not this or not this.presetName or not this.spawnToken then return end
    MoveSpawnToken(this.presetName, this.spawnToken, -1)
    RefreshRightPanel()
end

local function GRB_SpawnMoveDown_OnClick()
    if not this or not this.presetName or not this.spawnToken then return end
    MoveSpawnToken(this.presetName, this.spawnToken, 1)
    RefreshRightPanel()
end

local function GRB_AddSlotBtn_OnEnter()
    if this then this:SetBackdropColor(0.14, 0.28, 0.14, 0.95) end
end

local function GRB_AddSlotBtn_OnLeave()
    if this then this:SetBackdropColor(0.08, 0.18, 0.08, 0.9) end
end

local function GRB_AddSlotBtn_OnClick()
    if not this or not this.presetName or not this.accountName then return end
    local presetName = this.presetName
    local accName = this.accountName
    local slots = GetPresetSlots(presetName)
    if GetPresetTotalCount(presetName) >= 40 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Raid is full (40/40).")
        return
    end
    local count = GetAccountSlotCount(presetName, accName)
    if count >= 4 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r " .. accName .. " already has 4 slots (max).")
        return
    end
    table.insert(slots, NewDefaultSlot(accName))
    RefreshAll()
end

local function GRB_RenderLegacyRow(rightScrollContent, yOffset, presetName, legacySlots, acc, ls, ai, lSpawnToken, lSpawnPos)
    local lrow = CreateFrame("Frame", "GRBLegacyRow"..ai, rightScrollContent)
    lrow:SetWidth(RIGHT_WIDTH - 22)
    lrow:SetHeight(ROW_HEIGHT)
    lrow:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
    lrow:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
    lrow:SetBackdropColor(0.20, 0.05, 0.30, 0.85)
    lrow:SetBackdropBorderColor(0.60, 0.25, 0.80, 0.75)
    table.insert(GRBRightRows, lrow)

    local nameLbl = lrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("TOPLEFT", lrow, "TOPLEFT", COL_X[1] + 3, -5)
    nameLbl:SetWidth(COL_X[4] - COL_X[1] - 6)
    nameLbl:SetText("* " .. ls.charName)
    nameLbl:SetTextColor(0.80, 0.50, 1.0)

    local capturedAcc = acc
    local charClass = string.lower(GetAccountClass(acc) or "warrior")
    local roleOpts  = GetClassRoles(charClass)
    local roleValid = false
    for ri = 1, table.getn(roleOpts) do if roleOpts[ri] == ls.role then roleValid = true; break end end
    if not roleValid then ls.role = roleOpts[1] end

    local roleBtn = MakeCycleBtn(lrow, "GRBLegacyRole"..ai, COL_W[4], ROW_HEIGHT - 2,
        roleOpts, ls.role,
        function(v)
            legacySlots[capturedAcc].role = v
            local sp = GetSpecs(string.lower(GetAccountClass(capturedAcc) or "warrior"))
            legacySlots[capturedAcc].spec = sp[1]
            RefreshSummary()
            RefreshRightPanel()
        end, "Role")
    roleBtn:SetPoint("TOPLEFT", lrow, "TOPLEFT", COL_X[4], -1)

    local specOpts = GetSpecs(charClass)
    local specValid2 = false
    for si = 1, table.getn(specOpts) do if specOpts[si] == (ls.spec or "") then specValid2 = true; break end end
    if not specValid2 then ls.spec = specOpts[1] end
    local specBtn = MakeCycleBtn(lrow, "GRBLegacySpec"..ai, COL_W[5], ROW_HEIGHT - 2,
        specOpts, ls.spec,
        function(v) legacySlots[capturedAcc].spec = v end, "Spec")
    specBtn:SetPoint("TOPLEFT", lrow, "TOPLEFT", COL_X[5], -1)

    local fillerLbl = lrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fillerLbl:SetPoint("TOPLEFT", lrow, "TOPLEFT", COL_X[3] + 2, -5)
    fillerLbl:SetWidth(COL_X[4] - COL_X[3] - 4)
    local displayClass = string.upper(string.sub(charClass, 1, 1)) .. string.sub(charClass, 2)
    local cc = GRB_CLASS_COLORS[displayClass] or {0.70, 0.50, 0.90}
    fillerLbl:SetText(displayClass)
    fillerLbl:SetTextColor(cc[1], cc[2], cc[3])

    local lremBtn = CreateFrame("Button", "GRBLegacyRem"..ai, lrow)
    lremBtn:SetWidth(COL_W[8]) ; lremBtn:SetHeight(ROW_HEIGHT - 2)
    lremBtn:SetPoint("TOPLEFT", lrow, "TOPLEFT", COL_X[8], -1)
    lremBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
    lremBtn:SetBackdropColor(0.40, 0.08, 0.08, 0.9) ; lremBtn:SetBackdropBorderColor(0.70, 0.20, 0.20, 0.8)
    local lremTxt = lremBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lremTxt:SetPoint("CENTER", lremBtn, "CENTER", 0, 0) ; lremTxt:SetText("X") ; lremTxt:SetTextColor(1, 0.35, 0.35)
    lremBtn:SetScript("OnEnter", function() lremBtn:SetBackdropColor(0.60, 0.15, 0.15, 0.95) end)
    lremBtn:SetScript("OnLeave", function() lremBtn:SetBackdropColor(0.40, 0.08, 0.08, 0.9) end)
    lremBtn:SetScript("OnClick", function() legacySlots[capturedAcc] = nil ; RefreshAll() end)

    local lBadge = lrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lBadge:SetPoint("TOPLEFT", lrow, "TOPLEFT", 420, -5) ; lBadge:SetWidth(28)
    lBadge:SetText(tostring(lSpawnPos)) ; lBadge:SetTextColor(0.80, 0.50, 1.0)
    local lupBtn = CreateFrame("Button", nil, lrow)
    lupBtn:SetWidth(18) ; lupBtn:SetHeight(ROW_HEIGHT - 2)
    lupBtn:SetPoint("TOPLEFT", lrow, "TOPLEFT", 450, -1)
    lupBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
    lupBtn:SetBackdropColor(0.1, 0.05, 0.15, 0.85) ; lupBtn:SetBackdropBorderColor(0.5, 0.3, 0.7, 0.6)
    local lupTxt = lupBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lupTxt:SetPoint("CENTER", lupBtn, "CENTER", 0, 0) ; lupTxt:SetText("^") ; lupTxt:SetTextColor(0.8, 0.6, 1.0)
    lupBtn.presetName = presetName
    lupBtn.spawnToken = lSpawnToken
    lupBtn:SetScript("OnClick", GRB_SpawnMoveUp_OnClick)
    local ldnBtn = CreateFrame("Button", nil, lrow)
    ldnBtn:SetWidth(18) ; ldnBtn:SetHeight(ROW_HEIGHT - 2)
    ldnBtn:SetPoint("TOPLEFT", lrow, "TOPLEFT", 470, -1)
    ldnBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
    ldnBtn:SetBackdropColor(0.1, 0.05, 0.15, 0.85) ; ldnBtn:SetBackdropBorderColor(0.5, 0.3, 0.7, 0.6)
    local ldnTxt = ldnBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ldnTxt:SetPoint("CENTER", ldnBtn, "CENTER", 0, 0) ; ldnTxt:SetText("v") ; ldnTxt:SetTextColor(0.8, 0.6, 1.0)
    ldnBtn.presetName = presetName
    ldnBtn.spawnToken = lSpawnToken
    ldnBtn:SetScript("OnClick", GRB_SpawnMoveDown_OnClick)

    return yOffset - ROW_HEIGHT - 1
end

local function GRB_RenderBotRow(rightScrollContent, yOffset, presetName, slots, slot, i, spawnToken, spawnPos)
    local acc  = slot.account or "?"
    local role = string.lower(slot.role or "mdps")
    local bg   = ROLE_BG[role] or ROLE_BG.mdps
    local row = CreateFrame("Frame", "GRBSlotRow" .. i, rightScrollContent)
    row:SetWidth(RIGHT_WIDTH - 22) ; row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
    row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
    row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    row:SetBackdropBorderColor(0.26, 0.28, 0.36, 0.55)
    table.insert(GRBRightRows, row)

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(4)
    accent:SetHeight(ROW_HEIGHT - 6)
    accent:SetPoint("LEFT", row, "LEFT", 1, 0)
    accent:SetTexture(bg[1] + 0.10, bg[2] + 0.10, bg[3] + 0.10, 0.95)

    local accLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accLbl:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[1] + 3, -5)
    accLbl:SetWidth(COL_W[1] - 3) ; accLbl:SetText(acc) ; accLbl:SetTextColor(0.85, 0.87, 0.92)

    local capturedI = i

    local tierBtn = MakeCycleBtn(row, "GRBTier" .. i, COL_W[2], ROW_HEIGHT - 2,
        TIERS, slot.tier or "t2r", function(v) slots[capturedI].tier = v end, "Tier")
    tierBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[2], -1)

    local classOpts = GetClassesForAccount(acc)
    if not IsClassValidForAccount(slot.class, acc) then
        slot.class = classOpts[1]
        if not IsRoleValidForClass(slot.role, slot.class) then slot.role = GetClassRoles(slot.class)[1] end
        slot.spec = GetSpecs(slot.class)[1]
    end
    local classBtn = MakeCycleBtn(row, "GRBClass" .. i, COL_W[3], ROW_HEIGHT - 2,
        classOpts, slot.class or classOpts[1],
        function(v)
            slots[capturedI].class = v
            if not IsRoleValidForClass(slots[capturedI].role, v) then slots[capturedI].role = GetClassRoles(v)[1] end
            slots[capturedI].spec = GetSpecs(v)[1]
            RefreshRightPanel()
        end, "Class")
    classBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[3], -1)

    local roleOpts = GetClassRoles(slot.class or "warrior")
    if not IsRoleValidForClass(slot.role, slot.class) then slot.role = roleOpts[1] end
    local roleBtn = MakeCycleBtn(row, "GRBRole" .. i, COL_W[4], ROW_HEIGHT - 2,
        roleOpts, slot.role,
        function(v) slots[capturedI].role = v ; RefreshSummary() ; RefreshRightPanel() end, "Role")
    roleBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[4], -1)

    local specOpts = GetSpecs(slot.class or "warrior")
    local specValid = false
    for si = 1, table.getn(specOpts) do if specOpts[si] == slot.spec then specValid = true; break end end
    if not specValid then slot.spec = specOpts[1] end
    local specBtn = MakeCycleBtn(row, "GRBSpec" .. i, COL_W[5], ROW_HEIGHT - 2,
        specOpts, slot.spec, function(v) slots[capturedI].spec = v end, "Spec")
    specBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[5], -1)

    local raceOpts = GetRacesForAccount(acc, slot.class)
    local displayRace = slot.race
    if not IsRaceValidForAccount(displayRace, acc, slot.class) then
        displayRace = raceOpts[1]
        slot.race = displayRace
    end
    local raceBtn = MakeCycleBtn(row, "GRBRace" .. i, COL_W[6], ROW_HEIGHT - 2,
        raceOpts, displayRace, function(v) slots[capturedI].race = v end, "Race")
    raceBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[6], -1)

    local genderBtn = MakeCycleBtn(row, "GRBGender" .. i, COL_W[7], ROW_HEIGHT - 2,
        GENDERS, slot.gender or "male", function(v) slots[capturedI].gender = v end, "Gender")
    genderBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[7], -1)

    local remBtn = CreateFrame("Button", "GRBRem" .. i, row)
    remBtn:SetWidth(COL_W[8]) ; remBtn:SetHeight(ROW_HEIGHT - 2)
    remBtn:SetPoint("TOPLEFT", row, "TOPLEFT", COL_X[8], -1)
    remBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
    remBtn:SetBackdropColor(0.40, 0.08, 0.08, 0.9) ; remBtn:SetBackdropBorderColor(0.70, 0.20, 0.20, 0.8)
    local remTxt = remBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    remTxt:SetPoint("CENTER", remBtn, "CENTER", 0, 0) ; remTxt:SetText("X") ; remTxt:SetTextColor(1, 0.35, 0.35)
    remBtn:SetScript("OnEnter", function() remBtn:SetBackdropColor(0.60, 0.15, 0.15, 0.95) end)
    remBtn:SetScript("OnLeave", function() remBtn:SetBackdropColor(0.40, 0.08, 0.08, 0.9) end)
    remBtn:SetScript("OnClick", function() table.remove(slots, capturedI) ; RefreshAll() end)

    local spawnBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spawnBadge:SetPoint("TOPLEFT", row, "TOPLEFT", 420, -5) ; spawnBadge:SetWidth(28)
    spawnBadge:SetText(tostring(spawnPos)) ; spawnBadge:SetTextColor(1.0, 0.9, 0.35)
    local upBtn = CreateFrame("Button", nil, row)
    upBtn:SetWidth(18) ; upBtn:SetHeight(ROW_HEIGHT - 2)
    upBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 450, -1)
    upBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
    upBtn:SetBackdropColor(0.1, 0.1, 0.15, 0.85) ; upBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.6)
    local upTxt = upBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    upTxt:SetPoint("CENTER", upBtn, "CENTER", 0, 0) ; upTxt:SetText("^") ; upTxt:SetTextColor(0.8, 0.8, 1.0)
    upBtn.presetName = presetName
    upBtn.spawnToken = spawnToken
    upBtn:SetScript("OnClick", GRB_SpawnMoveUp_OnClick)
    local dnBtn = CreateFrame("Button", nil, row)
    dnBtn:SetWidth(18) ; dnBtn:SetHeight(ROW_HEIGHT - 2)
    dnBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 470, -1)
    dnBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
    dnBtn:SetBackdropColor(0.1, 0.1, 0.15, 0.85) ; dnBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.6)
    local dnTxt = dnBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dnTxt:SetPoint("CENTER", dnBtn, "CENTER", 0, 0) ; dnTxt:SetText("v") ; dnTxt:SetTextColor(0.8, 0.8, 1.0)
    dnBtn.presetName = presetName
    dnBtn.spawnToken = spawnToken
    dnBtn:SetScript("OnClick", GRB_SpawnMoveDown_OnClick)

    return yOffset - ROW_HEIGHT - 1
end

-- ============================================================
-- CONFIG / DATA ACCESS
-- ============================================================

GRB_CLASS_COLORS = {
    Warrior = {0.78, 0.61, 0.43},
    Mage    = {0.41, 0.80, 0.94},
    Warlock = {0.58, 0.51, 0.79},
    Priest  = {1.00, 1.00, 1.00},
    Druid   = {1.00, 0.49, 0.04},
    Paladin = {0.96, 0.55, 0.73},
    Shaman  = {0.00, 0.44, 0.87},
    Hunter  = {0.00, 1.00, 0.00},
    Rogue   = {1.00, 0.96, 0.41},
}

local function EnsureConfig()
    if not GuusRaidBuilder_Config then GuusRaidBuilder_Config = {} end
    if not GuusRaidBuilder_Config.presets then GuusRaidBuilder_Config.presets = {} end
    if not GuusRaidBuilder_Config.accounts then
        GuusRaidBuilder_Config.accounts = {}
    end
    if not GuusRaidBuilder_Config.accountFactions then
        GuusRaidBuilder_Config.accountFactions = {}
    end
    if not GuusRaidBuilder_Config.accountClasses then
        GuusRaidBuilder_Config.accountClasses = {}
    end
    if not GuusRaidBuilder_Config.accountClassAuto then
        GuusRaidBuilder_Config.accountClassAuto = {}
    end
    if not GuusRaidBuilder_Config.playerRoles then
        GuusRaidBuilder_Config.playerRoles = {}
    end
    if not GuusRaidBuilder_Config.nextUID then
        GuusRaidBuilder_Config.nextUID = 1
    end
    if not GuusRaidBuilder_Config.executeStartIndex then
        GuusRaidBuilder_Config.executeStartIndex = 1
    end
    if GuusRaidBuilder_Config.currentPreset == nil then
        GuusRaidBuilder_Config.currentPreset = nil
    end
end

GetPresetSlots = function(presetName)
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

GetAccountSlotCount = function(presetName, accountName)
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

local GetPresetLegacySlots

local function GetExecuteStartIndex(maxIndex)
    EnsureConfig()
    local idx = tonumber(GuusRaidBuilder_Config.executeStartIndex) or 1
    idx = math.floor(idx)
    if idx < 1 then idx = 1 end
    GuusRaidBuilder_Config.executeStartIndex = idx
    return idx
end

local function GetRunnableSpawnCount(presetName)
    if not presetName then return 1 end
    local spawnOrder
    if SyncSpawnOrder then
        spawnOrder = SyncSpawnOrder(presetName)
    else
        spawnOrder = GetPresetSpawnOrder(presetName)
    end
    local visibleTotal = table.getn(spawnOrder)
    if visibleTotal < 1 then visibleTotal = 1 end
    return visibleTotal
end

local function CycleExecuteStart(delta)
    local maxIndex = GetRunnableSpawnCount(GuusRaidBuilder_Config.currentPreset)
    local idx = GetExecuteStartIndex(maxIndex) + delta
    if idx < 1 then idx = maxIndex end
    if idx > maxIndex then idx = 1 end
    GuusRaidBuilder_Config.executeStartIndex = idx
    RefreshExecuteStartButton()
end

local function GetRoleSummary(presetName)
    EnsureConfig()
    local slots = GetPresetSlots(presetName)
    local s = {
        tank = 0, healer = 0, rdps = 0, mdps = 0,
        total = 0, bots = 0, legacy = 0, selfRole = nil,
    }
    for i = 1, table.getn(slots) do
        local role = string.lower(slots[i].role or "mdps")
        if s[role] ~= nil then s[role] = s[role] + 1 end
        s.total = s.total + 1
        s.bots = s.bots + 1
    end

    local legacySlots = GetPresetLegacySlots(presetName)
    for _, ls in pairs(legacySlots) do
        if ls and ls.charName and ls.charName ~= "" then
            local role = string.lower(ls.role or "")
            if s[role] ~= nil then s[role] = s[role] + 1 end
            s.total = s.total + 1
            s.legacy = s.legacy + 1
        end
    end

    local playerName = UnitName("player")
    if playerName and playerName ~= "" then
        local playerClass = GetAccountClass(playerName) or UnitClass("player")
        local configuredRole = GuusRaidBuilder_Config.playerRoles[playerName]
        local playerRole = nil
        if configuredRole and IsRoleValidForClass(configuredRole, playerClass) then
            playerRole = string.lower(configuredRole)
        else
            local validRoles = GetClassRoles(playerClass)
            if table.getn(validRoles) == 1 then
                playerRole = validRoles[1]
            end
        end
        if playerRole and s[playerRole] ~= nil then
            s[playerRole] = s[playerRole] + 1
        end
        s.selfRole = playerRole
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

NewDefaultSlot = function(accountName)
    local faction = GetAccountFaction(accountName)
    local defaultRace = (faction == "Alliance") and "human" or (faction == "Horde") and "orc" or "human"
    EnsureConfig()
    local uid = GuusRaidBuilder_Config.nextUID
    GuusRaidBuilder_Config.nextUID = uid + 1
    -- Use the stored account class (manual override first, then auto-detected) if valid
    local storedClass = GetAccountClass(accountName) or GetAccountClassAuto(accountName)
    local defaultClass = "warrior"
    local defaultRole  = "tank"
    local defaultSpec  = "default"
    if storedClass and IsClassValidForAccount(storedClass, accountName) then
        defaultClass = string.lower(storedClass)
        defaultRole  = GetClassRoles(defaultClass)[1]
        defaultSpec  = GetSpecs(defaultClass)[1]
    end
    return {
        uid     = uid,
        account = accountName,
        tier    = "t2r",
        class   = defaultClass,
        role    = defaultRole,
        spec    = defaultSpec,
        race    = defaultRace,
        gender  = "male",
    }
end

-- ============================================================
-- LEGACY SLOT HELPERS
-- ============================================================

GetPresetLegacySlots = function(presetName)
    EnsureConfig()
    if not presetName or not GuusRaidBuilder_Config.presets[presetName] then return {} end
    local p = GuusRaidBuilder_Config.presets[presetName]
    if not p.legacySlots then p.legacySlots = {} end
    return p.legacySlots
end

local function BuildLegacyCommand(ls)
    local cmd = ".z addlegacy \"" .. (ls.charName or "?") .. "\" " .. (ls.role or "mdps")
    if ls.spec and ls.spec ~= "" and ls.spec ~= "default" then
        cmd = cmd .. " " .. ls.spec
    end
    return cmd
end

-- Returns total raiders: 1 (you) + bots + assigned legacy chars
GetPresetTotalCount = function(presetName)
    local botCount = table.getn(GetPresetSlots(presetName))
    local legacyCount = 0
    local ls = GetPresetLegacySlots(presetName)
    for _, v in pairs(ls) do
        if v and v.charName and v.charName ~= "" then legacyCount = legacyCount + 1 end
    end
    return 1 + botCount + legacyCount  -- 1 = yourself
end

-- ============================================================
-- SPAWN ORDER HELPERS
-- ============================================================

-- Ensure every slot in the preset has a stable uid.
local function AssignSlotUIDs(presetName)
    EnsureConfig()
    local slots = GetPresetSlots(presetName)
    for i = 1, table.getn(slots) do
        if not slots[i].uid then
            slots[i].uid = GuusRaidBuilder_Config.nextUID
            GuusRaidBuilder_Config.nextUID = GuusRaidBuilder_Config.nextUID + 1
        end
    end
end

GetPresetSpawnOrder = function(presetName)
    EnsureConfig()
    if not presetName or not GuusRaidBuilder_Config.presets[presetName] then return {} end
    local p = GuusRaidBuilder_Config.presets[presetName]
    if not p.spawnOrder then p.spawnOrder = {} end
    return p.spawnOrder
end

-- Sync spawnOrder: remove stale tokens, append new ones in default order.
-- Returns (orderedTokens, slotByToken) where slotByToken maps "b:uid" -> slot object.
SyncSpawnOrder = function(presetName)
    AssignSlotUIDs(presetName)
    local preset     = GuusRaidBuilder_Config.presets[presetName]
    local slots      = GetPresetSlots(presetName)
    local legSlots   = GetPresetLegacySlots(presetName)
    local accounts   = GuusRaidBuilder_Config.accounts or {}
    local spawnOrder = GetPresetSpawnOrder(presetName)

    -- Build validity sets
    local validTokens = {}
    local slotByToken = {}
    validTokens[SELF_SPAWN_TOKEN] = true
    for i = 1, table.getn(slots) do
        local token = "b:" .. slots[i].uid
        validTokens[token] = true
        slotByToken[token] = slots[i]
    end
    for ai = 1, table.getn(accounts) do
        local acc = accounts[ai]
        local ls  = legSlots[acc]
        if ls and ls.charName and ls.charName ~= "" then
            validTokens["l:" .. acc] = true
        end
    end

    -- Keep existing valid tokens, remove stale/duplicates
    local filtered = {}
    local seen = {}
    for i = 1, table.getn(spawnOrder) do
        local token = spawnOrder[i]
        if validTokens[token] and not seen[token] then
            table.insert(filtered, token)
            seen[token] = true
        end
    end
    if not seen[SELF_SPAWN_TOKEN] then
        table.insert(filtered, SELF_SPAWN_TOKEN)
        seen[SELF_SPAWN_TOKEN] = true
    end
    -- Append new bot slots (index order)
    for i = 1, table.getn(slots) do
        local token = "b:" .. slots[i].uid
        if not seen[token] then
            table.insert(filtered, token)
            seen[token] = true
        end
    end
    -- Append new legacy (account order)
    for ai = 1, table.getn(accounts) do
        local acc   = accounts[ai]
        local token = "l:" .. acc
        if not seen[token] and validTokens[token] then
            table.insert(filtered, token)
            seen[token] = true
        end
    end

    if not preset.selfSpawnInitialized then
        local reordered = { SELF_SPAWN_TOKEN }
        for i = 1, table.getn(filtered) do
            if filtered[i] ~= SELF_SPAWN_TOKEN then
                table.insert(reordered, filtered[i])
            end
        end
        filtered = reordered
        preset.selfSpawnInitialized = true
    end

    preset.spawnOrder = filtered
    return filtered, slotByToken
end

-- ============================================================
-- EXECUTE LOGIC (hire() equivalent, no SuperMacro needed)
-- ============================================================

local GRB_executeFrame  = nil
local GRB_executing     = false
local GRB_stopRequested = false
local GRB_stopButton    = nil

local function ExecuteRaid(presetName)
    local legacySlots = GetPresetLegacySlots(presetName)
    local spawnOrder, slotByToken = SyncSpawnOrder(presetName)
    local displayTotal = table.getn(spawnOrder)
    local executeStartMoney = nil
    local startDisplayIndex = GetExecuteStartIndex(displayTotal)
    if startDisplayIndex > displayTotal then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff0000GuusRaidBuilder:|r Spawn #" .. startDisplayIndex
            .. " is higher than the number of rows in this preset."
        )
        return
    end
    local startSpawnPos = startDisplayIndex
    if startSpawnPos < 1 then startSpawnPos = 1 end

    -- Build command list in spawn order
    local queuedCommands = {}
    local queuedLabels = {}
    local queuedDisplayIndices = {}
    for si = startSpawnPos, table.getn(spawnOrder) do
        local token = spawnOrder[si]
        if token == SELF_SPAWN_TOKEN then
            -- Visible row only; nothing to execute for the local player.
        elseif string.sub(token, 1, 2) == "b:" then
            local s = slotByToken[token]
            if s then
                table.insert(queuedCommands, BuildCommand(s))
                table.insert(queuedLabels, (s.account or "?") .. " [bot]")
                table.insert(queuedDisplayIndices, si)
            end
        elseif string.sub(token, 1, 2) == "l:" then
            local acc = string.sub(token, 3)
            local ls = legacySlots[acc]
            if ls and ls.charName and ls.charName ~= "" then
                table.insert(queuedCommands, BuildLegacyCommand(ls))
                table.insert(queuedLabels, ls.charName .. " [legacy]")
                table.insert(queuedDisplayIndices, si)
            end
        end
    end

    local queueTotal = table.getn(queuedCommands)
    if queueTotal == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r No slots in preset '" .. presetName .. "'!")
        return
    end
    if GRB_executing then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Already running. Press Stop first.")
        return
    end
    if startDisplayIndex > 1 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GuusRaidBuilder:|r Starting from spawn order " .. startDisplayIndex .. ".")
    end

    GRB_executing     = true
    GRB_stopRequested = false
    if GRB_stopButton then GRB_stopButton:Show() end
    if type(GetMoney) == "function" then
        executeStartMoney = GetMoney() or 0
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffff00GuusRaidBuilder:|r Starting money " .. FormatMoneyText(executeStartMoney)
        )
    end

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
            local stoppedAt = startDisplayIndex - 1
            if index > 0 and queuedDisplayIndices[index] then
                stoppedAt = queuedDisplayIndices[index]
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cffff6600GuusRaidBuilder:|r Stopped at " .. stoppedAt .. "/" .. displayTotal)
            ReportExecuteMoneyChange(executeStartMoney)
            return
        end
        elapsed = elapsed + 1
        if elapsed >= delay or index == 0 then
            index = index + 1
            if index <= queueTotal then
                local actualIndex = queuedDisplayIndices[index] or startDisplayIndex
                SendChatMessage(queuedCommands[index], "SAY")
                elapsed = 0
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00GuusRaidBuilder:|r " .. actualIndex .. "/" .. displayTotal
                    .. " -> " .. (queuedLabels[index] or "?")
                )
            else
                GRB_executing = false
                if GRB_stopButton then GRB_stopButton:Hide() end
                GRB_executeFrame:SetScript("OnUpdate", nil)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GuusRaidBuilder:|r Done! Sent " .. queueTotal .. " invites.")
                ReportExecuteMoneyChange(executeStartMoney)
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
local summaryBar        = nil
local summaryNameText   = nil
local summaryBadges     = nil
local executeStartBtn   = nil
local presetCycleBtn    = nil
local presetDropBtn     = nil
local GRB_PresetPickerFrame = nil
local exportFrame       = nil
local exportEditBox     = nil

-- Tracks y-position of each account's header in the right panel (for scroll-to)
local GRB_accountTopY = {}

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================

-- ============================================================
-- CYCLE BUTTON FACTORY
-- ============================================================

local GRB_CYCLE_TTIP = "Left-click: next  ·  Right-click: previous"

MakeCycleBtn = function(parent, name, w, h, options, currentVal, onChange, tooltipTitle)
    local btn = CreateFrame("Button", name, parent)
    
    -- Tell the button to listen for both Left and Right clicks
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
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
    btn:SetScript("OnEnter", function()
        btn:SetBackdropColor(0.22, 0.22, 0.32, 0.95)
        if tooltipTitle then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipTitle, 1, 1, 1)
            GameTooltip:AddLine(GRB_CYCLE_TTIP, 0.8, 0.8, 0.8, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropColor(0.12, 0.12, 0.18, 0.92)
        if tooltipTitle then GameTooltip:Hide() end
    end)
    
    -- In Vanilla, 'arg1' securely holds which mouse button was clicked
    btn:SetScript("OnClick", function()
        local buttonPressed = arg1
        local newVal = (buttonPressed == "RightButton")
            and cyclePrev(options, btn.lbl:GetText())
            or  cycleNext(options, btn.lbl:GetText())
        btn.lbl:SetText(newVal)
        if onChange then onChange(newVal) end
    end)

    return btn
end

local function CommitExecuteStartInput()
    if not executeStartBtn or not executeStartBtn.input then return end
    local raw = trim(executeStartBtn.input:GetText() or "")
    local idx = tonumber(raw)
    if idx then idx = math.floor(idx) end
    if not idx or idx < 1 then idx = 1 end
    GuusRaidBuilder_Config.executeStartIndex = idx
    RefreshExecuteStartButton()
end

local function GRB_ExecuteStartBtn_OnEnter()
    GameTooltip:SetOwner(executeStartBtn.input or executeStartBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Start from spawn order", 1, 1, 1)
    GameTooltip:AddLine("Uses the visible SpawnOrder column.", 0.8, 0.8, 0.8, 1)
    GameTooltip:AddLine("If you start on your own row, execution skips it and continues with the next inviteable row.", 0.8, 0.8, 0.8, 1)
    GameTooltip:Show()
end

local function GRB_ExecuteStartBtn_OnLeave()
    GameTooltip:Hide()
end

local function GRB_ExecuteStartInput_OnEnterPressed()
    CommitExecuteStartInput()
    if executeStartBtn and executeStartBtn.input then executeStartBtn.input:ClearFocus() end
end

local function GRB_ExecuteStartInput_OnEscapePressed()
    RefreshExecuteStartButton()
    if executeStartBtn and executeStartBtn.input then executeStartBtn.input:ClearFocus() end
end

local function GRB_ExecuteStartInput_OnEditFocusLost()
    CommitExecuteStartInput()
end

local function GRB_ExecuteStartInput_OnTextChanged()
    local raw = executeStartBtn.input:GetText() or ""
    local digitsOnly = string.gsub(raw, "[^0-9]", "")
    if digitsOnly ~= raw then
        executeStartBtn.input:SetText(digitsOnly)
    end
    local idx = tonumber(digitsOnly)
    if idx then
        GuusRaidBuilder_Config.executeStartIndex = math.floor(idx)
    end
end

local function CreateExecuteStartButton(parent, anchor)
    executeStartBtn = CreateFrame("Frame", "GRBExecuteStartControl", parent)
    executeStartBtn:SetWidth(92)
    executeStartBtn:SetHeight(22)
    executeStartBtn:SetPoint("RIGHT", anchor, "LEFT", -4, 0)

    executeStartBtn.lbl = executeStartBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    executeStartBtn.lbl:SetPoint("LEFT", executeStartBtn, "LEFT", 0, 0)
    executeStartBtn.lbl:SetText("Spawn #")
    executeStartBtn.lbl:SetTextColor(0.92, 0.87, 0.45)

    executeStartBtn.input = CreateFrame("EditBox", "GRBExecuteStartEditBox", executeStartBtn, "InputBoxTemplate")
    executeStartBtn.input:SetWidth(28)
    executeStartBtn.input:SetHeight(20)
    executeStartBtn.input:SetPoint("RIGHT", executeStartBtn, "RIGHT", 0, 0)
    executeStartBtn.input:SetAutoFocus(false)
    executeStartBtn.input:SetMaxLetters(3)
    executeStartBtn.input:SetFontObject(GameFontNormalSmall)
    executeStartBtn.input:SetJustifyH("CENTER")
    executeStartBtn.input:SetScript("OnEnter", GRB_ExecuteStartBtn_OnEnter)
    executeStartBtn.input:SetScript("OnLeave", GRB_ExecuteStartBtn_OnLeave)
    executeStartBtn.input:SetScript("OnTextChanged", GRB_ExecuteStartInput_OnTextChanged)
    executeStartBtn.input:SetScript("OnEnterPressed", GRB_ExecuteStartInput_OnEnterPressed)
    executeStartBtn.input:SetScript("OnEscapePressed", GRB_ExecuteStartInput_OnEscapePressed)
    executeStartBtn.input:SetScript("OnEditFocusLost", GRB_ExecuteStartInput_OnEditFocusLost)
    return executeStartBtn
end

local function GRB_RightScrollFrame_OnMouseWheel()
    local d = arg1
    if not d then return end
    local sb = getglobal("GRBRightScrollFrameScrollBar")
    if sb then
        local mn, mx = sb:GetMinMaxValues()
        local cv = sb:GetValue()
        if mn and mx and cv then sb:SetValue(math.min(mx, math.max(mn, cv - d * 28))) end
    end
end

local function GRB_TransferBtn_OnClick()
    SendChatMessage(".z transfer", "SAY")
end

local function GRB_MainCloseBtn_OnClick()
    HidePresetPicker()
    if mainFrame then mainFrame:Hide() end
end

local function GRB_PresetCycleBtn_OnEnter()
    presetCycleBtn:SetBackdropColor(0.22, 0.22, 0.36, 0.95)
    GameTooltip:SetOwner(presetCycleBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Preset", 1, 1, 1)
    GameTooltip:AddLine("Left-click: next  ·  Right-click: previous", 0.8, 0.8, 0.8, 1)
    GameTooltip:AddLine("Click ▼ to pick from list", 1, 1, 0.6, 1)
    GameTooltip:Show()
end

local function GRB_PresetCycleBtn_OnLeave()
    presetCycleBtn:SetBackdropColor(0.12, 0.12, 0.22, 0.9)
    GameTooltip:Hide()
end

local function GRB_PresetCycleBtn_OnClick()
    local buttonPressed = arg1
    local names = GetPresetNames()
    if table.getn(names) == 0 then return end
    local cur = GuusRaidBuilder_Config.currentPreset
    local nextName = (buttonPressed == "RightButton")
        and cyclePrev(names, cur or names[1])
        or  cycleNext(names, cur or names[1])
    SwitchPreset(nextName)
end

local function GRB_PresetDropBtn_OnEnter()
    presetDropBtn:SetBackdropColor(0.22, 0.22, 0.36, 0.95)
    GameTooltip:SetOwner(presetDropBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Preset list", 1, 1, 1)
    GameTooltip:AddLine("Click to pick a preset", 0.8, 0.8, 0.8, 1)
    GameTooltip:Show()
end

local function GRB_PresetDropBtn_OnLeave()
    presetDropBtn:SetBackdropColor(0.12, 0.12, 0.22, 0.9)
    GameTooltip:Hide()
end

local function GRB_PresetDropBtn_OnClick()
    TogglePresetPicker(presetCycleBtn)
end

local function GRB_ExportBtn_OnClick()
    local name = GuusRaidBuilder_Config.currentPreset
    if not name then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r No preset selected.")
        return
    end
    ShowExportFrame(name)
end

local function GRB_ImportBtn_OnClick()
    ShowImportFrame()
end

local function GRB_StopBtn_OnClick()
    GRB_stopRequested = true
end

local function GRB_ExecBtn_OnEnter()
    local btn = getglobal("GRBExecBtn")
    if btn then btn:SetBackdropColor(0.50, 0.40, 0.0, 0.95) end
end

local function GRB_ExecBtn_OnLeave()
    local btn = getglobal("GRBExecBtn")
    if btn then btn:SetBackdropColor(0.35, 0.27, 0.0, 0.95) end
end

local function GRB_ExecBtn_OnClick()
    local name = GuusRaidBuilder_Config.currentPreset
    if name then ExecuteRaid(name) end
end

-- ============================================================
-- EXPORT FRAME
-- ============================================================

local function BuildExportText(presetName)
    local slots       = GetPresetSlots(presetName)
    local legacySlots = GetPresetLegacySlots(presetName)
    local spawnOrder, slotByToken = SyncSpawnOrder(presetName)
    local spawnTotal  = table.getn(spawnOrder)

    if spawnTotal == 0 then
        return "-- No slots in preset '" .. presetName .. "'"
    end

    local lines   = {}
    local lastAcc = nil
    table.insert(lines, '["' .. presetName .. '"] = {')
    table.insert(lines, "    -- == Group 1 ==")

    for soi = 1, spawnTotal do
        local token = spawnOrder[soi]

        -- Groups follow the visible order in blocks of 5.
        if soi > 1 and math.mod(soi - 1, 5) == 0 then
            local groupNum = math.floor((soi - 1) / 5) + 1
            table.insert(lines, "")
            table.insert(lines, "    -- == Group " .. groupNum .. "  (spawn " .. soi .. "-" .. math.min(soi + 4, spawnTotal) .. ") ==")
            lastAcc = nil
        end

        if token == SELF_SPAWN_TOKEN then
            table.insert(lines, "    -- you")
            lastAcc = nil
        elseif string.sub(token, 1, 2) == "b:" then
            local s = slotByToken[token]
            if s then
                local acc = s.account or "?"
                if acc ~= lastAcc then
                    table.insert(lines, "    -- " .. acc)
                    lastAcc = acc
                end
                table.insert(lines, '    "' .. BuildCommand(s) .. '",')
            end
        elseif string.sub(token, 1, 2) == "l:" then
            local acc = string.sub(token, 3)
            local ls  = legacySlots[acc]
            if ls and ls.charName and ls.charName ~= "" then
                table.insert(lines, "    -- legacychar " .. ls.charName .. "  (" .. acc .. ")")
                table.insert(lines, '    "' .. BuildLegacyCommand(ls) .. '",')
                lastAcc = nil
            end
        end
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
        exportFrame:SetScript("OnMouseUp", function() exportFrame:StopMovingOrSizing() end)
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

        local selBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
        selBtn:SetWidth(90)
        selBtn:SetHeight(22)
        selBtn:SetPoint("BOTTOMLEFT", exportFrame, "BOTTOMLEFT", 15, 14)
        selBtn:SetText("Select All")
        selBtn:SetScript("OnClick", function()
            exportEditBox:SetFocus()
            exportEditBox:HighlightText()
        end)

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

-- Parses the export text block and returns presetName, slots[], legacySlots{}, errors[]
-- Expected format (one or more presets, we import the first one found):
--   ["presetName"] = {
--       ".z addinvite account tier class role spec race gender",
--       -- legacychar CharacterName  (account)
--       ".z addlegacy \"CharacterName\" role [spec]",
--   },
local function ParseImportText(text)
    if not text or trim(text) == "" then
        return nil, nil, nil, { "Nothing to import." }
    end

    local presetName = string.match(text, '%["(.-)"%]%s*=%s*{')
    if not presetName or trim(presetName) == "" then
        return nil, nil, nil, { 'Could not find preset name. Expected: ["name"] = {' }
    end
    presetName = trim(presetName)

    local slots = {}
    local legacySlots = {}
    local errors = {}
    local pendingLegacy = nil

    for rawLine in string.gfind(text, "([^\r\n]+)") do
        local line = trim(rawLine)

        local legacyChar, legacyAcc = string.match(line, "^%-%-%s*legacychar%s+(.+)%s+%(([^%)]+)%)$")
        if legacyChar and legacyAcc then
            pendingLegacy = {
                charName = trim(legacyChar),
                account = trim(legacyAcc),
            }
        else
            if string.sub(line, 1, 1) == '"' then
                line = string.gsub(line, '^"', "")
                line = string.gsub(line, '",?$', "")
            elseif string.sub(line, 1, 1) == "'" then
                line = string.gsub(line, "^'", "")
                line = string.gsub(line, "',?$", "")
            end
            line = trim(line)

            local acc, tier, class, role, spec, race, gender =
                string.match(line, "^%.z%s+addinvite%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
            if acc then
                table.insert(slots, {
                    account = acc,
                    tier = tier,
                    class = string.lower(class),
                    role = string.lower(role),
                    spec = string.lower(spec),
                    race = string.lower(race),
                    gender = string.lower(gender),
                })
                pendingLegacy = nil
            else
                local charName, legacyRole, legacySpec =
                    string.match(line, '^%.z%s+addlegacy%s+"(.-)"%s+(%S+)%s*(%S*)$')
                if charName and pendingLegacy and pendingLegacy.account and pendingLegacy.account ~= "" then
                    legacySlots[pendingLegacy.account] = {
                        charName = charName,
                        role = string.lower(legacyRole),
                        spec = string.lower(legacySpec or ""),
                    }
                    pendingLegacy = nil
                end
            end
        end
    end

    if table.getn(slots) == 0 and countTableElements(legacySlots) == 0 then
        table.insert(errors, "No valid '.z addinvite ...' or '.z addlegacy ...' lines found.")
        return presetName, nil, nil, errors
    end

    return presetName, slots, legacySlots, errors
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
        hint:SetText('Paste a full Export block here: ["name"] = { ".z addinvite ...", ".z addlegacy ..." }')
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
            local presetName, slots, legacySlots, errors = ParseImportText(text)

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

            -- Infer faction for each account from the imported slot races
            local hordeRaceSet   = {}
            local allianceRaceSet = {}
            for _, r in pairs(HORDE_RACES)   do hordeRaceSet[r]    = true end
            for _, r in pairs(ALLIANCE_RACES) do allianceRaceSet[r] = true end
            local inferredFaction = {}
            for si = 1, table.getn(slots) do
                local acc  = slots[si].account
                local race = string.lower(slots[si].race or "")
                local lkey = string.lower(acc)
                -- Alliance evidence wins (first definitive race found per account wins)
                if allianceRaceSet[race] then
                    inferredFaction[lkey] = { name = acc, faction = "Alliance" }
                elseif hordeRaceSet[race] and not inferredFaction[lkey] then
                    inferredFaction[lkey] = { name = acc, faction = "Horde" }
                end
            end
            -- Always apply inferred faction from import (import text is ground truth)
            for _, info in pairs(inferredFaction) do
                GuusRaidBuilder_Config.accountFactions[info.name] = info.faction
            end

            -- Create or overwrite the preset
            if not GuusRaidBuilder_Config.presets[presetName] then
                GuusRaidBuilder_Config.presets[presetName] = {}
            end
            GuusRaidBuilder_Config.presets[presetName].slots = slots
            GuusRaidBuilder_Config.presets[presetName].legacySlots = legacySlots or {}
            GuusRaidBuilder_Config.currentPreset = presetName

            importFrame.statusTxt:SetText(
                "|cff66ff66Imported '" .. presetName .. "' with "
                .. table.getn(slots) .. " bot slot(s) and "
                .. countTableElements(legacySlots or {}) .. " legacy slot(s).|r"
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
    if not summaryText or not summaryNameText or not summaryBadges then return end
    local name = GuusRaidBuilder_Config.currentPreset
    if not name then
        summaryNameText:SetText("No preset selected")
        summaryText:SetTextColor(0.6, 0.6, 0.6)
        summaryText:SetText("Create a preset to start building a raid.")
        for _, badge in pairs(summaryBadges) do
            if badge.key == "total" then
                badge.value:SetText("-/40")
            else
                badge.value:SetText(badge.prefix .. " -")
            end
            badge.value:SetTextColor(0.7, 0.7, 0.7)
        end
        return
    end
    local s = GetRoleSummary(name)
    local remaining = 40 - s.total
    summaryNameText:SetText("Preset: " .. name)
    summaryNameText:SetTextColor(1.0, 0.95, 0.60)
    local selfText = s.selfRole and ("You " .. s.selfRole) or "You total only"
    summaryText:SetText("Bots " .. s.bots .. "   Legacy " .. s.legacy .. "   " .. selfText .. "   Remaining " .. remaining)
    summaryText:SetTextColor(0.78, 0.78, 0.84)

    summaryBadges.tank.value:SetText("T " .. tostring(s.tank))
    summaryBadges.tank.value:SetTextColor(1.0, 0.40, 0.40)
    summaryBadges.healer.value:SetText("H " .. tostring(s.healer))
    summaryBadges.healer.value:SetTextColor(0.45, 1.0, 0.45)
    summaryBadges.rdps.value:SetText("R " .. tostring(s.rdps))
    summaryBadges.rdps.value:SetTextColor(0.45, 0.70, 1.0)
    summaryBadges.mdps.value:SetText("M " .. tostring(s.mdps))
    summaryBadges.mdps.value:SetTextColor(1.0, 0.92, 0.40)
    summaryBadges.total.value:SetText(tostring(s.total) .. "/40")
    if s.total >= 40 then
        summaryBadges.total.value:SetTextColor(1.0, 0.35, 0.35)
    else
        summaryBadges.total.value:SetTextColor(1.0, 0.95, 0.55)
    end
end

-- ============================================================
-- PRESET CYCLE BUTTON
-- ============================================================

RefreshPresetButton = function()
    if not presetCycleBtn then return end
    local name = GuusRaidBuilder_Config.currentPreset
    presetCycleBtn.lbl:SetText(name or "(none)")
end

RefreshExecuteStartButton = function()
    if not executeStartBtn or not executeStartBtn.input then return end
    local idx = GetExecuteStartIndex(GetRunnableSpawnCount(GuusRaidBuilder_Config.currentPreset))
    executeStartBtn.input:SetText(tostring(idx))
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
        local accClass = GetAccountClass(accName)
        local accClassColor = accClass and GRB_CLASS_COLORS[accClass] or {0.9, 0.9, 1.0}
        nameTxt:SetTextColor(accClassColor[1], accClassColor[2], accClassColor[3])
        nameTxt:SetWidth(80)

        -- [L] Legacy assign button
        local presetName2 = GuusRaidBuilder_Config.currentPreset
        local legacySlots2 = presetName2 and GetPresetLegacySlots(presetName2) or {}
        local ls2 = legacySlots2[accName]

        local lBtn = CreateFrame("Button", "GRBLegacy" .. i, row)
        lBtn:SetWidth(20)
        lBtn:SetHeight(ROW_HEIGHT - 6)
        lBtn:SetPoint("RIGHT", row, "RIGHT", -47, 0)
        lBtn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        lBtn.lbl = lBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lBtn.lbl:SetPoint("CENTER", lBtn, "CENTER", 0, 0)
        lBtn.lbl:SetText("L")
        local GRB_LBTN_ROLE_BG = {
            tank   = { 0.35, 0.08, 0.08 },
            healer = { 0.08, 0.28, 0.08 },
            rdps   = { 0.08, 0.14, 0.35 },
            mdps   = { 0.30, 0.24, 0.04 },
        }
        local GRB_LBTN_ROLE_TC = {
            tank   = { 1.0, 0.4, 0.4 },
            healer = { 0.4, 1.0, 0.4 },
            rdps   = { 0.4, 0.7, 1.0 },
            mdps   = { 1.0, 0.9, 0.3 },
        }
        local GRB_LBTN_ROLE_ABBR = {
            tank = "T", healer = "H", rdps = "R", mdps = "M",
        }
        local function ApplyLBtnStyle(btn, ls)
            if ls then
                local role = ls.role or "tank"
                local bg = GRB_LBTN_ROLE_BG[role] or { 0.25, 0.05, 0.35 }
                local tc = GRB_LBTN_ROLE_TC[role]  or { 0.85, 0.55, 1.0 }
                btn:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
                btn:SetBackdropBorderColor(tc[1]*0.85, tc[2]*0.85, tc[3]*0.85, 0.9)
                btn.lbl:SetText(GRB_LBTN_ROLE_ABBR[role] or "L")
                btn.lbl:SetTextColor(tc[1], tc[2], tc[3])
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 0.85)
                btn:SetBackdropBorderColor(0.40, 0.40, 0.40, 0.7)
                btn.lbl:SetText("L")
                btn.lbl:SetTextColor(0.45, 0.45, 0.45)
            end
        end
        ApplyLBtnStyle(lBtn, ls2)
        local capturedAccL = accName
        lBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(lBtn, "ANCHOR_RIGHT")
            local pn = GuusRaidBuilder_Config.currentPreset
            local ls = pn and GetPresetLegacySlots(pn)[capturedAccL]
            if ls then
                GameTooltip:SetText("Legacy: " .. ls.charName, 0.85, 0.55, 1.0)
                GameTooltip:AddLine(ls.role .. (ls.spec ~= "" and (" / " .. ls.spec) or ""), 0.8, 0.8, 0.8)
                GameTooltip:AddLine("Click to change / clear", 1, 1, 0)
            else
                GameTooltip:SetText("No legacy assigned", 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Click to assign a legacy character", 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        lBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lBtn:SetScript("OnClick", function()
            local pn = GuusRaidBuilder_Config.currentPreset
            if not pn then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Select or create a preset first.")
                return
            end
            OpenLegacyPicker(capturedAccL, pn)
        end)
        table.insert(GRBLeftRows, lBtn)
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
            elseif f == "Alliance" then
                GuusRaidBuilder_Config.accountFactions[capturedAccF] = "Horde"
            else
                GuusRaidBuilder_Config.accountFactions[capturedAccF] = "Alliance"
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
        badge:SetPoint("RIGHT", row, "RIGHT", -26, 0)
        if count > 0 then
            badge:SetText("[" .. count .. "]")
            badge:SetTextColor(0.3, 1.0, 0.4)
        else
            badge:SetText("[0]")
            badge:SetTextColor(0.45, 0.45, 0.45)
        end

        -- [X] Delete account button
        local capturedAccDel = accName
        local delBtn = CreateFrame("Button", "GRBDelAcc" .. i, row)
        delBtn:SetWidth(18)
        delBtn:SetHeight(ROW_HEIGHT - 6)
        delBtn:SetPoint("RIGHT", row, "RIGHT", -3, 0)
        delBtn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        delBtn:SetBackdropColor(0.30, 0.05, 0.05, 0.9)
        delBtn:SetBackdropBorderColor(0.70, 0.20, 0.20, 0.8)
        local delTxt = delBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        delTxt:SetPoint("CENTER", delBtn, "CENTER", 0, 0)
        delTxt:SetText("X")
        delTxt:SetTextColor(1.0, 0.35, 0.35)
        delBtn:SetScript("OnEnter", function()
            delBtn:SetBackdropColor(0.50, 0.08, 0.08, 0.95)
            GameTooltip:SetOwner(delBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove account", 1, 0.3, 0.3)
            GameTooltip:AddLine("Removes '" .. capturedAccDel .. "' from the account list.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Does NOT delete any slots from presets.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function()
            delBtn:SetBackdropColor(0.30, 0.05, 0.05, 0.9)
            GameTooltip:Hide()
        end)
        delBtn:SetScript("OnClick", function()
            EnsureConfig()
            local accs = GuusRaidBuilder_Config.accounts
            for ai2 = 1, table.getn(accs) do
                if accs[ai2] == capturedAccDel then
                    table.remove(accs, ai2)
                    break
                end
            end
            -- Also remove stored faction/class/classAuto for this account
            if GuusRaidBuilder_Config.accountFactions  then GuusRaidBuilder_Config.accountFactions[capturedAccDel]  = nil end
            if GuusRaidBuilder_Config.accountClasses   then GuusRaidBuilder_Config.accountClasses[capturedAccDel]   = nil end
            if GuusRaidBuilder_Config.accountClassAuto then GuusRaidBuilder_Config.accountClassAuto[capturedAccDel] = nil end
            RefreshLeftPanel()
        end)
        table.insert(GRBLeftRows, delBtn)

        -- Click: add a slot for this account, then jump right panel to their group
        local capturedAcc = accName
        row:SetScript("OnClick", function()
            if not presetName then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Select or create a preset first.")
                return
            end
            local slots = GuusRaidBuilder_Config.presets[presetName].slots
            if GetPresetTotalCount(presetName) >= 40 then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Raid is full (40/40).")
                return
            end
            local count = GetAccountSlotCount(presetName, capturedAcc)
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
    addBtnTxt:SetText("+ Add lvl 60 character")
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
            lbl:SetText("Character name:")
            GRB_AccEdit = CreateFrame("EditBox", "GRBAccEdit", GRB_AccPopupFrame, "InputBoxTemplate")
            GRB_AccEdit:SetWidth(140)
            GRB_AccEdit:SetHeight(20)
            GRB_AccEdit:SetPoint("TOP", GRB_AccPopupFrame, "TOP", 0, -30)
            GRB_AccEdit:SetAutoFocus(true)
            local doAdd = function()
                local name = trim(GRB_AccEdit:GetText())
                if name ~= "" then
                    local lname = string.lower(name)
                    local found = false
                    local accs = GuusRaidBuilder_Config.accounts
                    for ai = 1, table.getn(accs) do
                        if string.lower(accs[ai]) == lname then found = true; break end
                    end
                    if not found then
                        table.insert(accs, name)
                        RefreshLeftPanel()
                    end
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

local GRB_sortKey  = "_spawn" -- "account","tier","class","role","spec","race","gender","_spawn", or nil
local GRB_sortDir  = "asc"   -- "asc" or "desc"

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
    local spawnOrder, slotByToken = SyncSpawnOrder(presetName)
    local tokenToPos = {}
    for pi = 1, table.getn(spawnOrder) do
        tokenToPos[spawnOrder[pi]] = pi
    end
    local yOffset = -4

    -- Column headers (click to sort; click active column again to reverse; third click clears sort)
    local headerRow = CreateFrame("Frame", nil, rightScrollContent)
    headerRow:SetWidth(RIGHT_WIDTH - 22)
    headerRow:SetHeight(18)
    headerRow:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
    headerRow:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
    headerRow:SetBackdropColor(0.07, 0.08, 0.12, 0.95)
    headerRow:SetBackdropBorderColor(0.30, 0.32, 0.40, 0.65)
    local hdrKeys   = { "account", "tier", "class", "role", "spec", "race", "gender" }
    local hdrLabels = { "Account", "Tier", "Class", "Role", "Spec", "Race", "Gender" }
    for h = 1, 7 do
        local key   = hdrKeys[h]
        local label = hdrLabels[h]
        local textPad = (h == 1) and 8 or 1
        local hBtn = CreateFrame("Button", nil, headerRow)
        hBtn:SetWidth(COL_W[h])
        hBtn:SetHeight(18)
        hBtn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", COL_X[h], 0)
        local ht = hBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("LEFT", hBtn, "LEFT", textPad, -1)
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
    -- Spawn-order column header (clickable sort)
    local spawnHdrBtn = CreateFrame("Button", nil, headerRow)
    spawnHdrBtn:SetWidth(70)
    spawnHdrBtn:SetHeight(18)
    spawnHdrBtn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 415, 0)
    local spawnHdrTxt = spawnHdrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spawnHdrTxt:SetPoint("LEFT", spawnHdrBtn, "LEFT", 2, -1)
    local function UpdateSpawnHdr()
        if GRB_sortKey == "_spawn" then
            spawnHdrTxt:SetText("SpawnOrder" .. (GRB_sortDir == "asc" and " ^" or " v"))
            spawnHdrTxt:SetTextColor(1.0, 0.9, 0.35)
        else
            spawnHdrTxt:SetText("SpawnOrder")
            spawnHdrTxt:SetTextColor(0.55, 0.55, 0.65)
        end
    end
    UpdateSpawnHdr()
    spawnHdrBtn:SetScript("OnClick", function()
        if GRB_sortKey == "_spawn" then
            if GRB_sortDir == "asc" then
                GRB_sortDir = "desc"
            else
                GRB_sortKey = nil
                GRB_sortDir = "asc"
            end
        else
            GRB_sortKey = "_spawn"
            GRB_sortDir = "asc"
        end
        RefreshRightPanel()
    end)
    spawnHdrBtn:SetScript("OnEnter", function() spawnHdrTxt:SetTextColor(1.0, 1.0, 0.6) end)
    spawnHdrBtn:SetScript("OnLeave", function() UpdateSpawnHdr() end)
    yOffset = yOffset - 20

    -- Build sorted display order (preserves original slot indices for editing)
    local displayOrder = {}
    for i = 1, table.getn(slots) do
        table.insert(displayOrder, i)
    end
    if GRB_sortKey then
        local sk = GRB_sortKey
        local sd = GRB_sortDir
        if sk == "_spawn" then
            table.sort(displayOrder, function(a, b)
                local ta = "b:" .. (slots[a].uid or 0)
                local tb = "b:" .. (slots[b].uid or 0)
                local pa = tokenToPos[ta] or 9999
                local pb = tokenToPos[tb] or 9999
                if sd == "asc" then return pa < pb else return pa > pb end
            end)
        else
            table.sort(displayOrder, function(a, b)
                local va = string.lower(tostring(slots[a][sk] or ""))
                local vb = string.lower(tostring(slots[b][sk] or ""))
                if sd == "asc" then return va < vb else return va > vb end
            end)
        end
    end

    local legacySlots = GetPresetLegacySlots(presetName)
    local accounts    = GuusRaidBuilder_Config.accounts or {}
    local accToAI     = {}
    for ai = 1, table.getn(accounts) do
        accToAI[accounts[ai]] = ai
    end
    local lastAccount = nil
    local spawnSortActive = (GRB_sortKey == "_spawn")

    if spawnSortActive then
        local playerName  = UnitName("player") or "You"
        local playerClass = GuusRaidBuilder_Config.accountClasses and GuusRaidBuilder_Config.accountClasses[playerName]
        local pcc         = playerClass and GRB_CLASS_COLORS[playerClass] or {0.9, 0.9, 1.0}

        -- Walk spawnOrder, rendering each item in sequence
        local spawnTotal = table.getn(spawnOrder)
        if spawnTotal == 0 and table.getn(displayOrder) > 0 then
            for di = 1, table.getn(displayOrder) do
                local idx = displayOrder[di]
                local slot = slots[idx]
                if slot and slot.uid then
                    table.insert(spawnOrder, "b:" .. slot.uid)
                    slotByToken["b:" .. slot.uid] = slot
                end
            end
            spawnTotal = table.getn(spawnOrder)
        end
        for soi = 1, spawnTotal do
            local token = spawnOrder[soi]
            -- Groups follow the visible order in blocks of 5.
            if soi == 1 then
                local g1Div = CreateFrame("Frame", nil, rightScrollContent)
                g1Div:SetWidth(RIGHT_WIDTH - 22) ; g1Div:SetHeight(15)
                g1Div:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
                g1Div:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
                g1Div:SetBackdropColor(0.05, 0.12, 0.05, 0.97) ; g1Div:SetBackdropBorderColor(0.30, 0.55, 0.30, 0.70)
                local g1Txt = g1Div:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                g1Txt:SetPoint("LEFT", g1Div, "LEFT", 6, 0)
                g1Txt:SetText("Group 1")
                g1Txt:SetTextColor(0.50, 1.0, 0.50)
                table.insert(GRBRightRows, g1Div)
                yOffset = yOffset - 17
            elseif math.mod(soi - 1, 5) == 0 then
                local groupNum = math.floor((soi - 1) / 5) + 1
                local div = CreateFrame("Frame", nil, rightScrollContent)
                div:SetWidth(RIGHT_WIDTH - 22) ; div:SetHeight(15)
                div:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
                div:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
                div:SetBackdropColor(0.05, 0.12, 0.05, 0.97) ; div:SetBackdropBorderColor(0.30, 0.55, 0.30, 0.70)
                local divTxt = div:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                divTxt:SetPoint("LEFT", div, "LEFT", 6, 0)
                divTxt:SetText("Group " .. groupNum .. "  (spawn " .. soi .. "-" .. math.min(soi + 4, spawnTotal) .. ")")
                divTxt:SetTextColor(0.50, 1.0, 0.50)
                table.insert(GRBRightRows, div)
                yOffset = yOffset - 17
            end

            if token == SELF_SPAWN_TOKEN then
                local prow = CreateFrame("Frame", nil, rightScrollContent)
                prow:SetWidth(RIGHT_WIDTH - 22) ; prow:SetHeight(ROW_HEIGHT)
                prow:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
                prow:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
                prow:SetBackdropColor(0.08, 0.08, 0.14, 0.85)
                prow:SetBackdropBorderColor(pcc[1]*0.6, pcc[2]*0.6, pcc[3]*0.6, 0.80)
                table.insert(GRBRightRows, prow)

                local pNameTxt = prow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pNameTxt:SetPoint("LEFT", prow, "LEFT", 8, 0)
                pNameTxt:SetText(playerName .. "  (you)")
                pNameTxt:SetTextColor(pcc[1], pcc[2], pcc[3])

                local pSlotTxt = prow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pSlotTxt:SetPoint("LEFT", prow, "LEFT", 420, 0)
                pSlotTxt:SetText(tostring(soi)) ; pSlotTxt:SetTextColor(1.0, 0.9, 0.35)

                local pupBtn = CreateFrame("Button", nil, prow)
                pupBtn:SetWidth(18) ; pupBtn:SetHeight(ROW_HEIGHT - 2)
                pupBtn:SetPoint("TOPLEFT", prow, "TOPLEFT", 450, -1)
                pupBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
                pupBtn:SetBackdropColor(0.1, 0.1, 0.15, 0.85) ; pupBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.6)
                local pupTxt = pupBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pupTxt:SetPoint("CENTER", pupBtn, "CENTER", 0, 0) ; pupTxt:SetText("^") ; pupTxt:SetTextColor(0.8, 0.8, 1.0)
                pupBtn.presetName = presetName
                pupBtn.spawnToken = SELF_SPAWN_TOKEN
                pupBtn:SetScript("OnClick", GRB_SpawnMoveUp_OnClick)

                local pdnBtn = CreateFrame("Button", nil, prow)
                pdnBtn:SetWidth(18) ; pdnBtn:SetHeight(ROW_HEIGHT - 2)
                pdnBtn:SetPoint("TOPLEFT", prow, "TOPLEFT", 470, -1)
                pdnBtn:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
                pdnBtn:SetBackdropColor(0.1, 0.1, 0.15, 0.85) ; pdnBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.6)
                local pdnTxt = pdnBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pdnTxt:SetPoint("CENTER", pdnBtn, "CENTER", 0, 0) ; pdnTxt:SetText("v") ; pdnTxt:SetTextColor(0.8, 0.8, 1.0)
                pdnBtn.presetName = presetName
                pdnBtn.spawnToken = SELF_SPAWN_TOKEN
                pdnBtn:SetScript("OnClick", GRB_SpawnMoveDown_OnClick)

                yOffset = yOffset - ROW_HEIGHT - 1
            elseif string.sub(token, 1, 2) == "b:" then
                local s = slotByToken[token]
                if s then
                    -- find slot index
                    local si = nil
                    for idx = 1, table.getn(slots) do if slots[idx] == s then si = idx; break end end
                    if si then yOffset = GRB_RenderBotRow(rightScrollContent, yOffset, presetName, slots, s, si, token, soi) end
                end
            elseif string.sub(token, 1, 2) == "l:" then
                local acc2 = string.sub(token, 3)
                local ls2  = legacySlots[acc2]
                local ai2  = accToAI[acc2]
                if ls2 and ls2.charName and ls2.charName ~= "" and ai2 then
                    yOffset = GRB_RenderLegacyRow(rightScrollContent, yOffset, presetName, legacySlots, acc2, ls2, ai2, token, soi)
                end
            end
        end

    elseif GRB_sortKey then
        -- ---- SORTED MODE: bots + legacy interleaved, sorted by key ----
        local combined = {}
        for di = 1, table.getn(displayOrder) do
            table.insert(combined, { kind = "bot", idx = displayOrder[di] })
        end
        for ai = 1, table.getn(accounts) do
            local acc = accounts[ai]
            local ls  = legacySlots[acc]
            if ls and ls.charName and ls.charName ~= "" then
                table.insert(combined, { kind = "legacy", acc = acc, ai = ai })
            end
        end
        local sk = GRB_sortKey
        local sd = GRB_sortDir
        local function getSortVal(item)
            if item.kind == "bot" then
                return string.lower(tostring(slots[item.idx][sk] or ""))
            else
                local ls = legacySlots[item.acc]
                if sk == "class" then
                    local cls = GetAccountClass(item.acc) or ""
                    return string.lower(cls)
                elseif sk == "role"    then return string.lower(ls.role or "")
                elseif sk == "spec"    then return string.lower(ls.spec or "")
                elseif sk == "account" then return string.lower(item.acc or "")
                else return ""
                end
            end
        end
        table.sort(combined, function(a, b)
            local va = getSortVal(a)
            local vb = getSortVal(b)
            if sd == "asc" then return va < vb else return va > vb end
        end)
        for ci = 1, table.getn(combined) do
            local item = combined[ci]
            if item.kind == "bot" then
                local slot = slots[item.idx]
                local spawnToken = "b:" .. (slot.uid or 0)
                local spawnPos   = tokenToPos[spawnToken] or item.idx
                yOffset = GRB_RenderBotRow(rightScrollContent, yOffset, presetName, slots, slot, item.idx, spawnToken, spawnPos)
            else
                local lSpawnToken = "l:" .. item.acc
                local lSpawnPos   = tokenToPos[lSpawnToken] or item.ai
                yOffset = GRB_RenderLegacyRow(rightScrollContent, yOffset, presetName, legacySlots, item.acc, legacySlots[item.acc], item.ai, lSpawnToken, lSpawnPos)
            end
        end

    else
        -- ---- NO SORT: bots grouped by account dividers, legacy at bottom ----
        local totalSlots = table.getn(displayOrder)
        for di = 1, totalSlots do
            local i    = displayOrder[di]
            local slot = slots[i]
            local acc  = slot.account or "?"

            if acc ~= lastAccount then
                GRB_accountTopY[string.lower(acc)] = -yOffset
                local div = CreateFrame("Frame", nil, rightScrollContent)
                div:SetWidth(RIGHT_WIDTH - 22) ; div:SetHeight(15)
                div:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
                div:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2} })
                div:SetBackdropColor(0.07, 0.07, 0.10, 0.97) ; div:SetBackdropBorderColor(0.38, 0.38, 0.48, 0.55)
                local divTxt = div:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                divTxt:SetPoint("LEFT", div, "LEFT", 6, 0)
                divTxt:SetText(acc) ; divTxt:SetTextColor(0.95, 0.88, 0.45)
                table.insert(GRBRightRows, div)
                yOffset = yOffset - 17
                lastAccount = acc
            end

            local spawnToken = "b:" .. (slot.uid or 0)
            local spawnPos   = tokenToPos[spawnToken] or di
            yOffset = GRB_RenderBotRow(rightScrollContent, yOffset, presetName, slots, slot, i, spawnToken, spawnPos)
        end

        -- Legacy rows at bottom (account order)
        for ai = 1, table.getn(accounts) do
            local acc = accounts[ai]
            local ls  = legacySlots[acc]
            if ls and ls.charName and ls.charName ~= "" then
                local lSpawnToken = "l:" .. acc
                local lSpawnPos   = tokenToPos[lSpawnToken] or ai
                yOffset = GRB_RenderLegacyRow(rightScrollContent, yOffset, presetName, legacySlots, acc, ls, ai, lSpawnToken, lSpawnPos)
            end
        end
    end

    -- Add-slot buttons (one per account), laid out in rows
    yOffset = yOffset - 10
    local labelFrame = CreateFrame("Frame", nil, rightScrollContent)
    labelFrame:SetWidth(RIGHT_WIDTH - 22)
    labelFrame:SetHeight(16)
    labelFrame:SetPoint("TOPLEFT", rightScrollContent, "TOPLEFT", 2, yOffset)
    local labelTxt = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelTxt:SetPoint("TOPLEFT", labelFrame, "TOPLEFT", 2, 0)
    labelTxt:SetText("Add slot for:")
    labelTxt:SetTextColor(0.55, 0.55, 0.55)
    table.insert(GRBRightRows, labelFrame)
    yOffset = yOffset - 20

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
        ab.presetName = presetName
        ab.accountName = accName
        ab:SetScript("OnEnter", GRB_AddSlotBtn_OnEnter)
        ab:SetScript("OnLeave", GRB_AddSlotBtn_OnLeave)
        ab:SetScript("OnClick", GRB_AddSlotBtn_OnClick)
        table.insert(GRBRightRows, ab)

        xBtn = xBtn + 94
        if xBtn + 90 > RIGHT_WIDTH - 22 then
            xBtn = 4
            yOffset = yOffset - 24
        end
    end

    yOffset = yOffset - 42

    -- Update scroll content height and scrollbar range
    local totalH = math.max(SCROLL_HEIGHT - 14, -yOffset + 32)
    rightScrollContent:SetHeight(totalH)
    local rsb = getglobal("GRBRightScrollFrameScrollBar")
    if rsb then
        rsb:SetMinMaxValues(0, math.max(0, totalH - (SCROLL_HEIGHT - 14)))
    end
end

-- ============================================================
-- REFRESH ALL
-- ============================================================

RefreshAll = function()
    RefreshPresetButton()
    RefreshExecuteStartButton()
    RefreshSummary()
    RefreshLeftPanel()
    RefreshRightPanel()
end

-- ============================================================
-- PRESET MANAGEMENT
-- ============================================================

local SwitchPreset
local GRB_PresetPickerRows = {}

HidePresetPicker = function()
    if GRB_PresetPickerFrame then GRB_PresetPickerFrame:Hide() end
end

local function BuildPresetPickerList()
    if not GRB_PresetPickerFrame or not GRB_PresetPickerFrame.content then return end

    for i = 1, table.getn(GRB_PresetPickerRows) do
        GRB_PresetPickerRows[i]:Hide()
        GRB_PresetPickerRows[i]:SetParent(nil)
    end
    GRB_PresetPickerRows = {}

    local names = GetPresetNames()
    local count = table.getn(names)
    if count == 0 then return end

    local content = GRB_PresetPickerFrame.content
    local cur     = GuusRaidBuilder_Config.currentPreset
    local rowH    = 20
    local width   = 140
    local maxRows = 12
    local visible = count
    if visible > maxRows then visible = maxRows end
    local listH   = visible * rowH

    content:SetWidth(width)
    content:SetHeight(count * rowH)

    for i = 1, count do
        local presetName = names[i]
        local row = CreateFrame("Button", nil, content)
        row:SetWidth(width)
        row:SetHeight(rowH)
        if i == 1 then
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", GRB_PresetPickerRows[i - 1], "BOTTOMLEFT", 0, 0)
        end
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        if presetName == cur then
            row:SetBackdropColor(0.18, 0.22, 0.12, 0.95)
            row:SetBackdropBorderColor(0.45, 0.65, 0.30, 0.85)
        else
            row:SetBackdropColor(0.10, 0.10, 0.16, 0.92)
            row:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.65)
        end
        local rowLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rowLbl:SetPoint("LEFT", row, "LEFT", 6, 0)
        rowLbl:SetWidth(width - 12)
        rowLbl:SetJustifyH("LEFT")
        rowLbl:SetText(presetName)
        if presetName == cur then
            rowLbl:SetTextColor(1.0, 0.95, 0.55)
        else
            rowLbl:SetTextColor(0.92, 0.92, 0.92)
        end
        row:SetScript("OnEnter", function()
            row:SetBackdropColor(0.20, 0.22, 0.32, 0.95)
            row:SetBackdropBorderColor(0.50, 0.50, 0.65, 0.85)
        end)
        row:SetScript("OnLeave", function()
            if presetName == cur then
                row:SetBackdropColor(0.18, 0.22, 0.12, 0.95)
                row:SetBackdropBorderColor(0.45, 0.65, 0.30, 0.85)
            else
                row:SetBackdropColor(0.10, 0.10, 0.16, 0.92)
                row:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.65)
            end
        end)
        row:SetScript("OnClick", function() SwitchPreset(presetName) end)
        table.insert(GRB_PresetPickerRows, row)
    end

    if count <= maxRows then
        GRB_PresetPickerFrame.scroll:Hide()
        GRB_PresetPickerFrame:SetHeight(listH + 6)
        content:SetParent(GRB_PresetPickerFrame)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", GRB_PresetPickerFrame, "TOPLEFT", 3, -3)
    else
        GRB_PresetPickerFrame.scroll:Show()
        content:SetParent(GRB_PresetPickerFrame.scroll)
        GRB_PresetPickerFrame:SetHeight(maxRows * rowH + 6)
        content:ClearAllPoints()
        GRB_PresetPickerFrame.scroll:SetScrollChild(content)
        GRB_PresetPickerFrame.scroll:SetVerticalScroll(0)
    end
    GRB_PresetPickerFrame:SetWidth(width + 6)
end

TogglePresetPicker = function(anchor)
    local names = GetPresetNames()
    if table.getn(names) == 0 then return end

    if not GRB_PresetPickerFrame then
        GRB_PresetPickerFrame = CreateFrame("Frame", "GRBPresetPickerFrame", mainFrame)
        GRB_PresetPickerFrame:SetFrameStrata("DIALOG")
        GRB_PresetPickerFrame:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        GRB_PresetPickerFrame:SetBackdropColor(0.05, 0.05, 0.10, 0.95)
        GRB_PresetPickerFrame:SetBackdropBorderColor(0.45, 0.45, 0.60, 0.9)
        GRB_PresetPickerFrame:EnableMouse(true)

        GRB_PresetPickerFrame.scroll = CreateFrame("ScrollFrame", "GRBPresetPickerScroll", GRB_PresetPickerFrame)
        GRB_PresetPickerFrame.scroll:SetPoint("TOPLEFT", GRB_PresetPickerFrame, "TOPLEFT", 3, -3)
        GRB_PresetPickerFrame.scroll:SetPoint("BOTTOMRIGHT", GRB_PresetPickerFrame, "BOTTOMRIGHT", -3, 3)
        GRB_PresetPickerFrame.scroll:EnableMouseWheel(true)
        GRB_PresetPickerFrame.scroll:SetScript("OnMouseWheel", function()
            local cur = GRB_PresetPickerFrame.scroll:GetVerticalScroll()
            local step = 20
            if arg1 and arg1 > 0 then
                cur = cur - step
            else
                cur = cur + step
            end
            if cur < 0 then cur = 0 end
            GRB_PresetPickerFrame.scroll:SetVerticalScroll(cur)
        end)

        GRB_PresetPickerFrame.content = CreateFrame("Frame", nil, GRB_PresetPickerFrame.scroll)
    end

    if GRB_PresetPickerFrame:IsVisible() then
        GRB_PresetPickerFrame:Hide()
        return
    end

    BuildPresetPickerList()
    GRB_PresetPickerFrame:ClearAllPoints()
    GRB_PresetPickerFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    GRB_PresetPickerFrame:Show()
end

SwitchPreset = function(name)
    HidePresetPicker()
    GuusRaidBuilder_Config.currentPreset = name
    RefreshAll()
end

local function CreatePreset(name)
    name = trim(name)
    if name == "" then return end
    EnsureConfig()
    if not GuusRaidBuilder_Config.presets[name] then
        GuusRaidBuilder_Config.presets[name] = { slots = {}, legacySlots = {} }
    end
    SwitchPreset(name)
end

local function BuildMainPanels(TOP_Y)
    -- ===== SUMMARY BAR =====
    summaryBar = CreateFrame("Frame", nil, mainFrame)
    summaryBar:SetWidth(WINDOW_WIDTH - 28)
    summaryBar:SetHeight(44)
    summaryBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, TOP_Y - 34)
    summaryBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    summaryBar:SetBackdropColor(0.06, 0.07, 0.11, 0.88)
    summaryBar:SetBackdropBorderColor(0.28, 0.30, 0.40, 0.60)

    summaryNameText = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryNameText:SetPoint("TOPLEFT", summaryBar, "TOPLEFT", 8, -7)
    summaryNameText:SetText("No preset selected")
    summaryNameText:SetTextColor(0.75, 0.75, 0.78)

    summaryText = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("BOTTOMLEFT", summaryBar, "BOTTOMLEFT", 8, 8)
    summaryText:SetText("Create a preset to start building a raid.")
    summaryText:SetTextColor(0.7, 0.7, 0.7)

    summaryBadges = {}
    local badgeDefs = {
        { key = "tank",   label = "T",     value = "0",    color = {1.0, 0.40, 0.40} },
        { key = "healer", label = "H",     value = "0",    color = {0.45, 1.0, 0.45} },
        { key = "rdps",   label = "R",     value = "0",    color = {0.45, 0.70, 1.0} },
        { key = "mdps",   label = "M",     value = "0",    color = {1.0, 0.92, 0.40} },
        { key = "total",  label = "Total", value = "0/40", color = {1.0, 0.95, 0.55} },
    }
    local badgeRight = -8
    for bi = table.getn(badgeDefs), 1, -1 do
        local def = badgeDefs[bi]
        local badge = CreateFrame("Frame", nil, summaryBar)
        badge:SetWidth(def.key == "total" and 72 or 52)
        badge:SetHeight(28)
        badge:SetPoint("RIGHT", summaryBar, "RIGHT", badgeRight, 0)
        badge:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        badge:SetBackdropColor(0.11, 0.12, 0.18, 0.92)
        badge:SetBackdropBorderColor(def.color[1] * 0.55, def.color[2] * 0.55, def.color[3] * 0.55, 0.8)
        badge.key = def.key
        badge.prefix = def.label

        local label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", badge, "TOP", 0, -4)
        label:SetText(def.label)
        label:SetTextColor(def.color[1], def.color[2], def.color[3])
        label:Hide()

        local value = badge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        value:SetPoint("CENTER", badge, "CENTER", 0, 0)
        value:SetText(def.value)
        value:SetTextColor(def.color[1], def.color[2], def.color[3])

        badge.label = label
        badge.value = value
        summaryBadges[def.key] = badge
        badgeRight = badgeRight - badge:GetWidth() - 4
    end

    local sep = mainFrame:CreateTexture(nil, "BACKGROUND")
    sep:SetWidth(WINDOW_WIDTH - 28); sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 13, TOP_Y - 82)
    sep:SetTexture(0.35, 0.35, 0.45, 0.55)

    local PANEL_TOP = TOP_Y - 86

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

    local vSep = mainFrame:CreateTexture(nil, "BACKGROUND")
    vSep:SetWidth(1); vSep:SetHeight(SCROLL_HEIGHT + 20)
    vSep:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", LEFT_WIDTH + 14, PANEL_TOP)
    vSep:SetTexture(0.35, 0.35, 0.45, 0.50)

    rightScrollFrame = CreateFrame("ScrollFrame", "GRBRightScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    rightScrollFrame:SetWidth(RIGHT_WIDTH - 5)
    rightScrollFrame:SetHeight(SCROLL_HEIGHT - 14)
    rightScrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", LEFT_WIDTH + 19, PANEL_TOP - 24)
    rightScrollFrame:EnableMouseWheel(true)
    rightScrollFrame:SetScript("OnMouseWheel", GRB_RightScrollFrame_OnMouseWheel)
    rightScrollContent = CreateFrame("Frame", "GRBRightScrollContent", rightScrollFrame)
    rightScrollContent:SetWidth(RIGHT_WIDTH - 25)
    rightScrollContent:SetHeight(2000)
    rightScrollFrame:SetScrollChild(rightScrollContent)

    local rightHdr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rightHdr:SetPoint("BOTTOMLEFT", rightScrollFrame, "TOPLEFT", 4, 6)
    rightHdr:SetText("Raid Composition")
    rightHdr:SetTextColor(0.92, 0.87, 0.45)

    local transferBtn = CreateFrame("Button", "GRBTransferBtn", mainFrame, "UIPanelButtonTemplate")
    transferBtn:SetWidth(90); transferBtn:SetHeight(22)
    transferBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 14, 12)
    transferBtn:SetText("Transfer")
    transferBtn:SetScript("OnClick", GRB_TransferBtn_OnClick)
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
    mainFrame:SetScript("OnHide", function() HidePresetPicker() end)

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
    closeBtn:SetScript("OnClick", GRB_MainCloseBtn_OnClick)

    -- ===== TOP BAR Y = -32 =====
    local TOP_Y = -32

    local topBar = CreateFrame("Frame", nil, mainFrame)
    topBar:SetWidth(WINDOW_WIDTH - 28)
    topBar:SetHeight(28)
    topBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, TOP_Y + 2)
    topBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    topBar:SetBackdropColor(0.08, 0.09, 0.14, 0.82)
    topBar:SetBackdropBorderColor(0.28, 0.30, 0.40, 0.55)

    local presetGroup = CreateFrame("Frame", nil, topBar)
    presetGroup:SetWidth(330)
    presetGroup:SetHeight(24)
    presetGroup:SetPoint("LEFT", topBar, "LEFT", 6, 0)

    local ioGroup = CreateFrame("Frame", nil, topBar)
    ioGroup:SetWidth(116)
    ioGroup:SetHeight(24)
    ioGroup:SetPoint("LEFT", topBar, "LEFT", 365, 0)

    local actionGroup = CreateFrame("Frame", nil, topBar)
    actionGroup:SetWidth(266)
    actionGroup:SetHeight(24)
    actionGroup:SetPoint("RIGHT", topBar, "RIGHT", -6, 0)

    -- "Preset:" label
    local pLbl = presetGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pLbl:SetPoint("LEFT", presetGroup, "LEFT", 0, 0)
    pLbl:SetText("Preset:")

-- Preset cycle button
    presetCycleBtn = CreateFrame("Button", "GRBPresetCycleBtn", presetGroup)
    
    -- Tell the Preset button to listen for Right Clicks!
    presetCycleBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    presetCycleBtn:SetWidth(100)
    presetCycleBtn:SetHeight(22)
    presetCycleBtn:SetPoint("LEFT", pLbl, "RIGHT", 8, 0)
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
    presetCycleBtn:SetScript("OnEnter", GRB_PresetCycleBtn_OnEnter)
    presetCycleBtn:SetScript("OnLeave", GRB_PresetCycleBtn_OnLeave)
    presetCycleBtn:SetScript("OnClick", GRB_PresetCycleBtn_OnClick)

    presetDropBtn = CreateFrame("Button", "GRBPresetDropBtn", presetGroup)
    presetDropBtn:SetWidth(18)
    presetDropBtn:SetHeight(22)
    presetDropBtn:SetPoint("TOPLEFT", presetCycleBtn, "TOPRIGHT", 1, 0)
    presetDropBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    presetDropBtn:SetBackdropColor(0.12, 0.12, 0.22, 0.9)
    presetDropBtn:SetBackdropBorderColor(0.48, 0.48, 0.70, 0.8)
    local dropLbl = presetDropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropLbl:SetPoint("CENTER", presetDropBtn, "CENTER", 0, 1)
    dropLbl:SetText("v")
    dropLbl:SetTextColor(0.85, 0.85, 1.0)
    presetDropBtn:SetScript("OnEnter", GRB_PresetDropBtn_OnEnter)
    presetDropBtn:SetScript("OnLeave", GRB_PresetDropBtn_OnLeave)
    presetDropBtn:SetScript("OnClick", GRB_PresetDropBtn_OnClick)

    -- [New]
    local newBtn = CreateFrame("Button", nil, presetGroup, "UIPanelButtonTemplate")
    newBtn:SetWidth(42); newBtn:SetHeight(20)
    newBtn:SetPoint("TOPLEFT", presetDropBtn, "TOPRIGHT", 4, 0)
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
    local delBtn = CreateFrame("Button", nil, presetGroup, "UIPanelButtonTemplate")
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

    -- [Rename]
    local renameBtn = CreateFrame("Button", nil, presetGroup, "UIPanelButtonTemplate")
    renameBtn:SetWidth(54); renameBtn:SetHeight(20)
    renameBtn:SetPoint("TOPLEFT", delBtn, "TOPRIGHT", 3, 0)
    renameBtn:SetText("Rename")
    renameBtn:SetScript("OnClick", function()
        local oldName = GuusRaidBuilder_Config.currentPreset
        if not oldName then return end
        if not GRB_RenamePopupFrame then
            GRB_RenamePopupFrame = CreateFrame("Frame", "GRBRenamePopupFrame", mainFrame)
            GRB_RenamePopupFrame:SetWidth(220); GRB_RenamePopupFrame:SetHeight(78)
            GRB_RenamePopupFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 60)
            GRB_RenamePopupFrame:SetFrameStrata("DIALOG")
            GRB_RenamePopupFrame:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 }
            })
            local rl = GRB_RenamePopupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            rl:SetPoint("TOP", GRB_RenamePopupFrame, "TOP", 0, -14)
            rl:SetText("Rename preset to:")
            GRB_RenameEdit = CreateFrame("EditBox", "GRBRenameEdit", GRB_RenamePopupFrame, "InputBoxTemplate")
            GRB_RenameEdit:SetWidth(150); GRB_RenameEdit:SetHeight(20)
            GRB_RenameEdit:SetPoint("TOP", GRB_RenamePopupFrame, "TOP", 0, -30)
            GRB_RenameEdit:SetAutoFocus(true)
            local doRename = function()
                local cur = GuusRaidBuilder_Config.currentPreset
                if not cur then GRB_RenamePopupFrame:Hide(); return end
                local newName = trim(GRB_RenameEdit:GetText())
                if newName == "" or newName == cur then GRB_RenamePopupFrame:Hide(); return end
                EnsureConfig()
                GuusRaidBuilder_Config.presets[newName] = GuusRaidBuilder_Config.presets[cur]
                GuusRaidBuilder_Config.presets[cur] = nil
                GuusRaidBuilder_Config.currentPreset = newName
                GRB_RenamePopupFrame:Hide()
                RefreshAll()
            end
            GRB_RenameEdit:SetScript("OnEnterPressed", doRename)
            GRB_RenameEdit:SetScript("OnEscapePressed", function() GRB_RenamePopupFrame:Hide() end)
            local ok = CreateFrame("Button", nil, GRB_RenamePopupFrame, "UIPanelButtonTemplate")
            ok:SetWidth(58); ok:SetHeight(18)
            ok:SetPoint("BOTTOMRIGHT", GRB_RenamePopupFrame, "BOTTOMRIGHT", -10, 9)
            ok:SetText("Rename")
            ok:SetScript("OnClick", doRename)
            local cancel = CreateFrame("Button", nil, GRB_RenamePopupFrame, "UIPanelButtonTemplate")
            cancel:SetWidth(58); cancel:SetHeight(18)
            cancel:SetPoint("BOTTOMRIGHT", ok, "BOTTOMLEFT", -4, 0)
            cancel:SetText("Cancel")
            cancel:SetScript("OnClick", function() GRB_RenamePopupFrame:Hide() end)
        end
        GRB_RenameEdit:SetText(oldName)
        GRB_RenameEdit:HighlightText()
        GRB_RenamePopupFrame:Show()
        GRB_RenameEdit:SetFocus()
    end)

    -- [Export]
    local exportBtn = CreateFrame("Button", nil, ioGroup, "UIPanelButtonTemplate")
    exportBtn:SetWidth(52); exportBtn:SetHeight(20)
    exportBtn:SetPoint("LEFT", ioGroup, "LEFT", 0, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", GRB_ExportBtn_OnClick)

    -- [Import]
    local importBtn = CreateFrame("Button", nil, ioGroup, "UIPanelButtonTemplate")
    importBtn:SetWidth(52); importBtn:SetHeight(20)
    importBtn:SetPoint("TOPLEFT", exportBtn, "TOPRIGHT", 3, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", GRB_ImportBtn_OnClick)

    -- [Stop] (hidden until executing)
    local stopBtn = CreateFrame("Button", "GRBStopBtn", actionGroup)
    stopBtn:SetWidth(50); stopBtn:SetHeight(26)
    stopBtn:SetPoint("RIGHT", actionGroup, "RIGHT", 0, 0)
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
    stopBtn:SetScript("OnClick", GRB_StopBtn_OnClick)
    stopBtn:Hide()
    GRB_stopButton = stopBtn

    CreateExecuteStartButton(actionGroup, stopBtn)

    -- [Execute Raid] (gold button)
    local execBtn = CreateFrame("Button", "GRBExecBtn", actionGroup)
    execBtn:SetWidth(112); execBtn:SetHeight(26)
    execBtn:SetPoint("TOPRIGHT", executeStartBtn, "TOPLEFT", -3, 0)
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
    execBtn:SetScript("OnEnter", GRB_ExecBtn_OnEnter)
    execBtn:SetScript("OnLeave", GRB_ExecBtn_OnLeave)
    execBtn:SetScript("OnClick", GRB_ExecBtn_OnClick)

    BuildMainPanels(TOP_Y)

    RefreshAll()
    mainFrame:Show()
end

-- ============================================================
-- LEGACY ASSIGN POPUP
-- ============================================================

local GRB_LegacyPopupFrame = nil
local GRB_LegacyPopupAcc   = nil
local GRB_LegacyPopupPreset = nil

local LEGACY_ROLE_COLORS = {
    tank   = { 0.35, 0.08, 0.08, 0.85 },
    healer = { 0.08, 0.28, 0.08, 0.85 },
    rdps   = { 0.08, 0.14, 0.35, 0.85 },
    mdps   = { 0.30, 0.24, 0.04, 0.85 },
}
local LEGACY_ROLE_TEXT_COLORS = {
    tank   = { 1.0, 0.4, 0.4 },
    healer = { 0.4, 1.0, 0.4 },
    rdps   = { 0.4, 0.7, 1.0 },
    mdps   = { 1.0, 0.9, 0.3 },
}
-- All possible specs across all classes
local ALL_SPECS = { "default", "frost", "fire", "arcane", "might", "magic" }

local function GRB_DoAssignLegacy(role, spec)
    local acc    = GRB_LegacyPopupAcc
    local preset = GRB_LegacyPopupPreset
    if not acc or not preset then return end
    -- If user manually picked a class, save it — but do NOT set accountClassAuto,
    -- so the class picker will keep showing on future opens
    if GRB_LegacyPopupFrame and GRB_LegacyPopupFrame.classBtn then
        local selClass = GRB_LegacyPopupFrame.classBtn.lbl:GetText()
        if selClass and selClass ~= "" then
            EnsureConfig()
            GuusRaidBuilder_Config.accountClasses[acc] = selClass
        end
    end
    local ls = GetPresetLegacySlots(preset)
    -- Check if this is a new legacy (not already assigned) and raid is full
    if not (ls[acc] and ls[acc].charName and ls[acc].charName ~= "") then
        if GetPresetTotalCount(preset) >= 40 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000GuusRaidBuilder:|r Raid is full (40/40).")
            if GRB_LegacyPopupFrame then GRB_LegacyPopupFrame:Hide() end
            return
        end
    end
    ls[acc] = { charName = acc, role = role, spec = (spec == "default" and "" or spec) }
    if GRB_LegacyPopupFrame then GRB_LegacyPopupFrame:Hide() end
    RefreshAll()
end

OpenLegacyPicker = function(accountName, presetName)
    GRB_LegacyPopupAcc    = accountName
    GRB_LegacyPopupPreset = presetName

    local savedClass  = GetAccountClass(accountName)
    local isAutoClass = GetAccountClassAuto(accountName)
    local existing    = presetName and GetPresetLegacySlots(presetName)[accountName]

    -- Faction-filtered class list, capitalized for display
    local rawClasses = GetClassesForAccount(accountName)
    local classOptsDisp = {}
    for i = 1, table.getn(rawClasses) do
        local c = rawClasses[i]
        table.insert(classOptsDisp, string.upper(string.sub(c,1,1)) .. string.sub(c,2))
    end

    if not GRB_LegacyPopupFrame then
        GRB_LegacyPopupFrame = CreateFrame("Frame", "GRBLegacyPopupFrame", UIParent)
        GRB_LegacyPopupFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        GRB_LegacyPopupFrame:SetFrameStrata("DIALOG")
        GRB_LegacyPopupFrame:SetMovable(true)
        GRB_LegacyPopupFrame:EnableMouse(true)
        GRB_LegacyPopupFrame:SetScript("OnMouseDown", function() GRB_LegacyPopupFrame:StartMoving() end)
        GRB_LegacyPopupFrame:SetScript("OnMouseUp",   function() GRB_LegacyPopupFrame:StopMovingOrSizing() end)
        GRB_LegacyPopupFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })

        -- Title
        GRB_LegacyPopupFrame.titleTxt = GRB_LegacyPopupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        GRB_LegacyPopupFrame.titleTxt:SetPoint("TOP", GRB_LegacyPopupFrame, "TOP", 0, -13)

        -- "Class:" label (shown only when class is not auto-detected)
        GRB_LegacyPopupFrame.classLbl = GRB_LegacyPopupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        GRB_LegacyPopupFrame.classLbl:SetPoint("TOPLEFT", GRB_LegacyPopupFrame, "TOPLEFT", 16, -36)
        GRB_LegacyPopupFrame.classLbl:SetText("Class:")
        GRB_LegacyPopupFrame.classLbl:SetTextColor(0.75, 0.75, 0.75)

        -- "Role:" label (repositioned each open)
        GRB_LegacyPopupFrame.roleLbl = GRB_LegacyPopupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        GRB_LegacyPopupFrame.roleLbl:SetText("Role:")
        GRB_LegacyPopupFrame.roleLbl:SetTextColor(0.75, 0.75, 0.75)

        -- "Spec:" label (repositioned each open, may be hidden)
        GRB_LegacyPopupFrame.specLbl = GRB_LegacyPopupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        GRB_LegacyPopupFrame.specLbl:SetText("Spec:")
        GRB_LegacyPopupFrame.specLbl:SetTextColor(0.75, 0.75, 0.75)

        -- [Assign] button
        local assignBtn = CreateFrame("Button", nil, GRB_LegacyPopupFrame, "UIPanelButtonTemplate")
        assignBtn:SetWidth(70)
        assignBtn:SetHeight(22)
        assignBtn:SetPoint("BOTTOMRIGHT", GRB_LegacyPopupFrame, "BOTTOMRIGHT", -14, 12)
        assignBtn:SetText("Assign")
        assignBtn:SetScript("OnClick", function()
            local role = GRB_LegacyPopupFrame.roleBtn and GRB_LegacyPopupFrame.roleBtn.lbl:GetText() or "tank"
            local spec = GRB_LegacyPopupFrame.specBtn and GRB_LegacyPopupFrame.specBtn.lbl:GetText() or "default"
            GRB_DoAssignLegacy(role, spec)
        end)

        -- [Clear] button
        local clearBtn = CreateFrame("Button", nil, GRB_LegacyPopupFrame, "UIPanelButtonTemplate")
        clearBtn:SetWidth(60)
        clearBtn:SetHeight(22)
        clearBtn:SetPoint("BOTTOMLEFT", GRB_LegacyPopupFrame, "BOTTOMLEFT", 14, 12)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            local pn = GRB_LegacyPopupPreset
            local ac = GRB_LegacyPopupAcc
            if pn and ac then
                GetPresetLegacySlots(pn)[ac] = nil
                GRB_LegacyPopupFrame:Hide()
                RefreshAll()
            end
        end)

        -- [Close] button
        local closeBtn = CreateFrame("Button", nil, GRB_LegacyPopupFrame, "UIPanelButtonTemplate")
        closeBtn:SetWidth(60)
        closeBtn:SetHeight(22)
        closeBtn:SetPoint("BOTTOM", GRB_LegacyPopupFrame, "BOTTOM", 0, 12)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() GRB_LegacyPopupFrame:Hide() end)
    end

    -- Destroy all dynamic buttons so they are rebuilt fresh each open
    if GRB_LegacyPopupFrame.classBtn then
        GRB_LegacyPopupFrame.classBtn:Hide()
        GRB_LegacyPopupFrame.classBtn:SetParent(nil)
        GRB_LegacyPopupFrame.classBtn = nil
    end
    if GRB_LegacyPopupFrame.roleBtn then
        GRB_LegacyPopupFrame.roleBtn:Hide()
        GRB_LegacyPopupFrame.roleBtn:SetParent(nil)
        GRB_LegacyPopupFrame.roleBtn = nil
    end
    if GRB_LegacyPopupFrame.specBtn then
        GRB_LegacyPopupFrame.specBtn:Hide()
        GRB_LegacyPopupFrame.specBtn:SetParent(nil)
        GRB_LegacyPopupFrame.specBtn = nil
    end

    -- Helper: rebuild role+spec buttons for a given capitalized class name.
    -- roleY/specY offsets depend on whether the class row is visible.
    local function RebuildRoleSpec(dispClass)
        local lcc      = string.lower(dispClass)
        local roleOpts = GetClassRoles(lcc)
        local specOpts = GetSpecs(lcc)
        local hasSpec  = not (table.getn(specOpts) == 1 and specOpts[1] == "default")
        local roleY    = isAutoClass and -32 or -60
        local specY    = isAutoClass and -60 or -88

        if GRB_LegacyPopupFrame.roleBtn then
            GRB_LegacyPopupFrame.roleBtn:Hide()
            GRB_LegacyPopupFrame.roleBtn:SetParent(nil)
            GRB_LegacyPopupFrame.roleBtn = nil
        end
        if GRB_LegacyPopupFrame.specBtn then
            GRB_LegacyPopupFrame.specBtn:Hide()
            GRB_LegacyPopupFrame.specBtn:SetParent(nil)
            GRB_LegacyPopupFrame.specBtn = nil
        end

        -- Role label + button
        GRB_LegacyPopupFrame.roleLbl:SetPoint("TOPLEFT", GRB_LegacyPopupFrame, "TOPLEFT", 16, roleY + 4)
        GRB_LegacyPopupFrame.roleLbl:Show()

        local initRole = (existing and existing.role) or roleOpts[1]
        local roleOk   = false
        for i = 1, table.getn(roleOpts) do if roleOpts[i] == initRole then roleOk = true end end
        if not roleOk then initRole = roleOpts[1] end

        GRB_LegacyPopupFrame.roleBtn = MakeCycleBtn(GRB_LegacyPopupFrame, nil, 62, 22, roleOpts, initRole, nil, "Role")
        GRB_LegacyPopupFrame.roleBtn:SetPoint("TOPLEFT", GRB_LegacyPopupFrame, "TOPLEFT", 52, roleY)
        local function UpdateRoleColor()
            local r = GRB_LegacyPopupFrame.roleBtn.lbl:GetText() or roleOpts[1]
            local c = LEGACY_ROLE_TEXT_COLORS[r] or {1,1,1}
            GRB_LegacyPopupFrame.roleBtn.lbl:SetTextColor(c[1], c[2], c[3])
        end
        UpdateRoleColor()
        GRB_LegacyPopupFrame.roleBtn:SetScript("OnClick", function(_, button)
            local cur = GRB_LegacyPopupFrame.roleBtn.lbl:GetText()
            local newVal = (button == "RightButton")
                and cyclePrev(roleOpts, cur)
                or  cycleNext(roleOpts, cur)
            GRB_LegacyPopupFrame.roleBtn.lbl:SetText(newVal)
            UpdateRoleColor()
        end)

        -- Spec label + button
        if hasSpec then
            GRB_LegacyPopupFrame.specLbl:SetPoint("TOPLEFT", GRB_LegacyPopupFrame, "TOPLEFT", 16, specY + 4)
            GRB_LegacyPopupFrame.specLbl:Show()
            local initSpec = (existing and existing.spec ~= "" and existing.spec) or specOpts[1]
            local specOk   = false
            for i = 1, table.getn(specOpts) do if specOpts[i] == initSpec then specOk = true end end
            if not specOk then initSpec = specOpts[1] end
            GRB_LegacyPopupFrame.specBtn = MakeCycleBtn(GRB_LegacyPopupFrame, nil, 80, 22, specOpts, initSpec, nil, "Spec")
            GRB_LegacyPopupFrame.specBtn:SetPoint("TOPLEFT", GRB_LegacyPopupFrame, "TOPLEFT", 52, specY)
            GRB_LegacyPopupFrame:SetHeight(isAutoClass and 155 or 185)
        else
            GRB_LegacyPopupFrame.specLbl:Hide()
            GRB_LegacyPopupFrame:SetHeight(isAutoClass and 125 or 155)
        end
    end

    -- Determine starting class and build the popup
    local currentDispClass
    if isAutoClass then
        -- Class was auto-detected on login — never show class picker
        GRB_LegacyPopupFrame.classLbl:Hide()
        currentDispClass = savedClass or "Warrior"
        RebuildRoleSpec(currentDispClass)
    else
        -- Class unknown or manually set — always show class picker
        GRB_LegacyPopupFrame.classLbl:Show()

        local initClass = savedClass or classOptsDisp[1]
        local classOk   = false
        for i = 1, table.getn(classOptsDisp) do
            if classOptsDisp[i] == initClass then classOk = true end
        end
        if not classOk then initClass = classOptsDisp[1] end

        GRB_LegacyPopupFrame.classBtn = MakeCycleBtn(GRB_LegacyPopupFrame, nil, 80, 22, classOptsDisp, initClass, nil, "Class")
        GRB_LegacyPopupFrame.classBtn:SetPoint("TOPLEFT", GRB_LegacyPopupFrame, "TOPLEFT", 52, -32)

        local function UpdateClassDisplay()
            local cls  = GRB_LegacyPopupFrame.classBtn.lbl:GetText()
            local cc2  = GRB_CLASS_COLORS[cls] or {1,1,1}
            GRB_LegacyPopupFrame.classBtn.lbl:SetTextColor(cc2[1], cc2[2], cc2[3])
            GRB_LegacyPopupFrame.titleTxt:SetText("|cff" .. string.format("%02x%02x%02x",
                cc2[1]*255, cc2[2]*255, cc2[3]*255) .. accountName .. "|r  legacy")
            RebuildRoleSpec(cls)
        end
        GRB_LegacyPopupFrame.classBtn:SetScript("OnClick", function(_, button)
            local cur = GRB_LegacyPopupFrame.classBtn.lbl:GetText()
            local newVal = (button == "RightButton")
                and cyclePrev(classOptsDisp, cur)
                or  cycleNext(classOptsDisp, cur)
            GRB_LegacyPopupFrame.classBtn.lbl:SetText(newVal)
            UpdateClassDisplay()
        end)
        UpdateClassDisplay()  -- set initial colors and build role/spec for initClass
        currentDispClass = initClass
    end

    -- Title (for auto-class path; manual path already set it in UpdateClassDisplay)
    if isAutoClass then
        local cc = GRB_CLASS_COLORS[currentDispClass] or {1, 1, 1}
        GRB_LegacyPopupFrame.titleTxt:SetText("|cff" .. string.format("%02x%02x%02x",
            cc[1]*255, cc[2]*255, cc[3]*255) .. accountName .. "|r  legacy")
    end
    GRB_LegacyPopupFrame:SetWidth(280)
    GRB_LegacyPopupFrame:Show()
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
    -- Save/update faction and class for this account name
    if faction and faction ~= "" then
        GuusRaidBuilder_Config.accountFactions[name] = faction
    end
    local class = UnitClass("player")
    local classUpdated = false
    if class and class ~= "" then
        GuusRaidBuilder_Config.accountClasses[name] = class
        GuusRaidBuilder_Config.accountClassAuto[name] = true
        classUpdated = true
    end
    local accounts = GuusRaidBuilder_Config.accounts
    -- Check if already in list (case-insensitive)
    local lname = string.lower(name)
    for i = 1, table.getn(accounts) do
        if string.lower(accounts[i]) == lname then
            -- Normalise stored name to the real capitalised UnitName so keys always match
            if accounts[i] ~= name then accounts[i] = name end
            -- Refresh left panel so name colour updates immediately if window is open
            if classUpdated and leftScrollContent then RefreshLeftPanel() end
            return true
        end
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
