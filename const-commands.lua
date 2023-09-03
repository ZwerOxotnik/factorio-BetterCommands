--[[ Uses https://github.com/ZwerOxotnik/factorio-BetterCommands
Returns tables of commands without functions as command "settings". All parameters are optional!
  Contains:
    name :: string: The name of your /command. (default: key of the table)
    description :: string or LocalisedString: The description of your command. (default: nil)
    is_allowed_empty_args :: boolean: Ignores empty parameters in commands, otherwise stops the command. (default: true)
    input_type :: string: Filter for parameters by type of input. (default: nil)
      possible variants:
        "player" - Stops execution if can't find a player by parameter
        "team" - Stops execution if can't find a team (force) by parameter
    allow_for_server :: boolean: Allow execution of a command from a server (default: false)
    only_for_admin :: boolean: The command can be executed only by admins (default: false)
	default_value :: boolean: Default value for settings (default: true)
	allow_for_players :: string[]: Allows to use the command for players with specified names (default: nil)
]]--
---@type table<string, BetterCommand>
return {

}
