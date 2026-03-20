local buffer = require("string.buffer")
local ffi = require("ffi")
local new_table = require("table.new")

local lib_path ---@type string
do
    local source = debug.getinfo(1, "S").source
    local repo_root = source:gsub("^@", ""):gsub("[/\\]?lua[/\\]deck%-zf%.lua$", "")
    if ffi.os == "Windows" then
        lib_path = repo_root .. [[\zig-out\bin\deck-zf.dll]]
    elseif ffi.os == "OSX" then
        lib_path = repo_root .. [[/zig-out/lib/libdeck-zf.dylib]]
    else
        lib_path = repo_root .. [[/zig-out/lib/libdeck-zf.so]]
    end
end

--- For performance, the external functions should be accessed as fields of the
--- C library namespace every time they are called.
---
--- ```lua
--- local func = lib.func -- NG
--- ```
local lib = ffi.load(lib_path)

---@class deck-zf.Highlight*: ffi.cdata*
---@field col integer
---@field end_col integer
local Highlight = {}

Highlight.type = ffi.typeof([[struct {
    uint32_t col __attribute__((aligned(sizeof(uint64_t))));
    uint32_t end_col;
}]])
ffi.metatype(Highlight.type, Highlight)

Highlight.ptr_type = ffi.typeof("$ *", Highlight.type)
Highlight.size = assert(ffi.sizeof(Highlight.type))

---@class deck-zf.HighlightBuffer*: ffi.cdata*
---@field ptr ffi.cdata*
---@field capacity integer
local HighlightBuffer = {}
---@private
HighlightBuffer.__index = HighlightBuffer

HighlightBuffer.type = ffi.typeof("struct { $ ptr; uint32_t capacity; }", Highlight.ptr_type)
ffi.metatype(HighlightBuffer.type, HighlightBuffer)

do
    local buf = buffer.new()

    ---@param min_capacity integer
    ---@return self
    function HighlightBuffer.new(min_capacity)
        local byte_ptr, byte_capapcity = buf:reserve(min_capacity * Highlight.size)
        return HighlightBuffer.type(
            ffi.cast(Highlight.ptr_type, byte_ptr),
            -- `number` can be automatically converted to `uint32_t`
            byte_capapcity / Highlight.size
        )
    end
end

---@param len integer
---@return { [1]: integer, [2]: integer }[]
function HighlightBuffer:to_deck_highlights(len)
    local ret = new_table(len, 0)
    for i = 0, len - 1 do
        ret[i + 1] = { self.ptr[i].col, self.ptr[i].end_col }
    end
    return ret
end

---@class deck-zf.InputStrings*: ffi.cdata*
---@field ptr ffi.cdata*
---@field query_len integer
---@field text_len integer
local InputStrings = {}
---@private
InputStrings.__index = InputStrings

InputStrings.type = ffi.typeof([[struct {
    const uint8_t *ptr;
    uint32_t query_len;
    uint32_t text_len;
    bool text_to_lower;
}]])
ffi.metatype(InputStrings.type, InputStrings)

do
    ---@generic F: fun(x: any): any
    ---@param fn F
    ---@return F
    local function cache_one(fn)
        local cache_key, cache_value
        return function(x)
            if x == cache_key then
                return cache_value
            end
            cache_key = x
            cache_value = fn(x)
            return cache_value
        end
    end

    ---@param s string
    local contains_uppercase = cache_one(function(s)
        return s:find("%u") ~= nil
    end)

    local to_lower = cache_one(string.lower)

    local buf = buffer.new()

    ---@param query string
    ---@param text string
    ---@param case "ignore" | "smart" | any
    ---@return self
    function InputStrings.new(query, text, case)
        query = case == "ignore" and to_lower(query) or query
        return InputStrings.type(
            buf:reset():put(query, text):ref(),
            #query,
            #text,
            case == "ignore" or case == "smart" and not contains_uppercase(query)
        )
    end
end

ffi.cdef("double deck_zf_InputStrings_getRank($ self)", InputStrings.type)
---@return number rank
function InputStrings:get_rank()
    return lib.deck_zf_InputStrings_getRank(self)
end

ffi.cdef("uint32_t deck_zf_InputStrings_getHighlights($ self, $ buf)", InputStrings.type, HighlightBuffer.type)
---@param buf deck-zf.HighlightBuffer*
---@return integer highlight_count
function InputStrings:get_highlights(buf)
    return lib.deck_zf_InputStrings_getHighlights(self, buf)
end

local M = {}

---@param opts? { case?: true | "ignore" | "smart" }
function M.matcher(opts)
    opts = opts or {}

    local matcher = {}

    local case = opts.case or vim.o.smartcase and "smart" or vim.o.ignorecase and "ignore" or true

    ---@param query string
    ---@param text string
    ---@return number
    function matcher.match(query, text)
        return InputStrings.new(query, text, case):get_rank()
    end

    ---@param query string
    ---@param text string
    ---@return { [1]: integer, [2]: integer }[]
    function matcher.decor(query, text)
        local buf = HighlightBuffer.new(#query)
        local len = InputStrings.new(query, text, case):get_highlights(buf)
        return buf:to_deck_highlights(len)
    end

    return matcher
end

return M
