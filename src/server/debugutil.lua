-- Centralized server-only debug logging utility.
-- Structured format: [system][level] message | key=value key=value

local debug = {}

debug.enabled = false -- disable verbose logging in production; set true for troubleshooting

local ALLOWED_LEVELS = {
	init = true,
	state = true,
	decision = true,
	warn = true,
	error = true,
}

local function sanitizeString(value)
	-- Collapse whitespace/newlines to single spaces to keep logs one-line.
	return (string.gsub(tostring(value), "%s+", " "))
end

local function formatValue(value)
	local valueType = typeof(value)

	if valueType == "table" then
		-- Avoid multi-line serialization; tag with table length when possible.
		local length = #value
		if length > 0 then
			return string.format("<table:%d>", length)
		end
		return "<table>"
	end

	if valueType == "Instance" then
		return string.format("<%s:%s>", value.ClassName, value:GetFullName())
	end

	return sanitizeString(value)
end

function debug.log(system, level, message, dataTable)
	if not debug.enabled then
		return
	end

	if type(system) ~= "string" or type(level) ~= "string" or type(message) ~= "string" then
		return
	end

	level = string.lower(level)
	if not ALLOWED_LEVELS[level] then
		return
	end

	system = string.lower(system)
	local line = string.format("[%s][%s] %s", system, level, sanitizeString(message))

	if type(dataTable) == "table" then
		local parts = {}

		for key, value in pairs(dataTable) do
			local safeKey = sanitizeString(key)
			local safeValue = formatValue(value)
			table.insert(parts, string.format("%s=%s", safeKey, safeValue))
		end

		table.sort(parts) -- deterministic ordering

		if #parts > 0 then
			line = string.format("%s | %s", line, table.concat(parts, " "))
		end
	end

	print(line)
end

return debug
