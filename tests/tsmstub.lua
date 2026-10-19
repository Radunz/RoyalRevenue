-- TSM simulado para os testes.
--
-- Por que existe: três correções de preço saíram com ZERO diferença na suíte — o preço do Livro
-- passando a usar min(reino, região), o teto do anúncio fora do mercado e o atlas da marca de
-- qualidade. Não porque estivessem certas: o harness não tem TSM, então `root.TSMPrice` devolve
-- nil e o caminho inteiro nunca roda. "Só dá para ver no jogo" é lacuna, não característica.
--
-- Os preços saem do que o próprio addon já gravou: cada receita guarda `r.audit.prices[itemID]`
-- com DBMarket, DBMinBuyout, DBRegionMarketAvg e companhia, tirados de um TSM de verdade.
--
-- Uso:
--   local TSM = dofile("tsmstub.lua")
--   TSM.Install()                      -- usa os preços da fixture carregada
--   TSM.Install({ [123] = { DBMarket = 50000 } })   -- ou os seus
--   TSM.Remove()
local M = {}

local dados, originalAPI, instalado = {}, nil, false

-- divide "a, b, c" respeitando parênteses
local function Partes(s)
	local out, atual, nivel = {}, {}, 0
	for i = 1, #s do
		local ch = s:sub(i, i)
		if ch == "(" then nivel = nivel + 1 elseif ch == ")" then nivel = nivel - 1 end
		if ch == "," and nivel == 0 then
			table.insert(out, table.concat(atual)); atual = {}
		else
			table.insert(atual, ch)
		end
	end
	table.insert(out, table.concat(atual))
	return out
end

local function Limpa(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Avalia a expressão de preço do TSM. Cobre o que o addon usa: nome de fonte, first(), min(),
-- max() e "fonte * N".
--
-- min() com um operando ausente devolve NIL, e não o outro operando. É a suposição com que o
-- `Pricing.SaleByLink` foi escrito: sem dado da região o `saleSource` não resolve e o código cai
-- no fallback. Se o TSM de verdade fizer diferente, o addon continua funcionando — o fallback é
-- que não seria exercitado.
local function Avalia(expr, id)
	expr = Limpa(expr)
	local base, mult = expr:match("^(.-)%s*%*%s*([%d%.]+)$")
	if base and base ~= "" then
		local v = Avalia(base, id)
		return v and v * tonumber(mult) or nil
	end
	local fn, args = expr:match("^(%a+)%((.*)%)$")
	if fn then
		local partes = Partes(args)
		if fn == "first" then
			for _, p in ipairs(partes) do
				local v = Avalia(p, id)
				if v then return v end
			end
			return nil
		elseif fn == "min" or fn == "max" then
			local r
			for _, p in ipairs(partes) do
				local v = Avalia(p, id)
				if not v then return nil end
				if not r or (fn == "min" and v < r) or (fn == "max" and v > r) then r = v end
			end
			return r
		end
		return nil
	end
	local d = dados[id]
	return d and d[expr] or nil
end
M.Avalia = Avalia

local function IdDe(itemString)
	if type(itemString) ~= "string" then return tonumber(itemString) end
	return tonumber(itemString:match("i:(%d+)") or itemString:match("item:(%d+)") or itemString:match("^(%d+)$"))
end

-- varre a fixture carregada e junta tudo que o addon já anotou de preço
function M.DaFixture()
	local out, n = {}, 0
	for _, profs in pairs((LucroCraftDB or {}).chars or {}) do
		for _, e in pairs(profs) do
			if type(e) == "table" and e.rows then
				for _, r in ipairs(e.rows) do
					for id, b in pairs((r.audit and r.audit.prices) or {}) do
						if not out[id] then
							local p = {}
							for k, v in pairs(b) do
								local num = tonumber(v)
								if num and k ~= "usedCost" and k ~= "usedSale" then p[k] = num end
							end
							if next(p) then out[id] = p; n = n + 1 end
						end
					end
				end
			end
		end
	end
	return out, n
end

function M.Install(precos)
	local n
	if precos then
		dados, n = precos, 0
		for _ in pairs(precos) do n = n + 1 end
	else
		dados, n = M.DaFixture()
	end
	if not instalado then originalAPI = TSM_API; instalado = true end
	TSM_API = {
		GetCustomPriceValue = function(priceStr, itemString)
			local id = IdDe(itemString)
			if not id then return nil end
			return Avalia(priceStr, id)
		end,
	}
	-- o cache de preço do addon é por sessão: zera para o stub valer já
	if RR and RR._ResetPriceCache then RR._ResetPriceCache() end
	return n
end

function M.Remove()
	if instalado then TSM_API = originalAPI; instalado = false end
	dados = {}
	if RR and RR._ResetPriceCache then RR._ResetPriceCache() end
end

function M.Precos(id) return dados[id] end

-- Trocar o preço no meio do teste exige zerar o cache: o `root.TSMPrice` guarda o valor por 60 s e
-- o GetTime do harness quase não anda, então sem isso o segundo Set devolve o preço do primeiro.
-- (Na instalação não aparece: sem TSM_API o TSMPrice sai antes de guardar, e o cache fica limpo.)
function M.Set(id, p)
	dados[id] = p
	if RR and RR._ResetPriceCache then RR._ResetPriceCache() end
end

return M
