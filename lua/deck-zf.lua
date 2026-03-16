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

ffi.cdef([[
typedef struct {
  uint32_t col __attribute__((aligned(sizeof(uint64_t))));
  uint32_t end_col;
} deck_zf_highlight_t;

double deck_zf_match(
  const uint8_t *buf,
  uint32_t query_len,
  uint32_t text_len
);

uint32_t deck_zf_decor(
  const uint8_t *buf,
  uint32_t query_len,
  uint32_t text_len,
  deck_zf_highlight_t *highlights,
  uint32_t highlight_capacity
);
]])

---@class deck-zf*: ffi.namespace*
---
---@field deck_zf_match fun(
---  buf: ffi.cdata*,
---  query_len: integer,
---  text_len: integer,
---): rank: number
---
---@field deck_zf_decor fun(
---  buf: ffi.cdata*,
---  query_len: integer,
---  text_len: integer,
---  highlights: ffi.cdata*,
---  highlight_capacity: integer,
---): highlight_count: integer
---
local lib = ffi.load(lib_path)

local matcher = {}

local buf = buffer.new()

---@param query string
---@param text string
---@return number
function matcher.match(query, text)
  buf:reset():put(query, text)
  return lib.deck_zf_match(buf:ref(), #query, #text)
end

local highlight_buf = buffer.new()
local highlight_ptr_t = ffi.typeof("deck_zf_highlight_t *")
local sizeof_highlight = assert(ffi.sizeof("deck_zf_highlight_t"))

---@param query string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function matcher.decor(query, text)
  local bytes, byte_capacity = highlight_buf:reserve(#query * sizeof_highlight)
  local highlights = ffi.cast(highlight_ptr_t, bytes)
  local highlight_capacity = math.floor(byte_capacity / sizeof_highlight)
  buf:reset():put(query, text)
  local highlight_count = lib.deck_zf_decor(buf:ref(), #query, #text, highlights, highlight_capacity)
  local ret = new_table(highlight_count, 0)
  for i = 0, highlight_count - 1 do
    ret[i + 1] = {
      highlights[i].col,
      highlights[i].end_col,
    }
  end
  return ret
end

return {
  matcher = matcher,
}
