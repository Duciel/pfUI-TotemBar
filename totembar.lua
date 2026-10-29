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
    return
  end

  local cfg = C.totembar
  local PREFIX = "|cff33ffccpf|rTotemBar: "
  local hasNampower = QueueSpellByName and true or nil

  local ELEMENTS = { "earth", "fire", "water", "air" }
  local SLOT = { fire = 1, earth = 2, water = 3, air = 4 }         -- same ids as pfUI's libtotem
  local SLOT2EL = { [1] = "fire", [2] = "earth", [3] = "water", [4] = "air" }
  local LABEL = { earth = T["Earth"], fire = T["Fire"], water = T["Water"], air = T["Air"] }
  local COLOR = {
    earth = { .45, .75, .2 },
    fire  = { .95, .4, .1 },
    water = { .2, .6, 1 },
    air   = { .7, .45, 1 },
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

  local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  end

  -- [[ spellbook scan ]] --
  local known = { earth = {}, fire = {}, water = {}, air = {} }
  local byname = {}
  local effectCache = {}

  local function ShortTexture(tex)
    if not tex then return "" end
    local _, _, short = string.find(tex, "([^\\]+)$")
    return string.lower(short or tex)
  end

  local function SlotByEffect(name)
    if not GetSpellIdForName or not GetSpellRecField then return nil end
    local id = GetSpellIdForName(name)
    if not id or id == 0 then return nil end
    local ok, effects = pcall(GetSpellRecField, id, "effect")
    if not ok or type(effects) ~= "table" then return nil end
    for _, effect in pairs(effects) do
      if TOTEM_EFFECTS[effect] then return TOTEM_EFFECTS[effect] end
    end
    return nil
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
    for _, el in pairs(ELEMENTS) do known[el] = {} end
    byname = {}

    local i = 1
    while true do
      local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
      if not name then break end

      local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
      local slot = TEXTURES[ShortTexture(tex)]
      if not slot then
        if effectCache[name] == nil then effectCache[name] = SlotByEffect(name) or false end
        slot = effectCache[name] or nil
      end

      if slot then
        local el = SLOT2EL[slot]
        local entry = byname[name]
        if not entry then
          entry = { name = name, element = el }
          byname[name] = entry
          table.insert(known[el], entry)
        end
        -- spellbook lists ranks in ascending order: the last one wins
        entry.index, entry.rank, entry.icon = i, rank, tex
        entry.range = ScanRange(i, tex)
      end

      i = i + 1
    end

    -- pick a sensible default the first time
    for _, el in pairs(ELEMENTS) do
      if (cfg[el] == nil or cfg[el] == "") and known[el][1] then
        cfg[el] = known[el][1].name
      end
    end
  end

  local function GetActive(el)
    local list = known[el]
    if not list or not list[1] then return nil end
    local want = cfg[el]
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
    CastSpellByName(SpellString(entry))
  end

  local function ParseOrder()
    local order, seen = {}, {}
    for el in string.gfind(string.lower(cfg.order or ""), "%a+") do
      if SLOT[el] and not seen[el] then
        table.insert(order, el)
        seen[el] = true
      end
    end
    for _, el in pairs(ELEMENTS) do
      if not seen[el] then table.insert(order, el) end
    end
    return order
  end

  -- [[ totem state ]] --
  -- GUID of each totem we dropped, learned from the combat log (ClassicAPI)
  local totemGUID = {}

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

  -- [[ cast all ]] --
  local function ShouldSkip(entry)
    if cfg.skipactive ~= "1" then return nil end
    local start, duration = ActiveTotemDown(entry)
    -- missing, or another totem of this element is down: cast the active one
    if not start then return nil end
    if OutOfRange(entry) then return nil end
    local remain = start + duration - GetTime()
    return remain > (tonumber(cfg.skipremain) or 0)
  end

  local function BuildCastList()
    local list = {}
    for _, el in pairs(ParseOrder()) do
      if cfg["all_" .. el] == "1" then
        local entry = GetActive(el)
        if entry and not ShouldSkip(entry) then
          table.insert(list, entry)
        end
      end
    end
    return list
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

  local function ShowTooltip(button, entry, main)
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetSpell(entry.index, BOOKTYPE_SPELL)
    GameTooltip:AddLine(" ")
    if main then
      GameTooltip:AddDoubleLine("Left-click", "Cast " .. entry.name, 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Right-click", "Pin the " .. LABEL[entry.element] .. " totem list", 1, 1, 1, .2, 1, .8)
    else
      GameTooltip:AddDoubleLine("Left-click", "Cast", 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Right-click", "Set as active " .. LABEL[entry.element] .. " totem", 1, 1, 1, .2, 1, .8)
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
    if not byname[name] or byname[name].element ~= el then return end
    cfg[el] = name
    bar:Refresh()
  end

  -- flyout buttons
  local function FlyOnClick()
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
    ShowTooltip(this, this.entry)
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
    ShowTooltip(this, GetActive(this.element), true)
  end

  local function MainOnLeave()
    this.hl:Hide()
    GameTooltip:Hide()
  end

  for _, el in pairs(ELEMENTS) do
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
    local fly, list, active = b.fly, known[el], GetActive(el)
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

      f.entry = list[i]
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

      f.icon:SetTexture(list[i].icon)
      if list[i] == active then
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
    for _, el in pairs(ELEMENTS) do
      local b = self.buttons[el]
      local entry = GetActive(el)
      if entry then
        b.icon:SetTexture(entry.icon)
        b:SetBackdropBorderColor(COLOR[el][1], COLOR[el][2], COLOR[el][3], 1)
        b.cdstart, b.cdduration = nil, nil
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
      if known[el][1] then
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

    for _, el in pairs(ELEMENTS) do
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
        if cfg.timer == "1" and GetTotemInfo then
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
      local _, sub, _, src, _, _, _, dst, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
      if sub == "SPELL_SUMMON" then
        this.player = this.player or UnitGUID("player")
        if src ~= this.player then return end
        local entry = spellName and byname[spellName]
        if not entry and spellId and GetSpellInfo then
          entry = byname[GetSpellInfo(spellId) or ""]
        end
        if entry then totemGUID[entry.element] = dst end
      elseif sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        for el, guid in pairs(totemGUID) do
          if guid == dst then totemGUID[el] = nil end
        end
      end
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
  if CombatLogGetCurrentEventInfo and UnitGUID then
    events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    events:RegisterEvent("PLAYER_TOTEM_UPDATE")
  end
  if hasNampower and GetSpellNameAndRankForId then
    events:RegisterEvent("SPELL_CAST_EVENT")
  end

  bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
  UpdateMovable(bar, true)
  Scan()
  bar:UpdateConfig()

  -- [[ public API ]] --
  local function CastElement(el)
    el = el and string.lower(el)
    if SLOT[el] then Cast(GetActive(el)) end
  end

  local function Cycle(el, dir)
    local list = known[el]
    local count = list and table.getn(list) or 0
    if count == 0 then return end
    local current, idx = GetActive(el), 1
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
  _G.pfTotemBar.Next = function(el) if SLOT[el] then Cycle(el, 1) end end
  _G.pfTotemBar.Prev = function(el) if SLOT[el] then Cycle(el, -1) end end
  _G.pfTotemBar.SetActive = function(el, name)
    local entry = SLOT[el] and name and FindByName(el, name)
    if entry then SetActive(el, entry.name) end
  end
  _G.pfTotemBar.GetActive = function(el)
    local entry = SLOT[el] and GetActive(el)
    return entry and entry.name
  end

  _G.SLASH_PFTOTEMBAR1 = "/totembar"
  _G.SLASH_PFTOTEMBAR2 = "/ptb"
  _G.SlashCmdList["PFTOTEMBAR"] = function(msg)
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "all" then
      CastAll()
    elseif SLOT[cmd] then
      CastElement(cmd)
    elseif (cmd == "next" or cmd == "prev") and SLOT[string.lower(rest)] then
      Cycle(string.lower(rest), cmd == "next" and 1 or -1)
    elseif cmd == "set" then
      local _, _, el, name = string.find(rest, "^(%a+)%s+(.+)$")
      el = el and string.lower(el)
      local entry = el and SLOT[el] and FindByName(el, name)
      if entry then
        SetActive(el, entry.name)
        Print(LABEL[el] .. ": " .. entry.name)
      else
        Print("unknown element or totem. Example: /totembar set fire searing")
      end
    elseif cmd == "list" then
      for _, el in pairs(ParseOrder()) do
        local entry = GetActive(el)
        Print(LABEL[el] .. ": " .. (entry and entry.name or "-") .. (cfg["all_" .. el] == "1" and "" or " (not in cast-all)"))
      end
    elseif cmd == "scan" then
      Scan()
      bar:UpdateConfig()
      Print("spellbook rescanned.")
    else
      Print("commands:")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar all |cffaaaaaa- cast every active totem")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar earth|fire|water|air |cffaaaaaa- cast the active totem of an element")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar next|prev <element> |cffaaaaaa- cycle the active totem")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar set <element> <name> |cffaaaaaa- e.g. /totembar set air windfury")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar list |cffaaaaaa- show the active totems")
      DEFAULT_CHAT_FRAME:AddMessage("  /totembar scan |cffaaaaaa- rescan the spellbook")
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
        if not values[1] then
          table.insert(values, ":" .. T["None"])
        end
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

      CreateConfig(nil, T["Cast All (/totembar all)"], nil, nil, "header")
      for _, el in pairs(ELEMENTS) do
        CreateConfig(update, T["Include"] .. " " .. LABEL[el], cfg, "all_" .. el, "checkbox")
      end
      CreateConfig(update, T["Cast Order (also the bar order)"], cfg, "order", nil, nil, nil, nil, "STRING")
      CreateConfig(update, T["Skip Totems That Are Still Active"], cfg, "skipactive", "checkbox")
      CreateConfig(update, T["...Unless Less Than X Seconds Left (0 = only when gone)"], cfg, "skipremain")
      CreateConfig(update, T["...Or You Are Out Of Its Range (UnitXP)"], cfg, "rangecheck", "checkbox")

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
