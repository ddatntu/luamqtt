--[[

Here is a MQTT v5.0 protocol implementation

MQTT v5.0 documentation (DOC):
	http://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html

]]

-- module table
local protocol5 = {}


-- MQTT protocol version
protocol5.version = "v5.0"


-- required modules
local string = require("string")
local bit = require("mqtt.bit")
local protocol = require("mqtt.protocol")

-- cache to locals
local assert = assert
local tostring = tostring
local setmetatable = setmetatable
local error = error
local str_sub = string.sub
local str_byte = string.byte
local str_char = string.char
local bor = bit.bor
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift
local make_uint8 = protocol.make_uint8
local make_uint16 = protocol.make_uint16
local make_uint32 = protocol.make_uint32
local make_string = protocol.make_string
local make_var_length = protocol.make_var_length
local make_header = protocol.make_header
local check_qos = protocol.check_qos
local check_packet_id = protocol.check_packet_id
local combine = protocol.combine
local parse_var_length = protocol.parse_var_length
local packet_type = protocol.packet_type
local packet_mt = protocol.packet_mt


-- Create Connect Flags data, DOC: 3.1.2.3 Connect Flags
local function make_connect_flags(args)
	local byte = 0 -- bit 0 should be zero
	-- DOC: 3.1.2.4 Clean Start
	if args.clean ~= nil then
		assert(type(args.clean) == "boolean", "expecting .clean to be a boolean")
		if args.clean then
			byte = bor(byte, lshift(1, 1))
		end
	end
	-- DOC: 3.1.2.5 Will Flag
	if args.will ~= nil then
		-- check required args are presented
		assert(type(args.will) == "table", "expecting .will to be a table")
		assert(type(args.will.payload) == "string", "expecting .will.payload to be a string")
		assert(type(args.will.topic) == "string", "expecting .will.topic to be a string")
		assert(type(args.will.qos) == "number", "expecting .will.qos to be a number")
		assert(check_qos(args.will.qos), "expecting .will.qos to be a valid QoS value")
		assert(type(args.will.retain) == "boolean", "expecting .will.retain to be a boolean")
		assert(type(args.will.properties) == "table", "expecting .will.properties to be a table")
		-- will flag should be set to 1
		byte = bor(byte, lshift(1, 2))
		-- DOC: 3.1.2.6 Will QoS
		byte = bor(byte, lshift(args.will.qos, 3))
		-- DOC: 3.1.2.7 Will Retain
		if args.will.retain then
			byte = bor(byte, lshift(1, 5))
		end
	end
	-- DOC: 3.1.2.8 User Name Flag
	if args.username ~= nil then
		assert(type(args.username) == "string", "expecting .username to be a string")
		byte = bor(byte, lshift(1, 7))
	end
	-- DOC: 3.1.2.9 Password Flag
	if args.password ~= nil then
		assert(type(args.password) == "string", "expecting .password to be a string")
		assert(args.username, "the .username is required to set .password")
		byte = bor(byte, lshift(1, 6))
	end
	return make_uint8(byte)
end

-- Make data for 1-byte property with only 0 or 1 value
local function make_uint8_0_or_1(value)
	if value ~= 0 and value ~= 1 then
		error("expecting 0 or 1 as value")
	end
	return make_uint8(value)
end

-- Known property names and its identifiers, DOC: 2.2.2.2 Property
local property_pairs = {
	{ 0x01, "payload_format_indicator",
		make = make_uint8_0_or_1,
		parse = function(read_func) error("not implemented") end, },
	{ 0x02, "message_expiry_interval",
		make = make_uint32,
		parse = function(read_func) error("not implemented") end, },
	{ 0x03, "content_type",
		make = make_string,
		parse = function(read_func) error("not implemented") end, },
	{ 0x08, "response_topic",
		make = make_string,
		parse = function(read_func) error("not implemented") end, },
	{ 0x09, "correlation_data",
		make = make_string, -- TODO: make_binary_data
		parse = function(read_func) error("not implemented") end, },
	{ 0x0B, "subscription_identifier",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x11, "session_expiry_interval",
		make = make_uint32,
		parse = function(read_func) error("not implemented") end, },
	{ 0x12, "assigned_client_identifier",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x13, "server_keep_alive",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x15, "authentication_method",
		make = make_string,
		parse = function(read_func) error("not implemented") end, },
	{ 0x16, "authentication_data",
		make = make_string, -- TODO: make_binary_data
		parse = function(read_func) error("not implemented") end, },
	{ 0x17, "request_problem_information",
		make = make_uint8_0_or_1,
		parse = function(read_func) error("not implemented") end, },
	{ 0x18, "will_delay_interval",
		make = make_uint32,
		parse = function(read_func) error("not implemented") end, },
	{ 0x19, "request_response_information",
		make = make_uint8_0_or_1,
		parse = function(read_func) error("not implemented") end, },
	{ 0x1A, "response_information",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x1C, "server_reference_",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x1F, "reason_string",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x21, "receive_maximum",
		make = make_uint16,
		parse = function(read_func) error("not implemented") end, },
	{ 0x22, "topic_alias_maximum",
		make = make_uint16,
		parse = function(read_func) error("not implemented") end, },
	{ 0x23, "topic_alias",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x24, "maximum_qos",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x25, "retain_available",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x26, "user_property",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x27, "maximum_packet_size",
		make = make_uint32,
		parse = function(read_func) error("not implemented") end, },
	{ 0x28, "wildcard_subscription_available",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x29, "subscription_identifier_available",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x2A, "shared_subscription_available",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
}

-- properties table with keys in two directions: from name to identifier and back
local properties = {}
-- table with property value make functions
local property_make = {}
-- table with property value parse function
local property_parse = {}
-- fill the properties and property_make tables
for _, prop in ipairs(property_pairs) do
	properties[prop[2]] = prop[1]			-- name ==> identifier
	properties[prop[1]] = prop[2]			-- identifier ==> name
	property_make[prop[1]] = prop.make		-- identifier ==> make function
	property_parse[prop[1]] = prop.parse	-- identifier ==> make function
end

-- Allowed properties per packet type
local allowed_properties = {
	-- DOC: 3.1.2.11 CONNECT Properties
	[packet_type.CONNECT] = {
		[0x11] = true, -- DOC: 3.1.2.11.2 Session Expiry Interval
		[0x21] = true, -- DOC: 3.1.2.11.3 Receive Maximum
		[0x27] = true, -- DOC: 3.1.2.11.4 Maximum Packet Size
		[0x22] = true, -- DOC: 3.1.2.11.5 Topic Alias Maximum
		[0x19] = true, -- DOC: 3.1.2.11.6 Request Response Information
		[0x17] = true, -- DOC: 3.1.2.11.7 Request Problem Information
		[0x26] = true, -- DOC: 3.1.2.11.8 User Property
		[0x15] = true, -- DOC: 3.1.2.11.9 Authentication Method
		[0x16] = true, -- DOC: 3.1.2.11.10 Authentication Data
	},
	-- TODO
}

-- Create properties field for various control packets, DOC: 2.2.2 Properties
local function make_properties(ptype, args)
	local allowed = assert(allowed_properties[ptype], "invalid packet type to detect allowed properties")
	local props = ""
	local uprop_id = properties.user_property
	-- writing known properties
	if args.properties ~= nil then
		assert(type(args.properties) == "table", "expecting .properties to be a table")
		for name, value in pairs(args.properties) do
			assert(type(name) == "string", "expecting property name to be a string: "..tostring(name))
			-- detect property identifier and check it's allowed for that packet type
			local prop_id = assert(properties[name], "unknown property: "..tostring(name))
			assert(prop_id ~= uprop_id, "user properties should be passed in .user_properties table")
			assert(allowed[prop_id], "property "..name.." is not allowed for packet type "..ptype)
			-- make property data
			local ok, val = pcall(property_make[prop_id], value)
			if not ok then
				error("invalid property value: "..name.." = "..tostring(value))
			end
			local prop = combine(
				str_char(make_var_length(prop_id)),
				val
			)
			-- and append it to props
			if type(props) == "string" then
				props = combine(prop)
			else
				props:append(prop)
			end
		end
	end
	-- writing userproperties
	if args.user_properties ~= nil then
		assert(type(args.user_properties) == "table", "expecting .user_properties to be a table")
		assert(allowed[uprop_id], "user_property is not allowed for packet type "..ptype)
		for name, value in pairs(args.user_properties) do
			if type(name) == "number" and type(value) == "table" then
				-- this is a {"name", "value"} array item, not name = "value" pair
				name = value[1]
				value = value[2]
			end
			assert(type(name) == "string", "expecting user property name to be a string: "..tostring(name))
			assert(type(value) == "string", "expecting user property value to be a string: "..tostring(value))
			-- make user property data
			local prop = combine(
				str_char(make_var_length(uprop_id)),
				make_string(name),
				make_string(value)
			)
			-- and append it to props
			if type(props) == "string" then
				props = combine(prop)
			else
				props:append(prop)
			end
		end
	end
	-- and combine properties with its length field
	return combine(
		str_char(make_var_length(props:len())),		-- DOC: 2.2.2.1 Property Length
		props										-- DOC: 2.2.2.2 Property
	)
end

-- Create CONNECT packet, DOC: 3.1 CONNECT – Connection Request
local function make_packet_connect(args)
	-- check args
	assert(type(args.id) == "string", "expecting .id to be a string with MQTT client id")
	-- DOC: 3.1.2.10 Keep Alive
	local keep_alive_ival = 0
	if args.keep_alive then
		assert(type(args.keep_alive) == "number")
		keep_alive_ival = args.keep_alive
	end
	-- DOC: 3.1.2.11 CONNECT Properties
	local props = make_properties(packet_type.CONNECT, args)
	-- DOC: 3.1.2 CONNECT Variable Header
	local variable_header = combine(
		make_string("MQTT"), 				-- DOC: 3.1.2.1 Protocol Name
		make_uint8(5), 						-- DOC: 3.1.2.2 Protocol Version (5 is for MQTT v5.0)
		make_connect_flags(args), 			-- DOC: 3.1.2.3 Connect Flags
		make_uint16(keep_alive_ival), 		-- DOC: 3.1.2.10 Keep Alive
		props								-- DOC: 3.1.2.11 CONNECT Properties
	)
	-- DOC: 3.1.3 CONNECT Payload
	-- DOC: 3.1.3.1 Client Identifier (ClientID)
	local payload = combine(
		make_string(args.id)
	)
	if args.will then
		-- DOC: 3.1.3.2 Will Properties
		payload:append(make_properties(packet_type.PUBLISH, args.will))
		-- DOC: 3.1.3.3 Will Topic
		payload:append(make_string(args.will.topic))
		-- DOC: 3.1.3.4 Will Payload
		payload:append(make_string(args.will.payload))
	end
	if args.username then
		-- DOC: 3.1.3.5 User Name
		payload:append(make_string(args.username))
		if args.password then
			-- DOC: 3.1.3.6 Password
			payload:append(make_string(args.password))
		end
	end
	-- DOC: 3.1.1 Fixed header
	local header = make_header(packet_type.CONNECT, 0, variable_header:len() + payload:len())
	return combine(header, variable_header, payload)
end


-- Create packet of given {type: number} in args
function protocol5.make_packet(args)
	assert(type(args) == "table", "expecting args to be a table")
	assert(type(args.type) == "number", "expecting .type number in args")
	local ptype = args.type
	if ptype == packet_type.CONNECT then
		return make_packet_connect(args)
	elseif ptype == packet_type.PUBLISH then
		return make_packet_publish(args)
	elseif ptype == packet_type.PUBACK then
		return make_packet_puback(args)
	elseif ptype == packet_type.PUBREC then
		return make_packet_pubrec(args)
	elseif ptype == packet_type.PUBREL then
		return make_packet_pubrel(args)
	elseif ptype == packet_type.PUBCOMP then
		return make_packet_pubcomp(args)
	elseif ptype == packet_type.SUBSCRIBE then
		return make_packet_subscribe(args)
	elseif ptype == packet_type.UNSUBSCRIBE then
		return make_packet_unsubscribe(args)
	elseif ptype == packet_type.PINGREQ then
		-- DOC: 3.12 PINGREQ – PING request
		return combine("\192\000") -- 192 == 0xC0, type == 12, flags == 0
	elseif ptype == packet_type.DISCONNECT then
		-- DOC: 3.14 DISCONNECT – Disconnect notification
		return combine("\224\000") -- 224 == 0xD0, type == 14, flags == 0
	else
		error("unexpected packet type to make: "..ptype)
	end
end

-- Parse packet using given read_func
-- Returns packet on success or false and error message on failure
function protocol5.parse_packet(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")

	-- TODO: 2.1.3 Flags

	error("not implemented")
end

-- export module table
return protocol5

-- vim: ts=4 sts=4 sw=4 noet ft=lua
