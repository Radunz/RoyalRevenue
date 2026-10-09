dofile("t2.lua")
local C = RR.Craft
for _, k in ipairs({"LIST","PLAN","INVEST","SALVAGE","QUEUE","BUY","SELL"}) do
  C.UI.ShowTab(C.UI.TAB[k])
  local cv = LucroCraftFrame.canvases[C.UI.TAB[k]]
  local err
  if cv then for i = 1, cv.used.text do local t = cv.pools.text[i]._text; if tostring(t):find("Erro") then err = t end end end
  print(k, err or "ok", cv and cv.used.box or "-")
end
