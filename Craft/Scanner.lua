local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

local Scanner = {}
ns.Scanner = Scanner

local P = ns.Pricing
local Cfg = ns.Cfg

local BASIC = (Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1

-- "Nome-Reino" do personagem logado (não muda na sessão: guardado assim que o jogo informa nome e reino)
local charKey
function ns.CharKey()
	if charKey then return charKey end
	local name, realm = UnitFullName("player")
	local r = realm or GetNormalizedRealmName() or GetRealmName()
	local k = (name or "?") .. "-" .. (r or "?")
	if name and r and r ~= "" then charKey = k end
	return k
end
function ns._ResetCharKey() charKey = nil end   -- testes fora do jogo (troca de personagem simulada)

-- Só escaneia a profissão do próprio personagem (não link, guilda ou NPC)
local function IsOwnProfession()
	if not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then return false end
	if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return false end
	if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return false end
	if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return false end
	return true
end

-- Expansão atual = linha de habilidade filha com o maior professionID
-- (as linhas novas da Blizzard sempre têm ID maior que as antigas)
local function GetCurrentExpansionProfession()
	local infos = C_TradeSkillUI.GetChildProfessionInfos and C_TradeSkillUI.GetChildProfessionInfos()
	local best
	if infos then
		for _, info in ipairs(infos) do
			if info.professionID and (not best or info.professionID > best.professionID) then
				best = info
			end
		end
	end
	return best or C_TradeSkillUI.GetChildProfessionInfo()
end

local function GetOutputItemID(recipeID, info, schematic)
	if info.qualityItemIDs and #info.qualityItemIDs > 0 then
		return info.qualityItemIDs[1]
	end
	if schematic and schematic.outputItemID then return schematic.outputItemID end
	if C_TradeSkillUI.GetRecipeOutputItemData then
		local ok, data = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, {}, nil)
		if ok and data and data.itemID then return data.itemID end
	end
	return nil
end

-- Simula o craft com os reagentes escolhidos (os mais baratos) e devolve a info de operação:
-- craftingQuality = qualidade que sai sem concentração, concentrationCost = custo p/ subir 1 tier.
-- IMPORTANTE (visto no CraftSim): só mandar slots de reagentes COM qualidade; se mandar um reagente
-- sem qualidade a API devolve nil. Formato: { reagent = { itemID }, quantity, dataSlotIndex }.
-- Cada qualidade do slot entra na lista; a escolhida com a qtd, as outras com 0.
local function GetOperationInfo(recipeID, parts, audit)
	if not C_TradeSkillUI.GetCraftingOperationInfo then
		audit.opError = L["API GetCraftingOperationInfo não existe"]
		return nil
	end
	local tbl = {}
	for _, p in ipairs(parts) do
		if p.slot and p.qualityItems and #p.qualityItems > 1 then
			for _, id in ipairs(p.qualityItems) do
				table.insert(tbl, {
					reagent = { itemID = id },
					quantity = (id == p.itemID) and p.qty or 0,
					dataSlotIndex = p.slot,
				})
			end
		end
	end
	audit.reagentsSent = {}
	for _, r in ipairs(tbl) do
		if r.quantity > 0 then
			table.insert(audit.reagentsSent, string.format(L["espaço %d: %dx %d"], r.dataSlotIndex, r.quantity, r.reagent.itemID))
		end
	end

	local ok, op = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, tbl, nil, false)
	if ok and op and op.craftingQuality then
		audit.opMode = L["reagentes escolhidos"]
		return op
	end
	audit.opError = ok and L["API devolveu nil com reagentes"] or (L["erro: "] .. tostring(op))
	-- fallback igual ao CraftSim: sem reagentes (skill base)
	ok, op = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, {}, nil, false)
	if ok and op and op.craftingQuality then
		audit.opMode = L["fallback sem reagentes"]
		return op
	end
	audit.opError = audit.opError .. L[" / fallback também falhou"]
	return nil
end

-- ===== Reagentes de qualidade superior (subir a qualidade sem concentração) =====
local function ReagentQuality(id)
	if C_TradeSkillUI.GetItemReagentQualityByItemInfo then
		local ok, q = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, id)
		if ok and type(q) == "number" then return q end
	end
	return nil
end
Scanner.ReagentQuality = ReagentQuality

-- item da maior qualidade do slot
local function TopItem(p)
	local list = p.qualityItems
	if not list or #list < 2 then return nil end
	local best, bq = list[#list], nil
	for _, id in ipairs(list) do
		local q = ReagentQuality(id)
		if q and (not bq or q > bq) then best, bq = id, q end
	end
	return best
end
Scanner.TopItem = TopItem

-- Tabela de reagentes para a API (GetCraftingOperationInfo / CraftRecipe), mesmo formato do CraftSim.
-- alloc[i] = quantas unidades do slot i vão na qualidade superior; tops[i] = itemID dela.
local function BuildReagentTbl(parts, alloc, tops)
	local tbl = {}
	for i, p in ipairs(parts or {}) do
		if p.slot and p.qualityItems and #p.qualityItems > 1 then
			local base = p.buyItem or p.itemID
			local n = alloc and alloc[i] or 0
			local top = n > 0 and ((tops and tops[i]) or TopItem(p)) or nil
			for _, id in ipairs(p.qualityItems) do
				local q = 0
				if id == base then q = q + (p.qty - n) end
				if top and id == top then q = q + n end
				table.insert(tbl, { reagent = { itemID = id }, quantity = q, dataSlotIndex = p.slot })
			end
		end
	end
	return tbl
end
Scanner.BuildReagentTbl = BuildReagentTbl

-- quantos o personagem tem para fabricar (bolsas, banco de reagentes e banco do bando)
local function Usable(id)
	if not (C_Item and C_Item.GetItemCount) then return math.huge end
	-- bolsas + banco do personagem logado + banco do bando
	local ok, n = pcall(C_Item.GetItemCount, id, true, false, true, true)
	return ok and n or 0
end
Scanner.Usable = Usable

-- Ajusta a tabela ao que existe de fato: se faltar a qualidade planejada de um espaço, completa com a
-- outra qualidade do mesmo espaço que estiver na bolsa (ex.: pediu 15 q1, tem 3 q1 + 20 q2 → 3 q1 + 12 q2).
-- Confere também os reagentes de uma qualidade só (o jogo preenche sozinho, mas falta = craft falha).
-- Devolve tbl ajustada, lista do que falta { {id, need, have} }, lista de trocas feitas (texto)
function Scanner.FitToBags(tbl, parts)
	local bySlot, order = {}, {}
	for _, e in ipairs(tbl or {}) do
		local s = e.dataSlotIndex
		if not bySlot[s] then bySlot[s] = {}; table.insert(order, s) end
		table.insert(bySlot[s], e)
	end
	local missing, swaps = {}, {}
	for _, s in ipairs(order) do
		local list = bySlot[s]
		local need = 0
		for _, e in ipairs(list) do need = need + (e.quantity or 0) end
		if need > 0 then
			local have, haveSum = {}, 0
			for _, e in ipairs(list) do have[e] = Usable(e.reagent.itemID); haveSum = haveSum + have[e] end
			if haveSum < need then
				table.insert(missing, { id = list[1].reagent.itemID, need = need, have = haveSum })
			else
				-- 1º: mantém o planejado onde dá; 2º: o que faltar vem das outras qualidades, da mais baixa para a mais alta
				local short = 0
				local before = {}
				for _, e in ipairs(list) do
					before[e] = e.quantity or 0
					if (e.quantity or 0) > have[e] then short = short + e.quantity - have[e]; e.quantity = have[e] end
				end
				for _, e in ipairs(list) do
					if short <= 0 then break end
					local spare = have[e] - e.quantity
					if spare > 0 then
						local take = math.min(spare, short)
						e.quantity = e.quantity + take
						short = short - take
					end
				end
				for _, e in ipairs(list) do
					if e.quantity ~= before[e] then
						table.insert(swaps, string.format("%dx %s", e.quantity, C_Item.GetItemNameByID(e.reagent.itemID) or e.reagent.itemID))
					end
				end
			end
		end
	end
	-- reagentes de uma qualidade só (não vão na tabela)
	for _, p in ipairs(parts or {}) do
		if not (p.qualityItems and #p.qualityItems > 1) and not p.bound and (p.qty or 0) > 0 then
			local id = p.buyItem or p.itemID
			local h = Usable(id)
			if h < p.qty then table.insert(missing, { id = id, need = p.qty, have = h }) end
		end
	end
	return tbl, missing, swaps
end

local function OpSkill(op) return (op.baseSkill or 0) + (op.bonusSkill or 0) end

local function TryOp(recipeID, tbl)
	local ok, op = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, tbl, nil, false)
	if ok and op and op.craftingQuality then return op end
	return nil
end

-- Menor custo extra para subir 1 qualidade só trocando reagentes pela qualidade superior.
-- A skill de cada slot é medida na API (slot inteiro na qualidade superior); as trocas entram da
-- mais barata por ponto de skill para a mais cara, e o resultado é conferido na API.
local function OptimizeReagents(recipeID, parts, op, baseQ)
	if not (op and baseQ and C_TradeSkillUI.GetCraftingOperationInfo) then return nil end
	local S0 = OpSkill(op)
	local need = (op.upperSkillTreshold or 0) - S0
	if need <= 0 then return nil end
	local slots = {}
	for i, p in ipairs(parts) do
		local top = TopItem(p)
		local base = p.buyItem or p.itemID
		if p.slot and top and top ~= base and (p.qty or 0) > 0 then
			local o = TryOp(recipeID, BuildReagentTbl(parts, { [i] = p.qty }, { [i] = top }))
			local topPrice = P.Cost(top)
			if o and topPrice then
				local gain = OpSkill(o) - S0
				if gain > 0 then
					table.insert(slots, { i = i, top = top, per = gain / p.qty, max = p.qty,
						extra = math.max(topPrice - (p.unit or 0), 0) })
				end
			end
		end
	end
	if #slots == 0 then return nil end
	table.sort(slots, function(a, b) return a.extra / a.per < b.extra / b.per end)
	local alloc, tops, got = {}, {}, 0
	for _, s in ipairs(slots) do
		tops[s.i] = s.top
		if got < need then
			local n = math.min(s.max, math.ceil((need - got) / s.per - 1e-6))
			if n > 0 then
				alloc[s.i] = n
				got = got + n * s.per
			end
		end
	end
	if got < need - 1e-6 then return nil end   -- nem tudo na qualidade superior alcança
	for _ = 1, 8 do
		local o = TryOp(recipeID, BuildReagentTbl(parts, alloc, tops))
		if o and o.craftingQuality > baseQ then
			local extra = 0
			for _, s in ipairs(slots) do extra = extra + (alloc[s.i] or 0) * s.extra end
			local usedTops = {}
			for i in pairs(alloc) do usedTops[i] = tops[i] end
			return { alloc = alloc, top = usedTops, extra = extra, quality = o.craftingQuality }
		end
		-- arredondamento do jogo: mais 1 unidade no slot de melhor custo por skill que ainda tem espaço
		local added = false
		for _, s in ipairs(slots) do
			if (alloc[s.i] or 0) < s.max then alloc[s.i] = (alloc[s.i] or 0) + 1; added = true; break end
		end
		if not added then return nil end
	end
	return nil
end

-- Custo dos reagentes obrigatórios (básicos). Para reagentes com qualidade usa a mais barata.
local function CalcCost(schematic)
	local total, missing, parts = 0, false, {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		if slot.required and slot.reagentType == BASIC and slot.reagents then
			local bestPrice, bestItem
			local qualityItems = {}
			for _, r in ipairs(slot.reagents) do
				if r.itemID then
					table.insert(qualityItems, r.itemID)
					local p = P.Cost(r.itemID)
					if p and (not bestPrice or p < bestPrice) then
						bestPrice, bestItem = p, r.itemID
					end
				end
			end
			local qty = slot.quantityRequired or 1
			local firstItem = qualityItems[1]
			-- sem preço em nenhuma fonte = item vinculado (obtido pelo personagem, não negociável): custo zero
			local bound = false
			if bestPrice then
				total = total + bestPrice * qty
			else
				bound = true
			end
			if bestItem or firstItem then
				table.insert(parts, {
					itemID = bestItem or firstItem,
					qty = qty,
					unit = bestPrice or 0,
					bound = bound or nil,
					slot = slot.dataSlotIndex,
					qualityItems = qualityItems,
				})
			end
		end
	end
	return total, missing, parts
end

-- Item que também se obtém fora do craft (ex.: motes de coleta via transmutação): pode ficar
-- fora do % de vendas e da curva ABC. Automático: receita "Prefixo: Nome do item" (transmutações).
-- Ctrl+clique na receita força marcar/desmarcar (LucroCraftDB.config.gathered[recipeID]).
function ns.IsGathered(r)
	local ov = LucroCraftDB.config.gathered
	if ov and ov[r.recipeID] ~= nil then return ov[r.recipeID] end
	local item = r.itemName or (r.itemID and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID))
	if item and r.name and r.name ~= item then
		local suffix = ": " .. item
		if #r.name > #suffix and r.name:sub(-#suffix) == suffix then return true end
	end
	return false
end
-- transmutação da Alquimia ("Transmute: X", "Transmutar: X", "Transmutação: X")
-- Cargas agora (estimado desde o último scan): devolve atual, máximo, segundos até a próxima, cargas por dia
function ns.Charges(r)
	local c = r and r.cd
	if not c then return nil end
	local max = c.max > 0 and c.max or 1
	local cur = c.max > 0 and c.charges or (c.cool > 0 and 0 or 1)
	local period = 86400   -- recarga de 1 carga (diária)
	local elapsed = time() - (c.t or time())
	local nextIn
	if cur < max then
		local first = c.cool > 0 and c.cool or period
		if elapsed >= first then
			cur = math.min(max, cur + 1 + math.floor((elapsed - first) / period))
			nextIn = cur < max and (period - ((elapsed - first) % period)) or nil
		else
			nextIn = first - elapsed
		end
	end
	return cur, max, nextIn, 86400 / period
end

-- Também pela categoria da receita na janela da profissão ("Transmutações"/"Transmutations") e pela
-- marcação manual (Ctrl+Shift+clique na lista: LucroCraftDB.config.transmute[recipeID] = true/false).
-- transmutações de Midnight que não têm "Transmute" no nome (viram baú: abre e sai o material)
local KNOWN_TRANSMUTE = { [1230891] = true, [1230892] = true, [1230893] = true }   -- Box of Rocks, Bouquet of Herbs, School of Gems
-- resultado pelo texto guardado por linha (nome/categoria não mudam); a marcação manual é conferida sempre
local tmCache = setmetatable({}, { __mode = "k" })
local TM_FIELDS = { "name", "category", "categoryParent" }
function ns.IsTransmute(r)
	if not r then return false end
	local ov = LucroCraftDB and LucroCraftDB.config.transmute
	if ov and r.recipeID and ov[r.recipeID] ~= nil then return ov[r.recipeID] end
	if r.recipeID and KNOWN_TRANSMUTE[r.recipeID] then return true end
	local c = tmCache[r]
	if c ~= nil and c.n == r.name and c.c == r.category then return c.v end
	local v = false
	for _, k in ipairs(TM_FIELDS) do
		local s = r[k]
		if type(s) == "string" and s:lower():find("transmut", 1, true) then v = true break end
	end
	tmCache[r] = { n = r.name, c = r.category, v = v }
	return v
end

function ns.ExcludedFromShare(r)
	return Cfg("excludeGathered") and ns.IsGathered(r) or false
end

-- item vinculado (ao pegar ou ao bando/conta) nunca vai para a casa de leilões, então não entra
-- na curva ABC nem no % de vendas, mesmo com giro (ex.: visão/estatística, item de missão).
local BIND_BOP = { [1] = true, [4] = true }
local BIND_WARBAND = { [7] = true, [8] = true, [9] = true }
function ns.IsAuctionable(itemID)
	if not itemID then return true end
	local bind = select(14, C_Item.GetItemInfo(itemID))
	if not bind then return true end -- item ainda não carregado: não exclui por engano
	return not (BIND_BOP[bind] or BIND_WARBAND[bind])
end

-- ===== Curva ABC: melhor uso da concentração =====
-- Entra só receita que DÁ LUCRO (com concentração ou sem ela), cujo item vai para a AH e que tem
-- giro (minSoldPerDay). Métrica = ouro por ponto de concentração (r.perConc): a ordem é a prioridade
-- de gasto dos pontos e o corte A/B/C é pelo % acumulado desse ouro/ponto, então A = onde a
-- concentração rende mais. Receita lucrativa que NÃO gasta concentração não disputa pontos: entra
-- como A (lucro livre, r.abcFree).
-- Por que não ponderar por vendas/dia: o spd é da REGIÃO (10 mil a 270 mil/dia), não o que você
-- consegue vender. Usá-lo como volume fazia o Bouquet of Herbs (0,3 ouro/ponto, 270 mil vendas/dia,
-- e ainda limitado a 2 cargas) virar 85% do "lucro da profissão" e jogava a curva toda em A.
-- Cada RESULTADO é classificado pelo seu próprio item (id), não pela receita:
--   base (r.itemID, sem concentração) -> r.abc / r.abcFree      · pelo lucro do próprio craft
--   conc (r.concItemID, com concentração) -> r.concAbc          · pela curva do ouro/ponto
--   mix  (r.mix.itemID, reagentes sup.)  -> r.mixAbc            · pelo lucro do próprio craft
-- Assim Light's Potential Q1 (que dá prejuízo fabricado) fica sem classe, mesmo que o Q2 da
-- mesma receita seja A — antes as duas linhas herdavam o abc da receita.
-- Cada ABA tem a SUA curva, porque o recurso escasso é diferente em cada uma:
--   Concentração     -> ouro por ponto de concentração (r.perConc)
--   Sem concentração -> margem (lucro ÷ custo), o ouro que volta por ouro parado em material
local function ApplyABC(rows)
	local conc, noconc, total, nTotal, spdTotal = {}, {}, 0, 0, 0
	local minSpd = tonumber(Cfg("minSoldPerDay")) or 1
	for _, r in ipairs(rows) do
		r.abc, r.abcShare, r.abcFree, r.spdShare = nil, nil, nil, nil
		r.concAbc, r.concAbcShare, r.mixAbc, r.mixAbcShare = nil, nil, nil, nil
		r.gathered = ns.ExcludedFromShare(r) or nil
		r.notAuctionable = (not ns.IsAuctionable(r.itemID)) or nil
		-- sem concItemID, a concentração sai no MESMO item: o vínculo é o do item base
		local concItem = r.concItemID or r.itemID
		if concItem == r.itemID then
			r.concNotAuctionable = r.notAuctionable
		else
			r.concNotAuctionable = (not ns.IsAuctionable(concItem)) or nil
		end
		if not r.gathered then
			if (r.spd or 0) > 0 and not r.notAuctionable then spdTotal = spdTotal + r.spd end
			-- resultado base (não gasta concentração): entra na curva da MARGEM
			if not r.notAuctionable and (r.profit or 0) > 0 and (r.spd or 0) >= minSpd then
				r.abcFree = true
				local m = (r.expCost and r.expCost > 0) and (r.profit / r.expCost) or nil
				if m and m > 0 then
					table.insert(noconc, { r = r, v = m, mix = false })
					nTotal = nTotal + m
				else
					r.abc = "A"   -- sem custo conhecido não dá para ranquear pela margem
				end
			end
			-- resultado com concentração: entra na curva do ouro/ponto
			if not r.concNotAuctionable and r.perConc and r.perConc > 0
				and (r.concSpd or r.spd or 0) >= minSpd then
				table.insert(conc, r)
				total = total + r.perConc
			end
			-- qualidade de cima com reagentes melhores: também não gasta concentração
			if r.mix and (r.mixProfit or 0) > 0 and (r.mixSpd or 0) >= minSpd
				and ns.IsAuctionable(r.mix.itemID) then
				local m = (r.mixExpCost and r.mixExpCost > 0) and (r.mixProfit / r.mixExpCost) or nil
				if m and m > 0 then
					table.insert(noconc, { r = r, v = m, mix = true })
					nTotal = nTotal + m
				else
					r.mixAbc = "A"
				end
			end
		end
	end
	-- % das vendas da profissão: continua sobre as VENDAS (é o que o recoMinShare filtra)
	if spdTotal > 0 then
		for _, r in ipairs(rows) do
			if not r.gathered and not r.notAuctionable and (r.spd or 0) > 0 then r.spdShare = r.spd / spdTotal end
		end
	end
	local a, b = Cfg("abcA"), Cfg("abcB")
	-- aba Concentração: ouro por ponto
	table.sort(conc, function(x, y) return x.perConc > y.perConc end)
	local cum = 0
	for _, r in ipairs(conc) do
		local share = total > 0 and cum / total or 0
		if share < a then r.concAbc = "A" elseif share < b then r.concAbc = "B" else r.concAbc = "C" end
		cum = cum + r.perConc
		r.concAbcShare = total > 0 and r.perConc / total or nil
	end
	-- aba Sem concentração: margem (lucro ÷ custo)
	table.sort(noconc, function(x, y) return x.v > y.v end)
	cum = 0
	for _, it in ipairs(noconc) do
		local share = nTotal > 0 and cum / nTotal or 0
		local cls = (share < a) and "A" or ((share < b) and "B" or "C")
		cum = cum + it.v
		local sh = nTotal > 0 and it.v / nTotal or nil
		if it.mix then it.r.mixAbc, it.r.mixAbcShare = cls, sh
		else it.r.abc, it.r.abcShare = cls, sh end
	end
end
Scanner.ApplyABC = ApplyABC

-- Receita pode ser recomendada (plano de concentração / investimento)?
-- Só itens com giro: classe ABC dentro do mínimo configurado (padrão A e B) e, se for usar
-- concentração, a qualidade superior também precisa vender pelo menos minSoldPerDay por dia.
local ABC_RANK = { A = 1, B = 2, C = 3 }
function ns.Recommendable(r, forConc)
	-- classe do resultado pedido: com concentração = curva do ouro/ponto; sem = curva da margem
	local abc = forConc and r.concAbc or r.abc
	-- item de coleta fica fora das duas curvas: só vale o mínimo de vendas/dia
	if r.gathered then
		local spd = forConc and r.concSpd or r.spd
		if (spd or 0) < (tonumber(Cfg("minSoldPerDay")) or 1) then return false, L[" vende pouco"] end
		return true
	end
	local min = ABC_RANK[(Cfg("recoMinABC") or "B"):upper()] or 2
	local rank = abc and ABC_RANK[abc] or 99
	if rank > min then return false, L["classe "] .. (abc or L["sem lucro"]) end
	-- participação mínima nas vendas da profissão (ex.: 1% = itens que realmente giram)
	local minShare = tonumber(Cfg("recoMinShare")) or 0.01
	if (r.spdShare or 0) < minShare then
		return false, string.format(L["só %.1f%% das vendas da profissão"], (r.spdShare or 0) * 100)
	end
	if forConc and r.concSpd and r.concSpd < (tonumber(Cfg("minSoldPerDay")) or 1) then
		return false, ns.QIcon(2) .. L[" vende pouco"]
	end
	return true
end

-- ===== Stats da profissão (multicraft / resourcefulness / ingenuity) =====
-- Mesmos fatores do CraftSim (TWW/Midnight): % = valor / fator
local STAT_FACTOR = { multicraft = 1100, resourcefulness = 900, ingenuity = 1000 }
local MC_CONST = { [1] = 2.1, [2] = 1.83, [5] = 1.875 }   -- extra máx. por proc ≈ const × rendimento base
local MC_CONST_DEFAULT = 2.5
local RES_SAVE = 0.30        -- resourcefulness economiza em média ~30% dos reagentes no proc
local ING_REFUND = 0.50      -- ingenuity devolve 50% da concentração no proc

local function StatKey(name)
	name = (name or ""):lower()
	local function is(g, en)
		local loc = _G[g]
		return (loc and name == loc:lower()) or name:find(en, 1, true)
	end
	if is("ITEM_MOD_MULTICRAFT_SHORT", "multicraft") then return "multicraft" end
	if is("ITEM_MOD_RESOURCEFULNESS_SHORT", "resourceful") then return "resourcefulness" end
	if is("ITEM_MOD_INGENUITY_SHORT", "ingenuity") then return "ingenuity" end
end

local function ReadStats(op)
	local st = { mc = 0, res = 0, ing = 0 }
	if not op or not op.bonusStats then return st end
	for _, s in pairs(op.bonusStats) do
		local k = StatKey(s.bonusStatName)
		if k then
			local pct
			if s.bonusStatValue and s.bonusStatValue > 0 then
				pct = s.bonusStatValue / STAT_FACTOR[k]
			elseif s.ratingPct then
				pct = s.ratingPct / 100
			end
			pct = math.min(math.max(pct or 0, 0), 1)
			if k == "multicraft" then st.mc = pct
			elseif k == "resourcefulness" then st.res = pct
			else st.ing = pct end
		end
	end
	return st
end

-- Itens esperados por craft considerando multicraft
-- itens extras médios quando o multicraft acontece: o que VOCÊ tirou nessa receita (3+ procs), senão
-- a média de todas as receitas com a mesma quantidade base (3+ procs), senão a fórmula de referência.
-- (Teste do Rafael, 03/10: tambores de Couraria, base 1, procs deram 4, 4 e 5 — bem acima da fórmula, ~2,5.)
local function ExtraPerProc(qty, recipeID, char, sig)
	char = char or ns.CharKey()
	-- só o próprio personagem, no perfil atual (pontos de conhecimento + equipamento da profissão)
	local Y = LucroCraftDB and LucroCraftDB.yieldBy and LucroCraftDB.yieldBy[char]
	if Y and (Y.sigs or Y.legacy) then
		Y.sigs = Y.sigs or {}
		local cur = sig and Y.sigs[sig]
		local o = cur and recipeID and cur[recipeID]
		if o and (o.mcN or 0) >= 3 then return o.mcItems / o.mcN, "receita" end
		if cur then
			local b = math.floor(qty + 0.5)
			local n, sum = 0, 0
			for _, x in pairs(cur) do
				if (x.n or 0) > 0 and (x.mcN or 0) > 0 and math.floor((x.base or 0) / x.n + 0.5) == b then
					n, sum = n + x.mcN, sum + x.mcItems
				end
			end
			if n >= 3 then return sum / n, "geral" end
		end
		-- perfil mudou (gastou pontos ou trocou equipamento): usa o perfil anterior mais recente desta receita
		local best
		for s2, t in pairs(Y.sigs) do
			local x = s2 ~= sig and recipeID and t[recipeID]
			if x and (x.mcN or 0) >= 3 and (not best or (x.t or 0) > (best.t or 0)) then best = x end
		end
		local lg = Y.legacy and recipeID and Y.legacy[recipeID]
		if lg and (lg.mcN or 0) >= 3 and (not best or (lg.t or 0) > (best.t or 0)) then best = lg end
		if best then return best.mcItems / best.mcN, "anterior" end
	end
	local c = MC_CONST[math.floor(qty + 0.5)] or MC_CONST_DEFAULT
	return (1 + c * qty) / 2, "fórmula"
end
Scanner.ExtraPerProc = ExtraPerProc

local function ExpectedItems(qty, st, recipeID, char, sig)
	if not Cfg("useStats") or not st or st.mc <= 0 then return qty end
	local extraIfProc = ExtraPerProc(qty, recipeID, char, sig)
	return qty + st.mc * extraIfProc
end

-- Custo esperado considerando resourcefulness
local function ExpectedCost(cost, st)
	if not Cfg("useStats") or not st or st.res <= 0 then return cost end
	return cost * (1 - st.res * RES_SAVE)
end

-- Concentração efetiva considerando ingenuity
-- refund = concentração devolvida no proc (vem do jogo em op.ingenuityRefund); sem ele usa 50%
local function EffectiveConc(conc, st, refund)
	if not conc then return nil end
	if not Cfg("useStats") or not st or st.ing <= 0 then return conc end
	refund = refund or conc * ING_REFUND
	return math.max(conc - st.ing * refund, 1)
end
Scanner.EffectiveConc = EffectiveConc

-- Calcula lucro, margem e concentração de uma linha (depois do custo final definido)
local function ComputeProfit(r)
	local ahCut = Cfg("ahCut")
	local st = r.stats
	r.expQty = ExpectedItems(r.qty, st, r.recipeID, Scanner._finalChar, Scanner._finalSig)
	r.expCost = ExpectedCost(r.cost, st)
	r.unitCost = r.expQty > 0 and r.expCost / r.expQty or nil
	r.profit, r.margin, r.profitBase = nil, nil, nil
	if r.sale then
		r.profitBase = r.sale * r.qty * (1 - ahCut) - r.cost
		r.profit = r.sale * r.expQty * (1 - ahCut) - r.expCost
		if r.expCost > 0 then r.margin = r.profit / r.expCost end
	end
	r.concProfit, r.perConc, r.concEff, r.concBeaten = nil, nil, nil, nil
	if r.concCost and r.concSale then
		r.concEff = EffectiveConc(r.concCost, st, r.ingRefund)
		r.concProfit = r.concSale * r.expQty * (1 - ahCut) - r.expCost
		r.perConc = r.concProfit / r.concEff
	end
	-- qualidade de cima com reagentes melhores (sem concentração)
	r.mixCost, r.mixExpCost, r.mixProfit = nil, nil, nil
	if r.mix and r.mixSale then
		r.mixCost = r.cost + (r.mix.extra or 0)
		r.mixExpCost = ExpectedCost(r.mixCost, st)
		r.mixProfit = r.mixSale * r.expQty * (1 - ahCut) - r.mixExpCost
		-- se os reagentes dão o mesmo resultado com mais lucro, não vale gastar concentração aqui
		if r.perConc and r.mixProfit >= (r.concProfit or -math.huge) then
			r.concBeaten = true
			r.perConc = nil
		end
	end
	if r.audit then
		r.audit.formula = string.format(
			L["custo compra=%d usado=%d esperado=%d | itens %.2f esperados %.2f | venda=%s | lucro base=%s esperado=%s | stats mc %.1f%% res %.1f%% ing %.1f%% | conc Q%s->Q%s %s (efetiva %s) venda %s lucro %s"],
			r.buyCost or 0, r.cost or 0, r.expCost or 0, r.qty, r.expQty, tostring(r.sale), tostring(r.profitBase), tostring(r.profit),
			(st and st.mc or 0) * 100, (st and st.res or 0) * 100, (st and st.ing or 0) * 100,
			tostring(r.quality), tostring(r.concQuality), tostring(r.concCost), tostring(r.concEff), tostring(r.concSale), tostring(r.concProfit))
	end
end
Scanner.ComputeProfit = ComputeProfit
Scanner.ExpectedItems = ExpectedItems
Scanner.ExpectedCost = ExpectedCost
Scanner.STAT_FACTOR = STAT_FACTOR
Scanner.StatKey = StatKey

-- ===== Reagente vinculado feito por você (recuperação) =====
-- Antes custava 0. Agora: custo de fazer (aba Destruir: entrada mais barata ÷ saída medida).
local function ApplyBoundCost(rows)
	local BC = ns.Salvage and ns.Salvage.BoundCost
	for _, r in ipairs(rows) do
		local extra = 0
		for _, p in ipairs(r.parts or {}) do
			p.boundCost, p.boundSrc = nil, nil
			if p.bound and BC then
				local u, info = BC(p.buyItem or p.itemID)
				if u then
					p.boundCost = u
					p.boundSrc = info and info.name
					extra = extra + u * (p.qty or 0)
				end
			end
		end
		r.boundExtra = extra > 0 and extra or nil
	end
end
Scanner.ApplyBoundCost = ApplyBoundCost

-- ===== Reagentes que você mesmo fabrica =====
-- Mapa itemID -> { unit = custo por unidade, name, char } de todas as profissões salvas (todos os personagens)
local function BuildCraftMap(extraRows, extraChar)
	local map = {}
	local function add(r, char)
		if not r.itemID or r.excluded or not r.unitCost or r.unitCost <= 0 then return end
		local cur = map[r.itemID]
		if not cur or r.unitCost < cur.unit then
			-- entradas e "é transmutação" só são calculadas se alguém consultar (CraftSource)
			map[r.itemID] = { unit = r.unitCost, name = r.name, char = char, row = r }
		end
	end
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			if e.rows ~= extraRows then
				for _, r in ipairs(e.rows) do add(r, char) end
			end
		end
	end
	for _, r in ipairs(extraRows or {}) do add(r, extraChar) end
	return map
end

-- detalhes da receita fonte (preguiçoso: a maioria dos itens do mapa nunca é consultada)
local function SourceInfo(c)
	if c.inputs == nil then
		local ins = {}
		for _, p in ipairs(c.row and c.row.parts or {}) do for _, id in ipairs(p.qualityItems or { p.itemID }) do ins[id] = true end end
		c.inputs = ins
		c.transmute = c.row and ns.IsTransmute(c.row) or false
	end
	return c
end

-- Troca o preço de compra pelo custo de fabricar quando fabricar é mais barato
local function ApplyCraftedReagents(rows, map)
	if not Cfg("useCrafted") then map = {} end
	for _, r in ipairs(rows) do
		local total, changed, usedCraft = 0, false, false
		local isT = ns.IsTransmute(r)
		for _, p in ipairs(r.parts or {}) do
			p.crafted = nil
			p.buyUnit, p.buyItem = p.buyUnit or p.unit, p.buyItem or p.itemID
			local bestUnit, bestItem, src = p.buyUnit, p.buyItem, nil
			if p.bound and p.boundCost then bestUnit = p.boundCost; changed = true end
			for _, id in ipairs(p.qualityItems or { p.itemID }) do
				local c = map[id]
				-- não usa o próprio item da receita como reagente dela mesma
				-- ciclo: a receita fonte consome o item desta; transmutação não usa outra transmutação como fonte
				if c and id ~= r.itemID and (not bestUnit or c.unit < bestUnit) then
					SourceInfo(c)
					if (r.itemID and c.inputs[r.itemID]) or (isT and c.transmute) then c = nil end
				else
					c = nil
				end
				if c then
					bestUnit, bestItem, src = c.unit, id, c
				end
			end
			if src then
				p.unit, p.itemID, changed = bestUnit, bestItem, true
				usedCraft = true
				p.crafted = string.format("%s (%s)", src.name or "?", src.char or "?")
			else
				p.unit, p.itemID = (p.bound and p.boundCost) or p.buyUnit, p.buyItem
			end
			if p.unit then total = total + p.unit * p.qty end
		end
		r.cost = changed and total or r.buyCost
		r.usesCrafted = usedCraft or nil
		if changed then
			local miss = false
			for _, p in ipairs(r.parts or {}) do if not p.unit then miss = true end end
			r.missing = miss
			r.excluded = miss or nil
		end
	end
end

Scanner.BuildCraftMap = BuildCraftMap
-- mapa de toda a conta para as telas (Mercado > Comprar): guardado até o próximo scan/reprecificação
local allMap
function Scanner.CraftMapAll()
	if not allMap then allMap = BuildCraftMap() end
	return allMap
end
function Scanner.InvalidateCraftMap() allMap = nil end
Scanner.ApplyCraftedReagents = ApplyCraftedReagents

-- Preços de venda, vendas/dia e tendência de uma linha (no scan e ao reprecificar sem a profissão aberta)
local function PriceRow(r)
	local s, spd
	if r.saleLink then s, spd = P.SaleByLink(r.saleLink) end
	r.sale = s or P.Sale(r.itemID)
	r.spd = spd or P.SoldPerDay(r.itemID)
	r.lowVolume = (r.spd or 0) < (tonumber(Cfg("minSoldPerDay")) or 1)
	r.trend = P.Trend(r.itemID)
	r.concSale, r.concSpd, r.concTrend = nil, nil, nil
	if r.concItemID then
		if r.gearQ then
			-- equipamento: só vale se o TSM tiver preço próprio do item level de cima
			local cs, cspd = P.SaleByLink(r.concLink)
			if cs and r.sale and cs > r.sale then r.concSale, r.concSpd = cs, cspd or r.spd end
			r.concTrend = r.trend
		else
			r.concSale = P.Sale(r.concItemID)
			r.concSpd = P.SoldPerDay(r.concItemID)
			r.concTrend = P.Trend(r.concItemID)
			-- baú (transmutação): sem preço/aberturas da qualidade de cima → projeção pelo conteúdo do baú comum
			r.concProjected = nil
			if not r.concSale and ns.Containers and ns.Containers.Get(r.itemID) then
				r.concSale = ns.Containers.ProjectHigher(r.itemID)
				r.concSpd = r.concSpd or r.spd
				r.concProjected = r.concSale and true or nil
			end
		end
	end
	r.mixSale, r.mixSpd, r.mixTrend = nil, nil, nil
	local m = r.mix
	if m and m.itemID then
		if r.gearQ then
			local ms, mspd = P.SaleByLink(m.link)
			if ms and r.sale and ms > r.sale then r.mixSale, r.mixSpd = ms, mspd or r.spd end
			r.mixTrend = r.trend
		else
			r.mixSale = P.Sale(m.itemID)
			r.mixSpd = P.SoldPerDay(m.itemID)
			r.mixTrend = P.Trend(m.itemID)
		end
	end
end
Scanner.PriceRow = PriceRow

-- Modo "estoque": reagente que você já tem (todos os personagens + bando) entra com custo 0
local function ApplyStock(rows)
	local on = Cfg("costMode") == "estoque" and ns.Stock
	for _, r in ipairs(rows) do
		r.usesStock = nil
		if on then
			local total, any = 0, false
			for _, p in ipairs(r.parts or {}) do
				local s = (not p.bound) and ns.Stock.Get(p.itemID)
				if s and s.total >= (p.qty or 1) then
					any = true
					p.fromStock = true
				else
					p.fromStock = nil
					total = total + (p.unit or 0) * (p.qty or 0)
				end
			end
			if any then r.cost = total; r.usesStock = true end
		else
			for _, p in ipairs(r.parts or {}) do p.fromStock = nil end
		end
	end
end

-- Custo final (fabricar x comprar, estoque), lucro e curva ABC
function Scanner.Finalize(rows, charKey)
	Scanner._finalChar = charKey
	-- 1ª passada: lucro só com preço de compra (gera o custo por unidade de cada item fabricado)
	ApplyBoundCost(rows)
	for _, r in ipairs(rows) do r.cost = r.buyCost + (r.boundExtra or 0); ComputeProfit(r) end
	-- 2ª passada: usa o custo de fabricar reagentes quando for mais barato que comprar
	local craftMap = BuildCraftMap(rows, charKey)
	ApplyCraftedReagents(rows, craftMap)
	ApplyStock(rows)
	for _, r in ipairs(rows) do ComputeProfit(r) end
	ApplyABC(rows)
	allMap = nil
	Scanner.gen = (Scanner.gen or 0) + 1   -- quem guarda cálculo por entrada (Invest) recalcula
end

-- Receitas desconhecidas: mesmo cálculo, usando só o que o personagem já sabe fabricar como reagente
-- (não entram na curva ABC, no plano, na fila nem no mapa de fabricados)
function Scanner.FinalizeUnknown(unknownRows, knownRows, charKey)
	if not unknownRows then return end
	Scanner._finalChar = charKey
	ApplyBoundCost(unknownRows)
	for _, r in ipairs(unknownRows) do r.cost = r.buyCost + (r.boundExtra or 0); ComputeProfit(r) end
	ApplyCraftedReagents(unknownRows, BuildCraftMap(knownRows, charKey))
	ApplyStock(unknownRows)
	for _, r in ipairs(unknownRows) do
		ComputeProfit(r)
		r.abc, r.abcShare, r.abcFree, r.spdShare = nil, nil, nil, nil
		r.concAbc, r.concAbcShare, r.mixAbc = nil, nil, nil
	end
end

-- Reprecifica o que está salvo (sem abrir a profissão): reagentes, venda, vendas/dia e tendência.
-- Skill, stats, qualidade e concentração continuam os do último scan.
function Scanner.Reprice(entry, charKey)
	if not entry or not entry.rows then return end
	if not P.HasAnySource() then return end
	local all = {}
	for _, r in ipairs(entry.rows) do table.insert(all, r) end
	for _, r in ipairs(entry.unknown or {}) do table.insert(all, r) end
	for _, r in ipairs(all) do
		local total = 0
		for _, p in ipairs(r.parts or {}) do
			local id = p.buyItem or p.itemID
			local u = P.Cost(id)
			if u then p.buyUnit, p.bound = u, nil end
			p.buyItem = id
			p.unit, p.itemID = p.buyUnit or p.unit or 0, id
			total = total + (p.unit or 0) * (p.qty or 0)
		end
		r.buyCost = total
		if r.mix and r.mix.alloc then
			local extra = 0
			for i, n in pairs(r.mix.alloc) do
				local p = r.parts and r.parts[i]
				local top = r.mix.top and r.mix.top[i]
				local tp = top and P.Cost(top)
				if p and tp then extra = extra + n * math.max(tp - (p.buyUnit or p.unit or 0), 0) end
			end
			r.mix.extra = extra
		end
		PriceRow(r)
	end
	Scanner._finalSig = entry.sig
	Scanner.Finalize(entry.rows, charKey)
	Scanner.FinalizeUnknown(entry.unknown, entry.rows, charKey)
	entry.pricedAt = time()
end

-- Reprecifica todos os personagens, uma profissão por vez (não trava o jogo)
local repricing = false
function Scanner.RepriceAll(onDone)
	if repricing then return end
	local jobs = {}
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do table.insert(jobs, { char = char, e = e }) end
	end
	repricing = true
	local i = 0
	local function step()
		i = i + 1
		local job = jobs[i]
		if not job then
			repricing = false
			if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
			if onDone then onDone() end
			return
		end
		local ok, err = pcall(Scanner.Reprice, job.e, job.char)
		if not ok then ns.Log(L["reprecificar: "] .. tostring(err)) end
		C_Timer.After(0.1, step)
	end
	step()
end

-- Como aprender uma receita desconhecida: texto do próprio jogo (instrutor, vendedor, drop...)
local function RecipeSource(recipeID)
	if not C_TradeSkillUI.GetRecipeSourceText then return nil end
	local ok, txt = pcall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
	if ok and type(txt) == "string" and txt ~= "" then return txt end
	return nil
end
Scanner.RecipeSource = RecipeSource

-- unknown = true: receitas da expansão que o personagem ainda NÃO aprendeu
local function CollectRows(targetID, unknown)
	local rows, skipped, matched = {}, 0, 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and ((info.learned and true or false) ~= (unknown and true or false)) and not info.isDummyRecipe and not info.isRecraft
			and C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID) == targetID then
			matched = matched + 1
			if info.isSalvageRecipe then
				if not unknown and ns.Salvage then pcall(ns.Salvage.Capture, recipeID, info, targetID) end
				skipped = skipped + 1   -- prospecção/moagem: saída aleatória, fica pra v2
			else
				if not unknown and ns.Salvage and ns.Salvage.IsCraftDestroy(info) then
					pcall(ns.Salvage.Capture, recipeID, info, targetID)   -- Estilhaçar: também entra na aba Destruir
				end
				local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
				local itemID = schematic and GetOutputItemID(recipeID, info, schematic)
				if not itemID then
					skipped = skipped + 1
				else
					local qMin, qMax = schematic.quantityMin or 1, schematic.quantityMax or 1
					local qty = (qMin + qMax) / 2
					if qty <= 0 then qty = 1 end
					-- quantidade base aprendida com as suas fabricações (o jogo às vezes informa errado)
					local ob = Scanner.ObservedBase(recipeID)
					if ob then qty = ob end
					local cost, missing, parts = CalcCost(schematic)

					-- Qualidade: "auto" usa a que sua skill atinge com os reagentes mais baratos
					local qIDs = info.qualityItemIDs
					local hasQIDs = qIDs and #qIDs > 0
					-- equipamento: o mesmo itemID em todas as qualidades (a qualidade muda o item level)
					local maxQ = hasQIDs and #qIDs
						or ((info.supportsQualities and (info.maxQuality or 0) > 1) and info.maxQuality) or 0
					local gearQ = (not hasQIDs) and maxQ > 1
					local audit = { time = time() }
					-- op info para todas as receitas: além da qualidade traz multicraft/resourcefulness/ingenuity
					local op = GetOperationInfo(recipeID, parts, audit)
					local stats = ReadStats(op)
					if op then
						audit.op = {
							craftingQuality = op.craftingQuality,
							baseSkill = op.baseSkill,
							bonusSkill = op.bonusSkill,
							lowerSkillThreshold = op.lowerSkillThreshold,
							upperSkillTreshold = op.upperSkillTreshold,
							recipeDifficulty = op.baseDifficulty,
							bonusDifficulty = op.bonusDifficulty,
							concentrationCost = op.concentrationCost,
							ingenuityRefund = op.ingenuityRefund,
						}
						audit.stats = stats
					elseif maxQ > 1 then
						ns.Log(string.format(L["%s: sem info de operação (%s)"], info.name or recipeID, audit.opError or "?"))
					end
					local baseQ
					if maxQ > 0 then
						local forced = tonumber(Cfg("outputQuality"))
						baseQ = forced or (op and op.craftingQuality) or 1
						baseQ = math.min(math.max(math.floor(baseQ), 1), maxQ)
						if hasQIDs then itemID = qIDs[baseQ] end
					end
					local function QItem(q) return (hasQIDs and qIDs[q]) or itemID end

					-- link real do item fabricado numa qualidade (equipamento: item level certo para o preço)
					local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
					local isGear = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
						and equipLoc ~= "INVTYPE_NON_EQUIP"
					local function OutLinkAt(q)
						if not (isGear and C_TradeSkillUI.GetRecipeOutputItemData) then return nil end
						local okO, od = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, {}, nil, q)
						if okO and od and od.hyperlink and od.hyperlink ~= "" then return od.hyperlink end
						return nil
					end

					-- perícia com todos os reagentes na qualidade superior (marcos da aba Investimento)
					local skillTop
					if op and baseQ and baseQ < maxQ then
						local all, any = {}, false
						for pi, p in ipairs(parts) do
							if p.slot and p.qualityItems and #p.qualityItems > 1 then all[pi] = p.qty; any = true end
						end
						if any then
							local o = TryOp(recipeID, BuildReagentTbl(parts, all))
							if o then skillTop = OpSkill(o) end
						end
					end

					local concCost, concQ, concItemID, concLink
					if op and baseQ and baseQ < maxQ and op.concentrationCost and op.concentrationCost > 0 then
						concCost = op.concentrationCost
						concQ = baseQ + 1
						concItemID = QItem(concQ)
						concLink = OutLinkAt(concQ)
					end

					-- mesma qualidade de cima trocando reagentes pela qualidade superior (sem concentração)
					local mix
					if Cfg("optimizeReagents") and not unknown and op and baseQ and baseQ < maxQ then
						local okM, m = pcall(OptimizeReagents, recipeID, parts, op, baseQ)
						if okM and m then
							m.quality = math.min(m.quality, maxQ)
							m.itemID = QItem(m.quality)
							m.link = OutLinkAt(m.quality)
							mix = m
						elseif not okM then
							ns.Log(string.format(L["%s: otimização de reagentes falhou (%s)"], info.name or recipeID, tostring(m)))
						end
					end

					-- auditoria de preços: todas as fontes de cada item envolvido
					audit.prices = {}
					for _, part in ipairs(parts) do
						for _, id in ipairs(part.qualityItems or { part.itemID }) do
							audit.prices[id] = P.Breakdown(id)
						end
					end
					for _, id in ipairs(hasQIDs and qIDs or { itemID }) do
						audit.prices[id] = P.Breakdown(id)
					end

					-- equipamento de profissão: link na qualidade máxima para o Investimento ler os stats
					local outLink
					if equipLoc == "INVTYPE_PROFESSION_TOOL" or equipLoc == "INVTYPE_PROFESSION_GEAR" then
						outLink = OutLinkAt((maxQ and maxQ > 0) and maxQ or 5)
					end

					-- categoria da receita na janela da profissão (ex.: "Transmutações") e a de cima
					local catName, catParent
					if info.categoryID and C_TradeSkillUI.GetCategoryInfo then
						local okC, ci = pcall(C_TradeSkillUI.GetCategoryInfo, info.categoryID)
						if okC and ci then
							catName = ci.name
							if ci.parentCategoryID then
								local okP, pi = pcall(C_TradeSkillUI.GetCategoryInfo, ci.parentCategoryID)
								if okP and pi then catParent = pi.name end
							end
						end
					end
					-- recarga / cargas (transmutações: N por dia conforme os pontos de especialização)
					local cdInfo
					if C_TradeSkillUI.GetRecipeCooldown then
						local okR, cool, isDay, charges, maxCharges = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
						if okR and ((maxCharges or 0) > 0 or (cool or 0) > 0) then
							cdInfo = { cool = cool or 0, day = isDay or nil, charges = charges or 0, max = maxCharges or 0, t = time() }
						end
					end
					local row = {
						cd = cdInfo,
						category = catName,
						categoryParent = catParent,
						outLink = outLink,
						recipeID = recipeID,
						name = info.name,
						itemName = itemID and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil,
						icon = info.icon,
						itemID = itemID,
						quality = baseQ,
						maxQuality = maxQ > 0 and maxQ or nil,
						gearQ = gearQ or nil,
						saleLink = OutLinkAt(baseQ),
						qty = qty,
						schemQty = (qMin + qMax) / 2,
						buyCost = cost,
						cost = cost,
						missing = missing,
						parts = parts,
						stats = stats,
						concCost = concCost,
						concQuality = concQ,
						concItemID = concItemID,
						concLink = concLink,
						mix = mix,
						skill = op and ((op.baseSkill or 0) + (op.bonusSkill or 0)) or nil,
						skillTop = skillTop,
						difficulty = op and (op.upperSkillTreshold or ((op.baseDifficulty or 0) + (op.bonusDifficulty or 0))) or nil,
						ingRefund = op and op.ingenuityRefund or nil,
						audit = audit,
						-- reagente sem preço = custo subestimado: fica fora do ranking de lucro
						excluded = missing or nil,
						unknown = unknown or nil,
						source = unknown and RecipeSource(recipeID) or nil,
					}
					-- desconhecida: guarda menos auditoria (economiza o arquivo salvo)
					if unknown then audit.prices = nil end
					PriceRow(row)
					if missing and not unknown then ns.Log(string.format(L["%s: reagente sem preço"], info.name or recipeID)) end
					if not row.sale and not unknown then ns.Log(string.format(L["%s: item final %d sem preço de venda"], info.name or recipeID, itemID or 0)) end
					table.insert(rows, row)

				end
			end
		end
	end
	return rows, skipped, matched
end

-- ícone da profissão (para as abas visuais)
local function ProfessionIcon(prof)
	if GetProfessions and prof then
		for _, idx in pairs({ GetProfessions() }) do
			local _, tex, _, _, _, _, skillLine = GetProfessionInfo(idx)
			if skillLine and (skillLine == prof.parentProfessionID or skillLine == prof.professionID) then return tex end
		end
	end
	if C_TradeSkillUI.GetTradeSkillTexture and prof then
		local ok, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, prof.parentProfessionID or prof.professionID)
		if ok and tex then return tex end
	end
	return nil
end

function Scanner.Scan(silent)
	if not IsOwnProfession() then
		if not silent then ns.Print(L["Abra a janela da sua profissão para escanear."]) end
		return nil
	end
	local prof = GetCurrentExpansionProfession()
	if not prof or not prof.professionID then return nil end

	local targetID = prof.professionID
	local rows, skipped, matched = CollectRows(targetID)
	-- fallback: se a heurística de "expansão atual" não achou nada, usa a aba aberta
	if matched == 0 then
		local shown = C_TradeSkillUI.GetChildProfessionInfo()
		if shown and shown.professionID and shown.professionID ~= targetID then
			prof, targetID = shown, shown.professionID
			rows, skipped, matched = CollectRows(targetID)
		end
	end

	local okSig, sig = pcall(Scanner.ProfileSig, prof)
	Scanner._finalSig = okSig and sig or nil
	if Scanner._finalSig then Scanner.NoteSig(Scanner._finalSig, targetID) end
	Scanner.Finalize(rows, ns.CharKey())
	-- receitas ainda não aprendidas (grupo "Receitas desconhecidas" na aba Receitas)
	local unknownRows = {}
	local okU, uRows = pcall(CollectRows, targetID, true)
	if okU and uRows then
		unknownRows = uRows
		Scanner.FinalizeUnknown(unknownRows, rows, ns.CharKey())
	elseif not okU then
		ns.Log(L["receitas desconhecidas: "] .. tostring(uRows))
	end

	local conc
	if C_TradeSkillUI.GetConcentrationCurrencyID then
		local ok, cid = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, targetID)
		if ok and cid and cid > 0 then
			local ci = C_CurrencyInfo.GetCurrencyInfo(cid)
			if ci then conc = { cur = ci.quantity, max = ci.maxQuantity } end
		end
	end

	LucroCraftDB.chars = LucroCraftDB.chars or {}
	local key = ns.CharKey()
	LucroCraftDB.chars[key] = LucroCraftDB.chars[key] or {}
	local entry = {
		sig = Scanner._finalSig,
		professionID = targetID,
		name = prof.parentProfessionName or prof.professionName,
		skillLine = prof.professionName,
		expansion = prof.expansionName,
		time = time(),
		source = P.SourceName(),
		skipped = skipped,
		conc = conc,
		pricedAt = time(),
		knowledge = nil,
		class = select(2, UnitClass("player")),
		icon = ProfessionIcon(prof),
		saleSource = Cfg("saleSource"),
		costSource = Cfg("costSource"),
		ahCut = Cfg("ahCut"),
		rows = rows,
		unknown = unknownRows,
		parentID = prof.parentProfessionID,
		-- coleta (Herbalismo 182, Mineração 186, Esfolamento 393): aba Investimento mostra os buffs de coleta
		gathering = (prof.isGatheringProfession or ({ [182] = true, [186] = true, [393] = true })[prof.parentProfessionID or 0]) and true or nil,
	}
	-- pontos de conhecimento ainda não gastos na árvore de especialização
	if C_ProfSpecs and C_ProfSpecs.GetCurrencyInfoForSkillLine then
		local okK, ki = pcall(C_ProfSpecs.GetCurrencyInfoForSkillLine, targetID)
		if okK and type(ki) == "table" then entry.knowledge = ki.numAvailable end
	end
	-- aprende a regeneração de concentração comparando com o scan anterior
	local prev = LucroCraftDB.chars[key][targetID]
	if prev and prev.conc and conc and prev.time and conc.cur > prev.conc.cur and conc.cur < (conc.max or 1000) then
		local hours = (entry.time - prev.time) / 3600
		if hours >= 1 then
			local rate = (conc.cur - prev.conc.cur) / hours
			if rate > 1 and rate < 60 then
				LucroCraftDB.concRate = LucroCraftDB.concRate and (LucroCraftDB.concRate * 0.7 + rate * 0.3) or rate
			end
		end
	end
	LucroCraftDB.chars[key][targetID] = entry
	if ns.Invest then
		local ok, err = pcall(ns.Invest.Evaluate, entry, prof)
		if not ok then ns.Log(L["investimento: "] .. tostring(err)) end
	end
	LucroCraftDB.last = { char = key, professionID = targetID }

	if not silent then
		ns.Print(string.format(L["%s: %d receitas analisadas (%d ignoradas). Preços: %s."],
			entry.skillLine or entry.name or "?", #rows, skipped, entry.source))
	end
	return entry
end

-- ===== Rendimento real das fabricações =====
-- A cada fabricação o jogo manda TRADE_SKILL_ITEM_CRAFTED_RESULT com a quantidade e quanto veio do
-- multicraft. Guarda por receita: fabricações, itens, base (quantidade − multicraft), procs de multicraft.
-- Com 3+ fabricações a quantidade base observada substitui a do jogo no cálculo do lucro.
-- LucroCraftDB.yield[recipeID] = { n, items, base, mcN, mcItems, t }
local yieldRecipe, yieldAt, yieldSig = nil, 0, nil

-- Perfil da profissão aberta: pontos de conhecimento gastos (soma dos ranks da árvore) + ferramenta e
-- acessórios equipados (item, encantamento, bônus). Mudou o perfil = novos dados de multicraft.
local function ItemKey(link)
	local s = link and link:match("item:([%-%d:]+)")
	if not s then return "-" end
	local f = {}
	for v in (s .. ":"):gmatch("([^:]*):") do table.insert(f, v) end
	local key = (f[1] or "") .. ":" .. (f[2] or "")
	local nb = tonumber(f[13] or "") or 0
	for i = 14, 13 + nb do key = key .. ":" .. (f[i] or "") end
	return key
end
function Scanner.ProfileSig(prof)
	if not prof then
		if not C_TradeSkillUI.GetChildProfessionInfo then return nil end
		local ok, p = pcall(C_TradeSkillUI.GetChildProfessionInfo)
		prof = ok and p or nil
	end
	if not prof or not prof.professionID then return nil end
	local spent = 0
	local configID = C_ProfSpecs and C_ProfSpecs.GetConfigIDForSkillLine and C_ProfSpecs.GetConfigIDForSkillLine(prof.professionID)
	if configID and C_Traits and C_Traits.GetNodeInfo and C_ProfSpecs.GetSpecTabIDsForSkillLine then
		for _, tabID in ipairs(C_ProfSpecs.GetSpecTabIDsForSkillLine(prof.professionID) or {}) do
			local queue = { C_ProfSpecs.GetRootPathForTab(tabID) }
			local guard = 0
			while #queue > 0 and guard < 500 do
				guard = guard + 1
				local p = table.remove(queue, 1)
				if p then
					local okN, ni = pcall(C_Traits.GetNodeInfo, configID, p)
					if okN and ni and ni.activeRank then spent = spent + ni.activeRank end
					for _, ch in ipairs(C_ProfSpecs.GetChildrenForPath(p) or {}) do table.insert(queue, ch) end
				end
			end
		end
	end
	local gear = {}
	local okS, slots = false, nil
	if prof.profession and C_TradeSkillUI.GetProfessionSlots then okS, slots = pcall(C_TradeSkillUI.GetProfessionSlots, prof.profession) end
	for _, slot in ipairs(okS and slots or {}) do table.insert(gear, ItemKey(GetInventoryItemLink("player", slot))) end
	return prof.professionID .. "|k" .. spent .. "|" .. table.concat(gear, ","), prof.professionID
end

-- LucroCraftDB.yieldBy[char] = { sigs = { [perfil] = { [recipeID] = { n, items, base, mcN, mcItems, t } } },
--                               cur = { [skillLine] = perfil atual } }
local function CharY(char)
	LucroCraftDB.yieldBy = LucroCraftDB.yieldBy or {}
	local Y = LucroCraftDB.yieldBy[char] or {}
	LucroCraftDB.yieldBy[char] = Y
	Y.sigs = Y.sigs or {}
	Y.cur = Y.cur or {}
	return Y
end
-- registra o perfil atual; dados antigos sem perfil (v1.0.13) entram no primeiro perfil visto dessa profissão
function Scanner.NoteSig(sig, skillLine, char)
	if not sig or not LucroCraftDB then return end
	local Y = CharY(char or ns.CharKey())
	Y.cur[skillLine] = sig
	if Y.legacy then
		Y.sigs[sig] = Y.sigs[sig] or {}
		for rid, o in pairs(Y.legacy) do
			local okL, sl = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, rid)
			if okL and sl == skillLine then
				if not Y.sigs[sig][rid] then Y.sigs[sig][rid] = o end
				Y.legacy[rid] = nil
			end
		end
		if not next(Y.legacy) then Y.legacy = nil end
	end
end
function Scanner.Observed(recipeID, char, sig)
	local Y = LucroCraftDB and LucroCraftDB.yieldBy and LucroCraftDB.yieldBy[char or ns.CharKey()]
	if not Y then return nil end
	if sig and Y.sigs and Y.sigs[sig] and Y.sigs[sig][recipeID] then return Y.sigs[sig][recipeID], false end
	if Y.legacy and Y.legacy[recipeID] then return Y.legacy[recipeID], true end
	return nil
end
-- quantidade base é da receita (não muda com a especialização): junta todos os personagens e perfis
function Scanner.ObservedBase(recipeID)
	local n, base = 0, 0
	for _, Y in pairs(LucroCraftDB and LucroCraftDB.yieldBy or {}) do
		for _, t in pairs(Y.sigs or {}) do
			local o = t[recipeID]
			if o then n, base = n + (o.n or 0), base + (o.base or 0) end
		end
		local o = Y.legacy and Y.legacy[recipeID]
		if o then n, base = n + (o.n or 0), base + (o.base or 0) end
	end
	if n < 3 or base <= 0 then return nil end
	local b = math.floor(base / n + 0.5)
	return b >= 1 and b or nil
end

-- migração: v1.0.13 guardava sem personagem; a semente dos tambores é do Uriuri (o teste foi nele)
local function SeedDrums()
	if not LucroCraftDB then return end
	LucroCraftDB.yieldBy = LucroCraftDB.yieldBy or {}
	local drumsChar, drumsID
	for ch, es in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(es) do
			for _, r in ipairs(e.rows or {}) do
				if r.name == "Void-Touched Drums" and (not drumsChar or ch == "Uriuri-Goldrinn") then drumsChar, drumsID = ch, r.recipeID end
			end
		end
	end
	local old = LucroCraftDB.yield
	if old then
		for rid, o in pairs(old) do
			local ch = (o.t == 1791063000 and drumsChar) or ns.CharKey()
			local Y = CharY(ch)
			Y.legacy = Y.legacy or {}
			if not Y.legacy[rid] then Y.legacy[rid] = o end
		end
		LucroCraftDB.yield = nil
		LucroCraftDB.yieldSeed1 = true
	end
	if LucroCraftDB.yieldSeed1 then return end
	LucroCraftDB.yieldSeed1 = true
	if drumsChar then
		local Y = CharY(drumsChar)
		Y.legacy = Y.legacy or {}
		Y.legacy[drumsID] = Y.legacy[drumsID] or { n = 10, items = 21, base = 10, mcN = 3, mcItems = 11, t = 1791063000 }
	end
end

local yf = CreateFrame("Frame")
yf:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
yf:RegisterEvent("PLAYER_LOGIN")
yf:RegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
yf:SetScript("OnEvent", function(_, event, a1)
	if not LucroCraftDB then return end
	if event == "PLAYER_LOGIN" then pcall(SeedDrums) return end
	if event == "TRADE_SKILL_CRAFT_BEGIN" then
		yieldRecipe, yieldAt = a1, GetTime()
		local okS, sig, sl = pcall(Scanner.ProfileSig)
		yieldSig = okS and sig or nil
		if yieldSig then Scanner.NoteSig(yieldSig, sl) end
		return
	end
	if not yieldRecipe or GetTime() - yieldAt > 15 then return end
	local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, yieldRecipe)
	if not ok or not info or info.isSalvageRecipe or info.isRecraft then return end
	local data = a1
	local okD, id, qty, mc, enchant = pcall(function() return data.itemID, data.quantity, data.multicraft, data.isEnchant end)
	if not okD or enchant or type(qty) ~= "number" or qty <= 0 or not id or id == 0 then return end
	mc = (type(mc) == "number" and mc > 0) and mc or 0
	local Y = CharY(ns.CharKey())
	local sig = yieldSig or "?"
	Y.sigs[sig] = Y.sigs[sig] or {}
	local o = Y.sigs[sig][yieldRecipe] or { n = 0, items = 0, base = 0, mcN = 0, mcItems = 0 }
	Y.sigs[sig][yieldRecipe] = o
	o.n = o.n + 1
	o.items = o.items + qty
	o.base = o.base + (qty - mc)
	if mc > 0 then o.mcN = o.mcN + 1; o.mcItems = o.mcItems + mc end
	o.t = time()
	yieldAt = GetTime()
end)
