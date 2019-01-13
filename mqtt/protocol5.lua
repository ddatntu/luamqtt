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
local table = require("table")
local string = require("string")
local bit = require("mqtt.bit")
local protocol = require("mqtt.protocol")

-- cache to locals
local assert = assert
local tostring = tostring
local setmetatable = setmetatable
local error = error
local tbl_sort = table.sort
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

-- Read string using given read_func function
-- Returns false plus error message on failure
-- Returns parsed string on success
local function parse_string(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local len, err = read_func(2)
	if not len then
		return false, "failed to read string length: "..err
	end
	-- convert len string from 2-byte integer
	local byte1, byte2 = str_byte(len, 1, 2)
	len = bor(lshift(byte1, 8), byte2)
	-- and return string if parsed length
	return read_func(len)
end

-- Parse uint8 value using given read_func
local function parse_uint8(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local value, err = read_func(1)
	if not value then
		return false, "failed to read 1 byte for uint8: "..err
	end
	return str_byte(value, 1, 1)
end

-- Parse uint8 value with only 0 or 1 value
local function parse_uint8_0_or_1(read_func)
	local value, err = parse_uint8(read_func)
	if not value then
		return false, err
	end
	if value ~= 0 and value ~= 1 then
		return false, "expecting only 0 or 1 but got: "..value
	end
	return value
end

-- Parse uint16 value using given read_func
local function parse_uint16(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local value, err = read_func(2)
	if not value then
		return false, "failed to read 2 byte for uint16: "..err
	end
	local byte1, byte2 = str_byte(value, 1, 2)
	return lshift(byte1, 8) + byte2
end

-- Parse uint32 value using given read_func
local function parse_uint32(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local value, err = read_func(4)
	if not value then
		return false, "failed to read 4 byte for uint32: "..err
	end
	local byte1, byte2, byte3, byte4 = str_byte(value, 1, 4)
	return lshift(byte1, 24) + lshift(byte2, 16) + lshift(byte3, 8) + byte4
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
		parse = parse_uint32, },
	{ 0x12, "assigned_client_identifier",
		make = function(value) error("not implemented") end,
		parse = parse_string, },
	{ 0x13, "server_keep_alive",
		make = function(value) error("not implemented") end,
		parse = parse_uint16, },
	{ 0x15, "authentication_method",
		make = make_string,
		parse = parse_string, },
	{ 0x16, "authentication_data",
		make = make_string, -- TODO: make_binary_data
		parse = parse_string, },
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
		parse = parse_string, },
	{ 0x1C, "server_reference",
		make = function(value) error("not implemented") end,
		parse = parse_string, },
	{ 0x1F, "reason_string",
		make = function(value) error("not implemented") end,
		parse = parse_string, },
	{ 0x21, "receive_maximum",
		make = make_uint16,
		parse = parse_uint16, },
	{ 0x22, "topic_alias_maximum",
		make = make_uint16,
		parse = parse_uint16, },
	{ 0x23, "topic_alias",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x24, "maximum_qos",
		make = function(value) error("not implemented") end,
		parse = parse_uint8_0_or_1, },
	{ 0x25, "retain_available",
		make = function(value) error("not implemented") end,
		parse = parse_uint8, },
	{ 0x26, "user_property",
		make = function(value) error("not implemented") end,
		parse = function(read_func) error("not implemented") end, },
	{ 0x27, "maximum_packet_size",
		make = make_uint32,
		parse = parse_uint32, },
	{ 0x28, "wildcard_subscription_available",
		make = function(value) error("not implemented") end,
		parse = parse_uint8_0_or_1, },
	{ 0x29, "subscription_identifier_available",
		make = function(value) error("not implemented") end,
		parse = parse_uint8_0_or_1, },
	{ 0x2A, "shared_subscription_available",
		make = function(value) error("not implemented") end,
		parse = parse_uint8_0_or_1, },
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
	[packet_type.CONNACK] = {
		[0x11] = true, -- DOC: 3.2.2.3.2 Session Expiry Interval
		[0x21] = true, -- DOC: 3.2.2.3.3 Receive Maximum
		[0x24] = true, -- DOC: 3.2.2.3.4 Maximum QoS
		[0x25] = true, -- DOC: 3.2.2.3.5 Retain Available
		[0x27] = true, -- DOC: 3.2.2.3.6 Maximum Packet Size
		[0x12] = true, -- DOC: 3.2.2.3.7 Assigned Client Identifier
		[0x22] = true, -- DOC: 3.2.2.3.8 Topic Alias Maximum
		[0x1F] = true, -- DOC: 3.2.2.3.9 Reason String
		[0x26] = true, -- DOC: 3.2.2.3.10 User Property
		[0x28] = true, -- DOC: 3.2.2.3.11 Wildcard Subscription Available
		[0x29] = true, -- DOC: 3.2.2.3.12 Subscription Identifiers Available
		[0x2A] = true, -- DOC: 3.2.2.3.13 Shared Subscription Available
		[0x13] = true, -- DOC: 3.2.2.3.14 Server Keep Alive
		[0x1A] = true, -- DOC: 3.2.2.3.15 Response Information
		[0x1C] = true, -- DOC: 3.2.2.3.16 Server Reference
		[0x15] = true, -- DOC: 3.2.2.3.17 Authentication Method
		[0x16] = true, -- DOC: 3.2.2.3.18 Authentication Data
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
		-- validate all properties and append them to order list
		local order = {}
		for name, value in pairs(args.properties) do
			assert(type(name) == "string", "expecting property name to be a string: "..tostring(name))
			-- detect property identifier and check it's allowed for that packet type
			local prop_id = assert(properties[name], "unknown property: "..tostring(name))
			assert(prop_id ~= uprop_id, "user properties should be passed in .user_properties table")
			assert(allowed[prop_id], "property "..name.." is not allowed for packet type "..ptype)
			order[#order + 1] = { prop_id, name, value }
		end
		-- sort props in the identifier ascending order
		tbl_sort(order, function(a, b) return a[1] < b[1] end)
		for _, item in ipairs(order) do
			local prop_id, name,  value = unpack(item)
			-- make property data
			local ok, val = pcall(property_make[prop_id], value)
			if not ok then
				error("invalid property value: "..name.." = "..tostring(value)..": "..tostring(val))
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

-- Parse properties using given read_data function for specified packet type
-- Result will be stored in packet.properties and packet.user_properties
-- Returns false plus string with error message on failure
-- Returns true on success
local function parse_properties(ptype, read_data, input, packet)
	assert(type(read_data) == "function", "expecting read_data to be a function")
	-- DOC: 2.2.2 Properties
	-- parse Property Length
	-- create read_func for parse_var_length and other parse functions, reading from data string instead of network connector
	print("parse_properties", input[1], input.available)
	local len = parse_var_length(read_data)
	print("parse_properties", input[1], input.available, len)
	-- check data contains enough bytes for reading properties
	if input.available < len then
		return true, "not enough data to parse properties of length "..len
	end
	-- parse allowed properties
	local uprop_id = properties.user_property
	local allowed = assert(allowed_properties[ptype], "no allowed properties for specified packet type: "..tostring(ptype))
	local props_end = input[1] + len
	while input[1] < props_end do
		-- property id, DOC: 2.2.2.2 Property
		local prop_id, err = parse_var_length(read_data)
		if not prop_id then
			return false, "failed to parse property length: "..err
		end
		if not allowed[prop_id] then
			return false, "property "..prop_id.." is not allowed for packet type "..ptype
		end
		if prop_id == uprop_id then
			-- parse name=value string pair
			local name, value
			name, err = parse_string(read_data)
			if not name then
				return false, "failed to parse user property name: "..err
			end
			value, err = parse_string(read_data)
			if not value then
				return false, "failed to parse user property value: "..err
			end
			packet.user_properties[name] = value
		else
			-- parse property value according its identifier
			local value
			value, err = property_parse[prop_id](read_data)
			if err then
				return false, "failed ro parse property "..prop_id.." value: "..err
			end
			packet.properties[properties[prop_id]] = value
		end
	end
	return true
end

-- Parse packet using given read_func
-- Returns packet on success or false and error message on failure
function protocol5.parse_packet(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	-- parse fixed header
	local byte1, byte2, err, len, data, rc
	byte1, err = read_func(1)
	if not byte1 then
		return false, "failed to read first byte: "..err
	end
	byte1 = str_byte(byte1, 1, 1)
	local ptype = rshift(byte1, 4)
	local flags = band(byte1, 0xF)
	len, err = parse_var_length(read_func)
	if not len then
		return false, "failed to parse remaining length: "..err
	end
	local input = {1, available = 0} -- input data offset and available size
	if len > 0 then
		data, err = read_func(len)
	else
		data = ""
	end
	if not data then
		return false, "failed to read packet data: "..err
	end
	local data_len = data:len() -- TODO: remove?
	input.available = data_len
	-- read data function
	local function read_data(size)
		if size > input.available then
			return false, "not enough data to read size: "..size
		end
		local off = input[1]
		local res = str_sub(data, off, off + size - 1)
		input[1] = off + size
		input.available = input.available - size
		return res
	end
	-- parse readed data according type in fixed header
	if ptype == packet_type.CONNACK then
		-- DOC: 3.2 CONNACK – Connect acknowledgement
		if data_len < 3 then
			return false, "expecting data of length 3 bytes or more"
		end
		-- DOC: 3.2.2.1.1 Session Present
		-- DOC: 3.2.2.2 Connect Reason Code
		byte1, byte2 = parse_uint8(read_data), parse_uint8(read_data)
		local sp = (band(byte1, 0x1) ~= 0)
		local packet = setmetatable({type=ptype, sp=sp, rc=byte2, properties={}, user_properties={}}, packet_mt)
		-- DOC: 3.2.2.3 CONNACK Properties
		local ok
		ok, err = parse_properties(ptype, read_data, input, packet)
		if not ok then
			return false, "failed to parse packet properties: "..err
		end
		if input.available > 0 then
			return false, "extra data in remaining length left after packet parsing"
		end
		return packet
	elseif ptype == packet_type.PUBLISH then
		-- DOC: 3.3 PUBLISH – Publish message
		-- DOC: 3.3.1.1 DUP
		local dup = (band(flags, 0x8) ~= 0)
		-- DOC: 3.3.1.2 QoS
		local qos = band(rshift(flags, 1), 0x3)
		-- DOC: 3.3.1.3 RETAIN
		local retain = (band(flags, 0x1) ~= 0)
		-- DOC: 3.3.2.1 Topic Name
		if data_len < 2 then
			return false, "expecting data of length at least 2 bytes"
		end
		byte1, byte2 = str_byte(data, 1, 2)
		local topic_len = bor(lshift(byte1, 8), byte2)
		if data_len < 2 + topic_len then
			return false, "malformed PUBLISH packet: not enough data to parse topic"
		end
		local topic = str_sub(data, 3, 3 + topic_len - 1)
		-- DOC: 3.3.2.2 Packet Identifier
		local packet_id, packet_id_len = nil, 0
		if qos > 0 then
			-- DOC: 3.3.2.2 Packet Identifier
			if data_len < 2 + topic_len + 2 then
				return false, "malformed PUBLISH packet: not enough data to parse packet_id"
			end
			byte1, byte2 = str_byte(data, 3 + topic_len, 3 + topic_len + 1)
			packet_id = bor(lshift(byte1, 8), byte2)
			packet_id_len = 2
		end
		-- DOC: 3.3.3 Payload
		local payload
		if data_len > 2 + topic_len + packet_id_len then
			payload = str_sub(data, 2 + topic_len + packet_id_len + 1)
		end
		return setmetatable({type=ptype, dup=dup, qos=qos, retain=retain, packet_id=packet_id, topic=topic, payload=payload}, packet_mt)
	elseif ptype == packet_type.PUBACK then
		-- DOC: 3.4 PUBACK – Publish acknowledgement
		if data_len ~= 2 then
			return false, "expecting data of length 2 bytes"
		end
		-- DOC: 3.4.2 Variable header
		byte1, byte2 = str_byte(data, 1, 2)
		return setmetatable({type=ptype, packet_id=bor(lshift(byte1, 8), byte2)}, packet_mt)
	elseif ptype == packet_type.PUBREC then
		-- DOC: 3.5 PUBREC – Publish received (QoS 2 publish received, part 1)
		if data_len ~= 2 then
			return false, "expecting data of length 2 bytes"
		end
		-- DOC: 3.5.2 Variable header
		byte1, byte2 = str_byte(data, 1, 2)
		return setmetatable({type=ptype, packet_id=bor(lshift(byte1, 8), byte2)}, packet_mt)
	elseif ptype == packet_type.PUBREL then
		-- DOC: 3.6 PUBREL – Publish release (QoS 2 publish received, part 2)
		if data_len ~= 2 then
			return false, "expecting data of length 2 bytes"
		end
		-- also flags should be checked to equals 2 by the server
		-- DOC: 3.6.2 Variable header
		byte1, byte2 = str_byte(data, 1, 2)
		return setmetatable({type=ptype, packet_id=bor(lshift(byte1, 8), byte2)}, packet_mt)
	elseif ptype == packet_type.PUBCOMP then
		-- 3.7 PUBCOMP – Publish complete (QoS 2 publish received, part 3)
		if data_len ~= 2 then
			return false, "expecting data of length 2 bytes"
		end
		-- DOC: 3.7.2 Variable header
		byte1, byte2 = str_byte(data, 1, 2)
		return setmetatable({type=ptype, packet_id=bor(lshift(byte1, 8), byte2)}, packet_mt)
	elseif ptype == packet_type.SUBACK then
		-- DOC: 3.9 SUBACK – Subscribe acknowledgement
		if data_len ~= 3 then
			return false, "expecting data of length 3 bytes"
		end
		-- DOC: 3.9.2 Variable header
		-- DOC: 3.9.3 Payload
		byte1, byte2, rc = str_byte(data, 1, 3)
		return setmetatable({type=ptype, packet_id=bor(lshift(byte1, 8), byte2), rc=rc, failure=(rc == 0x80)}, packet_mt)
	elseif ptype == packet_type.UNSUBACK then
		-- DOC: 3.11 UNSUBACK – Unsubscribe acknowledgement
		if data_len ~= 2 then
			return false, "expecting data of length 2 bytes"
		end
		-- DOC: 3.11.2 Variable header
		byte1, byte2 = str_byte(data, 1, 2)
		return setmetatable({type=ptype, packet_id=bor(lshift(byte1, 8), byte2)}, packet_mt)
	elseif ptype == packet_type.PINGRESP then
		-- DOC: 3.13 PINGRESP – PING response
		if data_len ~= 0 then
			return false, "expecting data of length 0 bytes"
		end
		return setmetatable({type=ptype}, packet_mt)
	else
		return false, "unexpected packet type received: "..tostring(ptype)
	end
end

-- export module table
return protocol5

-- vim: ts=4 sts=4 sw=4 noet ft=lua
