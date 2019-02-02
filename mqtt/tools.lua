-- module table
local tools = {}

-- required modules
local math = require("math")
local table = require("table")
local string = require("string")

-- cache to locals
local str_format = string.format
local str_byte = string.byte
local tbl_concat = table.concat
local math_floor = math.floor


-- Returns string encoded as HEX
function tools.hex(str)
	local res = {}
	for i = 1, #str do
		res[i] = str_format("%02X", str_byte(str, i))
	end
	return tbl_concat(res)
end

-- Integer division function
function tools.div(x, y)
	return math_floor(x / y)
end

-- Extract only HEX symbols from each line of str, ignoring comments after "--"
function tools.extract_hex(str)
	local res = {}
	-- iterate through lines
	for line in str:gmatch("[^\n]+") do
		-- find a comment start
		local comment_begin = line:find("--", 1, true)
		if comment_begin then
			line = line:sub(1, comment_begin - 1)
		end
		-- remove all non-hex symbols
		line = line:gsub("[^0-9A-F]+", "")
		-- and append line to concat list
		res[#res + 1] = line
	end
	return tbl_concat(res)
end

-- export module table
return tools

-- vim: ts=4 sts=4 sw=4 noet ft=lua
