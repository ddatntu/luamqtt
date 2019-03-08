-- busted -e 'package.path="./?/init.lua;./?.lua;"..package.path' tests/spec/protocol5-make.lua
-- DOC: https://docs.oasis-open.org/mqtt/mqtt/v5.0/cos02/mqtt-v5.0-cos02.html

describe("MQTT v5.0 protocol: making packets", function()
	local tools = require("mqtt.tools")
	local protocol = require("mqtt.protocol")
	local protocol5 = require("mqtt.protocol5")

	it("CONNECT with minimal properties", function()
		assert.are.equal(
			tools.extract_hex[[
				10						-- packet type == 1 (CONNECT), flags == 0
				18						-- length == 0x18 == 24 bytes

											-- next is 24 bytes for variable header and payload:

					0004 4D515454			-- protocol name == "MQTT"
					05						-- protocol version == 5 for MQTT v5.0
					00						-- connect flags == 0: clean=false, will=false, will_qos=0, will_retaion=false, password=false, username=false
					0000					-- keep alive
					00						-- connect properties length

											-- next is payload

					000B 636C69656E742D69642D35	-- client id string
			]],
			tools.hex(tostring(protocol5.make_packet{
				type = protocol.packet_type.CONNECT,
				id = "client-id-5",
			}))
		)
	end)
end)

-- vim: ts=4 sts=4 sw=4 noet ft=lua
