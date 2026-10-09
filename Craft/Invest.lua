local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Investimento em equipamento de profissão:
-- quanto ouro por semana cada peça (ferramenta/acessório) a mais te daria, e em quantas semanas se paga.
local Invest = {}
ns.Invest = Invest

local P = ns.Pricing
local Cfg = ns.Cfg

local DEFAULT_CONC_PER_HOUR = 10.5   -- medido nos seus scans (Escrivania do Radunz: +95 em 9h)

local function ConcPerWeek()
	local rate = tonumber(Cfg("concPerHour")) or LucroCraftDB.concRate or DEFAULT_CONC_PER_HOUR
	return rate * 24 * 7, rate
end

-- ===== Leitura de stats pelo tooltip =====
-- Buffs temporários que melhoram a fabricação (Midnight). Não existe consumível de perícia;
-- o único de fabricação é o frasco de engenhosidade da Alquimia (+ velocidade, que não vale ouro).
-- Comida: os chás da Culinária (Argentleaf/Sanguithorn/Azeroot Tea, buff "Relaxed" 60 min) dão Finesse,
-- Perception e Deftness = só coleta; nenhuma comida da Midnight melhora fabricação (verificado em 01/10/2026).
-- Para acrescentar outro: { itemID, quality, minutes, stats = { skill/multicraft/resourcefulness/ingenuity = valor } }
-- Buffs temporários de coleta (mostrados na aba Investimento ao abrir Herbalismo/Mineração/Esfolamento).
-- Valores pela Warcraft Wiki (amt = pontos do atributo principal); os chás não informam o número: sem ganho calculado.
Invest.GATHER_BUFFS = {
	{ group = "food",  itemID = 242298, minutes = 60,  stat = "finesse" },   -- Argentleaf Tea: Finesse + velocidade
	{ group = "food",  itemID = 242299, minutes = 60,  stat = "perception" },   -- Sanguithorn Tea: Perception + velocidade
	{ group = "food",  itemID = 242301, minutes = 60,  stat = "deftness" },   -- Azeroot Tea: Deftness + velocidade
	{ group = "phial", itemID = 241317, quality = 1, minutes = 30, stat = "perception", amt = 38 },   -- Haranir Phial of Perception ★1: +38 Perception, +12 Deftness
	{ group = "phial", itemID = 241316, quality = 2, minutes = 30, stat = "perception", amt = 45 },   -- ★2: +45 / +14
	{ group = "phial", itemID = 241311, quality = 1, minutes = 30, stat = "finesse", amt = 38 },   -- Haranir Phial of Finesse ★1: +38 Finesse, +12 Deftness
	{ group = "phial", itemID = 241310, quality = 2, minutes = 30, stat = "finesse", amt = 45 },   -- ★2: +45 / +14
	{ group = "stone", itemID = 237372, quality = 1, minutes = 120, stat = "finesse", amt = 43 },  -- Refulgent Razorstone ★1: +43 Finesse na ferramenta
	{ group = "stone", itemID = 237373, quality = 2, minutes = 120, stat = "finesse", amt = 57 },  -- ★2: +57
}

Invest.BUFFS = {
	{ itemID = 241313, quality = 1, minutes = 30, stats = { ingenuity = 38 } },   -- Haranir Phial of Ingenuity ★1
	{ itemID = 241312, quality = 2, minutes = 30, stats = { ingenuity = 45 } },   -- Haranir Phial of Ingenuity ★2
}

local function ParseStats(tip, profName)
	local st = { skill = 0, multicraft = 0, resourcefulness = 0, ingenuity = 0 }
	if not tip or not tip.lines then return st, false end
	local any = false
	local pl = (profName or ""):lower()
	for _, line in ipairs(tip.lines) do
		local text = line.leftText
		if text then
			-- skill da profissão vem como "Equip: +18 Midnight Inscription Skill"
			local eq = ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"
			if text:sub(1, #eq) == eq then text = text:sub(#eq + 1):gsub("^%s+", "") end
			if text:sub(1, 6) == "Equip:" then text = text:sub(7):gsub("^%s+", "") end
			local num, what = text:match("^%+([%d%.,]+)%s+(.+)$")
			if num then
				num = tonumber((num:gsub("[,%.]", "")))
				local w = what:lower()
				local k = ns.Scanner.StatKey(what)
				if k then
					st[k] = st[k] + num; any = true
				elseif w:find("random stat", 1, true) or w:find("atributo aleat", 1, true) then
					-- ferramenta ainda sem stat escolhido: o valor vale para qualquer um dos 3
					st.random = (st.random or 0) + num; any = true
				elseif (pl ~= "" and w:find(pl, 1, true)) or w:find("skill", 1, true) or w:find("perícia", 1, true) then
					st.skill = st.skill + num; any = true
				end
			end
		end
	end
	return st, any
end

local function ToFractions(st)
	local f = ns.Scanner.STAT_FACTOR
	return {
		skill = st.skill or 0,
		mc = (st.multicraft or 0) / f.multicraft,
		res = (st.resourcefulness or 0) / f.resourcefulness,
		ing = (st.ingenuity or 0) / f.ingenuity,
	}
end

-- ===== Encantamentos de ferramenta =====
-- enchantID -> stat (inclui os das expansões anteriores para reconhecer o que já está na ferramenta)
local ENCHANT_STATS = {
	[6662] = { "ingenuity", 22 }, [6663] = { "ingenuity", 30 }, [6664] = { "ingenuity", 38 },
	[6668] = { "resourcefulness", 22 }, [6669] = { "resourcefulness", 30 }, [6670] = { "resourcefulness", 38 },
	[7371] = { "ingenuity", 69 }, [7372] = { "ingenuity", 92 }, [7373] = { "ingenuity", 115 },
	[7377] = { "resourcefulness", 69 }, [7378] = { "resourcefulness", 92 }, [7379] = { "resourcefulness", 115 },
	[7976] = { "resourcefulness", 15 }, [7977] = { "resourcefulness", 30 },
	[8004] = { "multicraft", 15 }, [8005] = { "multicraft", 30 },
	[8034] = { "ingenuity", 15 }, [8035] = { "ingenuity", 30 },
}
-- opções do Midnight na melhor qualidade (Q2): pergaminho vendido na AH
local TOOL_ENCHANTS = {
	{ name = "Amani Resourcefulness", stat = "resourcefulness", value = 30, itemID = 243967, enchantID = 7977 },
	{ name = "Haranir Multicrafting", stat = "multicraft", value = 30, itemID = 243995, enchantID = 8005 },
	{ name = "Ren'dorei Ingenuity", stat = "ingenuity", value = 30, itemID = 244025, enchantID = 8035 },
}
-- nome do encantamento: nome do pergaminho no idioma do cliente (fallback em inglês)
local ENCHANT_ITEM = { [7976] = { 243966, 1 }, [7977] = { 243967, 2 }, [8004] = { 243994, 1 }, [8005] = { 243995, 2 },
	[8034] = { 244024, 1 }, [8035] = { 244025, 2 } }
local ENCHANT_NAME = { [7976] = "Amani Resourcefulness Q1", [7977] = "Amani Resourcefulness Q2",
	[8004] = "Haranir Multicrafting Q1", [8005] = "Haranir Multicrafting Q2",
	[8034] = "Ren'dorei Ingenuity Q1", [8035] = "Ren'dorei Ingenuity Q2" }

local function LinkEnchant(link)
	local s = link and link:match("item:([^|]+)")
	if not s then return nil end
	local e = tonumber(s:match("^%-?%d+:(%d*)") or "")
	return (e and e > 0) and e or nil
end

local function EnchantStats(enchantID)
	local st = { skill = 0, multicraft = 0, resourcefulness = 0, ingenuity = 0 }
	local e = enchantID and ENCHANT_STATS[enchantID]
	if e then st[e[1]] = e[2] end
	return st
end

local function AddStats(a, b)
	local o = {}
	for _, k in ipairs({ "skill", "multicraft", "resourcefulness", "ingenuity" }) do
		o[k] = (a and a[k] or 0) + (b and b[k] or 0)
	end
	return o
end


-- Categoria de "único equipado" do item (ex.: óculos, luvas). É o que o jogo usa para
-- impedir dois acessórios do mesmo tipo; cada slot de acessório fica com um tipo.
-- Só vale como "tipo de slot" se o limite for 1 (categoria compartilhada por todos os acessórios
-- da profissão, com limite 2, não diz nada sobre o slot).
local function UniqueCategory(itemID)
	if not itemID or not C_Item.GetItemUniquenessByID then return nil end
	local ok, _, name, count, catID = pcall(C_Item.GetItemUniquenessByID, itemID)
	if not ok then return nil end
	if catID and catID ~= 0 and (count or 1) == 1 then return catID, name end
	return nil, nil
end

Invest._UniqueCategory = function(id) return UniqueCategory(id) end

-- Diagnóstico: tudo que o jogo informa sobre o item, para descobrir como ele define o slot do acessório
local function ItemDebug(itemID, link, slot)
	local d = { itemID = itemID, link = link, slot = slot }
	local ok, a, b, c, e = pcall(C_Item.GetItemUniquenessByID, itemID)
	if ok then d.unique = { a, b, c, e } end
	local _, _, subType, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	d.subType, d.equipLoc, d.classID, d.subClassID = subType, equipLoc, classID, subClassID
	if C_Item.GetItemInventoryTypeByID then d.invType = C_Item.GetItemInventoryTypeByID(itemID) end
	local okT, tip
	if slot then okT, tip = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
	else okT, tip = pcall(C_TooltipInfo.GetItemByID, itemID) end
	if okT and tip and tip.lines then
		d.tip = {}
		for i, l in ipairs(tip.lines) do
			if i > 12 then break end
			table.insert(d.tip, (l.leftText or "") .. " | " .. (l.rightText or ""))
		end
	end
	return d
end

-- ===== Slots de profissão =====
local function GetSlots(prof)
	if C_TradeSkillUI.GetProfessionSlots and prof.profession then
		local ok, slots = pcall(C_TradeSkillUI.GetProfessionSlots, prof.profession)
		if ok and type(slots) == "table" and #slots > 0 then return slots end
	end
	if not GetProfessions then return nil end
	local p1, p2 = GetProfessions()
	for idx, base in pairs({ [p1 or -1] = 20, [p2 or -2] = 23 }) do
		if idx and idx > 0 then
			local _, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
			if skillLine == prof.parentProfessionID then return { base, base + 1, base + 2 } end
		end
	end
	return nil
end

local function ReadGear(prof)
	local slots = GetSlots(prof)
	local gear = {}
	if not slots then return gear end
	for i, slot in ipairs(slots) do
		local link = GetInventoryItemLink("player", slot)
		local g = { slot = slot, kind = (i == 1) and "tool" or "acc", link = link }
		if link then
			g.itemID = GetInventoryItemID("player", slot)
			g.name = C_Item.GetItemNameByID(g.itemID) or link
			local ok, tip = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
			g.stats = ParseStats(ok and tip, prof.parentProfessionName)
			local _, _, rarity, ilvl = C_Item.GetItemInfo(link)
			g.ilvl, g.rarity = ilvl, rarity
			g.cat, g.catName = UniqueCategory(g.itemID)
			g.enchant = LinkEnchant(link)
		else
			g.stats = ParseStats(nil)
		end
		table.insert(gear, g)
	end
	return gear
end



-- ===== Stats do candidato como ele sairia fabricado =====
-- O tooltip pelo itemID mostra a peça na qualidade/nível mais baixos (e ferramentas sem as
-- missivas). Para comparar de verdade, montamos o link do candidato a partir do link do item
-- equipado no mesmo slot (mesmo contexto, mesmas missivas), trocando o itemID e colocando a
-- qualidade escolhida. Bônus de qualidade do Midnight: 12499..12502 = Q2..Q5; modificador 38 = qualidade (5..8).
local TIER_BONUS = { [2] = 12499, [3] = 12500, [4] = 12501, [5] = 12502 }
local IS_TIER = { [12499] = true, [12500] = true, [12501] = true, [12502] = true }

local function BuildCraftedLink(templateLink, itemID, tier, statMod)
	if not templateLink or not itemID then return nil end
	local s = templateLink:match("item:([^|]+)")
	if not s then return nil end
	local f = {}
	for v in (s .. ":"):gmatch("([^:]*):") do table.insert(f, v) end
	local nb = tonumber(f[13] or "")
	if not nb or nb < 1 then return nil end
	local found = false
	for i = 14, 13 + nb do
		local b = tonumber(f[i] or "")
		if b and IS_TIER[b] then f[i] = tostring(TIER_BONUS[tier] or 12502); found = true end
	end
	if not found then return nil end   -- item de outra expansão: não serve de modelo
	local nm = tonumber(f[14 + nb] or "") or 0
	for k = 0, nm - 1 do
		local idx = 15 + nb + k * 2
		if f[idx] == "38" then f[idx + 1] = tostring((tier or 5) + 3) end
		if statMod and f[idx] == "29" then f[idx + 1] = tostring(statMod) end
	end
	f[1] = tostring(itemID)
	f[2] = ""   -- sem encantamento: ele é avaliado à parte
	return "item:" .. table.concat(f, ":")
end

-- qualidade (2..5) de um link fabricado no Midnight; nil se não identificar
local function LinkTier(link)
	local s = link and link:match("item:([^|]+)")
	if not s then return nil end
	for b in s:gmatch("(%d+)") do
		local n = tonumber(b)
		if IS_TIER[n] then return n - 12497 end
	end
end

-- sempre compara contra a melhor versão fabricável (qualidade máxima)
local BEST_TIER = 5

-- Ferramenta: o stat secundário é escolhido na hora de fabricar (modificador 29 do link).
-- Testa os valores possíveis e devolve cada opção distinta de stats.
local toolOptCache = {}
local function ToolStatOptions(c, templateLinks, profName)
	local key = c.itemID .. "#" .. BEST_TIER
	if toolOptCache[key] then return toolOptCache[key] end
	local opts, seen = {}, {}
	-- link real sem stat escolhido: "+N Random Stat" = N em qualquer um dos 3 stats
	if c.outLink then
		local ok, tip = pcall(C_TooltipInfo.GetHyperlink, c.outLink)
		local st, any = ParseStats(ok and tip, profName)
		if any and (st.random or 0) > 0 then
			for _, o in ipairs({ { "multicraft", ns.STAT.multicraft }, { "resourcefulness", ns.STAT.resourcefulness }, { "ingenuity", ns.STAT.ingenuity } }) do
				local s2 = { skill = st.skill, multicraft = 0, resourcefulness = 0, ingenuity = 0 }
				s2[o[1]] = st.random
				table.insert(opts, { stats = s2, label = o[2] })
			end
			toolOptCache[key] = opts
			return opts
		end
	end
	for _, tl in ipairs(templateLinks) do
		if tl and tl:find(":29:", 1, true) then
			for v = 40, 140 do
				local link = BuildCraftedLink(tl, c.itemID, BEST_TIER, v)
				if link then
					local ok, tip = pcall(C_TooltipInfo.GetHyperlink, link)
					local st, any = ParseStats(ok and tip, profName)
					if any and (st.multicraft + st.resourcefulness + st.ingenuity) > 0 then
						local sig = st.multicraft .. "/" .. st.resourcefulness .. "/" .. st.ingenuity
						if not seen[sig] then
							seen[sig] = true
							local label = (st.multicraft > 0 and ns.STAT.multicraft) or (st.resourcefulness > 0 and ns.STAT.resourcefulness) or ns.STAT.ingenuity
							table.insert(opts, { stats = st, label = label, mod = v })
						end
					end
				end
			end
			if #opts > 0 then break end
		end
	end
	-- tooltip ainda não carregado (dados assíncronos): só guarda quando achou as 3 opções
	if #opts >= 3 then toolOptCache[key] = opts end
	return opts
end

local function CraftedStats(c, templateLinks, profName)
	-- 1º: link real do jogo (receita na qualidade máxima), lido no scan de quem fabrica
	if c.outLink then
		local ok, tip = pcall(C_TooltipInfo.GetHyperlink, c.outLink)
		local st, any = ParseStats(ok and tip, profName)
		if any then return st, true, c.outLink end
	end
	local tier = BEST_TIER
	for _, tl in ipairs(templateLinks) do
		local link = BuildCraftedLink(tl, c.itemID, tier)
		if link then
			local ok, tip = pcall(C_TooltipInfo.GetHyperlink, link)
			local st, any = ParseStats(ok and tip, profName)
			if any then return st, true, link end
		end
	end
	return nil
end

-- ===== Candidatos: peças da profissão que algum personagem seu fabrica =====
local function FindCandidates(profName)
	local out, seen = {}, {}
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			-- receitas conhecidas e as ainda não aprendidas (a versão épica pode estar só nas desconhecidas)
			local all = {}
			for _, r in ipairs(e.rows or {}) do table.insert(all, r) end
			for _, r in ipairs(e.unknown or {}) do
				table.insert(all, setmetatable({ excluded = true }, { __index = r }))
			end
			for _, r in ipairs(all) do
				local id = r.itemID
				-- mesma peça fabricada por mais de um personagem: fica com o menor custo de fabricar
				if id and seen[id] and not r.excluded and r.cost then
					local c0 = seen[id]
					if type(c0) == "table" and not c0.outLink and r.outLink then c0.outLink = r.outLink end
					if type(c0) == "table" and (not c0.craftCost or r.cost < c0.craftCost) then
						c0.craftCost, c0.crafter, c0.craftMissing = r.cost, char:match("^[^-]+"), nil
					end
				end
				if id and not seen[id] then
					local _, _, subType, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
					if (equipLoc == "INVTYPE_PROFESSION_TOOL" or equipLoc == "INVTYPE_PROFESSION_GEAR")
						and subType and profName and subType == profName then
						seen[id] = true
						local ok, tip = pcall(C_TooltipInfo.GetItemByID, id)
						local st, any = ParseStats(ok and tip, profName)
						if not any and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
						local _, _, quality = C_Item.GetItemInfo(id)
						if not quality and C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(id) end
						local catID, catName = UniqueCategory(id)
						local cand = {
							cat = catID, catName = catName,
							itemID = id,
							outLink = r.outLink,
							name = r.name,
							kind = equipLoc == "INVTYPE_PROFESSION_TOOL" and "tool" or "acc",
							rarity = quality,
							stats = st,
							statsKnown = any,
							crafter = char:match("^[^-]+"),
							craftCost = (not r.excluded) and r.cost or nil,
							craftMissing = r.excluded,
							buy = (r.outLink and P.BuyByLink and P.BuyByLink(r.outLink)) or (P.Buy and P.Buy(id)) or nil,
						}
						seen[id] = cand
						table.insert(out, cand)
					end
				end
			end
		end
	end
	return out
end

-- ===== Custo de concentração para outra skill =====
local csCache = {}
local function CraftSimRecipe(recipeID)
	if not CraftSimAPI or not CraftSimAPI.GetRecipeData then return nil end
	if csCache[recipeID] ~= nil then return csCache[recipeID] or nil end
	local ok, rd = pcall(CraftSimAPI.GetRecipeData, CraftSimAPI, { recipeID = recipeID })
	csCache[recipeID] = (ok and rd) or false
	return ok and rd or nil
end

-- devolve custo de conc com skill S (sem ingenuity) e o método usado
local function ConcCostAt(r, S)
	local D, S0, c0 = r.difficulty, r.skill, r.concCost
	if not (D and S0 and c0) then return nil end
	if S >= D then return 0, "q2" end
	local rd = CraftSimRecipe(r.recipeID)
	if rd and rd.GetConcentrationCostForSkill then
		local ok1, cNow = pcall(rd.GetConcentrationCostForSkill, rd, S0, true)
		local ok2, cNew = pcall(rd.GetConcentrationCostForSkill, rd, S, true)
		if ok1 and ok2 and cNow and cNew and cNow > 0 then
			-- ajusta pela diferença entre o CraftSim e o valor real do jogo
			return c0 * (cNew / cNow), "CraftSim"
		end
	end
	local gap0 = D - S0
	if gap0 <= 0 then return c0, "aprox" end
	return c0 * math.max(D - S, 0) / gap0, "aprox"
end

-- ===== Valor semanal da profissão com um delta de stats =====
-- d = { skill, mc, res, ing } (mc/res/ing como fração, ex. 0.01 = 1%)
-- Conta só o que a concentração da semana fabrica: toda ela vai para as receitas de maior ouro/ponto.
local function WeeklyValue(entry, d)
	d = d or {}
	local budget = ConcPerWeek()
	local cut = Cfg("ahCut")
	local opts, natural = {}, {}
	local method
	for _, r in ipairs(entry.rows or {}) do
		local okConc = ns.Recommendable(r, true)
		if r.concSale and r.concCost and r.skill and r.difficulty and not r.excluded and r.sale
			and okConc and not r.concBeaten then
			-- d.recipes (opcional): delta vale só para essas receitas (nó de especialização)
			local on = not d.recipes or d.recipes[r.recipeID]
			local dd = on and d or {}
			local st0 = r.stats or { mc = 0, res = 0, ing = 0 }
			local st = { mc = st0.mc + (dd.mc or 0), res = st0.res + (dd.res or 0), ing = st0.ing + (dd.ing or 0) }
			local q = ns.Scanner.ExpectedItems(r.qty, st, r.recipeID, ns.CharKey(), entry.sig)
			if dd.mcExtra and q > r.qty then q = q + (q - r.qty) * dd.mcExtra end
			local cost = ns.Scanner.ExpectedCost(r.cost, st)
			local p1 = r.sale * q * (1 - cut) - cost
			local p2 = r.concSale * q * (1 - cut) - cost
			-- só conta o que a concentração fabrica: lucro do craft feito com concentração
			local gain = p2
			-- d.skillBy (opcional): perícia extra por receita (nós da especialização que afetam cada uma)
			local S = r.skill + (dd.skill or 0) + (d.skillBy and d.skillBy[r.recipeID] or 0)
			local c, how = ConcCostAt(r, S)
			if c and dd.concReduce then c = c * (1 - dd.concReduce) end
			if gain > 0 and okConc then
				if how == "q2" then
					-- já sai na qualidade alta sem concentração: não gasta concentração (fica só como informação)
					table.insert(natural, { row = r, gain = gain })
				elseif c and c > 0 then
					local refund = r.ingRefund and r.concCost > 0 and (r.ingRefund * c / r.concCost) or c * 0.5
					if dd.refundInc then refund = math.min(c, refund + c * dd.refundInc) end
					local eff = math.max(c - (Cfg("useStats") and st.ing * refund or 0), 1)
					table.insert(opts, { row = r, per = gain / eff, eff = eff, gain = gain, cap = cap })
					if how == "CraftSim" then method = "CraftSim" end
				end
			end
		end
	end
	table.sort(opts, function(a, b) return a.per > b.per end)
	local left, total, used = budget, 0, {}
	for _, o in ipairs(opts) do
		-- média semanal: a sobra de concentração passa para a semana seguinte, então conta fração de craft
		local n = left / o.eff
		if n > 0 then
			left = left - n * o.eff
			total = total + n * o.gain
			table.insert(used, { row = o.row, crafts = n, per = o.per, gold = n * o.gain })
		end
	end
	table.sort(natural, function(a, b) return a.gain > b.gain end)
	local natTotal = 0
	local best = opts[1]
	return total, {
		perConc = best and best.per or 0, row = best and best.row, method = method or "aprox",
		used = used, concGold = total, natural = natural, naturalGold = natTotal, leftover = left,
	}
end
-- valor base (sem delta) é pedido muitas vezes (Comprar receitas, Segunda profissão, Investimento):
-- guardado por entrada até a próxima reprecificação (Scanner.gen), troca de personagem ou 30 s
local wvBase = setmetatable({}, { __mode = "k" })
local function WeeklyValueCached(entry, d)
	if d ~= nil or type(entry) ~= "table" then return WeeklyValue(entry, d) end
	local c = wvBase[entry]
	local now, gen, me = GetTime(), ns.Scanner and ns.Scanner.gen or 0, ns.CharKey()
	if c and c.gen == gen and c.me == me and now - c.t < 30 then return c.v, c.info end
	local v, info = WeeklyValue(entry)
	wvBase[entry] = { v = v, info = info, gen = gen, me = me, t = now }
	return v, info
end
Invest.WeeklyValue = WeeklyValueCached
Invest.ConcPerWeek = ConcPerWeek

-- nome do degrau da escada de perícia
function Invest.LadderLabel(l)
	if l.label == "gear" then return L["Equipamento"] end
	if l.label == "max" then return L["Máximo"] end
	local pct = math.floor((l.frac or 0) * 100 + 0.5)
	if (l.gearSkill or 0) > 0 then return string.format(L["Equip. + %d%% pts"], pct) end
	return string.format(L["%d%% dos pontos"], pct)
end

local function Delta(new, old)
	local a, b = ToFractions(new or {}), ToFractions(old or {})
	return { skill = a.skill - b.skill, mc = a.mc - b.mc, res = a.res - b.res, ing = a.ing - b.ing }
end


-- ===== Árvore de especialização (aba → orbe/nó → dentes/marcos) =====
-- Nomes, ranks e em que rank cada perk libera vêm da API do jogo (C_ProfSpecs/C_Traits).
-- Quanto cada nó/perk dá e quais receitas ele afeta vêm dos dados do CraftSim (se instalado).
local function CraftSimSpecData(prof)
	if not CraftSimAPI or not CraftSimAPI.GetCraftSim then return nil end
	local ok, CS = pcall(CraftSimAPI.GetCraftSim, CraftSimAPI)
	if not ok or not CS or not CS.SPECIALIZATION_DATA or not CS.CONST then return nil end
	local exp = CS.CONST.EXPANSION_IDS and CS.CONST.EXPANSION_IDS.MIDNIGHT
	local byExp = exp and CS.SPECIALIZATION_DATA.NODE_DATA and CS.SPECIALIZATION_DATA.NODE_DATA[exp]
	return byExp and prof.profession and byExp[prof.profession] or nil
end

local function DefName(configID, nodeID)
	local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
	if not ok or not info then return nil, nil end
	local name
	for _, entryID in ipairs(info.entryIDs or {}) do
		local e = C_Traits.GetEntryInfo(configID, entryID)
		local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
		if def and def.overrideName then name = def.overrideName break end
	end
	return name, info
end

-- converte stats do CraftSim (ratings e %) para o delta usado no cálculo
local function StatsToDelta(stats, mult)
	local f = ns.Scanner.STAT_FACTOR
	mult = mult or 1
	local d = { skill = 0, mc = 0, res = 0, ing = 0 }
	for k, v in pairs(stats or {}) do
		v = v * mult
		if k == "skill" then d.skill = d.skill + v
		elseif k == "multicraft" then d.mc = d.mc + v / f.multicraft
		elseif k == "resourcefulness" then d.res = d.res + v / f.resourcefulness
		elseif k == "ingenuity" then d.ing = d.ing + v / f.ingenuity
		elseif k == "reduceconcentrationcost" then d.concReduce = (d.concReduce or 0) + v / 100
		elseif k == "ingenuityrefundincrease" then d.refundInc = (d.refundInc or 0) + v / 100
		elseif k == "additionalitemscraftedwithmulticraft" then d.mcExtra = (d.mcExtra or 0) + v / 100
		end
	end
	return d
end

local function AddDelta(a, b)
	local out = {}
	for k, v in pairs(a) do out[k] = v end
	for k, v in pairs(b) do if type(v) == "number" then out[k] = (out[k] or 0) + v end end
	return out
end

local function StatsText(stats)
	local t = {}
	local label = { skill = ns.STAT.skill, multicraft = ns.STAT.multicraft, resourcefulness = ns.STAT.resourcefulness, ingenuity = ns.STAT.ingenuity,
		craftingspeed = L["% velocidade"], reduceconcentrationcost = L["% menos concentração"],
		ingenuityrefundincrease = L["% reembolso de ingenuity"], additionalitemscraftedwithmulticraft = L["% itens extras no multicraft"],
		unlockreagentslot = L["slot de reagente"] }
	for k, v in pairs(stats or {}) do
		if k == "unlockreagentslot" then
			table.insert(t, L["libera slot de reagente"])
		else
			table.insert(t, string.format("+%s %s", tostring(v), label[k] or k))
		end
	end
	return table.concat(t, ", ")
end

-- dente que mexe nas CARGAS de uma receita com recarga (transmutações, Wondrous Synergist...):
--   "Gain an additional charge of X" / "Gain 2 additional charges of X" / "Gain a second charge of X" -> cap (máximo)
--   "X recharges quicker" -> rate (recarrega mais rápido; o jogo não diz quanto)
-- devolve { kind, n, target, text } ou nil. target = nome entre as cores ou "transmut" pelo nome do nó.
local WORDN = { an = 1, a = 1, one = 1, second = 1, third = 1, fourth = 1, two = 2, three = 3, uma = 1, mais = 1 }
local function ChargePerk(desc, nodeName)
	if type(desc) ~= "string" then return nil end
	local target = desc:match("|c%x%x%x%x%x%x%x%x(.-)|r")
	local d = desc:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local kind
	if d:find("recharge") or d:find("recarrega") then kind = "rate"
	elseif d:find("charge") or d:find("carga") then kind = "cap" end
	if not kind then return nil end
	local n = tonumber(d:match("(%d+)%s+%a*%s*charge") or d:match("(%d+)%s+%a*%s*carga") or "")
	if not n then
		local w = d:match("(%a+)%s+additional") or (d:find("second") and "second") or (d:find("third") and "third")
		n = WORDN[w or ""] or 1
	end
	if not target and nodeName and nodeName:lower():find("transmut") then target = "transmut" end
	local text = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return { kind = kind, n = n, target = target, text = text }
end
Invest.ChargePerk = ChargePerk

-- receitas do personagem que a carga afeta: pelo nome (receita ou item) ou todas as transmutações
local function ChargeTargets(entry, target)
	local out = {}
	if not target then return out end
	local t = target:lower()
	for _, r in ipairs(entry.rows or {}) do
		local rn, it = (r.name or ""):lower(), (r.itemName or ""):lower()
		if (rn == t or it == t) or (t:find("transmut") and ns.IsTransmute and ns.IsTransmute(r)) then table.insert(out, r) end
	end
	return out
end

-- lucro esperado de 1 carga: a melhor receita afetada (0 se todas dão prejuízo)
local function ChargeValue(entry, target)
	local best
	for _, r in ipairs(ChargeTargets(entry, target or "transmut")) do
		if r.profit and not r.excluded and (not best or r.profit > best.profit) then best = r end
	end
	return best and math.max(0, best.profit) or 0, best
end
Invest.ChargeValue = ChargeValue

-- dentes de carga/recarga ainda não conquistados; ordenados por pontos
function Invest.ChargePerks(entry, filter)
	local spec = entry and entry.invest and entry.invest.spec
	local list = {}
	for _, tab in ipairs(spec and spec.tabs or {}) do
		for _, node in ipairs(tab.nodes or {}) do
			for _, t in ipairs(node.teeth or {}) do
				local c = t.cd or ChargePerk(t.desc, node.name)
				if c and not t.earned and (not filter or filter(c)) then
					table.insert(list, { node = node.name, tab = tab.name, locked = node.locked, kind = c.kind, n = c.n, target = c.target, text = c.text,
						points = t.threshold - math.max(node.rank or 0, 0) + (node.locked and 1 or 0), threshold = t.threshold })
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.points < b.points end)
	return list
end
function Invest.NextCharge(entry)
	local l = Invest.ChargePerks(entry, function(c) return c.target and c.target:lower():find("transmut") end)
	return l[1]
end

local function ReadSpecTree(entry, prof, base)
	if not C_ProfSpecs or not C_ProfSpecs.GetSpecTabIDsForSkillLine then return nil end
	local skillLine = prof.professionID
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLine)
	if not configID then return nil end
	local raw = CraftSimSpecData(prof)
	-- quais das SUAS receitas cada nó afeta (a partir do mapeamento do CraftSim)
	local affects = {}
	if raw and raw.recipeMapping and raw.nodeData then
		for recipeID, ids in pairs(raw.recipeMapping) do
			for _, id in ipairs(ids) do
				local nd = raw.nodeData[id]
				local baseID = nd and nd.nodeID or id
				affects[baseID] = affects[baseID] or {}
				affects[baseID][recipeID] = true
			end
		end
	end
	local myRecipes = {}
	for _, r in ipairs(entry.rows or {}) do myRecipes[r.recipeID] = r end

	local tabs = {}
	for _, tabID in ipairs(C_ProfSpecs.GetSpecTabIDsForSkillLine(skillLine) or {}) do
		local tinfo = C_ProfSpecs.GetTabInfo(tabID)
		local tab = { name = tinfo and tinfo.name or (L["aba "] .. tabID), nodes = {} }
		local queue = { C_ProfSpecs.GetRootPathForTab(tabID) }
		local depth = { [queue[1] or 0] = 0 }
		while #queue > 0 do
			local pathID = table.remove(queue, 1)
			if pathID then
				for _, child in ipairs(C_ProfSpecs.GetChildrenForPath(pathID) or {}) do
					depth[child] = (depth[pathID] or 0) + 1
					table.insert(queue, child)
				end
				local name, ninfo = DefName(configID, pathID)
				local rank = ninfo and ninfo.activeRank and (ninfo.activeRank - 1) or -1
				local rawBase = raw and raw.nodeData and raw.nodeData[pathID]
				local maxRank = rawBase and rawBase.maxRank or (ninfo and ninfo.maxRanks and ninfo.maxRanks - 1) or 0
				local state = C_ProfSpecs.GetStateForPath and C_ProfSpecs.GetStateForPath(pathID, configID)
				local node = {
					id = pathID, name = name or (L["nó "] .. pathID), depth = depth[pathID] or 0,
					rank = rank, max = maxRank, locked = (state == (Enum.ProfessionsSpecPathState and Enum.ProfessionsSpecPathState.Locked)),
					perRank = rawBase and rawBase.stats, teeth = {},
				}
				-- receitas suas afetadas por este nó
				local set, n = {}, 0
				for recipeID in pairs(affects[pathID] or {}) do
					if myRecipes[recipeID] then set[recipeID] = true; n = n + 1 end
				end
				node.recipeSet, node.nRecipes = set, n
				-- dentes (perks) ordenados pelo rank em que liberam
				local perks = C_ProfSpecs.GetPerksForPath and C_ProfSpecs.GetPerksForPath(pathID) or {}
				for _, pk in ipairs(perks) do
					local th = C_ProfSpecs.GetUnlockRankForPerk(pk.perkID)
					local rawPerk = raw and raw.nodeData and raw.nodeData[pk.perkID]
					local earned = th and rank >= th
					local okD, fullDesc = pcall(C_ProfSpecs.GetDescriptionForPerk or function() end, pk.perkID)
					fullDesc = okD and fullDesc or nil
					local ch = ChargePerk(fullDesc, name)
					table.insert(node.teeth, {
						perkID = pk.perkID, threshold = th or 0, earned = earned, major = pk.isMajorPerk,
						stats = rawPerk and rawPerk.stats,
						desc = (not rawPerk or ch) and fullDesc or nil,
						cd = ch,
					})
					if ch then node.cdPerks = true end
				end
				table.sort(node.teeth, function(a, b) return a.threshold < b.threshold end)
				-- pontos restantes depois do último dente (cada ponto ainda dá os stats do orbe)
				local lastTh = rank
				for _, t in ipairs(node.teeth) do if not t.earned and t.threshold > lastTh then lastTh = t.threshold end end
				if maxRank and maxRank > lastTh and node.perRank then
					table.insert(node.teeth, { threshold = maxRank, earned = false, final = true })
				end
				node.remaining = maxRank and rank < maxRank
				-- valor de chegar em cada dente ainda não conquistado (acumulado desde o rank atual)
				if n > 0 then
					-- perks de dentes anteriores (ainda não conquistados) se acumulam até o dente avaliado
					local accPerks = { skill = 0, mc = 0, res = 0, ing = 0 }
					local fromRank = math.max(rank, 0)
					for _, t in ipairs(node.teeth) do
						if not t.earned then
							local pts = t.threshold - rank
							local ranks = t.threshold - fromRank
							local perkDelta = StatsToDelta(t.stats)
							local d = AddDelta(AddDelta(accPerks, StatsToDelta(node.perRank, math.max(ranks, 0))), perkDelta)
							d.recipes = set
							local v = WeeklyValue(entry, d)
							t.points, t.gain = pts, v - base
							t.perPoint = pts > 0 and t.gain / pts or nil
							accPerks = AddDelta(accPerks, perkDelta)
						end
					end
				end
				table.insert(tab.nodes, node)
			end
		end
		table.insert(tabs, tab)
	end
	return { tabs = tabs, hasCraftSim = raw ~= nil }
end

-- ===== Especialização de coleta (Erva/Minério/Esfolamento) =====
-- O CraftSim não tem os dados da Midnight para coleta: lê a árvore do jogo e tira os atributos do texto
-- ("+15 Perception", "Finesse by 3 for each point", "+10 Herbalism Skill"...). Flags: coletar montado, Overload.
local GSTAT_WORDS = {
	finesse = { "finesse", "fineza" },
	perception = { "perception", "percepção", "percepcao" },
	deftness = { "deftness", "destreza" },
	skill = { "skill", "perícia", "pericia" },
}
local function GatherTextStats(txt)
	if type(txt) ~= "string" or txt == "" then return nil end
	local low = txt:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local st, any = {}, false
	for k, words in pairs(GSTAT_WORDS) do
		for _, w in ipairs(words) do
			local loc = (k ~= "skill" and ns.STAT[k] or ""):lower()
			for _, ww in ipairs({ w, loc }) do
				if ww ~= "" and not st[k] then
					local n = low:match("%+?(%d+)%s+[%a%s]-" .. ww) or low:match(ww .. "[^%d%%]-(%d+)")
					if n then st[k] = tonumber(n); any = true end
				end
			end
		end
	end
	local flags = {}
	if low:find("mount", 1, true) or low:find("montad", 1, true) then flags.mounted = true end
	if low:find("overload", 1, true) or low:find("sobrecarg", 1, true) then flags.overload = true end
	return any and st or nil, flags
end
Invest._GatherTextStats = GatherTextStats

local function ReadGatherSpec(prof)
	if not (C_ProfSpecs and C_ProfSpecs.GetSpecTabIDsForSkillLine and prof and prof.professionID) then return nil end
	local skillLine = prof.professionID
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLine)
	if not configID then return nil end
	local function desc(fn, ...)
		if not fn then return nil end
		local ok, d = pcall(fn, ...)
		return ok and type(d) == "string" and d or nil
	end
	local tabs = {}
	for _, tabID in ipairs(C_ProfSpecs.GetSpecTabIDsForSkillLine(skillLine) or {}) do
		local tinfo = C_ProfSpecs.GetTabInfo(tabID)
		local tab = { name = tinfo and tinfo.name or (L["aba "] .. tabID), nodes = {} }
		local queue = { C_ProfSpecs.GetRootPathForTab(tabID) }
		local depth = { [queue[1] or 0] = 0 }
		while #queue > 0 do
			local pathID = table.remove(queue, 1)
			if pathID then
				for _, child in ipairs(C_ProfSpecs.GetChildrenForPath(pathID) or {}) do
					depth[child] = (depth[pathID] or 0) + 1
					table.insert(queue, child)
				end
				local name, ninfo = DefName(configID, pathID)
				local rank = ninfo and ninfo.activeRank and (ninfo.activeRank - 1) or -1
				local maxRank = ninfo and ninfo.maxRanks and ninfo.maxRanks - 1 or 0
				local state = C_ProfSpecs.GetStateForPath and C_ProfSpecs.GetStateForPath(pathID, configID)
				local pdesc = desc(C_ProfSpecs.GetDescriptionForPath, pathID)
				local perRank = GatherTextStats(pdesc)
				local node = { id = pathID, name = name or (L["nó "] .. pathID), depth = depth[pathID] or 0, rank = rank, max = maxRank,
					locked = (state == (Enum.ProfessionsSpecPathState and Enum.ProfessionsSpecPathState.Locked)), perRank = perRank, desc = pdesc, teeth = {} }
				for _, pk in ipairs(C_ProfSpecs.GetPerksForPath and C_ProfSpecs.GetPerksForPath(pathID) or {}) do
					local th = C_ProfSpecs.GetUnlockRankForPerk(pk.perkID)
					local d = desc(C_ProfSpecs.GetDescriptionForPerk, pk.perkID)
					local st, flags = GatherTextStats(d)
					table.insert(node.teeth, { perkID = pk.perkID, threshold = th or 0, earned = th and rank >= th, stats = st, flags = flags, desc = d })
				end
				table.sort(node.teeth, function(a, b) return a.threshold < b.threshold end)
				if maxRank > rank and perRank then
					local lastTh = rank
					for _, t in ipairs(node.teeth) do if not t.earned and t.threshold > lastTh then lastTh = t.threshold end end
					if maxRank > lastTh then table.insert(node.teeth, { threshold = maxRank, earned = false, final = true }) end
				end
				table.insert(tab.nodes, node)
			end
		end
		table.insert(tabs, tab)
	end
	return { tabs = tabs, time = time() }
end
Invest._ReadGatherSpec = ReadGatherSpec

-- ===== Avaliação (roda a cada scan) =====
function Invest.Evaluate(entry, prof)
	if not entry or not prof then return end
	-- profissão de coleta: o addon não calcula lucro de coleta; a aba mostra só os buffs temporários dela
	if entry.gathering then
		local okS, gspec = pcall(ReadGatherSpec, prof)
		entry.invest = { gathering = true, time = time(), gspec = okS and gspec or nil }
		if Invest.Refresh then Invest.Refresh() end
		return
	end
	local gear = ReadGear(prof)
	local base, info0 = WeeklyValue(entry)
	local inv = { gear = gear, base = base, info = info0, time = time() }

	-- valor de cada stat
	local function dv(d) local v = WeeklyValue(entry, d); return v - base end
	inv.values = {
		skill10 = dv({ skill = 10 }),
		mc1 = dv({ mc = 0.01 }),
		res1 = dv({ res = 0.01 }),
		ing1 = dv({ ing = 0.01 }),
	}

	-- candidatos
	local cands = FindCandidates(prof.parentProfessionName or entry.name)
	inv.itemDebug = {}
	for _, g in ipairs(gear) do
		if g.itemID then table.insert(inv.itemDebug, ItemDebug(g.itemID, g.link, g.slot)) end
	end
	for _, c in ipairs(cands) do table.insert(inv.itemDebug, ItemDebug(c.itemID)) end

	-- compara cada peça só pelos stats (skill, multicraft, resourcefulness, ingenuity) contra o que está
	-- equipado; acessórios são avaliados contra os dois slots de acessório, independente de nome ou raridade
	local had = {}
	for _, n in ipairs(info0.natural) do had[n.row.recipeID] = true end
	local profName = prof.parentProfessionName or entry.name
	local function EvalAgainst(c, g)
		local same = g and g.itemID and g.itemID == c.itemID
		-- mesma peça: só interessa se a sua está abaixo da qualidade máxima
		-- (ferramenta: sempre avalia, porque dá para refazer com outro stat)
		if same and c.kind ~= "tool" and (LinkTier(g.link) or BEST_TIER) >= BEST_TIER then return nil end
		-- modelo: o item equipado neste slot; para acessório, o outro acessório também serve
		local templates = {}
		if g and g.link then table.insert(templates, g.link) end
		if c.kind ~= "tool" then
			for _, o in ipairs({ gear[2], gear[3] }) do
				if o and o ~= g and o.link then table.insert(templates, o.link) end
			end
		end
		local cst, known = CraftedStats(c, templates, profName)
		local stats = cst or c.stats
		if known then c.craftedKnown = true end
		if not known and not c.statsKnown then return nil end   -- sem stats: não dá para comparar
		local cur = g and g.stats
		local enchOpt, statChoice, allChoices
		if c.kind == "tool" then
			-- ferramenta nova: escolhe o melhor stat entre as opções de fabricação.
			-- Encantamento fica de fora dos dois lados (é avaliado na seção própria de encantamento).
			cur = g and g.stats
			local choices = ToolStatOptions(c, templates, profName)
			if #choices == 0 then choices = { { stats = stats, label = nil } } end
			allChoices = {}
			local bestV
			for _, ch in ipairs(choices) do
				local vv = WeeklyValue(entry, Delta(ch.stats, cur))
				if not bestV or vv > bestV then bestV, statChoice, stats = vv, ch, ch.stats end
				if ch.label then table.insert(allChoices, { label = ch.label, gain = vv - base }) end
			end
		end
		local d = Delta(stats, cur)
		local v, info = WeeklyValue(entry, d)
		local res = { gain = v - base, delta = d, newNatural = {}, stats = stats, crafted = known,
			sameUpgrade = same and (LinkTier(g.link) or BEST_TIER) < BEST_TIER and LinkTier(g.link) or nil,
			same = same or nil }
		for _, n in ipairs(info.natural) do
			if not had[n.row.recipeID] then table.insert(res.newNatural, { name = n.row.name, gain = n.gain, spd = n.row.concSpd }) end
		end
		res.statChoice = statChoice and statChoice.label
		res.allChoices = allChoices
		if enchOpt then
			res.enchant = enchOpt
			res.enchantPrice = P.Buy(enchOpt.itemID)
			res.totalPrice = c.price and (c.price + (res.enchantPrice or 0)) or nil
		else
			res.totalPrice = c.price
		end
		res.payback = (res.totalPrice and res.gain > 0) and (res.totalPrice / res.gain) or nil
		-- raridade menor que o item atual e mesmo assim melhor
		res.beatsHigherRarity = (not same) and g and g.rarity and c.rarity and c.rarity < g.rarity and res.gain > 0 or nil
		return res
	end
	for _, c in ipairs(cands) do
		local price
		if c.craftCost and c.buy then price = math.min(c.craftCost, c.buy)
		else price = c.craftCost or c.buy end
		c.price = price
		c.priceFrom = (price and c.craftCost and price == c.craftCost) and (L["fabricar ("] .. (c.crafter or "?") .. ")") or L["comprar"]
		c.bySlot = {}
		if c.kind == "tool" then
			c.bySlot[1] = EvalAgainst(c, gear[1])
		else
			-- acessório só entra no slot do mesmo tipo (categoria de único equipado)
			local g2, g3 = gear[2], gear[3]
			local c2, c3 = g2 and g2.cat, g3 and g3.cat
			if g2 and g2.itemID == c.itemID then
				c.bySlot[2] = EvalAgainst(c, g2)   -- mesma peça: só no slot onde ela já está
			elseif g3 and g3.itemID == c.itemID then
				c.bySlot[3] = EvalAgainst(c, g3)
			elseif c.cat and c2 == c.cat then
				c.bySlot[2] = EvalAgainst(c, g2)
			elseif c.cat and c3 == c.cat then
				c.bySlot[3] = EvalAgainst(c, g3)
			elseif c.cat and g2 and not g2.link and (c3 ~= nil) then
				c.bySlot[2] = EvalAgainst(c, g2)   -- slot vazio e o outro já tem outro tipo
			elseif c.cat and g3 and not g3.link and (c2 ~= nil) then
				c.bySlot[3] = EvalAgainst(c, g3)
			else
				-- tipo desconhecido: avalia nos dois (o jogo decide ao equipar)
				c.bySlot[2] = EvalAgainst(c, g2)
				c.bySlot[3] = EvalAgainst(c, g3)
				c.typeUnknown = true
			end
		end
		-- melhor resultado entre os slots (para ordenação geral)
		for _, r in pairs(c.bySlot) do
			if not c.gain or r.gain > c.gain then c.gain, c.payback = r.gain, r.payback end
		end
	end
	-- encantar a ferramenta atual
	inv.enchants = {}
	local tool = gear[1]
	if tool and tool.link then
		inv.toolEnchant = tool.enchant
		local cur = AddStats(tool.stats, EnchantStats(tool.enchant))
		for _, o in ipairs(TOOL_ENCHANTS) do
			if o.enchantID ~= tool.enchant then
				local new = AddStats(tool.stats, { [o.stat] = o.value })
				local v = WeeklyValue(entry, Delta(new, cur))
				local price = P.Buy(o.itemID)
				local gain = v - base
				if gain > 0 then
					table.insert(inv.enchants, { opt = o, gain = gain, price = price,
						payback = price and price / gain or nil })
				end
			end
		end
		table.sort(inv.enchants, function(a, b)
			local pa, pb = a.payback or math.huge, b.payback or math.huge
			if pa ~= pb then return pa < pb end
			return a.gain > b.gain
		end)
	end

	table.sort(cands, function(a, b)
		local pa, pb = a.payback or math.huge, b.payback or math.huge
		if pa ~= pb then return pa < pb end
		return (a.gain or 0) > (b.gain or 0)
	end)
	inv.cands = cands

	local okSpec, spec = pcall(ReadSpecTree, entry, prof, base)
	if okSpec then inv.spec = spec else ns.Log(L["especialização: "] .. tostring(spec)) end

	-- Próximos marcos: receitas que passam a sair na qualidade de cima sem concentração.
	-- need = perícia que falta com os reagentes mais baratos; needTop = com todos os reagentes ★ superior.
	-- Só entra se for alcançável: needTop <= perícia que ainda dá para ganhar na especialização
	-- (nós que afetam a receita, dados do CraftSim) + melhor troca de equipamento por espaço.
	-- melhor troca de equipamento por espaço, em perícia (peça que dá mais perícia que a atual)
	local gearRoom, gearBest = 0, {}
	for idx = 1, 3 do
		local curSkill = ((gear[idx] or {}).stats or {}).skill or 0
		local best, bestC = 0, nil
		for _, cnd in ipairs(inv.cands or {}) do
			local res = cnd.bySlot and cnd.bySlot[idx]
			local sk = res and res.stats and res.stats.skill
			if sk and sk - curSkill > best then best, bestC = sk - curSkill, cnd end
		end
		if bestC then
			gearRoom = gearRoom + best
			table.insert(gearBest, { kind = "gear", name = bestC.name, itemID = bestC.itemID, skill = best,
				price = bestC.buy or bestC.craftCost })
		end
	end
	-- perícia que ainda falta pegar na árvore, por receita, com os nós de onde vem
	local specRoom, specNodes
	if inv.spec and inv.spec.hasCraftSim then
		specRoom, specNodes = {}, {}
		for _, tab in ipairs(inv.spec.tabs or {}) do
			for _, node in ipairs(tab.nodes or {}) do
				local per = node.perRank and node.perRank.skill or 0
				local left = math.max((node.max or 0) - math.max(node.rank or 0, 0), 0)
				local room = per * left
				for _, t in ipairs(node.teeth or {}) do
					if not t.earned and t.stats and t.stats.skill then room = room + t.stats.skill end
				end
				if room > 0 then
					for recipeID in pairs(node.recipeSet or {}) do
						specRoom[recipeID] = (specRoom[recipeID] or 0) + room
						specNodes[recipeID] = specNodes[recipeID] or {}
						table.insert(specNodes[recipeID], { kind = "node", name = node.name, skill = room, points = left,
							locked = node.locked })
					end
				end
			end
		end
	end
	inv.milestones = {}
	inv.gearRoom = gearRoom
	-- Escada de perícia: degraus ALCANÇÁVEIS, do equipamento ao máximo da árvore.
	-- 1º degrau = melhor equipamento (vale para todas as receitas); depois 25/50/75/100% dos pontos de
	-- conhecimento que faltam, cada receita ganhando só a perícia dos nós que a afetam. Último = máximo.
	inv.ladder = {}
	local function Step(label, uni, frac, points)
		local by
		if specRoom and frac > 0 then
			by = {}
			for rid, sk in pairs(specRoom) do by[rid] = sk * frac end
		end
		local v, info = WeeklyValue(entry, { skill = uni, skillBy = by })
		local top = info.used and info.used[1]
		local maxSk = uni
		if by then for _, sk in pairs(by) do if uni + sk > maxSk then maxSk = uni + sk end end end
		table.insert(inv.ladder, {
			label = label, skill = math.floor(maxSk + 0.5), gearSkill = uni, points = points, frac = frac,
			gain = v - base, conc = info.concGold, natural = info.naturalGold,
			top = top and top.row.name, nNatural = #info.natural,
		})
	end
	local ptsLeft = 0
	if inv.spec then
		for _, tab in ipairs(inv.spec.tabs or {}) do
			for _, node in ipairs(tab.nodes or {}) do
				ptsLeft = ptsLeft + math.max((node.max or 0) - math.max(node.rank or 0, 0), 0)
			end
		end
	end
	inv.ptsLeft = ptsLeft
	if gearRoom > 0 then Step("gear", gearRoom, 0, 0) end
	if specRoom and next(specRoom) then
		for _, f in ipairs({ 0.25, 0.5, 0.75, 1 }) do
			Step(f == 1 and "max" or "know", gearRoom, f, math.floor(ptsLeft * f + 0.5))
		end
	end
	inv.ladderNoSpec = not specRoom
	inv.ladderMaxed = #inv.ladder == 0

	local cut = Cfg("ahCut")
	for _, r in ipairs(entry.rows or {}) do
		if r.skill and r.difficulty and r.difficulty > r.skill and r.concSale and r.sale and not r.excluded and not r.mix then
			local q = r.expQty or r.qty
			local cost = r.expCost or r.cost
			local p1 = r.sale * q * (1 - cut) - cost
			local p2 = r.concSale * q * (1 - cut) - cost
			if p2 > math.max(p1, 0) then
				local need = r.difficulty - r.skill
				local needTop = r.skillTop and math.max(r.difficulty - r.skillTop, 0) or need
				local room = specRoom and ((specRoom[r.recipeID] or 0) + gearRoom) or nil
				-- inalcançável só com perícia: não é investimento, fica de fora (a concentração é do Plano)
				if not room or needTop <= room then
					-- caminho: equipamento primeiro (compra imediata), depois os nós com mais perícia
					local path, got = {}, 0
					local opts = {}
					for _, gb in ipairs(gearBest) do table.insert(opts, gb) end
					local nodes = specNodes and specNodes[r.recipeID] or {}
					table.sort(nodes, function(x, y) return x.skill > y.skill end)
					for _, nd in ipairs(nodes) do table.insert(opts, nd) end
					for _, o in ipairs(opts) do
						if got >= needTop then break end
						table.insert(path, o)
						got = got + o.skill
					end
					table.insert(inv.milestones, {
						name = r.name, need = need, needTop = needTop, room = room, gain = p2 - math.max(p1, 0),
						profit = p2, spd = r.concSpd, conc = r.concCost, recipeID = r.recipeID, path = path,
					})
				end
			end
		end
	end
	table.sort(inv.milestones, function(x, y) return x.needTop < y.needTop end)

	-- Buffs temporários de fabricação (frascos). Valor = ganho dos atributos sobre a concentração gasta
	-- numa sessão (até uma barra cheia, limitado ao que entra na semana); custo = preço do frasco.
	local perWeek = ConcPerWeek()
	local share = perWeek > 0 and math.min(1000, perWeek) / perWeek or 0
	inv.buffs = {}
	for _, b in ipairs(Invest.BUFFS) do
		local d = StatsToDelta(b.stats)
		local weekly = WeeklyValue(entry, d) - base
		local gainUse = weekly * share
		local price = P.Cost(b.itemID) or (P.Buy and P.Buy(b.itemID)) or nil
		table.insert(inv.buffs, { itemID = b.itemID, quality = b.quality, stats = b.stats, minutes = b.minutes,
			gain = gainUse, price = price, net = price and (gainUse - price) or nil, weekly = weekly })
	end

	entry.invest = inv
	-- reavaliar uma peça contra um espaço na hora de desenhar (versão épica cujo tooltip carregou depois).
	-- Fica fora do SavedVariables (função não é salva).
	Invest._reeval = Invest._reeval or setmetatable({}, { __mode = "k" })
	Invest._reeval[inv] = function(c, idx)
		local g = gear[idx]
		if not g then return nil end
		if not c.statsKnown then
			local ok, tip = pcall(C_TooltipInfo.GetItemByID, c.itemID)
			local st, any = ParseStats(ok and tip, profName)
			if any then c.stats, c.statsKnown = st, true end
		end
		if not c.cat then c.cat, c.catName = UniqueCategory(c.itemID) end
		return EvalAgainst(c, g)
	end
	if Invest.Refresh then Invest.Refresh() end
end

-- ===== Texto da aba =====
local RARITY = { [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee" }

local function StatStr(st)
	if not st then return "—" end
	local t = {}
	if (st.skill or 0) > 0 then table.insert(t, "+" .. st.skill .. " " .. ns.STAT.skill) end
	if (st.multicraft or 0) > 0 then table.insert(t, "+" .. st.multicraft .. " " .. ns.STAT.multicraft) end
	if (st.resourcefulness or 0) > 0 then table.insert(t, "+" .. st.resourcefulness .. " " .. ns.STAT.resourcefulness) end
	if (st.ingenuity or 0) > 0 then table.insert(t, "+" .. st.ingenuity .. " " .. ns.STAT.ingenuity) end
	return #t > 0 and table.concat(t, ", ") or L["sem stats"]
end

local function CurrentEntry()
	local chars = LucroCraftDB.chars or {}
	local mine = chars[ns.CharKey()] or {}
	local last = LucroCraftDB.last
	if last and mine[last.professionID] and mine[last.professionID].invest then return mine[last.professionID] end
	for _, e in pairs(mine) do if e.invest then return e end end
end

local function Render()
	local e = CurrentEntry()
	local out = {}
	local function add(s) table.insert(out, s) end
	local G = P.FormatGold
	if not e then
		add(L["Abra a profissão deste personagem para avaliar o equipamento."])
	else
		local inv = e.invest
		local perWeek, rate = ConcPerWeek()
		add(string.format(L["|cffffd100%s|r · %s   |cff9d9d9d(concentração: ~%.0f/semana, %.1f/h)|r"],
			ns.CharKey():match("^[^-]+"), e.name or "?", perWeek, rate))
		add(" ")
		add(L["|cffffd100Equipamento atual|r"])
		for _, g in ipairs(inv.gear or {}) do
			add(string.format("   %s: %s  |cff9d9d9d%s|r", g.kind == "tool" and L["Ferramenta"] or L["Acessório"],
				g.link or L["|cffff5555vazio|r"], StatStr(g.stats)))
		end
		add(" ")
		local i = inv.info or {}
		if i.used and #i.used > 0 then
			add(string.format(L["Melhor uso da concentração da semana > |cff55ff55%s|r"], G(i.concGold)))
			for k, u in ipairs(i.used) do
				if k > 4 then break end
				add(string.format(L["   ~%.1fx %s (%s/ponto) = %s"], u.crafts, u.row.name, G(u.per), G(u.gold)))
			end
		else
			add(L["|cff9d9d9dNenhuma receita dá lucro com concentração hoje.|r"])
		end
		local v = inv.values or {}
		add(string.format(L["Valor por semana de: |cffffffff+10 skill|r %s · |cffffffff+1%% multicraft|r %s · |cffffffff+1%% resourcefulness|r %s · |cffffffff+1%% ingenuity|r %s"],
			G(v.skill10, true), G(v.mc1, true), G(v.res1, true), G(v.ing1, true)))
		add(" ")
		local spec = inv.spec
		if spec and spec.tabs and #spec.tabs > 0 then
			add(L["|cffffd100Ganho de skill — especialização|r |cff9d9d9d(aba > orbe > dentes; ganho acumulado até cada dente)|r"])
			if not spec.hasCraftSim then
				add(L["   |cffff8800Sem os dados do CraftSim: mostrando só a árvore, sem o valor em ouro de cada dente.|r"])
			end
			local anyShown = false
			for _, tab in ipairs(spec.tabs) do
				-- só orbes onde ainda dá para gastar pontos (o que já foi conquistado não muda mais)
				local visible = {}
				for _, node in ipairs(tab.nodes) do
					local open = false
					for _, t in ipairs(node.teeth) do if not t.earned then open = true break end end
					if node.remaining or open then table.insert(visible, node) end
				end
				if #visible > 0 then
					anyShown = true
					add("   |cffffd100" .. tab.name .. "|r")
					for _, node in ipairs(visible) do
						local indent = string.rep("  ", node.depth or 0)
						local rk = node.rank < 0 and L["não desbloqueado"] or string.format("rank %d/%d", node.rank, node.max or 0)
						local per = node.perRank and (L[" · por ponto: "] .. StatsText(node.perRank)) or ""
						local who = node.nRecipes > 0 and string.format(L[" · afeta %d receita(s) suas"], node.nRecipes)
							or L[" · |cff9d9d9dnão afeta suas receitas lucrativas|r"]
						local lock = node.locked and L[" |cffff5555(bloqueado)|r"] or ""
						local col = node.nRecipes > 0 and "|cffffffff" or "|cff9d9d9d"
						add(string.format("     %s%so %s|r %s%s%s%s", indent, col, node.name, rk, lock, who, per))
						local best = 0
						for _, t in ipairs(node.teeth) do if not t.earned and (t.gain or 0) > best then best = t.gain end end
						if node.nRecipes > 0 and best < 1 then
							-- afeta receitas, mas nenhuma delas ganha lucro com isso hoje
							local unlocks = 0
							for _, t in ipairs(node.teeth) do if not t.earned and not t.stats and t.desc then unlocks = unlocks + 1 end end
							add(string.format(L["       %s|cff9d9d9dsem ganho de lucro hoje nas suas receitas%s|r"], indent,
								unlocks > 0 and string.format(L[" (libera %d receita(s) nova(s), sem preço calculado)"], unlocks) or ""))
						elseif node.nRecipes > 0 then
							local shown = 0
							for _, t in ipairs(node.teeth) do
								if not t.earned and shown < 5 then
									shown = shown + 1
									local what
									if t.final then what = L["pontos restantes até o máximo"]
									else what = t.stats and StatsText(t.stats) or (t.desc and t.desc:sub(1, 70)) or "?" end
									local val = ""
									if not t.stats and t.desc then
										val = L[" |cff9d9d9d(receita nova: valor não calculado)|r"]
									elseif t.gain then
										val = string.format(L[" = %s/semana"], G(t.gain, true))
										if t.perPoint and t.gain > 0 then val = val .. string.format(L[" (%s por ponto)"], G(t.perPoint)) end
									end
									add(string.format(L["       %s- rank %d (+%d pontos): %s%s"], indent, t.threshold,
										t.points or (t.threshold - node.rank), what, val))
								end
							end
						end
					end
				end
			end
			if not anyShown then
				add(L["   |cff55ff55Especialização completa: não há mais pontos para gastar nesta profissão.|r"])
			end
			add(" ")
		end
		add(L["|cffffd100Perícia alcançável|r |cff9d9d9d(melhor equipamento + pontos de conhecimento que faltam)|r"])
		if inv.ladderNoSpec then add(L["   |cff9d9d9dSem dados do CraftSim: só o degrau do equipamento.|r"]) end
		if #(inv.ladder or {}) == 0 then add(L["   |cff55ff55Nada a ganhar: equipamento e especialização já no máximo.|r"]) end
		for _, l in ipairs(inv.ladder or {}) do
			local extra = ""
			if l.nNatural > 0 then extra = string.format(L[" · %d receita(s) saem "] .. ns.QIcon(2) .. L[" sem conc"], l.nNatural) end
			add(string.format(L["   %s: até +%d skill > %s por semana%s%s"], Invest.LadderLabel(l), l.skill, G(l.gain, true),
				l.top and (L[" · conc em "] .. l.top) or "", extra))
		end
		local ms = inv.milestones or {}
		if #ms > 0 then
			add(L["   Próximos marcos (skill que falta para a receita sair "] .. ns.QIcon(2) .. L[" sem gastar concentração):"])
			for k, m in ipairs(ms) do
				if k > 6 then break end
				add(string.format(L["      +%d skill: %s · +%s por craft · hoje custa %d conc · "] .. ns.QIcon(2) .. L[" vende %s/dia"],
					m.need, m.name, G(m.gain), m.conc or 0, m.spd and root.Num(m.spd, 0) or "?"))
			end
		end
		add(" ")
		add(L["|cffffd100Upgrades de equipamento|r |cff9d9d9d(só peças que aumentam o lucro, da que se paga mais rápido para a mais lenta)|r"])
		if #(inv.cands or {}) == 0 then
			add(L["   |cff9d9d9dNenhuma peça encontrada. Abra as profissões que fabricam ferramentas/acessórios.|r"])
		end
		local SLOT_NAME = { L["Ferramenta"], L["Acessório 1"], L["Acessório 2"] }
		for idx = 1, 3 do
			local g = (inv.gear or {})[idx]
			local ups, evaluated, bestNo = {}, 0, nil
			for _, c in ipairs(inv.cands or {}) do
				local r = c.bySlot and c.bySlot[idx]
				if r then evaluated = evaluated + 1 end
				if r and r.gain > 0 then table.insert(ups, { c = c, r = r })
				elseif r and (not bestNo or r.gain > bestNo.r.gain) then bestNo = { c = c, r = r } end
			end
			table.sort(ups, function(a, b)
				local pa, pb = a.r.payback or math.huge, b.r.payback or math.huge
				if pa ~= pb then return pa < pb end
				return a.r.gain > b.r.gain
			end)
			if g or #ups > 0 then
				local cur = g and (g.link or L["|cffff5555vazio|r"]) or "?"
				local slotName = SLOT_NAME[idx]
				if idx > 1 and g and g.catName then slotName = slotName .. " · " .. g.catName end
				add(string.format(L["|cffffffff%s|r (%s |cff9d9d9d%s|r): %s"], slotName, cur, g and StatStr(g.stats) or "",
					#ups > 0 and ("|cff55ff55" .. #ups .. L[" upgrade(s) possível(is)|r"]) or L["|cff9d9d9dnenhum upgrade|r"]))
				if idx == 1 then
					-- ferramenta: tabela com todas as peças (verde/azul/roxo) x os 3 stats possíveis
					local all = {}
					for _, c in ipairs(inv.cands or {}) do
						local r = c.bySlot and c.bySlot[1]
						if r then table.insert(all, { c = c, r = r }) end
					end
					table.sort(all, function(x, y)
						if (x.c.rarity or 0) ~= (y.c.rarity or 0) then return (x.c.rarity or 0) < (y.c.rarity or 0) end
						return (x.c.name or "") < (y.c.name or "")
					end)
					if #all == 0 then
						add(L["   |cff9d9d9dnenhuma ferramenta fabricável encontrada (ou sem stats lidos ainda)|r"])
					end
					for _, u in ipairs(all) do
						local c, r = u.c, u.r
						local col = RARITY[c.rarity or 0] or "|cffffffff"
						local gainTxt = r.gain > 0 and ("|cff55ff55+" .. G(r.gain) .. L["/semana|r"]) or L["|cff9d9d9dnão muda o lucro|r"]
						local pay = (r.gain > 0) and (r.payback and string.format(L[" · recupera em |cff55ff55%.1f semanas|r"], r.payback) or L[" · |cffff8800sem preço|r"]) or ""
						add(string.format(L["   %s%s|r %s · +%d skill · melhor: %s%s |cff9d9d9d(custo %s, %s)%s|r"],
							col, c.name or "?", ns.QIcon(5, 5), (r.stats and r.stats.skill) or 0, gainTxt, pay,
							G(c.price), c.priceFrom or "?", r.same and L[" · é a sua peça"] or ""))
						local opts = {}
						for _, ch in ipairs(r.allChoices or {}) do
							local v = ch.gain
							local txt = v > 0 and ("|cff55ff55+" .. G(v) .. "|r") or ("|cff9d9d9d" .. G(v, true) .. "|r")
							table.insert(opts, ch.label .. " " .. txt)
						end
						if #opts > 0 then
							add(L["      por semana, fabricando com: "] .. table.concat(opts, " · "))
						else
							add(L["      |cff9d9d9dopções de stat ainda não lidas (abra de novo após o tooltip carregar)|r"])
						end
					end
				elseif #ups == 0 then
					if evaluated == 0 then
						add(L["   |cff9d9d9dnenhuma peça fabricável deste tipo foi encontrada (ou sem stats lidos ainda)|r"])
					elseif bestNo then
						add(string.format(L["   |cff9d9d9d%d peça(s) avaliada(s); a melhor (%s: %s) não muda o lucro (%s/semana)|r"],
							evaluated, bestNo.c.name or "?", StatStr(bestNo.r.stats), G(bestNo.r.gain, true)))
					end
				end
				for _, u in ipairs(idx == 1 and {} or ups) do
					local c, r = u.c, u.r
					local col = RARITY[c.rarity or 0] or "|cffffffff"
					local pay = r.payback and string.format(L["recupera em |cff55ff55%.1f semanas|r"], r.payback) or L["|cffff8800sem preço|r"]
					add(string.format(L["   %s%s|r · |cff55ff55+%s/semana|r · %s |cff9d9d9d(custo %s, %s; %s)|r"],
						col, c.name or "?", G(r.gain), pay, G(c.price), c.priceFrom or "?",
						StatStr(r.stats) .. (r.crafted and (" na " .. ns.QIcon(5, 5)) or L[" (item base)"])))
					if r.statChoice then
						local alts = {}
						for _, a in ipairs(r.allChoices or {}) do
							if a.label ~= r.statChoice then table.insert(alts, a.label .. " " .. G(a.gain, true)) end
						end
						add(string.format(L["      |cff66ccfffabricar com %s|r%s"], r.statChoice,
							#alts > 0 and (L[" |cff9d9d9d(outras opções/semana: "] .. table.concat(alts, " · ") .. ")|r") or ""))
					end
					if r.enchant then
						add(string.format(L["      |cff66ccff+ encantar com %s "] .. ns.QIcon(2) .. L["|r (%s) — custo total %s"],
							r.enchant.name, G(r.enchantPrice), G(r.totalPrice)))
					end
					if r.sameUpgrade then
						add(string.format(L["      |cffffd100mesma peça que você usa, refeita em "] .. ns.QIcon(5, 5) .. L[" (a sua é %s)|r"], ns.QIcon(r.sameUpgrade, 5)))
					end
					if c.typeUnknown then
						add(L["      |cff9d9d9dtipo de acessório não identificado — confira em qual slot ele encaixa|r"])
					end
					if r.beatsHigherRarity then
						add(L["      |cffffd100raridade menor que o item atual, mas com stats melhores|r"])
					end
					for k, n in ipairs(r.newNatural or {}) do
						if k > 2 then break end
						add(string.format(L["      |cff66ccffpassa a sair "] .. ns.QIcon(2) .. L[" sem concentração:|r %s (+%s por craft)"], n.name, G(n.gain)))
					end
				end
			end
		end
		local tool = (inv.gear or {})[1]
		if tool and tool.link then
			local ei = inv.toolEnchant and ENCHANT_ITEM[inv.toolEnchant]
			local eName = ei and C_Item.GetItemNameByID(ei[1])
			local curE = inv.toolEnchant and ((eName and (eName .. " " .. ns.QIcon(ei[2])))
				or (ENCHANT_NAME[inv.toolEnchant] and ENCHANT_NAME[inv.toolEnchant]:gsub(" Q(%d)$", function(q) return " " .. ns.QIcon(tonumber(q)) end))
				or (L["encantamento "] .. inv.toolEnchant)) or L["|cffff5555sem encantamento|r"]
			local ups = inv.enchants or {}
			add(string.format(L["|cffffffffEncantamento da ferramenta|r (atual: %s): %s"], curE,
				#ups > 0 and ("|cff55ff55" .. #ups .. L[" upgrade(s) possível(is)|r"]) or L["|cff9d9d9dnenhum upgrade|r"]))
			for _, u in ipairs(ups) do
				local pay = u.payback and string.format(L["recupera em |cff55ff55%.1f semanas|r"], u.payback) or L["|cffff8800sem preço|r"]
				add(string.format("   %s " .. ns.QIcon(2) .. L[" (+%d %s) · |cff55ff55+%s/semana|r · %s |cff9d9d9d(pergaminho %s)|r"],
					C_Item.GetItemNameByID(u.opt.itemID) or u.opt.name, u.opt.value, ns.STAT[u.opt.stat] or u.opt.stat, G(u.gain), pay, G(u.price)))
			end
		end
		local unknown = 0
		for _, c in ipairs(inv.cands or {}) do if not c.statsKnown and not c.craftedKnown then unknown = unknown + 1 end end
		if unknown > 0 then
			add(string.format(L["   |cffff8800%d peça(s) sem stats carregados — reabra a profissão para reavaliar.|r"], unknown))
		end
		add(" ")
		add(string.format(L["|cff9d9d9dCusto de concentração por skill: %s. Valores contam só o que a concentração da semana fabrica. Peças avaliadas na melhor versão fabricável ("] .. ns.QIcon(5, 5) .. L[", mesmas missivas do seu item); encantamento avaliado à parte.|r"],
			(i.method == "CraftSim") and L["curva do CraftSim"] or L["aproximação linear"]))
	end
	return table.concat(out, "\n")
end
Invest.GetText = Render

-- usados pela versão visual (InvestView.lua)
Invest._CurrentEntry = CurrentEntry
Invest._StatStr = StatStr
Invest._StatsText = StatsText
Invest._ConcPerWeek = ConcPerWeek
Invest._ENCHANT_ITEM = ENCHANT_ITEM
Invest._TOOL_ENCHANTS = TOOL_ENCHANTS

-- Conteúdo exibido na aba 3 da janela principal
function Invest.Toggle()
	ns.UI.ShowTab(ns.UI.TAB.INVEST)
end

function Invest.Refresh()
	if ns.UI and ns.UI.RefreshTab then ns.UI.RefreshTab(ns.UI.TAB.INVEST) end
end
