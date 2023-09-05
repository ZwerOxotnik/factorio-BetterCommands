local event_handler
if script.active_mods["zk-lib"] then
	-- Same as Factorio "event_handler", but slightly better performance
	local is_ok, zk_event_handler = pcall(require, "__zk-lib__/static-libs/lualibs/event_handler_vZO.lua")
	if is_ok then
		event_handler = zk_event_handler
	end
end
event_handler = event_handler or require("event_handler")


---@type table<string, module>
local modules = {}
modules.better_commands = require("__BetterCommands__/BetterCommands/control")
modules.coreCommands = require("coreCommands")


modules.better_commands.COMMAND_PREFIX = "BCommands_"
modules.better_commands.handle_custom_commands(modules.coreCommands) -- adds commands


event_handler.add_libraries(modules)
