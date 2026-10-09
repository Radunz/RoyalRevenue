local ADDON, root = ...
local print = function(...) return root.Out(...) end   -- mensagens vão para a aba de log
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Avisos no login: concentração perto de encher, conhecimento não gasto, reset semanal e scans antigos.
-- No login também reprecifica todos os dados salvos com o TSM (sem precisar abrir as profissões).
local Alerts = {}
ns.Alerts = Alerts

local Cfg = ns.Cfg

local function Short(char) return (char:match("^([^-]+)")) or char end

local function Hours(h)
	if h < 1 then return string.format("%d min", math.max(1, math.floor(h * 60 + 0.5))) end
	if h < 48 then return string.format("%.0fh", h) end
	return string.format(L["%.1f dias"], h / 24)
end
Alerts.Hours = Hours

-- idade de um timestamp em texto colorido (verde < 1 dia, laranja até staleDays, vermelho acima)
function Alerts.AgeText(t)
	if not t then return "|cff808080?|r" end
	local h = math.max(0, (time() - t) / 3600)
	local stale = (tonumber(Cfg("staleDays")) or 3) * 24
	local c = h < 24 and "|cff55ff55" or h < stale and "|cffff8800" or "|cffff5555"
	return c .. Hours(h) .. "|r"
end

function Alerts.IsStale(t)
	return not t or (time() - t) > (tonumber(Cfg("staleDays")) or 3) * 86400
end

-- início da semana atual (reset semanal)
local function WeekStart()
	if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
		local s = C_DateAndTime.GetSecondsUntilWeeklyReset()
		if s then return time() + s - 7 * 86400 end
	end
	return nil
end

function Alerts.Collect()
	local conc, know, stale = {}, {}, {}
	local pct = tonumber(Cfg("alertConcPct")) or 0.9
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			local prof = e.name or e.skillLine or "?"
			if e.conc and e.conc.max and e.conc.max > 0 and ns.Plan then
				local est = ns.Plan.EstimatedConc(e)
				if est >= e.conc.max * pct then
					local rate = tonumber(Cfg("concPerHour")) or LucroCraftDB.concRate or 10.5
					table.insert(conc, { char = char, prof = prof, est = est, max = e.conc.max,
						fullIn = (e.conc.max - est) / rate })
				end
			end
			if e.knowledge and e.knowledge > 0 then
				table.insert(know, { char = char, prof = prof, n = e.knowledge, time = e.time })
			end
			if Alerts.IsStale(e.time) then
				table.insert(stale, { char = char, prof = prof, time = e.time })
			end
		end
	end
	table.sort(conc, function(a, b) return a.fullIn < b.fullIn end)
	return conc, know, stale
end

function Alerts.Show(fromLogin)
	local conc, know, stale = Alerts.Collect()
	local any = false
	if #conc > 0 then
		any = true
		ns.Print(L["|cff66ccffConcentração perto de encher:|r"])
		for _, c in ipairs(conc) do
			local when = c.fullIn > 0 and (L["enche em "] .. Hours(c.fullIn)) or L["|cffff5555cheia (desperdiçando)|r"]
			print(string.format("   %s · %s: ~%d/%d · %s", Short(c.char), c.prof, math.floor(c.est), c.max, when))
		end
	end
	if #know > 0 then
		any = true
		ns.Print(L["|cffffd100Pontos de conhecimento não gastos:|r"])
		for _, k in ipairs(know) do
			print(string.format(L["   %s · %s: %d (no scan de %s)"], Short(k.char), k.prof, k.n, date("%d/%m", k.time or time())))
		end
	end
	-- reset semanal: lembra uma vez por semana das fontes semanais de conhecimento
	local ws = WeekStart()
	if ws and (LucroCraftDB.weeklySeen or 0) < ws - 60 then
		LucroCraftDB.weeklySeen = ws
		any = true
		ns.Print(L["|cffffd100Reset semanal:|r fontes semanais de conhecimento liberadas (missão da profissão, tratado, tesouros) — confira em cada personagem."])
	end
	if #stale > 0 then
		any = true
		local names = {}
		for _, s in ipairs(stale) do table.insert(names, Short(s.char) .. "/" .. s.prof) end
		ns.Print(string.format(L["|cffff8800Scans antigos (mais de %s dias):|r %s — preços são atualizados sozinhos, mas skill/stats/concentração só abrindo a profissão."],
			tostring(Cfg("staleDays")), table.concat(names, ", ")))
	end
	if not any and not fromLogin then ns.Print(L["nenhum alerta."]) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	-- espera o TSM carregar os preços
	C_Timer.After(12, function()
		if not LucroCraftDB then return end
		if ns.Scanner and ns.Scanner.RepriceAll then ns.Scanner.RepriceAll() end
		if Cfg("alertsOnLogin") then Alerts.Show(true) end
	end)
end)

