-- valores secretos: tabela-marcador; comparar com string dá erro como no jogo
local SECRET = setmetatable({}, { __eq = function() error("attempt to compare secret") end, __tostring = function() return "<secret>" end })
issecretvalue = function(v) return v == nil and false or rawequal(v, SECRET) end
dofile("harness12.lua")
local fired = 0
for _, fr in ipairs(ALL_FRAMES or {}) do end
-- dispara para todos os frames registrados
local n, errs = 0, 0
for _, fr in pairs(ALLF) do
  local h = fr._scripts and fr._scripts.OnEvent
  if h then
    for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_AURA", "CHAT_MSG_LOOT", "PLAYER_SPECIALIZATION_CHANGED" }) do
      n = n + 1
      local ok, e = pcall(h, fr, ev, "player", SECRET, "Cast-x", 1822)
      if not ok then errs = errs + 1; print("ERR", ev, e) end
      ok, e = pcall(h, fr, ev, SECRET, SECRET, SECRET, SECRET)
      if not ok then errs = errs + 1; print("ERR2", ev, e) end
    end
  end
end
print("chamadas", n, "erros", errs)
