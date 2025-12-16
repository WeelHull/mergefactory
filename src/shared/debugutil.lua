local debugutil = {}

debugutil.enabled = true

local function sanitize(value)
	-- gsub returns the replaced string and a count; capture only the string to avoid leaking extra args
	local cleaned = tostring(value):gsub("%s+", " ")
	return cleaned
end

function debugutil.log(system, level, message, data)
	if not debugutil.enabled then
		return
	end

	if type(system) ~= "string" or type(level) ~= "string" or type(message) ~= "string" then
		return
	end

	local line = string.format("[%s][%s] %s", sanitize(system), sanitize(level), sanitize(message))

	if type(data) == "table" then
		local parts = {}
		for k, v in pairs(data) do
			table.insert(parts, string.format("%s=%s", sanitize(k), sanitize(v)))
		end
		table.sort(parts)
		if #parts > 0 then
			line = line .. " | " .. table.concat(parts, " ")
		end
	end

	print(line)
end

return debugutil
