-- !!!CompatShims: Retail API stubs for 3.3.5a
-- Purpose: Provide missing CompactUnitFrame_Util* functions used by modern addons (e.g., BigDebuffs)
-- These are ONLY defined if they do not already exist (guards avoid overriding backported implementations).

local _G = _G

local function DefineIfMissing(globalName, fn)
  if _G[globalName] == nil then
    _G[globalName] = fn
  end
end

-- DetailsFramework role helper safety: ensure UnitGroupRolesAssigned exists and returns a sane default
do
  local DF = _G.DetailsFramework
  if type(DF) == "table" then
    if type(DF.UnitGroupRolesAssigned) ~= "function" then
      function DF.UnitGroupRolesAssigned(unit)
        return "NONE"
      end
    else
      local orig = DF.UnitGroupRolesAssigned
      DF.UnitGroupRolesAssigned = function(unit)
        local ok, role = pcall(orig, unit)
        role = ok and role or nil
        if role == nil or role == "" then
          return "NONE"
        end
        return role
      end
    end
  end
end

-- Apollo/XMLDoc compatibility shims (for WildStar-style addons such as CombatLogFix)
do
  if not _G.Apollo then
    local Apollo = {}
    function Apollo.RegisterAddon(...) end
    function Apollo.AddAddonErrorText(...) end
    function Apollo.LoadForm(...) return nil end
    function Apollo.GetAddon(...) return nil end
    function Apollo.RegisterEventHandler(...) end
    function Apollo.RemoveEventHandler(...) end
    function Apollo.GetString(key) return tostring(key) end
    _G.Apollo = Apollo
  end

  if not _G.XmlDoc then
    local XmlDoc = {}
    function XmlDoc.CreateFromFile(path)
      local doc = {}
      function doc:RegisterCallback(event, obj)
        if type(obj) == "table" and type(obj[event]) == "function" then
          pcall(obj[event], obj)
        end
      end
      function doc:IsLoaded() return true end
      return doc
    end
    _G.XmlDoc = XmlDoc
  end

  if not _G.String_GetWeaselString then
    function String_GetWeaselString(fmt, ...)
      if type(fmt) ~= "string" then return tostring(fmt) end
      if fmt:find("%%") then
        local ok, res = pcall(string.format, fmt, ...)
        if ok then return res end
      end
      local args = {...}
      if #args > 0 then
        for i,v in ipairs(args) do args[i] = tostring(v) end
        return fmt .. " " .. table.concat(args, " ")
      end
      return fmt
    end
  end
end

-- Boss/priority/visibility helpers (retail-only in many packs)
DefineIfMissing('CompactUnitFrame_UtilIsBossAura', function(...) return false end)
DefineIfMissing('CompactUnitFrame_UtilIsPriorityDebuff', function(...) return false end)
DefineIfMissing('CompactUnitFrame_UtilShouldDisplayBuff', function(...) return true end)
DefineIfMissing('CompactUnitFrame_UtilShouldDisplayDebuff', function(...) return true end)
DefineIfMissing('CompactUnitFrame_UtilShouldDisplayDispelDebuff', function(...) return true end)
DefineIfMissing('CompactUnitFrame_UtilIsBlacklistedDebuff', function(...) return false end)

-- Some addons call these utility wrappers in retail; make them harmless if missing on 3.3.5a
DefineIfMissing('CompactUnitFrame_UtilIsAuraFilteredOut', function(...) return false end)
DefineIfMissing('CompactUnitFrame_UtilAreAurasEqual', function(...) return false end)

-- Optional: simple one-time notice (comment out if undesired)
if DEFAULT_CHAT_FRAME and not _G.__CompatShimsAnnounced then
  _G.__CompatShimsAnnounced = true
  DEFAULT_CHAT_FRAME:AddMessage("|cff44d3e3!!!CompatShims|r loaded: retail API stubs enabled.")
end

-- LibGroupTalents-1.0 compatibility: protect calls that assume valid unit tokens.
-- Some addons (e.g., Details_TinyThreat) may call into LibGroupTalents with nil/invalid unit tokens,
-- which triggers "Usage: UnitGUID('unit')" errors on 3.3.5a. We wrap a few public entry points
-- to be nil-safe. This is done post-login/addon-load to ensure the library is available.

local function Compat_PatchLibGroupTalents()
  local LibStub = _G.LibStub
  if not LibStub then return end
  local lib = LibStub:GetLibrary("LibGroupTalents-1.0", true)
  if not lib or lib.__CompatShims_Patched then return end

  local function isSafeUnit(unit)
    return type(unit) == "string" and unit ~= "" and UnitExists(unit)
  end

  -- Wrap GetUnitRole to avoid calling UnitGUID on invalid input; delegate to GetGUIDRole when possible.
  if type(lib.GetUnitRole) == "function" then
    local orig = lib.GetUnitRole
    lib.GetUnitRole = function(self, unit, ...)
      if not isSafeUnit(unit) then return nil end
      local guid = UnitGUID(unit)
      if not guid then return nil end
      if type(self.GetGUIDRole) == "function" then
        return self:GetGUIDRole(guid, ...)
      end
      -- Fallback to original if needed
      local ok, r1, r2, r3 = pcall(orig, self, unit, ...)
      if ok then return r1, r2, r3 end
      return nil
    end
  end

  -- Generic safe wrapper for other unit-based queries in the library
  local function wrapUnitFn(name)
    if type(lib[name]) ~= "function" then return end
    local orig = lib[name]
    lib[name] = function(self, unit, ...)
      if not isSafeUnit(unit) then return nil end
      local ok, r1, r2, r3, r4 = pcall(orig, self, unit, ...)
      if ok then return r1, r2, r3, r4 end
      return nil
    end
  end

  for _, fname in ipairs({
    "GetUnitTalentSpec",
    "UnitHasTalent",
    "UnitHasGlyph",
    "GetUnitGlyphs",
    "GetUnitStorageString",
  }) do
    wrapUnitFn(fname)
  end

  lib.__CompatShims_Patched = true
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff44d3e3!!!CompatShims|r patched LibGroupTalents-1.0 (nil-safe unit wrappers)")
  end
end

-- Attempt patch after addons load and at login; also try once on first OnUpdate
local __Compat_Frame = CreateFrame("Frame")
__Compat_Frame:RegisterEvent("ADDON_LOADED")
__Compat_Frame:RegisterEvent("PLAYER_LOGIN")
__Compat_Frame:SetScript("OnEvent", function()
  Compat_PatchLibGroupTalents()
end)
__Compat_Frame:SetScript("OnUpdate", function(self)
  Compat_PatchLibGroupTalents()
  self:SetScript("OnUpdate", nil)
end)

-- Soft `require` wrapper: avoid hard errors like "Module not preloaded: Window".
-- We delegate to the original `require` first; on failure, we return a cached stub module
-- for known names (e.g., "Window"). This prevents load-time crashes in addons expecting
-- retail-style modules. Expand the list as needed.
do
  local orig_require = _G.require
  local cache = _G.__CompatRequireCache or {}
  _G.__CompatRequireCache = cache
  local function noop(...) end

  local STUB_WHITELIST = {
    Window = true,
    window = true,
  }

  local function getStub(name)
    if not cache[name] then
      cache[name] = setmetatable({}, {
        __index = function()
          return noop
        end,
        __call = function()
          return nil
        end,
      })
    end
    return cache[name]
  end

  _G.require = function(name)
    if type(orig_require) == "function" then
      local ok, result = pcall(orig_require, name)
      if ok then return result end
    end
    if STUB_WHITELIST[name] then
      return getStub(name)
    end
    -- Fallback: return original error behavior for unknown names to avoid hiding bugs
    -- Re-throw a minimal error matching retail style when orig_require isn't usable.
    error(("Module not preloaded: %s"):format(tostring(name)))
  end
end

-- Nil-safe wrappers for common unit queries used by some addons without guards.
-- These wrappers only alter behavior for invalid input; valid calls behave exactly the same.
do
  local orig_UnitExists = _G.UnitExists
  local function isSafeUnit(unit)
    return type(unit) == "string" and unit ~= "" and (not orig_UnitExists or orig_UnitExists(unit))
  end

  local orig_UnitClass = _G.UnitClass
  if type(orig_UnitClass) == "function" then
    _G.UnitClass = function(unit)
      if not isSafeUnit(unit) then
        -- Return classic-like tuple to avoid errors in code like: local _, class = UnitClass(unit)
        return "Unknown", "UNKNOWN"
      end
      return orig_UnitClass(unit)
    end
  end

  local orig_UnitGUID = _G.UnitGUID
  if type(orig_UnitGUID) == "function" then
    _G.UnitGUID = function(unit)
      if not isSafeUnit(unit) then return nil end
      return orig_UnitGUID(unit)
    end
  end

  local orig_GetUnitName = _G.GetUnitName
  if type(orig_GetUnitName) == "function" then
    _G.GetUnitName = function(unit, showServer)
      local name
      if isSafeUnit(unit) then
        name = orig_GetUnitName(unit, showServer)
      end
      if name ~= nil and name ~= "" then
        return name
      end
      -- Fallback to unit token to keep keys stable in addons (e.g., "party2", "raid5")
      if type(unit) == "string" and unit ~= "" then
        return unit
      end
      return "Unknown"
    end
  end
end
