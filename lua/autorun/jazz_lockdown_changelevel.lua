-- lua/autorun/server/jazz_lockdown_changelevel.lua
if not SERVER then return end

local BLOCK_CLASSES = {
  trigger_changelevel = true,
  game_end            = true,
  point_servercommand = true,
  point_clientcommand = true,
  lua_run             = true,   -- GMod
}

-- Commands that end/change/kick or load a new map
local function isBadCmd(s)
  s = string.lower(tostring(s or ""))
  return s:find("^changelevel",1,true)
      or s:find("^changelevel2",1,true)
      or s:find("^map ",1,true)
      or s:find("^map_background",1,true)
      or s:find("^disconnect",1,true)
      or s:find("^kick",1,true) or s:find("^kickid",1,true)
      or s:find("^quit",1,true) or s:find("^exit",1,true)
      or s:find("^killserver",1,true)
end

-- 1) Strip obvious ones on spawn
hook.Add("InitPostEntity","JLOCK_StripOnSpawn", function()
  for cls in pairs(BLOCK_CLASSES) do
    for _,e in ipairs(ents.FindByClass(cls)) do SafeRemoveEntity(e) end
  end
  print("[JLOCK] stripped changelevel/servercommand/lua_run on InitPostEntity")
end)

-- 2) Also kill any that are created later (via templates, etc.)
hook.Add("OnEntityCreated","JLOCK_KillLateSpawns", function(ent)
  local cls = ent:GetClass()
  if not BLOCK_CLASSES[cls] then return end
  timer.Simple(0, function()
    if IsValid(ent) then
      print("[JLOCK] Removing late-spawned", cls)
      SafeRemoveEntity(ent)
    end
  end)
end)

-- 3) Block inputs if any slip through
hook.Add("AcceptInput","JLOCK_BlockInputs", function(ent,input,activator,caller,data)
  local cls = ent:GetClass()
  if not BLOCK_CLASSES[cls] then return end

  if cls == "trigger_changelevel" or cls == "game_end" then
    print("[JLOCK] Blocked", cls, "input", input)
    return true
  end

  if (cls=="point_servercommand" or cls=="point_clientcommand")
     and (input=="Command" or input=="command") then
    if isBadCmd(data) then
      print("[JLOCK] Blocked map command:", data)
      return true
    end
  end

  if cls == "lua_run" then
    print("[JLOCK] Removing lua_run before it runs")
    SafeRemoveEntity(ent)
    return true
  end
end)

-- 4) Catch Lua-issued console commands (covers lua_run/scripted attempts)
local allowUntil = 0
local function allowBrief(sec) allowUntil = CurTime() + (sec or 3) end

local oldGCC = game.ConsoleCommand
function game.ConsoleCommand(cmd)
  if isBadCmd(cmd) and CurTime() > allowUntil then
    print("[JLOCK] BLOCK game.ConsoleCommand:", cmd)
    print(debug.traceback())
    return
  end
  return oldGCC(cmd)
end

local oldRCC = RunConsoleCommand
function RunConsoleCommand(cmd, ...)
  local line = cmd .. " " .. table.concat({...}, " ")
  if isBadCmd(line) and CurTime() > allowUntil then
    print("[JLOCK] BLOCK RunConsoleCommand:", line)
    print(debug.traceback())
    return
  end
  return oldRCC(cmd, ...)
end

-- 5) Let the tram/gamemode change level legitimately
hook.Add("Initialize","JLOCK_WrapLaunch", function()
  if mapcontrol and mapcontrol.Launch then
    local old = mapcontrol.Launch
    function mapcontrol.Launch(mapname)
      allowBrief(3)
      if newgame and newgame.SetGlobal then newgame.SetGlobal("last_map", game.GetMap()) end
      if playerwait and playerwait.SavePlayers then playerwait.SavePlayers() end
      return RunConsoleCommand("changelevel", string.StripExtension(mapname or ""))
    end
    print("[JLOCK] mapcontrol.Launch wrapped (tram allowed)")
  end
end)