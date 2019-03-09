-- busted -e 'package.path="./?/init.lua;./?.lua;"..package.path' tests/spec/protocol5-parse.lua
-- DOC: https://docs.oasis-open.org/mqtt/mqtt/v5.0/cos02/mqtt-v5.0-cos02.html

describe("MQTT v5.0 protocol: parsing packets", function()
	local tools = require("mqtt.tools")
	local protocol = require("mqtt.protocol")
	local protocol5 = require("mqtt.protocol5")

	local pt = assert(protocol.packet_type)

	-- returns read_func-compatible function
	local function make_read_func_hex(hex)
		-- decode hex string into data
		local data = {}
		for i = 1, hex:len() / 2 do
			local byte = hex:sub(i*2 - 1, i*2)
			data[#data + 1] = string.char(tonumber(byte, 16))
		end
		data = table.concat(data)
		-- and return read_func
		local data_size = data:len()
		local pos = 1
		return function(size)
			if pos > data_size then
				return false, "no more data available"
			end
			local res = data:sub(pos, pos + size - 1)
			if res:len() ~= size then
				return false, "not enough unparsed data"
			end
			pos = pos + size
			return res
		end
	end

	it("failures", function()
		assert.is_false(protocol5.parse_packet(make_read_func_hex("")))
		assert.is_false(protocol5.parse_packet(make_read_func_hex("01")))
		assert.is_false(protocol5.parse_packet(make_read_func_hex("02")))
		assert.is_false(protocol5.parse_packet(make_read_func_hex("0304")))
		assert.is_false(protocol5.parse_packet(make_read_func_hex("20")))
		assert.is_false(protocol5.parse_packet(make_read_func_hex("20030000"))) -- CONNACK with invalid length
	end)

	it("CONNACK with minimal params and without properties", function()
		local packet, err = protocol5.parse_packet(make_read_func_hex(
			tools.extract_hex[[
				20 					-- packet type == 2 (CONNACK), flags == 0
				03 					-- variable length == 3 bytes
					00 				-- 0-th bit is sp (session present) -- DOC: 3.2.2.1 Connect Acknowledge Flags
					00 				-- connect reason code
					00				-- properties length
			]]
		))
		assert.is_nil(err)
		assert.are.same(
			packet,
			{
				type=pt.CONNACK, sp=false, rc=0, properties={}, user_properties={}
			}
		)
	end)

	it("CONNACK with full params and without properties", function()
		local packet, err = protocol5.parse_packet(make_read_func_hex(
			tools.extract_hex[[
				20 					-- packet type == 2 (CONNACK), flags == 0
				03 					-- variable length == 3 bytes
					01 				-- 0-th bit is sp (session present) -- DOC: 3.2.2.1 Connect Acknowledge Flags
					8A 				-- connect reason code
					00				-- properties length
			]]
		))
		assert.is_nil(err)
		assert.are.same(
			packet,
			{
				type=pt.CONNACK, sp=true, rc=0x8A, properties={}, user_properties={}
			}
		)
	end)

	it("CONNACK with full params and full properties", function()
		local packet, err = protocol5.parse_packet(make_read_func_hex(
			tools.extract_hex[[
				20 					-- packet type == 2 (CONNACK), flags == 0

				75 					-- variable length == 0x66 == 102 bytes

					01 				-- 0-th bit is sp (session present) -- DOC: 3.2.2.1 Connect Acknowledge Flags
					82 				-- connect reason code

					72				-- properties length == 0x63 == 99 bytes

					11 00000E10		-- property 0x11 == 3600, -- DOC: 3.2.2.3.2 Session Expiry Interval
					21 1234			-- property 0x21 == 0x1234, -- DOC: 3.2.2.3.3 Receive Maximum
					24 01			-- property 0x24 == 1, -- DOC: 3.2.2.3.4 Maximum QoS
					25 01			-- property 0x25 == 1, -- DOC: 3.2.2.3.5 Retain Available
					27 00004567		-- property 0x27 == 0x4567, -- DOC: 3.2.2.3.6 Maximum Packet Size
					12 0005 736C617665	-- property 0x12 == "slave", -- DOC: 3.2.2.3.7 Assigned Client Identifier
					22 4321			-- property 0x22 == 0x4321, -- DOC: 3.2.2.3.8 Topic Alias Maximum
					1F 0007 70726F63656564	-- property 0x1F == "proceed", -- DOC: 3.2.2.3.9 Reason String
					28 01			-- property 0x28 == 1, -- DOC: 3.2.2.3.11 Wildcard Subscription Available
					29 00			-- property 0x29 == 0, -- DOC: 3.2.2.3.12 Subscription Identifiers Available
					2A 01			-- property 0x2A == 1, -- DOC: 3.2.2.3.13 Shared Subscription Available
					13 0078			-- property 0x13 == 120, -- DOC: 3.2.2.3.14 Server Keep Alive
					1A 0005 686572652F	-- property 0x1A == "here/", -- DOC: 3.2.2.3.15 Response Information
					1C 000D 736565202F6465762F6E756C6C	-- property 0x1C == "see /dev/null", -- DOC: 3.2.2.3.16 Server Reference
					15 0005 6775657373	-- property 0x15 == "guess", -- DOC: 3.2.2.3.17 Authentication Method
					16 0002 3130		-- property 0x16 == "10", -- DOC: 3.2.2.3.18 Authentication Data
					26 0005 68656C6C6F 0005 776F726C64	-- property 0x26 (user) == ("hello", "world")  -- DOC: 3.2.2.3.10 User Property
					26 0005 68656C6C6F 0005 616761696E	-- property 0x26 (user) == ("hello", "again")  -- DOC: 3.2.2.3.10 User Property
			]]
		))
		assert.is_nil(err)
		assert.are.same(
			packet,
			{
				type=pt.CONNACK, sp=true, rc=0x82,
				properties={
					session_expiry_interval = 3600,
					receive_maximum = 0x1234,
					maximum_qos = 1,
					retain_available = 1,
					maximum_packet_size = 0x4567,
					assigned_client_identifier = "slave",
					topic_alias_maximum = 0x4321,
					reason_string = "proceed",
					wildcard_subscription_available = 1,
					subscription_identifiers_available = 0,
					shared_subscription_available = 1,
					server_keep_alive = 120,
					response_information = "here/",
					server_reference = "see /dev/null",
					authentication_method = "guess",
					authentication_data = "10",
				},
				user_properties={
					hello = "again",
					{"hello", "world"},
					{"hello", "again"},
				}
			}
		)
	end)
end)

-- vim: ts=4 sts=4 sw=4 noet ft=lua
