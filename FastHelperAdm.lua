-- FastHelperAdm v2.1 (ANSI, CP1251)
script_name("FastHelperAdm")
script_author("waldemar03 | Alim Akimov")
script_version("2.2")

require "lib.moonloader"
require "lib.render"
local imgui = require "imgui"
local encoding = require "encoding"
local vkeys = require 'vkeys'
require "lib.sampfuncs"
local sampev = require 'samp.events'
local Matrix3X3 = require "matrix3x3"
local Vector3D = require "vector3d"
require "samp.raknet"
encoding.default = "CP1251"
local u8 = encoding.UTF8

-- ===== АВТООБНОВЛЕНИЕ (ПРОСТОЙ И НАДЁЖНЫЙ) =====
local function checkForUpdate()
    local CURRENT_VERSION = 2.2
    local repoURL = "https://raw.githubusercontent.com/AlimkaSa/samp-script-updater/main"
    local scriptName = "FastHelperAdm.lua"
    
    -- Получаем полный путь к скрипту
    local scriptPath = getWorkingDirectory() .. "\\" .. scriptName
    local tempPath = getWorkingDirectory() .. "\\FastHelperAdm_temp.lua"
    
    -- Функция для скачивания текста через curl
    local function downloadText(url)
        local tempFile = os.tmpname()
        os.execute('curl -s --connect-timeout 5 "' .. url .. '" -o "' .. tempFile .. '"')
        local file = io.open(tempFile, "r")
        if file then
            local content = file:read("*a")
            file:close()
            os.remove(tempFile)
            return content
        end
        return nil
    end
    
    -- Функция для скачивания файла
    local function downloadFile(url, filename)
        os.execute('curl -s --connect-timeout 10 "' .. url .. '" -o "' .. filename .. '"')
        local file = io.open(filename, "r")
        if file then
            file:close()
            return true
        end
        return false
    end
    
    -- Проверяем версию на GitHub
    local remoteVer = downloadText(repoURL .. "/version.txt")
    if not remoteVer then
        return
    end
    
    remoteVer = remoteVer:gsub("%s+", "")
    local remoteNum = tonumber(remoteVer)
    
    if not remoteNum or remoteNum <= CURRENT_VERSION then
        return
    end
    
    -- Есть обновление!
    print(string.format("[FastHelperAdm] Найдено обновление! %s -> %s", CURRENT_VERSION, remoteNum))
    
    -- Скачиваем в temp файл
    if not downloadFile(repoURL .. "/" .. scriptName, tempPath) then
        print("[FastHelperAdm] Ошибка скачивания!")
        return
    end
    
    -- Проверяем, что скачалось
    local testFile = io.open(tempPath, "r")
    if not testFile then
        print("[FastHelperAdm] Файл не скачан!")
        return
    end
    testFile:close()
    
    -- УДАЛЯЕМ старый файл
    if io.open(scriptPath, "r") then
        os.remove(scriptPath)
    end
    
    -- ПЕРЕИМЕНОВЫВАЕМ temp в основной
    os.rename(tempPath, scriptPath)
    
    print("[FastHelperAdm] Обновление установлено на версию " .. remoteNum .. "!")
    printStringNow("~g~FastHelperAdm~w~: ~y~Обновление установлено!~n~~w~Версия " .. remoteNum, 3000)
    
    -- ПЕРЕЗАГРУЗКА
    lua_thread.create(function()
        wait(1500)
        for _, scr in ipairs(script.list()) do
            if scr.filename == scriptPath or scr.filename:match("FastHelperAdm%.lua$") then
                scr:unload()
                break
            end
        end
        wait(100)
        script.load(scriptPath)
    end)
end

-- Запускаем проверку
lua_thread.create(function()
    wait(3000)
    checkForUpdate()
end)
-- ===== КОНЕЦ АВТООБНОВЛЕНИЯ =====

-- ===== ADMIN RENDER СТРУКТУРА =====
local adminRender = {
    enabled = imgui.ImBool(false),
    showLvl = imgui.ImBool(true),
    showAction = imgui.ImBool(true),
    showActive = imgui.ImBool(true),
    admins = {},
    afk = 0,
    recon = 0,
    activeTimes = {},
    font = nil,
    posX = 500,
    posY = 500,
    cooldown = 30,
    lastUpdate = 0,
    isMoving = false,
    dragOffsetX = 0,
    dragOffsetY = 0,
    initialized = false,
    levelColors = {
        [1]  = "00A000", [2]  = "009000", [3]  = "008000",
        [4]  = "1AD600", [5]  = "C2A600", [6]  = "9E8700",
        [7]  = "7B69ED", [8]  = "5C42EB", [9]  = "472BE8",
        [10] = "8A2BE3", [11] = "6E19BD", [12] = "C016E7",
        [13] = "D14C39", [14] = "E67A00",
    },
    lvlFilter = {true, true, true, true, true, true, true, true, true, true, true, true, true, true},
}

-- ===== ФУНКЦИИ ДЛЯ РАБОТЫ С ЦВЕТАМИ =====
function join_argb(r, g, b, a)
    a = a or 255
    local argb = math.floor(b)
    argb = bit.bor(argb, bit.lshift(math.floor(g), 8))
    argb = bit.bor(argb, bit.lshift(math.floor(r), 16))
    argb = bit.bor(argb, bit.lshift(math.floor(a), 24))
    return argb
end

function explode_argb(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF)
    local r = bit.band(bit.rshift(argb, 16), 0xFF)
    local g = bit.band(bit.rshift(argb, 8), 0xFF)
    local b = bit.band(argb, 0xFF)
    return a, r, g, b
end

-- ===== KILL LIST ID МОДУЛЬ =====
local killList = {
    enabled = false,
    ptr = nil,
    originalKiller = {},
    originalVictim = {},
    initialized = false
}

local ffi = require 'ffi'
ffi.cdef[[
struct stKillEntry
{
    char szKiller[25];
    char szVictim[25];
    uint32_t clKillerColor;
    uint32_t clVictimColor;
    uint8_t byteType;
} __attribute__ ((packed));

struct stKillInfo
{
    int iEnabled;
    struct stKillEntry killEntry[5];
    int iLongestNickLength;
    int iOffsetX;
    int iOffsetY;
    void *pD3DFont;
    void *pWeaponFont1;
    void *pWeaponFont2;
    void *pSprite;
    void *pD3DDevice;
    int iAuxFontInited;
    void *pAuxFont1;
    void *pAuxFont2;
} __attribute__ ((packed));
]]

function killList.saveOriginalNames()
    if not killList.ptr then return end
    for i = 0, 4 do
        killList.originalKiller[i] = ffi.string(killList.ptr.killEntry[i].szKiller)
        killList.originalVictim[i] = ffi.string(killList.ptr.killEntry[i].szVictim)
    end
end

function killList.restoreOriginalNames()
    if not killList.ptr then return end
    for i = 0, 4 do
        if killList.originalKiller[i] and #killList.originalKiller[i] > 0 then
            ffi.copy(killList.ptr.killEntry[i].szKiller, killList.originalKiller[i])
        end
        if killList.originalVictim[i] and #killList.originalVictim[i] > 0 then
            ffi.copy(killList.ptr.killEntry[i].szVictim, killList.originalVictim[i])
        end
    end
end

function killList.init()
    if killList.initialized then return end
    killList.ptr = ffi.cast('struct stKillInfo*', sampGetKillInfoPtr())
    if killList.ptr == nil then
        return
    end
    killList.saveOriginalNames()
    killList.initialized = true
end

function killList.toggle()
    killList.enabled = not killList.enabled
    if killList.enabled then
        killList.saveOriginalNames()
    else
        killList.restoreOriginalNames()
    end
end

function killList.onDeath(killerId, killedId, reason)
    if not killList.enabled or not killList.ptr then return end
    
    local _, myid = sampGetPlayerIdByCharHandle(playerPed)
    
    local n_killer = (sampIsPlayerConnected(killerId) or killerId == myid) and sampGetPlayerNickname(killerId) or nil
    local n_killed = (sampIsPlayerConnected(killedId) or killedId == myid) and sampGetPlayerNickname(killedId) or nil
    
    lua_thread.create(function()
        wait(0)
        if n_killer and killerId and killerId >= 0 then
            killList.ptr.killEntry[4].szKiller = ffi.new('char[25]', (n_killer .. '[' .. killerId .. ']'):sub(1, 24))
        end
        if n_killed and killedId and killedId >= 0 then
            killList.ptr.killEntry[4].szVictim = ffi.new('char[25]', (n_killed .. '[' .. killedId .. ']'):sub(1, 24))
        end
    end)
end

-- ===== WALLHACK МОДУЛЬ =====
local mem = require "memory"
local getBonePosition = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 0x5E4280)

local wh_settings = {
    enabled = false,
    by_nick = true,
    by_skeleton = true,
    show_on_screenshot = false
}

local wh_enabled_checkbox = imgui.ImBool(false)
local wh_by_nick_checkbox = imgui.ImBool(true)
local wh_by_skeleton_checkbox = imgui.ImBool(true)
local wh_show_on_screenshot_checkbox = imgui.ImBool(false)

local nameTag = false
local NTdist, NTwalls, NTshow = 0, 0, 0

FHA = FHA or {}
FHA.whPaused = false

local function wh_nameTagOn()
    local pStSet = sampGetServerSettingsPtr()
    NTdist = mem.getfloat(pStSet + 39)
    NTwalls = mem.getint8(pStSet + 47)
    NTshow = mem.getint8(pStSet + 56)
    mem.setfloat(pStSet + 39, 1488.0)
    mem.setint8(pStSet + 47, 0)
    mem.setint8(pStSet + 56, 1)
    nameTag = true
end

local function wh_nameTagOff()
    local pStSet = sampGetServerSettingsPtr()
    mem.setfloat(pStSet + 39, NTdist)
    mem.setint8(pStSet + 47, NTwalls)
    mem.setint8(pStSet + 56, NTshow)
    nameTag = false
end

local function wh_getBodyPartCoordinates(id, handle)
    local pedptr = getCharPointer(handle)
    local vec = ffi.new("float[3]")
    getBonePosition(ffi.cast("void*", pedptr), vec, id, true)
    return vec[0], vec[1], vec[2]
end

local function wh_isKeyDown(key)
    return isKeyDown(key)
end

local function wh_thread()
    while not FHA.isUnloading do
        wait(0)
        
        if wh_settings.enabled then
            if wh_settings.by_nick and not nameTag then
                wh_nameTagOn()
            end
            
            local should_hide = not wh_settings.show_on_screenshot and (isPauseMenuActive() or wh_isKeyDown(0x78))
            
            if not should_hide then
                if wh_settings.by_skeleton then
                    for i = 0, sampGetMaxPlayerId() do
                        if sampIsPlayerConnected(i) then
                            local result, cped = sampGetCharHandleBySampPlayerId(i)
                            local color = sampGetPlayerColor(i)
                            local aa, rr, gg, bb = explode_argb(color)
                            local color = join_argb(rr, gg, bb, 255)
                            if result then
                                if doesCharExist(cped) and isCharOnScreen(cped) then
                                    if not FHA.whPaused then
                                        local bodyX, bodyY, bodyZ = wh_getBodyPartCoordinates(3, cped)
                                        local bodyX2, bodyY2, bodyZ2 = wh_getBodyPartCoordinates(2, cped)
                                        local bodyScrX, bodyScrY = convert3DCoordsToScreen(bodyX, bodyY, bodyZ)
                                        local bodyScrX2, bodyScrY2 = convert3DCoordsToScreen(bodyX2, bodyY2, bodyZ2)
                                        
                                        local bones = {3, 4, 5, 51, 52, 41, 42, 31, 32, 33, 21, 22, 23, 2}
                                        for v = 1, #bones do
                                            local pos1X, pos1Y, pos1Z = wh_getBodyPartCoordinates(bones[v], cped)
                                            local pos2X, pos2Y, pos2Z = wh_getBodyPartCoordinates(bones[v] + 1, cped)
                                            local scrX1, scrY1 = convert3DCoordsToScreen(pos1X, pos1Y, pos1Z)
                                            local scrX2, scrY2 = convert3DCoordsToScreen(pos2X, pos2Y, pos2Z)
                                            renderDrawLine(scrX1, scrY1, scrX2, scrY2, 2, color)
                                        end
                                        for v = 4, 5 do
                                            local pos2X, pos2Y, pos2Z = wh_getBodyPartCoordinates(v * 10 + 1, cped)
                                            local scrX, scrY = convert3DCoordsToScreen(pos2X, pos2Y, pos2Z)
                                            renderDrawLine(bodyScrX, bodyScrY, scrX, scrY, 2, color)
                                            renderDrawLine(bodyScrX2, bodyScrY2, scrX, scrY, 2, color)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            else
                if nameTag then
                    wh_nameTagOff()
                end
                while isPauseMenuActive() or wh_isKeyDown(0x78) do wait(0) end
                if wh_settings.enabled and wh_settings.by_nick then
                    wh_nameTagOn()
                end
            end
        else
            if nameTag then
                wh_nameTagOff()
            end
        end
    end
end

-- ===== ADMIN RENDER ФУНКЦИИ =====
function adminRender.init()
    if adminRender.initialized then return end
    adminRender.font = renderCreateFont("Arial", 10, 1 + 8)
    adminRender.initialized = true
end

function adminRender.update()
    if not adminRender.enabled.v then return end
    
    lua_thread.create(function()
        if FHA.isUnloading then return end
        adminRender.admins = {}
        adminRender.afk = 0
        adminRender.recon = 0
        
        sampSendChat("/admins")
        wait(2000)
        
        adminRender.lastUpdate = os.clock()
    end)
end

function adminRender.onServerMessage(color, text)
    if not adminRender.enabled.v then return false end
    if not text then return false end
    
    local cleanText = text:gsub("{%x%x%x%x%x%x}", "")
    
    -- Пропускаем заголовок
    if cleanText:find("Администрация в сети:") or cleanText:find("Администраторы онлайн") then
        return true
    end
    
    -- Парсим: "Nickname[ID] (LVL lvl) [AFK]"
    local nick, id, lvl, action = 
        cleanText:match("([^%[]+)%[(%d+)%] %((%d+) lvl%)(.*)")
    
    -- Альтернативный формат: "Nickname [ID] - LVL lvl"
    if not nick then
        nick, id, lvl, action = 
            cleanText:match("([^%[]+)%[(%d+)%] %- (%d+) lvl(.*)")
    end
    
    if nick and id and lvl then
        nick = nick:gsub("^%s*(.-)%s*$", "%1")
        
        local actionType = "not"
        if action and action:find("AFK") then
            actionType = "AFK"
            adminRender.afk = adminRender.afk + 1
        elseif action and action:find("/re") then
            actionType = "re"
            adminRender.recon = adminRender.recon + 1
        end
        
        local admin = {
            nick = nick,
            id = tonumber(id),
            lvl = tonumber(lvl),
            action = actionType,
            reNick = nil,
            reId = nil,
        }
        
        adminRender.activeTimes[nick] = os.time()
        table.insert(adminRender.admins, admin)
        return true
    end
    
    return false
end

function adminRender.draw()
    if not adminRender.enabled.v then return end
    if not adminRender.initialized then adminRender.init() end
    
    -- Если админов нет, показываем статус
    if #adminRender.admins == 0 then
        local posX = adminRender.posX
        local posY = adminRender.posY
        renderFontDrawText(adminRender.font, "Администраторы: загрузка...", posX, posY, -1)
        return
    end
    
    local state = sampGetGamestate()
    if state ~= 3 then return end
    if isPauseMenuActive() then return end
    if FHA.state and FHA.state.showMenu and FHA.state.showMenu.v then return end
    
    local posX = adminRender.posX
    local posY = adminRender.posY
    
    local header = string.format("Администраторы {00ff00}online{ffffff} [ %s | {ff0000}AFK: %s{ffffff} | {32CD32}/re: %s{ffffff} ]:", 
        #adminRender.admins, adminRender.afk, adminRender.recon)
    
    renderFontDrawText(adminRender.font, header, posX, posY - 20, -1)
    
    local sorted = {}
    for _, admin in ipairs(adminRender.admins) do
        local lvl = admin.lvl or 0
        if lvl >= 1 and lvl <= 14 and adminRender.lvlFilter[lvl] then
            table.insert(sorted, admin)
        end
    end
    table.sort(sorted, function(a, b)
        return (a.lvl or 0) > (b.lvl or 0)
    end)
    
    local yOffset = 0
    local lineHeight = 16
    
    for _, admin in ipairs(sorted) do
        local color = adminRender.levelColors[admin.lvl] or "FFFFFF"
        local nick = admin.nick
        
        if nick == sampGetPlayerNickname(sampGetPlayerIdByCharHandle(PLAYER_PED)) then
            local time = os.clock()
            local r = math.floor((math.sin(time * 2.0) + 1.0) * 127.5)
            local g = math.floor((math.sin(time * 2.0 + math.pi/3) + 1.0) * 127.5)
            local b = math.floor((math.sin(time * 2.0 + 2*math.pi/3) + 1.0) * 127.5)
            color = string.format("%02X%02X%02X", r, g, b)
        end
        
        local text = string.format("{%s} | %s(%s)", color, nick, admin.id)
        
        if adminRender.showLvl.v then
            text = text .. string.format(" - {%s}%s lvl", color, admin.lvl)
        end
        
        if adminRender.showAction.v then
            if admin.action == "AFK" then
                text = text .. " - {FF0000}AFK"
            elseif admin.action == "re" then
                text = text .. " - {32CD32}/re"
            end
        end
        
        if adminRender.showActive.v then
            local activeTime = adminRender.activeTimes[nick] or 0
            if activeTime > 0 then
                local seconds = math.floor(os.time() - activeTime)
                if seconds > 0 then
                    local timeStr = seconds < 60 and string.format("%ss", seconds) or 
                                   string.format("%sm", math.floor(seconds/60))
                    text = text .. string.format(" | A: {FFA500}%s", timeStr)
                end
            end
        end
        
        renderFontDrawText(adminRender.font, text, posX, posY + yOffset, -1)
        yOffset = yOffset + lineHeight
    end
end

function adminRender.updateLoop()
    while not FHA.isUnloading do
        wait(0)
        if adminRender.enabled.v then
            adminRender.draw()
        end
    end
end

function adminRender.autoUpdateLoop()
    while not FHA.isUnloading do
        wait(adminRender.cooldown * 1000)
        if adminRender.enabled.v then
            adminRender.update()
        end
    end
end

function adminRender.startMove()
    adminRender.isMoving = true
    local mx, my = getCursorPos()
    adminRender.dragOffsetX = mx - adminRender.posX
    adminRender.dragOffsetY = my - adminRender.posY
    sampSetCursorMode(4)
end

function adminRender.stopMove(save)
    adminRender.isMoving = false
    sampSetCursorMode(0)
    if save then
        local f = io.open(getWorkingDirectory() .. "\\config\\admin_render_pos.ini", "w")
        if f then
            f:write("posX=" .. adminRender.posX .. "\n")
            f:write("posY=" .. adminRender.posY .. "\n")
            f:close()
        end
    end
end

function adminRender.updateMove()
    if not adminRender.isMoving then return end
    local mx, my = getCursorPos()
    adminRender.posX = mx - adminRender.dragOffsetX
    adminRender.posY = my - adminRender.dragOffsetY
    
    local sw, sh = getScreenResolution()
    adminRender.posX = math.max(0, math.min(sw - 300, adminRender.posX))
    adminRender.posY = math.max(0, math.min(sh - 100, adminRender.posY))
end

function adminRender.loadPosition()
    local f = io.open(getWorkingDirectory() .. "\\config\\admin_render_pos.ini", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%w+)=([%d.]+)$")
            if k == "posX" then adminRender.posX = tonumber(v) end
            if k == "posY" then adminRender.posY = tonumber(v) end
        end
        f:close()
    end
end

function adminRender.saveFilter()
    local f = io.open(getWorkingDirectory() .. "\\config\\admin_render_filter.ini", "w")
    if f then
        for i = 1, 14 do
            f:write("lvl" .. i .. "=" .. (adminRender.lvlFilter[i] and "1" or "0") .. "\n")
        end
        f:close()
    end
end

function adminRender.loadFilter()
    local f = io.open(getWorkingDirectory() .. "\\config\\admin_render_filter.ini", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(lvl%d+)=([%d.]+)$")
            if k then
                local lvl = tonumber(k:match("lvl(%d+)"))
                if lvl and lvl >= 1 and lvl <= 14 then
                    adminRender.lvlFilter[lvl] = (tonumber(v) == 1)
                end
            end
        end
        f:close()
    end
end

-- ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ =====
FastHelperAdm = FastHelperAdm or {}
FHA = FastHelperAdm
FHA.threads = {}
FHA.isUnloading = false
FHA.isImguiInteracting = false

-- ===== АВТОЛОГИН =====
FHA.autoLogin = {
    enabled = imgui.ImBool(false),
    password = imgui.ImBuffer(128),
    showPassword = imgui.ImBool(false)
}

-- ===== СИСТЕМА ОТВЕТОВ НА РЕПОРТЫ =====
FHA.reports = {}
FHA.MAX_REPORTS = 15
FHA.REPORT_LIFETIME = 120
FHA.selectedReport = nil
FHA.answerText = imgui.ImBuffer(256)

-- ===== ПРАВИЛА СЕРВЕРОВ =====
FHA.rulesMode = 1
FHA.rulesSearch = imgui.ImBuffer(128)
FHA.rulesSectionStates = {true, true, true, true, true, true}

FHA.PRIZE_IDS = {
    LEVEL          = 1,
    WANTED         = 2,
    MATERIALS      = 3,
    KILLS          = 4,
    PHONE          = 5,
    EXP            = 6,
    BANK_MONEY     = 7,
    PHONE_MONEY    = 8,
    CASH           = 9,
    MEDKITS        = 10,
    ORG_MEMBER     = 11,
    BOX            = 12,
    KUNGFU         = 13,
    KICKBOX        = 14,
    DRUG_ADD       = 15,
    DRUGS          = 16
}

-- ===== ФУНКЦИЯ ЗАГРУЗКИ ТЕКСТОВЫХ ФАЙЛОВ =====
function FHA_loadTextFile(path)
    local t = {}
    local f = io.open(path, "r")
    if not f then 
        table.insert(t, "Файл не найден: " .. path)
        return t
    end
    
    for line in f:lines() do
        table.insert(t, line)
    end
    f:close()
    return t
end

local rulesEnvyPath  = getWorkingDirectory() .. "\\FastHelperAdm\\Rules_Envy\\"
local rulesPridePath = getWorkingDirectory() .. "\\FastHelperAdm\\Rules_Pride\\"
local rulesAngerPath = getWorkingDirectory() .. "\\FastHelperAdm\\Rules_Anger\\"

FHA.rulesEnvy = {server = {}, admin = {}, aad = {}, goss = {}, capt = {}, bizwar = {}}
FHA.rulesPride = {server = {}, admin = {}, aad = {}, goss = {}, capt = {}, bizwar = {}}
FHA.rulesAnger = {server = {}, admin = {}, aad = {}, goss = {}, capt = {}, bizwar = {}}

FHA.rulesEnvyNames = {
    "ENVY | Правила Сервера",
    "ENVY | Правила Администрации",
    "ENVY | Правила использования /aad и /o",
    "ENVY | Общие правила Goss",
    "ENVY | Правила каптов",
    "ENVY | Правила стрел bizwar"
}

FHA.rulesPrideNames = {
    "PRIDE | Правила Сервера",
    "PRIDE | Правила Администраций",
    "PRIDE | Правила Использования /aad и /o",
    "PRIDE | Общие правила Goss",
    "PRIDE | Правила Каптов",
    "PRIDE | Правила стрел bizwar"
}

FHA.rulesAngerNames = {
    "ANGER | Правила Сервера",
    "ANGER | Правила Администрации",
    "ANGER | Правила использования /aad и /o",
    "ANGER | Общие правила Goss",
    "ANGER | Правила каптов",
    "ANGER | Правила стрел bizwar"
}

function FHA_loadEnvyRules()
    FHA.rulesEnvy.server = FHA_loadTextFile(rulesEnvyPath .. "rules_envy.txt")
    FHA.rulesEnvy.admin = FHA_loadTextFile(rulesEnvyPath .. "rules_adm_envy.txt")
    FHA.rulesEnvy.aad = FHA_loadTextFile(rulesEnvyPath .. "rules_aad_envy.txt")
    FHA.rulesEnvy.goss = FHA_loadTextFile(rulesEnvyPath .. "rules_goss_envy.txt")
    FHA.rulesEnvy.capt = FHA_loadTextFile(rulesEnvyPath .. "rules_capt_envy.txt")
    FHA.rulesEnvy.bizwar = FHA_loadTextFile(rulesEnvyPath .. "rules_bizwar_envy.txt")
end

function FHA_loadPrideRules()
    FHA.rulesPride.server = FHA_loadTextFile(rulesPridePath .. "rules_pride.txt")
    FHA.rulesPride.admin = FHA_loadTextFile(rulesPridePath .. "rules_adm_pride.txt")
    FHA.rulesPride.aad = FHA_loadTextFile(rulesPridePath .. "rules_aad_pride.txt")
    FHA.rulesPride.goss = FHA_loadTextFile(rulesPridePath .. "rules_goss_pride.txt")
    FHA.rulesPride.capt = FHA_loadTextFile(rulesPridePath .. "rules_capt_pride.txt")
    FHA.rulesPride.bizwar = FHA_loadTextFile(rulesPridePath .. "rules_bizwar_pride.txt")
end

function FHA_loadAngerRules()
    FHA.rulesAnger.server = FHA_loadTextFile(rulesAngerPath .. "rules_anger.txt")
    FHA.rulesAnger.admin = FHA_loadTextFile(rulesAngerPath .. "rules_adm_anger.txt")
    FHA.rulesAnger.aad = FHA_loadTextFile(rulesAngerPath .. "rules_aad_anger.txt")
    FHA.rulesAnger.goss = FHA_loadTextFile(rulesAngerPath .. "rules_goss_anger.txt")
    FHA.rulesAnger.capt = FHA_loadTextFile(rulesAngerPath .. "rules_capt_anger.txt")
    FHA.rulesAnger.bizwar = FHA_loadTextFile(rulesAngerPath .. "rules_bizwar_anger.txt")
end

-- ===== ФУНКЦИЯ СОЗДАНИЯ СИНХРОДАННЫХ =====
function samp_create_sync_data(arg_4_0, arg_4_1)
    local var_4_0 = require("ffi")
    local var_4_1 = require("sampfuncs")
    local var_4_2 = require("samp.raknet")

    arg_4_1 = arg_4_1 or true

    local var_4_3 = ( {
        player = {
            "PlayerSyncData",
            var_4_2.PACKET.PLAYER_SYNC,
            sampStorePlayerOnfootData
        },
        vehicle = {
            "VehicleSyncData",
            var_4_2.PACKET.VEHICLE_SYNC,
            sampStorePlayerIncarData
        },
        passenger = {
            "PassengerSyncData",
            var_4_2.PACKET.PASSENGER_SYNC,
            sampStorePlayerPassengerData
        },
        aim = {
            "AimSyncData",
            var_4_2.PACKET.AIM_SYNC,
            sampStorePlayerAimData
        },
        trailer = {
            "TrailerSyncData",
            var_4_2.PACKET.TRAILER_SYNC,
            sampStorePlayerTrailerData
        },
        unoccupied = {
            "UnoccupiedSyncData",
            var_4_2.PACKET.UNOCCUPIED_SYNC
        },
        bullet = {
            "BulletSyncData",
            var_4_2.PACKET.BULLET_SYNC
        },
        spectator = {
            "SpectatorSyncData",
            var_4_2.PACKET.SPECTATOR_SYNC
        }
    })[arg_4_0]
    local var_4_4 = "struct " .. var_4_3[1]
    local var_4_5 = var_4_0.new(var_4_4, {})
    local var_4_6 = tonumber(var_4_0.cast("uintptr_t", var_4_0.new(var_4_4 .. "*", var_4_5)))

    if arg_4_1 then
        local var_4_7 = var_4_3[3]

        if var_4_7 then
            local var_4_8
            local var_4_9

            if arg_4_1 == true then
                local var_4_10
                local var_4_11

                var_4_11, var_4_9 = sampGetPlayerIdByCharHandle(PLAYER_PED)
            else
                var_4_9 = tonumber(arg_4_1)
            end

            var_4_7(var_4_9, var_4_6)
        end
    end

    local function var_4_12()
        local var_5_0 = raknetNewBitStream()

        raknetBitStreamWriteInt8(var_5_0, var_4_3[2])
        raknetBitStreamWriteBuffer(var_5_0, var_4_6, var_4_0.sizeof(var_4_5))
        raknetSendBitStreamEx(var_5_0, var_4_1.HIGH_PRIORITY, var_4_1.UNRELIABLE_SEQUENCED, 1)
        raknetDeleteBitStream(var_5_0)
    end

    local var_4_13 = {
        __index = function(arg_6_0, arg_6_1)
            return var_4_5[arg_6_1]
        end,
        __newindex = function(arg_7_0, arg_7_1, arg_7_2)
            var_4_5[arg_7_1] = arg_7_2
        end
    }

    return setmetatable({
        send = var_4_12
    }, var_4_13)
end

-- ===== ФУНКЦИИ ДЛЯ ПРАВИЛ =====
local function normalize(str)
    if not str then return "" end
    return tostring(str):lower()
end

function FHA_removeColorCodes(text)
    if not text then return "" end
    text = text:gsub("{%x%x%x%x%x%x}", "")
    text = text:gsub("%x%x%x%x%x%x", "")
    return text
end

function FHA_removeReport(index)
    if not index or not FHA.reports[index] then return end
    table.remove(FHA.reports, index)
    FHA.selectedReport = nil
    FHA.answerText.v = ""
end

-- ===== INPUT МЕНЕДЖЕР =====
Input = {
    binds = {},
    
    canUse = function(self)
        if FHA.isUnloading then return false end
        if FHA.state.showMenu.v then return false end
        if sampIsChatInputActive() then return false end
        if sampIsScoreboardOpen() then return false end
        if FHA.isImguiInteracting then return false end
        return true
    end,
    
    bind = function(self, name, keyFunc, callback)
        self.binds[name] = {
            key = keyFunc,
            callback = callback,
            lastState = false,
            cooldown = 0
        }
    end,
    
    update = function(self)
        if FHA.isUnloading then return end
        if not self:canUse() then return end
        
        local currentTime = os.clock()
        
        for name, bind in pairs(self.binds) do
            if bind and bind.key and bind.callback then
                local pressed = false
                local success, result = pcall(bind.key)
                if success then
                    pressed = result
                else
                    pressed = false
                end
                
                if pressed and not bind.lastState and currentTime >= bind.cooldown then
                    local cbSuccess, cbError = pcall(bind.callback)
                    if not cbSuccess then
                        print("[FastHelperAdm][Input] Callback error for '"..tostring(name).."':", cbError)
                    end
                    
                    bind.cooldown = currentTime + 0.2
                end
                
                bind.lastState = pressed
            end
        end
    end,
    
    unbind = function(self, name)
        self.binds[name] = nil
    end,
    
    clear = function(self)
        self.binds = {}
    end
}

local function vkToString(vk)
    local keyNames = {
        [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3",
        [0x34] = "4", [0x35] = "5", [0x36] = "6", [0x37] = "7",
        [0x38] = "8", [0x39] = "9",
        [vkeys.VK_F1] = "F1", [vkeys.VK_F2] = "F2", [vkeys.VK_F3] = "F3",
        [vkeys.VK_F4] = "F4", [vkeys.VK_F5] = "F5", [vkeys.VK_F6] = "F6",
        [vkeys.VK_F7] = "F7", [vkeys.VK_F8] = "F8", [vkeys.VK_F9] = "F9",
        [vkeys.VK_F10] = "F10", [vkeys.VK_F11] = "F11", [vkeys.VK_F12] = "F12",
        [vkeys.VK_NUMPAD0] = "Num 0", [vkeys.VK_NUMPAD1] = "Num 1",
        [vkeys.VK_NUMPAD2] = "Num 2", [vkeys.VK_NUMPAD3] = "Num 3",
        [vkeys.VK_NUMPAD4] = "Num 4", [vkeys.VK_NUMPAD5] = "Num 5",
        [vkeys.VK_NUMPAD6] = "Num 6", [vkeys.VK_NUMPAD7] = "Num 7",
        [vkeys.VK_NUMPAD8] = "Num 8", [vkeys.VK_NUMPAD9] = "Num 9",
        [vkeys.VK_INSERT] = "Insert", [vkeys.VK_HOME] = "Home",
        [vkeys.VK_DELETE] = "Delete", [vkeys.VK_END] = "End",
        [vkeys.VK_SPACE] = "Space", [vkeys.VK_TAB] = "Tab",
        [vkeys.VK_LSHIFT] = "LShift", [vkeys.VK_RSHIFT] = "RShift",
        [vkeys.VK_LCONTROL] = "LCtrl", [vkeys.VK_RCONTROL] = "RCtrl",
        [vkeys.VK_MENU] = "Alt", [vkeys.VK_ESCAPE] = "Esc",
        [vkeys.VK_RETURN] = "Enter", [vkeys.VK_BACK] = "Backspace",
    }
    for i = 0x41, 0x5A do keyNames[i] = string.char(i) end
    return keyNames[vk] or ("VK_" .. tostring(vk))
end

local function formatMoneySmart(n)
    if not n or n < 0 then return "0" end
    n = math.floor(n)
    
    if n >= 1000000 then
        local m = math.floor(n / 1000000)
        local r = math.floor((n % 1000000) / 1000)
        return r > 0 and (m .. "kk" .. r) or (m .. "kk")
    elseif n >= 1000 then
        local k = math.floor(n / 1000)
        local r = n % 1000
        return r > 0 and (k .. "k" .. r) or (k .. "k")
    end
    return tostring(n)
end

FHA.VK_RSHIFT = 0xA1
FHA.VK_LSHIFT = 0xA0
FHA.VK_SPACE = 0x20
FHA.VK_F3 = 0x72
FHA.VK_F4 = 0x73
FHA.VK_MBUTTON = 0x04
FHA.VK_LBUTTON = 0x01
FHA.VK_RBUTTON = 0x02
FHA.VK_ESCAPE = 0x1B

function FHA_givePrize(playerId, prizeId, value)
    if prizeId == FHA.PRIZE_IDS.ORG_MEMBER then
        return
    end

    if prizeId == FHA.PRIZE_IDS.BOX 
    or prizeId == FHA.PRIZE_IDS.KUNGFU 
    or prizeId == FHA.PRIZE_IDS.KICKBOX then
        value = 50000
    end

    if prizeId == FHA.PRIZE_IDS.BANK_MONEY then
        sampSendChat(string.format("/money %d %d", playerId, tonumber(value)))
    else
        local command = string.format("/setstat %d %d %d", playerId, prizeId, tonumber(value))
        sampSendChat(command)
    end
    
    return true
end

-- ===== ZZVEH ФУНКЦИЯ (обход зелёной зоны) =====
function FHA_createCarInZZ()
    local st = FHA.state
    lua_thread.create(function()
        if FHA.isUnloading then return end
        
        -- Запоминаем позицию игрока
        local x, y, z = getCharCoordinates(PLAYER_PED)
        
        st.zzvehAct = true
        
        wait(1050)
        
        -- Отправляем /veh с сохранёнными параметрами
        sampSendChat("/veh " .. st.zzvehId .. " " .. st.zzvehC1 .. " " .. st.zzvehC2)
        wait(500)
        
        st.zzvehAct = false
        
        -- Возвращаем игрока на место
        setCharCoordinates(PLAYER_PED, x, y, z)
        
        st.zzvehActive = false
    end)
end

-- ===== СТИЛИ =====
function FHA_ApplyRedStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.12, 0.05, 0.05, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.50, 0.10, 0.10, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.75, 0.15, 0.15, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.60, 0.12, 0.12, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.80, 0.18, 0.18, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.95, 0.25, 0.25, 1.00)
end

function FHA_ApplyGreenStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.05, 0.12, 0.05, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.10, 0.50, 0.10, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.15, 0.75, 0.15, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.12, 0.60, 0.12, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.18, 0.80, 0.18, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.25, 0.95, 0.25, 1.00)
end

function FHA_ApplyBlueStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.05, 0.05, 0.12, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.10, 0.10, 0.50, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.15, 0.15, 0.75, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.12, 0.12, 0.60, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.18, 0.18, 0.80, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.25, 0.25, 0.95, 1.00)
end

function FHA_ApplyOrangeStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.12, 0.07, 0.03, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.80, 0.40, 0.10, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(1.00, 0.50, 0.15, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.90, 0.45, 0.12, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(1.00, 0.55, 0.20, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(1.00, 0.65, 0.30, 1.00)
end

function FHA_ApplyYellowStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.12, 0.12, 0.03, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.80, 0.80, 0.10, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(1.00, 1.00, 0.15, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.90, 0.90, 0.12, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(1.00, 1.00, 0.20, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(1.00, 1.00, 0.30, 1.00)
end

function FHA_ApplyCyanStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.03, 0.10, 0.12, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.10, 0.70, 0.80, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.15, 0.85, 1.00, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.12, 0.75, 0.85, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.18, 0.85, 0.95, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.25, 0.95, 1.00, 1.00)
end

function FHA_ApplyPurpleStyle()
    local style = imgui.GetStyle()
    local c = style.Colors
    style.WindowRounding = 8
    style.FrameRounding = 6
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.10, 0.05, 0.12, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.50, 0.10, 0.60, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.65, 0.15, 0.75, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(0.60, 0.12, 0.70, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.70, 0.18, 0.80, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.80, 0.25, 0.90, 1.00)
end

function FHA_ApplyRainbowStyle()
    local style = imgui.GetStyle()
    style.WindowRounding = 8
    style.FrameRounding = 6
    
    local timeElapsed = os.clock()
    local r = (math.sin(timeElapsed * 2.0) + 1.0) * 0.5
    local g = (math.sin(timeElapsed * 2.0 + math.pi/3) + 1.0) * 0.5
    local b = (math.sin(timeElapsed * 2.0 + 2*math.pi/3) + 1.0) * 0.5
    
    local c = style.Colors
    c[imgui.Col.WindowBg] = imgui.ImVec4(r * 0.1, g * 0.1, b * 0.1, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(r * 0.5, g * 0.5, b * 0.5, 1.00)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(r * 0.7, g * 0.7, b * 0.7, 1.00)
    c[imgui.Col.Button] = imgui.ImVec4(r * 0.6, g * 0.6, b * 0.6, 1.00)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(r * 0.8, g * 0.8, b * 0.8, 1.00)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(r, g, b, 1.00)
end

-- ===== ГЛОБАЛЬНОЕ СОСТОЯНИЕ =====
FHA.state = {
    showMenu = imgui.ImBool(false),
    selectedTab = 1,
    styleApplied = false,
    lastSendTime = 0,
    cooldown = 1.0,
    fastCodes = {
        o="Ожидайте",y="Уточните",go="Уже иду",hel="Помог",sg="Свободная группа",
        non="Нет в сети",per="Передам",otk="Отказ",rp="РП путём",s="Слежу"
    },
    
    adminLevel = imgui.ImInt(1),
    gender = imgui.ImInt(0),
    
    invisEnabled = imgui.ImBool(false),
    invisActive = false,
    
    airbrakeEnabled = imgui.ImBool(false),
    airbrakeActive = false,
    airbrakeSpeed = imgui.ImFloat(0.25),
    
    tracerEnabled = imgui.ImBool(false),
    tracerDrawMyBullets = imgui.ImBool(false),
    tracerDrawBullets = imgui.ImBool(false),
    tracerCbEndMy = imgui.ImBool(false),
    tracerCbEnd = imgui.ImBool(false),
    tracerShowPlayerInfo = imgui.ImBool(false),
    tracerOnlyId = imgui.ImBool(false),
    tracerOnlyNick = imgui.ImBool(false),
    
    tracerTimeRenderMyBullets = imgui.ImInt(10),
    tracerTimeRenderBullets = imgui.ImInt(10),
    tracerSizeOffMyLine = imgui.ImInt(1),
    tracerSizeOffLine = imgui.ImInt(0),
    tracerSizeOffMyPolygonEnd = imgui.ImInt(1),
    tracerSizeOffPolygonEnd = imgui.ImInt(1),
    tracerRotationMyPolygonEnd = imgui.ImInt(10),
    tracerRotationPolygonEnd = imgui.ImInt(10),
    tracerDegreeMyPolygonEnd = imgui.ImInt(50),
    tracerDegreePolygonEnd = imgui.ImInt(50),
    tracerMaxLineMyLimit = imgui.ImInt(30),
    tracerMaxLineLimit = imgui.ImInt(30),
    
    tracerStaticObjectMy = imgui.ImFloat4(1.0, 0.0, 0.0, 1.0),
    tracerDinamicObjectMy = imgui.ImFloat4(1.0, 1.0, 0.0, 1.0),
    tracerPedPMy = imgui.ImFloat4(0.0, 1.0, 0.0, 1.0),
    tracerCarPMy = imgui.ImFloat4(0.0, 0.0, 1.0, 1.0),
    tracerStaticObject = imgui.ImFloat4(1.0, 0.0, 0.0, 1.0),
    tracerDinamicObject = imgui.ImFloat4(1.0, 1.0, 0.0, 1.0),
    tracerPedP = imgui.ImFloat4(0.0, 1.0, 0.0, 1.0),
    tracerCarP = imgui.ImFloat4(0.0, 0.0, 1.0, 1.0),
    tracerColorPlayerI = imgui.ImFloat4(1.0, 1.0, 1.0, 1.0),
    
    bulletSync = {lastId = 0, maxLines = 30},
    bulletSyncMy = {lastId = 0, maxLines = 30},
    
    clickWarpEnabled = imgui.ImBool(false),
    cursorEnabled = false,
    pointMarker = nil,
    clickWarpFont = nil,
    clickWarpFont2 = nil,
    
    autoWish = imgui.ImBool(false),
    paydayTriggered = false,
    
    lastAutoAction = 0,
    
    fractions = {
        {id = 1, name = u8"LSPD"},
        {id = 2, name = u8"FBI"},
        {id = 3, name = u8"Army LS"},
        {id = 4, name = u8"MCLS"},
        {id = 5, name = u8"LCN"},
        {id = 6, name = u8"Yakuza"},
        {id = 7, name = u8"Marya"},
        {id = 12, name = u8"Ballas"},
        {id = 13, name = u8"Vagos"},
        {id = 14, name = u8"Russia Mafia"},
        {id = 15, name = u8"Grove"},
        {id = 16, name = u8"SMI"},
        {id = 17, name = u8"Aztec"},
        {id = 18, name = u8"Rifa"},
        {id = 23, name = u8"Xitman"},
        {id = 25, name = u8"SWAT"},
        {id = 26, name = u8"AP"},
        {id = 27, name = u8"RCPD"},
        {id = 28, name = u8"Outlaws MC"},
        {id = 29, name = u8"BC"}
    },
    
    autoEnable = imgui.ImBool(false),
    autoAgm = imgui.ImBool(false),
    autoChatsms = imgui.ImBool(false),
    autoChat = imgui.ImBool(false),
    autoTogphone = imgui.ImBool(false),
    autoOffgoto = imgui.ImBool(false),

    speedhackEnabled = imgui.ImBool(false),
    speedhackKey = imgui.ImBuffer("Left Alt", 64),
    speedhackActive = false,
    
    FLOOD_DELAY = 1200,
    MSK_OFFSET = 3*3600,
    active_razd = false,
    active_razd2 = false,
    antiFlood = false,
    razdLocked = false,
    timer = 0,
    timerr = 0,
    razd_player_id = -1,
    text_word = imgui.ImBuffer(64),
    text_real = imgui.ImBuffer(64),
    arr_chat = {'aad','o'},
    combo_chat = imgui.ImInt(0),
    arr_priz = {
        u8'Уровень',u8'Законопослушность',u8'Материалы',u8'Убийства',
        u8'Номер телефона',u8'EXP',u8'Деньги в банке',
        u8'Деньги на мобиле',u8'Наличные деньги',u8'Аптечки',
        u8'Бокс',u8'Kung-Fu',u8'KickBox',u8'Наркозависимость',u8'Наркотики'
    },
    prizStatId = {1,2,3,4,5,6,7,8,9,10,12,13,14,15,16},
    combo_priz = imgui.ImInt(0),
    guiLog = {},
    
    mp_names = {
        u8"Король Дигла",
        u8"Русская Рулетка",
        u8"Поливалка",
        u8"Дерби",
        u8"Снайпер",
        u8"Paint-Ball",
        u8"Бой на Катанах"
    },
    combo_mp_name = imgui.ImInt(0),
    mp_custom_name = imgui.ImBuffer(64),
    
    mp_prize_text = imgui.ImBuffer(256),
    
    otbor_leader_name = imgui.ImBuffer(64),
    otbor_chat = imgui.ImInt(1),
    otborRunning = false,
    otborPrefixSent = false,
    otbor_selectLeader = imgui.ImInt(0),
    mp_selectEvent = imgui.ImInt(0),
    otbor_leader_combo = imgui.ImInt(0),
    
    menuColor = imgui.ImInt(6),
    
    showTracerSettings = imgui.ImBool(false),
    startAutoMpFlag = false,
    startAutoOtborFlag = false,
    startRazdachaFlag = false,
    saveSettingsFlag = false,
    
    customWindowSize = false,
    defaultWindowSize = imgui.ImVec2(900, 550),
    currentWindowSize = imgui.ImVec2(900, 680),

    shouldFocusMenu = false,
    
    razdTimeout = 0,
    razdInProgress = false,
    
    gmCarEnabled = imgui.ImBool(false),

    -- === ZZVEH ПЕРЕМЕННЫЕ ===
    zzvehEnabled = imgui.ImBool(false),
    zzvehId = 0,
    zzvehC1 = 0,
    zzvehC2 = 0,
    zzvehActive = false,
    zzvehTime = 0,
    zzvehCar = "",
    zzvehAct = false,
    -- === КОНЕЦ ZZVEH ===

    razdStartTime = 0,
    razdWord = "",
    razdPrizeName = "",
    razdPrizeAmount = 0,
    razdIsStyle = false,
    
    gz_initialized = false,
    gz_zones = {},
    gz_selectedZone = -1,
    gz_undoState = {},
    gz_showConfirm = false,
    gz_autoReform = {
        active = false,
        paused = false,
        savedPosition = nil,
        currentIndex = 1,
    },
    gz_lastUpdate = 0,
    gz_lastCapCheck = 0,
    gz_capZoneId = nil,
    gz_capAttacker = nil,
    
    autoDialogOpen = false,
    autoDialogClosedTime = 0,
    autoWaitingForClose = false,
    autoExecutingCommands = false,
    autoCommandsSent = 0,
    autoLastCommandTime = 0,
    autoDelayBeforeCheck = 3500,
    autoDelayBetweenCommands = 1050,
    autoLastDialogId = nil,
}

-- ===== GHETTO PAINTER DATA =====
local bit = require("bit")

ffi.cdef([[
    struct stGangzone { float fPosition[4]; uint32_t dwColor; uint32_t dwAltColor; };
    struct stGangzonePool { struct stGangzone *pGangzone[1024]; int iIsListed[1024]; };
]])

local gangZones = {
    ballas = {
        name = "Ballas",
        colorCode = 12,
        displayColor = {0.8, 0.2, 0.8, 1.0},
        zones = {1, 2, 3, 13, 14, 15, 16, 17, 18, 29, 103, 104, 105, 111, 112, 114, 115, 116, 122, 123, 124, 125, 126, 127, 128}
    },
    vagos = {
        name = "Vagos",
        colorCode = 13,
        displayColor = {1.0, 0.8, 0.0, 1.0},
        zones = {0, 4, 9, 10, 11, 12, 19, 20, 21, 30, 31, 41, 106, 107, 108, 109, 110, 117, 118, 119, 121, 129, 130, 131, 132}
    },
    grove = {
        name = "Grove",
        colorCode = 15,
        displayColor = {0.2, 0.8, 0.2, 1.0},
        zones = {22, 23, 24, 25, 32, 33, 34, 35, 36, 42, 43, 45, 46, 52, 53, 54, 55, 56, 64, 65, 66, 67, 76, 77, 78}
    },
    rifa = {
        name = "Rifa",
        colorCode = 18,
        displayColor = {0.2, 0.4, 0.8, 1.0},
        zones = {26, 27, 28, 37, 38, 39, 40, 47, 48, 49, 50, 51, 57, 58, 59, 60, 61, 62, 68, 70, 71, 79, 80, 81, 82}
    },
    aztec = {
        name = "Aztec",
        colorCode = 17,
        displayColor = {0.2, 0.7, 0.9, 1.0},
        zones = {5, 6, 7, 8, 63, 74, 75, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101}
    },
    neutral = {
        name = "Neutral",
        colorCode = 1,
        displayColor = {1.0, 1.0, 1.0, 1.0},
        zones = {44, 69, 72, 73, 83, 84, 102, 113, 120}
    }
}

local zoneGridOrder = {
    {122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132},
    {111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121},
    {3, 1, 2, 103, 104, 105, 106, 107, 108, 109, 110},
    {18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 4},
    {29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19},
    {40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30},
    {51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41},
    {62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52},
    {73, 72, 71, 70, 69, 68, 67, 66, 65, 64, 63},
    {84, 83, 82, 81, 80, 79, 78, 77, 76, 75, 74},
    {95, 94, 93, 92, 91, 90, 89, 88, 87, 86, 85},
    {102, 5, 6, 7, 8, 101, 100, 99, 98, 97, 96}
}

local autoReformOrder = {"ballas", "vagos", "grove", "rifa", "aztec", "neutral"}

local allReformZones = {}
for _, gangName in ipairs(autoReformOrder) do
    local gang = gangZones[gangName]
    if gang then
        for _, zoneId in ipairs(gang.zones) do
            table.insert(allReformZones, {gang = gangName, zoneId = zoneId, colorCode = gang.colorCode, name = gang.name})
        end
    end
end

-- Ghetto Painter functions
local function GZ_getGangzonePoolSafe()
    local poolPtr = sampGetGangzonePoolPtr()
    if poolPtr == 0 or poolPtr == nil then return nil end
    local success, pool = pcall(function() return ffi.cast("struct stGangzonePool*", poolPtr) end)
    if not success or pool == nil then return nil end
    return pool
end

local function GZ_getGangByRealColor(r, g, b)
    if r > 200 and g > 200 and b > 200 then return "neutral" end
    if r > 200 and b > 200 and g < 50 then return "ballas" end
    if r > 200 and g > 80 and g < 180 and b < 50 then return "rifa" end
    if g > 150 and r < 50 and b < 50 then return "grove" end
    if b > 150 and g > 150 and r < 50 then return "vagos" end
    if r > 150 and g > 150 and b < 50 then return "aztec" end
    if b > 200 and g > 150 then return "vagos" end
    return "neutral"
end

local function GZ_getDisplayColor(gangName)
    if gangZones[gangName] then return gangZones[gangName].displayColor[1], gangZones[gangName].displayColor[2], gangZones[gangName].displayColor[3] end
    return 1.0, 1.0, 1.0
end

local function GZ_getDisplayName(gangName)
    if gangZones[gangName] then return gangZones[gangName].name end
    return "Unknown"
end

local function GZ_getZoneById(zoneId)
    for _, zone in ipairs(FHA.state.gz_zones) do
        if zone.id == zoneId then return zone end
    end
    return nil
end

local function GZ_getAllGangZones()
    local zones = {}
    local pool = GZ_getGangzonePoolSafe()
    if not pool then return zones end
    for zoneId = 0, 200 do
        if pool.iIsListed and pool.iIsListed[zoneId] and pool.iIsListed[zoneId] ~= 0 then
            local zone = pool.pGangzone[zoneId]
            if zone and zone ~= nil then
                local centerX = (zone.fPosition[0] + zone.fPosition[2]) / 2
                local centerY = (zone.fPosition[1] + zone.fPosition[3]) / 2
                local groundZ = getGroundZFor3dCoord(centerX, centerY)
                local rgb = zone.dwColor
                local r = bit.band(bit.rshift(rgb, 16), 255)
                local g = bit.band(bit.rshift(rgb, 8), 255)
                local b = bit.band(rgb, 255)
                local realGang = GZ_getGangByRealColor(r, g, b)
                table.insert(zones, {id = zoneId, colorRGB = zone.dwColor, altColor = zone.dwAltColor, isEmpty = false, gang = realGang, pos = {x = centerX, y = centerY, z = groundZ > 0 and groundZ or 20.0}})
            end
        end
    end
    return zones
end

local function GZ_isZoneUnderCapture(zoneId)
    local zone = GZ_getZoneById(zoneId)
    if not zone or zone.isEmpty then return false end
    if zone.altColor and zone.altColor ~= 0 and zone.altColor ~= zone.colorRGB then
        local r1 = bit.band(bit.rshift(zone.colorRGB, 16), 255)
        local g1 = bit.band(bit.rshift(zone.colorRGB, 8), 255)
        local b1 = bit.band(zone.colorRGB, 255)
        local r2 = bit.band(bit.rshift(zone.altColor, 16), 255)
        local g2 = bit.band(bit.rshift(zone.altColor, 8), 255)
        local b2 = bit.band(zone.altColor, 255)
        return GZ_getGangByRealColor(r1, g1, b1) ~= GZ_getGangByRealColor(r2, g2, b2)
    end
    return false
end

local function GZ_getZoneAttacker(zoneId)
    local zone = GZ_getZoneById(zoneId)
    if not zone or zone.isEmpty then return nil end
    if zone.altColor and zone.altColor ~= 0 then
        local r2 = bit.band(bit.rshift(zone.altColor, 16), 255)
        local g2 = bit.band(bit.rshift(zone.altColor, 8), 255)
        local b2 = bit.band(zone.altColor, 255)
        return GZ_getGangByRealColor(r2, g2, b2)
    end
    return nil
end

local function GZ_teleportToZone(zoneId)
    local pool = GZ_getGangzonePoolSafe()
    if not pool then return false end
    if pool.iIsListed and zoneId >= 0 and zoneId < 1024 and pool.iIsListed[zoneId] ~= 0 then
        local zone = pool.pGangzone[zoneId]
        if zone then
            local cx = (zone.fPosition[0] + zone.fPosition[2]) / 2
            local cy = (zone.fPosition[1] + zone.fPosition[3]) / 2
            local cz = getGroundZFor3dCoord(cx, cy)
            if cz <= 0 then cz = 20.0 end
            setCharCoordinates(PLAYER_PED, cx, cy, cz + 2)
            return true
        end
    end
    return false
end

local function GZ_saveUndoState()
    FHA.state.gz_undoState = {}
    local pool = GZ_getGangzonePoolSafe()
    if not pool then return end
    for _, item in ipairs(allReformZones) do
        local zoneId = item.zoneId
        if pool.iIsListed and pool.iIsListed[zoneId] and pool.iIsListed[zoneId] ~= 0 then
            local zone = pool.pGangzone[zoneId]
            if zone then
                local rgb = zone.dwColor
                local r = bit.band(bit.rshift(rgb, 16), 255)
                local g = bit.band(bit.rshift(rgb, 8), 255)
                local b = bit.band(rgb, 255)
                local gangName = GZ_getGangByRealColor(r, g, b)
                local colorCode = gangZones[gangName] and gangZones[gangName].colorCode or 1
                FHA.state.gz_undoState[zoneId] = colorCode
            end
        end
    end
end

local function GZ_paintZoneWithReturn(zoneId, colorCode, colorName)
    local x, y, z = getCharCoordinates(PLAYER_PED)
    if GZ_teleportToZone(zoneId) then
        wait(200)
        sampSendChat(string.format("/gzcolor %d", colorCode))
        sampAddChatMessage(string.format("{33FF33}[GZ] Zone %d -> %s", zoneId, colorName), -1)
        wait(400)
        setCharCoordinates(PLAYER_PED, x, y, z + 1)
    end
end

local function GZ_undoReform()
    if next(FHA.state.gz_undoState) == nil then 
        sampAddChatMessage("{FF4444}[GZ] Nothing to restore!", -1) 
        return 
    end
    if FHA.state.gz_autoReform.active then 
        sampAddChatMessage("{FF4444}[GZ] Stop reform first!", -1) 
        return 
    end
    sampAddChatMessage("{33FF33}[GZ] === UNDO: RESTORING ZONES ===", -1)
    local x, y, z = getCharCoordinates(PLAYER_PED)
    local restored = 0
    for zoneId, savedColorCode in pairs(FHA.state.gz_undoState) do
        local pool = GZ_getGangzonePoolSafe()
        if pool and pool.iIsListed and pool.iIsListed[zoneId] and pool.iIsListed[zoneId] ~= 0 then
            local zone = pool.pGangzone[zoneId]
            if zone then
                local rgb = zone.dwColor
                local r = bit.band(bit.rshift(rgb, 16), 255)
                local g = bit.band(bit.rshift(rgb, 8), 255)
                local b = bit.band(rgb, 255)
                local currentGang = GZ_getGangByRealColor(r, g, b)
                local currentCode = gangZones[currentGang] and gangZones[currentGang].colorCode or 0
                if currentCode ~= savedColorCode then
                    local cx = (zone.fPosition[0] + zone.fPosition[2]) / 2
                    local cy = (zone.fPosition[1] + zone.fPosition[3]) / 2
                    local cz = getGroundZFor3dCoord(cx, cy)
                    if cz <= 0 then cz = 20.0 end
                    setCharCoordinates(PLAYER_PED, cx, cy, cz + 2)
                    wait(200)
                    sampSendChat(string.format("/gzcolor %d", savedColorCode))
                    restored = restored + 1
                    wait(400)
                end
            end
        end
    end
    setCharCoordinates(PLAYER_PED, x, y, z + 1)
    sampAddChatMessage(string.format("{33FF33}[GZ] UNDO done! Restored %d zones", restored), -1)
    FHA.state.gz_zones = GZ_getAllGangZones()
end

local function GZ_autoReformLoop()
    local total = #allReformZones
    local painted = 0
    local checked = 0
    GZ_saveUndoState()
    for i = FHA.state.gz_autoReform.currentIndex, total do
        if not FHA.state.gz_autoReform.active then break end
        while FHA.state.gz_autoReform.paused and FHA.state.gz_autoReform.active do wait(200) end
        if not FHA.state.gz_autoReform.active then break end
        local item = allReformZones[i]
        local zoneId = item.zoneId
        local expectedColorCode = item.colorCode
        local gangName = item.name
        local pool = GZ_getGangzonePoolSafe()
        if pool and pool.iIsListed and pool.iIsListed[zoneId] and pool.iIsListed[zoneId] ~= 0 then
            local zone = pool.pGangzone[zoneId]
            if zone then
                checked = checked + 1
                local rgb = zone.dwColor
                local r = bit.band(bit.rshift(rgb, 16), 255)
                local g = bit.band(bit.rshift(rgb, 8), 255)
                local b = bit.band(rgb, 255)
                local currentGang = GZ_getGangByRealColor(r, g, b)
                local currentCode = gangZones[currentGang] and gangZones[currentGang].colorCode or 0
                if currentCode ~= expectedColorCode then
                    sampAddChatMessage(string.format("{33CCFF}[GZ] [%d/%d] Zone %d: %s -> %s", i, total, zoneId, GZ_getDisplayName(currentGang), gangName), -1)
                    local cx = (zone.fPosition[0] + zone.fPosition[2]) / 2
                    local cy = (zone.fPosition[1] + zone.fPosition[3]) / 2
                    local cz = getGroundZFor3dCoord(cx, cy)
                    if cz <= 0 then cz = 20.0 end
                    setCharCoordinates(PLAYER_PED, cx, cy, cz + 2)
                    wait(200)
                    sampSendChat(string.format("/gzcolor %d", expectedColorCode))
                    painted = painted + 1
                    wait(300)
                end
            end
        end
        FHA.state.gz_autoReform.currentIndex = i + 1
        wait(500)
    end
    local status = FHA.state.gz_autoReform.active and "DONE" or "STOPPED"
    sampAddChatMessage(string.format("{33FF33}[GZ] === %s! Checked: %d | Painted: %d ===", status, checked, painted), -1)
    if FHA.state.gz_autoReform.savedPosition then
        wait(200)
        setCharCoordinates(PLAYER_PED, FHA.state.gz_autoReform.savedPosition.x, FHA.state.gz_autoReform.savedPosition.y, FHA.state.gz_autoReform.savedPosition.z + 1)
    end
    FHA.state.gz_autoReform.active = false
    FHA.state.gz_autoReform.paused = false
    FHA.state.gz_zones = GZ_getAllGangZones()
end

local function GZ_startAutoReform()
    if FHA.state.gz_autoReform.active then
        if FHA.state.gz_autoReform.paused then 
            sampAddChatMessage("{FFCC00}[GZ] Paused! Use Pause button to resume", -1)
        else 
            sampAddChatMessage("{FF4444}[GZ] Already running!", -1) 
        end
        return    end
    FHA.state.gz_showConfirm = false
    local x, y, z = getCharCoordinates(PLAYER_PED)
    FHA.state.gz_autoReform.savedPosition = {x = x, y = y, z = z}
    FHA.state.gz_autoReform.currentIndex = 1
    FHA.state.gz_autoReform.active = true
    FHA.state.gz_autoReform.paused = false
    sampAddChatMessage(string.format("{33FF33}[GZ] === START: %d zones ===", #allReformZones), -1)
    lua_thread.create(GZ_autoReformLoop)
end

local function GZ_pauseAutoReform()
    if not FHA.state.gz_autoReform.active then 
        sampAddChatMessage("{FF4444}[GZ] Not running", -1) 
        return 
    end
    FHA.state.gz_autoReform.paused = not FHA.state.gz_autoReform.paused
    sampAddChatMessage(FHA.state.gz_autoReform.paused and "{FFCC00}[GZ] PAUSED" or "{33FF33}[GZ] RESUMED", -1)
end

local function GZ_stopAutoReform()
    if not FHA.state.gz_autoReform.active then 
        sampAddChatMessage("{FF4444}[GZ] Not running", -1) 
        return 
    end
    FHA.state.gz_autoReform.active = false
    FHA.state.gz_autoReform.paused = false
    sampAddChatMessage("{FF4444}[GZ] Stopped! Use UNDO to restore", -1)
end

local function GZ_updateCapStatus()
    for _, zone in ipairs(FHA.state.gz_zones) do
        if not zone.isEmpty and zone.altColor and zone.altColor ~= 0 and zone.altColor ~= zone.colorRGB then
            local r1 = bit.band(bit.rshift(zone.colorRGB, 16), 255)
            local g1 = bit.band(bit.rshift(zone.colorRGB, 8), 255)
            local b1 = bit.band(zone.colorRGB, 255)
            local r2 = bit.band(bit.rshift(zone.altColor, 16), 255)
            local g2 = bit.band(bit.rshift(zone.altColor, 8), 255)
            local b2 = bit.band(zone.altColor, 255)
            if GZ_getGangByRealColor(r1, g1, b1) ~= GZ_getGangByRealColor(r2, g2, b2) then
                FHA.state.gz_capZoneId = zone.id
                FHA.state.gz_capAttacker = GZ_getGangByRealColor(r2, g2, b2)
                return
            end
        end
    end
    FHA.state.gz_capZoneId = nil
    FHA.state.gz_capAttacker = nil
end

-- ===== ФУНКЦИИ ВИЗУАЛЬНОЙ ПОЧИНКИ МАШИНЫ =====
function fixCarDoor(car, door)
    if doesVehicleExist(car) then
        local carPtr = getCarPointer(car)
        if carPtr and carPtr ~= 0 then
            local doorOffset = 0x5B4
            local doorFlags = readMemory(carPtr + doorOffset, 4, false)
            doorFlags = bit.band(doorFlags, bit.bnot(bit.lshift(1, door)))
            writeMemory(carPtr + doorOffset, 4, doorFlags, false)
        end
    end
end

function fixCarPanel(car, panel)
    if doesVehicleExist(car) then
        local carPtr = getCarPointer(car)
        if carPtr and carPtr ~= 0 then
            local panelOffset = 0x5A4
            local panelFlags = readMemory(carPtr + panelOffset, 4, false)
            panelFlags = bit.band(panelFlags, bit.bnot(bit.lshift(1, panel)))
            writeMemory(carPtr + panelOffset, 4, panelFlags, false)
        end
    end
end

-- ===== GM CAR ПОТОК =====
function FHA_gmCarThread()
    local st = FHA.state
    while not FHA.isUnloading do
        wait(10)
        if st.gmCarEnabled.v and isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            if doesVehicleExist(car) then
                local carPtr = getCarPointer(car)
                if carPtr and carPtr ~= 0 then
                    setCarHealth(car, 1000)
                    setCarProofs(car, true, true, true, true, true)
                    writeMemory(carPtr + 0x5B8, 4, 1000, false)
                    writeMemory(carPtr + 0x5B0, 4, 1, false)
                    writeMemory(carPtr + 0x5A4, 4, 0, false)
                    writeMemory(carPtr + 0x5B4, 4, 0, false)
                    writeMemory(carPtr + 0x5A0, 4, 0, false)
                    writeMemory(carPtr + 0x584, 1, 0, false)
                    
                    local vehicleFlags = readMemory(carPtr + 0x5AC, 4, false)
                    vehicleFlags = bit.band(vehicleFlags, bit.bnot(0x2C0))
                    writeMemory(carPtr + 0x5AC, 4, vehicleFlags, false)
                    
                    for i = 0, 6 do
                        writeMemory(carPtr + 0x5A4 + (i * 4), 4, 0, false)
                    end
                    
                    for i = 0, 3 do
                        writeMemory(carPtr + 0x5C0 + i, 1, 0, false)
                    end
                    
                    for i = 0, 5 do
                        if doesVehicleExist(car) then
                            local carPtr2 = getCarPointer(car)
                            if carPtr2 and carPtr2 ~= 0 then
                                local doorOffset = 0x5B4
                                local doorFlags = readMemory(carPtr2 + doorOffset, 4, false)
                                doorFlags = bit.band(doorFlags, bit.bnot(bit.lshift(1, i)))
                                writeMemory(carPtr2 + doorOffset, 4, doorFlags, false)
                            end
                        end
                    end
                    
                    for i = 0, 6 do
                        if doesVehicleExist(car) then
                            local carPtr2 = getCarPointer(car)
                            if carPtr2 and carPtr2 ~= 0 then
                                local panelOffset = 0x5A4
                                local panelFlags = readMemory(carPtr2 + panelOffset, 4, false)
                                panelFlags = bit.band(panelFlags, bit.bnot(bit.lshift(1, i)))
                                writeMemory(carPtr2 + panelOffset, 4, panelFlags, false)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ===== SAMPEV ОБРАБОТЧИКИ =====
function sampev.onVehicleDamageStatusUpdate(vehicleid, playerid)
    local st = FHA.state
    if st.gmCarEnabled.v then
        if isCharInAnyCar(PLAYER_PED) then
            local myCar = storeCarCharIsInNoSave(PLAYER_PED)
            if myCar and vehicleid == myCar then
                return false
            end
        end
    end
end

function sampev.onPlayerDeathNotification(killerId, killedId, reason)
    killList.onDeath(killerId, killedId, reason)
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    local st = FHA.state
    local al = FHA.autoLogin
    
    if id == 2934 and al.enabled.v and al.password.v ~= "" and st.adminLevel.v >= 6 then
        sampSendDialogResponse(id, 1, 0, tostring(al.password.v))
        sampSendDialogResponse(id, 0, 0, "")
        return false
    end
    
    if not title then return end

    if st.mpAutoStep == 1 and title:find(u8:decode("Меню мероприятий")) then
        lua_thread.create(function()
            if FHA.isUnloading then return end
            wait(200)
            if FHA.isUnloading then return end
            sampSendDialogResponse(id, 1, 0, "")
            st.mpAutoStep = 0
        end)
    end

    if st.otborRunning and title:find(u8:decode("Меню мероприятий")) then
        lua_thread.create(function()
            if FHA.isUnloading then return end
            wait(200)
            if FHA.isUnloading then return end
            sampSendDialogResponse(id, 1, 0, "")
            st.otborRunning = false
        end)
    end

    if st.autoEnable.v and st.adminLevel.v >= 6 then
        st.autoLastDialogId = id
        if id == 2934 then
            st.autoDialogOpen = true
            st.autoDialogClosedTime = os.clock() * 1000
            st.autoWaitingForClose = true
            st.autoExecutingCommands = false
            st.autoCommandsSent = 0
        else
            st.autoDialogOpen = false
            st.autoWaitingForClose = false
            st.autoExecutingCommands = false
            st.autoCommandsSent = 0
        end
    end
end

function sampev.onSendBulletSync(data)
    FHA_onSendBulletSync(data)
end

function sampev.onBulletSync(playerid, data)
    FHA_onBulletSync(playerid, data)
end

function sampev.onSendPlayerSync(data)
    local st = FHA.state
    if st.invisEnabled.v and st.adminLevel.v >= 6 and st.invisActive then
        local var_3_0 = samp_create_sync_data("spectator")
        var_3_0.position = data.position
        var_3_0.send()
        return false
    end
end

-- ===== ОСНОВНОЙ ОБРАБОТЧИК СООБЩЕНИЙ =====
function sampev.onServerMessage(color, text)
    -- === ПЕРЕХВАТ /VEH ДЛЯ ZZVEH ===
    local st = FHA.state
    
    -- Убираем цветовые коды
    local rawText = text:gsub("{%x%x%x%x%x%x}", "")
    
    -- Проверяем команду /veh (3 параметра: id, c1, c2)
    if rawText:find("^/veh%s(%d+)%s(%d+)%s(%d+)") and not st.zzvehAct and st.zzvehEnabled.v and st.adminLevel.v >= 6 then
        -- Сохраняем параметры как в GrandTools
        st.zzvehId, st.zzvehC1, st.zzvehC2 = rawText:match("^/veh%s(%d+)%s(%d+)%s(%d+)")
        st.zzvehActive = true
        st.zzvehTime = os.time()
        st.zzvehCar = rawText
        
        -- Запускаем создание
        FHA_createCarInZZ()
        
        -- Не показываем команду в чате
        return false
    end
    
    -- Проверяем выход из зоны (как в GrandTools)
    if rawText:find("Вы покинули зелёную зону") or rawText:find("Вы покинули зону") then
        if st.zzvehActive and st.zzvehEnabled.v and st.adminLevel.v >= 6 then
            -- Если машина ещё не создалась, создаём при выходе
            if not st.zzvehAct then
                FHA_createCarInZZ()
            end
            return false
        end
    end
    -- === КОНЕЦ ПЕРЕХВАТА ===
    
    -- Обработка для Admin Render
    if adminRender.onServerMessage(color, text) then
        return false
    end
    
    local cleanText = FHA_removeColorCodes(text)
    local state = FHA.state
    
    if state.autoWish.v then
        if cleanText:find("БАНКОВСКИЙ ЧЕК") then
            if not state.paydayTriggered then
                state.paydayTriggered = true
                lua_thread.create(function()
                    if FHA.isUnloading then return end
                    wait(500)
                    if FHA.isUnloading then return end
                    sampSendChat("/gg")
                end)
            end
        elseif not cleanText:find("БАНКОВСКИЙ ЧЕК") then
            state.paydayTriggered = false
        end
    end

    local nick, id, msg
    
    nick, id, msg = cleanText:match("Репорт от (.+)%[(%d+)%]: (.+)")
    
    if not nick then
        nick, id, msg = cleanText:match("Репорт от (.+) %((%d+)%)%: (.+)")
    end
    
    if not nick then
        nick, id, msg = cleanText:match("%[REPORT%] (.+)%[(%d+)%]: (.+)")
    end
    
    if nick and id and msg then
        nick = nick:gsub("^%s*(.-)%s*$", "%1")
        msg = msg:gsub("^%s*(.-)%s*$", "%1")
        
        FHA_addReport(nick, tonumber(id), msg)
    end

    if state.active_razd and not state.active_razd2 and state.text_word.v ~= "" then
        local _, pid2, msg2 = text:match('Репорт от (.*)%[(%d+)%]: %{FFFFFF%}(.*)')
        if msg2 then
            local repWord = msg2:match("^(%S+)")
            if repWord == u8:decode(state.text_word.v) then
                if sampIsPlayerConnected(tonumber(pid2)) then
                    state.razd_player_id = tonumber(pid2)
                    state.active_razd2 = true
                    sampAddChatMessage("{33FF33}[FastHelperAdm] Победитель найден! Выдача приза...", -1)
                else
                    sampAddChatMessage("{FF5555}[FastHelperAdm] Победитель вышел из игры, раздача отменена", -1)
                    FHA_resetRazdacha()
                end
            end
        end
    end
end

-- ===== ФУНКЦИИ ДЛЯ РАБОТЫ С ЦВЕТАМИ =====
function FHA_join_argb(r, g, b, a)
    a = a or 1.0
    local argb = math.floor(b * 255)
    argb = bit.bor(argb, bit.lshift(math.floor(g * 255), 8))
    argb = bit.bor(argb, bit.lshift(math.floor(r * 255), 16))
    argb = bit.bor(argb, bit.lshift(math.floor(a * 255), 24))
    return argb
end

function FHA_genderEnding(text)
    if FHA.state.gender.v == 1 then
        return text:gsub("%((.-)%)", "%1")
    end
    return text:gsub("%(.-%)", "")
end

function FHA_genderText(male, female)
    if FHA.state.gender.v == 1 then
        return female
    else
        return male
    end
end

function FHA_adminWord()
    if FHA.state.gender.v == 1 then
        return "Администраторши"
    else
        return "Администратора"
    end
end

FHA.templates = {
    pleasant_game = function()
        return FHA_genderText(
            "Приятной игры от Администратора <3",
            "Приятной игры от Администраторши <3"
        )
    end,

    pleasant_game_waiting = function()
        return FHA_genderText(
            "Ожидайте | Приятной игры от Администратора <3",
            "Ожидайте | Приятной игры от Администраторши <3"
        )
    end,

    clarify = function()
        return FHA_genderEnding(
            "Уточните ваш вопрос."
        )
    end,

    helped = function()
        return FHA_genderEnding(
            "Я помог(ла) вам. " .. FHA.templates.pleasant_game()
        )
    end,

    waiting = function()
        return FHA_genderEnding(
            "Ожидайте, я уже проверяю вашу ситуацию."
        )
    end,

    watching = function()
        return FHA_genderEnding(
            "Я слежу за вашей ситуацией."
        )
    end,

    transferred = function()
        return FHA_genderEnding(
            "Передаю ваш репорт старшей администрации."
        )
    end,

    spawn = function()
        return "Используйте /spawn для решения проблемы."
    end
}

function FHA_formatTime(sec)
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%d min %d sec", m, s)
end

function FHA_addReport(nick, id, msg)
    local cleanMsg = FHA_removeColorCodes(msg)
    local utf8Msg = u8(cleanMsg)
    
    if #FHA.reports >= FHA.MAX_REPORTS then
        table.remove(FHA.reports, 1)
        if FHA.selectedReport and FHA.selectedReport > #FHA.reports then
            FHA.selectedReport = nil
        end
    end

    table.insert(FHA.reports, {
        nick = nick,
        id = id,
        text = utf8Msg,
        time = os.time()
    })
end

function FHA_clearAllReports()
    FHA.reports = {}
    FHA.selectedReport = nil
    FHA.answerText.v = ""
end

function FHA_sendWithDelay(cmd1, cmd2, delayMs)
    delayMs = delayMs or 950
    sampSendChat(cmd1)
    if cmd2 then
        lua_thread.create(function()
            wait(delayMs)
            if not FHA.isUnloading then
                sampSendChat(cmd2)
            end
        end)
    end
end

function FHA_reportCleanupThread()
    while not FHA.isUnloading do
        wait(2000)
        if #FHA.reports > 0 then
            local i = 1
            while i <= #FHA.reports do
                if os.time() - FHA.reports[i].time >= FHA.REPORT_LIFETIME then
                    table.remove(FHA.reports, i)
                    if FHA.selectedReport then
                        if FHA.selectedReport > i then
                            FHA.selectedReport = FHA.selectedReport - 1
                        elseif FHA.selectedReport == i then
                            FHA.selectedReport = nil
                        end
                    end
                else
                    i = i + 1
                end
            end
        end
    end
end

function FHA_resetRazdacha()
    local st = FHA.state
    st.razdLocked = false
    st.active_razd = false
    st.active_razd2 = false
    st.antiFlood = false
    st.razd_player_id = -1
    st.startRazdachaFlag = false
    st.razdInProgress = false
    st.razdTimeout = 0
    st.timer = 0
    st.timerr = 0
end

function FHA_addGuiLog(text)
    local utf8Text = u8(text)
    table.insert(FHA.state.guiLog, 1, utf8Text)
    if #FHA.state.guiLog > 10 then
        table.remove(FHA.state.guiLog)
    end
end

function FHA_parseAmount(str)
    if not str or str == '' then return nil end
    str = str:lower()
    if not str:match('^%d+[kkk]*$') then return nil end
    
    local numStr = str:match('^(%d+)')
    local kCount = select(2, str:gsub('k', ''))
    
    local num = tonumber(numStr)
    if not num then return nil end
    
    local multiplier = 1
    if kCount > 0 then
        multiplier = 1000 ^ kCount
    end
    
    local result = num * multiplier
    
    if result > 1000000000 then
        return nil
    end
    
    return math.floor(result)
end

-- ===== CONFIG SAVE / LOAD =====
FHA.cfgFile = getWorkingDirectory().."\\config\\FastHelperAdm.ini"

function FHA_saveCfg()
    local st = FHA.state
    local al = FHA.autoLogin
    local f = io.open(FHA.cfgFile, "w")
    if not f then return end
    
    f:write("autoEnable="     .. (st.autoEnable.v and "1" or "0") .. "\n")
    f:write("autoAgm="        .. (st.autoAgm.v and "1" or "0") .. "\n")
    f:write("autoChatsms="    .. (st.autoChatsms.v and "1" or "0") .. "\n")
    f:write("autoChat="       .. (st.autoChat.v and "1" or "0") .. "\n")
    f:write("autoTogphone="   .. (st.autoTogphone.v and "1" or "0") .. "\n")
    f:write("autoOffgoto="    .. (st.autoOffgoto.v and "1" or "0") .. "\n")
    f:write("autoWish="       .. (st.autoWish.v and "1" or "0") .. "\n")
    f:write("adminLevel="     .. st.adminLevel.v .. "\n")
    f:write("gender="         .. st.gender.v .. "\n")
    f:write("menuColor="      .. st.menuColor.v .. "\n")
    f:write("tracerEnabled="  .. (st.tracerEnabled.v and "1" or "0") .. "\n")
    f:write("clickWarpEnabled=" .. (st.clickWarpEnabled.v and "1" or "0") .. "\n")
    f:write("invisEnabled="     .. (st.invisEnabled.v and "1" or "0") .. "\n")
    f:write("airbrakeEnabled="  .. (st.airbrakeEnabled.v and "1" or "0") .. "\n")
    f:write("airbrakeSpeed="    .. string.format("%.2f", st.airbrakeSpeed.v) .. "\n")
    f:write("showTracerSettings=" .. (st.showTracerSettings.v and "1" or "0") .. "\n")
    f:write("gmCarEnabled="     .. (st.gmCarEnabled.v and "1" or "0") .. "\n")
    f:write("speedhackEnabled=" .. (st.speedhackEnabled.v and "1" or "0") .. "\n")
    f:write("speedhackKey="    .. tostring(st.speedhackKey.v) .. "\n")
    
    f:write("tracerDrawMyBullets=" .. (st.tracerDrawMyBullets.v and "1" or "0") .. "\n")
    f:write("tracerDrawBullets=" .. (st.tracerDrawBullets.v and "1" or "0") .. "\n")
    f:write("tracerCbEndMy=" .. (st.tracerCbEndMy.v and "1" or "0") .. "\n")
    f:write("tracerCbEnd=" .. (st.tracerCbEnd.v and "1" or "0") .. "\n")
    f:write("tracerShowPlayerInfo=" .. (st.tracerShowPlayerInfo.v and "1" or "0") .. "\n")
    f:write("tracerOnlyId=" .. (st.tracerOnlyId.v and "1" or "0") .. "\n")
    f:write("tracerOnlyNick=" .. (st.tracerOnlyNick.v and "1" or "0") .. "\n")
    f:write("tracerTimeRenderMyBullets=" .. st.tracerTimeRenderMyBullets.v .. "\n")
    f:write("tracerTimeRenderBullets=" .. st.tracerTimeRenderBullets.v .. "\n")
    f:write("tracerSizeOffMyLine=" .. st.tracerSizeOffMyLine.v .. "\n")
    f:write("tracerSizeOffLine=" .. st.tracerSizeOffLine.v .. "\n")
    f:write("tracerSizeOffMyPolygonEnd=" .. st.tracerSizeOffMyPolygonEnd.v .. "\n")
    f:write("tracerSizeOffPolygonEnd=" .. st.tracerSizeOffPolygonEnd.v .. "\n")
    f:write("tracerRotationMyPolygonEnd=" .. st.tracerRotationMyPolygonEnd.v .. "\n")
    f:write("tracerRotationPolygonEnd=" .. st.tracerRotationPolygonEnd.v .. "\n")
    f:write("tracerDegreeMyPolygonEnd=" .. st.tracerDegreeMyPolygonEnd.v .. "\n")
    f:write("tracerDegreePolygonEnd=" .. st.tracerDegreePolygonEnd.v .. "\n")
    f:write("tracerMaxLineMyLimit=" .. st.tracerMaxLineMyLimit.v .. "\n")
    f:write("tracerMaxLineLimit=" .. st.tracerMaxLineLimit.v .. "\n")

    f:write("active_razd=" .. (st.active_razd and "1" or "0") .. "\n")
    f:write("active_razd2=" .. (st.active_razd2 and "1" or "0") .. "\n")
    f:write("antiFlood=" .. (st.antiFlood and "1" or "0") .. "\n")
    f:write("razdLocked=" .. (st.razdLocked and "1" or "0") .. "\n")
    f:write("razd_player_id=" .. st.razd_player_id .. "\n")
    f:write("text_word=" .. u8:decode(st.text_word.v) .. "\n")
    f:write("text_real=" .. u8:decode(st.text_real.v) .. "\n")
    f:write("combo_chat=" .. st.combo_chat.v .. "\n")
    f:write("combo_priz=" .. st.combo_priz.v .. "\n")

    f:write("tracerStaticObjectMyR=" .. string.format("%.3f", st.tracerStaticObjectMy.v[1]) .. "\n")
    f:write("tracerStaticObjectMyG=" .. string.format("%.3f", st.tracerStaticObjectMy.v[2]) .. "\n")
    f:write("tracerStaticObjectMyB=" .. string.format("%.3f", st.tracerStaticObjectMy.v[3]) .. "\n")
    f:write("tracerDinamicObjectMyR=" .. string.format("%.3f", st.tracerDinamicObjectMy.v[1]) .. "\n")
    f:write("tracerDinamicObjectMyG=" .. string.format("%.3f", st.tracerDinamicObjectMy.v[2]) .. "\n")
    f:write("tracerDinamicObjectMyB=" .. string.format("%.3f", st.tracerDinamicObjectMy.v[3]) .. "\n")
    f:write("tracerPedPMyR=" .. string.format("%.3f", st.tracerPedPMy.v[1]) .. "\n")
    f:write("tracerPedPMyG=" .. string.format("%.3f", st.tracerPedPMy.v[2]) .. "\n")
    f:write("tracerPedPMyB=" .. string.format("%.3f", st.tracerPedPMy.v[3]) .. "\n")
    f:write("tracerCarPMyR=" .. string.format("%.3f", st.tracerCarPMy.v[1]) .. "\n")
    f:write("tracerCarPMyG=" .. string.format("%.3f", st.tracerCarPMy.v[2]) .. "\n")
    f:write("tracerCarPMyB=" .. string.format("%.3f", st.tracerCarPMy.v[3]) .. "\n")
    f:write("tracerStaticObjectR=" .. string.format("%.3f", st.tracerStaticObject.v[1]) .. "\n")
    f:write("tracerStaticObjectG=" .. string.format("%.3f", st.tracerStaticObject.v[2]) .. "\n")
    f:write("tracerStaticObjectB=" .. string.format("%.3f", st.tracerStaticObject.v[3]) .. "\n")
    f:write("tracerDinamicObjectR=" .. string.format("%.3f", st.tracerDinamicObject.v[1]) .. "\n")
    f:write("tracerDinamicObjectG=" .. string.format("%.3f", st.tracerDinamicObject.v[2]) .. "\n")
    f:write("tracerDinamicObjectB=" .. string.format("%.3f", st.tracerDinamicObject.v[3]) .. "\n")
    f:write("tracerPedPR=" .. string.format("%.3f", st.tracerPedP.v[1]) .. "\n")
    f:write("tracerPedPG=" .. string.format("%.3f", st.tracerPedP.v[2]) .. "\n")
    f:write("tracerPedPB=" .. string.format("%.3f", st.tracerPedP.v[3]) .. "\n")
    f:write("tracerCarPR=" .. string.format("%.3f", st.tracerCarP.v[1]) .. "\n")
    f:write("tracerCarPG=" .. string.format("%.3f", st.tracerCarP.v[2]) .. "\n")
    f:write("tracerCarPB=" .. string.format("%.3f", st.tracerCarP.v[3]) .. "\n")
    f:write("tracerColorPlayerIR=" .. string.format("%.3f", st.tracerColorPlayerI.v[1]) .. "\n")
    f:write("tracerColorPlayerIG=" .. string.format("%.3f", st.tracerColorPlayerI.v[2]) .. "\n")
    f:write("tracerColorPlayerIB=" .. string.format("%.3f", st.tracerColorPlayerI.v[3]) .. "\n")
    
    f:write("autoLoginEnabled=" .. (al.enabled.v and "1" or "0") .. "\n")
    f:write("autoLoginPassword=" .. tostring(al.password.v) .. "\n")
    
    f:write("whEnabled=" .. (wh_settings.enabled and "1" or "0") .. "\n")
    f:write("whByNick=" .. (wh_settings.by_nick and "1" or "0") .. "\n")
    f:write("whBySkeleton=" .. (wh_settings.by_skeleton and "1" or "0") .. "\n")
    f:write("whShowOnScreenshot=" .. (wh_settings.show_on_screenshot and "1" or "0") .. "\n")
    
    f:write("killListEnabled=" .. (killList.enabled and "1" or "0") .. "\n")
    
    -- === СОХРАНЕНИЕ ZZVEH ===
    f:write("zzvehEnabled=" .. (st.zzvehEnabled.v and "1" or "0") .. "\n")
    -- === КОНЕЦ ZZVEH ===
    
    f:close()
end

function FHA_loadCfg()
    local st = FHA.state
    local al = FHA.autoLogin
    local f = io.open(FHA.cfgFile, "r")
    if not f then 
        FHA_saveCfg()
        return 
    end
    
    local function toBool(v)
        if v == nil then return false end
        if type(v) == "boolean" then return v end
        if type(v) == "number" then return v == 1 or v == true end
        if type(v) == "string" then return v == "1" or v == "true" end
        return false
    end
    
    for line in f:lines() do
        local k, v = line:match("^(%w+)=([%d.]+)$")
        if k and v then
            local numVal = tonumber(v)
            if k == "autoEnable" then st.autoEnable.v = toBool(numVal) end
            if k == "autoAgm" then st.autoAgm.v = toBool(numVal) end
            if k == "autoChatsms" then st.autoChatsms.v = toBool(numVal) end
            if k == "autoChat" then st.autoChat.v = toBool(numVal) end
            if k == "autoTogphone" then st.autoTogphone.v = toBool(numVal) end
            if k == "autoOffgoto" then st.autoOffgoto.v = toBool(numVal) end
            if k == "autoWish" then st.autoWish.v = toBool(numVal) end
            if k == "adminLevel" then st.adminLevel.v = tonumber(v) end
            if k == "gender" then st.gender.v = tonumber(v) end
            if k == "menuColor" then st.menuColor.v = tonumber(v) end
            if k == "tracerEnabled" then st.tracerEnabled.v = toBool(numVal) end
            if k == "clickWarpEnabled" then st.clickWarpEnabled.v = toBool(numVal) end
            if k == "invisEnabled" then st.invisEnabled.v = toBool(numVal) end
            if k == "airbrakeEnabled" then st.airbrakeEnabled.v = toBool(numVal) end
            if k == "airbrakeSpeed" then st.airbrakeSpeed.v = tonumber(v) or 0.25 end
            if k == "showTracerSettings" then st.showTracerSettings.v = toBool(numVal) end
            if k == "gmCarEnabled" then st.gmCarEnabled.v = toBool(numVal) end
            if k == "speedhackEnabled" then st.speedhackEnabled.v = toBool(numVal) end
            if k == "speedhackKey" then st.speedhackKey.v = v end
            
            if k == "tracerDrawMyBullets" then st.tracerDrawMyBullets.v = toBool(numVal) end
            if k == "tracerDrawBullets" then st.tracerDrawBullets.v = toBool(numVal) end
            if k == "tracerCbEndMy" then st.tracerCbEndMy.v = toBool(numVal) end
            if k == "tracerCbEnd" then st.tracerCbEnd.v = toBool(numVal) end
            if k == "tracerShowPlayerInfo" then st.tracerShowPlayerInfo.v = toBool(numVal) end
            if k == "tracerOnlyId" then st.tracerOnlyId.v = toBool(numVal) end
            if k == "tracerOnlyNick" then st.tracerOnlyNick.v = toBool(numVal) end
            if k == "tracerTimeRenderMyBullets" then st.tracerTimeRenderMyBullets.v = tonumber(v) end
            if k == "tracerTimeRenderBullets" then st.tracerTimeRenderBullets.v = tonumber(v) end
            if k == "tracerSizeOffMyLine" then st.tracerSizeOffMyLine.v = tonumber(v) end
            if k == "tracerSizeOffLine" then st.tracerSizeOffLine.v = tonumber(v) end
            if k == "tracerSizeOffMyPolygonEnd" then st.tracerSizeOffMyPolygonEnd.v = tonumber(v) end
            if k == "tracerSizeOffPolygonEnd" then st.tracerSizeOffPolygonEnd.v = tonumber(v) end
            if k == "tracerRotationMyPolygonEnd" then st.tracerRotationMyPolygonEnd.v = tonumber(v) end
            if k == "tracerRotationPolygonEnd" then st.tracerRotationPolygonEnd.v = tonumber(v) end
            if k == "tracerDegreeMyPolygonEnd" then st.tracerDegreeMyPolygonEnd.v = tonumber(v) end
            if k == "tracerDegreePolygonEnd" then st.tracerDegreePolygonEnd.v = tonumber(v) end
            if k == "tracerMaxLineMyLimit" then st.tracerMaxLineMyLimit.v = tonumber(v) end
            if k == "tracerMaxLineLimit" then st.tracerMaxLineLimit.v = tonumber(v) end

            if k == "active_razd" then st.active_razd = toBool(numVal) end
            if k == "active_razd2" then st.active_razd2 = toBool(numVal) end
            if k == "antiFlood" then st.antiFlood = toBool(numVal) end
            if k == "razdLocked" then st.razdLocked = toBool(numVal) end
            if k == "razd_player_id" then st.razd_player_id = tonumber(v) end
            
            if k == "autoLoginEnabled" then al.enabled.v = toBool(numVal) end
            
            if k == "whEnabled" then wh_settings.enabled = toBool(numVal) end
            if k == "whByNick" then wh_settings.by_nick = toBool(numVal) end
            if k == "whBySkeleton" then wh_settings.by_skeleton = toBool(numVal) end
            if k == "whShowOnScreenshot" then wh_settings.show_on_screenshot = toBool(numVal) end
            
            if k == "killListEnabled" then 
                killList.enabled = toBool(numVal)
                if killList.enabled then
                    killList.saveOriginalNames()
                end
            end
            
            -- === ЗАГРУЗКА ZZVEH ===
            if k == "zzvehEnabled" then st.zzvehEnabled.v = toBool(numVal) end
            -- === КОНЕЦ ZZVEH ===
        end
        
        local k2, v2 = line:match("^(%w+[RGB])=([%d.]+)$")
        if k2 and v2 then
            local value = tonumber(v2)
            if k2 == "tracerStaticObjectMyR" then st.tracerStaticObjectMy.v[1] = value end
            if k2 == "tracerStaticObjectMyG" then st.tracerStaticObjectMy.v[2] = value end
            if k2 == "tracerStaticObjectMyB" then st.tracerStaticObjectMy.v[3] = value end
            if k2 == "tracerDinamicObjectMyR" then st.tracerDinamicObjectMy.v[1] = value end
            if k2 == "tracerDinamicObjectMyG" then st.tracerDinamicObjectMy.v[2] = value end
            if k2 == "tracerDinamicObjectMyB" then st.tracerDinamicObjectMy.v[3] = value end
            if k2 == "tracerPedPMyR" then st.tracerPedPMy.v[1] = value end
            if k2 == "tracerPedPMyG" then st.tracerPedPMy.v[2] = value end
            if k2 == "tracerPedPMyB" then st.tracerPedPMy.v[3] = value end
            if k2 == "tracerCarPMyR" then st.tracerCarPMy.v[1] = value end
            if k2 == "tracerCarPMyG" then st.tracerCarPMy.v[2] = value end
            if k2 == "tracerCarPMyB" then st.tracerCarPMy.v[3] = value end
            if k2 == "tracerStaticObjectR" then st.tracerStaticObject.v[1] = value end
            if k2 == "tracerStaticObjectG" then st.tracerStaticObject.v[2] = value end
            if k2 == "tracerStaticObjectB" then st.tracerStaticObject.v[3] = value end
            if k2 == "tracerDinamicObjectR" then st.tracerDinamicObject.v[1] = value end
            if k2 == "tracerDinamicObjectG" then st.tracerDinamicObject.v[2] = value end
            if k2 == "tracerDinamicObjectB" then st.tracerDinamicObject.v[3] = value end
            if k2 == "tracerPedPR" then st.tracerPedP.v[1] = value end
            if k2 == "tracerPedPG" then st.tracerPedP.v[2] = value end
            if k2 == "tracerPedPB" then st.tracerPedP.v[3] = value end
            if k2 == "tracerCarPR" then st.tracerCarP.v[1] = value end
            if k2 == "tracerCarPG" then st.tracerCarP.v[2] = value end
            if k2 == "tracerCarPB" then st.tracerCarP.v[3] = value end
            if k2 == "tracerColorPlayerIR" then st.tracerColorPlayerI.v[1] = value end
            if k2 == "tracerColorPlayerIG" then st.tracerColorPlayerI.v[2] = value end
            if k2 == "tracerColorPlayerIB" then st.tracerColorPlayerI.v[3] = value end
        end
        
        local k3, v3 = line:match("^(%w+)=(.+)$")
        if k3 and v3 and k3 == "autoLoginPassword" then
            al.password.v = u8(v3)
        end
        if k3 and v3 and k3 == "text_word" then
            st.text_word.v = u8(v3)
        end
        if k3 and v3 and k3 == "text_real" then
            st.text_real.v = u8(v3)
        end
        if k3 and v3 and k3 == "speedhackKey" then
            st.speedhackKey.v = v3
        end
    end
    f:close()
    
    wh_enabled_checkbox.v = wh_settings.enabled
    wh_by_nick_checkbox.v = wh_settings.by_nick
    wh_by_skeleton_checkbox.v = wh_settings.by_skeleton
    wh_show_on_screenshot_checkbox.v = wh_settings.show_on_screenshot
    
    if killList.enabled then
        killList.saveOriginalNames()
    end
    
    st.invisActive = false
    st.airbrakeActive = false
end

-- ===== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ МЕНЮ =====
local function U32(col)
    return imgui.ColorConvertFloat4ToU32(col)
end

local function getMSKTime()
    local utc = os.time(os.date('!*t'))
    local localTime = os.time()
    local diff = os.difftime(localTime, utc)
    
    if math.abs(diff - 10800) < 3600 then
        return os.date('%H:%M:%S')
    else
        return os.date('%H:%M:%S', utc + 10800)
    end
end

-- ===== КИБЕР-МЕНЮ =====
FHA.cyberMenu = FHA.cyberMenu or {
    visible = false,
    gearAngle = 0.0,
    windowPos = imgui.ImVec2(-1, -1),
    windowSize = imgui.ImVec2(900, 680),
    minWindowSize = imgui.ImVec2(500, 400),
    maxWindowSize = imgui.ImVec2(1200, 900),
    screenW = 0,
    screenH = 0,
    timePulse = 0,
    cursorEnabled = false,
    dragging = false,
    dragOffset = imgui.ImVec2(0, 0),
    selectedTab = 1,
    initDone = false,
    contentScrollY = 0,
    resizeCornerDragging = false,
    savedWpX = 0,
    savedWpY = 0,
    savedWsX = 0,
    savedWsY = 0,
    savedMouseX = 0,
    savedMouseY = 0,
}

local menu = FHA.cyberMenu

local serverInfo = {
    totalPlayers = 0,
    maxPlayers = 1000,
}

local particles = {}
local PARTICLE_COUNT = 25

local function initParticles()
    particles = {}
    for i = 1, PARTICLE_COUNT do
        particles[i] = {
            x = math.random() * menu.windowSize.x,
            y = math.random() * menu.windowSize.y,
            vx = (math.random() - 0.5) * 0.3,
            vy = (math.random() - 0.5) * 0.3,
            size = math.random(1, 3),
            alpha = math.random() * 0.5 + 0.1,
            life = math.random() * 100,
            maxLife = math.random() * 200 + 100,
        }
    end
end

local cs = {
    bgTop      = imgui.ImVec4(0.04, 0.01, 0.08, 0.96),
    bgBot      = imgui.ImVec4(0.01, 0.00, 0.02, 0.96),
    border     = imgui.ImVec4(0.35, 0.02, 0.55, 0.8),
    accent     = imgui.ImVec4(0.60, 0.05, 0.85, 1.0),
    accentHov  = imgui.ImVec4(0.85, 0.10, 1.0, 1.0),
    text       = imgui.ImVec4(0.85, 0.80, 0.95, 1.0),
    textDim    = imgui.ImVec4(0.45, 0.40, 0.55, 1.0),
    gearCol    = imgui.ImVec4(0.55, 0.05, 0.80, 1.0),
    neonGlow   = imgui.ImVec4(0.50, 0.03, 0.75, 0.7),
    timeCol    = imgui.ImVec4(0.45, 0.08, 0.65, 1.0),
    onlineCol  = imgui.ImVec4(0.55, 0.15, 0.75, 1.0),
    panelBg    = imgui.ImVec4(0.03, 0.02, 0.06, 0.9),
    particleCol = imgui.ImVec4(0.50, 0.10, 0.80, 0.6),
}

local function UpdateCyberColors()
    local st = FHA.state
    if st.menuColor.v == 0 then
        cs.accent = imgui.ImVec4(0.85, 0.10, 0.10, 1.0)
        cs.accentHov = imgui.ImVec4(1.0, 0.20, 0.20, 1.0)
        cs.gearCol = imgui.ImVec4(0.80, 0.08, 0.12, 1.0)
        cs.neonGlow = imgui.ImVec4(0.75, 0.05, 0.15, 0.7)
        cs.timeCol = imgui.ImVec4(0.65, 0.10, 0.15, 1.0)
        cs.onlineCol = imgui.ImVec4(0.75, 0.15, 0.15, 1.0)
        cs.particleCol = imgui.ImVec4(0.80, 0.10, 0.20, 0.6)
        cs.border = imgui.ImVec4(0.55, 0.05, 0.10, 0.8)
    elseif st.menuColor.v == 1 then
        cs.accent = imgui.ImVec4(0.10, 0.80, 0.10, 1.0)
        cs.accentHov = imgui.ImVec4(0.20, 1.0, 0.20, 1.0)
        cs.gearCol = imgui.ImVec4(0.10, 0.70, 0.10, 1.0)
        cs.neonGlow = imgui.ImVec4(0.05, 0.70, 0.10, 0.7)
        cs.timeCol = imgui.ImVec4(0.10, 0.60, 0.15, 1.0)
        cs.onlineCol = imgui.ImVec4(0.15, 0.70, 0.15, 1.0)
        cs.particleCol = imgui.ImVec4(0.10, 0.75, 0.15, 0.6)
        cs.border = imgui.ImVec4(0.05, 0.50, 0.10, 0.8)
    elseif st.menuColor.v == 2 then
        cs.accent = imgui.ImVec4(0.10, 0.30, 0.85, 1.0)
        cs.accentHov = imgui.ImVec4(0.20, 0.50, 1.0, 1.0)
        cs.gearCol = imgui.ImVec4(0.10, 0.20, 0.80, 1.0)
        cs.neonGlow = imgui.ImVec4(0.05, 0.15, 0.75, 0.7)
        cs.timeCol = imgui.ImVec4(0.10, 0.20, 0.65, 1.0)
        cs.onlineCol = imgui.ImVec4(0.15, 0.30, 0.75, 1.0)
        cs.particleCol = imgui.ImVec4(0.15, 0.25, 0.80, 0.6)
        cs.border = imgui.ImVec4(0.05, 0.10, 0.55, 0.8)
    elseif st.menuColor.v == 3 then
        cs.accent = imgui.ImVec4(1.0, 0.50, 0.10, 1.0)
        cs.accentHov = imgui.ImVec4(1.0, 0.70, 0.20, 1.0)
        cs.gearCol = imgui.ImVec4(0.90, 0.45, 0.10, 1.0)
        cs.neonGlow = imgui.ImVec4(0.80, 0.40, 0.05, 0.7)
        cs.timeCol = imgui.ImVec4(0.70, 0.35, 0.10, 1.0)
        cs.onlineCol = imgui.ImVec4(0.80, 0.40, 0.12, 1.0)
        cs.particleCol = imgui.ImVec4(0.85, 0.40, 0.15, 0.6)
        cs.border = imgui.ImVec4(0.60, 0.30, 0.05, 0.8)
    elseif st.menuColor.v == 4 then
        cs.accent = imgui.ImVec4(1.0, 1.0, 0.10, 1.0)
        cs.accentHov = imgui.ImVec4(1.0, 1.0, 0.30, 1.0)
        cs.gearCol = imgui.ImVec4(0.90, 0.90, 0.10, 1.0)
        cs.neonGlow = imgui.ImVec4(0.80, 0.80, 0.05, 0.7)
        cs.timeCol = imgui.ImVec4(0.70, 0.70, 0.10, 1.0)
        cs.onlineCol = imgui.ImVec4(0.80, 0.80, 0.12, 1.0)
        cs.particleCol = imgui.ImVec4(0.85, 0.85, 0.15, 0.6)
        cs.border = imgui.ImVec4(0.60, 0.60, 0.05, 0.8)
    elseif st.menuColor.v == 5 then
        cs.accent = imgui.ImVec4(0.10, 0.80, 0.85, 1.0)
        cs.accentHov = imgui.ImVec4(0.20, 1.0, 1.0, 1.0)
        cs.gearCol = imgui.ImVec4(0.10, 0.75, 0.80, 1.0)
        cs.neonGlow = imgui.ImVec4(0.05, 0.70, 0.75, 0.7)
        cs.timeCol = imgui.ImVec4(0.10, 0.65, 0.70, 1.0)
        cs.onlineCol = imgui.ImVec4(0.12, 0.75, 0.80, 1.0)
        cs.particleCol = imgui.ImVec4(0.15, 0.75, 0.80, 0.6)
        cs.border = imgui.ImVec4(0.05, 0.55, 0.60, 0.8)
    elseif st.menuColor.v == 6 then
        cs.accent = imgui.ImVec4(0.60, 0.05, 0.85, 1.0)
        cs.accentHov = imgui.ImVec4(0.85, 0.10, 1.0, 1.0)
        cs.gearCol = imgui.ImVec4(0.55, 0.05, 0.80, 1.0)
        cs.neonGlow = imgui.ImVec4(0.50, 0.03, 0.75, 0.7)
        cs.timeCol = imgui.ImVec4(0.45, 0.08, 0.65, 1.0)
        cs.onlineCol = imgui.ImVec4(0.55, 0.15, 0.75, 1.0)
        cs.particleCol = imgui.ImVec4(0.50, 0.10, 0.80, 0.6)
        cs.border = imgui.ImVec4(0.35, 0.02, 0.55, 0.8)
    elseif st.menuColor.v == 7 then
        local t = os.clock()
        local r = (math.sin(t * 2.0) + 1.0) * 0.5
        local g = (math.sin(t * 2.0 + math.pi/3) + 1.0) * 0.5
        local b = (math.sin(t * 2.0 + 2*math.pi/3) + 1.0) * 0.5
        cs.accent = imgui.ImVec4(r*0.7+0.3, g*0.7+0.3, b*0.7+0.3, 1.0)
        cs.accentHov = imgui.ImVec4(r*0.9+0.1, g*0.9+0.1, b*0.9+0.1, 1.0)
        cs.gearCol = imgui.ImVec4(r*0.6+0.2, g*0.6+0.2, b*0.6+0.2, 1.0)
        cs.neonGlow = imgui.ImVec4(r*0.5+0.1, g*0.5+0.1, b*0.5+0.1, 0.7)
        cs.timeCol = imgui.ImVec4(r*0.4+0.2, g*0.4+0.2, b*0.4+0.2, 1.0)
        cs.onlineCol = imgui.ImVec4(r*0.5+0.1, g*0.5+0.1, b*0.5+0.1, 1.0)
        cs.particleCol = imgui.ImVec4(r*0.5+0.1, g*0.5+0.1, b*0.5+0.1, 0.6)
        cs.border = imgui.ImVec4(r*0.3+0.1, g*0.3+0.1, b*0.3+0.1, 0.8)
    end
end

local function updateOnline()
    local total = 0
    for i = 0, 999 do
        if sampIsPlayerConnected(i) then
            total = total + 1
        end
    end
    serverInfo.totalPlayers = total + 1
end

local function ShowCursor(show)
    if show then
        sampSetCursorMode(1)
        menu.cursorEnabled = true
    else
        sampSetCursorMode(0)
        sampToggleCursor(false)
        menu.cursorEnabled = false
    end
end

local function updateParticles()
    for i = 1, #particles do
        local p = particles[i]
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.life = p.life + 1
        
        if p.x < 0 or p.x > menu.windowSize.x then p.vx = -p.vx end
        if p.y < 0 or p.y > menu.windowSize.y then p.vy = -p.vy end
        
        if p.life > p.maxLife then
            p.x = math.random() * menu.windowSize.x
            p.y = math.random() * menu.windowSize.y
            p.vx = (math.random() - 0.5) * 0.3
            p.vy = (math.random() - 0.5) * 0.3
            p.life = 0
            p.maxLife = math.random() * 200 + 100
        end
    end
end

local function DrawGear(cx, cy, outerR, innerR, angle, color)
    local dl = imgui.GetWindowDrawList()
    local teeth = 8
    local step = math.pi * 2 / (teeth * 2)
    local color32 = U32(color)
    local prevX, prevY, firstX, firstY = nil, nil, nil, nil
    
    for i = 0, teeth * 2 - 1 do
        local a = angle + i * step
        local r = (i % 2 == 0) and outerR or innerR
        local px = cx + math.cos(a) * r
        local py = cy + math.sin(a) * r
        
        if not firstX then firstX = px; firstY = py end
        if prevX and prevY then
            dl:AddLine(imgui.ImVec2(prevX, prevY), imgui.ImVec2(px, py), color32, 2.0)
        end
        prevX = px; prevY = py
    end
    if prevX and firstX then
        dl:AddLine(imgui.ImVec2(prevX, prevY), imgui.ImVec2(firstX, firstY), color32, 2.0)
    end
    
    dl:AddCircleFilled(imgui.ImVec2(cx, cy), innerR - 3, U32(imgui.ImVec4(0.03,0.01,0.05,1.0)))
    dl:AddCircle(imgui.ImVec2(cx, cy), innerR - 2, U32(cs.accent), 0, 1.5)
end

local function DrawLogoAndTime()
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local ws = imgui.GetWindowSize()
    
    updateOnline()
    
    local logoCenterX = wp.x + 65
    local logoCenterY = wp.y + 45
    
    for i = 3, 0, -1 do
        dl:AddCircleFilled(imgui.ImVec2(logoCenterX, logoCenterY), 40 + i*3, 
            U32(imgui.ImVec4(cs.accent.x*0.7, cs.accent.y*0.7, cs.accent.z*0.7, 0.12 - i*0.03)))
    end
    
    DrawGear(logoCenterX - 16, logoCenterY + 8, 20, 12, menu.gearAngle, cs.gearCol)
    DrawGear(logoCenterX + 16, logoCenterY - 8, 20, 12, -menu.gearAngle + 0.3, cs.gearCol)
    
    local textX = logoCenterX + 38
    dl:AddText(imgui.ImVec2(textX, logoCenterY - 16), U32(cs.accent), "FastHelperAdm")
    dl:AddText(imgui.ImVec2(textX + 4, logoCenterY + 4), U32(cs.textDim), "Version: 2.1")
    dl:AddLine(imgui.ImVec2(textX, logoCenterY + 20), imgui.ImVec2(textX + 130, logoCenterY + 20), U32(cs.neonGlow), 1.5)
    
    local rightBlockX = wp.x + ws.x - 165
    local blockW = 150
    
    local onlineY = wp.y + 32
    local onlineStr = "Online: " .. serverInfo.totalPlayers .. " / " .. serverInfo.maxPlayers
    local osSize = imgui.CalcTextSize(onlineStr)
    
    dl:AddRectFilled(imgui.ImVec2(rightBlockX-5, onlineY-3), 
        imgui.ImVec2(rightBlockX+blockW, onlineY+osSize.y+3),
        U32(imgui.ImVec4(0.03,0.02,0.06,0.85)), 6)
    
    local glowAlpha = 0.4 + math.sin(menu.timePulse * 1.5) * 0.25
    dl:AddRect(imgui.ImVec2(rightBlockX-5, onlineY-3), 
        imgui.ImVec2(rightBlockX+blockW, onlineY+osSize.y+3),
        U32(imgui.ImVec4(cs.onlineCol.x, cs.onlineCol.y, cs.onlineCol.z, glowAlpha)), 6, 15, 1.5)
    
    dl:AddText(imgui.ImVec2(rightBlockX + (blockW - osSize.x)*0.5, onlineY), U32(cs.onlineCol), onlineStr)
    
    local timeY = onlineY + osSize.y + 8
    local timeStr = getMSKTime()
    local ts = imgui.CalcTextSize(timeStr)
    
    dl:AddRectFilled(imgui.ImVec2(rightBlockX-5, timeY-3), 
        imgui.ImVec2(rightBlockX+blockW, timeY+ts.y+3),
        U32(imgui.ImVec4(0.03,0.02,0.06,0.85)), 6)
    
    dl:AddRect(imgui.ImVec2(rightBlockX-5, timeY-3), 
        imgui.ImVec2(rightBlockX+blockW, timeY+ts.y+3),
        U32(imgui.ImVec4(cs.timeCol.x, cs.timeCol.y, cs.timeCol.z, glowAlpha)), 6, 15, 1.5)
    
    dl:AddText(imgui.ImVec2(rightBlockX + (blockW - ts.x)*0.5, timeY), U32(cs.timeCol), timeStr)
    
    imgui.SetCursorScreenPos(imgui.ImVec2(wp.x, wp.y + 90))
    imgui.Dummy(imgui.ImVec2(1, 1))
end

local function TabButton(label, active)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    local h = 36
    local r = h * 0.5
    
    local col = active and imgui.ImVec4(cs.accent.x*0.5, cs.accent.y*0.5, cs.accent.z*0.5, 0.9) or imgui.ImVec4(0.04, 0.02, 0.06, 0.7)
    local colHov = active and imgui.ImVec4(cs.accent.x*0.7, cs.accent.y*0.7, cs.accent.z*0.7, 0.9) or imgui.ImVec4(cs.accent.x*0.15, cs.accent.y*0.15, cs.accent.z*0.15, 0.8)
    
    local hovered = imgui.IsMouseHoveringRect(p, imgui.ImVec2(p.x + w, p.y + h))
    local clicked = hovered and imgui.IsMouseClicked(0)
    local useCol = hovered and colHov or col
    
    dl:AddRectFilled(imgui.ImVec2(p.x+1, p.y+1), imgui.ImVec2(p.x+w+1, p.y+h+1), 
        U32(imgui.ImVec4(cs.accent.x*0.3, cs.accent.y*0.3, cs.accent.z*0.3, 0.4)), r)
    dl:AddRectFilled(p, imgui.ImVec2(p.x+w, p.y+h), U32(useCol), r)
    
    local ts = imgui.CalcTextSize(label)
    dl:AddText(imgui.ImVec2(p.x + 12, p.y + (h - ts.y)*0.5),
        U32(active and imgui.ImVec4(1,1,1,1) or cs.textDim), label)
    
    imgui.Dummy(imgui.ImVec2(w, h))
    return clicked
end

-- ===== SPEEDHACK =====
local speedhackListening = false
local function FHA_SpeedhackThread()
    local st = FHA.state
    local ffi = require("ffi")
    local bit = require("bit")
    local samem = require 'SAMemory'
    samem.require 'CTrain'
    local player_vehicle = samem.cast('CVehicle **', samem.player_vehicle)

    while not FHA.isUnloading do
        wait(0)
        if st.speedhackEnabled.v and st.adminLevel.v >= 6 then
            local keyName = tostring(st.speedhackKey.v)
            local keyId = vkeys.name_to_id(keyName, false)
            if keyId and isKeyDown(keyId) then
                local veh = player_vehicle[0]
                if veh ~= samem.nullptr then
                    if veh.nVehicleClass == 6 then
                        local train = samem.cast('CTrain *', veh)
                        while train ~= samem.nullptr do
                            local new_speed = train.fTrainSpeed * 1.02
                            if new_speed <= 1.25 then
                                train.fTrainSpeed = new_speed
                            end
                            train = train.pNextCarriage
                        end
                    else
                        while veh ~= samem.nullptr do
                            local new_speed = veh.vMoveSpeed * 1.02
                            if new_speed:magnitude() <= 1.25 then
                                veh.vMoveSpeed = new_speed
                            end
                            veh = veh.pTrailer
                        end
                    end
                end
            end
        end
    end
end

-- ===== НАСТРОЙКИ ТРЕЙСЕРА =====
local function DrawTracerSettings()
    local st = FHA.state
    
    imgui.BeginChild("##tracer_settings", imgui.ImVec2(0, 0), true, imgui.WindowFlags.VerticalScrollbar)
    
    imgui.TextColored(cs.accent, u8"=== НАСТРОЙКИ ТРЕЙСЕРА ===")
    imgui.Spacing()
    
    imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"Мои пули:")
    if imgui.Checkbox(u8"Отображать свои пули", st.tracerDrawMyBullets) then st.saveSettingsFlag = true end
    if imgui.Checkbox(u8"Полигон в конце (свои)", st.tracerCbEndMy) then st.saveSettingsFlag = true end
    
    imgui.SliderInt(u8"Время отображения (свои)", st.tracerTimeRenderMyBullets, 1, 60)
    imgui.SliderInt(u8"Толщина линии (свои)", st.tracerSizeOffMyLine, 1, 10)
    imgui.SliderInt(u8"Размер полигона (свои)", st.tracerSizeOffMyPolygonEnd, 1, 20)
    imgui.SliderInt(u8"Вращение полигона (свои)", st.tracerRotationMyPolygonEnd, 1, 360)
    imgui.SliderInt(u8"Угол полигона (свои)", st.tracerDegreeMyPolygonEnd, 3, 360)
    imgui.SliderInt(u8"Лимит линий (свои)", st.tracerMaxLineMyLimit, 1, 100)
    
    imgui.ColorEdit4(u8"Статик. объект (свои)", st.tracerStaticObjectMy)
    imgui.ColorEdit4(u8"Динамик. объект (свои)", st.tracerDinamicObjectMy)
    imgui.ColorEdit4(u8"Игрок (свои)", st.tracerPedPMy)
    imgui.ColorEdit4(u8"Машина (свои)", st.tracerCarPMy)
    
    imgui.Separator()
    imgui.Spacing()
    
    imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"Чужие пули:")
    if imgui.Checkbox(u8"Отображать чужие пули", st.tracerDrawBullets) then st.saveSettingsFlag = true end
    if imgui.Checkbox(u8"Полигон в конце (чужие)", st.tracerCbEnd) then st.saveSettingsFlag = true end
    if imgui.Checkbox(u8"Информация об игроке", st.tracerShowPlayerInfo) then st.saveSettingsFlag = true end
    
    if st.tracerShowPlayerInfo.v then
        if imgui.Checkbox(u8"Только ID", st.tracerOnlyId) then st.saveSettingsFlag = true end
        imgui.SameLine()
        if imgui.Checkbox(u8"Только Ник", st.tracerOnlyNick) then st.saveSettingsFlag = true end
    end
    
    imgui.SliderInt(u8"Время отображения (чужие)", st.tracerTimeRenderBullets, 1, 60)
    imgui.SliderInt(u8"Толщина линии (чужие)", st.tracerSizeOffLine, 1, 10)
    imgui.SliderInt(u8"Размер полигона (чужие)", st.tracerSizeOffPolygonEnd, 1, 20)
    imgui.SliderInt(u8"Вращение полигона (чужие)", st.tracerRotationPolygonEnd, 1, 360)
    imgui.SliderInt(u8"Угол полигона (чужие)", st.tracerDegreePolygonEnd, 3, 360)
    imgui.SliderInt(u8"Лимит линий (чужие)", st.tracerMaxLineLimit, 1, 100)
    
    imgui.ColorEdit4(u8"Статик. объект (чужие)", st.tracerStaticObject)
    imgui.ColorEdit4(u8"Динамик. объект (чужие)", st.tracerDinamicObject)
    imgui.ColorEdit4(u8"Игрок (чужие)", st.tracerPedP)
    imgui.ColorEdit4(u8"Машина (чужие)", st.tracerCarP)
    imgui.ColorEdit4(u8"Цвет инфо игрока", st.tracerColorPlayerI)
    
    imgui.Separator()
    imgui.Spacing()
    
    if imgui.Button(u8"Сохранить настройки", imgui.ImVec2(-1, 30)) then
        FHA_saveCfg()
        sampAddChatMessage("{33FF33}[FastHelperAdm] Настройки Tracer сохранены!", -1)
    end
    
    imgui.EndChild()
end

-- ===== ВКЛАДКИ МЕНЮ =====
local function DrawTab1_Cyber()
    imgui.TextColored(cs.accent, u8">>> ОСНОВНЫЕ КОМАНДЫ <<<")
    imgui.Spacing()
    imgui.TextWrapped(FHA_genderText(
        u8"Основные команды:\n/plmenu – открыть/закрыть меню\n/pl [id] [код/текст]\n/lc - Открыть/закрыть вкладку Временное Лидерство\n/invis - Для использования невидимости",
        u8"Основные команды:\n/plmenu – открыть/закрыть меню\n/pl [id] [код/текст]\n/lc - Открыть/закрыть вкладку Временное Лидерство\n/invis - Для использования невидимости"
    ))
    imgui.TextWrapped(FHA_genderText(
        u8"Быстрые коды:\no – Ожидайте\ny – Уточните\ngo – Уже иду\nhel – Помог\nsg – Свободная группа\nnon – Нет в сети\nper – Передам\notk – Отказ\nrp – РП путём\ns – Слежу",
        u8"Быстрые коды:\no – Ожидайте\ny – Уточните\ngo – Уже иду\nhel – Помогла\nsg – Свободная группа\nnon – Нет в сети\nper – Передам\notk – Отказ\nrp – РП путём\ns – Слежу"
    ))
    imgui.TextWrapped(FHA_genderText(
        u8"Примеры:\n/pl 15 o\n/pl 15 Привет",
        u8"Примеры:\n/pl 15 o\n/pl 15 Привет"
    ))
end

local function DrawTab2_Cyber()
    local st = FHA.state
    local al = FHA.autoLogin
    
    imgui.TextColored(cs.accent, u8">>> НАСТРОЙКИ <<<")
    imgui.Spacing()
    
    imgui.Text(u8"Основные настройки")
    imgui.Separator()
    
    imgui.Text(u8"Цвет меню")
    local colorChoices = {
        u8"Красный", 
        u8"Зеленый", 
        u8"Синий", 
        u8"Оранжевый", 
        u8"Желтый", 
        u8"Голубой", 
        u8"Фиолетовый",
        u8"Радужный"
    }
    if imgui.Combo(u8"Выберите цвет", st.menuColor, colorChoices, #colorChoices) then
        UpdateCyberColors()
        st.saveSettingsFlag = true
    end

    if st.menuColor.v == 7 then
        imgui.TextColored(imgui.ImVec4(1,0,1,1), u8"? Радужный режим активен")
    end

    imgui.Spacing()
    imgui.Text(FHA_genderText(u8"Пол администратора", u8"Пол администраторши"))
    imgui.RadioButton(u8"Мужской", st.gender, 0)
    imgui.SameLine()
    imgui.RadioButton(u8"Женский", st.gender, 1)

    imgui.Spacing()
    imgui.Text(u8"Уровень админ прав")
    imgui.SliderInt(u8"Выберите уровень", st.adminLevel, 1, 14)

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    imgui.TextColored(imgui.ImVec4(1, 0.8, 0.2, 1), u8"[#] Автоматический вход в админку")
    
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"Включить авто-логин", al.enabled) then
            FHA_saveCfg()
        end
    else
        imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1), u8"Включить авто-логин (требуется уровень 6+)")
        if al.enabled.v then
            al.enabled.v = false
            FHA_saveCfg()
        end
    end
    
    if al.enabled.v or st.adminLevel.v >= 6 then
        imgui.Spacing()
        imgui.Text(u8"Пароль от админки:")
        
        local buttonWidth = 40
        local inputWidth = 200
        
        imgui.PushItemWidth(inputWidth)
        
        local flags = imgui.InputTextFlags.None
        if not al.showPassword.v then
            flags = imgui.InputTextFlags.Password
        end
        
        if imgui.InputText("##autologin_password", al.password, flags) then
            FHA_saveCfg()
        end
        
        imgui.PopItemWidth()
        imgui.SameLine()
        
        local buttonLabel = al.showPassword.v and u8"*" or u8"O"
        if imgui.Button(buttonLabel, imgui.ImVec2(buttonWidth, 0)) then
            al.showPassword.v = not al.showPassword.v
        end
        
        if imgui.IsItemHovered() then
            if al.showPassword.v then
                imgui.SetTooltip(u8("Скрыть пароль"))
            else
                imgui.SetTooltip(u8("Показать пароль"))
            end
        end
    end
    
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    if st.adminLevel.v >= 9 then
        imgui.TextColored(imgui.ImVec4(0,1,0,1), u8"Доступ ко всем вкладкам доступен")
    else
        imgui.TextColored(imgui.ImVec4(1,0.5,0,1), u8"Доступ ограничен. Уровни 1-8 не могут использовать:")
        imgui.Text(u8"• Авто-Мероприятие")
        imgui.Text(u8"• Авто-Раздачу") 
        imgui.Text(u8"• Авто-Отбор")
        imgui.Text(u8"• Временное лидерство")
    end
end

local function DrawTab3_Cyber()
    imgui.TextColored(cs.accent, u8">>> ОТВЕТЫ НА РЕПОРТЫ <<<")
    imgui.Spacing()

    imgui.Text(u8"Активные репорты: " .. #FHA.reports)
    imgui.SameLine()
    if imgui.Button(u8"Очистить все") then
        FHA_clearAllReports()
    end

    imgui.Separator()

    imgui.BeginChild("reports_list", imgui.ImVec2(0, 150), true)
    if #FHA.reports == 0 then
        imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1), u8"Нет активных репортов")
    else
        for i, r in ipairs(FHA.reports) do
            local passed = os.time() - r.time
            local timeStr = FHA_formatTime(passed)
            
            local displayText = string.format("[%s] %s[%d]: %s", 
                timeStr, r.nick, r.id, 
                #r.text > 50 and r.text:sub(1, 47) .. "..." or r.text)
            
            if imgui.Selectable(displayText, FHA.selectedReport == i, imgui.SelectableFlags.None, imgui.ImVec2(0, 0)) then
                FHA.selectedReport = i
                FHA.answerText.v = ""
            end
        end
    end
    imgui.EndChild()

    imgui.Separator()

    if FHA.selectedReport then
        local r = FHA.reports[FHA.selectedReport]
        imgui.TextColored(cs.accent, u8"Выбранный репорт:")
        imgui.TextWrapped(string.format("%s [%d]: %s", r.nick, r.id, r.text))
        imgui.Spacing()
    else
        imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1), u8"Выберите репорт из списка выше.")
        imgui.Spacing()
    end

    imgui.Separator()

    if FHA.selectedReport then
        local r = FHA.reports[FHA.selectedReport]

        imgui.Text(u8"Ответ игроку:")
        
        local inputHeight = 70
        if imgui.InputTextMultiline("##answer", FHA.answerText, 
            imgui.ImVec2(-1, inputHeight), imgui.InputTextFlags.None) then
        end

        if imgui.Button(u8"Закрыть репорт", imgui.ImVec2(-1, 35)) then
            FHA_removeReport(FHA.selectedReport)
        end

        imgui.Spacing()

        if imgui.Button(u8"Отправить ответ", imgui.ImVec2(-1, 30)) then
            if #FHA.answerText.v > 0 then
                local answerCp1251 = encoding.UTF8:decode(FHA.answerText.v)
                sampSendChat(string.format("/pm %d %s", r.id, answerCp1251))
                FHA_removeReport(FHA.selectedReport)
            else
                sampAddChatMessage("{FF4444}[FastHelperAdm] Введите текст ответа", -1)
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Text(u8"Быстрые действия:")
        
        imgui.BeginChild("##quick_actions", imgui.ImVec2(0, 150), true)
        local buttonWidth = imgui.GetContentRegionAvail().x - 5
        
        if imgui.Button(u8"Приятной Игры", imgui.ImVec2(buttonWidth, 28)) then
            sampSendChat(string.format("/pm %d Приятной игры от %s <3", r.id, FHA_adminWord()))
            FHA_removeReport(FHA.selectedReport)
        end
        
        if imgui.Button(u8"Спавн", imgui.ImVec2(buttonWidth, 28)) then
            FHA_sendWithDelay(
                "/sp " .. r.id,
                string.format("/pm %d Вы успешно заспавнены | Приятной игры от %s <3", r.id, FHA_adminWord()),
                950
            )
            FHA_removeReport(FHA.selectedReport)
        end
        
        if imgui.Button(u8"Ожидайте", imgui.ImVec2(buttonWidth, 28)) then
            sampSendChat(string.format("/pm %d Ожидайте | Приятной игры от %s <3", r.id, FHA_adminWord()))
            FHA_removeReport(FHA.selectedReport)
        end
        
        if imgui.Button(u8"Передать", imgui.ImVec2(buttonWidth, 28)) then
            FHA_sendWithDelay(
                string.format("/a Репорт от %s[%d] <<%s>>", r.nick, r.id, encoding.UTF8:decode(r.text)),
                string.format("/pm %d Репорт был передан | Приятной игры от %s <3", r.id, FHA_adminWord()),
                950
            )
            FHA_removeReport(FHA.selectedReport)
        end
        
        if imgui.Button(u8"СГ", imgui.ImVec2(buttonWidth, 28)) then
            sampSendChat(string.format("/pm %d Оставьте жалобу в Свободной Группе ВК @inferno_sv", r.id))
            FHA_removeReport(FHA.selectedReport)
        end
        imgui.EndChild()
    else
        imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1), u8"Выберите репорт для отображения действий.")
    end
end

-- ===== ВКЛАДКА 4: ФУНКЦИИ =====
local function DrawTab4_Cyber()
    local st = FHA.state
    
    imgui.TextColored(cs.accent, u8">>> ПОЛЕЗНЫЕ ФУНКЦИИ <<<")
    imgui.Spacing()
    
    if imgui.Checkbox(u8"Авто Пожелание", st.autoWish) then st.saveSettingsFlag = true end
    imgui.SameLine()
    if imgui.Button(u8" ? ") then end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8"При появлении PayDay будет отправлен /gg")
    end
    
    imgui.Text(u8"Speedhack")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"Speedhack", st.speedhackEnabled) then 
            st.saveSettingsFlag = true 
        end
        imgui.SameLine()
        imgui.TextDisabled(u8"(Админ 6+)")
        if st.speedhackEnabled.v then
            imgui.Text(u8"Клавиша:")
            imgui.SameLine()
            if imgui.Button(tostring(st.speedhackKey.v) .. "") then
                speedhackListening = true
                sampAddChatMessage("{FFCC00}[Speedhack] Нажмите любую клавишу для смены бинда...", -1)
            end
            if speedhackListening then
                for vk = 0, 255 do
                    if wasKeyPressed(vk) then
                        local keyName = vkToString(vk)
                        if keyName and keyName ~= "VK_0" then
                            st.speedhackKey.v = keyName
                            speedhackListening = false
                            st.saveSettingsFlag = true
                            sampAddChatMessage(string.format("{33FF33}[Speedhack] Бинд изменён на: %s", keyName), -1)
                            break
                        end
                    end
                end
            end
        end
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"Speedhack (Админ 6+)")
    end
    
    imgui.Text(u8"Tracer")
    if imgui.Checkbox(u8"Включить Tracer", st.tracerEnabled) then st.saveSettingsFlag = true end
    imgui.SameLine()
    if imgui.Button(u8"Настроить Трейсер") then
        st.showTracerSettings.v = not st.showTracerSettings.v
    end
    
    if st.showTracerSettings.v then
        imgui.Separator()
        DrawTracerSettings()
        imgui.Separator()
    end
    
    imgui.Text(u8"ClickWarp")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"ClickWarp (телепорт на колесо)", st.clickWarpEnabled) then st.saveSettingsFlag = true end
        imgui.SameLine()
        imgui.TextDisabled(u8"(Админ 6+)")
        
        if st.clickWarpEnabled.v then
            imgui.TextColored(imgui.ImVec4(0,1,0,1), u8"Управление:")
            imgui.Text(u8"• Колесо мыши - включить/выключить режим")
            imgui.Text(u8"• ЛКМ - телепорт к точке")
            imgui.Text(u8"• ПКМ + ЛКМ - телепорт в машину")
        end
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"ClickWarp [уровень 6+]")
    end
    
    imgui.Text(u8"Невидимость")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"Невидимость (/invis)", st.invisEnabled) then st.saveSettingsFlag = true end
        if st.invisEnabled.v then
            imgui.TextColored(imgui.ImVec4(0,1,0,1), u8("Статус: ") .. (st.invisActive and u8"Включено" or u8"Выключено"))
            if imgui.Button(u8"Переключить невидимость") then
                FHA_cmd_invis()
            end
        end
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"Невидимость [уровень 6+]")
    end
    
    imgui.Text(u8"AirBrake")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"Включить AirBrake (RSHIFT)", st.airbrakeEnabled) then st.saveSettingsFlag = true end
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"AirBrake [уровень 6+]")
    end
    
    imgui.Text(u8"GM Car")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"GM Car", st.gmCarEnabled) then
            st.saveSettingsFlag = true
        end
        imgui.TextDisabled(u8"(Админ 6+)")
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"GM Car [уровень 6+]")
    end

    -- ===== ZZVEH НАСТРОЙКА =====
    imgui.Text(u8"Обход Зелёной Зоны (ZZVeh)")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"Включить ZZVeh (создание машин в ЗЗ)", st.zzvehEnabled) then
            st.saveSettingsFlag = true
            if st.zzvehEnabled.v then
                sampAddChatMessage("{33FF33}[FastHelperAdm] ZZVeh включен! Просто пишите /veh [id] [c1] [c2]", -1)
            else
                sampAddChatMessage("{FF4444}[FastHelperAdm] ZZVeh выключен", -1)
            end
        end
        imgui.TextDisabled(u8"(Админ 6+)")
        if st.zzvehEnabled.v then
            imgui.TextColored(imgui.ImVec4(0.5, 0.8, 1, 1), u8"Как работает:")
            imgui.Text(u8"• Пишите /veh [id] [c1] [c2] в зелёной зоне")
            imgui.Text(u8"• Вы будете телепортированы вне зоны на 1 секунду")
            imgui.Text(u8"• Машина создастся на вашем месте")
            imgui.Text(u8"• Вы вернётесь обратно с машиной!")
        end
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"ZZVeh [уровень 6+]")
    end

    imgui.Text(u8"Авто Ввод команд")
    if st.adminLevel.v >= 6 then
        if imgui.Checkbox(u8"Авто Ввод", st.autoEnable) then st.saveSettingsFlag = true end
        if st.autoEnable.v then
            imgui.Checkbox(u8"/agm", st.autoAgm)
            imgui.Checkbox(u8"/chat", st.autoChat)
            imgui.Checkbox(u8"/chatsms", st.autoChatsms)
            imgui.Checkbox(u8"/offgoto", st.autoOffgoto)
            imgui.Checkbox(u8"/togphone", st.autoTogphone)
        end
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8"Авто Ввод [уровень 6+]")
    end

    -- WALLHACK
    imgui.Spacing()
    imgui.Spacing()

    local label = u8"Wallhack "
    if imgui.Checkbox(label, wh_enabled_checkbox) then
        wh_settings.enabled = wh_enabled_checkbox.v
        st.saveSettingsFlag = true
    end
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.6, 0.05, 0.85, 1.0))
    imgui.Text("(?)")
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8"Видеть сквозь стены")
    end
    imgui.PopStyleColor()

    if wh_settings.enabled then
        if imgui.Checkbox(u8"По нику", wh_by_nick_checkbox) then
            wh_settings.by_nick = wh_by_nick_checkbox.v
            st.saveSettingsFlag = true
        end
        if imgui.Checkbox(u8"По скелету", wh_by_skeleton_checkbox) then
            wh_settings.by_skeleton = wh_by_skeleton_checkbox.v
            st.saveSettingsFlag = true
        end
        if imgui.Checkbox(u8"Показывать на скрине", wh_show_on_screenshot_checkbox) then
            wh_settings.show_on_screenshot = wh_show_on_screenshot_checkbox.v
            st.saveSettingsFlag = true
        end
    end

    -- KILL LIST ID
    imgui.Spacing()
    imgui.Spacing()
    
    imgui.TextColored(imgui.ImVec4(0.7, 0.4, 0.9, 1), u8"Kill List ID")
    if imgui.Checkbox(u8"Показывать ID в килл листе", imgui.ImBool(killList.enabled)) then
        killList.toggle()
    end
    imgui.SameLine()
    if imgui.Button(u8" ? ", imgui.ImVec2(25, 20)) then end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8"Показывает ID игроков в списке убийств")
    end

    -- ===== ADMIN RENDER =====
    imgui.Spacing()
    imgui.Spacing()
    
    imgui.TextColored(imgui.ImVec4(0.4, 0.8, 1.0, 1), u8">>> ADMIN RENDER <<<")
    imgui.Spacing()
    
    if imgui.Checkbox(u8"Включить Admin Render", adminRender.enabled) then
        if adminRender.enabled.v then
            adminRender.init()
            adminRender.update()
            adminRender.loadPosition()
            adminRender.loadFilter()
        end
    end
    
    if adminRender.enabled.v then
        imgui.Indent()
        
        if imgui.Checkbox(u8"Показывать уровни", adminRender.showLvl) then
            adminRender.saveFilter()
        end
        if imgui.Checkbox(u8"Показывать статусы (AFK/re)", adminRender.showAction) then
            adminRender.saveFilter()
        end
        if imgui.Checkbox(u8"Показывать время активности", adminRender.showActive) then
            adminRender.saveFilter()
        end
        
        imgui.Spacing()
        imgui.Text(u8"Фильтр по уровням:")
        
        for i = 1, 7 do
            local lvl = i
            local label = string.format("%s lvl", lvl)
            if imgui.Checkbox(label, imgui.ImBool(adminRender.lvlFilter[lvl])) then
                adminRender.lvlFilter[lvl] = not adminRender.lvlFilter[lvl]
                adminRender.saveFilter()
            end
            if i < 7 then
                imgui.SameLine()
            end
        end
        for i = 8, 14 do
            local lvl = i
            local label = string.format("%s lvl", lvl)
            if imgui.Checkbox(label, imgui.ImBool(adminRender.lvlFilter[lvl])) then
                adminRender.lvlFilter[lvl] = not adminRender.lvlFilter[lvl]
                adminRender.saveFilter()
            end
            if i < 14 then
                imgui.SameLine()
            end
        end
        
        imgui.Spacing()
        
        if imgui.Button(u8"Переместить список", imgui.ImVec2(-1, 30)) then
            adminRender.startMove()
        end
        
        if adminRender.isMoving then
            adminRender.updateMove()
            imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"Нажмите ENTER для сохранения позиции")
            imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8"Нажмите ESC для отмены")
            
            if wasKeyPressed(vkeys.VK_RETURN) then
                adminRender.stopMove(true)
            end
            if wasKeyPressed(vkeys.VK_ESCAPE) then
                adminRender.stopMove(false)
            end
        end
        
        imgui.Spacing()
        imgui.Text(string.format("Позиция: X=%d Y=%d", adminRender.posX, adminRender.posY))
        
        if imgui.Button(u8"Обновить список сейчас", imgui.ImVec2(-1, 25)) then
            adminRender.update()
        end
        
        imgui.Unindent()
    end
end

-- ===== ВКЛАДКА 5: АВТО МЕРОПРИЯТИЕ, РАЗДАЧА, ОТБОР =====
local function DrawTab5_Cyber()
    local st = FHA.state
    
    imgui.TextColored(cs.accent, u8">>> АВТО МЕРОПРИЯТИЕ <<<")
    imgui.Spacing()
    
    if st.adminLevel.v < 9 then
        imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8"Доступно с 9 уровня администратора")
        imgui.Separator()
        imgui.Spacing()
        imgui.TextColored(cs.accent, u8">>> АВТО РАЗДАЧА <<<")
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8"Доступно с 9 уровня администратора")
        imgui.Separator()
        imgui.Spacing()
        imgui.TextColored(cs.accent, u8">>> АВТО ОТБОР <<<")
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8"Доступно с 9 уровня администратора")
        return
    end
    
    imgui.Text(u8"Выберите мероприятие:")
    
    local mpChoices = {u8"Стандартное", u8"Своё"}
    imgui.Combo(u8"Тип мероприятия", st.mp_selectEvent, mpChoices, #mpChoices)
    
    if st.mp_selectEvent.v == 0 then
        imgui.Combo(u8"Название МП", st.combo_mp_name, st.mp_names, #st.mp_names)
    else
        imgui.InputText(u8"Своё название", st.mp_custom_name)
    end
    
    imgui.InputText(u8"Приз", st.mp_prize_text)
    
    imgui.Spacing()
    if imgui.Button(u8"Запустить мероприятие", imgui.ImVec2(-1, 30)) then
        st.startAutoMpFlag = true
    end
    
    imgui.Separator()
    imgui.Spacing()
    
    imgui.TextColored(cs.accent, u8">>> АВТО РАЗДАЧА <<<")
    imgui.Spacing()
    
    imgui.Text(u8"Слово для /rep")
    imgui.InputText("##word", st.text_word)
    
    imgui.Text(u8"Чат для объявления")
    imgui.Combo("##chat", st.combo_chat, st.arr_chat, #st.arr_chat)
    
    imgui.Text(u8"Приз")
    imgui.Combo("##prize", st.combo_priz, st.arr_priz, #st.arr_priz)
    
    local selectedPrizeIdx = st.combo_priz.v + 1
    local isStyle = (selectedPrizeIdx >= 11 and selectedPrizeIdx <= 13)
    
    if not isStyle then
        imgui.Text(u8"Количество (5k, 1kk, 5000)")
        imgui.InputText("##amount", st.text_real)
    else
        imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"Стиль боя: кол-во не требуется")
    end
    
    imgui.Spacing()
    if imgui.Button(u8"Запустить раздачу", imgui.ImVec2(-1, 30)) then
        st.startRazdachaFlag = true
    end
    
    imgui.Spacing()
    imgui.Separator()
    imgui.Text(u8"Лог раздач:")
    
    imgui.BeginChild("##razd_log", imgui.ImVec2(0, 150), true)
    if #st.guiLog == 0 then
        imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1), u8"Пусто")
    else
        for i, entry in ipairs(st.guiLog) do
            imgui.TextWrapped(entry)
        end
    end
    imgui.EndChild()
    
    imgui.Separator()
    imgui.Spacing()
    
    imgui.TextColored(cs.accent, u8">>> АВТО ОТБОР <<<")
    imgui.Spacing()
    
    imgui.Text(u8"Выберите лидерку:")
    
    local otborChoices = {u8"Своё название", u8"Из списка"}
    imgui.Combo(u8"Тип", st.otbor_selectLeader, otborChoices, #otborChoices)
    
    if st.otbor_selectLeader.v == 0 then
        imgui.InputText(u8"Название лидерки", st.otbor_leader_name)
    else
        local fractionNames = {}
        for _, fr in ipairs(st.fractions) do
            table.insert(fractionNames, u8:decode(fr.name))
        end
        imgui.Combo(u8"Фракция", st.otbor_leader_combo, fractionNames, #fractionNames)
    end
    
    imgui.Text(u8"Чат для объявления")
    local chatChoices = {"aad", "o"}
    imgui.Combo("##otbor_chat", st.otbor_chat, chatChoices, #chatChoices)
    
    imgui.Spacing()
    if imgui.Button(u8"Запустить отбор", imgui.ImVec2(-1, 30)) then
        st.startAutoOtborFlag = true
    end
end

-- ===== ВКЛАДКА 6: ВРЕМЕННОЕ ЛИДЕРСТВО =====
local function DrawTab6_Cyber()
    local st = FHA.state
    
    imgui.TextColored(cs.accent, u8">>> ВРЕМЕННОЕ ЛИДЕРСТВО <<<")
    imgui.Spacing()
    
    if st.adminLevel.v < 9 then
        imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8"Доступно с 9 уровня администратора")
        return
    end
    
    imgui.TextWrapped(u8"Выберите фракцию для получения временного лидерства. При нажатии будет отправлена команда /templeader [номер фракции]")
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    imgui.Columns(2, "##templeader_cols", false)
    
    local btnWidth = imgui.GetColumnWidth() - 10
    local btnHeight = 35
    
    for i, fraction in ipairs(FHA.state.fractions) do
        local label = u8:decode(fraction.name) .. " [" .. fraction.id .. "]"
        
        if imgui.Button(label, imgui.ImVec2(btnWidth, btnHeight)) then
            sampSendChat("/templeader " .. fraction.id)
        end
        
        imgui.NextColumn()
    end
    
    imgui.Columns(1)
end

-- ===== ВКЛАДКА 7: ПРАВИЛА =====
local function DrawTab7_Cyber()
    imgui.TextColored(cs.accent, u8">>> ПРАВИЛА СЕРВЕРОВ <<<")
    imgui.Spacing()

    if imgui.Button(u8"ENVY") then 
        FHA.rulesMode = 1 
        FHA_loadEnvyRules()
    end
    imgui.SameLine()
    if imgui.Button(u8"PRIDE") then 
        FHA.rulesMode = 2 
        FHA_loadPrideRules()
    end
    imgui.SameLine()
    if imgui.Button(u8"ANGER") then 
        FHA.rulesMode = 3 
        FHA_loadAngerRules()
    end

    imgui.InputText(u8"Поиск по правилам", FHA.rulesSearch)

    local searchText = FHA.rulesSearch.v
    local searchDecoded = u8:decode(searchText)

    imgui.BeginChild("rules_scroll", imgui.ImVec2(0, 0), true, imgui.WindowFlags.VerticalScrollbar)
    
    if searchDecoded ~= "" then
        imgui.TextColored(imgui.ImVec4(0, 1, 0, 1), u8("Поиск: ") .. u8('"' .. searchDecoded .. '"'))
        
        local function searchInRules(rulesTable, sectionName)
            local foundLines = {}
            for _, line in ipairs(rulesTable) do
                if line:lower():find(searchDecoded:lower(), 1, true) then
                    table.insert(foundLines, line)
                end
            end
            
            if #foundLines > 0 then
                imgui.TextColored(imgui.ImVec4(1.0, 0.7, 0.0, 1.0), u8(sectionName .. ":"))
                for _, line in ipairs(foundLines) do
                    imgui.TextWrapped(u8(line))
                end
            end
        end
        
        if FHA.rulesMode == 1 then
            local found = false
            for i, sectionName in ipairs(FHA.rulesEnvyNames) do
                local rulesTable
                if i == 1 then rulesTable = FHA.rulesEnvy.server
                elseif i == 2 then rulesTable = FHA.rulesEnvy.admin
                elseif i == 3 then rulesTable = FHA.rulesEnvy.aad
                elseif i == 4 then rulesTable = FHA.rulesEnvy.goss
                elseif i == 5 then rulesTable = FHA.rulesEnvy.capt
                elseif i == 6 then rulesTable = FHA.rulesEnvy.bizwar
                end
                
                if rulesTable then
                    searchInRules(rulesTable, sectionName)
                end
            end
            if not found then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8("По запросу '" .. searchDecoded .. "' ничего не найдено"))
            end
        elseif FHA.rulesMode == 2 then
            local found = false
            for i, sectionName in ipairs(FHA.rulesPrideNames) do
                local rulesTable
                if i == 1 then rulesTable = FHA.rulesPride.server
                elseif i == 2 then rulesTable = FHA.rulesPride.admin
                elseif i == 3 then rulesTable = FHA.rulesPride.aad
                elseif i == 4 then rulesTable = FHA.rulesPride.goss
                elseif i == 5 then rulesTable = FHA.rulesPride.capt
                elseif i == 6 then rulesTable = FHA.rulesPride.bizwar
                end
                
                if rulesTable then
                    searchInRules(rulesTable, sectionName)
                end
            end
            if not found then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8("По запросу '" .. searchDecoded .. "' ничего не найдено"))
            end
        else
            local found = false
            for i, sectionName in ipairs(FHA.rulesAngerNames) do
                local rulesTable
                if i == 1 then rulesTable = FHA.rulesAnger.server
                elseif i == 2 then rulesTable = FHA.rulesAnger.admin
                elseif i == 3 then rulesTable = FHA.rulesAnger.aad
                elseif i == 4 then rulesTable = FHA.rulesAnger.goss
                elseif i == 5 then rulesTable = FHA.rulesAnger.capt
                elseif i == 6 then rulesTable = FHA.rulesAnger.bizwar
                end
                
                if rulesTable then
                    searchInRules(rulesTable, sectionName)
                end
            end
            if not found then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0, 1), u8("По запросу '" .. searchDecoded .. "' ничего не найдено"))
            end
        end
    else
        if FHA.rulesMode == 1 then
            local sections = {
                {title = FHA.rulesEnvyNames[1], content = FHA.rulesEnvy.server},
                {title = FHA.rulesEnvyNames[2], content = FHA.rulesEnvy.admin},
                {title = FHA.rulesEnvyNames[3], content = FHA.rulesEnvy.aad},
                {title = FHA.rulesEnvyNames[4], content = FHA.rulesEnvy.goss},
                {title = FHA.rulesEnvyNames[5], content = FHA.rulesEnvy.capt},
                {title = FHA.rulesEnvyNames[6], content = FHA.rulesEnvy.bizwar}
            }
            
            for sectionIndex, section in ipairs(sections) do
                local is_open, _ = imgui.CollapsingHeader(u8(section.title), FHA.rulesSectionStates[sectionIndex])
                FHA.rulesSectionStates[sectionIndex] = is_open
                
                if is_open then
                    imgui.BeginChild("##rules_envy_" .. sectionIndex, imgui.ImVec2(0, 0), false)
                    for _, line in ipairs(section.content) do
                        imgui.TextWrapped(u8(line))
                    end
                    imgui.EndChild()
                    imgui.Spacing()
                end
            end
        elseif FHA.rulesMode == 2 then
            local sections = {
                {title = FHA.rulesPrideNames[1], content = FHA.rulesPride.server},
                {title = FHA.rulesPrideNames[2], content = FHA.rulesPride.admin},
                {title = FHA.rulesPrideNames[3], content = FHA.rulesPride.aad},
                {title = FHA.rulesPrideNames[4], content = FHA.rulesPride.goss},
                {title = FHA.rulesPrideNames[5], content = FHA.rulesPride.capt},
                {title = FHA.rulesPrideNames[6], content = FHA.rulesPride.bizwar}
            }
            
            for sectionIndex, section in ipairs(sections) do
                local is_open, _ = imgui.CollapsingHeader(u8(section.title), FHA.rulesSectionStates[sectionIndex])
                FHA.rulesSectionStates[sectionIndex] = is_open
                
                if is_open then
                    imgui.BeginChild("##rules_pride_" .. sectionIndex, imgui.ImVec2(0, 0), false)
                    for _, line in ipairs(section.content) do
                        imgui.TextWrapped(u8(line))
                    end
                    imgui.EndChild()
                    imgui.Spacing()
                end
            end
        else
            local sections = {
                {title = FHA.rulesAngerNames[1], content = FHA.rulesAnger.server},
                {title = FHA.rulesAngerNames[2], content = FHA.rulesAnger.admin},
                {title = FHA.rulesAngerNames[3], content = FHA.rulesAnger.aad},
                {title = FHA.rulesAngerNames[4], content = FHA.rulesAnger.goss},
                {title = FHA.rulesAngerNames[5], content = FHA.rulesAnger.capt},
                {title = FHA.rulesAngerNames[6], content = FHA.rulesAnger.bizwar}
            }
            
            for sectionIndex, section in ipairs(sections) do
                local is_open, _ = imgui.CollapsingHeader(u8(section.title), FHA.rulesSectionStates[sectionIndex])
                FHA.rulesSectionStates[sectionIndex] = is_open
                
                if is_open then
                    imgui.BeginChild("##rules_anger_" .. sectionIndex, imgui.ImVec2(0, 0), false)
                    for _, line in ipairs(section.content) do
                        imgui.TextWrapped(u8(line))
                    end
                    imgui.EndChild()
                    imgui.Spacing()
                end
            end
        end
    end
    
    imgui.EndChild()
end

-- ===== ВКЛАДКА 8: ОБНОВЛЕНИЯ =====
local function DrawTab8_Cyber()
    imgui.TextColored(cs.accent, u8">>> ОБНОВЛЕНИЯ <<<")
    imgui.Spacing()
    imgui.PushTextWrapPos(imgui.GetWindowWidth() - 20)
    imgui.TextWrapped(u8(
        "FastHelperAdm История обновлений:\n\n" ..
        "v1.0 — Релиз\n" ..
        "v1.2 — Фикс багов\n" ..
        "v1.4 — Улучшения\n" ..
        "v1.5 — Авто Раздача\n" ..
        "v1.55 — Фикс багов 2\n" ..
        "v1.60 — Авто Пожелание + Ответы на Репорты + Авто-команды через 10 сек\n" ..
        "v1.70 — Добавлена выдача себе лидерки + Добавлено авто мероприятие + Фикс неких багов\n" ..
        "v1.75 — Добавлен Авто Отбор и добавлен визуал для меню\n" ..
        "v1.80 — Фикс Багов 3\n" ..
        "v1.9 — Добавлен Трейсер Пуль, ClickWarp (Телепорт на колёсико мыши) + Выбор пола м/ж в настройках меню + Фикс Багов + Авто Пожелание GG\n" ..
        "v2.0 — Возвращена вкладка Ответы на Репорты + Улучшенная система ответов + Добавлена вкладка Правила Серверов (Envy/Pride/Anger) с поиском + Добавлена функция Невидимости + Добавлена функция AirBrake + Фикс Автораздачи\n" ..
        "v2.1 — Добавлен Авто Alogin (6+), GM Car (GM + Визуал), Новое UI меню, Покраска Гетто, Фикс Автораздачи#2, Speedhack, WallHack, Фикс скелета при открытом меню, Kill List ID, Admin Render, ZZVeh (обход зелёной зоны для /veh)\n"
    ));
    imgui.PopTextWrapPos()
end

-- ===== ВКЛАДКА 9: ОБ АВТОРЕ =====
local function DrawTab9_Cyber()
    imgui.TextColored(cs.accent, u8">>> ОБ АВТОРЕ <<<")
    imgui.Spacing()
    imgui.TextWrapped(
        u8("FastHelperAdm v2.1\nАвтор: Alim Akimov\n@waldemar03")
    )
end

-- ===== ВКЛАДКА 10: ПОКРАСКА ГЕТТО =====
local function DrawTab10_Cyber()
    local st = FHA.state
    
    imgui.TextColored(cs.accent, u8">>> ПОКРАСКА ГЕТТО <<<")
    imgui.Spacing()
    
    if not st.gz_initialized then
        st.gz_zones = GZ_getAllGangZones()
        st.gz_initialized = true
    end
    
    local title = "=== AUTO REFORM ==="
    local titleWidth = imgui.CalcTextSize(title).x
    imgui.SetCursorPosX((imgui.GetWindowWidth() - titleWidth) / 2)
    imgui.TextColored(imgui.ImVec4(0.4, 0.8, 1.0, 1), title)
    
    imgui.Spacing()
    
    local buttonsWidth = 260
    local startX = (imgui.GetWindowWidth() - buttonsWidth) / 2
    imgui.SetCursorPosX(startX)
    
    if st.gz_autoReform.active then
        if st.gz_autoReform.paused then
            if imgui.Button(u8("ПРОДОЛЖИТЬ"), imgui.ImVec2(120, 30)) then GZ_pauseAutoReform() end
        else
            if imgui.Button(u8("ПАУЗА"), imgui.ImVec2(120, 30)) then GZ_pauseAutoReform() end
        end
        imgui.SameLine()
        if imgui.Button(u8("СТОП"), imgui.ImVec2(120, 30)) then GZ_stopAutoReform() end
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(0, 1, 0, 1), string.format("Progress: %d/%d", st.gz_autoReform.currentIndex - 1, #allReformZones))
    else
        if imgui.Button(u8("СТАРТ"), imgui.ImVec2(120, 30)) then
            st.gz_showConfirm = true
        end
        imgui.SameLine()
        if imgui.Button(u8("UNDO"), imgui.ImVec2(120, 30)) then 
            lua_thread.create(GZ_undoReform) 
        end
    end
    
    imgui.Separator()
    imgui.Spacing()
    
    imgui.Columns(2, "##gz_columns", false)
    imgui.SetColumnWidth(0, 220)
    
    imgui.BeginChild("##gz_info", imgui.ImVec2(0, 0), true)
    
    imgui.TextColored(imgui.ImVec4(0.4, 0.8, 1.0, 1), u8"GANG ZONES:")
    imgui.Separator()
    imgui.TextColored(imgui.ImVec4(0.8, 0.2, 0.8, 1), u8"Ballas - Purple (25)")
    imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.0, 1), u8"Vagos - Yellow (25)")
    imgui.TextColored(imgui.ImVec4(0.2, 0.8, 0.2, 1), u8"Grove - Green (25)")
    imgui.TextColored(imgui.ImVec4(0.2, 0.4, 0.8, 1), u8"Rifa - Blue (25)")
    imgui.TextColored(imgui.ImVec4(0.2, 0.7, 0.9, 1), u8"Aztec - Cyan (24)")
    imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1), u8"Neutral - White (9)")
    imgui.Separator()
    
    local counts = {ballas = 0, vagos = 0, grove = 0, rifa = 0, aztec = 0, neutral = 0}
    for _, zone in ipairs(st.gz_zones) do
        if not zone.isEmpty and counts[zone.gang] then 
            counts[zone.gang] = counts[zone.gang] + 1 
        end
    end
    imgui.Text(string.format("Now: B:%d V:%d G:%d R:%d A:%d N:%d", 
        counts.ballas, counts.vagos, counts.grove, counts.rifa, counts.aztec, counts.neutral))
    imgui.Separator()
    
    if st.gz_autoReform.active then
        if st.gz_autoReform.paused then
            imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), string.format("PAUSED %d/%d", 
                st.gz_autoReform.currentIndex - 1, #allReformZones))
        else
            imgui.TextColored(imgui.ImVec4(0, 1, 0, 1), string.format("Reform: %d/%d", 
                st.gz_autoReform.currentIndex - 1, #allReformZones))
        end
    end
    
    if next(st.gz_undoState) ~= nil then 
        imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"UNDO ready!") 
    end
    
    if st.gz_capZoneId then
        local zone = GZ_getZoneById(st.gz_capZoneId)
        if zone then
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(1, 0.3, 0.3, 1), u8"CAPTURE!")
            imgui.Text(string.format("Zone %d: %s -> %s", 
                st.gz_capZoneId, GZ_getDisplayName(zone.gang), GZ_getDisplayName(st.gz_capAttacker)))
        end
    end
    
    imgui.EndChild()
    
    imgui.NextColumn()
    
    imgui.BeginChild("##gz_map", imgui.ImVec2(0, 0), true)
    
    local buttonSize = 28
    for rowIndex, row in ipairs(zoneGridOrder) do
        for colIndex, zoneId in ipairs(row) do
            local zone = GZ_getZoneById(zoneId)
            if zone then
                local isUnderCap = GZ_isZoneUnderCapture(zoneId)
                local red, green, blue
                if zone.isEmpty then 
                    red, green, blue = 0.3, 0.3, 0.3
                elseif isUnderCap then 
                    red, green, blue = 1.0, 0.2, 0.2
                else 
                    red, green, blue = GZ_getDisplayColor(zone.gang) 
                end
                
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(red, green, blue, 0.85))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(red, green, blue, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(red, green, blue, 0.7))
                
                if imgui.Button(tostring(zoneId), imgui.ImVec2(buttonSize, buttonSize)) then
                    if not zone.isEmpty then GZ_teleportToZone(zoneId) end
                end
                
                if imgui.IsItemClicked(1) and not zone.isEmpty then 
                    st.gz_selectedZone = zoneId
                    imgui.OpenPopup("##gz_paint") 
                end
                
                if imgui.IsItemHovered() then
                    imgui.BeginTooltip()
                    imgui.Text(string.format("Zone ID: %d", zoneId))
                    imgui.Text(string.format("Gang: %s", GZ_getDisplayName(zone.gang)))
                    imgui.Text(u8"ЛКМ - Телепорт")
                    imgui.Text(u8"ПКМ - Покрасить")
                    if isUnderCap then 
                        local att = GZ_getZoneAttacker(zoneId)
                        if att then 
                            imgui.TextColored(imgui.ImVec4(1, 0.3, 0.3, 1), string.format("CAPTURE! -> %s", GZ_getDisplayName(att))) 
                        end
                    end
                    imgui.EndTooltip()
                end
                
                imgui.PopStyleColor(3)
                if colIndex < #row then imgui.SameLine(0, 1) end
            end
        end
    end
    
    if imgui.BeginPopup("##gz_paint") then
        imgui.Text(string.format("Paint Zone %d", st.gz_selectedZone))
        imgui.Separator()
        for _, gName in ipairs({"ballas", "vagos", "grove", "rifa", "aztec", "neutral"}) do
            local g = gangZones[gName]
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(g.displayColor[1], g.displayColor[2], g.displayColor[3], 0.8))
            if imgui.Button(g.name, imgui.ImVec2(100, 25)) then
                imgui.CloseCurrentPopup()
                lua_thread.create(function() GZ_paintZoneWithReturn(st.gz_selectedZone, g.colorCode, g.name) end)
            end
            imgui.PopStyleColor(1)
        end
        imgui.EndPopup()
    end
    
    imgui.EndChild()
    imgui.Columns(1)
    
    if st.gz_showConfirm then
        imgui.OpenPopup("##gz_confirm")
        st.gz_showConfirm = false
    end
    
    if imgui.BeginPopupModal("##gz_confirm", nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse) then
        imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"Start Auto Reform?")
        imgui.Spacing()
        imgui.Text(string.format("%d zones will be repainted", #allReformZones))
        imgui.TextDisabled(u8"Order: Ballas > Vagos > Grove > Rifa > Aztec > Neutral")
        imgui.Spacing()
        
        if imgui.Button(u8("YES, START"), imgui.ImVec2(120, 35)) then
            imgui.CloseCurrentPopup()
            GZ_startAutoReform()
        end
        imgui.SameLine()
        if imgui.Button(u8("CANCEL"), imgui.ImVec2(120, 35)) then
            imgui.CloseCurrentPopup()
        end
        
        imgui.EndPopup()
    end
end

-- ===== ОСНОВНОЕ МЕНЮ =====
local function DrawCyberMenu()
    if not menu.visible then return end
    
    menu.screenW, menu.screenH = getScreenResolution()
    menu.gearAngle = menu.gearAngle + 0.015
    menu.timePulse = menu.timePulse + 0.05
    
    updateParticles()
    
    local ww, wh = menu.windowSize.x, menu.windowSize.y
    
    if menu.windowPos.x < 0 then
        menu.windowPos = imgui.ImVec2(
            (menu.screenW - ww) * 0.5,
            (menu.screenH - wh) * 0.5
        )
    end
    
    if FHA.state.menuColor.v == 0 then FHA_ApplyRedStyle()
    elseif FHA.state.menuColor.v == 1 then FHA_ApplyGreenStyle()
    elseif FHA.state.menuColor.v == 2 then FHA_ApplyBlueStyle()
    elseif FHA.state.menuColor.v == 3 then FHA_ApplyOrangeStyle()
    elseif FHA.state.menuColor.v == 4 then FHA_ApplyYellowStyle()
    elseif FHA.state.menuColor.v == 5 then FHA_ApplyCyanStyle()
    elseif FHA.state.menuColor.v == 6 then FHA_ApplyPurpleStyle()
    elseif FHA.state.menuColor.v == 7 then FHA_ApplyRainbowStyle()
    end
    UpdateCyberColors()
    
    local flags = 1 + 2 + 8 + 16 + 32
    
    imgui.SetNextWindowPos(menu.windowPos, imgui.Cond.Always)
    imgui.SetNextWindowSize(menu.windowSize, imgui.Cond.Always)
    
    imgui.Begin("##cybermenu", nil, flags)
    
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local ws = imgui.GetWindowSize()
    menu.windowPos = wp
    menu.windowSize = ws
    local mousePos = imgui.GetMousePos()
    
    dl:AddRectFilled(imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x + ws.x, wp.y + ws.y),
        U32(cs.bgBot), 14)
    
    for i = 1, #particles do
        local p = particles[i]
        local px = wp.x + p.x
        local py = wp.y + p.y
        local alpha = p.alpha * (1 - p.life / p.maxLife)
        if alpha > 0.02 then
            dl:AddCircleFilled(
                imgui.ImVec2(px, py),
                p.size,
                U32(imgui.ImVec4(cs.particleCol.x, cs.particleCol.y, cs.particleCol.z, alpha))
            )
        end
    end
    
    for i = 1, 3 do
        dl:AddRect(
            imgui.ImVec2(wp.x - i, wp.y - i),
            imgui.ImVec2(wp.x + ws.x + i, wp.y + ws.y + i),
            U32(imgui.ImVec4(cs.border.x, cs.border.y, cs.border.z, 0.4/i + math.sin(menu.timePulse)*0.1)),
            14, 15, 1.5)
    end
    
    imgui.SetCursorScreenPos(imgui.ImVec2(wp.x + ws.x - 30, wp.y + 5))
    if imgui.Button("X", imgui.ImVec2(22, 20)) then
        menu.visible = false
        FHA.whPaused = false
        ShowCursor(false)
        imgui.Process = false
    end
    
    local dragAreaMin = imgui.ImVec2(wp.x, wp.y)
    local dragAreaMax = imgui.ImVec2(wp.x + ws.x - 35, wp.y + 28)
    
    if imgui.IsMouseHoveringRect(dragAreaMin, dragAreaMax) then
        if imgui.IsMouseDown(0) then
            if not menu.dragging then
                menu.dragging = true
                menu.dragOffset = imgui.ImVec2(mousePos.x - wp.x, mousePos.y - wp.y)
            end
        end
    end
    
    if menu.dragging then
        if imgui.IsMouseDown(0) then
            menu.windowPos = imgui.ImVec2(mousePos.x - menu.dragOffset.x, mousePos.y - menu.dragOffset.y)
        else
            menu.dragging = false
        end
    end
    
    local resizeHandlePos = imgui.ImVec2(wp.x + ws.x - 8, wp.y)
    local resizeHandleSize = imgui.ImVec2(8, ws.y)
    
    if imgui.IsMouseHoveringRect(resizeHandlePos, imgui.ImVec2(resizeHandlePos.x + resizeHandleSize.x, resizeHandlePos.y + resizeHandleSize.y)) then
        imgui.SetMouseCursor(imgui.MouseCursor.ResizeEW)
        if imgui.IsMouseDown(0) then
            local newWidth = math.max(menu.minWindowSize.x, math.min(menu.maxWindowSize.x, mousePos.x - wp.x))
            menu.windowSize = imgui.ImVec2(newWidth, menu.windowSize.y)
        end
    end
    
    local resizeHandlePosH = imgui.ImVec2(wp.x, wp.y + ws.y - 8)
    local resizeHandleSizeH = imgui.ImVec2(ws.x, 8)
    
    if imgui.IsMouseHoveringRect(resizeHandlePosH, imgui.ImVec2(resizeHandlePosH.x + resizeHandleSizeH.x, resizeHandlePosH.y + resizeHandleSizeH.y)) then
        imgui.SetMouseCursor(imgui.MouseCursor.ResizeNS)
        if imgui.IsMouseDown(0) then
            local newHeight = math.max(menu.minWindowSize.y, math.min(menu.maxWindowSize.y, mousePos.y - wp.y))
            menu.windowSize = imgui.ImVec2(menu.windowSize.x, newHeight)
        end
    end
    
    DrawLogoAndTime()
    
    imgui.Columns(2, "##maincols", false)
    imgui.SetColumnWidth(0, 175)
    
    local tabs = {
        u8"Основное",
        u8"Настройки", 
        u8"Репорты", 
        u8"Функции", 
        u8"Авто",
        u8"Врем. Лидер",
        u8"Правила",
        u8"Обновления",
        u8"Об авторе",
        u8"Покраска Гетто"
    }
    
    for i, name in ipairs(tabs) do
        if TabButton(name, menu.selectedTab == i) then
            menu.selectedTab = i
        end
        imgui.Spacing()
    end
    
    imgui.NextColumn()
    
    imgui.Spacing()
    imgui.Spacing()
    
    imgui.BeginChild("##content_scroll", imgui.ImVec2(0, 0), true, imgui.WindowFlags.VerticalScrollbar)
    
    if menu.selectedTab == 1 then
        DrawTab1_Cyber()
    elseif menu.selectedTab == 2 then
        DrawTab2_Cyber()
    elseif menu.selectedTab == 3 then
        DrawTab3_Cyber()
    elseif menu.selectedTab == 4 then
        DrawTab4_Cyber()
    elseif menu.selectedTab == 5 then
        DrawTab5_Cyber()
    elseif menu.selectedTab == 6 then
        DrawTab6_Cyber()
    elseif menu.selectedTab == 7 then
        DrawTab7_Cyber()
    elseif menu.selectedTab == 8 then
        DrawTab8_Cyber()
    elseif menu.selectedTab == 9 then
        DrawTab9_Cyber()
    elseif menu.selectedTab == 10 then
        DrawTab10_Cyber()
    end
    
    imgui.EndChild()
    
    imgui.Columns(1)
    
    dl:AddRectFilled(
        imgui.ImVec2(wp.x+10, wp.y+ws.y-4),
        imgui.ImVec2(wp.x+ws.x-10, wp.y+ws.y-2),
        U32(imgui.ImVec4(cs.neonGlow.x, cs.neonGlow.y, cs.neonGlow.z, 0.5 + math.sin(menu.timePulse)*0.2)),
        2)
    
    menu.savedWpX = wp.x
    menu.savedWpY = wp.y
    menu.savedWsX = ws.x
    menu.savedWsY = ws.y
    menu.savedMouseX = mousePos.x
    menu.savedMouseY = mousePos.y
    
    imgui.End()
    
    if not menu.visible then return end
    
    local sx = menu.savedWpX
    local sy = menu.savedWpY
    local sw = menu.savedWsX
    local sh = menu.savedWsY
    local mx = menu.savedMouseX
    local my = menu.savedMouseY
    
    if not sx or not sy or not sw or not sh then return end
    
    local cornerSize = 20
    local cornerMinX = sx + sw - cornerSize
    local cornerMinY = sy + sh - cornerSize
    local cornerMaxX = sx + sw
    local cornerMaxY = sy + sh
    
    local isHoveringCorner = (mx >= cornerMinX and mx <= cornerMaxX and my >= cornerMinY and my <= cornerMaxY)
    
    if isHoveringCorner then
        if isKeyDown(1) and not menu.resizeCornerDragging then
            menu.resizeCornerDragging = true
        end
    end
    
    if menu.resizeCornerDragging then
        if isKeyDown(1) then
            local newWidth = math.max(menu.minWindowSize.x, math.min(menu.maxWindowSize.x, mx - sx))
            local newHeight = math.max(menu.minWindowSize.y, math.min(menu.maxWindowSize.y, my - sy))
            menu.windowSize = imgui.ImVec2(newWidth, newHeight)
        else
            menu.resizeCornerDragging = false
        end
    end
    
    local triAlpha = (isHoveringCorner or menu.resizeCornerDragging) and 255 or 180
    
    renderDrawPolygon(sx + sw, sy + sh, cornerSize, cornerSize, 0, 3, 
        join_argb(140, 140, 140, triAlpha))
    
    local outlineColor = join_argb(255, 255, 255, triAlpha)
    renderDrawLine(sx + sw - cornerSize, sy + sh, sx + sw, sy + sh - cornerSize, 1, outlineColor)
    renderDrawLine(sx + sw - cornerSize, sy + sh, sx + sw, sy + sh, 1, outlineColor)
    renderDrawLine(sx + sw, sy + sh - cornerSize, sx + sw, sy + sh, 1, outlineColor)
    
    for i = 1, 2 do
        local offset = 3 + i * 4
        local lineColor = join_argb(80, 80, 80, triAlpha)
        renderDrawLine(sx + sw - offset, sy + sh, sx + sw, sy + sh - offset, 1, lineColor)
    end
end

-- ===== ФУНКЦИИ ДЛЯ ВКЛАДОК =====
function FHA_DrawTab1() DrawTab1_Cyber() end
function FHA_DrawTab2() DrawTab2_Cyber() end
function FHA_DrawTab3() DrawTab3_Cyber() end
function FHA_DrawTab4() DrawTab4_Cyber() end
function FHA_DrawTab5() DrawTab5_Cyber() end
function FHA_DrawTab6() DrawTab6_Cyber() end
function FHA_DrawTab7() DrawTab7_Cyber() end
function FHA_DrawTab8() DrawTab8_Cyber() end
function FHA_DrawTab9() DrawTab9_Cyber() end
function FHA_DrawTab10() DrawTab10_Cyber() end
function FHA_DrawTab11() end

function FHA_DrawMainMenu() end

-- ===== ОБРАБОТЧИКИ МЕРОПРИЯТИЙ =====
function FHA_doAutoMP()
    local st = FHA.state
    local mpName

    if st.mp_selectEvent.v == 0 then
        mpName = u8:decode(st.mp_names[st.combo_mp_name.v + 1])
    else
        if st.mp_custom_name.v ~= "" then
            mpName = u8:decode(st.mp_custom_name.v)
        else
            sampAddChatMessage("{FF4444}[MP] Укажите название мероприятия", -1)
            return
        end
    end

    local prizeText = u8:decode(st.mp_prize_text.v)
    if prizeText == "" then
        sampAddChatMessage("{FF4444}[MP] Укажите приз мероприятия", -1)
        return
    end

    st.mpPrefixSent = false
    
    if not st.mpPrefixSent then
        sampSendChat("/a z aad")
        st.mpPrefixSent = true
        wait(1000)
    end
    
    sampSendChat('/aad MP | Уважаемые игроки, сейчас пройдет мероприятие "'..mpName..'"')
    wait(1000)
    sampSendChat('/aad MP | Приз: '..prizeText)
    wait(1000)
    sampSendChat('/aad MP | Желающие /gomp')
    wait(1000)

    st.mpAutoStep = 1
    sampSendChat("/mp")
end

function FHA_doAutoOtbor()
    local st = FHA.state
    local leaderNameCP1251 = ""

    if st.otbor_selectLeader.v == 1 then
        local selectedFractionIndex = st.otbor_leader_combo.v + 1
        if selectedFractionIndex >= 1 and selectedFractionIndex <= #st.fractions then
            leaderNameCP1251 = u8:decode(st.fractions[selectedFractionIndex].name)
        else
            sampAddChatMessage("{FF4444}[Отбор] Ошибка: Неверный индекс фракции в списке.", -1)
            return
        end
    else
        leaderNameCP1251 = u8:decode(st.otbor_leader_name.v) 
    end

    leaderNameCP1251 = leaderNameCP1251:gsub("^%s*(.-)%s*$", "%1") 

    if leaderNameCP1251 == "" then
        sampAddChatMessage("{FF4444}[Отбор] Укажите название лидерки", -1)
        return
    end

    local chatCmd = (st.otbor_chat.v == 0 and "aad" or "o")
    
    st.otborPrefixSent = false

    if not st.otborPrefixSent then
        sampSendChat("/a z " .. chatCmd)
        st.otborPrefixSent = true
        wait(1000)
    end
    
    sampSendChat('/'..chatCmd..' ОТБОР | Сейчас пройдёт отбор на лидера "'..leaderNameCP1251..'"')
    wait(1000)

    sampSendChat('/'..chatCmd..' ОТБОР | Критерий: 2+ часов на аккаунте, иметь вк')
    wait(1000)

    sampSendChat('/'..chatCmd..' ОТБОР | Желающий /gomp')
    wait(1000)

    st.otborRunning = true
    sampSendChat("/mp")
end

function FHA_doRazdacha()
    local st = FHA.state
    
    if st.razdInProgress then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Раздача уже запущена! Дождитесь окончания.", -1)
        return
    end
    
    local prizeIdx = st.combo_priz.v + 1
    local pName = u8:decode(st.arr_priz[prizeIdx])
    local isStyle = (prizeIdx >= 11 and prizeIdx <= 13)
    local amount = isStyle and 50000 or (FHA_parseAmount(st.text_real.v) or 0)
    
    if st.text_word.v == "" or st.text_word.v == " " then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Укажите слово для /rep", -1)
        return
    end
    
    if not isStyle and (amount == nil or amount <= 0) then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Укажите корректное количество (пример: 5k, 1kk, 5000)", -1)
        return
    end
    
    local txt
    if isStyle then
        txt = "РАЗДАЧА | Кто первый напишет /rep "..u8:decode(st.text_word.v).." получит стиль \""..pName.."\""
    else
        txt = "РАЗДАЧА | Кто первый напишет /rep "..u8:decode(st.text_word.v).." получит "..formatMoneySmart(amount).." "..pName
    end
    
    sampSendChat('/'..st.arr_chat[st.combo_chat.v+1]..' '..txt)
    
    st.razdStartTime = os.clock()
    st.razdWord = u8:decode(st.text_word.v)
    st.razdPrizeName = pName
    st.razdPrizeAmount = amount
    st.razdIsStyle = isStyle
    
    FHA_resetRazdacha()
    st.razdInProgress = true
    st.active_razd = true
    st.active_razd2 = false
    st.razd_player_id = -1
    st.razdTimeout = os.clock() + 30
    
    sampAddChatMessage("{33CCFF}[FastHelperAdm] Раздача запущена! Ожидание ответа 30 секунд...", -1)
end

-- ===== AIRBRAKE ФУНКЦИИ =====
local airBrkCoords = {0, 0, 0}

function FHA_toggleAirBrake()
    local st = FHA.state
    
    if not st.airbrakeEnabled.v then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Функция AirBrake не активирована в меню скрипта.", -1)
        return
    end
    if st.adminLevel.v < 6 then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Для использования AirBrake требуется уровень администратора 6+.", -1)
        return
    end

    st.airbrakeActive = not st.airbrakeActive
    
    if st.airbrakeActive then
        printStringNow("~P~Airbrake ~G~Active", 3000)
    else
        printStringNow("~P~Airbrake ~R~OFF", 3000)
    end
    
    if not st.airbrakeActive then return end
    
    airBrkCoords = {getCharCoordinates(PLAYER_PED)}
    if not isCharInAnyCar(PLAYER_PED) then 
        airBrkCoords[3] = airBrkCoords[3] - 1 
    end
    
    lua_thread.create(FHA_airbrakeThread)
end

function FHA_airbrakeThread()
    local st = FHA.state
    
    while st.airbrakeActive and not FHA.isUnloading do
        wait(0)
        
        local speed = st.airbrakeSpeed.v
        
        if isCharInAnyCar(PLAYER_PED) then 
            setCarHeading(getCarCharIsUsing(PLAYER_PED), getHeadingFromVector2d(select(1, getActiveCameraPointAt()) - select(1, getActiveCameraCoordinates()), select(2, getActiveCameraPointAt()) - select(2, getActiveCameraCoordinates()))) 
        else 
            setCharHeading(PLAYER_PED, getHeadingFromVector2d(select(1, getActiveCameraPointAt()) - select(1, getActiveCameraCoordinates()), select(2, getActiveCameraPointAt()) - select(2, getActiveCameraCoordinates()))) 
        end

        if sampIsCursorActive() then 
            setCharCoordinates(PLAYER_PED, airBrkCoords[1], airBrkCoords[2], airBrkCoords[3])
            goto continue 
        end

        if isKeyDown(VK_SPACE) or isKeyDown(VK_UP) then 
            airBrkCoords[3] = airBrkCoords[3] + speed / 2 
        elseif (isKeyDown(VK_LSHIFT) or isKeyDown(VK_DOWN)) and airBrkCoords[3] > -95.0 then 
            airBrkCoords[3] = airBrkCoords[3] - speed / 2 
        end

        if isKeyDown(VK_W) then 
            airBrkCoords[1] = airBrkCoords[1] + speed * math.sin(-math.rad(getCharHeading(PLAYER_PED))) 
            airBrkCoords[2] = airBrkCoords[2] + speed * math.cos(-math.rad(getCharHeading(PLAYER_PED))) 
        elseif isKeyDown(VK_S) then 
            airBrkCoords[1] = airBrkCoords[1] - speed * math.sin(-math.rad(getCharHeading(PLAYER_PED))) 
            airBrkCoords[2] = airBrkCoords[2] - speed * math.cos(-math.rad(getCharHeading(PLAYER_PED))) 
        end
        
        if isKeyDown(VK_A) then 
            airBrkCoords[1] = airBrkCoords[1] - speed * math.sin(-math.rad(getCharHeading(PLAYER_PED) - 90)) 
            airBrkCoords[2] = airBrkCoords[2] - speed * math.cos(-math.rad(getCharHeading(PLAYER_PED) - 90)) 
        elseif isKeyDown(VK_D) then 
            airBrkCoords[1] = airBrkCoords[1] + speed * math.sin(-math.rad(getCharHeading(PLAYER_PED) - 90)) 
            airBrkCoords[2] = airBrkCoords[2] + speed * math.cos(-math.rad(getCharHeading(PLAYER_PED) - 90)) 
        end

        ::continue::
        setCharCoordinates(PLAYER_PED, airBrkCoords[1], airBrkCoords[2], airBrkCoords[3])
    end
end

function FHA_onWindowMessage(msg, wparam, lparam) 
    if(msg == 0x100 or msg == 0x101) then 
        if lparam == 3538945 and not sampIsChatInputActive() and not sampIsDialogActive() and not sampIsCursorActive() then 
            local st = FHA.state
            
            if not st.airbrakeEnabled.v or st.adminLevel.v < 6 then return end
            
            FHA_toggleAirBrake()
        end 
    end 
end

-- ===== CLICKWARP ФУНКЦИИ =====
function FHA_initializeClickWarp()
    FHA.state.clickWarpFont = renderCreateFont("Tahoma", 10, 1 + 8)
    FHA.state.clickWarpFont2 = renderCreateFont("Arial", 8, 2 + 8)
end

function FHA_rotateCarAroundUpAxis(car, vec)
    local mat = Matrix3X3(FHA_getVehicleRotationMatrix(car))
    local rotAxis = Vector3D(mat.up:get())
    vec:normalize()
    rotAxis:normalize()
    local theta = math.acos(rotAxis:dotProduct(vec))
    if theta ~= 0 then
        rotAxis:crossProduct(vec)
        rotAxis:normalize()
        rotAxis:zeroNearZero()
        mat = mat:rotate(rotAxis, -theta)
    end
    FHA_setVehicleRotationMatrix(car, mat:get())
end

function FHA_readFloatArray(ptr, idx)
    return representIntAsFloat(readMemory(ptr + idx * 4, 4, false))
end

function FHA_writeFloatArray(ptr, idx, value)
    writeMemory(ptr + idx * 4, 4, representFloatAsInt(value), false)
end

function FHA_getVehicleRotationMatrix(car)
    local entityPtr = getCarPointer(car)
    if entityPtr ~= 0 then
        local mat = readMemory(entityPtr + 0x14, 4, false)
        if mat ~= 0 then
            local rx, ry, rz, fx, fy, fz, ux, uy, uz
            rx = FHA_readFloatArray(mat, 0)
            ry = FHA_readFloatArray(mat, 1)
            rz = FHA_readFloatArray(mat, 2)

            fx = FHA_readFloatArray(mat, 4)
            fy = FHA_readFloatArray(mat, 5)
            fz = FHA_readFloatArray(mat, 6)

            ux = FHA_readFloatArray(mat, 8)
            uy = FHA_readFloatArray(mat, 9)
            uz = FHA_readFloatArray(mat, 10)
            return rx, ry, rz, fx, fy, fz, ux, uy, uz
        end
    end
end

function FHA_setVehicleRotationMatrix(car, rx, ry, rz, fx, fy, fz, ux, uy, uz)
    local entityPtr = getCarPointer(car)
    if entityPtr ~= 0 then
        local mat = readMemory(entityPtr + 0x14, 4, false)
        if mat ~= 0 then
            FHA_writeFloatArray(mat, 0, rx)
            FHA_writeFloatArray(mat, 1, ry)
            FHA_writeFloatArray(mat, 2, rz)

            FHA_writeFloatArray(mat, 4, fx)
            FHA_writeFloatArray(mat, 5, fy)
            FHA_writeFloatArray(mat, 6, fz)

            FHA_writeFloatArray(mat, 8, ux)
            FHA_writeFloatArray(mat, 9, uy)
            FHA_writeFloatArray(mat, 10, uz)
        end
    end
end

function FHA_displayVehicleName(x, y, gxt)
    x, y = convertWindowScreenCoordsToGameScreenCoords(x, y)
    useRenderCommands(true)
    setTextWrapx(640.0)
    setTextProportional(true)
    setTextJustify(false)
    setTextScale(0.33, 0.8)
    setTextDropshadow(0, 0, 0, 0, 0)
    setTextColour(255, 255, 255, 230)
    setTextEdge(1, 0, 0, 0, 100)
    setTextFont(1)
    displayText(x, y, gxt)
end

function FHA_createPointMarker(x, y, z)
    if FHA.state.pointMarker then
        removeUser3dMarker(FHA.state.pointMarker)
    end
    FHA.state.pointMarker = createUser3dMarker(x, y, z + 0.3, 4)
end

function FHA_removePointMarker()
    if FHA.state.pointMarker then
        removeUser3dMarker(FHA.state.pointMarker)
        FHA.state.pointMarker = nil
    end
end

function FHA_getCarFreeSeat(car)
    if doesCharExist(getDriverOfCar(car)) then
        local maxPassengers = getMaximumNumberOfPassengers(car)
        for i = 0, maxPassengers do
            if isCarPassengerSeatFree(car, i) then
                return i + 1
            end
        end
        return nil
    else
        return 0
    end
end

function FHA_jumpIntoCar(car)
    local seat = FHA_getCarFreeSeat(car)
    if not seat then return false end
    if seat == 0 then warpCharIntoCar(PLAYER_PED, car)
    else warpCharIntoCarAsPassenger(PLAYER_PED, car, seat - 1)
    end
    restoreCameraJumpcut()
    return true
end

function FHA_setEntityCoordinates(entityPtr, x, y, z)
  if entityPtr ~= 0 then
    local matrixPtr = readMemory(entityPtr + 0x14, 4, false)
    if matrixPtr ~= 0 then
      local posPtr = matrixPtr + 0x30
      writeMemory(posPtr + 0, 4, representFloatAsInt(x), false)
      writeMemory(posPtr + 4, 4, representFloatAsInt(y), false)
      writeMemory(posPtr + 8, 4, representFloatAsInt(z), false)
    end
  end
end

function FHA_setCharCoordinatesDontResetAnim(char, x, y, z)
  if doesCharExist(char) then
    local ptr = getCharPointer(char)
    FHA_setEntityCoordinates(ptr, x, y, z)
  end
end

function FHA_teleportPlayer(x, y, z)
  if isCharInAnyCar(PLAYER_PED) then
    setCharCoordinates(PLAYER_PED, x, y, z)
  end
  FHA_setCharCoordinatesDontResetAnim(PLAYER_PED, x, y, z)
end

function FHA_showCursor(toggle)
    if toggle then
        sampSetCursorMode(CMODE_LOCKCAM)
        FHA.state.cursorEnabled = true
    else
        sampToggleCursor(false) 
        FHA.state.cursorEnabled = false
    end
end

function FHA_updateClickWarp()
    local st = FHA.state
    
    if not st.clickWarpEnabled.v or st.adminLevel.v < 6 then
        if st.cursorEnabled then
            FHA_showCursor(false) 
        end
        FHA_removePointMarker() 
        return
    end
    
    if menu.visible then
        if st.cursorEnabled then
            FHA_showCursor(false)
        end
        FHA_removePointMarker()
        return
    end
    
    if wasKeyPressed(FHA.VK_MBUTTON) then
        st.cursorEnabled = not st.cursorEnabled
        FHA_showCursor(st.cursorEnabled)
        if not st.cursorEnabled then
            FHA_removePointMarker()
        end
    end

    if st.cursorEnabled then
        local mode = sampGetCursorMode()
        if mode == CMODE_DISABLE then
             FHA_showCursor(true)
        end
        local sx, sy = getCursorPos()
        local sw, sh = getScreenResolution()
        
        if sx >= 0 and sy >= 0 and sx < sw and sy < sh then
            local posX, posY, posZ = convertScreenCoordsToWorld3D(sx, sy, 700.0)
            local camX, camY, camZ = getActiveCameraCoordinates()
            
            local result, colpoint = processLineOfSight(camX, camY, camZ, posX, posY, posZ, true, true, false, true, false, false, false)
            if result and colpoint.entity ~= 0 then
                local normal = colpoint.normal
                local pos = {}
                pos.x = colpoint.pos[1] - normal[1] * 0.1
                pos.y = colpoint.pos[2] - normal[2] * 0.1
                pos.z = colpoint.pos[3] - normal[3] * 0.1
                
                local zOffset = 300
                if normal[3] >= 0.5 then zOffset = 1 end
                
                local result2, colpoint2 = processLineOfSight(pos.x, pos.y, pos.z + zOffset, pos.x, pos.y, pos.z - 0.3,
                    true, true, false, true, false, false, false)
                
                if result2 then
                    pos.x = colpoint2.pos[1]
                    pos.y = colpoint2.pos[2]
                    pos.z = colpoint2.pos[3] + 1

                    local curX, curY, curZ  = getCharCoordinates(PLAYER_PED)
                    local dist              = getDistanceBetweenCoords3d(curX, curY, curZ, pos.x, pos.y, pos.z)
                    local hoffs             = renderGetFontDrawHeight(st.clickWarpFont)

                    local drawSx, drawSy = sx - 2, sy - 2
                    renderFontDrawText(st.clickWarpFont, string.format("%0.2fm", dist), drawSx, drawSy - hoffs, 0xEEEEEEEE)

                    local tpIntoCar = nil
                    if colpoint.entityType == 2 then
                        local car = getVehiclePointerHandle(colpoint.entity)
                        if doesVehicleExist(car) and (not isCharInAnyCar(PLAYER_PED) or storeCarCharIsInNoSave(PLAYER_PED) ~= car) then
                            FHA_displayVehicleName(drawSx, drawSy - hoffs * 2, getNameOfVehicleModel(getCarModel(car)))
                            local color = 0xAAFFFFFF
                            if isKeyDown(FHA.VK_RBUTTON) then
                                tpIntoCar = car
                                color = 0xFFFFFFFF
                            end
                            renderFontDrawText(st.clickWarpFont2, "Hold right mouse button to teleport into the car", drawSx, drawSy - hoffs * 3, color)
                        end
                    end

                    FHA_createPointMarker(pos.x, pos.y, pos.z)

                    if wasKeyPressed(FHA.VK_LBUTTON) then
                        if tpIntoCar then
                            if not FHA_jumpIntoCar(tpIntoCar) then
                                FHA_teleportPlayer(pos.x, pos.y, pos.z)
                            end
                        else
                            if isCharInAnyCar(PLAYER_PED) then
                                local norm = {}
                                norm.x = colpoint2.normal[1]
                                norm.y = colpoint2.normal[2]
                                norm.z = 0
                                
                                local norm2 = {}
                                norm2.x = colpoint2.normal[1]
                                norm2.y = colpoint2.normal[2]
                                norm2.z = colpoint2.normal[3]
                                
                                FHA_rotateCarAroundUpAxis(storeCarCharIsInNoSave(PLAYER_PED), Vector3D(norm2.x, norm2.y, norm2.z))
                                pos.x = pos.x - norm.x * 1.8
                                pos.y = pos.y - norm.y * 1.8
                                pos.z = pos.z - 0.8
                            end
                            FHA_teleportPlayer(pos.x, pos.y, pos.z)
                        end
                        FHA_removePointMarker()
                        FHA_showCursor(false)
                    end
                else
                    FHA_removePointMarker()
                end
            else
                FHA_removePointMarker()
            end
        else
            FHA_removePointMarker()
        end
    else
        FHA_removePointMarker()
    end
end

-- ===== КОМАНДЫ ЧАТА =====
function FHA_cmd_plmenu()
    if menu.visible then
        menu.visible = false
        FHA.whPaused = false
        ShowCursor(false)
        imgui.Process = false
    else
        imgui.Process = true
        menu.visible = true
        FHA.whPaused = true
        menu.windowPos = imgui.ImVec2(-1, -1)
        ShowCursor(true)
        if not menu.initDone then
            initParticles()
            menu.initDone = true
        end
    end
end

function FHA_cmd_pl(param)
    local st = FHA.state
    local now = os.clock()
    if now - st.lastSendTime < st.cooldown then
        sampAddChatMessage("{FF0000}[FastReply] Подождите немного", -1)
        return
    end
    st.lastSendTime = now
    if not param or param == "" then
        sampAddChatMessage("{FF0000}Использование: /pl [id] [код/текст]", -1)
        return
    end
    local space = param:find(" ")
    local id = tonumber(space and param:sub(1, space-1) or param)
    local txt = space and param:sub(space+1) or ""
    if not id or not sampIsPlayerConnected(id) then
        sampAddChatMessage("{FF0000}Ошибка: игрок не найден", -1)
        return
    end
    local final = st.fastCodes[txt] or txt or ""
    local msg = ""
    
    if final ~= "" then
        if txt == "hel" then
            msg = FHA.templates.helped()
        else
            msg = final .. " | " .. FHA.templates.pleasant_game()
        end
    else
        msg = FHA.templates.pleasant_game()
    end
    
    sampSendChat("/pm "..id.." "..msg)
end

function FHA_cmd_lc()
    if menu.visible and menu.selectedTab == 6 then
        menu.visible = false
        FHA.whPaused = false
        ShowCursor(false)
        imgui.Process = false
    else
        if not menu.visible then
            imgui.Process = true
            menu.visible = true
            FHA.whPaused = true
            menu.windowPos = imgui.ImVec2(-1, -1)
            ShowCursor(true)
            if not menu.initDone then
                initParticles()
                menu.initDone = true
            end
        end
        menu.selectedTab = 6
    end
end

function FHA_cmd_invis()
    local st = FHA.state
    
    if not st.invisEnabled.v then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Функция невидимости не активирована в меню скрипта.", -1)
        return
    end
    if st.adminLevel.v < 6 then
        sampAddChatMessage("{FF4444}[FastHelperAdm] Для использования невидимости требуется уровень администратора 6+.", -1)
        return
    end

    st.invisActive = not st.invisActive
    sampAddChatMessage("[{FF0000}FastHelperAdm{FFFFFF}] {ffff00}Невидимость " .. (st.invisActive and "{00ff00}Включено" or "{FF0000}Выключено"), -1)
end

-- ===== TRACER ЛОГИКА =====
local FHA_font = nil

function FHA_initializeTracer()
    if not FHA_font then
        FHA_font = renderCreateFont("Arial", 10, 1)
    end
    
    local st = FHA.state
    st.bulletSync = {lastId = 0, maxLines = st.tracerMaxLineLimit.v}
    st.bulletSyncMy = {lastId = 0, maxLines = st.tracerMaxLineMyLimit.v}
    
    for i = 1, st.bulletSync.maxLines do
        st.bulletSync[i] = { other = {time = 0, t = {x=0,y=0,z=0}, o = {x=0,y=0,z=0}, type = 0, color = 0, id = -1, colorText = 0}}
    end
    
    for i = 1, st.bulletSyncMy.maxLines do
        st.bulletSyncMy[i] = { my = {time = 0, t = {x=0,y=0,z=0}, o = {x=0,y=0,z=0}, type = 0, color = 0}}
    end
end

function FHA_onSendBulletSync(data)
    local st = FHA.state
    if not st.tracerEnabled.v or st.adminLevel.v < 6 or not st.tracerDrawMyBullets.v then return end
    
    if data.center.x ~= 0 and data.center.y ~= 0 and data.center.z ~= 0 then
        st.bulletSyncMy.lastId = st.bulletSyncMy.lastId + 1
        if st.bulletSyncMy.lastId < 1 or st.bulletSyncMy.lastId > st.bulletSyncMy.maxLines then
            st.bulletSyncMy.lastId = 1
        end
        st.bulletSyncMy[st.bulletSyncMy.lastId].my.time = os.time() + st.tracerTimeRenderMyBullets.v
        st.bulletSyncMy[st.bulletSyncMy.lastId].my.o.x, st.bulletSyncMy[st.bulletSyncMy.lastId].my.o.y, st.bulletSyncMy[st.bulletSyncMy.lastId].my.o.z = data.origin.x, data.origin.y, data.origin.z
        st.bulletSyncMy[st.bulletSyncMy.lastId].my.t.x, st.bulletSyncMy[st.bulletSyncMy.lastId].my.t.y, st.bulletSyncMy[st.bulletSyncMy.lastId].my.t.z = data.target.x, data.target.y, data.target.z
        
        if data.targetType == 0 then
            st.bulletSyncMy[st.bulletSyncMy.lastId].my.color = FHA_join_argb(st.tracerStaticObjectMy.v[1], st.tracerStaticObjectMy.v[2], st.tracerStaticObjectMy.v[3])
        elseif data.targetType == 1 then
            st.bulletSyncMy[st.bulletSyncMy.lastId].my.color = FHA_join_argb(st.tracerPedPMy.v[1], st.tracerPedPMy.v[2], st.tracerPedPMy.v[3])
        elseif data.targetType == 2 then
            st.bulletSyncMy[st.bulletSyncMy.lastId].my.color = FHA_join_argb(st.tracerCarPMy.v[1], st.tracerCarPMy.v[2], st.tracerCarPMy.v[3])
        elseif data.targetType == 3 then
            st.bulletSyncMy[st.bulletSyncMy.lastId].my.color = FHA_join_argb(st.tracerDinamicObjectMy.v[1], st.tracerDinamicObjectMy.v[2], st.tracerDinamicObjectMy.v[3])
        else
            st.bulletSyncMy[st.bulletSyncMy.lastId].my.color = 0xFFFFFFFF
        end
    end
end

function FHA_onBulletSync(playerid, data)
    local st = FHA.state
    if not st.tracerEnabled.v or st.adminLevel.v < 6 or not st.tracerDrawBullets.v then return end
    
    if data.center.x ~= 0 and data.center.y ~= 0 and data.center.z ~= 0 then
        st.bulletSync.lastId = st.bulletSync.lastId + 1
        if st.bulletSync.lastId < 1 or st.bulletSync.lastId > st.bulletSync.maxLines then
            st.bulletSync.lastId = 1
        end
        
        if st.tracerShowPlayerInfo.v then
            st.bulletSync[st.bulletSync.lastId].other.id = playerid
            st.bulletSync[st.bulletSync.lastId].other.colorText = FHA_join_argb(st.tracerColorPlayerI.v[1], st.tracerColorPlayerI.v[2], st.tracerColorPlayerI.v[3])
        end
        
        st.bulletSync[st.bulletSync.lastId].other.time = os.time() + st.tracerTimeRenderBullets.v
        st.bulletSync[st.bulletSync.lastId].other.o.x, st.bulletSync[st.bulletSync.lastId].other.o.y, st.bulletSync[st.bulletSync.lastId].other.o.z = data.origin.x, data.origin.y, data.origin.z
        st.bulletSync[st.bulletSync.lastId].other.t.x, st.bulletSync[st.bulletSync.lastId].other.t.y, st.bulletSync[st.bulletSync.lastId].other.t.z = data.target.x, data.target.y, data.target.z
        st.bulletSync[st.bulletSync.lastId].other.type = data.targetType
        
        if data.targetType == 0 then
            st.bulletSync[st.bulletSync.lastId].other.color = FHA_join_argb(st.tracerStaticObject.v[1], st.tracerStaticObject.v[2], st.tracerStaticObject.v[3])
        elseif data.targetType == 1 then
            st.bulletSync[st.bulletSync.lastId].other.color = FHA_join_argb(st.tracerPedP.v[1], st.tracerPedP.v[2], st.tracerPedP.v[3])
        elseif data.targetType == 2 then
            st.bulletSync[st.bulletSync.lastId].other.color = FHA_join_argb(st.tracerCarP.v[1], st.tracerCarP.v[2], st.tracerCarP.v[3])
        elseif data.targetType == 3 then
            st.bulletSync[st.bulletSync.lastId].other.color = FHA_join_argb(st.tracerDinamicObject.v[1], st.tracerDinamicObject.v[2], st.tracerDinamicObject.v[3])
        else
            st.bulletSync[st.bulletSync.lastId].other.color = 0xFFFFFFFF
        end
    end
end

function FHA_TracerThread()
    if FHA.isUnloading then return end
    
    while not FHA.isUnloading do
        wait(0)
        local st = FHA.state
        local oTime = os.time()
        
        if st.tracerEnabled.v and st.adminLevel.v >= 6 and st.tracerDrawMyBullets.v then
            for i = 1, st.bulletSyncMy.maxLines do
                if st.bulletSyncMy[i].my.time >= oTime then
                    local result, wX, wY, wZ, wW, wH = convert3DCoordsToScreenEx(st.bulletSyncMy[i].my.o.x, st.bulletSyncMy[i].my.o.y, st.bulletSyncMy[i].my.o.z, true, true)
                    local resulti, pX, pY, pZ, pW, pH = convert3DCoordsToScreenEx(st.bulletSyncMy[i].my.t.x, st.bulletSyncMy[i].my.t.y, st.bulletSyncMy[i].my.t.z, true, true)
                    if result and resulti then
                        renderDrawLine(wX, wY, pX, pY, st.tracerSizeOffMyLine.v, st.bulletSyncMy[i].my.color)
                        if st.tracerCbEndMy.v then
                            renderDrawPolygon(pX, pY-1, 3 + st.tracerSizeOffMyPolygonEnd.v, 3 + st.tracerSizeOffMyPolygonEnd.v, 1 + st.tracerRotationMyPolygonEnd.v, st.tracerDegreeMyPolygonEnd.v, st.bulletSyncMy[i].my.color)
                        end
                    end
                end
            end
        end
        
        if st.tracerEnabled.v and st.adminLevel.v >= 6 and st.tracerDrawBullets.v then
            for i = 1, st.bulletSync.maxLines do
                if st.bulletSync[i].other.time >= oTime then
                    local result, wX, wY, wZ, wW, wH = convert3DCoordsToScreenEx(st.bulletSync[i].other.o.x, st.bulletSync[i].other.o.y, st.bulletSync[i].other.o.z, true, true)
                    local resulti, pX, pY, pZ, pW, pH = convert3DCoordsToScreenEx(st.bulletSync[i].other.t.x, st.bulletSync[i].other.t.y, st.bulletSync[i].other.t.z, true, true)
                    if result and resulti then
                        if st.tracerShowPlayerInfo.v and st.bulletSync[i].other.id ~= -1 then
                            if sampIsPlayerConnected(st.bulletSync[i].other.id) then
                                if st.tracerOnlyId.v and st.tracerOnlyNick.v then
                                    renderFontDrawText(FHA_font, sampGetPlayerNickname(st.bulletSync[i].other.id)..'['..st.bulletSync[i].other.id..']', wX + 0.5, wY, st.bulletSync[i].other.colorText, false)
                                elseif st.tracerOnlyId.v then
                                    renderFontDrawText(FHA_font, '['..st.bulletSync[i].other.id..']', wX + 0.5, wY, st.bulletSync[i].other.colorText, false)
                                elseif st.tracerOnlyNick.v then
                                    renderFontDrawText(FHA_font, sampGetPlayerNickname(st.bulletSync[i].other.id), wX + 0.5, wY, st.bulletSync[i].other.colorText, false)
                                end
                            end
                        end
                        renderDrawLine(wX, wY, pX, pY, st.tracerSizeOffLine.v, st.bulletSync[i].other.color)
                        if st.tracerCbEnd.v then
                            renderDrawPolygon(pX, pY-1, 3 + st.tracerSizeOffPolygonEnd.v, 3 + st.tracerSizeOffPolygonEnd.v, 1 + st.tracerRotationPolygonEnd.v, st.tracerDegreePolygonEnd.v, st.bulletSync[i].other.color)
                        end
                    end
                end
            end
        end
    end
end

-- ===== АВТО ВВОД КОМАНД =====
local function FHA_CheckAutoCommands()
    local st = FHA.state
    
    if not st.autoEnable.v or st.adminLevel.v < 6 then
        st.autoDialogOpen = false
        st.autoDialogClosedTime = 0
        st.autoWaitingForClose = false
        st.autoExecutingCommands = false
        st.autoCommandsSent = 0
        st.autoLastCommandTime = 0
        st.autoLastDialogId = nil
        return
    end
    
    local dialogActive = sampIsDialogActive()
    local currentTime = os.clock() * 1000
    
    if dialogActive then
        local dialogId = sampGetCurrentDialogId()
        if dialogId then
            st.autoLastDialogId = dialogId
        end
        st.autoDialogOpen = true
        st.autoWaitingForClose = false
        st.autoExecutingCommands = false
        st.autoCommandsSent = 0
        return
    end
    
    if st.autoDialogOpen and not dialogActive then
        if st.autoLastDialogId == 2934 then
            if not st.autoWaitingForClose then
                st.autoDialogClosedTime = currentTime
                st.autoWaitingForClose = true
                st.autoDialogOpen = false
            end
        else
            st.autoDialogOpen = false
            st.autoWaitingForClose = false
            st.autoLastDialogId = nil
        end
    end
    
    if st.autoWaitingForClose and not st.autoExecutingCommands then
        local elapsed = currentTime - st.autoDialogClosedTime
        
        if elapsed >= st.autoDelayBeforeCheck then
            if not sampIsDialogActive() then
                st.autoExecutingCommands = true
                st.autoCommandsSent = 0
                st.autoLastCommandTime = currentTime
            else
                st.autoWaitingForClose = false
                st.autoDialogOpen = true
                st.autoLastDialogId = nil
            end
        end
    end
    
    if st.autoExecutingCommands then
        local commands = {}
        if st.autoAgm.v then table.insert(commands, "/agm") end
        if st.autoChat.v then table.insert(commands, "/chat") end
        if st.autoChatsms.v then table.insert(commands, "/chatsms") end
        if st.autoOffgoto.v then table.insert(commands, "/offgoto") end
        if st.autoTogphone.v then table.insert(commands, "/togphone") end
        
        if #commands == 0 then
            st.autoExecutingCommands = false
            st.autoWaitingForClose = false
            st.autoDialogOpen = false
            st.autoLastDialogId = nil
            return
        end
        
        local elapsed = currentTime - st.autoLastCommandTime
        
        if st.autoCommandsSent < #commands then
            if elapsed >= st.autoDelayBetweenCommands then
                local cmd = commands[st.autoCommandsSent + 1]
                sampSendChat(cmd)
                st.autoCommandsSent = st.autoCommandsSent + 1
                st.autoLastCommandTime = currentTime
            end
        else
            st.autoExecutingCommands = false
            st.autoWaitingForClose = false
            st.autoDialogOpen = false
            st.autoCommandsSent = 0
            st.autoLastDialogId = nil
        end
    end
end

-- ===== ОБНОВЛЕНИЕ СИСТЕМЫ =====
function FHA_updateSystem()
    local st = FHA.state
    
    -- НОВЫЙ БЛОК ДЛЯ ADMIN RENDER
    if adminRender.isMoving then
        adminRender.updateMove()
        if wasKeyPressed(vkeys.VK_RETURN) then
            adminRender.stopMove(true)
        end
        if wasKeyPressed(vkeys.VK_ESCAPE) then
            adminRender.stopMove(false)
        end
    end
    
    if st.clickWarpEnabled.v and st.adminLevel.v >= 6 then
        FHA_updateClickWarp()
    else
        if st.cursorEnabled then
            FHA_showCursor(false)
        end
        FHA_removePointMarker()
    end
    
    FHA_CheckAutoCommands()
    
    if st.active_razd and not st.active_razd2 and st.razdTimeout > 0 and os.clock() > st.razdTimeout then
        sampAddChatMessage("{FF5555}[FastHelperAdm] Раздача отменена - никто не ввел /rep " .. u8:decode(st.text_word.v), -1)
        FHA_resetRazdacha()
    end
    
    if st.active_razd and st.active_razd2 and not st.antiFlood then
        st.antiFlood = true
        st.active_razd = false
        st.active_razd2 = false
        
        if not sampIsPlayerConnected(st.razd_player_id) then
            sampAddChatMessage('{FF5555}[FastHelperAdm] Победитель вышел, раздача отменена.', -1)
            FHA_resetRazdacha()
        else
            local idx = st.combo_priz.v + 1
            local statId = st.prizStatId[idx]
            local prize = u8:decode(st.arr_priz[idx])
            local nick = sampGetPlayerNickname(st.razd_player_id)
            local isStyle = (idx >= 11 and idx <= 13)
            local amount = isStyle and 50000 or (FHA_parseAmount(st.text_real.v) or 0)
            
            local responseTime = os.clock() - st.razdStartTime
            local responseTimeStr = string.format("%.3f sec", responseTime)
            
            lua_thread.create(function()
                if FHA.isUnloading then return end
                
                FHA_givePrize(st.razd_player_id, statId, amount)
                wait(st.FLOOD_DELAY)

                if FHA.isUnloading then return end
                local pm_message = isStyle
                    and ('Поздравляем! Вы победили в раздаче! Вы выиграли стиль боя "'..prize..'"')
                    or  ('Поздравляем! Вы победили в раздаче! Выиграли '..formatMoneySmart(amount)..' '..prize)
                sampSendChat('/pm '..st.razd_player_id..' '..pm_message..' | ' .. FHA.templates.pleasant_game())
                wait(st.FLOOD_DELAY)

                if FHA.isUnloading then return end
                
                local prizeText
                if isStyle then
                    prizeText = 'Style '..prize
                else
                    prizeText = formatMoneySmart(amount)..' '..prize
                end
                
                local logMessage = string.format(
                    'WINNER: %s[%d] | Слово: %s (%s) | %s',
                    nick,
                    st.razd_player_id,
                    st.razdWord,
                    responseTimeStr,
                    prizeText
                )
                
                local announce_message = isStyle
                    and ('РАЗДАЧА | WIN '..st.razd_player_id..'id выиграл стиль "'..prize..'"')
                    or  ('РАЗДАЧА | WIN '..st.razd_player_id..'id')
                
                sampSendChat('/'..st.arr_chat[st.combo_chat.v+1]..' '..announce_message)
                
                FHA_addGuiLog(logMessage)
                FHA_resetRazdacha()
            end)
        end
    end
    
    if st.startAutoMpFlag then
        st.startAutoMpFlag = false
        FHA_doAutoMP()
    end
    
    if st.startAutoOtborFlag then
        st.startAutoOtborFlag = false
        FHA_doAutoOtbor()
    end
    
    if st.startRazdachaFlag then
        st.startRazdachaFlag = false
        FHA_doRazdacha()
    end
    
    if st.saveSettingsFlag then
        st.saveSettingsFlag = false
        FHA_saveCfg()
    end
    
    if os.time() - st.gz_lastUpdate >= 0.5 then 
        st.gz_lastUpdate = os.time()
        st.gz_zones = GZ_getAllGangZones() 
    end
    if os.time() - st.gz_lastCapCheck >= 0.5 then 
        st.gz_lastCapCheck = os.time()
        GZ_updateCapStatus() 
    end
end

-- ===== IMGUI ОБРАБОТЧИК =====
function imgui.OnDrawFrame()
    FHA.isImguiInteracting = imgui.IsAnyItemActive() or imgui.IsWindowHovered(imgui.HoveredFlags_AnyWindow)
    
    if not menu.visible then
        FHA.isImguiInteracting = false
    end
    
    local success, err = pcall(DrawCyberMenu)
    if not success then
        menu.visible = false
        FHA.whPaused = false
        ShowCursor(false)
        imgui.Process = false
        print("[FastHelperAdm][Imgui] Ошибка рисования:", err)
    end
end

function onWindowMessage(msg, wparam, lparam)
    FHA_onWindowMessage(msg, wparam, lparam)
end

-- ===== ВЫГРУЗКА СКРИПТА =====
function script.unload()
    FHA.isUnloading = true

    FHA_saveCfg()

    if FHA.state.cursorEnabled then
        FHA_showCursor(false)
    end
    
    if menu.cursorEnabled then
        ShowCursor(false)
    end

    FHA_removePointMarker()

    menu.visible = false
    FHA.whPaused = false
    imgui.Process = false
    
    FHA.state.gz_autoReform.active = false
    FHA.state.gz_autoReform.paused = false
    
    if nameTag then
        wh_nameTagOff()
    end
    wh_settings.enabled = false

    killList.restoreOriginalNames()

    adminRender.saveFilter()
    if adminRender.isMoving then
        adminRender.stopMove(false)
    end

    sampAddChatMessage("{33CCFF}[FastHelperAdm] Скрипт выгружен корректно", -1)
end

-- ===== ГЛАВНАЯ ФУНКЦИЯ =====
function main()
    FHA_loadCfg()
    FHA.isUnloading = false
    FHA.threads = {}
    
    menu.visible = false
    imgui.Process = false
    menu.selectedTab = 1
    
    FHA_ApplyPurpleStyle()
    UpdateCyberColors()
    
    repeat wait(0) until isSampAvailable()
    
    sampRegisterChatCommand("plmenu", FHA_cmd_plmenu)
    sampRegisterChatCommand("pl", FHA_cmd_pl)
    sampRegisterChatCommand("lc", FHA_cmd_lc)
    sampRegisterChatCommand("invis", FHA_cmd_invis)
    
    FHA.state.loginTime = os.clock()
    FHA.state.adminLoginExecuted = false

    
    if FHA.state.menuColor.v == 0 then FHA_ApplyRedStyle()
    elseif FHA.state.menuColor.v == 1 then FHA_ApplyGreenStyle()
    elseif FHA.state.menuColor.v == 2 then FHA_ApplyBlueStyle()
    elseif FHA.state.menuColor.v == 3 then FHA_ApplyOrangeStyle()
    elseif FHA.state.menuColor.v == 4 then FHA_ApplyYellowStyle()
    elseif FHA.state.menuColor.v == 5 then FHA_ApplyCyanStyle()
    elseif FHA.state.menuColor.v == 6 then FHA_ApplyPurpleStyle()
    elseif FHA.state.menuColor.v == 7 then FHA_ApplyRainbowStyle()
    end
    UpdateCyberColors()
    
    if not doesDirectoryExist(rulesEnvyPath) then
        createDirectory(rulesEnvyPath)
    end
    if not doesDirectoryExist(rulesPridePath) then
        createDirectory(rulesPridePath)
    end
    if not doesDirectoryExist(rulesAngerPath) then
        createDirectory(rulesAngerPath)
    end
    
    FHA_loadEnvyRules()
    FHA_loadPrideRules()
    FHA_loadAngerRules()
    
    FHA_initializeTracer()
    FHA_initializeClickWarp()
    
    initParticles()
    menu.initDone = true
    
    local success, maxPlayers = pcall(sampGetMaxPlayers)
    if success and maxPlayers and maxPlayers > 0 then
        serverInfo.maxPlayers = maxPlayers
    end
    
    lua_thread.create(FHA_gmCarThread)
    lua_thread.create(FHA_SpeedhackThread)

    -- === ДОБАВИТЬ ЭТИ СТРОКИ ===
    lua_thread.create(adminRender.updateLoop)
    lua_thread.create(adminRender.autoUpdateLoop)
    adminRender.init()
    adminRender.loadPosition()
    adminRender.loadFilter()
    -- === КОНЕЦ ДОБАВЛЕНИЯ ===
    
    FHA.threads.reportCleanup = lua_thread.create(FHA_reportCleanupThread)

    lua_thread.create(wh_thread)

    killList.init()

    sampAddChatMessage("{CCCCCC}[INFORMATION] {CC88FF}Скрипт {AA66FF}FastHelperAdm {999999}version 2.2 {CC88FF}успешно загружен", -1)
    sampAddChatMessage("{CCCCCC}[INFORMATION] {CC88FF}Для использования пропишите - {999999}/plmenu", -1)

    FHA.threads.autosave = lua_thread.create(function()
        while not FHA.isUnloading do
            wait(5000)
            if FHA.isUnloading then break end
            FHA_saveCfg()
        end
    end)
    
    FHA.threads.tracer = lua_thread.create(function()
        while not FHA.isUnloading do
            FHA_TracerThread()
            wait(0)
        end
    end)

    while not FHA.isUnloading do
        wait(0)
        
        imgui.Process = menu.visible
        
        local success, err = pcall(function() Input:update() end)
        if not success then
            print("[FastHelperAdm][Input] Ошибка в Input:update():", err)
            Input:clear()
        end
        
        FHA_updateSystem()
        
        if not menu.visible then
            imgui.Process = false
            if menu.cursorEnabled then
                ShowCursor(false)
            end
        end
    end
end
