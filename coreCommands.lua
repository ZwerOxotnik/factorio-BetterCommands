local M = {}


---@param cmd CustomCommandData
M.__show_global_data_command = function(cmd)
	local mod_name = "level"
	if cmd.parameter and #cmd.parameter > 0 then
		mod_name = cmd.parameter
	end

	local player
	if cmd.player_index > 0 then
		player = game.get_player(cmd.player_index)
		if not (player and player.valid) then return end
	end

	local interface_name = "__" .. mod_name .. "__BC"
	local interface = remote.interfaces[interface_name]
	if interface == nil or interface.get_global_data_as_json == nil then
		if player then
			-- TODO: add localization
			player.print("Can't get global data of it", {1, 0, 0})
		else
			print("Can't get global data of it")
		end
		return
	end

	local json = remote.call(interface_name, "get_global_data_as_json")
	if type(json) ~= "string" or #json == 0 then
		if player then
			-- TODO: add localization
			player.print("Global data is empty", {0, 1, 0})
		else
			print("Global data is empty")
		end
		return
	end

	if #json < 100 then
		if player then
			player.print(json)
		else
			print(json)
		end
		return
	end


	local file_name = "__global_data_" .. mod_name .. "_BC.json"
	game.write_file(file_name, json, false, cmd.player_index)

	local message = "Global data as json has been saved into script-output/" .. file_name
	if player then
		player.print(message)
	else
		print(message)
	end
end


M.commands = {
	__show_global_data = M.__show_global_data_command,
}


return M
