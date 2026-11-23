require("spec.spec_helper")
local luablaze = require("luablaze")

describe("Error-path memory safety", function()
  local ITERATIONS = 20
  local OBJECT_SCHEMA = '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object"}'
  local REQUIRED_SCHEMA = '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "required": ["a"]}'

  it("does not leak on luablaze.new errors (> 15-byte and > 1024-byte messages)", function()
    local long_mode = string.rep("m", 1500)
    local long_dialect = string.rep("d", 1500)

    for _ = 1, ITERATIONS do
      -- > 15-byte error message (exceeds libstdc++ SSO)
      local ok1, err1 = pcall(luablaze.new, OBJECT_SCHEMA, { mode = "invalid_mode_exceeding_sso" })
      assert.is_false(ok1)
      assert.is_string(err1)
      assert.truthy(#err1 > 15)
      assert.truthy(err1:find("Unknown mode", 1, true))

      -- > 1024-byte error message (tests err_buf truncation safety)
      local ok2, err2 = pcall(luablaze.new, OBJECT_SCHEMA, { mode = long_mode })
      assert.is_false(ok2)
      assert.is_string(err2)
      assert.truthy(#err2 > 100)
      assert.truthy(err2:find("Unknown mode", 1, true))

      -- > 1024-byte dialect error message
      local ok3, err3 = pcall(luablaze.new, OBJECT_SCHEMA, { dialect = long_dialect })
      assert.is_false(ok3)
      assert.is_string(err3)
      assert.truthy(#err3 > 100)
      assert.truthy(err3:find("Unknown dialect", 1, true))
    end
  end)

  it("does not leak on :validate errors", function()
    local schema = luablaze.new(OBJECT_SCHEMA)
    local long_key = string.rep("k", 1500)

    for _ = 1, ITERATIONS do
      -- > 15-byte error message (unsupported Lua type)
      local ok1, err1 = pcall(function()
        return schema:validate({ bad = function() end })
      end)
      assert.is_false(ok1)
      assert.is_string(err1)
      assert.truthy(#err1 > 15)
      assert.truthy(err1:find("Unsupported Lua type", 1, true))

      -- Error with > 1024-byte table key present
      local ok2, err2 = pcall(function()
        return schema:validate({ [long_key] = function() end })
      end)
      assert.is_false(ok2)
      assert.is_string(err2)
      assert.truthy(#err2 > 15)
      assert.truthy(err2:find("Unsupported Lua type", 1, true))
    end
  end)

  it("does not leak on :validate_json errors", function()
    local schema = luablaze.new(OBJECT_SCHEMA, { max_depth = 2 })
    local long_invalid_json = '{"key": "' .. string.rep("x", 1500)

    for _ = 1, ITERATIONS do
      -- > 15-byte parse error (depth limit exceeded)
      local ok1, err1 = pcall(function()
        return schema:validate_json('{"a": {"b": {"c": 1}}}')
      end)
      assert.is_false(ok1)
      assert.is_string(err1)
      assert.truthy(#err1 > 15)
      assert.truthy(err1:find("depth", 1, true))

      -- > 1024-byte invalid JSON input
      local ok2, err2 = pcall(function()
        return schema:validate_json(long_invalid_json)
      end)
      assert.is_false(ok2)
      assert.is_string(err2)
      assert.truthy(#err2 > 0)
    end
  end)

  it("does not leak on :validate_detailed errors", function()
    local schema = luablaze.new(OBJECT_SCHEMA)
    local shallow_schema = luablaze.new(REQUIRED_SCHEMA, { max_recursion_depth = 1 })
    local long_key = string.rep("k", 1500)

    for _ = 1, ITERATIONS do
      -- > 15-byte error message (unsupported Lua type)
      local ok1, err1 = pcall(function()
        return schema:validate_detailed({ bad = function() end })
      end)
      assert.is_false(ok1)
      assert.is_string(err1)
      assert.truthy(#err1 > 15)
      assert.truthy(err1:find("Unsupported Lua type", 1, true))

      -- > 15-byte error during detailed report conversion (recursion depth exceeded)
      local ok2, err2 = pcall(function()
        return shallow_schema:validate_detailed({ [long_key] = 1 })
      end)
      assert.is_false(ok2)
      assert.is_string(err2)
      assert.truthy(#err2 > 15)
      assert.truthy(err2:find("recursion depth", 1, true))
    end
  end)

  it("does not leak on :validate_json_detailed errors", function()
    local schema = luablaze.new(OBJECT_SCHEMA, { max_depth = 2 })
    local long_invalid_json = '{"key": "' .. string.rep("x", 1500)

    for _ = 1, ITERATIONS do
      -- > 15-byte parse error (depth limit exceeded)
      local ok1, err1 = pcall(function()
        return schema:validate_json_detailed('{"a": {"b": {"c": 1}}}')
      end)
      assert.is_false(ok1)
      assert.is_string(err1)
      assert.truthy(#err1 > 15)
      assert.truthy(err1:find("depth", 1, true))

      -- > 1024-byte invalid JSON input
      local ok2, err2 = pcall(function()
        return schema:validate_json_detailed(long_invalid_json)
      end)
      assert.is_false(ok2)
      assert.is_string(err2)
      assert.truthy(#err2 > 0)
    end
  end)
end)

describe("Table/JSON edge cases (F-10)", function()
  it("handles embedded-NUL object property keys in validate and validate_json_detailed", function()
    local schema_str = '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"a\\u0000b":{"type":"integer"}},"required":["a\\u0000b"]}'
    local schema = luablaze.new(schema_str)

    local ok_json, report_json = schema:validate_json_detailed('{"a\\u0000b": 1}')
    assert.is_true(ok_json)
    assert.is_table(report_json)
    assert.is_true(report_json.valid)

    local bad_json, bad_report = schema:validate_json_detailed('{"a\\u0000b": "wrong"}')
    assert.is_false(bad_json)
    assert.is_table(bad_report)
    assert.is_false(bad_report.valid)

    assert.is_true(schema:validate({ ["a\0b"] = 1 }))
    assert.is_false(schema:validate({ ["a"] = 1 }))
  end)

  it("recognizes > 2^53 integer array keys via lua_isinteger and enforces max_array_length", function()
    local schema = luablaze.new('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"array"}', {
      max_array_length = 10,
    })
    local sparse = {}
    sparse[9007199254740993] = "x" -- 2^53 + 1

    local ok, err = pcall(function()
      return schema:validate(sparse)
    end)
    assert.is_false(ok)
    assert.is_string(err)
    assert.truthy(err:find("Array length exceeds max_array_length", 1, true))
  end)
end)
