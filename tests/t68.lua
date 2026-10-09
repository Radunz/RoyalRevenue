dofile("harness11.lua")
local C = RR.Craft
UnitRace = function() return "Human", "Human" end
local HERB = { [236761]=1,[236770]=1,[236778]=1,[236776]=1,[236774]=1,[236767]=1,[236780]=1,[236771]=1,[236779]=1 }
C_Item.GetItemInfoInstant = function(id) id = tonumber(id); if HERB[id] then return id, "", "", "", 0, 7, 9 end; return id, "", "", "", 0, 15, 0 end
C_Item.GetItemCount = function(id) return ({ [242299] = 3, [241316] = 2, [237373] = 1 })[id] or 0 end
C.Pricing.Sale = function(id) return 20000 end
-- árvore de especialização simulada
C_ProfSpecs = { GetSpecTabIDsForSkillLine = function() return { 1 } end, GetConfigIDForSkillLine = function() return 9 end,
  GetTabInfo = function() return { name = "Botany" } end, GetRootPathForTab = function() return 100 end,
  GetChildrenForPath = function(p) if p == 100 then return { 101, 102 } end return {} end,
  GetStateForPath = function() return 1 end,
  GetDescriptionForPath = function(p) if p == 101 then return "Increases Perception by 2 for each point spent." elseif p == 102 then return "Increases Finesse by 3 for each point." end return "Root" end,
  GetPerksForPath = function(p) if p == 101 then return { { perkID = 5 } } elseif p == 102 then return { { perkID = 6 } } end return {} end,
  GetUnlockRankForPerk = function(k) return k == 5 and 10 or 20 end,
  GetDescriptionForPerk = function(k) return k == 5 and "+15 Perception" or "You can gather herbs while mounted." end }
C_Traits = { GetNodeInfo = function(c, n) return { activeRank = n == 100 and 1 or 3, maxRanks = 31, entryIDs = {} } end, GetEntryInfo = function() return nil end }
Enum.ProfessionsSpecPathState = { Locked = 0 }
local gs = C.Invest._ReadGatherSpec({ professionID = 2900 })
print("tabs", #gs.tabs, "nodes", #gs.tabs[1].nodes)
for _, n in ipairs(gs.tabs[1].nodes) do print(n.name, n.rank, n.max, n.perRank and (n.perRank.perception or n.perRank.finesse), #n.teeth) end
C.UI.ShowTab(3)
local cv = LucroCraftFrame.canvases[3]
cv:Begin()
print(pcall(C.Invest._RenderGathering, cv, { parentID = 182, name = "Herbalism", class = "HUNTER", invest = { gathering = true, gspec = gs } }, 760))
local out = {}
for i = 1, (cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); if t ~= "" then table.insert(out, t) end end
local s = table.concat(out, " | "); print(s:match("Pontos de conhecimento.-Buffs") or "?"); print(s:match("Buffs temporários.-Sigla") or "?")
print("secure", cv.secureUsed)
