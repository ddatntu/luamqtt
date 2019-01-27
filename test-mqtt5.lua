local protocol = require("mqtt.protocol")
local protocol5 = require("mqtt.protocol5")
local tools = require("mqtt.tools")


local socket = require("socket")

local conn = socket.connect("mqtt.flespi.io", 1883)

-- 101200044D515454050000000000056162636465
--[[
	10						CONNECT, flags == 0
	12						remaining length == 0x12 == 18
		next is 18 bytes:
		0004 4D515454		"MQTT" - protocol name
		05					protocol version == v5.0
		00					connect flags == 0x00
		0000				keep alive == 0
		00					property length == 0
		0005 6162636465		"abcde" - client id
]]
local connect = protocol5.make_packet{
	type = protocol.packet_type.CONNECT,
	id = "abcde",
	username = "stPwSVV73Eqw5LSv0iMXbc4EguS7JyuZR9lxU5uLxI5tiNM8ToTVqNpu85pFtJv9",
	clean = false,
	properties = {
		session_expiry_interval = 10,
	},
}

local data = tostring(connect)
print("send:", data:len(), tools.hex(data))
conn:send(data)

local packet = protocol5.parse_packet(function(size)
	local part, err = conn:receive(size)
	if not part then
		return false, err
	end
	print("read_func", size, tools.hex(part))
	return part
end)

print(packet)


do return end

print(tools.hex(tostring(connect)))


local connect = protocol5.make_packet{
	type = protocol.packet_type.CONNECT,
	id = "abcde",
	properties = {
		session_expiry_interval = 0xDEADBEEF,
		authentication_method = "some",
	},
	user_properties = {
		-- { "timestamp", "1234567", }
		timestamp = "1234567",
	},
}

print(tools.hex(tostring(connect)))
