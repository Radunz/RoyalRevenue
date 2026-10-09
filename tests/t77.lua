local got = {}
ChatFrame1 = { AddMessage = function(_, m) table.insert(got, "GERAL: " .. m) end }
ChatFrame3 = { name = "Log", AddMessage = function(_, m) table.insert(got, "LOG: " .. m) end }
DEFAULT_CHAT_FRAME = ChatFrame1
NUM_CHAT_WINDOWS = 10
GetChatWindowInfo = function(i) if i == 1 then return "General", 0,0,0,0,0, true, 0, 1 elseif i == 3 then return "Log", 0,0,0,0,0, false, 0, 1 end return "", 0,0,0,0,0,false,0,nil end
dofile("harness.lua")
RR.Craft.Print("teste do craft")
SlashCmdList.ROYALREVENUE("log")
for _, m in ipairs(got) do if not m:find("Varreduras") then print(m) end end
