-- TODO: fix localization, handle settings on events more accurately using global data


---@class BetterCommands : module
---@source https://github.com/ZwerOxotnik/factorio-BetterCommands
---@module "BetterCommands.control"
local M = {
	DEFAULT_MAX_INPUT_LENGTH = 500, -- set any number
	COMMAND_PREFIX = nil -- TODO: store as global data
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
---@field default_value boolean? # Default value for settings (default: true)
---@field allow_for_players string[] # Allows to use the command for players with specified names (default: nil)
---@field max_input_length uint # Max amount of characters for command (default: 500)


---@type table<string, BetterCommand>
local _all_commands = {} -- commands from other modules


local __mod_path = ""
if script.mod_name ~= "level" then
	__mod_path = "__" ..  script.mod_name .. "__"
end


local CONST_COMMANDS, SWITCHABLE_COMMANDS
local __is_ok, __commands_data = pcall(require, __mod_path .. ".const-commands")
if __is_ok then
	CONST_COMMANDS = __commands_data
end
__is_ok, __commands_data = pcall(require, __mod_path .. ".switchable-commands")
if __is_ok then
	SWITCHABLE_COMMANDS = __commands_data
end


---@param s string
local function trim(s)
	return s:match'^%s*(.*%S)' or ''
end


---@return boolean
local function remove_command(command_name)
	if commands.remove_command((M.COMMAND_PREFIX or MOD_SHORT_NAME) .. command_name) then
		return true
	else
		return commands.remove_command(command_name)
	end
end


---@param command_settings BetterCommand
---@param player LuaPlayer
---@return boolean
local is_player_allowed_to_use = function(command_settings, player)
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


---@param error_message string
---@param player_index? number
---@param orig_command_name string
local function disable_setting(error_message, player_index, orig_command_name)
	print_to_caller(error_message, player_index)

	local is_message_sended = false
	if game then
		for _, player in pairs(game.connected_players) do
			if player.valid and player.admin then
				player.print(error_message)
				is_message_sended = true
			end
		end
	end
	if is_message_sended == false then
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

local _PLAYER_INPUT_TYPE = 1
local _TEAM_INPUT_TYPE = 2
local _INPUT_TYPES = {
	player = _PLAYER_INPUT_TYPE,
	team   = _TEAM_INPUT_TYPE
}

---@param command_settings BetterCommand
---@param original_func function
---@return boolean
local function add_custom_command(orig_command_name, command_settings, original_func)
	local input_type = _INPUT_TYPES[command_settings.input_type]
	local is_allowed_empty_args = command_settings.is_allowed_empty_args
	local command_name = command_settings.name
	if commands.commands[command_name] then
		command_name = (M.COMMAND_PREFIX or MOD_SHORT_NAME) .. command_name
		if commands.commands[command_name] then
			return false
		end
	end

	local max_input_length = command_settings.max_input_length or M.DEFAULT_MAX_INPUT_LENGTH
	local command_description = command_settings.description or {script.mod_name .. "-commands." .. command_settings.name}
	commands.add_command(command_name, command_description, function(cmd)
		if cmd.player_index == 0 then
			if command_settings.allow_for_server == false then
				print({"prohibited-server-command"})
				return
			end
		else
			local caller = game.get_player(cmd.player_index)
			if not (caller and caller.valid) then return end
			if is_player_allowed_to_use(command_settings, caller) then
				caller.print({"command-output.parameters-require-admin"})
				return
			end
		end

		if cmd.parameter == nil then
			if is_allowed_empty_args == false then
				print_to_caller({"", '/' .. command_name .. ' ', command_description}, cmd.player_index)
				return
			end
		elseif #cmd.parameter > Mmax_input_length then
			print_to_caller({"", {"description.maximum-length", '=', max_input_length}}, cmd.player_index)
			return
		end

		if cmd.parameter and input_type then
			if input_type == _PLAYER_INPUT_TYPE then
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
			elseif input_type == _TEAM_INPUT_TYPE then
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

		-- error handling
		local is_ok, error_message = pcall(original_func, cmd)
		if is_ok then
			return
		else
			disable_setting(error_message, cmd.player_index, orig_command_name)
		end
	end)

	return true
end


---Handles commands of a module
---@param module module your module with commands
function M:handle_custom_commands(module)
	if module == nil then
		log("Parameter is nil")
		return false
	end
	if type(module.commands) ~= "table" then
		log("Current module doesn't have proper commands")
		return false
	end

	for _, added_commands in pairs(_all_commands) do
		if added_commands == module.commands then
			log("Current commands was added before")
			return true
		end
	end
	table.insert(_all_commands, module.commands)

	for command_name, func in pairs(module.commands) do
		local command_settings = (SWITCHABLE_COMMANDS and SWITCHABLE_COMMANDS[command_name])
			or (CONST_COMMANDS and CONST_COMMANDS[command_name])
			or {}
		command_settings.name = command_settings.name or command_name
		local setting = nil
		if SWITCHABLE_COMMANDS[command_name] then
			setting = settings.global[(M.COMMAND_PREFIX or MOD_SHORT_NAME) .. command_name]
		end

		if setting == nil then
			local is_added = add_custom_command(command_name, command_settings, func)
			if is_added == false then
				log(script.mod_name .. " can't add command \"" .. command_settings.name .. "\"")
			end
		elseif setting.value then
			local is_added = add_custom_command(command_name, command_settings, func)
			if is_added == false then
				local message = script.mod_name .. " can't add command \"" .. command_settings.name .. "\""
				disable_setting(message, nil, command_name)
			end
		else
			remove_command(command_settings.name)
		end
	end

	return true
end


---@param command_name string original command name
---@return function?
local function find_func_by_command_name(command_name)
	for _, some_commands in pairs(_all_commands) do
		local func = some_commands[command_name]
		if func then
			return func
		end
	end
end


---@return boolean
local function on_runtime_mod_setting_changed(event)
	if event.setting_type ~= "runtime-global" then return end
	local setting_name = event.setting
	if string.find(setting_name, '^' .. (M.COMMAND_PREFIX or MOD_SHORT_NAME)) ~= 1 then return end

	local command_name = string.gsub(setting_name, '^' .. (M.COMMAND_PREFIX or MOD_SHORT_NAME), "")
	local func = find_func_by_command_name(command_name)
	if func == nil then
		log("Didn't find '" .. command_name .. "' among commands in modules")
	end
	local command_settings = SWITCHABLE_COMMANDS[command_name] or {}
	local state = settings.global[setting_name].value
	command_settings.name = command_settings.name or command_name
	if state == true then
		local is_added = add_custom_command(command_name, command_settings, func)
		if is_added then
			game.print("Added command: " .. command_settings.name or command_name)
		else
			local message = script.mod_name .. " can't add command \"" .. command_settings.name .. "\""
			disable_setting(message, nil, command_name)
		end
	else
		remove_command(command_settings.name or command_name)
		game.print("Removed command: " .. command_settings.name or command_name)
	end

	return true
end


--- Adds settings for commands, so we can disable commands by settings
--- Use it during setting stage
---@param mod_name string?
---@param mod_short_name string?
function M.create_settings(mod_name, mod_short_name)
	mod_name = mod_name or MOD_NAME
	mod_short_name = mod_short_name or MOD_SHORT_NAME

	local new_settings = {}
	for name, command_settings in pairs(SWITCHABLE_COMMANDS) do
		local command_name = command_settings.name or name
		local description = command_settings.description or {mod_name .. "-commands." .. command_name}
		command_name = '/' .. command_name
		new_settings[#new_settings + 1] = {
			type = "bool-setting",
			name = mod_short_name .. name,
			setting_type = "runtime-global",
			default_value = command_settings.default_value or true,
			localised_name = command_name,
			localised_description = {'', command_name, ' ', description}
		}
	end

	if #new_settings > 0 then
		data:extend(new_settings)
	end
end


M.events = {
	[defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed
}


return M
