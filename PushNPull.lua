PushNPull = {
	VERSION = "0.1.5",

	--- If pnp is active, will also be put in your avatar vars
	active = true,
	--- Will ignore the whitelist of friends below, will also be put in your avatar vars
	ignoreWhitelist = false,
	--- Friend whitelist, either hardcode it here or set it elsewhere, read live so changes can be made at runtime
	WhitelistedPlayers = {
		vickystxr = true, -- Just an example. Welcome to remove it ;)
	},
	--- Automatically makes an action wheel button
	autoActionWheel = true,

	--- Change stuff here if you want
	config = {
		--- Distance the "forceChoke" will grab the person at, this is mostly an example value that you can change
		grabDistance = 4,
		--- Launch strength, another example value to show the customizability
		launchStrength = 60,
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
	--- Here is were setVel and setPos will be put
	movementFunctions = {},
	--- Logic for the modes, like forcechoke and leash
	--- Every mode gets passed an entity
	modesLogic = {},
	--- The active modes, dont mess anything here it's all handled by code to register / unregister tick events
	activeModes = {},
	--- Caching of avatar vars for saving instructions, only used in the modesLogic
	cachedAvatarVars = {},

	--- Your own avatar vars, handled by code and updated
	avatarVar = {},
}


function PushNPull.functions.isValidVector(v, ...)
	return type(v) == "Vector3" and v
		or type(v) == "number" and vec(v, ...)
		or type(v) == "table" and vec(table.unpack(v))
end

function PushNPull.movementFunctions.setVel(...)
	if host:isHost() then
		local v = PushNPull.functions.isValidVector(...);
		if PushNPull.active and v then
			v = v:clamped(0, 5)

			if goofy then
				if goofy.setVel then return goofy:setVel(v); end
				if goofy.setVelocity then return goofy:setVelocity(v); end
			end
			if host.setVel then return host:setVel(v); end
			if host.setVelocity then return host:setVelocity(v); end

			error(
				"You probably dont have host:setVelocity or goofy:setVelocity! Please make sure to have one of the two or change this function to the one you actually have!")
		end
	end
end

function PushNPull.movementFunctions.setPos(...)
	if host:isHost() then
		local v = PushNPull.functions.isValidVector(...);
		if PushNPull.active and v then
			if goofy then
				if goofy.setPos then return goofy:setPos(v); end
				if goofy.setPosition then return goofy:setPosition(v); end
			end
			if host.setPos then return host:setPos(v); end
			if host.setPosition then return host:setPosition(v); end

			error(
				"You probably dont have host:setPos or goofy:setPos! Please make sure to have one of the two or change this function to the one you actually have!")
		end
	end
end

---Grabs the necessary variables that pnp uses for its logic, pretty easy to change and modify if needed
---@param ent Entity
---@return table|nil
function PushNPull.functions.grabVariables(ent)
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
		---@type boolean|nil
		clientIsWhitelisted = vars.clientIsWhitelisted
	}

	PushNPull.cachedAvatarVars[ent:getUUID()] = tbl;
	return tbl;
end

---Does an large "validity checker" on the variables of the chosen entity
---@param ent Entity
---@return table|nil
function PushNPull.functions.validOverallChecker(ent)
	if not PushNPull.active then return; end
	if not ent then return; end
	if not player:isLoaded() or not ent:isLoaded() then return; end
	local vars = PushNPull.cachedAvatarVars[ent:getUUID()] or PushNPull.functions.grabVariables(ent);
	if not vars or not vars.enabled then return; end
	if vars.clientIsWhitelisted == false  then return; end 
	-- Checks if the var even exists and if it does if it's true
	-- (this allows for non-player interactions)
	return vars;
end

---Simple "leash" for players, keeps them inside a radiu
---@param ent Entity
function PushNPull.modesLogic.leash(ent)
	local vars = PushNPull.functions.validOverallChecker(ent)
	-- Removes itself from the ticking if it doesnt find any variables
	if not vars then return PushNPull.functions.setMode("leash", ent, true); end

	if (ent:getPos() - player:getPos()):length() > 5 then
		local v = ((player:getPos() - ent:getPos()):clampLength(0, 5) * 0.075);
		PushNPull.functions.setInstruction(ent, "setVel", { value = v, extra = "leash" })
	else
		PushNPull.functions.setInstruction(ent, "setVel", nil)
	end
end

---RP as Darth Vader B)
---@param ent Entity
function PushNPull.modesLogic.forceChoke(ent)
	local vars = PushNPull.functions.validOverallChecker(ent)
	-- Removes itself from the ticking if it doesnt find any variables
	if not vars then return PushNPull.functions.tickManager("forceChoke", ent, true); end

	local v = ((player:getPos() + vec(0, player:getEyeHeight() - ent:getBoundingBox().y / 2, 0) + player:getLookDir() * PushNPull.config.grabDistance) - ent:getPos())
		:clamped(0, 2);
	PushNPull.functions.setInstruction(ent, "setVel", { value = v, extra = "forceChoke" })
end

---Removes instruction from tickEvent
---@param mode string
---@param ent Entity
---@param identifier string
local function removeTick(mode, ent, identifier)
	events.TICK:remove(identifier);
	PushNPull.functions.setInstruction(ent, nil)
	PushNPull.activeModes[identifier] = nil;
end

---Registers instruction to tickEvent
---@param mode string
---@param ent Entity
---@param identifier string
local function registerTick(mode, ent, identifier)
	events.TICK:register(function() pcall(PushNPull.modesLogic[mode], ent) end, identifier)
	PushNPull.activeModes[identifier] = PushNPull.modesLogic[mode];
end

---Manages removing adding instructions to tickEvents
---@param mode string
---@param ent Entity
---@param removeMode? boolean
function PushNPull.functions.tickManager(mode, ent, removeMode)
	if not ent and type(ent) ~= "PlayerAPI" then return; end
	local identifier = mode .. ent:getUUID();

	if type(removeMode) == "boolean" then
		if removeMode then
			removeTick(mode, ent, identifier);
		else
			registerTick(mode, ent, identifier);
		end
		return;
	end

	if PushNPull.activeModes[identifier] then
		removeTick(mode, ent, identifier);
	elseif PushNPull.modesLogic[mode] then
		registerTick(mode, ent, identifier);
	end
end

---Manages interacting with tickManager and does some simple type checking
---@param forceMode string
---@param entity Entity|string
---@param removeMode? boolean
function PushNPull.functions.setMode(forceMode, entity, removeMode)
	if not entity then return; end
	if type(entity) == "string" then entity = world.getEntity(entity); end

	PushNPull.functions.tickManager(forceMode, entity, removeMode)
end

---Ping version of the functions.setMode
---@param forceMode string
---@param entity Entity|string
---@param removeMode? boolean
function pings.pnpSetMode(forceMode, entity, removeMode)
	PushNPull.functions.setMode(forceMode, entity, removeMode);
end


---Adds or removes player to/from the whitelist
---@param user string|Entity|string[]|Entity[]
---@param remove true|nil
---@return any
function PushNPull.functions.whitelistPlayer(user,remove)
	if type(user) == "table" then
		for i = 1, #user, 1 do
			PushNPull.functions.whitelistPlayer(user[i])
		end
	end
	if type(user) == "EntityAPI" then
		if user:isLoaded() then
			PushNPull.functions.whitelistPlayer(user:getUUID())
		end
	end

	if type(user) == "string" then
		PushNPull.WhitelistedPlayers[user] = not remove;

		PushNPull.avatarVar.whitelist = PushNPull.WhitelistedPlayers;
		PushNPull.avatarVar.clientIsWhitelisted = PushNPull.ignoreWhitelist or
			(PushNPull.WhitelistedPlayers[client:getViewer():getUUID()] ~= nil) or
			(PushNPull.WhitelistedPlayers[client:getViewer():getName()] ~= nil);

		PushNPull.functions.avatarStore();
	end

	return user;
end


---Adds or removes player to/from the whitelist, ping version
---@param user string|Entity|string[]|Entity[]
---@param remove true|nil
function pings.pnpWhitelistPlayer(user,remove)
	PushNPull.functions.whitelistPlayer(user,remove)
end

---Sets the status of pnp to be enabled or disabled based on the bool
---@param active? boolean
---@param ignoreWhitelist? boolean
function PushNPull.functions.setEnabled(active, ignoreWhitelist)
	PushNPull.active = type(active) == "boolean" and active or PushNPull.active;
	PushNPull.ignoreWhitelist = type(ignoreWhitelist) == "boolean" and ignoreWhitelist or
		PushNPull.ignoreWhitelist;
	PushNPull.avatarVar.enabled = PushNPull.active;
	PushNPull.avatarVar.ignoreWhitelist = PushNPull.ignoreWhitelist;
	PushNPull.functions.avatarStore()
end

---Sets the status of pnp to be enabled or disabled based on the bool
---@param active? boolean
---@param ignoreWhitelist? boolean
function pings.pnpSetEnabled(active, ignoreWhitelist)
	PushNPull.functions.setEnabled(active, ignoreWhitelist)
end

---Stores all the necessary pnp data to the avatar store
---@param tbl table|nil
function PushNPull.functions.avatarStore(tbl)
	avatar:store("PushNPull", tbl or PushNPull.avatarVar)
	return PushNPull.avatarVar;
end

--- Sets instructions for the targetted entity, if Mode is nil it'll remove the mode (setPos or setVel come to mind), if vector is nil, it'll remove the vector thus nothing happening.
---@param target string|Entity
---@param instructionMode string|nil
---@param instruction {value:Vector3, timer?:number, extra:any}|nil
function PushNPull.functions.setInstruction(target, instructionMode, instruction)
	if type(target) ~= "string" then
		target = target:getUUID()
	end
	local inst = PushNPull.avatarVar.instructions;

	if instructionMode then
		inst[target] = inst[target] or {};
		if instruction and type(instruction.value):lower():find("vector") then
			instruction.value = { instruction.value:unpack() }
			instruction.timer = instruction.timer or 5
		end

		inst[target][instructionMode] = instruction;
	else
		inst[target] = nil;
	end

	PushNPull.functions.avatarStore();
end

function events.entity_init()
	PushNPull.playerName = player:getName()
	PushNPull.playerUUID = player:getUUID()

	PushNPull.avatarVar = {
		VERSION = PushNPull.VERSION,
		enabled = PushNPull.active,
		whileGrabbing = PushNPull.functions.whileGrabbing,
		instructions = {},
		
		ignoreWhitelist = PushNPull.ignoreWhitelist,
		whitelist = PushNPull.WhitelistedPlayers, -- You can remove this if you don't want to expose your whitelist.
		clientIsWhitelisted = PushNPull.ignoreWhitelist or
			(PushNPull.WhitelistedPlayers[client:getViewer():getUUID()] ~= nil) or
			(PushNPull.WhitelistedPlayers[client:getViewer():getName()] ~= nil)
	}

	PushNPull.functions.avatarStore(PushNPull.avatarVar)
end

-- Does instructions timeouts, pretty much counts them down to 0 and removes them if needed
function events.tick()
	for uuid, instructions in pairs(PushNPull.avatarVar.instructions) do
		if instructions then
			for mode, value in pairs(instructions) do
				value.timer = value.timer - 1
				if value.timer <= 0 then
					PushNPull.functions.setInstruction(uuid, mode, nil)
				end
			end
		end
	end
end

local worldTime = 0;
-- Main Instruction handler, Don't touch anything here FOR SURE if you don't know what you're doing.
function events.render()
	if not PushNPull.active then return; end

	for name, grabber in pairs(world.getPlayers()) do
		-- Simple whitelist checking, not exactly that expensive, only grows with more players loaded tbh
		if not ((PushNPull.WhitelistedPlayers[name] or PushNPull.WhitelistedPlayers[grabber:getUUID()]) ~= nil or PushNPull.ignoreWhitelist) then goto EndWhitelist end

		--Grabs variables from the player
		local vars = PushNPull.functions.grabVariables(grabber)
		--Simple checking
		if vars and vars.enabled and vars.instructions then
			-- Checks if there's any instructions from this player TO YOU, so if they're telling you to do XYZ
			local instructions = vars.instructions[PushNPull.playerUUID] or
				vars.instructions[PushNPull.playerName];

			-- If there is then fire up this block
			if instructions then
				for mode, inst in pairs(instructions) do
					pcall(function()
						--Gets the type in key, something like "setPos" or "setVel" for example, and runs it using the value
						PushNPull.movementFunctions[mode](inst.value);

						--Only does it once per tick, so that it doesnt spam codeblocks, this event was originally in tick but got changed to render due to lagginess with tick
						if world.getTime() ~= worldTime then
							worldTime = world.getTime();
							vars.whileGrabbing(player, inst, mode, player:getVariable());
							PushNPull.functions.whileGrabbed(grabber, inst, mode,
								grabber:getVariable());
						end
					end)
				end
			end
		end

		::EndWhitelist::
	end
end

-- Some basic syncing, remove this if you want but it'll cause some desync
function events.tick()
	if world.getTime() % 100 == 0 then
		pings.pnpSetEnabled(PushNPull.active, PushNPull.ignoreWhitelist)
	end
end

if host:isHost() and PushNPull.autoActionWheel then
	function events.entity_init()
		-- you can see my code did a massive nosedive here because i got tired of this project
		if config:load("PNPActive") ~= nil then
			PushNPull.active = config:load("PNPActive")
		end
		if config:load("PNPIgnoreWhitelist") ~= nil then
			PushNPull.ignoreWhitelist = config:load("PNPIgnoreWhitelist")
		end

		local function isEnabled()
			return { text = (PushNPull.active and "PNP Enabled" or "PNP Disabled"), color = (PushNPull.active and "#60b044" or "#d24a4a") }
		end

		local function isWhitelist()
			return { text = (PushNPull.ignoreWhitelist and "Whitelist Disabled" or "Whitelist Enabled"), color = (PushNPull.ignoreWhitelist and "#d24a4a" or "#60b044") }
		end

		local page = action_wheel:getCurrentPage()
		if not page then
			page = action_wheel:newPage("Main Page")
			action_wheel:setPage(page)
		end

		page:newAction():setTitle(toJson({ isEnabled(), "\n", isWhitelist() }))
			:toggleColor(0.3, 0.4, 0.8)
			:item("minecraft:lead")
			:setOnLeftClick(function(self)
				PushNPull.active = not PushNPull.active;
				config:save("PNPActive", PushNPull.active)
				pings.pnpSetEnabled(PushNPull.active)
				printJson(toJson(isEnabled()))
				self:setTitle(toJson({ isEnabled(), "\n", isWhitelist() }))
			end)
			:setOnRightClick(function(self)
				PushNPull.ignoreWhitelist = not PushNPull.ignoreWhitelist;
				config:save("PNPIgnoreWhitelist", PushNPull.ignoreWhitelist)
				pings.pnpSetEnabled(nil, PushNPull.ignoreWhitelist)
				printJson(toJson(isWhitelist()))
				self:setTitle(toJson({ isEnabled(), "\n", isWhitelist() }))
			end)
	end
end


return PushNPull;
