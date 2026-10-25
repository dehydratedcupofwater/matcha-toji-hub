--[[
    JJS - Toji (Hired Killer) Matcha Script Hub
    Version 1.0.0

    Rupture Timings:              
    Tap 3 to start Rupture. The script waits until the grab phase starts,
    then presses 3 a second time at the right moment.

    Hotkeys:
        F2 / F3   lower / raise the delay by 0.01s
        F4        stop the script
        F5        start (or cancel) calibration, see the README

    Settings: edit the CONFIG section below, or (if you load this with
    loadstring and can't edit it) set overrides BEFORE the loadstring line:
        _G.TojiRuptureConfig = { DELAY = 0.30, DEBUG = true, CALIBRATE = true }
    Nothing below the CONFIG section should need changes.
]]

local VERSION = "1.0.0"
-- CONFIG
-- Seconds to wait after the grab phase starts before the second press.
-- Tuned at ~13 ms ping on a stationary dummy. Run calibration (F5) to find yours.
local DELAY = 0.325
-- true = print extra timing information to the console
local DEBUG = false
local KEY_ABILITY = 0x33     -- "3"
local KEY_DELAY_DOWN = 0x71  -- F2
local KEY_DELAY_UP = 0x72    -- F3
local KEY_STOP = 0x73        -- F4
local KEY_CALIBRATE = 0x74   -- F5
local REQUIRED_MOVES = { "Rupture", "ISOH" }

-- Calibration sweep (F5): tries each delay a few times and reports what worked
local CAL = { from = 0.00, to = 0.60, step = 0.05, tries = 2 }
-- INTERNALS (no need to edit below this line)
local STEP = 0.01        
local GIVE_UP = 3.0    
local MIN_WAIT = 1.3     
local SPIN = 0.25        
local HOLD = 0.03        
local WARN_AFTER = 3   

local clock = os.clock or tick
local LocalPlayer = game:GetService("Players").LocalPlayer

local function say(msg)
    print("[JJS Toji] " .. msg)
end

local function dbg(msg)
    if DEBUG then print("[JJS Toji][debug] " .. msg) end
end

local G = _G or {}
local GUARD_KEY = "__JJS_TOJI_RUPTURE_RUN"
if G[GUARD_KEY] then say("replacing the previously loaded copy.") end
G[GUARD_KEY] = (G[GUARD_KEY] or 0) + 1
local RUN_ID = G[GUARD_KEY]
local stopped = false
local function alive() return G[GUARD_KEY] == RUN_ID and not stopped end

local START_CALIBRATING = false
local userCfg = G.TojiRuptureConfig
if type(userCfg) == "table" then
    if type(userCfg.DELAY) == "number" then DELAY = userCfg.DELAY end
    if type(userCfg.DEBUG) == "boolean" then DEBUG = userCfg.DEBUG end
    if type(userCfg.CAL_FROM) == "number" then CAL.from = userCfg.CAL_FROM end
    if type(userCfg.CAL_TO) == "number" then CAL.to = userCfg.CAL_TO end
    if type(userCfg.CAL_STEP) == "number" and userCfg.CAL_STEP > 0 then CAL.step = userCfg.CAL_STEP end
    if type(userCfg.CAL_TRIES) == "number" and userCfg.CAL_TRIES >= 1 then CAL.tries = userCfg.CAL_TRIES end
    START_CALIBRATING = (userCfg.CALIBRATE == true)
end

local function getChar()
    local chars = game.Workspace:FindFirstChild("Characters")
    return chars and chars:FindFirstChild(LocalPlayer.Name)
end

local function isUsingHiredKiller()
    local char = getChar()
    local ms = char and char:FindFirstChild("Moveset")
    if not ms then return false end
    for _, name in ipairs(REQUIRED_MOVES) do
        if not ms:FindFirstChild(name) then return false end
    end
    return true
end

local infoCache = nil
local infoFailAt = -10

local function cacheValid()
    if not infoCache then return false end
    local ok, parent = pcall(function() return infoCache.Parent end)
    return ok and parent ~= nil
end

local function findInfo(char)
    if cacheValid() then return infoCache end
    infoCache = nil
    if clock() - infoFailAt < 1 then return nil end  
    for _, c in ipairs(char:GetChildren()) do
        if c.Name == "Info" then infoCache = c return c end
    end
    for _, d in ipairs(char:GetDescendants()) do
        if d.Name == "Info" then infoCache = d return d end
    end
    infoFailAt = clock()
    return nil
end

local function rcState()
    local char = getChar()
    local info = char and findInfo(char)
    if not info then return "absent" end
    local rc = info:FindFirstChild("RuptureCheck")
    if not rc then return "absent" end
    local v = "false"
    pcall(function() v = tostring(rc.Value) end)
    return v
end

local function waitUntil(t)
    while clock() < t - SPIN do task.wait() end
    local n = 0
    while clock() < t and n < 2000000 do n = n + 1 end
end

local cal = { active = false, index = 0, try = 0, results = {} }

local function calDelay()
    return CAL.from + cal.index * CAL.step
end

local function cancelCalibration()
    if cal.active then
        cal.active = false
        say("calibration cancelled.")
    end
end

local function finishCalibration()
    cal.active = false
    local last = cal.index - 1
    local bestS, bestE, curS = nil, nil, nil

    say("calibration results (hits/tries per delay):")
    for i = 0, last do
        local r = cal.results[i]
        if r then
            say(string.format("  delay %.3f: %d/%d", r.delay, r.wins, r.tries))
        end
        local good = r and r.tries > 0 and r.wins == r.tries
        if good then
            if not curS then curS = i end
            if not bestS or (i - curS) > (bestE - bestS) then
                bestS, bestE = curS, i
            end
        else
            curS = nil
        end
    end

    if bestS then
        local lo, hi = cal.results[bestS].delay, cal.results[bestE].delay
        DELAY = (lo + hi) / 2
        say(string.format("working window: %.3f to %.3f.", lo, hi))
        say(string.format("Using DELAY = %.3f for this session. To keep it, put _G.TojiRuptureConfig = { DELAY = %.3f } before the loadstring line (or set DELAY at the top if you run a local copy).", DELAY, DELAY))
    else
        say("no delay worked every time. Make sure you were casting Rupture on a target and tapping 3 once per cast, then try again.")
    end
end

local function recordCal(delayUsed, ok)
    local r = cal.results[cal.index]
    if not r then
        r = { delay = delayUsed, wins = 0, tries = 0 }
        cal.results[cal.index] = r
    end
    r.tries = r.tries + 1
    if ok then r.wins = r.wins + 1 end
    say(string.format("calibration: delay %.3f -> %s", delayUsed, ok and "hit" or "miss"))

    cal.try = cal.try + 1
    if cal.try >= CAL.tries then
        cal.try = 0
        cal.index = cal.index + 1
        if CAL.from + cal.index * CAL.step > CAL.to + 0.0001 then
            finishCalibration()
        end
    end
end

local function startCalibration()
    cal.active = true
    cal.index, cal.try, cal.results = 0, 0, {}
    local steps = math.floor((CAL.to - CAL.from) / CAL.step + 0.5) + 1
    say(string.format("calibration started: about %d casts. Tap 3 once per cast on a training dummy. Press F5 again to cancel.", steps * CAL.tries))
end

local noFreshStreak = 0

local function runCast(t0)
    local delay = cal.active and calDelay() or DELAY
    local seenAbsent = (rcState() == "absent")
    local freshAt = nil

    -- Wait for a NEW RuptureCheck (the grab phase). One left over from the
    -- previous cast doesn't count: it has to disappear and then reappear.
    while clock() - t0 < GIVE_UP do
        task.wait()
        local s = rcState()
        if s == "absent" then
            seenAbsent = true
        elseif seenAbsent and (clock() - t0) > MIN_WAIT then
            freshAt = clock()
            break
        end
    end

    if not freshAt then
        noFreshStreak = noFreshStreak + 1
        dbg("no fresh RuptureCheck, not pressing")
        if noFreshStreak >= WARN_AFTER then
            noFreshStreak = 0
            say("Rupture didn't reach the grab phase " .. WARN_AFTER .. " casts in a row. It may be on cooldown, or the lunge may be missing. If neither is the case, the game may have updated and this script needs a fix.")
        end
        return
    end
    noFreshStreak = 0

    waitUntil(freshAt + delay)

    local w = clock()
    while iskeypressed(KEY_ABILITY) and clock() - w < 0.5 do task.wait() end

    local pressAt = clock()
    keypress(KEY_ABILITY)
    waitUntil(clock() + HOLD)
    keyrelease(KEY_ABILITY)

    -- RuptureCheck flips to true when the second press is accepted.
    local last, ok = rcState(), false
    local t2 = clock()
    while clock() - t2 < 1.5 do
        task.wait()
        local s = rcState()
        if s ~= last then
            dbg(string.format("RuptureCheck %.3fs after press: %s -> %s", clock() - pressAt, last, s))
            last = s
        end
        if s == "true" then ok = true end
    end

    dbg(string.format("grab phase seen at +%.3fs, pressed %.3fs later (delay %.3f): %s",
        freshAt - t0, pressAt - freshAt, delay, ok and "hit" or "miss"))

    if cal.active then recordCal(delay, ok) end
end

-- Main loop
local keyState = {}
local function pressed(key)  -- true once, on the frame the key goes down
    local down = iskeypressed(key)
    local was = keyState[key]
    keyState[key] = down
    return down and not was
end

local function measure(arg)
    local t = clock()
    for _ = 1, 10 do
        if arg then task.wait(arg) else task.wait() end
    end
    return (clock() - t) / 10
end

say(string.format("v%s loaded. Tap 3 to cast Rupture. F2/F3 delay, F4 stop, F5 calibrate. Delay is %.3f.", VERSION, DELAY))
if not isUsingHiredKiller() then
    say("Toji (Hired Killer) not detected right now. The script activates when you play him.")
end

if START_CALIBRATING then startCalibration() end

local busy = false
task.spawn(function()
    if DEBUG then
        dbg(string.format("task.wait() ~%.0f ms | task.wait(0.05) ~%.0f ms", measure(nil) * 1000, measure(0.05) * 1000))
    end

    while alive() do
        task.wait()

        if pressed(KEY_STOP) then
            stopped = true
            say("stopped.")
        end
        if pressed(KEY_DELAY_DOWN) then
            cancelCalibration()
            DELAY = math.max(0, DELAY - STEP)
            say(string.format("delay = %.3f", DELAY))
        end
        if pressed(KEY_DELAY_UP) then
            cancelCalibration()
            DELAY = DELAY + STEP
            say(string.format("delay = %.3f", DELAY))
        end
        if pressed(KEY_CALIBRATE) then
            if cal.active then cancelCalibration() else startCalibration() end
        end

        local t0 = clock()
        if pressed(KEY_ABILITY) and not busy and isUsingHiredKiller() then
            busy = true
            task.spawn(function()
                local ok, err = pcall(runCast, t0)
                if not ok then say("error: " .. tostring(err)) end
                task.wait(0.5)  -- let the synthetic key release settle
                busy = false
            end)
        end
    end
end)
