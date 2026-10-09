local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- ===== Aba Compras =====
-- Só os materiais do Plano de concentração: o que comprar, quanto custa hoje e qual o melhor dia
-- (e horário, quando houver dados) para comprar.
--
-- De onde vem o histórico:
--  1. Auctionator: menor preço de cada dia (até 21 dias; já existe no primeiro uso).
--  2. Scan próprio do Royal Revenue (botão "Escanear AH"; também o histórico diário dele).
--  3. Buscas na casa de leilões (qualquer addon): menor preço do momento, com hora.
--  4. Varredura completa do Auctionator: quando o preço guardado muda, anota com a hora.
-- Dia da semana: cada dia é comparado com a média dos 7 dias em volta (tira a tendência de subida/queda).
local Buy = {}
ns.Buy = Buy

local P = ns.Pricing

local KEEP_SECS = 60 * 86400   -- guarda 60 dias
local MAX_SAMPLES = 400        -- por item
local MERGE_SECS = 600         -- amostras com menos de 10 min de diferença viram uma só (fica o menor preço)
local NOW_FRESH = 3 * 3600     -- amostra própria vale como "preço agora" por 3 h
local GREEN, RED = -0.04, 0.06 -- limites do selo (preço agora contra o típico)
local BANDS = 6                -- faixas de 4 horas

-- textos em inglês (o código é escrito em português)
if not ns.isPT then
	local T = {
		["Compras"] = "Purchases",
		["Materiais do Plano de concentração · melhor dia para comprar"] = "Concentration plan materials · best day to buy",
		["Comprar hoje"] = "Buy today",
		["No melhor dia"] = "On the best day",
		["Compre agora"] = "Buy now",
		["Histórico"] = "History",
		["Escanear AH"] = "Scan AH",
		["Lista no Auctionator"] = "Auctionator list",
		["Melhor dia para a lista toda"] = "Best day for the whole list",
		["Melhor horário"] = "Best time of day",
		["COMPRE"] = "BUY",
		["NORMAL"] = "NORMAL",
		["ESPERE"] = "WAIT",
		["VENDEDOR"] = "VENDOR",
		["SEM PREÇO"] = "NO PRICE",
		["já tem"] = "have it",
		["comprar %s"] = "buy %s",
		["precisa %s · tem %s"] = "need %s · have %s",
		["precisa %s · tem %s · bando %s"] = "need %s · have %s · warband %s",
		["%d dias"] = "%d days",
		["materiais"] = "materials",
		["economia %s"] = "saves %s",
		["poucos dados"] = "little data",
		["sem dados"] = "no data",
		["Nada para comprar: o plano não tem fabricações ou falta abrir as profissões."] = "Nothing to buy: the plan has no crafts or the professions haven't been scanned.",
		["Você já tem tudo o que o plano precisa."] = "You already have everything the plan needs.",
		["Preço agora"] = "Price now",
		["Preço típico (7 dias)"] = "Typical price (7 days)",
		["Diferença"] = "Difference",
		["Melhor dia"] = "Best day",
		["Dias com preço"] = "Days with price",
		["Amostras com hora"] = "Samples with time",
		["Fonte do preço agora"] = "Source of the price now",
		["sua busca/scan"] = "your search/scan",
		["Auctionator (hoje)"] = "Auctionator (today)",
		["fonte de preços"] = "price source",
		["Precisa"] = "Need",
		["Tem (bolsa + banco)"] = "Have (bags + bank)",
		["Banco do bando usado"] = "Warband bank used",
		["Nos alts"] = "On alts",
		["Comprar"] = "Buy",
		["Usado em"] = "Used in",
		["Barras: quanto o preço do dia fica acima (vermelho) ou abaixo (verde) da média da semana."] = "Bars: how far the day's price is above (red) or below (green) the week's average.",
		["Cada dia é comparado com a média dos 7 dias em volta, para não confundir tendência com dia da semana."] = "Each day is compared with the average of the 7 days around it, so a trend isn't mistaken for a weekday effect.",
		["Com menos de 2 semanas de dados o padrão ainda é fraco."] = "With less than 2 weeks of data the pattern is still weak.",
		["Preço do vendedor: não muda com o dia."] = "Vendor price: doesn't change by day.",
		["Sem preço na casa de leilões."] = "No auction house price.",
		["Custo da lista em cada dia (preço típico × padrão do dia)"] = "List cost on each day (typical price × day pattern)",
		["hoje"] = "today",
		["Precisa de amostras com hora: faça buscas ou scans na casa de leilões em horários diferentes."] = "Needs timed samples: search or scan the auction house at different times.",
		["Faixa"] = "Band",
		["amostras"] = "samples",
		["Ponderado pelo custo de cada material da lista."] = "Weighted by each material's cost in the list.",
		["Abra a casa de leilões: lê o mercado inteiro (1 vez a cada 15 min) e guarda o preço com dia e hora."] = "Open the auction house: reads the whole market (once every 15 min) and stores the price with day and time.",
		["Cria a lista \"Royal Revenue - Compras\" no Auctionator com o que falta comprar."] = "Creates the \"Royal Revenue - Shopping\" list in Auctionator with what's left to buy.",
		["lista \"%s\" criada no Auctionator com %d itens."] = "list \"%s\" created in Auctionator with %d items.",
		["Royal Revenue - Compras"] = "Royal Revenue - Shopping",
		["materiais com preço abaixo do típico agora"] = "materials priced below typical now",
		["dias com preço (Auctionator + suas buscas e scans)"] = "days with price (Auctionator + your searches and scans)",
		["Verde = abaixo do típico (compre). Amarelo = normal. Vermelho = acima (espere o melhor dia)."] = "Green = below typical (buy). Yellow = normal. Red = above (wait for the best day).",
		["espere: %s"] = "wait: %s",
		["Planejado"] = "Planned",
		["%dx %s"] = "%dx %s",
		["Materiais que já tem"] = "Materials you already have",
		["hoje já está mais barato: compre agora"] = "today is already cheaper: buy now",
		["agora há pouco"] = "just now",
		["há %d min"] = "%d min ago",
		["há %d h"] = "%d h ago",
		["há %d dias"] = "%d days ago",
		["aguardando o servidor... %d s"] = "waiting for the server... %d s",
		["lendo %d%%"] = "reading %d%%",
		["último scan %s"] = "last scan %s",
		["nenhum scan ainda"] = "no scan yet",
		["1. Pedido enviado: o servidor prepara a lista (costuma levar de alguns segundos a 1 min)."] = "1. Request sent: the server prepares the list (usually a few seconds to 1 min).",
		["2. Lendo os anúncios: %d de %d."] = "2. Reading the listings: %d of %d.",
		["Último scan"] = "Last scan",
		["Próximo scan liberado em"] = "Next scan allowed in",
		["%d min"] = "%d min",
		["A casa de leilões está fechada."] = "The auction house is closed.",
		["Ao terminar, o chat avisa quantos anúncios foram lidos e a aba é atualizada."] = "When it finishes, chat shows how many listings were read and the tab refreshes.",
		["Escaneando..."] = "Scanning...",
		["Escanear (%d min)"] = "Scan (%d min)",
		["Comprar para:"] = "Buy for:",
		["agora"] = "now",
		["1 dia"] = "1 day",
		["Só a concentração que você tem agora (o mesmo do Plano de concentração)."] = "Only the concentration you have now (same as the Concentration plan).",
		["Concentração de agora + o que regenera em %d dia(s) (~%d por profissão)."] = "Concentration now + what regenerates in %d day(s) (~%d per profession).",
		["Supõe que você fabrica antes de a barra encher (1000)."] = "Assumes you craft before the bar fills up (1000).",
		["lucro previsto: %s"] = "expected profit: %s",
		["concentração de agora"] = "concentration now",
		["para 1 dia de craft"] = "for 1 day of crafting",
		["para %d dias de craft"] = "for %d days of crafting",
		["Concentração usada"] = "Concentration used",
		["%d (agora ~%d + %d regenerando)"] = "%d (now ~%d + %d regenerating)",
		["|cff9d9d9d%d fabricações · lucro %s|r"] = "|cff9d9d9d%d crafts · profit %s|r",
	}
	for k, v in pairs(T) do L[k] = v end
end

local WD_SHORT = ns.isPT and { "Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb" } or { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local WD_LONG = ns.isPT and { "domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado" }
	or { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local BAND_TXT = { "0-4h", "4-8h", "8-12h", "12-16h", "16-20h", "20-24h" }
Buy.WD_SHORT, Buy.WD_LONG = WD_SHORT, WD_LONG

-- ===== dados =====
local function DB()
	LucroCraftDB.buyHist = LucroCraftDB.buyHist or {}
	local d = LucroCraftDB.buyHist
	d.items = d.items or {}
	d.atrM = d.atrM or {}
	return d
end

-- número do dia local (meio-dia local / 86400) e dia da semana (1 = domingo)
local dayCache = {}
local function DayNum(t)
	local h = math.floor(t / 3600)
	local v = dayCache[h]
	if v then return v end
	local d = date("*t", t)
	v = math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
	dayCache[h] = v
	return v
end
local function WeekdayOf(dn)
	return date("*t", dn * 86400 + 43200).wday
end
Buy.DayNum, Buy.WeekdayOf = DayNum, WeekdayOf

-- guarda uma amostra (preço mínimo em cobre) com a hora
function Buy.Record(id, price, t)
	if not id or not price or price <= 0 then return end
	t = t or time()
	local items = DB().items
	local it = items[id]
	if not it then it = { t = {}, p = {} }; items[id] = it end
	local n = #it.t
	if n > 0 and math.abs(t - it.t[n]) < MERGE_SECS then
		if price < it.p[n] then it.p[n] = math.floor(price + 0.5) end
		return
	end
	it.t[n + 1], it.p[n + 1] = t, math.floor(price + 0.5)
	-- limpa o velho
	local cut = t - KEEP_SECS
	local drop = 0
	while drop < #it.t and (it.t[drop + 1] < cut or (#it.t - drop) > MAX_SAMPLES) do drop = drop + 1 end
	if drop > 0 then
		local nt, np = {}, {}
		for i = drop + 1, #it.t do nt[#nt + 1], np[#np + 1] = it.t[i], it.p[i] end
		it.t, it.p = nt, np
	end
end

-- ===== itens acompanhados: reagentes de todas as receitas salvas =====
local tracked, trackedAt
function Buy.Tracked()
	if tracked and trackedAt and time() - trackedAt < 60 then return tracked end
	tracked = {}
	for _, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			for _, r in ipairs(e.rows or {}) do
				-- saídas (aba Vender)
				if r.itemID then tracked[r.itemID] = true end
				if r.concItemID then tracked[r.concItemID] = true end
				for _, p in ipairs(r.parts or {}) do
					if p.itemID then tracked[p.itemID] = true end
					if p.buyItem then tracked[p.buyItem] = true end
					for _, id in ipairs(p.qualityItems or {}) do tracked[id] = true end
				end
			end
		end
	end
	if Buy.ExtraTracked then
		local ok, extra = pcall(Buy.ExtraTracked)
		if ok and extra then for id in pairs(extra) do tracked[id] = true end end
	end
	trackedAt = time()
	return tracked
end

function Buy.RecordScan(acc)
	local now, tr = time(), Buy.Tracked()
	for id, a in pairs(acc or {}) do
		if tr[id] and a.min then Buy.Record(id, a.min, now) end
	end
end

-- ===== Auctionator =====
local function Atr() return Auctionator and Auctionator.Database end
local function AtrDay0()
	local c = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
	return c or time({ year = 2020, month = 1, day = 1, hour = 0 })
end

-- varredura do Auctionator: o preço guardado (m) mudou desde a última leitura = preço novo, com a hora de agora
function Buy.ReadAuctionator(baselineOnly)
	local db = Atr()
	if not (db and db.GetPrice and db.GetPriceAge) then return end
	local d, now = DB(), time()
	for id in pairs(Buy.Tracked()) do
		local key = tostring(id)
		local okA, age = pcall(db.GetPriceAge, db, key)
		if okA and age == 0 then
			local okP, m = pcall(db.GetPrice, db, key)
			if okP and type(m) == "number" and m > 0 then
				if d.atrM[id] ~= m then
					if not baselineOnly and d.atrM[id] ~= nil then Buy.Record(id, m, now) end
					d.atrM[id] = m
				end
			end
		end
	end
end

-- ===== série diária (menor preço de cada dia) =====
local function DailySeries(id)
	local daily = {}
	local function put(dn, v)
		if v and v > 0 and (not daily[dn] or v < daily[dn]) then daily[dn] = v end
	end
	-- Auctionator
	local db = Atr()
	if db and db.GetPriceHistory then
		local ok, hist = pcall(db.GetPriceHistory, db, tostring(id))
		if ok and type(hist) == "table" then
			local day0 = AtrDay0()
			for _, h in ipairs(hist) do
				local raw = tonumber(h.rawDay)
				if raw then put(DayNum(day0 + raw * 86400 + 43200), h.minSeen or h.maxSeen) end
			end
		end
	end
	-- scan próprio (dia UTC)
	local realm = GetRealmName and ((GetRealmName() or "?"):gsub("[%s%-']", "")) or "?"
	local own = LucroCraftDB.ah and LucroCraftDB.ah[realm] and LucroCraftDB.ah[realm].items[id]
	if own and own.d then
		for d, v in pairs(own.d) do
			local n = tonumber(d)
			if n and v.l then put(DayNum(n * 86400 + 43200), v.l) end
		end
	end
	-- amostras com hora
	local it = DB().items[id]
	if it then
		for i = 1, #it.t do put(DayNum(it.t[i]), it.p[i]) end
	end
	return daily, it
end

-- Histórico completo de um item, dia a dia (aba Vender, parte de baixo):
-- { days = { [dn] = { min, max, avail, src = { atr, own, samp }, samples = { {t, p}, ... } } }, first, last }
function Buy.History(id)
	local out, first, last = {}, nil, nil
	local function day(dn)
		local d = out[dn]
		if not d then
			d = { src = {}, samples = {} }
			out[dn] = d
			if not first or dn < first then first = dn end
			if not last or dn > last then last = dn end
		end
		return d
	end
	local function price(d, v)
		if not v or v <= 0 then return end
		if not d.min or v < d.min then d.min = v end
		if not d.max or v > d.max then d.max = v end
	end
	local db = Atr()
	if db and db.GetPriceHistory then
		local ok, hist = pcall(db.GetPriceHistory, db, tostring(id))
		if ok and type(hist) == "table" then
			local day0 = AtrDay0()
			for _, h in ipairs(hist) do
				local raw = tonumber(h.rawDay)
				if raw then
					local d = day(DayNum(day0 + raw * 86400 + 43200))
					price(d, h.minSeen); price(d, h.maxSeen)
					if h.available then d.avail = math.max(d.avail or 0, h.available) end
					d.src.atr = true
				end
			end
		end
	end
	local realm = GetRealmName and ((GetRealmName() or "?"):gsub("[%s%-']", "")) or "?"
	local own = LucroCraftDB.ah and LucroCraftDB.ah[realm] and LucroCraftDB.ah[realm].items[id]
	if own and own.d then
		for k, v in pairs(own.d) do
			local n = tonumber(k)
			if n and v.l then
				local d = day(DayNum(n * 86400 + 43200))
				price(d, v.l)
				if v.a then d.avail = math.max(d.avail or 0, v.a) end
				d.src.own = true
			end
		end
	end
	local it = DB().items[id]
	if it then
		for i = 1, #it.t do
			local d = day(DayNum(it.t[i]))
			price(d, it.p[i])
			table.insert(d.samples, { t = it.t[i], p = it.p[i] })
			d.src.samp = true
		end
	end
	return { days = out, first = first, last = last }
end

-- média dos dias com preço em [dn-3, dn+3]; precisa de 4 dias
-- mediana (resiste a anúncio absurdo: 11.111g num item que vale 20g)
local function Median(t)
	local n = #t
	if n == 0 then return nil end
	table.sort(t)
	if n % 2 == 1 then return t[(n + 1) / 2] end
	return (t[n / 2] + t[n / 2 + 1]) / 2
end
Buy.Median = Median
local function Around(daily, dn)
	local t = {}
	for k = dn - 3, dn + 3 do
		local v = daily[k]
		if v then t[#t + 1] = v end
	end
	if #t < 4 then return nil end
	return Median(t)
end
-- razão de um dia contra os dias em volta, em log e limitada a 1/3..3x (um dia maluco não domina a média)
local LOG3 = math.log(3)
local function LogRatio(v, m) return math.max(-LOG3, math.min(LOG3, math.log(v / m))) end
local OUTLIER = 2.5   -- preço agora acima de 2,5x o típico = anúncio fora da realidade

-- Análise de um item: padrão por dia da semana e por faixa de horário, preço típico e preço agora
local cache = {}
function Buy.Analyze(id)
	local c = cache[id]
	if c then return c end
	local daily, samples = DailySeries(id)
	local today = DayNum(time())
	local a = { id = id, days = 0, wd = {}, band = {}, timed = 0 }
	for w = 1, 7 do a.wd[w] = { s = 0, n = 0 } end
	for b = 1, BANDS do a.band[b] = { s = 0, n = 0, days = {} } end
	local recent = {}
	for dn, v in pairs(daily) do
		a.days = a.days + 1
		local m = Around(daily, dn)
		if m and m > 0 then
			local w = a.wd[WeekdayOf(dn)]
			w.s, w.n = w.s + LogRatio(v, m), w.n + 1
		end
		if dn > today - 7 then recent[#recent + 1] = v end
	end
	-- índice do dia: média geométrica das razões, centrada (dias com dado somam 0 em log) → nunca abaixo de −100%
	local tot, cnt = 0, 0
	for w = 1, 7 do
		local x = a.wd[w]
		if x.n > 0 then x.lg = x.s / x.n; tot = tot + x.lg; cnt = cnt + 1 end
	end
	if cnt > 0 then
		local mean = tot / cnt
		for w = 1, 7 do local x = a.wd[w]; if x.lg then x.idx = math.exp(x.lg - mean) - 1 end end
	end
	a.covered = cnt
	local minWd = 99
	for w = 1, 7 do
		local x = a.wd[w]
		if x.n > 0 and x.n < minWd then minWd = x.n end
		if x.idx and (not a.best or x.idx < a.wd[a.best].idx) then a.best = w end
	end
	a.conf = (a.days >= 14 and cnt == 7 and minWd >= 2) and "ok" or (cnt >= 4) and "low" or "none"
	for w = 1, 7 do
		local x = a.wd[w]
		if x.idx and (not a.bestSell or x.idx > a.wd[a.bestSell].idx) then a.bestSell = w end
	end
	if a.conf == "none" then a.best, a.bestSell = nil, nil end
	-- faixa de horário: amostras com hora contra a média dos dias em volta
	if samples then
		for i = 1, #samples.t do
			local t = samples.t[i]
			local m = Around(daily, DayNum(t))
			if m and m > 0 then
				local b = a.band[math.floor(tonumber(date("%H", t)) / 4) + 1]
				b.s, b.n = b.s + math.exp(LogRatio(samples.p[i], m)), b.n + 1
				b.days[DayNum(t)] = true
				a.timed = a.timed + 1
			end
		end
	end
	-- preço típico: média dos últimos 7 dias; sem isso, a referência da fonte de preços
	a.typical = Median(recent) or P.Reference(id) or P.Cost(id)
	-- preço agora
	local now = time()
	if samples and #samples.t > 0 and now - samples.t[#samples.t] < NOW_FRESH then
		a.now, a.nowSrc = samples.p[#samples.t], "own"
	else
		local db = Atr()
		if db and db.GetPriceAge then
			local okA, age = pcall(db.GetPriceAge, db, tostring(id))
			if okA and age == 0 then
				local okP, m = pcall(db.GetPrice, db, tostring(id))
				if okP and type(m) == "number" and m > 0 then a.now, a.nowSrc = m, "atr" end
			end
		end
		if not a.now then
			local m = P.MarketNow(id)
			if m and m > 0 then a.now, a.nowSrc = m, "src" end
		end
	end
	if not a.now then a.now, a.nowSrc = P.Cost(id), "src" end
	-- vendedor
	local vendor = P.VendorBuy(id)
	if vendor and vendor > 0 and (not a.now or vendor <= a.now) then
		a.vendor, a.now, a.typical = vendor, vendor, vendor
	end
	-- anúncio fora da realidade (mercado vazio, alguém pôs 11.111g): não é o preço do item
	a.outlier = (not a.vendor and a.now and a.typical and a.typical > 0 and a.now > a.typical * OUTLIER) or nil
	-- selo
	if a.vendor then
		a.signal = "vendor"
	elseif not a.now then
		a.signal = "none"
	else
		a.diff = (a.typical and a.typical > 0) and (a.now / a.typical - 1) or 0
		local todayWd = WeekdayOf(today)
		if a.diff <= GREEN or (a.best == todayWd and a.diff <= 0.02) then
			a.signal = "buy"
		elseif a.diff >= RED then
			a.signal = "wait"
		else
			a.signal = "normal"
		end
	end
	cache[id] = a
	return a
end

-- ===== dias de craft =====
-- 0 = só a concentração de agora; N = agora + o que regenera em N dias
Buy.DAY_CHOICES = { 0, 1, 2, 3, 5, 7, 14 }
function Buy.Days()
	local v = tonumber(LucroCraftDB.config and LucroCraftDB.config.buyDays) or 0
	return math.max(0, math.min(30, math.floor(v)))
end
function Buy.SetDays(n)
	LucroCraftDB.config = LucroCraftDB.config or {}
	LucroCraftDB.config.buyDays = math.max(0, math.min(30, math.floor(tonumber(n) or 0)))
	Buy.Refresh()
	if ns.Sell and ns.Sell.Refresh then ns.Sell.Refresh() end
end

-- ===== lista de compras do plano, por personagem =====
function Buy.Build()
	wipe(cache)
	if ns.Plan.ResetCounts then ns.Plan.ResetCounts() end
	local C = ns.Plan.Count
	local days = Buy.Days()
	local list = ns.Plan.Build(days)
	local me = ns.CharKey()
	local groups, byChar = {}, {}
	for _, it in ipairs(list) do
		if not it.cook and it.used and #it.used > 0 then
			local g = byChar[it.char]
			if not g then
				g = { char = it.char, class = it.e.class, profs = {}, mats = {}, order = {}, cost = 0, gain = 0, crafts = 0 }
				byChar[it.char] = g
				table.insert(groups, g)
			end
			table.insert(g.profs, it)
			g.gain = g.gain + (it.gain or 0)
			for _, u in ipairs(it.used) do g.crafts = g.crafts + u.crafts end
			for _, u in ipairs(it.used) do
				for _, p in ipairs(u.row.parts or {}) do
					if p.qty and p.qty > 0 then
						local ids = (p.qualityItems and #p.qualityItems > 0) and p.qualityItems or { p.buyItem or p.itemID }
						local key = ids[1]
						if key then
							local m = g.mats[key]
							if not m then
								m = { key = key, ids = ids, buyId = p.buyItem or p.itemID or key, need = 0, uses = {} }
								g.mats[key] = m
								table.insert(g.order, m)
							end
							m.need = m.need + p.qty * u.crafts
							table.insert(m.uses, { row = u.row, crafts = u.crafts })
						end
					end
				end
			end
		end
	end
	-- logado primeiro, depois pelo lucro do plano
	table.sort(groups, function(a, b)
		if (a.char == me) ~= (b.char == me) then return a.char == me end
		return a.gain > b.gain
	end)
	-- fila de fabricação + pedidos (lidos e pegos): vem antes de tudo; estoque = bolsa + banco do bando
	if ns.Queue and ns.Queue.Shopping then
		local okS, shop = pcall(ns.Queue.Shopping)
		if okS and shop and #shop > 0 then
			local qg = { char = me, queue = true, profs = {}, mats = {}, order = {}, cost = 0, gain = 0, crafts = 0 }
			local okB, items = pcall(ns.Queue.ShopItems)
			if okB and items then for _, it in ipairs(items) do qg.crafts = qg.crafts + (it.n or 1) end end
			for _, x in ipairs(shop) do
				local m = { key = x.id, ids = { x.id }, buyId = x.id, need = x.need, uses = {}, own = x.bags or x.have, wb = x.wb or 0,
					alts = x.stock and x.stock.alts or 0, buy = x.buy, queue = true, byQ = x.byQ }
				table.insert(qg.order, m)
			end
			table.insert(groups, 1, qg)
		end
	end
	-- lista escolhida na barra: plano (só este personagem, ou todos marcando a opção) · fila · consumíveis
	local list = Buy.List()
	local allChars = LucroCraftDB.config.buyAllChars
	local kept = {}
	for _, g in ipairs(groups) do
		if list == "queue" and g.queue then table.insert(kept, g)
		elseif list == "plan" and not g.queue and (allChars or g.char == me) then table.insert(kept, g) end
	end
	groups = kept
	if list == "cons" then
		groups = Buy.ConsGroups(me, allChars)
		if ns.Consum then
			local okS, sg = pcall(ns.Consum.Groups, me, allChars, groups)
			if okS then for _, g in ipairs(sg) do table.insert(groups, g) end
			elseif ns.Log then ns.Log("sugestão de consumíveis: " .. tostring(sg)) end
		end
	end
	local craftMap = ns.Scanner.CraftMapAll and ns.Scanner.CraftMapAll() or {}
	-- banco do bando: um só para todos, gasto na ordem dos grupos
	local wbLeft = {}
	local res = { list = list, groups = groups, costNow = 0, costTyp = 0, nBuy = 0, nGreen = 0, items = {}, days = days, gain = 0 }
	for _, g in ipairs(groups) do res.gain = res.gain + g.gain end
	for _, g in ipairs(groups) do
		for _, m in ipairs(g.order) do
		  if not m.queue then
			local own, alts = 0, 0
			if wbLeft[m.key] == nil then
				local wb = 0
				for _, id in ipairs(m.ids) do wb = wb + C.warband(id) end
				wbLeft[m.key] = wb
			end
			for _, id in ipairs(m.ids) do
				own = own + C.own(g.char, id)
				alts = alts + C.alts(g.char, id)
			end
			local miss = math.max(0, m.need - own)
			local take = math.min(miss, wbLeft[m.key])
			wbLeft[m.key] = wbLeft[m.key] - take
			m.own, m.wb, m.alts, m.buy = own, take, alts, miss - take
		  end
			m.a = Buy.Analyze(m.buyId)
			-- comprar ou fabricar? o seu custo de fabricar (receita mais barata de qualquer personagem)
			local best
			for _, id in ipairs(m.ids) do
				local c = craftMap[id]
				if c and c.unit and c.unit > 0 and (not best or c.unit < best.unit) then best = { unit = c.unit, name = c.name, char = c.char, id = id } end
			end
			m.craft = best
			-- preço de referência da compra: o de agora; com anúncio absurdo, o típico
			local ref = m.a.outlier and m.a.typical or m.a.now
			if best and ref and ref > 0 then
				m.craftSave = (ref - best.unit) / ref
				m.craftBetter = best.unit < ref * 0.97
			elseif best and not ref then
				m.craftBetter = true
			end
			-- custo da linha: fabricando, o custo de fabricar; senão o preço de referência
			m.unitEff = (m.craftBetter and best and best.unit) or ref or 0
			m.cost = m.buy * m.unitEff
			m.costTyp = m.buy * (m.a.typical or m.a.now or 0)
			g.cost = g.cost + m.cost
			-- consumível com mais de uma qualidade: preço/selo/fabricar de cada uma (compra é uma OU outra)
			if m.variants and m.buy > 0 then
				m.vdata = {}
				for _, vid in ipairs(m.variants) do
					local va = Buy.Analyze(vid)
					local vc = craftMap[vid]
					local vbest = vc and vc.unit and vc.unit > 0 and { unit = vc.unit, name = vc.name, char = vc.char } or nil
					local vref = va.outlier and va.typical or va.now
					local vCraftBetter = vbest and vref and vref > 0 and vbest.unit < vref * 0.97
					local vUnitEff = (vCraftBetter and vbest and vbest.unit) or vref or 0
					table.insert(m.vdata, { id = vid, a = va, craft = vbest, craftBetter = vCraftBetter, cost = m.buy * vUnitEff })
				end
			end
			if m.buy > 0 then
				res.nBuy = res.nBuy + 1
				if m.a.signal == "buy" then res.nGreen = res.nGreen + 1 end
				res.costNow = res.costNow + m.cost
				res.costTyp = res.costTyp + m.costTyp
				table.insert(res.items, m)
			end
		end
		-- comprar primeiro; os que já tem vão para o fim
		table.sort(g.order, function(a, b)
			if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
			return a.cost > b.cost
		end)
	end
	-- padrão da lista toda: custo típico de cada material × índice do dia (sem dado = 0)
	res.wd = {}
	local anyData = false
	for w = 1, 7 do
		local s = 0
		for _, m in ipairs(res.items) do
			local x = m.a.conf ~= "none" and not m.a.vendor and m.a.wd[w].idx or 0
			if x ~= 0 then anyData = true end
			s = s + m.costTyp * (1 + x)
		end
		res.wd[w] = s
	end
	if anyData and res.costTyp > 0 then
		for w = 1, 7 do
			if not res.best or res.wd[w] < res.wd[res.best] then res.best = w end
		end
	end
	-- faixa de horário da lista: média ponderada pelo custo
	res.band = {}
	for b = 1, BANDS do
		local s, wsum, n, days = 0, 0, 0, {}
		for _, m in ipairs(res.items) do
			local x = m.a.band[b]
			if x.n > 0 and not m.a.vendor then
				local wgt = math.max(m.costTyp, 1)
				s, wsum, n = s + wgt * (x.s / x.n - 1), wsum + wgt, n + x.n
				for d in pairs(x.days) do days[d] = true end
			end
		end
		local nd = 0
		for _ in pairs(days) do nd = nd + 1 end
		res.band[b] = { idx = wsum > 0 and s / wsum or nil, n = n, days = nd }
	end
	-- centra as faixas com dado suficiente (3+ dias diferentes)
	local bs, bc = 0, 0
	for b = 1, BANDS do local x = res.band[b]; if x.idx and x.days >= 3 then bs, bc = bs + x.idx, bc + 1 end end
	if bc >= 2 then
		for b = 1, BANDS do
			local x = res.band[b]
			if x.idx and x.days >= 3 then
				x.idx = x.idx - bs / bc
				if not res.bestBand or x.idx < res.band[res.bestBand].idx then res.bestBand = b end
			else
				x.idx = nil
			end
		end
	else
		for b = 1, BANDS do res.band[b].idx = nil end
	end
	-- dias com dado (o maior entre os materiais)
	res.histDays = 0
	for _, m in ipairs(res.items) do if m.a.days > res.histDays then res.histDays = m.a.days end end
	return res
end

-- ===== andamento do scan da AH =====
local scanUI = {}
local ScanTip
local function Ago(secs)
	if secs < 60 then return L["agora há pouco"] end
	if secs < 3600 then return string.format(L["há %d min"], math.floor(secs / 60)) end
	if secs < 86400 then return string.format(L["há %d h"], math.floor(secs / 3600)) end
	return string.format(L["há %d dias"], math.floor(secs / 86400))
end
local function ScanText(st)
	if st.scanning and st.phase == "wait" then
		return string.format(L["aguardando o servidor... %d s"], st.waited), 0, { 0.17, 0.36, 0.66 }
	elseif st.scanning and st.phase == "read" then
		local f = st.n > 0 and st.i / st.n or 0
		return string.format(L["lendo %d%%"], math.floor(f * 100)), f, { 0.17, 0.36, 0.66 }
	elseif st.last and st.last > 0 then
		local txt = string.format(L["último scan %s"], Ago(time() - st.last))
		return txt, 1, st.cooldown > 0 and { 0.15, 0.6, 0.25 } or { 0.45, 0.45, 0.5 }
	end
	return L["nenhum scan ainda"], 0, { 0.45, 0.45, 0.5 }
end
ScanTip = function(tt)
	local st = ns.Own and ns.Own.ScanStatus and ns.Own.ScanStatus()
	tt:SetText(L["Escanear AH"])
	tt:AddLine(L["Abra a casa de leilões: lê o mercado inteiro (1 vez a cada 15 min) e guarda o preço com dia e hora."], 1, 1, 1, true)
	if not st then return end
	tt:AddLine(" ")
	if st.scanning and st.phase == "wait" then
		tt:AddLine(L["1. Pedido enviado: o servidor prepara a lista (costuma levar de alguns segundos a 1 min)."], 0.4, 0.8, 1, true)
	elseif st.scanning and st.phase == "read" then
		tt:AddLine(string.format(L["2. Lendo os anúncios: %d de %d."], st.i, st.n), 0.4, 0.8, 1, true)
	elseif st.last and st.last > 0 then
		tt:AddDoubleLine(L["Último scan"], date("%d/%m %H:%M", st.last), 1, 0.82, 0, 1, 1, 1)
		if st.cooldown > 0 then
			tt:AddDoubleLine(L["Próximo scan liberado em"], string.format(L["%d min"], math.ceil(st.cooldown / 60)), 1, 0.82, 0, 1, 1, 1)
		end
	end
	if not st.ahOpen and not st.scanning then tt:AddLine(L["A casa de leilões está fechada."], 1, 0.5, 0.2) end
	tt:AddLine(L["Ao terminar, o chat avisa quantos anúncios foram lidos e a aba é atualizada."], 0.7, 0.7, 0.7, true)
end
-- atualiza só a barra e o botão (sem redesenhar a aba); no fim do scan redesenha tudo
local wasScanning = false
function Buy.ScanProgress()
	local st = ns.Own and ns.Own.ScanStatus and ns.Own.ScanStatus()
	if not st then return end
	for _, ui in pairs(scanUI) do
		local bar, btn = ui.bar, ui.btn
		if bar and bar:IsShown() then
			local txt, f, col = ScanText(st)
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(f)
			bar:SetStatusBarColor(col[1], col[2], col[3])
			bar.text:SetText(txt)
		end
		if btn and btn:IsShown() then
			local label = st.scanning and L["Escaneando..."]
				or (st.cooldown > 0 and string.format(L["Escanear (%d min)"], math.ceil(st.cooldown / 60)))
				or L["Escanear AH"]
			btn:SetText(label)
		end
	end
	if wasScanning and not st.scanning then
		wasScanning = false
		Buy.Refresh()
		if ns.Sell and ns.Sell.Refresh then ns.Sell.Refresh() end
	end
	wasScanning = st.scanning and true or false
end

-- barra + botão do scan (cada aba guarda os seus)
function Buy.DrawScan(cv, key, x)
	local ui = scanUI[key] or {}
	scanUI[key] = ui
	ui.bar = cv:Bar(x, 2, 170, 16, 0, 1, { 0.17, 0.36, 0.66 }, "", nil, ScanTip)
	ui.btn = cv:Button(x + 176, 0, 120, 20, L["Escanear AH"], function() if ns.Own then ns.Own.StartScan(true) end end, ScanTip)
	Buy.ScanProgress()
end

-- ===== desenho =====
local G = function(c, col) return P.FormatGold(c, col) end
local function Pct(x)
	if not x then return "—" end
	local v = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
	if v == 0 then return "0%" end
	return (v > 0 and "+" or "") .. v .. "%"
end
local function PctColored(x)
	if not x then return "|cff9d9d9d—|r" end
	local s = Pct(x)
	if x <= -0.005 then return "|cff55ff55" .. s .. "|r" end
	if x >= 0.005 then return "|cffff5555" .. s .. "|r" end
	return "|cffffffff" .. s .. "|r"
end
-- cor de uma célula pelo índice (verde = mais barato, vermelho = mais caro)
local function CellColor(idx)
	if not idx then return 1, 1, 1, 0.06 end
	local a = math.min(0.85, 0.18 + math.abs(idx) * 9)
	if idx < 0 then return 0.15, 0.85, 0.25, a end
	return 0.9, 0.2, 0.2, a
end

local SIGNAL = {
	buy = { txt = "COMPRE", r = 0.15, g = 0.75, b = 0.25 },
	normal = { txt = "NORMAL", r = 0.85, g = 0.7, b = 0.1 },
	wait = { txt = "ESPERE", r = 0.85, g = 0.2, b = 0.2 },
	vendor = { txt = "VENDEDOR", r = 0.45, g = 0.45, b = 0.5 },
	none = { txt = "SEM PREÇO", r = 0.35, g = 0.35, b = 0.35 },
	craft = { txt = "FABRIQUE", r = 0.2, g = 0.5, b = 0.95 },
}

local function DayStripTip(a, title)
	return function(tt)
		tt:SetText(title or L["Melhor dia"])
		for w = 1, 7 do
			local x = a.wd[w]
			tt:AddDoubleLine(WD_LONG[w], x.idx and (PctColored(x.idx) .. string.format(" |cff9d9d9d(%d)|r", x.n)) or "|cff9d9d9d—|r",
				1, 0.82, 0, 1, 1, 1)
		end
		tt:AddLine(" ")
		tt:AddLine(L["Barras: quanto o preço do dia fica acima (vermelho) ou abaixo (verde) da média da semana."], 0.7, 0.7, 0.7, true)
		tt:AddLine(L["Cada dia é comparado com a média dos 7 dias em volta, para não confundir tendência com dia da semana."], 0.7, 0.7, 0.7, true)
		if a.conf ~= "ok" then tt:AddLine(L["Com menos de 2 semanas de dados o padrão ainda é fraco."], 1, 0.6, 0.1, true) end
	end
end

-- 7 células pequenas (uma por dia da semana)
local function MiniDays(cv, x, y, a, tip, sell)
	local todayWd = WeekdayOf(DayNum(time()))
	local best = sell and a.bestSell or a.best
	for w = 1, 7 do
		local cx = x + (w - 1) * 17
		local x0 = a.wd[w]
		if best == w then cv:Box(cx - 1, y - 1, 17, 22, 0.83, 0.69, 0.22, 0.9) end
		local v = a.conf ~= "none" and x0.idx or nil
		if v and sell then v = -v end
		local r, g, b, al = CellColor(v)
		cv:Box(cx, y, 15, 20, 0.08, 0.13, 0.24, 1)
		cv:Box(cx, y, 15, 20, r, g, b, al)
		cv:Text(cx, y + 4, (w == todayWd and "|cffffffff" or "|cffb0b0b0") .. WD_SHORT[w]:sub(1, 1) .. "|r", GameFontHighlightSmall, 15, "CENTER")
	end
	cv:Hit(x, y, 7 * 17, 20, nil, tip)
end

local function MatTip(m)
	local a = m.a
	return function(tt)
		tt:SetItemByID(m.buyId)
		tt:AddLine(" ")
		tt:AddDoubleLine(L["Precisa"], root.Num(m.need, 0), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L["Tem (bolsa + banco)"], root.Num(m.own, 0), 1, 0.82, 0, 1, 1, 1)
		if m.wb > 0 then tt:AddDoubleLine(L["Banco do bando usado"], root.Num(m.wb, 0), 1, 0.82, 0, 1, 1, 1) end
		if m.alts > 0 then tt:AddDoubleLine(L["Nos alts"], root.Num(m.alts, 0), 1, 0.82, 0, 1, 1, 1) end
		tt:AddDoubleLine(L["Comprar"], root.Num(m.buy, 0), 1, 0.82, 0, 0.4, 0.8, 1)
		if m.why then tt:AddLine(" "); tt:AddLine(m.note or "", 0.4, 0.8, 1); tt:AddLine(m.why, 1, 1, 1, true) end
		if m.byQ and #m.byQ > 1 or (m.byQ and m.byQ[1] and m.byQ[1].id ~= m.buyId) then
			tt:AddLine(L["Conta qualquer qualidade do reagente:"], 0.6, 0.6, 0.6)
			for _, q in ipairs(m.byQ) do
				local qi = ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(q.id)
				tt:AddDoubleLine("   " .. (qi and ns.QIcon(qi, 2, 12) or "") .. " " .. (C_Item.GetItemNameByID(q.id) or q.id), tostring(q.n), 1, 1, 1, 1, 1, 1)
			end
		end
		if m.usedQ then
			tt:AddDoubleLine(L["Usou"], string.format(L["%d em %.0f dias"], m.usedQ, m.usedDays or 14), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Para repor"], string.format(L["%d dias"], Buy.ConsDays()), 1, 0.82, 0, 1, 1, 1)
		end
		tt:AddLine(" ")
		if a.vendor then
			tt:AddLine(L["Preço do vendedor: não muda com o dia."], 0.7, 0.7, 0.7, true)
		else
			tt:AddDoubleLine(L["Preço agora"], a.now and P.FormatMoney(a.now) or "—", 1, 0.82, 0, 1, 1, 1)
			local src = a.nowSrc == "own" and L["sua busca/scan"] or a.nowSrc == "atr" and L["Auctionator (hoje)"] or L["fonte de preços"]
			tt:AddDoubleLine(L["Fonte do preço agora"], src, 1, 0.82, 0, 0.7, 0.7, 0.7)
			tt:AddDoubleLine(L["Preço típico (7 dias)"], a.typical and P.FormatMoney(a.typical) or "—", 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Diferença"], PctColored(a.diff), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Melhor dia"], a.best and (WD_LONG[a.best] .. " " .. PctColored(a.wd[a.best].idx)) or L["sem dados"], 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Dias com preço"], root.Num(a.days, 0), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Amostras com hora"], root.Num(a.timed, 0), 1, 0.82, 0, 1, 1, 1)
		end
		tt:AddLine(" ")
		tt:AddLine(L["Usado em"], 1, 0.82, 0)
		local seen = {}
		for _, u in ipairs(m.uses) do
			local k = u.row.recipeID or u.row.name
			if not seen[k] then
				seen[k] = true
				tt:AddLine(string.format(L["%dx %s"], u.crafts, u.row.name or "?"), 1, 1, 1)
			end
		end
	end
end

local function Card(cv, x, y, w, label, value, sub)
	cv:Box(x, y, w, 46, 0.17, 0.36, 0.66, 0.18)
	cv:Box(x, y, 3, 46, 0.83, 0.69, 0.22, 0.9)
	cv:Text(x + 10, y + 5, "|cff9d9d9d" .. label .. "|r", GameFontDisableSmall, w - 14)
	cv:Text(x + 10, y + 19, value, GameFontNormalLarge, w - 14)
	if sub then cv:Text(x + 10, y + 34, sub, GameFontDisableSmall, w - 14) end
end

-- seletor de dias de craft (compartilhado: Compras e Vender usam o mesmo valor)
function Buy.DrawDays(cv, y, W, res, title)
	cv:Text(8, y + 4, title, GameFontHighlightSmall, 96)
	local bx = 104
	local cur = res.days
	for _, d in ipairs(Buy.DAY_CHOICES) do
		local label = d == 0 and L["agora"] or d == 1 and L["1 dia"] or string.format(L["%d dias"], d)
		if d == cur then cv:Box(bx - 2, y - 2, 64, 24, 0.83, 0.69, 0.22, 0.95) end
		cv:Button(bx, y, 60, 20, d == cur and ("|cffffffff" .. label .. "|r") or label, function() Buy.SetDays(d) end, function(tt)
			tt:SetText(label)
			if d == 0 then
				tt:AddLine(L["Só a concentração que você tem agora (o mesmo do Plano de concentração)."], 1, 1, 1, true)
			else
				tt:AddLine(string.format(L["Concentração de agora + o que regenera em %d dia(s) (~%d por profissão)."], d,
					math.floor(d * 24 * (ns.Plan.Rate and ns.Plan.Rate() or 10.5) + 0.5)), 1, 1, 1, true)
				tt:AddLine(L["Supõe que você fabrica antes de a barra encher (1000)."], 0.7, 0.7, 0.7, true)
			end
		end)
		bx = bx + 66
	end
	-- dias fora da lista (ex.: /rr compras 10)
	local inList = false
	for _, d in ipairs(Buy.DAY_CHOICES) do if d == cur then inList = true end end
	if not inList then
		cv:Box(bx - 2, y - 2, 64, 24, 0.83, 0.69, 0.22, 0.95)
		cv:Text(bx, y + 4, "|cffffffff" .. string.format(L["%d dias"], cur) .. "|r", GameFontHighlightSmall, 60, "CENTER")
		bx = bx + 66
	end
	if res.gain and res.gain > 0 then
		cv:Text(bx + 8, y + 4, string.format(L["lucro previsto: %s"], G(res.gain, true)), GameFontHighlightSmall, W - bx - 16)
	end
	return y + 30
end

function Buy.Render(cv)
	local res = Buy.Build()
	local W = cv:Width()
	cv:Begin()
	local TITLE = { plan = L["Materiais do Plano de concentração · melhor dia para comprar"], queue = L["Materiais da fila de craft e dos pedidos"],
		cons = L["Consumíveis e outros itens"] }
	cv:Text(8, 4, TITLE[res.list] or "", GameFontNormal, W - 460)
	-- andamento do scan da AH (atualizado ao vivo por Buy.ScanProgress)
	Buy.DrawScan(cv, "buy", W - 446)
	if Buy.AHOpen() then
		cv:Text(W - 146, 4, L["|cff55ff55casa de leilões aberta|r"], GameFontHighlightSmall, 140, "RIGHT")
	else
		cv:Text(W - 146, 4, L["|cff9d9d9dabra a casa de leilões para comprar|r"], GameFontDisableSmall, 140, "RIGHT")
	end
	local y = Buy.DrawListBar(cv, 26, W, res)
	if res.list == "cons" then y = Buy.DrawConsOptions(cv, y, W) end
	if res.list == "plan" then y = Buy.DrawDays(cv, y, W, res, L["Comprar para:"]) end
	if #res.groups == 0 and res.list == "cons" then
		-- nada registrado: mostra só o token (como antes)
		return Buy.RenderCons(cv, y, W)
	end
	if #res.groups == 0 then
		local msg = res.list == "queue" and L["Nada para comprar: a fila e os pedidos estão vazios (ou você já tem tudo)."]
			or (not LucroCraftDB.config.buyAllChars and L["Nada para comprar neste personagem: marque \"Mostrar todos os personagens\" ou abra as profissões."])
			or L["Nada para comprar: o plano não tem fabricações ou falta abrir as profissões."]
		cv:Text(8, y, msg, GameFontHighlight, W - 16)
		if cv._buyList then cv._buyList:Hide() end
		cv:End(y + 30)
		return
	end

	-- cartões
	local cw = math.floor((W - 8 - 3 * 8) / 4)
	local bestCost = res.best and res.wd[res.best]
	local forTxt = res.days == 0 and L["concentração de agora"] or res.days == 1 and L["para 1 dia de craft"] or string.format(L["para %d dias de craft"], res.days)
	Card(cv, 4, y, cw, L["Comprar hoje"], G(res.costNow, true), res.nBuy .. " " .. L["materiais"] .. " · " .. forTxt)
	Card(cv, 4 + (cw + 8), y, cw, L["No melhor dia"] .. (res.best and (" · " .. WD_LONG[res.best]) or ""),
		bestCost and G(bestCost, true) or "|cff9d9d9d—|r",
		bestCost and (res.costNow > bestCost and string.format(L["economia %s"], G(res.costNow - bestCost)) or L["hoje já está mais barato: compre agora"]) or L["poucos dados"])
	Card(cv, 4 + 2 * (cw + 8), y, cw, L["Compre agora"], string.format("|cff55ff55%d|r / %d", res.nGreen, res.nBuy),
		L["materiais com preço abaixo do típico agora"])
	Card(cv, 4 + 3 * (cw + 8), y, cw, L["Histórico"], string.format(L["%d dias"], res.histDays),
		L["dias com preço (Auctionator + suas buscas e scans)"])
	y = y + 56

	if res.nBuy == 0 then
		cv:Text(8, y, "|cff55ff55" .. L["Você já tem tudo o que o plano precisa."] .. "|r", GameFontHighlight)
		y = y + 24
	else
		-- faixa: custo da lista em cada dia da semana
		cv:Text(8, y, L["Melhor dia para a lista toda"], GameFontNormal)
		y = y + 18
		local todayWd = WeekdayOf(DayNum(time()))
		local dw = math.floor((W - 8 - 6 * 6) / 7)
		local maxDev = 0.005
		if res.best then
			for w = 1, 7 do maxDev = math.max(maxDev, math.abs(res.wd[w] / res.costTyp - 1)) end
		end
		for w = 1, 7 do
			local x = 4 + (w - 1) * (dw + 6)
			local dev = res.best and (res.wd[w] / res.costTyp - 1) or nil
			if res.best == w then cv:Box(x - 2, y - 2, dw + 4, 58, 0.83, 0.69, 0.22, 0.9) end
			cv:Box(x, y, dw, 54, 0.08, 0.13, 0.24, 1)
			local r, g, b, al = CellColor(dev)
			-- barra: altura pelo tamanho do desvio
			local bh = dev and math.max(3, math.floor(30 * math.abs(dev) / maxDev)) or 0
			if bh > 0 then cv:Box(x + 6, y + 48 - bh, dw - 12, bh, r, g, b, math.max(al, 0.5)) end
			local name = (w == todayWd) and ("|cffffffff" .. WD_SHORT[w] .. "|r |cff9d9d9d(" .. L["hoje"] .. ")|r") or ("|cffd9dde3" .. WD_SHORT[w] .. "|r")
			cv:Text(x, y + 3, name, GameFontHighlightSmall, dw, "CENTER")
			cv:Text(x, y + 16, dev and PctColored(dev) or "|cff9d9d9d—|r", GameFontNormal, dw, "CENTER")
			cv:Hit(x, y, dw, 54, nil, function(tt)
				tt:SetText(WD_LONG[w])
				tt:AddLine(L["Custo da lista em cada dia (preço típico × padrão do dia)"], 0.7, 0.7, 0.7, true)
				tt:AddDoubleLine(L["Comprar"], res.best and G(res.wd[w]) or "—", 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L["Diferença"], PctColored(dev), 1, 0.82, 0, 1, 1, 1)
				tt:AddLine(L["Ponderado pelo custo de cada material da lista."], 0.7, 0.7, 0.7, true)
				if res.histDays < 14 then tt:AddLine(L["Com menos de 2 semanas de dados o padrão ainda é fraco."], 1, 0.6, 0.1, true) end
			end)
		end
		y = y + 62

		-- faixa de horário
		cv:Text(8, y, L["Melhor horário"], GameFontNormal)
		if res.bestBand then
			local bw = math.floor((W - 120 - 5 * 4) / BANDS)
			for b = 1, BANDS do
				local x = 116 + (b - 1) * (bw + 4)
				local band = res.band[b]
				if res.bestBand == b then cv:Box(x - 2, y - 2, bw + 4, 22, 0.83, 0.69, 0.22, 0.9) end
				cv:Box(x, y, bw, 18, 0.08, 0.13, 0.24, 1)
				local r, g, bb, al = CellColor(band.idx)
				cv:Box(x, y, bw, 18, r, g, bb, al)
				cv:Text(x, y + 3, BAND_TXT[b] .. "  " .. (band.idx and PctColored(band.idx) or "|cff9d9d9d—|r"), GameFontHighlightSmall, bw, "CENTER")
				cv:Hit(x, y, bw, 18, nil, function(tt)
					tt:SetText(L["Faixa"] .. " " .. BAND_TXT[b])
					tt:AddDoubleLine(L["Diferença"], PctColored(band.idx), 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L["amostras"], string.format("%d · %s", band.n, string.format(L["%d dias"], band.days)), 1, 0.82, 0, 1, 1, 1)
				end)
			end
		else
			cv:Text(116, y + 2, "|cff9d9d9d" .. L["Precisa de amostras com hora: faça buscas ou scans na casa de leilões em horários diferentes."] .. "|r", GameFontDisableSmall, W - 124)
		end
		y = y + 28
		cv:Text(8, y, "|cff9d9d9d" .. L["Verde = abaixo do típico (compre). Amarelo = normal. Vermelho = acima (espere o melhor dia)."] .. "|r", GameFontDisableSmall, W - 16)
		y = y + 18
	end

	-- grupos por personagem
	local X_ICON, X_NAME, X_PRICE, X_SIG, X_DAYS, X_COST = 8, 48, 300, 430, 520, W - 144   -- lista fica numa área com barra (14 px)
	local ROW_H = 40
	-- material selecionado (histórico de preço embaixo): clique na linha; padrão = o primeiro a comprar
	local selM
	for _, g in ipairs(res.groups) do
		for _, m in ipairs(g.order) do
			if Buy.selected and m.buyId == Buy.selected and not selM then selM = m end
		end
	end
	local tokenSel = Buy.selected == Buy.TOKEN_ITEM
	if not selM and not tokenSel then
		for _, g in ipairs(res.groups) do for _, m in ipairs(g.order) do if not selM and m.buy > 0 then selM = m end end end
	end
	-- lista dos materiais com rolagem própria (como a bolsa da aba Vender); cartões em cima e histórico embaixo visíveis
	local LIST_H = 360
	local lc = cv._buyList
	if not lc then lc = ns.Visual.CreateSub(cv); cv._buyList = lc end
	lc:Place(0, y, W, LIST_H)
	lc:Show()
	lc:Begin()
	local LW = lc:Width()
	local top = y
	y = 0
	if res.list == "cons" then
		y = Buy.DrawToken(lc, y, LW, { icon = X_ICON, name = X_NAME, price = X_PRICE, sig = X_SIG, days = X_DAYS, cost = X_COST })
	end
	for _, g in ipairs(res.groups) do
		-- cabeçalho do personagem
		local mine = g.char == ns.CharKey()
		lc:Box(0, y, LW, 30, mine and 1 or 0.17, mine and 0.82 or 0.36, mine and 0 or 0.66, mine and 0.12 or 0.16)
		if g.sugg then
			lc:Text(8, y + 8, "|cff66ccff" .. L["Sugestão"] .. "|r · " .. ns.Visual.ClassName(g.char, g.class), GameFontNormal, 200)
		elseif g.queue then
			lc:Text(8, y + 8, "|cffd4af37" .. L["Fila e pedidos"] .. "|r", GameFontNormal, 120)
		else
			lc:Text(8, y + 8, ns.Visual.ClassName(g.char, g.class), GameFontNormal, 120)
		end
		local px = 130
		for _, it in ipairs(g.profs) do
			lc:Icon(px, y + 3, 24, ns.Visual.ProfIcon(it.char, it.e), { border = { 0.6, 0.6, 0.6 }, tip = function(tt)
				tt:SetText((it.e.name or "?") .. " — " .. it.char)
				tt:AddDoubleLine(L["Concentração usada"], string.format(L["%d (agora ~%d + %d regenerando)"],
					math.floor((it.budget or it.est or 0) - (it.left or 0) + 0.5), math.floor(it.est or 0), math.floor(it.regen or 0)), 1, 0.82, 0, 1, 1, 1)
				tt:AddLine(L["Planejado"], 1, 0.82, 0)
				for _, u in ipairs(it.used) do tt:AddLine(string.format(L["%dx %s"], u.crafts, u.row.name or "?"), 1, 1, 1) end
			end })
			px = px + 28
		end
		if g.sugg then
			lc:Text(px + 90, y + 9, string.format(L["|cff9d9d9dmelhor de cada tipo · %.1f h e %d chefes em masmorra/raide/imersão (14 dias)|r"], g.hours or 0, g.runs or 0), GameFontHighlightSmall, X_COST - px - 110)
		elseif g.cons then
			lc:Text(px + 8, y + 9, string.format(L["|cff9d9d9d%d consumíveis usados em masmorra, raide e imersão (14 dias) · repor para %d dias|r"], #g.order, Buy.ConsDays()), GameFontHighlightSmall, X_COST - px - 30)
		else
			lc:Text(px + 8, y + 9, string.format(L["|cff9d9d9d%d fabricações · lucro %s|r"], g.crafts, G(g.gain)), GameFontHighlightSmall, X_COST - px - 30)
		end
		lc:Text(X_COST - 10, y + 8, G(g.cost, true), GameFontNormal, 130, "RIGHT")
		y = y + 34
		local shownHave = false
		for k, m in ipairs(g.order) do
			local a = m.a
			local have = m.buy <= 0
			if have and not shownHave then
				shownHave = true
				lc:Text(X_NAME, y + 2, "|cff9d9d9d" .. L["Materiais que já tem"] .. "|r", GameFontDisableSmall)
				y = y + 16
			end
			root.Zebra(lc, k, 0, y, LW, have and 36 or 40)
			if selM and m.buyId == selM.buyId then
				lc:Box(0, y, 3, have and 36 or 40, 0.4, 0.8, 1, 1)
				lc:Box(0, y, LW, have and 36 or 40, 0.4, 0.8, 1, 0.08)
			end
			lc:Hit(X_NAME, y, X_PRICE - X_NAME - 8, have and 36 or 40, function() Buy.selected = m.buyId; Buy.ShowInAH(m.buyId); Buy.Refresh() end, function(tt)
				tt:SetText(C_Item.GetItemNameByID(m.buyId) or "?")
				tt:AddLine(L["Clique: ver o histórico de preço embaixo"], 0.4, 0.8, 1)
				tt:AddLine(Buy.AHOpen() and L["e procurar na casa de leilões (lista de preços)"] or L["(com a casa de leilões aberta, também procura o item lá)"], 0.4, 0.8, 1)
			end)
			local rarity = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(m.buyId) or nil
			local q = ns.Scanner and ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(m.buyId)
			lc:Icon(X_ICON, y + 4, 32, ns.Visual.ItemIcon(m.buyId), {
				count = not have and tostring(m.buy) or nil, desaturate = have, rarity = rarity,
				quality = q and ns.QIcon(q, 2, 10) or nil,
				link = select(2, C_Item.GetItemInfo(m.buyId)), tip = MatTip(m) })
			local name = ns.Visual.ItemName(m.buyId)
			lc:Text(X_NAME, y + 6, (have and "|cff9d9d9d" or "|cffffffff") .. name .. "|r", GameFontHighlight, X_PRICE - X_NAME - 8)
			local stock = m.wb > 0 and string.format(L["precisa %s · tem %s · bando %s"], root.Num(m.need, 0), root.Num(m.own, 0), root.Num(m.wb, 0))
				or string.format(L["precisa %s · tem %s"], root.Num(m.need, 0), root.Num(m.own, 0))
			if m.craft and not have then
				local ctxt = m.craftBetter and string.format(L[" · |cff66ccfffabricar %s/un%s|r"], G(m.craft.unit), m.craftSave and string.format(" (-%d%%)", math.min(99, math.floor(m.craftSave * 100))) or "")
					or string.format(L[" · |cff9d9d9dfabricar %s/un|r"], G(m.craft.unit))
				stock = stock .. ctxt
			end
			if m.note then stock = "|cff66ccff" .. m.note .. "|r|cff9d9d9d · " .. stock end
			lc:Text(X_NAME, y + 22, "|cff9d9d9d" .. stock .. "|r", GameFontDisableSmall, X_PRICE - X_NAME - 8)
			if not have and m.vdata then
				-- mais de uma qualidade (ex.: consumíveis): duas opções de compra lado a lado, na mesma linha
				local optW = math.floor((X_COST + 122 - X_PRICE - 10) / #m.vdata)
				for i, v in ipairs(m.vdata) do
					local ox = X_PRICE + (i - 1) * (optW + 10)
					local va = v.a
					local rarity2 = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(v.id) or nil
					lc:Icon(ox, y + 2, 26, ns.Visual.ItemIcon(v.id), { rarity = rarity2, link = select(2, C_Item.GetItemInfo(v.id)),
						tip = function(tt)
							tt:SetItemByID(v.id)
							tt:AddLine(" ")
							tt:AddDoubleLine(L["Preço agora"], va.now and P.FormatMoney(va.now) or "—", 1, 0.82, 0, 1, 1, 1)
							tt:AddDoubleLine(L["Preço típico (7 dias)"], va.typical and P.FormatMoney(va.typical) or "—", 1, 0.82, 0, 1, 1, 1)
							if v.craft then
								tt:AddDoubleLine(L["Custo de fabricar"], P.FormatMoney(v.craft.unit) .. L["/un"], 0.4, 0.8, 1, 1, 1, 1)
								if v.craftBetter then tt:AddLine(L["Fabricar sai mais barato."], 0.4, 0.8, 1, true) end
							end
						end })
					lc:Text(ox + 30, y + 1, ns.Visual.ItemName(v.id), GameFontHighlightSmall, optW - 30)
					local vtxt = va.now and ((va.outlier and "|cffff9933" or "") .. G(va.now) .. (va.outlier and "|r" or "")) or "|cff9d9d9d—|r"
					if v.craftBetter then vtxt = vtxt .. string.format(L[" · |cff66ccfffabricar %s|r"], G(v.craft.unit)) end
					lc:Text(ox + 30, y + 15, vtxt, GameFontDisableSmall, optW - 30)
					Buy.DrawBuyButton(lc, ox, y + 21, optW, v.id, m.buy)
				end
			elseif not have then
				-- preço agora e diferença do típico
				lc:Text(X_PRICE, y + 6, a.now and ((a.outlier and "|cffff9933" or "") .. G(a.now) .. (a.outlier and "|r" or "")) or "|cff9d9d9d—|r", GameFontHighlightSmall, 120, "RIGHT")
				if a.outlier then
					lc:Text(X_PRICE, y + 22, "|cffff9933" .. L["anúncio fora do normal"] .. "|r |cff9d9d9d" .. (a.typical and G(a.typical) or "") .. "|r", GameFontDisableSmall, 120, "RIGHT")
				elseif not a.vendor then
					lc:Text(X_PRICE, y + 22, PctColored(a.diff) .. " |cff9d9d9dvs. " .. (a.typical and G(a.typical) or "—") .. "|r", GameFontDisableSmall, 120, "RIGHT")
				end
				-- selo
				local s = (m.craftBetter and SIGNAL.craft) or SIGNAL[a.signal] or SIGNAL.none
				lc:Box(X_SIG, y + 8, 80, 22, s.r, s.g, s.b, 0.85)
				lc:Text(X_SIG, y + 13, "|cffffffff" .. L[s.txt] .. "|r", GameFontNormalSmall, 80, "CENTER")
				local sigTip = function(tt)
					tt:SetText(L[s.txt])
					tt:AddDoubleLine(L["Preço agora"], a.now and P.FormatMoney(a.now) or "—", 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L["Preço típico (7 dias)"], a.typical and P.FormatMoney(a.typical) or "—", 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L["Diferença"], PctColored(a.diff), 1, 0.82, 0, 1, 1, 1)
					if a.outlier then tt:AddLine(L["O menor anúncio está muito acima do normal (mercado vazio ou preço de provocação). Não compre: o custo da linha usa o preço típico."], 1, 0.6, 0.2, true) end
					if a.signal == "wait" and a.best then tt:AddLine(string.format(L["espere: %s"], WD_LONG[a.best]), 1, 0.82, 0) end
					if m.craft then
						tt:AddLine(" ")
						tt:AddDoubleLine(L["Custo de fabricar"], P.FormatMoney(m.craft.unit) .. L["/un"], 0.4, 0.8, 1, 1, 1, 1)
						tt:AddLine(string.format(L["%s (%s)"], m.craft.name or "?", m.craft.char or "?"), 0.6, 0.6, 0.6)
						if m.craftBetter then
							tt:AddLine(string.format(L["Fabricar sai mais barato: economiza %s nesta compra."], P.FormatMoney((((a.outlier and a.typical) or a.now or 0) - m.craft.unit) * m.buy)), 0.4, 0.8, 1, true)
						else
							tt:AddLine(L["Comprar sai mais barato (ou igual) que fabricar."], 0.6, 0.6, 0.6, true)
						end
					end
					if a.vendor then tt:AddLine(L["Preço do vendedor: não muda com o dia."], 0.7, 0.7, 0.7, true) end
					if a.signal == "none" then tt:AddLine(L["Sem preço na casa de leilões."], 0.7, 0.7, 0.7, true) end
				end
				lc:Hit(X_SIG, y + 8, 80, 22, nil, sigTip)
				-- dias da semana
				if not a.vendor then
					MiniDays(lc, X_DAYS, y + 9, a, DayStripTip(a, name))
					local bestTxt = a.best and (WD_LONG[a.best] .. " " .. PctColored(a.wd[a.best].idx))
						or ("|cff9d9d9d" .. (a.conf == "none" and L["poucos dados"] or "") .. "|r")
					lc:Text(X_DAYS + 7 * 17 + 6, y + 13, bestTxt, GameFontHighlightSmall, X_COST - (X_DAYS + 7 * 17 + 6) - 4)
				end
				-- custo
				lc:Text(X_COST, y + 6, G(m.cost, true), GameFontNormal, 122, "RIGHT")
				Buy.DrawBuyButton(lc, X_COST + 2, y + 20, 120, m.buyId, m.buy)
			else
				lc:Text(X_PRICE, y + 13, "|cff55ff55" .. L["já tem"] .. "|r", GameFontHighlightSmall, 120, "RIGHT")
			end
			y = y + (have and 36 or ROW_H)
		end
		y = y + 8
	end
	lc:End(y)
	local vis = math.min(y, LIST_H)
	lc:Place(0, top, W, vis)
	y = top + vis + 6
	-- histórico de preço do material selecionado (o mesmo da aba Vender)
	if tokenSel and ns.Sell and ns.Sell.DrawHistory then
		local hm = { id = Buy.TOKEN_ITEM, a = Buy.Analyze(Buy.TOKEN_ITEM) }
		local ok, yy = pcall(ns.Sell.DrawHistory, cv, y + 10, W, hm, Buy.Refresh, "bhist")
		if ok and yy then y = yy end
	elseif selM and ns.Sell and ns.Sell.DrawHistory then
		local hm = { id = selM.buyId, a = selM.a, spd = P.SoldPerDay(selM.buyId) }
		local ok, yy = pcall(ns.Sell.DrawHistory, cv, y + 10, W, hm, Buy.Refresh, "bhist")
		if ok and yy then y = yy end
	end
	cv:End(y + 8)
end

-- ===== Comprar direto da lista (casa de leilões aberta) =====
-- 1º clique: pede o preço ao servidor (StartCommoditiesPurchase). 2º clique: confirma (ConfirmCommoditiesPurchase).
-- O jogo exige um clique para cada passo. Preço muito acima do típico pede atenção no botão.
Buy.pur = nil      -- { itemID, qty, state = "quote" | "confirm" | "buying", unit, total, t }
function Buy.AHOpen()
	return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) and true or false
end
local function IsCommodity(itemID)
	if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus then
		local ok, st = pcall(C_AuctionHouse.GetItemCommodityStatus, itemID)
		if ok and Enum and Enum.ItemCommodityStatus then return st ~= Enum.ItemCommodityStatus.Item end
	end
	local _, _, _, _, _, _, _, stack = C_Item.GetItemInfo(itemID)
	return (stack or 1) > 1
end
function Buy.StartBuy(itemID, qty)
	if not Buy.AHOpen() then ns.Print(L["abra a casa de leilões para comprar."]) return end
	if not IsCommodity(itemID) then ns.Print(L["este item não é vendido em lote: compre pela janela da casa de leilões."]) return end
	Buy.pur = { itemID = itemID, qty = qty, state = "quote", t = GetTime() }
	local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, itemID, qty)
	if not ok then ns.Print(L["erro ao pedir o preço: "] .. tostring(err)); Buy.pur = nil end
	Buy.Refresh()
end
function Buy.ConfirmBuy()
	local p = Buy.pur
	if not (p and p.state == "confirm") then return end
	if GetTime() - p.t > 50 then ns.Print(L["o preço expirou: clique em comprar de novo."]); Buy.pur = nil; Buy.Refresh() return end
	p.state = "buying"
	local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, p.itemID, p.qty)
	if not ok then ns.Print(L["erro ao comprar: "] .. tostring(err)); Buy.pur = nil end
	Buy.Refresh()
end
function Buy.CancelBuy()
	if Buy.pur and C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
	Buy.pur = nil
	Buy.Refresh()
end
do
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_SHOW" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function(_, ev, a1, a2)
		local p = Buy.pur
		if ev == "COMMODITY_PRICE_UPDATED" and p then
			p.unit, p.total, p.state, p.t = a1, a2, "confirm", GetTime()
		elseif ev == "COMMODITY_PRICE_UNAVAILABLE" and p then
			ns.Print(L["sem oferta suficiente na casa de leilões para essa quantidade."])
			Buy.pur = nil
		elseif ev == "COMMODITY_PURCHASE_SUCCEEDED" and p then
			ns.Print(string.format(L["comprado: %dx %s por %s."], p.qty, C_Item.GetItemNameByID(p.itemID) or "?", P.FormatMoney(p.total or 0)))
			if p.unit then Buy.Record(p.itemID, p.unit) end
			Buy.pur = nil
		elseif ev == "COMMODITY_PURCHASE_FAILED" and p then
			ns.Print(L["a compra falhou (o preço mudou ou faltou ouro)."])
			Buy.pur = nil
		elseif ev == "AUCTION_HOUSE_CLOSED" then
			Buy.pur = nil
		end
		local fr = LucroCraftFrame
		if fr and fr:IsShown() and ns.UI and fr.currentTab == ns.UI.TAB.BUY then Buy.Refresh() end
	end)
end
function Buy.DrawBuyButton(lc, x, y, w, itemID, qty)
	local G = P.FormatGold
	local p = Buy.pur
	if p and p.itemID == itemID then
		if p.state == "confirm" then
			local a = Buy.Analyze(itemID)
			local hot = a.typical and p.unit and p.unit > a.typical * 1.3
			lc:Box(x - 2, y - 2, w + 4, 20, hot and 1 or 0.3, hot and 0.3 or 1, 0.3, 0.35)
			lc:Button(x, y, w - 22, 16, string.format(L["Confirmar %s"], G(p.total or 0)), function() Buy.ConfirmBuy() end, function(tt)
				tt:SetText(string.format(L["Comprar %dx %s"], p.qty, C_Item.GetItemNameByID(itemID) or "?"))
				tt:AddDoubleLine(L["Preço un"], P.FormatMoney(p.unit or 0), 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L["Total"], P.FormatMoney(p.total or 0), 1, 0.82, 0, 1, 1, 1)
				if a.typical then tt:AddDoubleLine(L["Preço típico (7 dias)"], P.FormatMoney(a.typical), 1, 0.82, 0, 1, 1, 1) end
				if hot then tt:AddLine(L["Atenção: mais de 30% acima do típico."], 1, 0.3, 0.3, true) end
			end)
			lc:Button(x + w - 20, y, 20, 16, "x", function() Buy.CancelBuy() end)
			return
		end
		lc:Text(x, y + 2, L["|cff9d9d9dconsultando...|r"], GameFontDisableSmall, w, "RIGHT")
		return
	end
	if Buy.AHOpen() then
		lc:Button(x + 20, y, w - 20, 16, string.format(L["Comprar %s"], root.Num(qty, 0)), function() Buy.StartBuy(itemID, qty) end, function(tt)
			tt:SetText(string.format(L["Comprar %dx"], qty))
			tt:AddLine(L["1º clique pede o preço; o 2º confirma a compra."], 1, 1, 1, true)
		end)
	else
		lc:Text(x, y + 2, "|cff9d9d9d" .. string.format(L["comprar %s"], root.Num(qty, 0)) .. "|r", GameFontDisableSmall, w, "RIGHT")
	end
end

-- ===== Lista de consumíveis: o que cada personagem gastou (livro-caixa, conta 4.5.01) =====
-- Consumível usado (poção, frasco, comida, tambor, item de reviver...) fica no Diário com item e quantidade.
-- Uso dos últimos N dias → reposição para cobrir o mesmo período, menos o que já tem (bolsa/banco + bando).
local CONS_SUB = { [1] = "pot", [2] = "elixir", [3] = "flask", [5] = "food" }
function Buy.ConsDays() return tonumber(LucroCraftDB.config.consDays) or 7 end
-- só o que foi gasto em masmorra, raide e imersão (delve); o resto (profissão, mundo aberto) fica fora
local COMBAT_ACT
COMBAT_ACT = { dungeon = true, raid = true, delve = true }
local ConsAct
-- atividade do lançamento: gravada desde a v1.23.2 (e.k); antes, achada pelo nome do lugar nas subcontas do dia
ConsAct = function(c, e)
	if e.k then return e.k end
	local day = c.days and c.days[root.DayKey(e.t)]
	if not day or not day.act then return nil end
	local best
	for k, a in pairs(day.act) do
		local sx = a.sub and a.sub[e.h or ""]
		if sx and sx.cost and (sx.cost.consum or 0) > 0 then
			if COMBAT_ACT[k] then return k end
			best = best or k
		end
	end
	return best
end
function Buy.ConsGroups(me, allChars)
	local LDB = LucroLivroDB
	if not (LDB and LDB.chars) then return {} end
	local C = ns.Plan.Count
	local span = 14 * 86400          -- olha 14 dias de uso
	local cover = Buy.ConsDays()     -- e repõe para N dias
	local hidePots = LucroCraftDB.config.consHidePots
	local since = time() - span
	local out = {}
	for char, c in pairs(LDB.chars) do
		if allChars or char == me then
			local used, first = {}, nil
			for _, e in ipairs(c.journal or {}) do
				if e.a == "4.5.01" and e.i and e.t >= since and (e.q or 0) < 0 and COMBAT_ACT[ConsAct(c, e) or ""] then
					used[e.i] = (used[e.i] or 0) - e.q
					first = (not first or e.t < first) and e.t or first
				end
			end
			local g
			for id, q in pairs(used) do
				local _, _, _, _, _, classID, sub = C_Item.GetItemInfoInstant(id)
				local kind = classID == 0 and (CONS_SUB[sub] or "other") or "other"
				if not (hidePots and kind == "pot") then
					-- ritmo: pelo período em que o personagem jogou (no mínimo 3 dias, no máximo 14)
					local days = first and math.max(3, math.min(14, (time() - first) / 86400)) or 14
					local need = math.ceil(q / days * cover)
					if need > 0 then
						if not g then
							g = { char = char, class = c.class, cons = true, profs = {}, mats = {}, order = {}, cost = 0, gain = 0, crafts = 0 }
							table.insert(out, g)
						end
						local own = C.own(char, id)
						local wb = C.warband(id)
						local m = { key = id, ids = { id }, buyId = id, need = need, uses = {}, own = own, wb = math.min(wb, math.max(0, need - own)),
							alts = 0, queue = true, kind = kind, usedQ = q, usedDays = days }
						m.buy = math.max(0, need - own - m.wb)
						table.insert(g.order, m)
					end
				end
			end
		end
	end
	table.sort(out, function(a, b) if (a.char == me) ~= (b.char == me) then return a.char == me end return a.char < b.char end)
	return out
end
function Buy.DrawConsOptions(cv, y, W)
	local cfg = LucroCraftDB.config
	local x = 300
	cv:Text(x, y - 20, L["Repor para:"], GameFontHighlightSmall, 80)
	x = x + 80
	for _, d in ipairs({ 3, 7, 14 }) do
		local on = Buy.ConsDays() == d
		if on then cv:Box(x - 2, y - 22, 56, 20, 0.83, 0.69, 0.22, 0.95) end
		cv:Button(x, y - 21, 52, 18, string.format(L["%d dias"], d), function() cfg.consDays = d; Buy.Refresh() end)
		x = x + 58
	end
	local gi = cfg.consGroup and true or false
	cv:Box(x + 196, y - 17, 12, 12, 0.83, 0.69, 0.22, gi and 1 or 0.18)
	cv:Text(x + 212, y - 18, (gi and "|cffffffff" or "|cff8f8f8f") .. L["Itens de grupo"] .. "|r", GameFontHighlightSmall, 120)
	cv:Hit(x + 192, y - 20, 130, 18, function() cfg.consGroup = not gi or nil; Buy.Refresh() end, function(tt)
		tt:SetText(L["Itens de grupo"])
		tt:AddLine(L["Inclui na sugestão: invisibilidade, caldeirão e banquete. Tambores aparecem sempre para quem não tem Heroísmo e o Emergency Soul Link para quem não tem reviver em combate."], 1, 1, 1, true)
	end)
	local hp = cfg.consHidePots and true or false
	cv:Box(x + 14, y - 17, 12, 12, 0.83, 0.69, 0.22, hp and 1 or 0.18)
	cv:Text(x + 30, y - 18, (hp and "|cffffffff" or "|cff8f8f8f") .. L["Esconder poções"] .. "|r", GameFontHighlightSmall, 150)
	cv:Hit(x + 10, y - 20, 150, 18, function() cfg.consHidePots = not hp or nil; Buy.Refresh() end, function(tt)
		tt:SetText(L["Esconder poções"])
		tt:AddLine(L["Tira da lista as poções (as de uso constante em masmorra), deixando frascos, comida, tambores, itens de reviver etc."], 1, 1, 1, true)
	end)
	return y
end

-- ===== Barra das listas de compras =====
local LISTS = { { key = "plan", label = "Plano de concentração" }, { key = "queue", label = "Fila de craft" }, { key = "cons", label = "Consumíveis" } }
function Buy.List()
	local v = LucroCraftDB and LucroCraftDB.config and LucroCraftDB.config.buyList
	if v == "plan" or v == "queue" or v == "cons" then return v end
	return "plan"
end
function Buy.DrawListBar(cv, y, W, res)
	local cur = Buy.List()
	cv:Box(0, y - 2, W, 34, 0.08, 0.13, 0.24, 0.9)
	local bw = math.floor((W - 16 - 2 * 8) / 3)
	for i, li in ipairs(LISTS) do
		local x = 8 + (i - 1) * (bw + 8)
		local on = cur == li.key
		cv:Box(x - 2, y, bw + 4, 30, on and 0.83 or 0.3, on and 0.69 or 0.3, on and 0.22 or 0.35, on and 0.95 or 0.6)
		cv:Box(x, y + 2, bw, 26, 0.06, 0.1, 0.2, 1)
		local label = L[li.label]
		if li.key == "plan" and on then
			label = label .. (LucroCraftDB.config.buyAllChars and L[" · todos"] or L[" · este personagem"])
		end
		cv:Text(x, y + 8, (on and "|cffffd100" or "|cffd9dde3") .. label .. "|r", GameFontNormal, bw, "CENTER")
		cv:Hit(x, y, bw, 30, function() LucroCraftDB.config.buyList = li.key; Buy.selected = nil; Buy.Refresh() end, function(tt)
			tt:SetText(L[li.label])
			tt:AddLine(li.key == "plan" and L["Materiais que o plano de concentração vai gastar."]
				or li.key == "queue" and L["Materiais da fila de craft e dos pedidos (lidos e pegos)."]
				or L["WoW Token e os consumíveis que cada personagem usou (poções, frascos, comida, tambores, itens de reviver...) para repor."], 1, 1, 1, true)
		end)
	end
	y = y + 36
	if cur == "plan" or cur == "cons" then
		local all = LucroCraftDB.config.buyAllChars and true or false
		cv:Box(10, y + 1, 12, 12, 0.83, 0.69, 0.22, all and 1 or 0.18)
		cv:Text(28, y, (all and "|cffffffff" or "|cff8f8f8f") .. L["Mostrar todos os personagens"] .. "|r", GameFontHighlightSmall, 260)
		cv:Hit(6, y - 2, 270, 18, function() LucroCraftDB.config.buyAllChars = not all or nil; Buy.Refresh() end, function(tt)
			tt:SetText(L["Mostrar todos os personagens"])
			tt:AddLine(L["Desligado: só o que o personagem logado vai fabricar no plano."], 1, 1, 1, true)
		end)
		y = y + 20
	end
	return y
end

-- lista "Consumíveis": por enquanto o WoW Token (como item comum, com histórico embaixo)
function Buy.RenderCons(cv, y, W)
	local X = { icon = 8, name = 48, price = 300, sig = 430, days = 520, cost = W - 144 }
	local lc = cv._buyList
	if not lc then lc = ns.Visual.CreateSub(cv); cv._buyList = lc end
	lc:Place(0, y, W, 200)
	lc:Show()
	lc:Begin()
	local yy = Buy.DrawToken(lc, 0, lc:Width(), X)
	lc:End(yy)
	lc:Place(0, y, W, yy)
	y = y + yy + 6
	if not Buy.selected then Buy.selected = Buy.TOKEN_ITEM end
	if Buy.selected == Buy.TOKEN_ITEM and ns.Sell and ns.Sell.DrawHistory then
		local ok, y2 = pcall(ns.Sell.DrawHistory, cv, y + 4, W, { id = Buy.TOKEN_ITEM, a = Buy.Analyze(Buy.TOKEN_ITEM) }, Buy.Refresh, "bhist")
		if ok and y2 then y = y2 end
	end
	cv:End(y + 8)
end

-- clique no item: a casa de leilões (aberta) procura e mostra a lista de preços dele
function Buy.ShowInAH(itemID)
	if not (itemID and Buy.AHOpen()) or itemID == Buy.TOKEN_ITEM then return end
	local ok = false
	if AuctionHouseFrame.SelectBrowseResult and C_AuctionHouse.MakeItemKey then
		ok = pcall(function()
			if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
				AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
			end
			AuctionHouseFrame:SelectBrowseResult({ itemKey = C_AuctionHouse.MakeItemKey(itemID) })
		end)
	end
	if not ok then
		-- plano B: digita o nome na busca da casa de leilões e pesquisa
		local name = C_Item.GetItemNameByID(itemID)
		local bar = AuctionHouseFrame.SearchBar
		if name and bar and bar.SearchBox then
			pcall(function()
				bar.SearchBox:SetText(name)
				if bar.StartSearch then bar:StartSearch() end
			end)
		end
	end
end

-- ===== WoW Token (topo da lista de compras, grupo minimizável) =====
-- Tratado como um item comum: o preço do C_WowTokenPublic vira amostra (Buy.Record) no mesmo histórico dos
-- materiais → preço agora × típico, selo, dias da semana e o gráfico de histórico embaixo (clique na linha).
local TOKEN_ITEM = 122284
Buy.TOKEN_ITEM = TOKEN_ITEM
function Buy.TokenPrice()
	LucroCraftDB.token = LucroCraftDB.token or {}
	local tk = LucroCraftDB.token
	-- histórico guardado pela v1.21.1 (1 por hora) passa para as amostras normais
	if tk.hist then
		for _, h in ipairs(tk.hist) do Buy.Record(TOKEN_ITEM, h.p, h.t) end
		tk.hist = nil
		cache[TOKEN_ITEM] = nil
	end
	if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice and (not tk.asked or time() - tk.asked > 300) then
		tk.asked = time()
		pcall(C_WowTokenPublic.UpdateMarketPrice)
	end
	if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then
		local ok, price = pcall(C_WowTokenPublic.GetCurrentMarketPrice)
		if ok and type(price) == "number" and price > 0 then
			if price ~= tk.price or not tk.t or time() - tk.t > 600 then
				Buy.Record(TOKEN_ITEM, price)
				cache[TOKEN_ITEM] = nil
			end
			tk.price, tk.t = price, time()
		end
	end
	return tk.price and tk or nil
end
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED")
	f:SetScript("OnEvent", function()
		if not LucroCraftDB then return end
		pcall(Buy.TokenPrice)
		local fr = LucroCraftFrame
		if fr and fr:IsShown() and ns.UI and fr.currentTab == ns.UI.TAB.BUY then Buy.Refresh() end
	end)
end

function Buy.DrawToken(lc, y, LW, X)
	local G = P.FormatGold
	local tk = Buy.TokenPrice()
	local a = Buy.Analyze(TOKEN_ITEM)
	local price = tk and tk.price or a.now
	local name = C_Item.GetItemNameByID(TOKEN_ITEM) or L["WoW Token"]
	local summary = price and (G(price) .. (a.diff and ("  " .. PctColored(a.diff)) or "")) or L["|cff9d9d9dbuscando o preço...|r"]
	local col
	y, col = ns.Sell.Group(lc, y, LW, "buyToken", L["WoW Token"], summary, 0, Buy.Refresh)
	if col then return y end
	local H = 40
	local sel = Buy.selected == TOKEN_ITEM
	if sel then
		lc:Box(0, y, 3, H, 0.4, 0.8, 1, 1)
		lc:Box(0, y, LW, H, 0.4, 0.8, 1, 0.08)
	end
	lc:Hit(X.name, y, X.price - X.name - 8, H, function() Buy.selected = TOKEN_ITEM; Buy.Refresh() end, function(tt)
		tt:SetText(name)
		tt:AddLine(L["Clique: ver o histórico de preço embaixo"], 0.4, 0.8, 1)
	end)
	lc:Icon(X.icon, y + 4, 32, C_Item.GetItemIconByID and C_Item.GetItemIconByID(TOKEN_ITEM) or 1120721, {
		rarity = 8, link = select(2, C_Item.GetItemInfo(TOKEN_ITEM)), tip = function(tt)
			tt:SetItemByID(TOKEN_ITEM)
			tt:AddLine(" ")
			tt:AddLine(L["Preço atual na casa de leilões (atualiza a cada 5 min com a janela aberta)."], 0.6, 0.6, 0.6, true)
		end })
	lc:Text(X.name, y + 6, "|cffffffff" .. name .. "|r", GameFontHighlight, X.price - X.name - 8)
	local gold = 0
	for _, c in pairs(LucroLivroDB and LucroLivroDB.chars or {}) do gold = gold + (c.lastMoney or 0) end
	if price and gold > 0 then
		lc:Text(X.name, y + 22, string.format(L["|cff9d9d9dseu ouro = %.1f fichas|r"], gold / price), GameFontDisableSmall, X.price - X.name - 8)
	end
	-- preço agora × típico, selo e dias da semana (como os materiais)
	lc:Text(X.price, y + 6, price and G(price) or "|cff9d9d9d—|r", GameFontHighlightSmall, 120, "RIGHT")
	lc:Text(X.price, y + 22, PctColored(a.diff) .. " |cff9d9d9dvs. " .. (a.typical and G(a.typical) or "—") .. "|r", GameFontDisableSmall, 120, "RIGHT")
	local s = SIGNAL[a.signal] or SIGNAL.none
	lc:Box(X.sig, y + 8, 80, 22, s.r, s.g, s.b, 0.85)
	lc:Text(X.sig, y + 13, "|cffffffff" .. L[s.txt] .. "|r", GameFontNormalSmall, 80, "CENTER")
	lc:Hit(X.sig, y + 8, 80, 22, nil, function(tt)
		tt:SetText(L[s.txt])
		tt:AddDoubleLine(L["Preço agora"], price and P.FormatMoney(price) or "—", 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L["Preço típico (7 dias)"], a.typical and P.FormatMoney(a.typical) or "—", 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L["Diferença"], PctColored(a.diff), 1, 0.82, 0, 1, 1, 1)
		if a.signal == "wait" and a.best then tt:AddLine(string.format(L["espere: %s"], WD_LONG[a.best]), 1, 0.82, 0) end
	end)
	MiniDays(lc, X.days, y + 9, a, DayStripTip(a, name))
	local bestTxt = a.best and (WD_LONG[a.best] .. " " .. PctColored(a.wd[a.best].idx))
		or ("|cff9d9d9d" .. (a.conf == "none" and L["poucos dados"] or "") .. "|r")
	lc:Text(X.days + 7 * 17 + 6, y + 13, bestTxt, GameFontHighlightSmall, X.cost - (X.days + 7 * 17 + 6) - 4)
	lc:Text(X.cost, y + 6, price and G(price, true) or "—", GameFontNormal, 122, "RIGHT")
	lc:Text(X.cost, y + 22, "|cff9d9d9d" .. string.format(L["comprar %s"], "1") .. "|r", GameFontDisableSmall, 122, "RIGHT")
	return y + H + 8
end

-- ===== lista no Auctionator (só o que falta comprar) =====
local function BuyRows()
	local res = Buy.Build()
	local total, order = {}, {}
	for _, m in ipairs(res.items) do
		if not total[m.buyId] then table.insert(order, m.buyId) end
		total[m.buyId] = (total[m.buyId] or 0) + m.buy
	end
	local rows = {}
	for _, id in ipairs(order) do if total[id] > 0 then table.insert(rows, { id = id, qty = total[id] }) end end
	return rows
end
ns.Stock.RegisterListBuilder("buy", BuyRows)

function Buy.ExportAuctionator()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		ns.Print(L["Auctionator não encontrado."])
		return
	end
	local terms = ns.Stock.Terms(BuyRows())
	if #terms == 0 then ns.Print(L["nada a comprar."]) return end
	local listName = L["Royal Revenue - Compras"]
	local ok, err = pcall(api.CreateShoppingList, ADDON, listName, terms)
	if ok then
		ns.Stock.LiveList(listName, "buy", terms)
		ns.Print(string.format(L["lista \"%s\" criada no Auctionator com %d itens."], listName, #terms) .. L[" Ela se atualiza sozinha: o que você compra sai da lista."])
	else
		ns.Print(L["erro no Auctionator: "] .. tostring(err))
	end
end

function Buy.Refresh()
	if ns.UI and ns.UI.RefreshTab and ns.UI.TAB and ns.UI.TAB.BUY then ns.UI.RefreshTab(ns.UI.TAB.BUY) end
end

-- ===== eventos: guarda o preço com a hora =====
local ticker, refreshPending = nil, false
local function SoonRefresh()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(2, function() refreshPending = false; Buy.Refresh() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:SetScript("OnEvent", function(_, event, arg1)
	if not LucroCraftDB then return end
	if event == "PLAYER_LOGIN" then
		-- só marca o preço atual do Auctionator (a hora dele é desconhecida)
		C_Timer.After(15, function() pcall(Buy.ReadAuctionator, true) end)
	elseif event == "AUCTION_HOUSE_SHOW" then
		if ticker then ticker:Cancel() end
		if C_Timer.NewTicker then
			ticker = C_Timer.NewTicker(30, function() pcall(Buy.ReadAuctionator) end)
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if ticker then ticker:Cancel(); ticker = nil end
		pcall(Buy.ReadAuctionator)
		SoonRefresh()
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		local id = arg1
		if id and Buy.Tracked()[id] and C_AuctionHouse and C_AuctionHouse.GetCommoditySearchResultInfo then
			local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, id, 1)
			if ok and type(info) == "table" and info.unitPrice then Buy.Record(id, info.unitPrice) end
		end
	end
end)

-- usado nos testes fora do jogo
Buy._Around, Buy._DailySeries = Around, DailySeries
function Buy._ClearCache() wipe(cache); wipe(dayCache); tracked = nil end

-- utilidades de desenho para a aba Vender (Sell.lua)
Buy.UI = { G = G, Pct = Pct, PctColored = PctColored, CellColor = CellColor, MiniDays = MiniDays, Card = Card,
	DayStripTip = DayStripTip, BAND_TXT = BAND_TXT, BANDS = BANDS }
