---@class BetterCommands : module
---@source https://github.com/ZwerOxotnik/factorio-BetterCommands
---@module "__BetterCommands__.BetterCommands.control"
local M = {
	is_commands_added_by_default = true, --[[@type boolean]]
	DEFAULT_MAX_INPUT_LENGTH = 500,   --[[@type uint]]
	COMMAND_PREFIX = nil,             --[[@type string?]] -- TODO: store as global data
	is_commands_logged = false,       --[[@type boolean?]]
	global_commands_cooldown = nil,   --[[@type uint?]]
	commands_player_cooldown = nil,   --[[@type uint?]]
}


---@alias BetterCommandType
---| '"player"' # Stops execution if can't find a player by parameter
---| '"team"' # Stops execution if can't find a team (force) by parameter

---@class BetterCommand
---@field name string? # The name of your /command. (default: key of the table)
---@field description string|LocalisedString? # The description of your command. (default: nil)
---@field is_allowed_empty_args boolean? # Ignores empty parameters in commands, otherwise stops the command. (default: true)
---@field input_type BetterCommandType? # Filter for parameters by type of input. (default: nil)
---@field allow_for_server boolean?  # Allow execution of a command from a server (default: false)
---@field only_for_admin boolean? # The command can be executed only by admins (default: false)
---@field is_added_by_default boolean? # Default value for switchable commands (default: true)
---@field allow_for_players string[]? # Allows to use the command for players with specified names (default: nil)
---@field max_input_length uint? # Max amount of characters for command (default: 500)
---@field is_logged boolean? # Logs the command into .log file (default: true)
---@field alternative_names string[]? # Alternative names for the command (all commands should be added) (default: nil)
---@field is_one_time_use boolean? # Disables the command after using it (default: false)
---@field is_one_time_use_for_player boolean? # Disables for a player after using it (default: false)
---@field is_one_time_use_for_force  boolean? # Disables for a force after using it (default: false)
-- TODO: ---@field global_cooldown uint? # (default: nil)
-- TODO: ---@field player_cooldown uint? # (default: nil)
-- TODO: ---@field force_cooldown  uint? # (default: nil)
-- TODO: ---@field disable_cooldown_for_admins boolean? # (default: false)
-- TODO: ---@field disable_cooldown_for_server boolean? # (default: true)


---@type table<string, function>
local _all_commands = {} -- commands from other modules


local __mod_path = ""
---@type table<string, BetterCommand>?
local CONST_COMMANDS
---@type table<string, BetterCommand>?
local SWITCHABLE_COMMANDS
if script and commands and settings and settings.global then
	if script.mod_name ~= "level" then
		__mod_path = "__" ..  script.mod_name .. "__"
	end

	local __is_ok, __commands_data = pcall(require, __mod_path .. ".const-commands")
	if __is_ok then
		CONST_COMMANDS = __commands_data
	end
	__is_ok, __commands_data = pcall(require, __mod_path .. ".switchable-commands")
	if __is_ok then
		SWITCHABLE_COMMANDS = __commands_data
	end
end


local _INPUT_TYPES = {
	player = 1,
	team   = 2
}


---@param s string
local function trim(s)
	return s:match'^%s*(.*%S)' or ''
end


---@param command_settings BetterCommand
---@param player LuaPlayer
---@return boolean
function M.is_player_allowed_to_use(command_settings, player)
	if not command_settings.only_for_admin or player.admin then
		return true
	end
	if command_settings.allow_for_players == nil then
		return false
	end

	for _, player_name in pairs(command_settings.allow_for_players) do
		if player_name == player.name then
			return true
		end
	end

	return false
end


---@param message string
---@param player_index? number
-- Sends message to a player or server
local function print_to_caller(message, player_index)
	if not (game and player_index) then
		print(message) -- this message for server
	else
		local player = game.get_player(player_index)
		if player and player.valid then
			player.print(message)
		end
	end
end


---@param error_message string?
---@param player_index  number?
---@param orig_command_name string
local function disable_setting(error_message, player_index, orig_command_name)
	if error_message then
		print_to_caller(error_message, player_index)

		if game then
			for _, player in pairs(game.connected_players) do
				if player.valid and player.admin then
					player.print(error_message)
				end
			end
		end
		log(error_message)
	end

	-- Turns off the command
	if orig_command_name then
		local setting_name = (M.COMMAND_PREFIX or MOD_SHORT_NAME) .. orig_command_name
		if settings.global[setting_name] then
			settings.global[setting_name] = {
				value = false
			}
		end
	end
end


---@param command_name string
---@param is_disabled boolean?
function M._remove_commands(command_name, is_disabled)
	local activated_commands = global.BetterCommands.activated_commands
	local added_commands = activated_commands[command_name]
	if type(added_commands) == "string" then
		if is_disabled then
			--- TODO: add localization
			game.print("Removed command: " .. added_commands)
		end
		commands.remove_command(added_commands)
	else
		if is_disabled then
			--- TODO: add localization and improve
			game.print("Removed command: " .. added_commands[1])
		end
		for _, name in ipairs(added_commands) do
			commands.remove_command(name)
		end
	end
	activated_commands[command_name] = nil
end


---@param command_name string
function M.add_custom_commands(command_name)
	if not game then return end
	local activated_commands = global.BetterCommands.activated_commands
	local original_func = _all_commands[command_name]
	local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name]) or
		(CONST_COMMANDS and CONST_COMMANDS[command_name])
	---@type string[]
	local new_commands = {}

	local new_command_name = M.add_custom_command(command_name, command_settings, original_func)
	if new_command_name then
		new_commands[#new_commands+1] = new_command_name
	else
		log(script.mod_name .. " can't add command \"" .. command_settings.name .. "\"")
	end

	for _, alternative_name in ipairs(command_settings.alternative_names or {}) do
		local new_command_name = M.add_custom_command(command_name, command_settings, original_func, alternative_name)
		if new_command_name then
			new_commands[#new_commands+1] = new_command_name
		else
			log(script.mod_name .. " can't add command \"" .. command_settings.name .. "\" as \"" .. alternative_name .. "\"")
		end
	end

	local custom_names_raw = settings.global[M.COMMAND_PREFIX .. command_name .. "_alternative_names"].value
	for alternative_name in string.gmatch(custom_names_raw, "%g+") do
		local new_command_name = M.add_custom_command(command_name, command_settings, original_func, alternative_name)
		if new_command_name then
			new_commands[#new_commands+1] = new_command_name
		else
			log(script.mod_name .. " can't add command \"" .. command_settings.name .. "\" as \"" .. alternative_name .. "\"")
		end
	end

	if #new_commands == 1 then
		activated_commands[command_name] = new_commands[1]
	elseif #new_commands > 0 then
		activated_commands[command_name] = new_commands
	else
		activated_commands[command_name] = nil
	end
end


---@param orig_command_name string
---@param command_settings BetterCommand
---@param original_func function
---@param alternative_name string?
---@return string? # command name
function M.add_custom_command(orig_command_name, command_settings, original_func, alternative_name)
	local input_type = _INPUT_TYPES[command_settings.input_type]
	local is_allowed_empty_args = command_settings.is_allowed_empty_args
	local new_command_name = alternative_name or command_settings.name
	if commands.commands[new_command_name] then
		new_command_name = (M.COMMAND_PREFIX or MOD_SHORT_NAME) .. new_command_name
		if commands.commands[new_command_name] then
			return
		end
	end

	local disabled_commands = global.BetterCommands.disabled_commands
	local disabled_commands_for_players = global.BetterCommands.disabled_commands_for_players
	local disabled_commands_for_forces  = global.BetterCommands.disabled_commands_for_forces
	local max_input_length = command_settings.max_input_length or M.DEFAULT_MAX_INPUT_LENGTH
	local command_description = command_settings.description or {script.mod_name .. "-commands." .. command_settings.name}
	commands.add_command(new_command_name, command_description, function(cmd)
		local caller
		if cmd.player_index == 0 then
			if command_settings.allow_for_server == false then
				print({"prohibited-server-command"})
				return
			end
		else
			caller = game.get_player(cmd.player_index)
			if not (caller and caller.valid) then return end
			if not M.is_player_allowed_to_use(command_settings, caller) then
				caller.print({"command-output.parameters-require-admin"})
				return
			end
		end

		if disabled_commands[orig_command_name] then
			-- TODO: add localization
			print_to_caller("This command can't be used anymore.", cmd.player_index)
			return
		elseif disabled_commands_for_players[orig_command_name] and
			disabled_commands_for_players[orig_command_name][cmd.player_index]
		then
			-- TODO: add localization
			print_to_caller("This command can't be used by you anymore.", cmd.player_index)
			return
		elseif caller and disabled_commands_for_forces[orig_command_name] and
			disabled_commands_for_forces[orig_command_name][caller.force.index]
		then
			-- TODO: add localization
			print_to_caller("This command can't be used by your force anymore.", cmd.player_index)
			return
		end

		if cmd.parameter == nil then
			if is_allowed_empty_args == false then
				print_to_caller({"", '/' .. new_command_name .. ' ', command_description}, cmd.player_index)
				return
			end
		elseif #cmd.parameter > max_input_length then
			print_to_caller({"", {"description.maximum-length", '=', max_input_length}}, cmd.player_index)
			return
		end

		if cmd.parameter and input_type then
			if input_type == _INPUT_TYPES.player then
				if #cmd.parameter > 32 then
					print_to_caller({"gui-auth-server.username-too-long"}, cmd.player_index)
					return
				else
					cmd.parameter = trim(cmd.parameter)
					local player = game.get_player(cmd.parameter)
					if not (player and player.valid) then
						print_to_caller({"player-doesnt-exist", cmd.parameter}, cmd.player_index)
						return
					end
				end
			elseif input_type == _INPUT_TYPES.team then
				if #cmd.parameter > 52 then
					print_to_caller({"too-long-team-name"}, cmd.player_index)
					return
				else
					cmd.parameter = trim(cmd.parameter)
					local force = game.forces[cmd.parameter]
					if not (force and force.valid) then
						print_to_caller({"force-doesnt-exist", cmd.parameter}, cmd.player_index)
						return
					end
				end
			end
		end

		if command_settings.is_logged ~= false and
			not (command_settings.is_logged or M.is_commands_logged)
		then
			local message

			if caller then
				message = string.format("\"%s\" player", caller.name)
			else
				message = "Server"
			end

			message = string.format("%s used command /%s %s (tick: %d)", message, orig_command_name, (cmd.parameter or ""), cmd.tick)
			log(message)
		end

		-- error handling
		local is_ok, error_message = pcall(original_func, cmd)
		if is_ok then
			if command_settings.is_one_time_use then
				if SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[orig_command_name] then
					disable_setting(nil, cmd.player_index, orig_command_name)
				else
					disabled_commands[orig_command_name] = true
				end
			else
				if command_settings.is_one_time_use_for_player then
					disabled_commands_for_players[orig_command_name] = disabled_commands_for_players[orig_command_name] or {}
					disabled_commands_for_players[orig_command_name][cmd.player_index] = true
				end
				if caller and command_settings.is_one_time_use_for_force then
					disabled_commands_for_forces[orig_command_name] = disabled_commands_for_forces[orig_command_name] or {}
					disabled_commands_for_forces[orig_command_name][caller.force.index] = true
				end
			end
			return
		else
			disable_setting(error_message, cmd.player_index, orig_command_name)
		end
	end)

	return new_command_name
end


---Handles commands of a module
---@param module module your module with commands
function M.handle_custom_commands(module)
	if module == nil then
		log("Parameter is nil")
		return false
	end
	if type(module.commands) ~= "table" then
		log("Current module doesn't have proper commands")
		return false
	end

	for command_name, func in pairs(module.commands) do
		local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
		or (CONST_COMMANDS and CONST_COMMANDS[command_name])
		if not command_settings then
			goto continue
		end

		if _all_commands[command_name] then
			log(string.format("[ERROR] \"%s\" command was added before", command_name))
		else
			_all_commands[command_name] = func
		end

		:: continue ::
	end

	return true
end


function M.on_runtime_mod_setting_changed(event)
	if event.setting_type ~= "runtime-global" then return end
	local setting_name = event.setting
	if string.find(setting_name, '^' .. (M.COMMAND_PREFIX or MOD_SHORT_NAME)) == nil then return end

	local command_name = string.gsub(setting_name, '^' .. (M.COMMAND_PREFIX or MOD_SHORT_NAME), "")
	local func = _all_commands[command_name]
	if func == nil then
		setting_name = string.gsub(setting_name, "_alternative_names$", "")
		command_name = string.gsub(command_name, "_alternative_names$", "")
		func = _all_commands[command_name]
		if command_name and func and settings.global[setting_name].value then
			M._remove_commands(command_name)
			M.add_custom_commands(command_name)
		end
		return
	end

	if SWITCHABLE_COMMANDS == nil then return end
	local command_settings = SWITCHABLE_COMMANDS[command_name]
	command_settings.name = command_settings.name or command_name
	local activated_commands = global.BetterCommands.activated_commands
	if settings.global[setting_name].value == true then
		M.add_custom_commands(command_name)
		local added_commands = activated_commands[command_name]
		if added_commands then
			if type(added_commands) == "string" then
				--- TODO: add localization and improve
				game.print("Added command: " .. added_commands)
				activated_commands[command_name] = added_commands
			else -- table
				--- TODO: add localization and improve
				game.print("Added command: " .. added_commands[1])
				activated_commands[command_name] = added_commands[1]
			end
		else
			local message = script.mod_name .. " can't add command \"" .. command_settings.name .. "\""
			disable_setting(message, nil, command_name)
		end
	elseif activated_commands[command_name] then
		M._remove_commands(command_name, true)
	end
end


--- Adds settings for commands, so scripts/admins can disable commands via settings
--- Use it during setting stage
---@param mod_name string?
---@param mod_short_name string?
function M.create_settings(mod_name, mod_short_name)
	mod_name = mod_name or MOD_NAME
	mod_short_name = mod_short_name or M.COMMAND_PREFIX

	if mods[mod_name] then
		__mod_path = "__" .. mod_name .. "__."
	end
	local _is_ok, _commands_data = pcall(require, __mod_path .. "const-commands")
	if _is_ok then
		CONST_COMMANDS = _commands_data
	end
	_is_ok, _commands_data = pcall(require, __mod_path .. "switchable-commands")
	if _is_ok then
		SWITCHABLE_COMMANDS = _commands_data
	end

	local new_settings = {}
	if SWITCHABLE_COMMANDS then
		for name, command_settings in pairs(SWITCHABLE_COMMANDS) do
			local command_name = command_settings.name or name
			local description = command_settings.description or {mod_name .. "-commands." .. command_name}
			command_name = '/' .. command_name
			new_settings[#new_settings + 1] = {
				type = "bool-setting",
				name = mod_short_name .. name,
				setting_type = "runtime-global",
				default_value = command_settings.is_added_by_default or M.is_commands_added_by_default,
				localised_name = command_name,
				localised_description = {'', command_name, ' ', description}
			}
			new_settings[#new_settings + 1] = {
				type = "string-setting",
				name = mod_short_name .. name .. "_alternative_names",
				setting_type = "runtime-global",
				default_value = "", allow_blank = true,
				localised_name = {"BetterCommands.command_alternative_names", command_name},
				-- localised_description = {} -- TODO: add all alternative names
			}
		end
	end

	if CONST_COMMANDS then
		for name, command_settings in pairs(CONST_COMMANDS) do
			local command_name = command_settings.name or name
			command_name = '/' .. command_name
			new_settings[#new_settings + 1] = {
				type = "string-setting",
				name = mod_short_name .. name .. "_alternative_names",
				setting_type = "runtime-global",
				default_value = "", allow_blank = true,
				localised_name = {"BetterCommands.command_alternative_names", command_name},
				-- localised_description = {} -- TODO: add all alternative names
			}
		end
	end

	if #new_settings > 0 then
		data:extend(new_settings)
	end
end


local _is_commands_added = false
function M._add_commands()
	if _is_commands_added then return end

	local activated_commands = global.BetterCommands.activated_commands
	if game then
		for command_name in pairs(_all_commands) do
			local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
				or (CONST_COMMANDS and CONST_COMMANDS[command_name]) --[[@as BetterCommand?]]
			if not command_settings then
				goto continue
			end

			command_settings.name = command_settings.name or command_name
			local setting = nil
			if SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name] then
				setting = settings.global[(M.COMMAND_PREFIX or MOD_SHORT_NAME) .. command_name]
			end

			if setting == nil then
				M.add_custom_commands(command_name)
			elseif setting.value then
				M.add_custom_commands(command_name)
				if activated_commands[command_name] == nil then
					local message = script.mod_name .. " can't add command \"" .. command_settings.name .. "\""
					disable_setting(message, nil, command_name)
				end
			elseif activated_commands[command_name] then
				local added_commands = activated_commands[command_name]
				if type(added_commands) == "string" then
					commands.remove_command(added_commands)
				else
					for _, name in ipairs(added_commands) do
						commands.remove_command(name)
					end
				end
				activated_commands[command_name] = nil
			end

			::continue::
		end
	else
		for command_name, _commands in ipairs(activated_commands) do
			local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
				or (CONST_COMMANDS and CONST_COMMANDS[command_name])
			if not command_settings then
				goto continue
			end
			local func = _all_commands[command_name]
			if not func then
				goto continue
			end

			if type(_commands) == "string" then
				local result = M.add_custom_command(_commands, command_settings, func)
				if result == nil then
					log(string.format("WARNING! \"%s\" command wasn't added as \"%s\""), command_name, _commands)
				end
			else
				for _, name in pairs(_commands) do
					local result = M.add_custom_command(name, command_settings, func)
					if result == nil then
						log(string.format("WARNING! \"%s\" command wasn't added as \"%s\""), command_name, name)
					end
				end
			end

			::continue::
		end
	end

	_is_commands_added = true
end


function M._check_settings_data()
	local activated_commands = global.BetterCommands.activated_commands
	for command_name, _commands in pairs(activated_commands) do
		local _type = type(_commands)
		if _type == "string" then
			if commands.commands[_commands] == nil then
				activated_commands[command_name] = nil
			end
		elseif _type == "table" then
			for i=#_commands, 1, -1 do
				local name = _commands[i]
				if commands.commands[name] == nil then
					table.remove(_commands, i)
				end
			end
			if #_commands == 0 then
				activated_commands[command_name] = nil
			end
		else
			activated_commands[command_name] = nil
		end
	end
end


function M.update_global_data()
	global.BetterCommands = global.BetterCommands or {}
	local mod_data = global.BetterCommands
	---@type table<string, string|string[]>
	mod_data.activated_commands = mod_data.activated_commands or {}
	---@type table<string, boolean>
	mod_data.disabled_commands  = mod_data.disabled_commands  or {}
	---@type table<string, table<uint, boolean>>
	mod_data.disabled_commands_for_players = mod_data.disabled_commands_for_players  or {}
	---@type table<string, table<uint, boolean>>
	mod_data.disabled_commands_for_forces = mod_data.disabled_commands_for_forces or {}

	-- Remove data of not existing commands
	local activated_commands = mod_data.activated_commands
	for command_name in pairs(activated_commands) do
		local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
			or (CONST_COMMANDS and CONST_COMMANDS[command_name])
		if command_settings == nil then
			activated_commands[command_name] = nil
		end
	end
	local disabled_commands = mod_data.disabled_commands
	for command_name in pairs(disabled_commands) do
		if SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name] then
			disable_setting(nil, nil, command_name)
			disabled_commands[command_name] = nil
		elseif CONST_COMMANDS and CONST_COMMANDS[command_name] then
			disabled_commands[command_name] = nil
		end
	end
	local disabled_commands_for_players = mod_data.disabled_commands_for_players
	for command_name, players_data in pairs(disabled_commands_for_players) do
		local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
			or (CONST_COMMANDS and CONST_COMMANDS[command_name])
		if command_settings == nil then
			disabled_commands_for_players[command_name] = nil
			goto skip_command
		end
		for player_index in pairs(players_data) do
			local player = game.get_player(player_index)
			if not (player and player.valid) then
				players_data[player_index] = nil
			end
		end
		if next(players_data) == nil then
			disabled_commands_for_players[command_name] = nil
		end
		:: skip_command ::
	end
	local disabled_commands_for_forces = mod_data.disabled_commands_for_forces
	for command_name, forces_data in pairs(disabled_commands_for_forces) do
		local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
			or (CONST_COMMANDS and CONST_COMMANDS[command_name])
		if command_settings == nil then
			disabled_commands_for_forces[command_name] = nil
			goto skip_command
		end
		for force_index in pairs(forces_data) do
			local force = game.forces[force_index]
			if not (force and force.valid) then
				forces_data[force_index] = nil
			end
		end
		if next(forces_data) == nil then
			disabled_commands_for_forces[command_name] = nil
		end
		:: skip_command ::
	end
end


function M.expose_global_data()
	local interface_name = "__" .. script.mod_name .. "__BC"
	remote.remove_interface(interface_name) -- for safety
	remote.add_interface(interface_name, {
		get_global_data_as_json = function()
			if not game then return end
			return game.table_to_json(global)
		end,
		get_global_data_as_string = function()
			return serpent.line(global)
		end,
	})
end


function M.on_init()
	M.update_global_data()
	M._add_commands()
	M._check_settings_data()
end

function M.on_load()
	M._add_commands()
end


function M.on_configuration_changed()
	M.update_global_data()
	M._add_commands()
	M._check_settings_data()
end


M.events = {
	[defines.events.on_runtime_mod_setting_changed] = M.on_runtime_mod_setting_changed
}


return M
