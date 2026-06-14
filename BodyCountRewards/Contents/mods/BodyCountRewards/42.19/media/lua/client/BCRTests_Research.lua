-- ============================================================
-- BCR v1.3.0 - Research Tests (Build 42.19+)
-- Call: BCRResearchTests() from debug console in active SP game
-- ============================================================

function BCRResearchTests()
    print("[BCR Research] === TEST 1: Trait Resolution via CharacterTrait.NAME ===")
    local traits = {
        "SPEED_DEMON", "NIGHT_VISION", "DEXTROUS", "FAST_READER", "INVENTIVE",
        "LIGHT_EATER", "LOW_THIRST", "OUTDOORSMAN", "NEEDS_LESS_SLEEP", "IRON_GUT",
        "ADRENALINE_JUNKIE", "EAGLE_EYED", "GRACEFUL", "INCONSPICUOUS", "NUTRITIONIST",
        "ORGANIZED", "RESILIENT", "FAST_HEALER", "FAST_LEARNER", "KEEN_HEARING", "THICK_SKINNED",
        "HIGH_THIRST", "SUNDAY_DRIVER", "ALL_THUMBS", "CLUMSY", "COWARDLY",
        "SLOW_READER", "SLOW_HEALER", "WEAK_STOMACH", "SMOKER", "AGORAPHOBIC",
        "CLAUSTROPHOBIC", "CONSPICUOUS", "HEARTY_APPETITE", "PACIFIST", "PRONE_TO_ILLNESS",
        "NEEDS_MORE_SLEEP", "ASTHMATIC", "HEMOPHOBIC", "DISORGANIZED", "SLOW_LEARNER",
        "ILLITERATE", "THIN_SKINNED",
    }
    local resolved, failed = 0, 0
    for _, name in ipairs(traits) do
        local obj = CharacterTrait[name]
        if type(obj) == "userdata" then
            resolved = resolved + 1
        else
            failed = failed + 1
            print("[BCR Research]   FAIL: CharacterTrait." .. name .. " = " .. type(obj))
        end
    end
    print("[BCR Research]   Result: " .. resolved .. " resolved, " .. failed .. " failed")

    print("")
    print("[BCR Research] === TEST 2: Alternative Resolution Methods ===")
    local testNames = { "SPEED_DEMON", "KEEN_HEARING", "THIN_SKINNED" }
    for _, name in ipairs(testNames) do
        local obj1 = CharacterTrait[name]
        print("[BCR Research]   CharacterTrait." .. name .. " = " .. type(obj1))
        local obj2 = rawget(CharacterTrait, name)
        print("[BCR Research]   rawget(CharacterTrait, \"" .. name .. "\") = " .. type(obj2))
        local stripped = string.lower(string.gsub(name, "_", ""))
        local ok, rl = pcall(function() return ResourceLocation.of("base:" .. stripped) end)
        if ok and rl then
            local ok2, obj3 = pcall(function() return CharacterTrait.get(rl) end)
            if ok2 and obj3 then
                print("[BCR Research]   ResourceLocation base:" .. stripped .. " = " .. type(obj3))
            else
                print("[BCR Research]   ResourceLocation base:" .. stripped .. " = FAILED (" .. tostring(obj3) .. ")")
            end
        else
            print("[BCR Research]   ResourceLocation.of(\"base:" .. stripped .. "\") = FAILED")
        end
    end

    print("")
    print("[BCR Research] === TEST 3: Trait Name Resolution ===")
    for _, name in ipairs(testNames) do
        local obj = CharacterTrait[name]
        if type(obj) == "userdata" then
            local ok, displayName = pcall(function() return obj:getName() end)
            if ok and displayName then
                print("[BCR Research]   " .. name .. " -> getName() = \"" .. displayName .. "\"")
            else
                print("[BCR Research]   " .. name .. " -> getName() FAILED: " .. tostring(displayName))
            end
        end
    end

    print("")
    print("[BCR Research] === TEST 4: Kill Count Methods ===")
    local player = nil
    local ok, p = pcall(function() return getSpecificPlayer(0) end)
    if ok then player = p end
    if not player then
        print("[BCR Research]   No player available — run from active savegame, not main menu")
    else
        local kills = player:getZombieKills()
        print("[BCR Research]   getZombieKills() = " .. tostring(kills) .. " (type: " .. type(kills) .. ")")
        local ok2, lastKills = pcall(function() return player:getLastZombieKills() end)
        if ok2 then
            print("[BCR Research]   getLastZombieKills() = " .. tostring(lastKills) .. " (type: " .. type(lastKills) .. ")")
        else
            print("[BCR Research]   getLastZombieKills() = NOT AVAILABLE (" .. tostring(lastKills) .. ")")
        end
        local ok3, survKills = pcall(function() return player:getSurvivorKills() end)
        if ok3 then
            print("[BCR Research]   getSurvivorKills() = " .. tostring(survKills) .. " (type: " .. type(survKills) .. ")")
        else
            print("[BCR Research]   getSurvivorKills() = NOT AVAILABLE (" .. tostring(survKills) .. ")")
        end

        print("")
        print("[BCR Research] === TEST 5: hasTrait with CharacterTrait object ===")
        for _, name in ipairs(testNames) do
            local obj = CharacterTrait[name]
            if type(obj) == "userdata" then
                local ok4, result = pcall(function() return player:hasTrait(obj) end)
                if ok4 then
                    print("[BCR Research]   player:hasTrait(" .. name .. ") = " .. tostring(result))
                else
                    print("[BCR Research]   player:hasTrait(" .. name .. ") FAILED: " .. tostring(result))
                end
            end
        end

        print("")
        print("[BCR Research] === TEST 6: getCharacterTraits() ===")
        local ok5, traitsObj = pcall(function() return player:getCharacterTraits() end)
        if ok5 and traitsObj then
            local knownTraits = traitsObj:getKnownTraits()
            if knownTraits then
                local ok6, size = pcall(function() return knownTraits:size() end)
                if ok6 and size then
                    print("[BCR Research]   Known traits count: " .. size)
                    local count = math.min(size, 5)
                    for i = 0, count - 1 do
                        local ok7, t = pcall(function() return knownTraits:get(i) end)
                        if ok7 and t then
                            local ok8, tname = pcall(function() return t:getName() end)
                            print("[BCR Research]     " .. i .. ": " .. tostring(tname or t))
                        end
                    end
                else
                    print("[BCR Research]   knownTraits:size() FAILED")
                end
            else
                print("[BCR Research]   getKnownTraits() = nil")
            end
        else
            print("[BCR Research]   getCharacterTraits() FAILED: " .. tostring(traitsObj))
        end

        print("")
        print("[BCR Research] === TEST 8: getModData() and SandboxVars access ===")
        local ok9, modData = pcall(function() return player:getModData() end)
        print("[BCR Research]   getModData() success = " .. tostring(ok9) .. ", type = " .. type(modData))
        local sv = SandboxVars.BCR
        print("[BCR Research]   SandboxVars.BCR = " .. type(sv))
        if type(sv) == "table" then
            for k, v in pairs(sv) do
                print("[BCR Research]     " .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end

    print("")
    print("[BCR Research] === TEST 7: Available Kill-Related Events ===")
    local events = {
        "OnCharacterDeath", "OnHitZombie", "OnWeaponHitCharacter",
        "OnZombieDead", "OnWeaponHitXp", "OnPlayerUpdate",
        "OnInitWorld", "OnGameStart", "OnCreatePlayer",
    }
    for _, evName in ipairs(events) do
        local ev = Events[evName]
        if ev then
            print("[BCR Research]   Events." .. evName .. " EXISTS")
        else
            print("[BCR Research]   Events." .. evName .. " = nil")
        end
    end

    print("")
    print("[BCR Research] ======== RESEARCH TESTS COMPLETE ========")
end
