local pnp = require("PushNPull")

-- configuring pnp

pnp.active = true;
pnp.ignoreWhitelist = false;

pnp.WhitelistedPlayers["vickystxr"] = true
pnp.WhitelistedPlayers["ghostystxr"] = true

pnp.config.launchStrength = 30;

pnp.autoActionWheel = true
-- all these changes are setup now and applied on entity_init !
-- If you got vscode hovering over them should give you a nice tooltip telling you what they do.

--[[
    CUSTOMIZE ANYTHING UNDER THIS WITH WHATFUCKEN EVER CODE YOU WANT
    THIS IS YOUR LIFE, THIS IS JUST AN EXAMPLE!!!!!!!!!!!!!!!
]]

-- Simple function to just get the look position of the player, this is because im lazy :3c
local function lookPos(r)
    if not player:isLoaded() then return 0; end
    return player:getPos() + vec(0, player:getEyeHeight(), 0) + (player:getLookDir() * (r or 30))
end


-- Setting up the whileGrabbing function so I can do cool particles if i grab someone!
-- Ent is the player that im grabbing and V is the vector / velocity im grabbing them at!
-- If you have vscode Hover over the function to see what is passed through.
function pnp.functions.whileGrabbing(ent, v)
    if v.extra == "forceChoke" then
        if world.getTime() % 2 == 0 then
            particles:newParticle("minecraft:end_rod", ent:getPos() + vec(0, ent:getBoundingBox().y / 2, 0))
            particles:newParticle("minecraft:glow", ent:getPos() + vec(0, ent:getBoundingBox().y / 2, 0))
            particles:newParticle("minecraft:enchant", ent:getPos() + vec(0, ent:getBoundingBox().y / 2, 0))
        end
    else
        if world.getTime() % 3 == 0 then
            local dist = (ent:getPos() - player:getPos()):length() * 3;
            for i = 1, dist, 1 do
                particles:newParticle("minecraft:end_rod",
                    (player:getPos() + vec(0, player:getBoundingBox().y / 2, 0) + (ent:getPos() - player:getPos()) / dist * i))
            end
        end
    end
end

-- Setting up while grabbed function, i want to do a little broken heart particle whenever people grab me!
-- Seems basic cuz it is!
-- If you have vscode Hover over the function to see what is passed through.
function pnp.functions.whileGrabbed()
    particles:newParticle("minecraft:damage_indicator", player:getPos())
end

-- Here i setup a quick keybind to grab the person I'm looking at
-- then using pings.pnpSetMode, passing through the pnp.modesLogic[INDEX], in this example INDEX is forceChoke!
-- Look at forceChoke in the main file to look at what it does! and how to make your own function!
-- Then I also pass through the UUID of the person I'm doing this on and if I want to remove or add it to the tick events list,
-- in this case I put in false because I want this to be added to the list!
local lastForceChokeTarget;
local key = keybinds:newKeybind("Force choke", "key.keyboard.z", false)
key:setOnPress(function()
    -- Using a raycast cuz fancy :3c
    local t = raycast:entity(lookPos(0), lookPos(60), function(e) return e ~= player; end);
    if not t then return end;
    lastForceChokeTarget = t:getUUID()
    pings.pnpSetMode("forceChoke", lastForceChokeTarget, false)
end)

-- And in here i pass through the last entity's UUID and do true so that I remove it from the tick events list and reset it!
key:setOnRelease(function()
    if not lastForceChokeTarget then return; end
    pings.pnpSetMode("forceChoke", lastForceChokeTarget, true);
    lastForceChokeTarget = nil;
end)

-- This is a function I made custom (aka does not come with the pnp file) that lets me throw whoever I want,
-- technically this can be ran at any time! as long as you pass through an entity and a vector.
---@param ent Entity
---@param v Vector3
function pnp.functions.throwEntity(ent, v)
    local vars = pnp.functions.validOverallChecker(ent)
    if not vars then return; end

    -- New thing added! Timers! It adds a timeout to each instruction (defaults to 5 ticks) and it ticks off the instruction, neat right?
    pnp.functions.setInstruction(ent, "setVel", { value = v, extra = "throw", timer = 3 })
end

-- Little ping so I can run it with the keybind!
function pings.launch(uuid)
    -- In here I remove the person from the tick events list so I dont regrab them!
    -- True is there so i remove them!
    pnp.functions.setMode("forceChoke", uuid, true);

    local t = world.getEntity(uuid)
    if type(t) == "PlayerAPI" then
        -- Running the function as thou can see
        pnp.functions.throwEntity(t, (lookPos(pnp.config.launchStrength) - player:getPos()) * 0.1)
    end
    lastForceChokeTarget = nil;
end

-- Making this all host only
if not host:isHost() then return; end

-- See how easy this is! I check if the lastForceChokeTarget isnt nil / has a UUID and i throw em >:3
keybinds:newKeybind("Force Launch", "key.keyboard.x", false):setOnPress(function(modifiers, self)
    if lastForceChokeTarget then
        -- Yeet
        pings.launch(lastForceChokeTarget)
    end
end)

-- In here is where I do the leash function!
function events.tick()
    -- Get if player is swinging
    if player:getSwingTime() == 1 then
        local item = player:getHeldItem():getID():gsub("^.+:", "");
        local t = player:getTargetedEntity();
        if not t then return; end
        local name,uuid = t:getName(), t:getUUID()
        -- Check if I'm holding a lead! and if im looking at something!
        if item == "lead" and t then
            -- Then yoink i grab them, as you can see in the final field i didnt put in a true or false, this is because i want to toggle!
            -- Well then i did a small little nil check
            -- As you can see every tick event is stored in pnp.activeModes
            pings.pnpSetMode("leash", uuid, pnp.activeModes["leash" .. uuid] ~= nil)
        end
        if item == "feather" and t then
            local v = (pnp.WhitelistedPlayers[uuid] or pnp.WhitelistedPlayers[name]);
            pings.pnpWhitelistPlayer(name, v)
            v = not v;
            printJson(toJson({
                text = (v and "Added " or "Removed ") ..
                    name .. " to/from the whitelist.\n",
                color = v and "green" or "red",
            }))
        end
    end
end
