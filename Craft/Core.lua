local ADDON, root = ...
local print = function(...) return root.Out(...) end   -- mensagens vão para a aba de log
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

function ns.Print(msg)
	print("|cffd4af37Royal Revenue|r: " .. tostring(msg))
end

-- Log de avisos da varredura (fica salvo no SavedVariables para auditoria)
local LOG_MAX = 300
function ns.Log(msg)
	if not LucroCraftDB then return end
	LucroCraftDB.log = LucroCraftDB.log or {}
	local log = LucroCraftDB.log
	msg = tostring(msg)
	-- a varredura roda várias vezes com a profissão aberta: não repete o mesmo aviso (em todo o registro,
	-- senão os ~100 avisos de "sem preço" de cada varredura empurram os erros de verdade para fora)
	for i = #log, 1, -1 do
		if log[i]:sub(16) == msg then return end
	end
	table.insert(log, date("%d/%m %H:%M:%S") .. " " .. msg)
	while #log > LOG_MAX do table.remove(log, 1) end
	if LucroCraftDB.config and LucroCraftDB.config.debug then ns.Print("|cffff8800" .. L["[registro]"] .. "|r " .. tostring(msg)) end
end

local function G(c) return c and ns.Pricing.FormatMoney(c) or "—" end

-- /lucro audit <nome ou recipeID>: despeja no chat todo o cálculo da receita
local function Audit(query)
	local q = (query or ""):lower()
	if q == "" then ns.Print(L["uso: /lucro audit <nome da receita ou recipeID>"]) return end
	local found
	for _, entry in pairs((LucroCraftDB.chars or {})[ns.CharKey()] or {}) do
		local list = {}
		for _, r in ipairs(entry.rows or {}) do table.insert(list, r) end
		for _, r in ipairs(entry.unknown or {}) do table.insert(list, r) end
		for _, r in ipairs(list) do
			if tostring(r.recipeID) == q or (r.name and r.name:lower():find(q, 1, true)) then
				found = r
				break
			end
		end
		if found then break end
	end
	if not found then ns.Print(L["receita não encontrada: "] .. query) return end
	local r, a = found, found.audit or {}
	ns.Print(string.format(L["|cffffd100Auditoria: %s|r (recipe %d, item %d)"], r.name or "?", r.recipeID, r.itemID or 0))
	for _, part in ipairs(r.parts or {}) do
		local name = C_Item.GetItemNameByID(part.itemID) or part.itemID
		print(string.format(L["  reagente %dx %s (id %d, slot %s): %s un = %s"],
			part.qty, name, part.itemID, tostring(part.slot), G(part.unit), G(part.unit and part.unit * part.qty)))
	end
	print(string.format(L["  custo total: %s"], G(r.cost)))
	print(string.format(L["  qualidade: %s de %s | modo: %s"], r.quality and ns.QIcon(r.quality, r.maxQuality) or "?", tostring(r.maxQuality), a.opMode or "—"))
	if a.opError then print(L["  |cffff5555erro operação:|r "] .. a.opError) end
	if a.op then
		print(string.format(L["  skill %s+%s | dificuldade %s+%s | limites %s-%s | conc %s | ingenuity %s"],
			tostring(a.op.baseSkill), tostring(a.op.bonusSkill), tostring(a.op.recipeDifficulty), tostring(a.op.bonusDifficulty),
			tostring(a.op.lowerSkillThreshold), tostring(a.op.upperSkillTreshold),
			tostring(a.op.concentrationCost), tostring(a.op.ingenuityRefund)))
	end
	for _, line in ipairs(a.reagentsSent or {}) do print(L["  enviado p/ API: "] .. line) end
	for id, b in pairs(a.prices or {}) do
		local name = C_Item.GetItemNameByID(id) or id
		print(string.format(L["  preço %s: minBuy %s | market %s | regionAvg %s | vendor %s | usado custo %s / venda %s"],
			name, G(b.DBMinBuyout), G(b.DBMarket), G(b.DBRegionMarketAvg), G(b.VendorBuy), G(b.usedCost), G(b.usedSale)))
	end
	print(string.format(L["  venda un %s x %.1f x %.0f%% = %s"], G(r.sale), r.qty, (1 - ns.Cfg("ahCut")) * 100,
		G(r.sale and r.sale * r.qty * (1 - ns.Cfg("ahCut")))))
	print(string.format(L["  lucro: %s | margem %s"], G(r.profit), r.margin and string.format("%.0f%%", r.margin * 100) or "—"))
	if r.concCost then
		print(string.format(L["  conc: %d -> %s venda %s | lucro c/ conc %s | lucro/conc %s"],
			r.concCost, ns.QIcon(r.concQuality or 2, r.maxQuality), G(r.concSale), G(r.concProfit), G(r.perConc)))
	end
	if a.formula then print("  |cff9d9d9d" .. a.formula .. "|r") end
end
ns.Audit = Audit

local wantOpen = false      -- só abre sozinho quando a profissão acabou de ser aberta
local autoOpened = false
-- O scan lê todas as receitas da profissão (pesado). TRADE_SKILL_LIST_UPDATE chega a cada fabricação:
-- fabricando em sequência, o scan espera 3 s sem eventos (no máx. 30 s) e não roda de novo antes de 8 s.
-- Profissão/expansão diferente da última escaneada (ou janela recém-aberta) escaneia logo (0,6 s).
local token, firstAt, lastScanAt, lastProf = 0, nil, -100, nil
local function RunScan()
	firstAt = nil
	lastScanAt = GetTime()
	local entry = ns.Scanner.Scan(true)
	if entry then
		lastProf = entry.professionID
		if wantOpen and ns.Cfg("autoOpen") and not ns.UI.IsShown() then
			wantOpen = false
			autoOpened = true
			ns.UI.Show(entry.professionID)
		else
			ns.UI.Select(entry.professionID)
		end
	end
end
local function ScheduleScan(now)
	token = token + 1
	local my = token
	local t = GetTime()
	local delay = 0.6
	if not now then
		local shown = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
		local same = shown and shown.professionID and shown.professionID == lastProf
		if same then
			firstAt = firstAt or t
			delay = math.max(3, 8 - (t - lastScanAt))
			if t + delay - firstAt > 30 then delay = math.max(0.6, 30 - (t - firstAt)) end
		end
	end
	C_Timer.After(delay, function()
		if my ~= token then return end   -- chegou outro evento: o mais novo agenda
		RunScan()
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
f:RegisterEvent("TRADE_SKILL_CLOSE")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		LucroCraftDB = LucroCraftDB or {}
		LucroCraftDB.config = LucroCraftDB.config or {}
		LucroCraftDB.chars = LucroCraftDB.chars or {}
		LucroCraftDB.queue = LucroCraftDB.queue or { list = {} }
	elseif event == "TRADE_SKILL_SHOW" then
		wantOpen = true
		ScheduleScan(true)
	elseif event == "TRADE_SKILL_LIST_UPDATE" then
		ScheduleScan()
	elseif event == "TRADE_SKILL_CLOSE" then
		wantOpen = false
		if autoOpened then ns.UI.Hide() end
		autoOpened = false
	end
end)

local HELP = {
	L["|cffffd100/lucro|r — abre/fecha a janela"],
	L["|cffffd100/lucro scan|r — reescaneia (com a profissão aberta)"],
	L["|cffffd100/lucro venda <preço TSM>|r — fonte do preço de venda (atual: %s)"],
	L["|cffffd100/lucro custo <preço TSM>|r — fonte do custo dos reagentes (atual: %s)"],
	L["|cffffd100/lucro qualidade <auto|1-5>|r — qualidade do item final (auto = a que sua skill atinge; atual: %s)"],
	L["|cffffd100/lucro abc <A> <B>|r — cortes da curva ABC em %% (atual: %d / %d)"],
	L["|cffffd100/lucro auto on|off|r — abrir junto com a profissão (atual: %s)"],
	L["|cffffd100/lucro colunas [chave|reset]|r — mostra/oculta colunas (ou arraste/botão direito no cabeçalho)"],
	L["|cffffd100/lucro audit <receita>|r — mostra o cálculo completo · |cffffd100/lucro log [limpar]|r · |cffffd100/lucro debug on|off|r"],
	L["|cffffd100/lucro liquidez <n>|r — vendas/dia mínimas p/ não marcar como pouca venda (atual: %s)"],
	L["|cffffd100/lucro plano|r — plano de concentração (todos os personagens) · |cffffd100/lucro stats on|off|r · |cffffd100/lucro fabricar on|off|r"],
	L["|cffffd100/lucro investir|r — ganho por semana e retorno de ferramentas/acessórios · |cffffd100/lucro regen <n/h>|r · |cffffd100/lucro giro <%%>|r · |cffffd100/lucro recomendar A|B|C|r"],
	L["|cffffd100/lucro config|r — abre a aba de configurações"],
	L["|cffffd100/lucro resetpos|r — volta a janela para o lado da profissão"],
	L["|cffffd100/lucro reset|r — apaga dados salvos e configurações"],
	L["|cffffd100/lucro fila|r — fila e lista de compras · |cffffd100/lucro historico|r — suas vendas reais x previstas"],
	L["|cffffd100/lucro alertas|r · |cffffd100/lucro reprecificar|r (todos os personagens, sem abrir a profissão) · |cffffd100/lucro estoque mercado|estoque|r (atual: %s)"],
}

local function ShowHelp()
	local C = ns.Cfg
	ns.Print(L["comandos:"])
	print(HELP[1]); print(HELP[2])
	print(string.format(HELP[3], C("saleSource")))
	print(string.format(HELP[4], C("costSource")))
	print(string.format(HELP[5], C("outputQuality")))
	print(string.format(HELP[6], C("abcA") * 100, C("abcB") * 100))
	print(string.format(HELP[7], C("autoOpen") and "on" or "off"))
	print(HELP[8]); print(HELP[9])
	print(string.format(HELP[10], tostring(C("minSoldPerDay"))))
	print(HELP[11]); print(HELP[12]); print(HELP[13]); print(HELP[14]); print(HELP[15])
	print(HELP[16]); print(string.format(HELP[17], L[tostring(C("costMode"))]))
end

local function Rescan()
	local e = ns.Scanner.Scan(false)
	if e then ns.UI.Show(e.professionID) end
end

-- comandos em português e em inglês levam ao mesmo lugar
local ALIAS = {
	escanear = "scan", varrer = "scan", auditoria = "audit", registro = "log", depurar = "debug",
	atributos = "stats", reposicionar = "resetpos", zerar = "reset",
	sale = "venda", cost = "custo", quality = "qualidade", columns = "colunas", liquidity = "liquidez",
	plan = "plano", crafted = "fabricar", invest = "investir", turnover = "giro", recommend = "recomendar",
	settings = "config", queue = "fila", history = "historico", alerts = "alertas", reprice = "reprecificar",
	stock = "estoque", auction = "leilao",
}
local OFF = { off = true, no = true, nao = true, ["não"] = true, desligar = true }
local function IsOff(rest) return OFF[(rest or ""):lower()] or false end

SLASH_LUCROCRAFT1 = "/lucro"
SLASH_LUCROCRAFT2 = "/lucrocraft"
SlashCmdList.LUCROCRAFT = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	cmd = ALIAS[cmd] or cmd
	local cfg = LucroCraftDB.config

	if cmd == "" then
		ns.UI.Toggle()
	elseif cmd == "scan" then
		Rescan()
	elseif cmd == "venda" or cmd == "custo" then
		if rest == "" then ShowHelp() return end
		if not ns.Pricing.Validate(rest) then
			ns.Print(L["string de preço inválida no TSM: "] .. rest)
			return
		end
		cfg[cmd == "venda" and "saleSource" or "costSource"] = rest
		ns.Print((cmd == "venda" and L["Venda"] or L["Custo"]) .. " = " .. rest)
		Rescan()
	elseif cmd == "qualidade" then
		if rest:lower() == "auto" then
			cfg.outputQuality = nil
			ns.Print(L["qualidade do item final = auto (pela sua skill)"])
			Rescan()
			return
		end
		local q = tonumber(rest)
		if not q or q < 1 or q > 5 then ShowHelp() return end
		cfg.outputQuality = math.floor(q)
		ns.Print(L["qualidade do item final = "] .. cfg.outputQuality)
		Rescan()
	elseif cmd == "abc" then
		local a, b = rest:match("^(%d+)%s+(%d+)$")
		a, b = tonumber(a), tonumber(b)
		if not a or not b or a <= 0 or b <= a or b > 100 then ShowHelp() return end
		cfg.abcA, cfg.abcB = a / 100, b / 100
		for _, entries in pairs(LucroCraftDB.chars) do
			for _, e in pairs(entries) do ns.Scanner.ApplyABC(e.rows) end
		end
		ns.Print(string.format(L["ABC: A até %d%%, B até %d%%"], a, b))
		ns.UI.Refresh()
	elseif cmd == "auto" then
		cfg.autoOpen = not IsOff(rest)
		ns.Print(L["abrir junto com a profissão: "] .. (cfg.autoOpen and "on" or "off"))
	elseif cmd == "audit" or cmd == "auditoria" then
		Audit(rest)
	elseif cmd == "log" then
		if rest:lower() == "limpar" or rest:lower() == "clear" then
			LucroCraftDB.log = {}
			ns.Print(L["log limpo."])
			return
		end
		local log = LucroCraftDB.log or {}
		ns.Print(string.format(L["últimas %d de %d linhas do log:"], math.min(20, #log), #log))
		for i = math.max(1, #log - 19), #log do print("  " .. log[i]) end
	elseif cmd == "debug" then
		cfg.debug = not IsOff(rest)
		ns.Print(L["debug (avisos no chat): "] .. (cfg.debug and "on" or "off"))
	elseif cmd == "investir" or cmd == "invest" then
		ns.Invest.Toggle()
	elseif cmd == "config" or cmd == "opcoes" then
		ns.UI.ShowTab(ns.UI.TAB.SETTINGS)
	elseif cmd == "giro" then
		local n = tonumber((rest:gsub(",", ".")))
		if not n or n < 0 or n > 100 then ns.Print(L["uso: /lucro giro <% mínimo das vendas da profissão>"]) return end
		cfg.recoMinShare = n / 100
		ns.Print(string.format(L["recomendações só para itens com pelo menos %.1f%% das vendas da profissão"], n))
		Rescan()
	elseif cmd == "recomendar" then
		local k = rest:upper()
		if k ~= "A" and k ~= "B" and k ~= "C" then ns.Print(L["uso: /lucro recomendar A|B|C (classes que entram no plano)"]) return end
		cfg.recoMinABC = k
		ns.Print(L["recomendações para classes até "] .. k)
		Rescan()
	elseif cmd == "regen" then
		local n = tonumber((rest:gsub(",", ".")))
		cfg.concPerHour = n
		ns.Print(n and (L["concentração regenera "] .. n .. "/h") or L["regeneração: aprendida pelos scans"])
	elseif cmd == "plano" or cmd == "conc" then
		ns.Plan.Toggle()
	elseif cmd == "compras" or cmd == "buy" then
		if tonumber(rest) and ns.Buy then ns.Buy.SetDays(tonumber(rest)) end
		ns.UI.ShowTab(ns.UI.TAB.BUY)
	elseif cmd == "vender" or cmd == "sell" then
		if tonumber(rest) and ns.Buy then ns.Buy.SetDays(tonumber(rest)) end
		ns.UI.ShowTab(ns.UI.TAB.SELL)
	elseif cmd == "fila" then
		ns.UI.ShowTab(ns.UI.TAB.QUEUE)
	elseif cmd == "vendas" or cmd == "historico" or cmd == "histórico" then
		-- vendas agora ficam no LucroLivro
		if ns.root and ns.root.Open then ns.root.Open("livro", 6)
		else ns.Print(L["as vendas agora ficam no addon Royal Revenue (/livro)."]) end
	elseif cmd == "leilao" or cmd == "leilão" or cmd == "ah" then
		if ns.Own then ns.Own.StartScan(true) end
	elseif cmd == "alertas" then
		ns.Alerts.Show(false)
	elseif cmd == "reprecificar" or cmd == "reprice" then
		ns.Scanner.RepriceAll(function() ns.Print(L["preços atualizados em todos os personagens."]) end)
	elseif cmd == "estoque" then
		local m = rest:lower()
		if m == "market" then m = "mercado" elseif m == "owned" then m = "estoque" end
		if m ~= "mercado" and m ~= "estoque" then ns.Print(L["uso: /lucro estoque mercado|estoque"]) return end
		cfg.costMode = m
		ns.Print(L["custo do que já está no estoque: "] .. L[m])
		ns.Scanner.RepriceAll()
	elseif cmd == "stats" or cmd == "fabricar" then
		local key = cmd == "stats" and "useStats" or "useCrafted"
		cfg[key] = not IsOff(rest)
		ns.Print((cmd == "stats" and "multicraft/resourcefulness/ingenuity" or L["reagentes fabricados"]) .. ": " .. (cfg[key] and "on" or "off"))
		Rescan()
	elseif cmd == "liquidez" then
		local n = tonumber((rest:gsub(",", ".")))
		if not n or n < 0 then ShowHelp() return end
		cfg.minSoldPerDay = n
		ns.Print(L["pouca venda = abaixo de "] .. n .. L[" vendas/dia"])
		Rescan()
	elseif cmd == "colunas" or cmd == "cols" then
		ns.UI.ColumnsCommand(rest)
	elseif cmd == "resetpos" then
		LucroCraftDB.pos = nil
		if ns.UI.IsShown() then ns.UI.Show() end
	elseif cmd == "reset" then
		LucroCraftDB = { config = {}, chars = {}, queue = { list = {} } }
		ns.Print(L["dados apagados."])
		ns.UI.Refresh()
	else
		ShowHelp()
	end
end
