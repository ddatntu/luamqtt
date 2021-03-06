-- busted -e 'package.path="./?/init.lua;"..package.path;' spec/*.lua
-- DOC: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/errata01/os/mqtt-v3.1.1-errata01-os-complete.html

describe("MQTT lua library", function()
	-- load MQTT lua library
	local mqtt = require("mqtt")

	it("has .client function", function()
		assert.are.equal("function", type(mqtt.client))
	end)
end)

describe("MQTT client", function()
	-- load MQTT lua library
	local mqtt = require("mqtt")

	-- test servers
	local cases = {
		{
			name = "mqtt.flespi.io PLAIN, MQTTv3.1.1",
			args = {
				id = "luamqtt-test-flespi",
				uri = "mqtt.flespi.io",
				clean = true,
				-- NOTE: more about flespi tokens: https://flespi.com/kb/tokens-access-keys-to-flespi-platform
				username = "stPwSVV73Eqw5LSv0iMXbc4EguS7JyuZR9lxU5uLxI5tiNM8ToTVqNpu85pFtJv9",
			}
		},
		{
			name = "mqtt.flespi.io SECURE, MQTTv3.1.1",
			args = {
				-- id = "luamqtt-test-flespi-ssl", -- testing randomly generated client id
				uri = "mqtt.flespi.io",
				secure = true,
				clean = true,
				-- NOTE: more about flespi tokens: https://flespi.com/kb/tokens-access-keys-to-flespi-platform
				username = "stPwSVV73Eqw5LSv0iMXbc4EguS7JyuZR9lxU5uLxI5tiNM8ToTVqNpu85pFtJv9",
			}
		},
		{
			name = "test.mosquitto.org PLAIN",
			args = {
				id = "luamqtt-test-mosquitto",
				uri = "test.mosquitto.org", -- NOTE: this broker is not working sometimes
				clean = true,
			}
		},
		{
			name = "test.mosquitto.org SECURE",
			args = {
				-- id = "luamqtt-test-mosquitto", -- testing randomly generated client id
				uri = "test.mosquitto.org",
				secure = true,
				clean = true,
			}
		},
		{
			name = "mqtt.fluux.io PLAIN, MQTTv3.1.1",
			args = {
				id = "luamqtt-test-fluux",
				uri = "mqtt.fluux.io",
				clean = true,
			}
		},
		{
			name = "mqtt.fluux.io SECURE, MQTTv3.1.1",
			args = {
				-- id = "luamqtt-test-fluux", -- testing randomly generated client id
				uri = "mqtt.fluux.io",
				secure = true,
				clean = true,
			}
		},
	}

	for _, case in ipairs(cases) do
		it("complex test - "..case.name, function()
			local errors = {}
			local acknowledge = false
			local test_msg_2 = false

			-- create client
			local client = mqtt.client(case.args)

			-- set on-connect handler
			client:on{
				connect = function()
					assert(client:subscribe("luamqtt/0/test", 0, function()
						assert(client:publish{
							topic = "luamqtt/0/test",
							payload = "initial",
						})
					end))
				end,

				message = function(msg)
					client:acknowledge(msg)

					if msg.topic == "luamqtt/0/test" then
						-- re-subscribe test
						assert(client:unsubscribe("luamqtt/0/test", function()
							assert(client:subscribe("luamqtt/#", 2, function()
								assert(client:publish{
									topic = "luamqtt/1/test",
									payload = "testing QoS 1",
									qos = 1,
									callback = function()
										acknowledge = true
										if acknowledge and test_msg_2 then
											-- done
											assert(client:disconnect())
										end
									end,
								})
							end))
						end))
					elseif msg.topic == "luamqtt/1/test" then
						assert(client:publish{
							topic = "luamqtt/2/test",
							payload = "testing QoS 2",
							qos = 2,
						})
					elseif msg.topic == "luamqtt/2/test" then
						test_msg_2 = true
						if acknowledge and test_msg_2 then
							-- done
							assert(client:disconnect())
						end
					end
				end,

				error = function(err)
					errors[#errors + 1] = err
				end,
			}

			-- and wait for connection to broker is closed
			mqtt.run_ioloop(client)

			assert.are.same({}, errors)
			assert.is_true(acknowledge)
		end)
	end
end)

-- vim: ts=4 sts=4 sw=4 noet ft=lua
