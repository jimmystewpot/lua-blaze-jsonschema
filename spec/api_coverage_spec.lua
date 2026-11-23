require("spec.spec_helper")

local luablaze = require("luablaze")

describe("Module-level API functions", function()
  local SCHEMA = '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"name":{"type":"string","minLength":1},"count":{"type":"integer","minimum":0}},"required":["name","count"]}'

  it("luablaze.validate validates Lua tables", function()
    local compiled = luablaze.new(SCHEMA)
    assert.is_true(luablaze.validate(compiled, { name = "widget", count = 3 }))
    assert.is_false(luablaze.validate(compiled, { name = "", count = 3 }))
    assert.is_false(luablaze.validate(compiled, { name = "widget" }))
  end)

  it("luablaze.validate rejects non-schema first argument", function()
    local ok = pcall(luablaze.validate, {}, { name = "widget", count = 1 })
    assert.is_false(ok)
  end)

  it("luablaze.validate_json validates JSON strings", function()
    local compiled = luablaze.new(SCHEMA)
    assert.is_true(luablaze.validate_json(compiled, '{"name":"widget","count":3}'))
    assert.is_false(luablaze.validate_json(compiled, '{"name":"widget","count":-1}'))
    assert.is_false(luablaze.validate_json(compiled, '{}'))
  end)

  it("luablaze.validate_detailed returns boolean and basic report table", function()
    local compiled = luablaze.new(SCHEMA, { mode = "Exhaustive" })

    local ok_valid, report_valid = luablaze.validate_detailed(compiled, { name = "widget", count = 2 })
    assert.is_true(ok_valid)
    assert.is_table(report_valid)
    assert.is_true(report_valid.valid)

    local ok_invalid, report_invalid = luablaze.validate_detailed(compiled, { name = "widget", count = -5 })
    assert.is_false(ok_invalid)
    assert.is_table(report_invalid)
    assert.is_false(report_invalid.valid)
    assert.is_table(report_invalid.errors)
    assert.is_true(#report_invalid.errors > 0)
  end)

  it("luablaze.validate_json_detailed returns boolean and basic report table", function()
    local compiled = luablaze.new(SCHEMA, { mode = "Exhaustive" })

    local ok_valid, report_valid = luablaze.validate_json_detailed(compiled, '{"name":"widget","count":0}')
    assert.is_true(ok_valid)
    assert.is_table(report_valid)
    assert.is_true(report_valid.valid)

    local ok_invalid, report_invalid = luablaze.validate_json_detailed(compiled, '{"name":"","count":0}')
    assert.is_false(ok_invalid)
    assert.is_table(report_invalid)
    assert.is_false(report_invalid.valid)
    assert.is_table(report_invalid.errors)
    assert.is_true(#report_invalid.errors > 0)
  end)
end)

describe("CompiledSchema method aliases", function()
  local SCHEMA = '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"x":{"type":"integer"}},"required":["x"]}'

  it("CompiledSchema:validate_detailed returns boolean and report table", function()
    local compiled = luablaze.new(SCHEMA, { mode = "Exhaustive" })

    local ok_valid, report_valid = compiled:validate_detailed({ x = 42 })
    assert.is_true(ok_valid)
    assert.is_table(report_valid)
    assert.is_true(report_valid.valid)

    local ok_invalid, report_invalid = compiled:validate_detailed({ x = "not-an-int" })
    assert.is_false(ok_invalid)
    assert.is_table(report_invalid)
    assert.is_false(report_invalid.valid)
    assert.is_table(report_invalid.errors)
    assert.is_true(#report_invalid.errors > 0)
  end)

  it("CompiledSchema:evaluate acts as an alias for :validate", function()
    local compiled = luablaze.new(SCHEMA)

    assert.is_true(compiled:evaluate({ x = 10 }))
    assert.is_false(compiled:evaluate({ x = "bad" }))
    assert.is_false(compiled:evaluate({}))
    assert.are.equal(compiled:validate({ x = 10 }), compiled:evaluate({ x = 10 }))
    assert.are.equal(compiled:validate({ x = "bad" }), compiled:evaluate({ x = "bad" }))
  end)
end)

describe("Fast-mode INT64_MAX and INT64_MIN exclusive bounds (F-03 regression)", function()
  for _, mode in ipairs({ "Fast", "Exhaustive" }) do
    it("rejects 0 and INT64_MAX for exclusiveMinimum = INT64_MAX in " .. mode .. " mode", function()
      local schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","exclusiveMinimum":9223372036854775807}'
      local compiled = luablaze.new(schema, { mode = mode })

      assert.is_false(compiled:validate_json("0"))
      assert.is_false(compiled:validate_json("9223372036854775807"))
      assert.is_true(compiled:validate_json("9223372036854775808"))

      local obj_schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"v":{"exclusiveMinimum":9223372036854775807}},"required":["v"]}'
      local obj_compiled = luablaze.new(obj_schema, { mode = mode })
      assert.is_false(obj_compiled:validate({ v = 0 }))
    end)

    it("rejects 0 and INT64_MIN for exclusiveMaximum = INT64_MIN in " .. mode .. " mode", function()
      local schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","exclusiveMaximum":-9223372036854775808}'
      local compiled = luablaze.new(schema, { mode = mode })

      assert.is_false(compiled:validate_json("0"))
      assert.is_false(compiled:validate_json("-9223372036854775808"))
      assert.is_true(compiled:validate_json("-9223372036854775809"))

      local obj_schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"v":{"exclusiveMaximum":-9223372036854775808}},"required":["v"]}'
      local obj_compiled = luablaze.new(obj_schema, { mode = mode })
      assert.is_false(obj_compiled:validate({ v = 0 }))
    end)
  end
end)

describe("UTF-8 long property keys and >32 property objects", function()
  local utf8_long_key = "\xC3\xA9" .. string.rep("a", 30) -- 32 bytes UTF-8
  local utf8_longer_key = "\xC3\xA9" .. string.rep("b", 40) -- 42 bytes UTF-8

  for _, mode in ipairs({ "Fast", "Exhaustive" }) do
    it("handles 32+ byte UTF-8 property keys in " .. mode .. " mode", function()
      local schema = string.format(
        '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"%s":{"type":"integer"},"%s":{"type":"string"}},"required":["%s"],"additionalProperties":false}',
        utf8_long_key, utf8_longer_key, utf8_long_key
      )
      local compiled = luablaze.new(schema, { mode = mode })

      assert.is_true(compiled:validate({ [utf8_long_key] = 7, [utf8_longer_key] = "ok" }))
      assert.is_false(compiled:validate({ [utf8_long_key] = "wrong" }))
      assert.is_false(compiled:validate({ [utf8_longer_key] = "missing-required" }))
      assert.is_false(compiled:validate({ [utf8_long_key] = 7, extra = true }))

      local valid_json = string.format('{"%s":7,"%s":"ok"}', utf8_long_key, utf8_longer_key)
      local invalid_json = string.format('{"%s":"wrong"}', utf8_long_key)
      assert.is_true(compiled:validate_json(valid_json))
      assert.is_false(compiled:validate_json(invalid_json))

      local ok, report = compiled:validate_detailed({ [utf8_long_key] = 7 })
      assert.is_true(ok)
      assert.is_true(report.valid)
    end)

    it("handles objects with 35 properties (> 32 bitmask threshold) in " .. mode .. " mode", function()
      local prop_defs = {}
      local req_defs = {}
      local valid_obj = {}
      local valid_json_parts = {}

      for i = 1, 35 do
        local key = string.format("prop_%02d", i)
        table.insert(prop_defs, string.format('"%s":{"type":"integer"}', key))
        table.insert(req_defs, string.format('"%s"', key))
        valid_obj[key] = i
        table.insert(valid_json_parts, string.format('"%s":%d', key, i))
      end

      local schema = string.format(
        '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{%s},"required":[%s],"additionalProperties":false}',
        table.concat(prop_defs, ","),
        table.concat(req_defs, ",")
      )
      local compiled = luablaze.new(schema, { mode = mode })

      assert.is_true(compiled:validate(valid_obj))
      assert.is_true(compiled:validate_json("{" .. table.concat(valid_json_parts, ",") .. "}"))

      local ok_det, report_det = compiled:validate_detailed(valid_obj)
      assert.is_true(ok_det)
      assert.is_true(report_det.valid)

      -- Missing 35th required property
      local missing_obj = {}
      for k, v in pairs(valid_obj) do
        missing_obj[k] = v
      end
      missing_obj["prop_35"] = nil
      assert.is_false(compiled:validate(missing_obj))

      -- Wrong type on 35th property
      local wrong_type_obj = {}
      for k, v in pairs(valid_obj) do
        wrong_type_obj[k] = v
      end
      wrong_type_obj["prop_35"] = "not-an-integer"
      assert.is_false(compiled:validate(wrong_type_obj))

      -- Disallowed 36th property
      local extra_obj = {}
      for k, v in pairs(valid_obj) do
        extra_obj[k] = v
      end
      extra_obj["prop_36"] = 36
      assert.is_false(compiled:validate(extra_obj))
    end)
  end
end)
