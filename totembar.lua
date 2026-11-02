-- pfUI-TotemBar
-- A pfUI third-party module for shamans:
--   * one button per element showing the "active" totem of that element
--   * hover a button to open the list of every totem known for that element
--       left-click  -> cast that totem
--       right-click -> make it the active totem of its element
--   * left-click an element button to cast its active totem
--   * /totembar all  -> casts every active totem in a row (uses Nampower's queue)

-- global API (usable from macros, /run and key bindings)
pfTotemBar = pfTotemBar or {}

BINDING_HEADER_PFTOTEMBAR = "pfUI Totem Bar"
BINDING_NAME_PFTOTEMBAR_ALL = "Cast all active totems"
BINDING_NAME_PFTOTEMBAR_EARTH = "Cast active Earth totem"
BINDING_NAME_PFTOTEMBAR_FIRE = "Cast active Fire totem"
BINDING_NAME_PFTOTEMBAR_WATER = "Cast active Water totem"
BINDING_NAME_PFTOTEMBAR_AIR = "Cast active Air totem"
BINDING_NAME_PFTOTEMBAR_SHIELD = "Cast active shield"
BINDING_NAME_PFTOTEMBAR_TOTEMS = "Cast the 4 active totems (no shield)"

pfUI:RegisterModule("totembar", "vanilla", function()
  local _, class = UnitClass("player")

  -- [[ default configuration ]] --
  local defaults = {
    enable     = "1",
    earth      = "", fire = "", water = "", air = "",   -- active totem per element (spell name)
    all_earth  = "1", all_fire = "1", all_water = "1", all_air = "1",
    order      = "earth,fire,water,air",               -- cast-all order (and bar order)
    skipactive = "1",                                  -- cast-all skips totems already down
    skipremain = "0",                                  -- ...unless less than X seconds left
    rangecheck = "1",                                  -- recast totems you are out of range of (UnitXP)
    shield     = "",                                   -- active shield (spell name)
    all_shield = "0",                                  -- include the shield in cast-all
    shieldcharges = "0",                               -- recast the shield at X charges or less (0 = only when gone)
    showshield = "1",                                  -- show the shield button on the bar
    size       = "30",
    spacing    = "2",
    direction  = "HORIZONTAL",
    flyout     = "TOP",
    hover      = "1",
    timer      = "1",
    showbg     = "1",
  }
  for key, value in pairs(defaults) do
    pfUI:UpdateConfig("totembar", nil, key, value)
  end

  -- v1.1: cast-all only refreshes missing totems by default
  if not C.totembar.migrated_skip then
    C.totembar.skipactive = "1"
    C.totembar.skipremain = "0"
    C.totembar.migrated_skip = "1"
  end

  if class ~= "SHAMAN" then
    _G.pfTotemBar.CastAll = function() end
    _G.pfTotemBar.Cast = function() end
    _G.pfTotemBar.CastShield = function() end
    _G.pfTotemBar.CastTotems = function() end
    return
  end

  local cfg = C.totembar
  local PREFIX = "|cff33ffccpf|rTotemBar: "
  local hasNampower = QueueSpellByName and true or nil

  local ELEMENTS = { "earth", "fire", "water", "air" }              -- totem elements
  local GROUPS = { "earth", "fire", "water", "air", "shield" }     -- everything on the bar
  local VALID = { earth = true, fire = true, water = true, air = true, shield = true }
  local SLOT = { fire = 1, earth = 2, water = 3, air = 4 }         -- same ids as pfUI's libtotem
  local SLOT2EL = { [1] = "fire", [2] = "earth", [3] = "water", [4] = "air" }
  local LABEL = { earth = T["Earth"], fire = T["Fire"], water = T["Water"], air = T["Air"], shield = T["Shield"] }
  local COLOR = {
    earth = { .45, .75, .2 },
    fire  = { .95, .4, .1 },
    water = { .2, .6, 1 },
    air   = { .7, .45, 1 },
    shield = { .9, .8, .2 },
  }

  -- shaman shields: icon or name (en/fr/de), checked before the totem tables
  local SHIELD_TEXTURES = {
    ["spell_nature_lightningshield"] = true,   -- Lightning Shield
    ["ability_shaman_watershield"] = true,     -- Water Shield
    ["spell_nature_skinofearth"] = true,       -- Earth Shield
  }
  local SHIELD_NAMES = {
    ["lightning shield"] = true, ["water shield"] = true, ["earth shield"] = true,
    ["bouclier de foudre"] = true, ["bouclier d'eau"] = true, ["bouclier de terre"] = true,
    ["blitzschlagschild"] = true, ["wasserschild"] = true, ["erdschild"] = true,
  }

  -- icon -> totem slot (locale independent, same data pfUI's libtotem uses)
  local TEXTURES = {
    ["spell_fire_sealoffire"] = 1,                -- Fire Nova
    ["spell_nature_guardianward"] = 1,            -- Flametongue
    ["spell_frostresistancetotem_01"] = 1,        -- Frost Resistance
    ["spell_fire_selfdestruct"] = 1,              -- Magma
    ["spell_fire_searingtotem"] = 1,              -- Searing
    ["spell_nature_strengthofearthtotem02"] = 2,  -- Earthbind
    ["spell_nature_stoneclawtotem"] = 2,          -- Stoneclaw
    ["spell_nature_stoneskintotem"] = 2,          -- Stoneskin
    ["spell_nature_earthbindtotem"] = 2,          -- Strength of Earth
    ["spell_nature_tremortotem"] = 2,             -- Tremor
    ["spell_nature_diseasecleansingtotem"] = 3,   -- Disease Cleansing
    ["spell_fireresistancetotem_01"] = 3,         -- Fire Resistance
    ["inv_spear_04"] = 3,                         -- Healing Stream
    ["spell_nature_manaregentotem"] = 3,          -- Mana Spring
    ["spell_frost_summonwaterelemental"] = 3,     -- Mana Tide
    ["spell_nature_poisoncleansingtotem"] = 3,    -- Poison Cleansing
    ["spell_nature_invisibilitytotem"] = 4,       -- Grace of Air
    ["spell_nature_groundingtotem"] = 4,          -- Grounding
    ["spell_nature_natureresistancetotem"] = 4,   -- Nature Resistance
    ["spell_nature_brilliance"] = 4,              -- Tranquil Air
    ["spell_nature_windfury"] = 4,                -- Windfury
    ["spell_nature_earthbind"] = 4,               -- Windwall
    ["spell_nature_removecurse"] = 4,             -- Sentry
  }

  -- SPELL_EFFECT_SUMMON_TOTEM_SLOT1..4 -> totem slot (fallback for custom/unknown totems, needs Nampower)
  local TOTEM_EFFECTS = { [87] = 1, [88] = 2, [89] = 3, [90] = 4 }

  -- "none" choice for an element: nothing is cast for it
  local NONE = "none"
  local NONE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- red cross
  local NONE_TEXT = "|T" .. NONE_ICON .. "|t |cffff5555" .. T["None"] .. "|r"   -- no ":" (dropdown splits on it)

  local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  end

  -- [[ spellbook scan ]] --
  local known = { earth = {}, fire = {}, water = {}, air = {}, shield = {} }
  local byname = {}
  local effectCache = {}

  local function ShortTexture(tex)
    if not tex then return "" end
    local _, _, short = string.find(tex, "([^\\]+)$")
    return string.lower(short or tex)
  end

  -- Nampower: the totem slot from the spell's own data (summon totem effect)
  -- returns the slot, false when the spell is not a totem, nil when unknown
  local function SlotByEffect(name)
    if not GetSpellIdForName or not GetSpellRecField then return nil end
    local okId, id = pcall(GetSpellIdForName, name)
    if not okId or not id or id == 0 then return nil end
    local ok, effects = pcall(GetSpellRecField, id, "effect")
    if not ok or type(effects) ~= "table" then return nil end
    for _, effect in pairs(effects) do
      if TOTEM_EFFECTS[effect] then return TOTEM_EFFECTS[effect] end
    end
    return false
  end

  local ScanRange
  -- [[ totem ranges ]] --
  -- read "within X yards" from the spell tooltip, fall back to this table
  -- (0 = never treat as out of range)
  local RANGE_FALLBACK = {
    ["spell_nature_stoneclawtotem"] = 0,   -- Stoneclaw: taunt, no aura
    ["spell_nature_groundingtotem"] = 0,   -- Grounding
    ["spell_nature_removecurse"] = 0,      -- Sentry
    ["spell_nature_tremortotem"] = 30,
    ["spell_fire_selfdestruct"] = 8,       -- Magma
    ["spell_fire_sealoffire"] = 10,        -- Fire Nova
    ["spell_nature_strengthofearthtotem02"] = 10, -- Earthbind
  }
  local DEFAULT_RANGE = 20

  local scanner = CreateFrame("GameTooltip", "pfTotemBarScanner", nil, "GameTooltipTemplate")
  scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

  function ScanRange(index, tex)
    local key = ShortTexture(tex)
    if RANGE_FALLBACK[key] then return RANGE_FALLBACK[key] end

    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:ClearLines()
    scanner:SetSpell(index, BOOKTYPE_SPELL)
    for line = 2, (scanner:NumLines() or 0) do
      local left = _G["pfTotemBarScannerTextLeft" .. line]
      local text = left and left:GetText()
      if text then
        local _, _, yards = string.find(text, "(%d+) ?[yY]a?r?d")
        if not yards then _, _, yards = string.find(text, "(%d+) ?m[eè]tres") end
        if yards then return tonumber(yards) end
      end
    end
    return DEFAULT_RANGE
  end

  local function Scan()
    for _, el in pairs(GROUPS) do known[el] = {} end
    byname = {}

    -- spellbook indexes in Mounts / Companions / Toys tabs (for the icon fallback)
    local collection = {}
    if GetNumSpellTabs and GetSpellTabInfo then
      for tab = 1, GetNumSpellTabs() or 0 do
        local tabname, _, offset, count = GetSpellTabInfo(tab)
        local lname = string.lower(tabname or "")
        if offset and count and (string.find(lname, "mount") or string.find(lname, "companion")
          or string.find(lname, "toy") or string.find(lname, "monture") or string.find(lname, "compagnon")
          or string.find(lname, "jouet") or string.find(lname, "reittier") or string.find(lname, "haustier")
          or string.find(lname, "spielzeug")) then
          for idx = offset + 1, offset + count do collection[idx] = true end
        end
      end
    end

    local i = 1
    while true do
      local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
      if not name then break end

      local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
      local el
      if SHIELD_TEXTURES[ShortTexture(tex)] or SHIELD_NAMES[string.lower(name)] then
        el = "shield"
      else
        -- spell data first (companions and toys can reuse totem icons),
        -- the icon table only when the spell data can't be read
        if effectCache[name] == nil then
          local bySpell = SlotByEffect(name)
          if bySpell ~= nil then effectCache[name] = bySpell end
        end
        local slot = effectCache[name]
        if slot == nil and not collection[i] then slot = TEXTURES[ShortTexture(tex)] end
        el = slot and SLOT2EL[slot]
      end

      if el then
        local entry = byname[name]
        if not entry then
          entry = { name = name, element = el }
          byname[name] = entry
          table.insert(known[el], entry)
        end
        -- spellbook lists ranks in ascending order: the last one wins
        entry.index, entry.rank, entry.icon = i, rank, tex
        if el ~= "shield" then entry.range = ScanRange(i, tex) end
      end

      i = i + 1
    end

    -- pick a sensible default the first time
    for _, el in pairs(GROUPS) do
      if (cfg[el] == nil or cfg[el] == "") and known[el][1] then
        cfg[el] = known[el][1].name
      end
    end
  end

  local function GetActive(el)
    local list = known[el]
    if not list or not list[1] then return nil end
    local want = cfg[el]
    if want == NONE then return nil end
    if want and byname[want] and byname[want].element == el then
      return byname[want]
    end
    return list[1]
  end

  local function SpellString(entry)
    if entry.rank and entry.rank ~= "" then
      return entry.name .. "(" .. entry.rank .. ")"
    end
    return entry.name
  end

  local function Cast(entry)
    if not entry then return end
    if entry.element == "shield" then
      CastSpellByName(SpellString(entry), 1)   -- shields always on yourself
    else
      CastSpellByName(SpellString(entry))
    end
  end

  local function ParseOrder()
    local order, seen = {}, {}
    for el in string.gfind(string.lower(cfg.order or ""), "%a+") do
      if VALID[el] and not seen[el] then
        table.insert(order, el)
        seen[el] = true
      end
    end
    for _, el in pairs(GROUPS) do
      if not seen[el] then table.insert(order, el) end
    end
    return order
  end

  -- [[ totem state ]] --
  -- GUID of each of our totems. Candidates come from the combat log (totems
  -- are the source of their own buff/heal/mana/damage ticks), target,
  -- mouseover and nameplates; ClassicAPI's UnitOwnerGUID / UnitCreatedBySpell
  -- confirm it is ours and tell which slot it belongs to.
  local totemGUID = {}
  local notMine, notMineCount = {}, 0
  local playerGUID

  local function SameGUID(a, b)
    return a and b and string.upper(a) == string.upper(b)
  end

  local function LearnGUID(guid)
    if not guid or guid == "" or notMine[guid] then return end
    if not UnitOwnerGUID or not UnitCreatedBySpell or not GetTotemInfo then return end
    for _, known in pairs(totemGUID) do
      if known == guid then return end
    end

    playerGUID = playerGUID or UnitGUID("player")
    local okOwner, owner = pcall(UnitOwnerGUID, guid)
    if not okOwner or not SameGUID(owner, playerGUID) then
      -- remember strangers so busy raid combat logs stay cheap
      if notMineCount > 2000 then notMine, notMineCount = {}, 0 end
      notMine[guid] = true
      notMineCount = notMineCount + 1
      return
    end

    local okSpell, spellId = pcall(UnitCreatedBySpell, guid)
    if not okSpell or not spellId then return end
    for slot = 1, 4 do
      local _, _, start, _, _, _, sid = GetTotemInfo(slot)
      if start and start > 0 and sid == spellId then
        totemGUID[SLOT2EL[slot]] = guid
        return
      end
    end
  end

  local function LearnUnit(unit)
    if UnitExists(unit) then LearnGUID(UnitGUID(unit)) end
  end

  -- returns start, duration when the active totem of the element is the one down
  local function ActiveTotemDown(entry)
    if not GetTotemInfo then return nil end
    local _, name, start, duration, icon = GetTotemInfo(SLOT[entry.element])
    if not start or start <= 0 then return nil end
    local same = (icon and icon ~= "" and entry.icon and string.lower(icon) == string.lower(entry.icon))
      or (name and string.find(name, entry.name, 1, true) == 1)
    if not same then return nil end
    return start, duration or 0
  end

  -- nil = in range or unknown, otherwise the distance
  local function OutOfRange(entry)
    if cfg.rangecheck ~= "1" or not UnitXP then return nil end
    local guid = totemGUID[entry.element]
    local range = entry.range or DEFAULT_RANGE
    if not guid or range <= 0 then return nil end
    local ok, dist = pcall(UnitXP, "distanceBetween", "player", guid, "AoE")
    if ok and dist and dist > range then return dist end
    return nil
  end

  -- [[ shield ]] --
  -- charges of the shield on you, nil when it is not up
  local function ShieldCharges(entry)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
      local ok, d = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", entry.name, "HELPFUL")
      if ok then return d and (d.applications or 1) or nil end
    end
    local tex = entry.icon and string.lower(entry.icon)
    for i = 1, 32 do
      local icon, apps = UnitBuff("player", i)
      if not icon then break end
      if string.lower(icon) == tex then return apps or 1 end
    end
    return nil
  end

  -- [[ cast all ]] --
  local function ShouldSkip(entry)
    if entry.element == "shield" then
      local charges = ShieldCharges(entry)
      return charges and charges > (tonumber(cfg.shieldcharges) or 0)
    end
    if cfg.skipactive ~= "1" then return nil end
    local start, duration = ActiveTotemDown(entry)
    -- missing, or another totem of this element is down: cast the active one
    if not start then return nil end
    if OutOfRange(entry) then return nil end
    local remain = start + duration - GetTime()
    return remain > (tonumber(cfg.skipremain) or 0)
  end

  -- totemsOnly: the 4 totems (ignores the cast-all include boxes), no shield
  local function BuildCastList(totemsOnly, force)
    local list = {}
    for _, el in pairs(ParseOrder()) do
      local wanted
      if totemsOnly then wanted = SLOT[el] else wanted = cfg["all_" .. el] == "1" end
      if wanted then
        local entry = GetActive(el)
        if entry and (force or not ShouldSkip(entry)) then
          table.insert(list, entry)
        end
      end
    end
    return list
  end

  local function CastList(list)
    for i = 1, table.getn(list) do
      Cast(list[i])
    end
  end

  -- the 4 totems that need a refresh (force = all 4), never the shield
  local function CastTotems(force)
    CastList(BuildCastList(true, force))
  end

  local function CastAll()
    local list = BuildCastList()
    -- same as a macro with one /cast line per totem
    for i = 1, table.getn(list) do
      Cast(list[i])
    end
  end

  -- [[ the bar ]] --
  local bar = CreateFrame("Frame", "pfTotemBar", UIParent)
  bar.buttons = {}

  local function DefaultBorder(button)
    button:SetBackdropBorderColor(GetStringColor(pfUI_config.appearance.border.color))
  end

  local function ShowNoneTooltip(button, el, main)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["None"], 1, .33, .33)
    GameTooltip:AddLine(main and ("No " .. LABEL[el] .. " is cast. Pick one in the list.")
      or ("Right-click: cast no " .. LABEL[el]), 1, 1, 1)
    GameTooltip:Show()
  end

  local function ShowTooltip(button, entry, main)
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetSpell(entry.index, BOOKTYPE_SPELL)
    GameTooltip:AddLine(" ")
    if main then
      GameTooltip:AddDoubleLine("Left-click", "Cast " .. entry.name, 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Right-click", "Pin the " .. LABEL[entry.element] .. " list", 1, 1, 1, .2, 1, .8)
    else
      GameTooltip:AddDoubleLine("Left-click", "Cast", 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Right-click", "Set as active " .. LABEL[entry.element], 1, 1, 1, .2, 1, .8)
    end
    GameTooltip:Show()
  end

  local function CreateTotemButton(name, parent)
    local b = CreateFrame("Button", name, parent)
    b:SetWidth(30)
    b:SetHeight(30)
    CreateBackdrop(b, nil, true)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(.08, .92, .08, .92)
    SetAllPointsOffset(b.icon, b, 2)

    b.hl = b:CreateTexture(nil, "OVERLAY")
    b.hl:SetAllPoints(b.icon)
    b.hl:SetTexture(1, 1, 1, .2)
    b.hl:Hide()

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
  end

  local function SetActive(el, name)
    if name ~= NONE and (not byname[name] or byname[name].element ~= el) then return end
    cfg[el] = name
    bar:Refresh()
  end

  -- flyout buttons
  local function FlyOnClick()
    if this.none then
      if arg1 == "RightButton" then
        SetActive(this.none, NONE)
        ShowNoneTooltip(this, this.none)
      end
      return
    end
    if not this.entry then return end
    if arg1 == "RightButton" then
      SetActive(this.entry.element, this.entry.name)
      ShowTooltip(this, this.entry)
    else
      Cast(this.entry)
    end
  end

  local function FlyOnEnter()
    this.hl:Show()
    if this.none then ShowNoneTooltip(this, this.none) else ShowTooltip(this, this.entry) end
  end

  local function FlyOnLeave()
    this.hl:Hide()
    GameTooltip:Hide()
  end

  local function FlyoutOnUpdate()
    if this.pinned then return end
    if MouseIsOver(this) or MouseIsOver(this.owner) then
      this.leave = nil
    else
      this.leave = this.leave or GetTime()
      if GetTime() - this.leave > .3 then this:Hide() end
    end
  end

  -- element buttons
  local function MainOnClick()
    if arg1 == "RightButton" then
      local fly = this.fly
      if fly:IsShown() and fly.pinned then
        fly.pinned = nil
        fly:Hide()
      else
        fly.pinned = true
        fly.leave = nil
        fly:Show()
      end
    else
      Cast(GetActive(this.element))
    end
  end

  local function MainOnEnter()
    this.hl:Show()
    if cfg.hover == "1" then
      this.fly.leave = nil
      this.fly:Show()
    end
    local entry = GetActive(this.element)
    if entry then ShowTooltip(this, entry, true) else ShowNoneTooltip(this, this.element, true) end
  end

  local function MainOnLeave()
    this.hl:Hide()
    GameTooltip:Hide()
  end

  for _, el in pairs(GROUPS) do
    local b = CreateTotemButton("pfTotemBar" .. el, bar)
    b.element = el

    b.cdbg = CreateFrame("Frame", nil, b)
    b.cdbg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.cd = CreateFrame(COOLDOWN_FRAME_TYPE or "Model", "pfTotemBar" .. el .. "Cooldown", b.cdbg, "CooldownFrameTemplate")
    b.cd.pfCooldownType = "ALL"

    b.textframe = CreateFrame("Frame", nil, b)
    b.textframe:SetAllPoints(b)
    b.textframe:SetFrameLevel(b:GetFrameLevel() + 4)
    b.timer = b.textframe:CreateFontString(nil, "OVERLAY")
    b.timer:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    b.timer:SetPoint("BOTTOM", b, "BOTTOM", 0, 3)

    b:SetScript("OnClick", MainOnClick)
    b:SetScript("OnEnter", MainOnEnter)
    b:SetScript("OnLeave", MainOnLeave)

    b.fly = CreateFrame("Frame", nil, b)
    b.fly.owner = b
    b.fly.buttons = {}
    b.fly:SetFrameStrata("DIALOG")
    b.fly:SetScript("OnUpdate", FlyoutOnUpdate)
    b.fly:Hide()

    bar.buttons[el] = b
  end

  function bar:BuildFlyout(el)
    local b = self.buttons[el]
    local fly, active = b.fly, GetActive(el)
    local list = {}
    for _, entry in pairs(known[el]) do table.insert(list, entry) end
    table.insert(list, NONE)
    local size, spacing, dir = self.size, self.spacing, cfg.flyout
    local count = table.getn(list)
    local step = size + spacing

    for i = 1, count do
      local f = fly.buttons[i]
      if not f then
        f = CreateTotemButton(nil, fly)
        f:SetScript("OnClick", FlyOnClick)
        f:SetScript("OnEnter", FlyOnEnter)
        f:SetScript("OnLeave", FlyOnLeave)
        fly.buttons[i] = f
      end

      local isNone = list[i] == NONE
      f.entry = (not isNone) and list[i] or nil
      f.none = isNone and el or nil
      f:SetWidth(size)
      f:SetHeight(size)
      f:ClearAllPoints()
      if dir == "BOTTOM" then
        f:SetPoint("TOP", fly, "TOP", 0, -(i - 1) * step)
      elseif dir == "LEFT" then
        f:SetPoint("RIGHT", fly, "RIGHT", -(i - 1) * step, 0)
      elseif dir == "RIGHT" then
        f:SetPoint("LEFT", fly, "LEFT", (i - 1) * step, 0)
      else
        f:SetPoint("BOTTOM", fly, "BOTTOM", 0, (i - 1) * step)
      end

      f.icon:SetTexture(isNone and NONE_ICON or list[i].icon)
      if (isNone and not active) or (not isNone and list[i] == active) then
        f:SetBackdropBorderColor(COLOR[el][1], COLOR[el][2], COLOR[el][3], 1)
      else
        DefaultBorder(f)
      end
      f:Show()
    end

    for i = count + 1, table.getn(fly.buttons) do
      fly.buttons[i]:Hide()
    end

    local length = math.max(count * size + (count - 1) * spacing, 1)
    fly:ClearAllPoints()
    if dir == "BOTTOM" then
      fly:SetPoint("TOP", b, "BOTTOM", 0, -spacing)
      fly:SetWidth(size) fly:SetHeight(length)
    elseif dir == "LEFT" then
      fly:SetPoint("RIGHT", b, "LEFT", -spacing, 0)
      fly:SetWidth(length) fly:SetHeight(size)
    elseif dir == "RIGHT" then
      fly:SetPoint("LEFT", b, "RIGHT", spacing, 0)
      fly:SetWidth(length) fly:SetHeight(size)
    else
      fly:SetPoint("BOTTOM", b, "TOP", 0, spacing)
      fly:SetWidth(size) fly:SetHeight(length)
    end
  end

  function bar:Refresh()
    for _, el in pairs(GROUPS) do
      local b = self.buttons[el]
      local entry = GetActive(el)
      if known[el][1] then
        b.cdstart, b.cdduration = nil, nil
        if entry then
          b.icon:SetTexture(entry.icon)
          b:SetBackdropBorderColor(COLOR[el][1], COLOR[el][2], COLOR[el][3], 1)
        else
          b.icon:SetTexture(NONE_ICON)
          b.icon:SetVertexColor(1, 1, 1)
          b.timer:SetText("")
          CooldownFrame_SetTimer(b.cd, 0, 0, 0)
          DefaultBorder(b)
        end
        self:BuildFlyout(el)
      end
    end
  end

  -- hide pfUI's own totem bar (pfTotems) while this bar is enabled
  local function SuppressDefaultTotems()
    local pft = pfUI.totems
    if not pft then return end

    if not pft.pfTotemBarHooked then
      pft.pfTotemBarHooked = true
      local origShow = pft.Show
      pft.Show = function(self)
        if cfg.enable == "1" then return self:Hide() end
        return origShow(self)
      end
    end

    if cfg.enable == "1" then
      pft:Hide()
    elseif pft.RefreshList then
      pft:RefreshList()
    end
  end

  function bar:UpdateConfig()
    SuppressDefaultTotems()

    if cfg.enable ~= "1" then
      self:Hide()
      return
    end

    local size = tonumber(cfg.size) or 30
    local spacing = tonumber(cfg.spacing) or 2
    local horizontal = cfg.direction ~= "VERTICAL"
    self.size, self.spacing = size, spacing

    local shown, prev = 0, nil
    for _, el in pairs(ParseOrder()) do
      local b = self.buttons[el]
      if known[el][1] and (el ~= "shield" or cfg.showshield == "1") then
        shown = shown + 1
        b:SetWidth(size)
        b:SetHeight(size)
        b.cdbg:SetWidth(size - 3)
        b.cdbg:SetHeight(size - 3)
        b:ClearAllPoints()
        if not prev then
          b:SetPoint("TOPLEFT", self, "TOPLEFT", spacing, -spacing)
        elseif horizontal then
          b:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        else
          b:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        end
        b:Show()
        prev = b
      else
        b.fly:Hide()
        b:Hide()
      end
    end

    if shown == 0 then
      self:Hide()
      return
    end

    local long = spacing + shown * (size + spacing)
    local short = size + spacing * 2
    self:SetWidth(horizontal and long or short)
    self:SetHeight(horizontal and short or long)

    if cfg.showbg == "1" then
      CreateBackdrop(self)
      self.backdrop:Show()
    elseif self.backdrop then
      self.backdrop:Hide()
    end

    self:Show()
    self:Refresh()
  end

  -- cooldowns, mana and totem timers
  local function FormatTime(remain)
    if remain >= 60 then return math.ceil(remain / 60) .. "m" end
    return math.floor(remain + .5)
  end

  bar:SetScript("OnUpdate", function()
    if (this.tick or 0) > GetTime() then return end
    this.tick = GetTime() + .1

    for _, el in pairs(GROUPS) do
      local b = this.buttons[el]
      local entry = b:IsShown() and GetActive(el)
      if entry then
        local start, duration, enable = GetSpellCooldown(entry.index, BOOKTYPE_SPELL)
        if start ~= b.cdstart or duration ~= b.cdduration then
          b.cdstart, b.cdduration = start, duration
          CooldownFrame_SetTimer(b.cd, start, duration, enable)
        end

        if IsSpellUsable then
          local usable, oom = IsSpellUsable(entry.name)
          if usable == 0 and oom == 1 then
            b.icon:SetVertexColor(.4, .5, 1)
          else
            b.icon:SetVertexColor(1, 1, 1)
          end
        end

        local text = ""
        if el == "shield" then
          -- charges of the active shield
          local charges = cfg.timer == "1" and ShieldCharges(entry)
          if charges then text = "|cffffffff" .. charges .. "|r" end
        elseif cfg.timer == "1" and GetTotemInfo then
          local active, name, tstart, tduration = GetTotemInfo(SLOT[el])
          if active and tstart then
            local remain = tstart + tduration - GetTime()
            if remain > 0 then
              -- white when your active totem is down, grey when another one is
              -- white: your active totem, red: out of range, grey: another totem
              local color = "|cffaaaaaa"
              if ActiveTotemDown(entry) then
                color = OutOfRange(entry) and "|cffff5555" or "|cffffffff"
              end
              text = color .. FormatTime(remain) .. "|r"
            end
          end
        end
        b.timer:SetText(text)
      end
    end
  end)

  -- [[ events ]] --
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("SPELLS_CHANGED")
  events:RegisterEvent("LEARNED_SPELL_IN_TAB")
  events:SetScript("OnEvent", function()
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      local _, sub, _, src, _, _, _, dst = CombatLogGetCurrentEventInfo()
      if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        for el, guid in pairs(totemGUID) do
          if guid == dst then totemGUID[el] = nil end
        end
        return
      end
      -- creatures only (0xF1...): our totems are the source of their effects
      if src and string.sub(src, 1, 4) == "0xF1" then LearnGUID(src) end
      if sub == "SPELL_SUMMON" and dst then LearnGUID(dst) end
      return
    elseif event == "SPELL_GO_OTHER" then
      -- Nampower: a totem pulsing its spell (arg3 = caster GUID)
      if arg3 and string.sub(arg3, 1, 4) == "0xF1" then LearnGUID(arg3) end
      return
    elseif event == "AURA_CAST_ON_SELF" then
      -- Nampower: a totem aura landing on us (arg2 = caster GUID)
      if arg2 and string.sub(arg2, 1, 4) == "0xF1" then LearnGUID(arg2) end
      return
    elseif event == "PLAYER_TARGET_CHANGED" then
      LearnUnit("target")
      return
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
      LearnUnit("mouseover")
      return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
      LearnUnit(arg1)
      return
    elseif event == "PLAYER_TOTEM_UPDATE" then
      -- slot emptied: forget its GUID
      local el = SLOT2EL[arg1]
      if el and GetTotemInfo then
        local _, _, start = GetTotemInfo(arg1)
        if not start or start <= 0 then totemGUID[el] = nil end
      end
      return
    elseif event == "SPELL_CAST_EVENT" then
      -- queued casts bypass the CastSpellByName hook pfUI uses to track totems
      if arg1 == 1 and GetSpellNameAndRankForId and pfUI.api.libtotem then
        local name, rank = GetSpellNameAndRankForId(arg2)
        local entry = name and byname[name]
        if entry then pfUI.api.libtotem:CheckAddQueue(name, rank, entry.icon) end
      end
      return
    end
    this.dirty = true
  end)
  events:SetScript("OnUpdate", function()
    if not this.dirty then return end
    this.dirty = nil
    Scan()
    bar:UpdateConfig()
  end)
  if UnitGUID and UnitOwnerGUID and UnitCreatedBySpell then
    if CombatLogGetCurrentEventInfo then events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end
    events:RegisterEvent("PLAYER_TOTEM_UPDATE")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    if hasNampower then
      -- Nampower 4.5+ enables these events when they are registered
      events:RegisterEvent("SPELL_GO_OTHER")
      events:RegisterEvent("AURA_CAST_ON_SELF")
    end
  end
  if hasNampower and GetSpellNameAndRankForId then
    events:RegisterEvent("SPELL_CAST_EVENT")
  end

  bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
  UpdateMovable(bar, true)
  Scan()
  bar:UpdateConfig()

  -- [[ public API ]] --
  -- casts unless it is still up (same rules as cast-all); force = always cast
  local function CastElement(el, force)
    el = el and string.lower(el)
    if not VALID[el] then return end
    local entry = GetActive(el)
    if entry and (force or not ShouldSkip(entry)) then Cast(entry) end
  end

  local function Cycle(el, dir)
    local list = known[el]
    local count = list and table.getn(list) or 0
    if count == 0 then return end
    local current = GetActive(el)
    local idx = current and 1 or 0
    for i = 1, count do
      if list[i] == current then idx = i end
    end
    idx = idx + dir
    if idx > count then idx = 1 elseif idx < 1 then idx = count end
    SetActive(el, list[idx].name)
    Print(LABEL[el] .. ": " .. list[idx].name)
  end

  local function FindByName(el, query)
    query = string.lower(query)
    for _, entry in pairs(known[el] or {}) do
      if string.lower(entry.name) == query then return entry end
    end
    for _, entry in pairs(known[el] or {}) do
      if string.find(string.lower(entry.name), query, 1, true) then return entry end
    end
  end

  _G.pfTotemBar.CastAll = CastAll
  _G.pfTotemBar.Cast = CastElement
  _G.pfTotemBar.CastShield = function(force) CastElement("shield", force) end
  _G.pfTotemBar.CastTotems = CastTotems
  _G.pfTotemBar.Next = function(el) if VALID[el] then Cycle(el, 1) end end
  _G.pfTotemBar.Prev = function(el) if VALID[el] then Cycle(el, -1) end end
  _G.pfTotemBar.SetActive = function(el, name)
    if VALID[el] and name and string.lower(name) == NONE then SetActive(el, NONE) return end
    local entry = VALID[el] and name and FindByName(el, name)
    if entry then SetActive(el, entry.name) end
  end
  _G.pfTotemBar.GetActive = function(el)
    local entry = VALID[el] and GetActive(el)
    return entry and entry.name
  end

  _G.SLASH_PFTOTEMBAR1 = "/totembar"
  _G.SLASH_PFTOTEMBAR2 = "/ptb"
  _G.SlashCmdList["PFTOTEMBAR"] = function(msg)
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "all" then
      CastAll()
    elseif cmd == "totems" then
      CastTotems(string.lower(rest) == "force")
    elseif VALID[cmd] then
      CastElement(cmd, string.lower(rest) == "force")
    elseif (cmd == "next" or cmd == "prev") and VALID[string.lower(rest)] then
      Cycle(string.lower(rest), cmd == "next" and 1 or -1)
    elseif cmd == "set" then
      local _, _, el, name = string.find(rest, "^(%a+)%s+(.+)$")
      el = el and string.lower(el)
      if el and VALID[el] and name and string.lower(name) == NONE then
        SetActive(el, NONE)
        Print(LABEL[el] .. ": " .. T["None"])
        return
      end
      local entry = el and VALID[el] and FindByName(el, name)
      if entry then
        SetActive(el, entry.name)
        Print(LABEL[el] .. ": " .. entry.name)
      else
        Print("unknown element or spell. Examples: /totembar set fire searing, /totembar set shield water")
      end
    elseif cmd == "list" then
      for _, el in pairs(ParseOrder()) do
        local entry = GetActive(el)
        Print(LABEL[el] .. ": " .. (entry and entry.name or "-") .. (cfg["all_" .. el] == "1" and "" or " (not in cast-all)"))
      end
    elseif cmd == "debug" then
      Print("UnitXP: " .. (UnitXP and "yes" or "|cffff5555no|r") ..
        ", UnitOwnerGUID: " .. (UnitOwnerGUID and "yes" or "|cffff5555no|r") ..
        ", combat log: " .. (CombatLogGetCurrentEventInfo and "yes" or "|cffff5555no|r") ..
        ", range check: " .. (cfg.rangecheck == "1" and "on" or "off"))
      for _, el in pairs(ELEMENTS) do
        local entry = GetActive(el)
        local name, start, sid
        if GetTotemInfo then _, name, start, _, _, _, sid = GetTotemInfo(SLOT[el]) end
        local guid = totemGUID[el]
        local dist
        if guid and UnitXP then
          local ok, d = pcall(UnitXP, "distanceBetween", "player", guid, "AoE")
          dist = ok and d
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: active=%s range=%s | slot=%s spell=%s | guid=%s dist=%s | down=%s out=%s",
          LABEL[el], entry and entry.name or "-", entry and tostring(entry.range) or "-",
          (start and start > 0) and tostring(name) or "empty", tostring(sid),
          tostring(guid), dist and string.format("%.1f", dist) or "-",
          entry and (ActiveTotemDown(entry) and "yes" or "no") or "-",
          entry and (OutOfRange(entry) and "|cffff5555yes|r" or "no") or "-"))
      end
      local sh = GetActive("shield")
      DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: active=%s charges=%s refresh at <= %s",
        LABEL.shield, sh and sh.name or "-", sh and tostring(ShieldCharges(sh)) or "-", tostring(cfg.shieldcharges)))
    elseif cmd == "scan" then
      Scan()
      bar:UpdateConfig()
      Print("spellbook rescanned.")
    else
      Print("commands:")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar all |cffaaaaaa- cast everything ticked in Cast All that needs a refresh")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar totems [force] |cffaaaaaa- cast the 4 active totems that need a refresh (no shield)")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar earth|fire|water|air |cffaaaaaa- cast the active totem of an element if it needs a refresh")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar shield |cffaaaaaa- cast the active shield if it is gone / low on charges")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar <element|shield> force |cffaaaaaa- cast it even if it is still up")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar next|prev <element> |cffaaaaaa- cycle the active totem")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar set <element> <name|none> |cffaaaaaa- e.g. /totembar set air windfury")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar list |cffaaaaaa- show the active totems")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar scan |cffaaaaaa- rescan the spellbook")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar debug |cffaaaaaa- show totem tracking and range info")
    end
  end

  -- [[ pfUI config GUI ]] --
  if pfUI.gui and pfUI.gui.CreateGUIEntry then
    local positions = {
      "TOP:" .. T["Top"],
      "BOTTOM:" .. T["Bottom"],
      "LEFT:" .. T["Left"],
      "RIGHT:" .. T["Right"],
    }

    local function TotemValues(el)
      return function()
        local values = {}
        for _, entry in pairs(known[el]) do
          table.insert(values, entry.name .. ":" .. entry.name)
        end
        table.insert(values, NONE .. ":" .. NONE_TEXT)
        return values
      end
    end

    local update = function() bar:UpdateConfig() end

    pfUI.gui.CreateGUIEntry(T["Thirdparty"], T["Totem Bar"], function()
      local CreateConfig = pfUI.gui.CreateConfig

      CreateConfig(update, T["Enable Totem Bar (hides pfUI Totem Icons)"], cfg, "enable", "checkbox")

      CreateConfig(nil, T["Active Totems"], nil, nil, "header")
      for _, el in pairs(ELEMENTS) do
        CreateConfig(update, LABEL[el] .. " " .. T["Totem"], cfg, el, "dropdown", TotemValues(el))
      end
      CreateConfig(update, T["Shield"], cfg, "shield", "dropdown", TotemValues("shield"))

      CreateConfig(nil, T["Cast All (/totembar all)"], nil, nil, "header")
      for _, el in pairs(GROUPS) do
        CreateConfig(update, T["Include"] .. " " .. LABEL[el], cfg, "all_" .. el, "checkbox")
      end
      CreateConfig(update, T["Cast Order (also the bar order)"], cfg, "order", nil, nil, nil, nil, "STRING")
      CreateConfig(update, T["Skip Totems That Are Still Active"], cfg, "skipactive", "checkbox")
      CreateConfig(update, T["...Unless Less Than X Seconds Left (0 = only when gone)"], cfg, "skipremain")
      CreateConfig(update, T["...Or You Are Out Of Its Range (UnitXP)"], cfg, "rangecheck", "checkbox")

      CreateConfig(nil, T["Shield (/totembar shield)"], nil, nil, "header")
      CreateConfig(update, T["Refresh At X Charges Or Less (0 = only when gone)"], cfg, "shieldcharges")
      CreateConfig(update, T["Show Shield Button"], cfg, "showshield", "checkbox")

      CreateConfig(nil, T["Layout"], nil, nil, "header")
      CreateConfig(update, T["Button Size"], cfg, "size")
      CreateConfig(update, T["Spacing"], cfg, "spacing", "dropdown", pfUI.gui.dropdowns.spacing)
      CreateConfig(update, T["Bar Direction"], cfg, "direction", "dropdown", pfUI.gui.dropdowns.orientation)
      CreateConfig(update, T["Totem List Direction"], cfg, "flyout", "dropdown", positions)
      CreateConfig(update, T["Open Totem List On Mouseover"], cfg, "hover", "checkbox")
      CreateConfig(update, T["Show Totem Timers"], cfg, "timer", "checkbox")
      CreateConfig(update, T["Show Background"], cfg, "showbg", "checkbox")
    end)
  end
end)
