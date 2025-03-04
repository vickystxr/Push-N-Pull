PushNPull = {
    VERSION = "0.1.0",

    -- If pnp is active, will also be put in your avatar vars
    active = true,
    -- Will ignore the whitelist of friends below, will also be put in your avatar vars
    ignoreWhitelist = false,
    -- Friend whitelist, either hardcode it here or set it elsewhere, read live so changes can be made at runtime
    WhitelistedPlayers = {},

    -- Change stuff here if you want
    config = {
        grabDistance = 4,
        launchDistance = 60,
    },

    functions = {
        ---This function runs every tick in the grabbing-mode as the grabbee, passes through the grabber player, Vector3 and Mode;
        ---@param ent Entity
        ---@param value {value:table,extra?:any}
        ---@param mode string
        ---@param vars table
        whileGrabbed = function(ent, value, mode, vars) end,
        ---This function runs every tick in the grabbing-mode as the grabber, passes through the grabbee entity, Vector3 and Mode;
        ---@param ent Entity
        ---@param value {value:table,extra?:any}
        ---@param mode string
        ---@param vars table
        whileGrabbing = function(ent, value, mode, vars) end,
    },
    -- Here is were setVel and setPos will be put
    movementFunctions = {},
    -- Logic for the modes, like forcechoke and leash
    -- Every mode gets passed an entity
    modesLogic = {},
    -- The active modes, dont mess anything here it's all handled by code to register / unregister tick events
    activeModes = {},
    -- Caching of avatar vars for saving instructions, only used in the modesLogic
    cachedAvatarVars = {},

    -- Your own avatar vars, handled by code and updated
    avatarVar = {},
}
-- Making some shortcuts
local pnp = PushNPull;
local pnpf = pnp.functions;


function pnpf.isValidVector(v, ...)
    return type(v) == "Vector3" and v
        or type(v) == "number" and vec(v, ...)
        or type(v) == "table" and vec(table.unpack(v))
end

function pnp.movementFunctions.setVel(...)
    if host:isHost() then
        local v = pnpf.isValidVector(...);
        if pnp.active and v then
            v = v:clamped(0, 5)
            if goofy then
                return goofy:setVelocity(v);
            end
            if host.setVelocity then
                return host:setVelocity(v);
            end
            error("You probably dont have host:setVelocity or goofy:setVelocity! Please make sure to have one of the two or change this function to the one you actually have!")
        end
    end
end

function pnp.movementFunctions.setPos(...)
    if host:isHost() then
        local v = pnpf.isValidVector(...);
        if pnp.active and v then
            if goofy then
                return goofy:setPos(v);
            end
            if host.setPos then
                return host:setPos(v);
            end
            error("You probably dont have host:setPos or goofy:setPos! Please make sure to have one of the two or change this function to the one you actually have!")
        end
    end
end

---@param ent Entity
---@return table|nil
function pnpf.grabVariables(ent)
    if not ent then return; end
    if not player:isLoaded() or not ent:isLoaded() then return; end
    local vars = ent:getVariable().PushNPull
    if not vars then return; end

    local tbl = {
        ---@type boolean
        enabled = vars.enabled,
        ---@type boolean
        ignoreWhitelist = vars.ignoreWhitelist,
        ---@type function
        whileGrabbing = vars.whileGrabbing,
        ---@type table[]
        instructions = vars.instructions,
    }

    pnp.cachedAvatarVars[ent:getUUID()] = tbl;
    return tbl;
end

---@param ent Entity
---@return table|nil
function pnpf.validOverallChecker(ent)
    if not pnp.active then return; end
    if not ent then return; end
    if not player:isLoaded() or not ent:isLoaded() then return; end
    local vars = pnp.cachedAvatarVars[ent:getUUID()] or pnpf.grabVariables(ent);
    if not vars.enabled or not vars then return; end
    return vars;
end

---@param ent Entity
function pnp.modesLogic.leash(ent)
    local vars = pnpf.validOverallChecker(ent)
    -- Removes itself from the ticking if it doesnt find any variables
    if not vars then return pnpf.setMode("leash", ent, true); end

    if (ent:getPos() - player:getPos()):length() > 5 then
        local v = ((player:getPos() - ent:getPos()):clampLength(0, 5) * 0.075);
        pnpf.setInstruction(ent, "setVel", { value = v, extra = "leash" })
    else
        pnpf.setInstruction(ent, "setVel", nil)
    end
end

---@param ent Entity
function pnp.modesLogic.forceChoke(ent)
    local vars = pnpf.validOverallChecker(ent)
    -- Removes itself from the ticking if it doesnt find any variables
    if not vars then return pnpf.tickManager("forceChoke", ent, true); end

    local v = ((player:getPos() + vec(0, player:getEyeHeight() - ent:getBoundingBox().y / 2, 0) + player:getLookDir() * pnp.config.grabDistance) - ent:getPos())
        :clamped(0, 2);
    pnpf.setInstruction(ent, "setVel", { value = v, extra = "forceChoke" })
end

---@param mode string
---@param ent Entity
---@param identifier string
local function remove(mode, ent, identifier)
    events.TICK:remove(identifier);
    pnpf.setInstruction(ent, nil)
    pnp.activeModes[identifier] = nil;
end


---@param mode string
---@param ent Entity
---@param identifier string
local function register(mode, ent, identifier)
    events.TICK:register(function() pcall(pnp.modesLogic[mode], ent) end, identifier)
    pnp.activeModes[identifier] = pnp.modesLogic[mode];
end


---@param mode string
---@param ent Entity
---@param removeMode? boolean
function pnpf.tickManager(mode, ent, removeMode)
    if not ent and type(ent) ~= "PlayerAPI" then return; end
    local identifier = mode .. ent:getUUID();

    if type(removeMode) == "boolean" then
        if removeMode then
            remove(mode, ent, identifier);
        else
            register(mode, ent, identifier);
        end
        return;
    end

    if pnp.activeModes[identifier] then
        remove(mode, ent, identifier);
    elseif pnp.modesLogic[mode] then
        register(mode, ent, identifier);
    end
end

---@param forceMode string
---@param entity Entity|string
---@param removeMode? boolean
function pnpf.setMode(forceMode, entity, removeMode)
    if not entity then return; end
    if type(entity) == "string" then entity = world.getEntity(entity); end

    pnpf.tickManager(forceMode, entity, removeMode)
end

---@param forceMode string
---@param entity Entity|string
---@param removeMode? boolean
function pings.pnpSetMode(forceMode, entity, removeMode)
    pnpf.setMode(forceMode, entity, removeMode);
end

---Sets the status of pnp to be enabled or disabled based on the bool
---@param active? boolean
---@param ignoreWhitelist? boolean
function pnpf.setEnabled(active, ignoreWhitelist)
    pnp.active = type(active) == "boolean" and active or pnp.active;
    pnp.ignoreWhitelist = type(ignoreWhitelist) == "boolean" and ignoreWhitelist or
        pnp.ignoreWhitelist;
    pnp.avatarVar.enabled = pnp.active;
    pnp.avatarVar.ignoreWhitelist = pnp.ignoreWhitelist;
    pnpf.avatarStore()
end

---Sets the status of pnp to be enabled or disabled based on the bool
---@param active? boolean
---@param ignoreWhitelist? boolean
function pings.pnpSetEnabled(active, ignoreWhitelist)
    pnpf.setEnabled(active, ignoreWhitelist)
end

---@param tbl table|nil
function pnpf.avatarStore(tbl)
    avatar:store("PushNPull", tbl or pnp.avatarVar)
    return pnp.avatarVar;
end

--- Sets instructions for the targetted entity, if Mode is nil it'll remove the mode (setPos or setVel come to mind), if vector is nil, it'll remove the vector thus nothing happening.
---@param target string|Entity
---@param instructionMode string|nil
---@param instruction {value:Vector3, extra:any}|nil
function pnpf.setInstruction(target, instructionMode, instruction)
    if type(target) ~= "string" then
        target = target:getUUID()
    end
    local inst = pnp.avatarVar.instructions;

    if instructionMode then
        inst[target] = inst[target] or {};
        if type(instruction.value):lower():find("vector") then
            instruction.value = { instruction.value:unpack() }
        end

        inst[target][instructionMode] = instruction;
    else
        inst[target] = nil;
    end

    pnpf.avatarStore();
end

function events.entity_init()
    pnp.playerName = player:getName()
    pnp.playerUUID = player:getUUID()

    pnp.avatarVar = {
        VERSION = pnp.VERSION,
        enabled = pnp.active,
        ignoreWhitelist = pnp.ignoreWhitelist,
        whileGrabbing = pnpf.whileGrabbing,
        instructions = {},
    }

    pnpf.avatarStore(pnp.avatarVar)
end

function events.tick()
    if not pnp.active then return; end
    local playerVars = pnpf.grabVariables(player);

    for name, grabber in pairs(world.getPlayers()) do
        -- Simple whitelist checking, not exactly that expensive, only grows with more players loaded tbh
        if not ((pnp.WhitelistedPlayers[name] or pnp.WhitelistedPlayers[grabber:getUUID()]) ~= nil or pnp.ignoreWhitelist) then goto EndWhitelist end

        local vars = pnpf.grabVariables(grabber)
        if vars and vars.enabled and vars.instructions then
            local instructions = vars.instructions[pnp.playerUUID] or
                vars.instructions[pnp.playerName];
            if instructions then
                for key, value in pairs(instructions) do
                    pcall(function()
                        vars.whileGrabbing(player, value, key, playerVars)
                        pnpf.whileGrabbed(grabber, value, key, vars)
                        pnp.movementFunctions[key](value.value);
                    end)
                end
            end
        end

        ::EndWhitelist::
    end
end

-- Some basic syncing, remove this if you want
function events.tick()
    if world.getTime() % 100 == 0 then
        pings.pnpSetEnabled(pnp.active, pnp.ignoreWhitelist)
    end
end

if host:isHost() then
    function events.entity_init()
        -- you can see my code did a massive nosedive here because i got tired of this project
        
        local function isEnabled()
            return { text = (pnp.active and "PNP Enabled" or "PNP Disabled"), color = (pnp.active and "#60b044" or "#d24a4a") }
        end

        local function isWhitelist()
            return { text = (pnp.ignoreWhitelist and "Whitelist Disabled" or "Whitelist Enabled"), color = (pnp.ignoreWhitelist and "#d24a4a" or "#60b044") }
        end

        action_wheel:getCurrentPage():newAction():setTitle(toJson({ isEnabled(),"\n", isWhitelist() }))
            :toggleColor(0.3, 0.4, 0.8)
            :item("minecraft:lead")
            :setOnLeftClick(function(self)
                pnp.active = not pnp.active
                pings.pnpSetEnabled(pnp.active)
                printJson(toJson(isEnabled()))
                self:setTitle(toJson({ isEnabled(),"\n", isWhitelist() }))
            end)
            :setOnRightClick(function(self)
                pnp.ignoreWhitelist = not pnp.ignoreWhitelist
                pings.pnpSetEnabled(nil, pnp.ignoreWhitelist)
                printJson(toJson(isWhitelist()))
                self:setTitle(toJson({ isEnabled(),"\n", isWhitelist() }))
            end)
    end
end


return PushNPull;
