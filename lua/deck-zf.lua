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
double deck_match(
  const uint8_t *buf,
  uint32_t query_len,
  uint32_t text_len
);

typedef struct {
  uint32_t col __attribute__((aligned(sizeof(uint64_t))));
  uint32_t end_col;
} deck_highlight_t;

uint32_t deck_decor(
  const uint8_t *buf,
  uint32_t query_len,
  uint32_t text_len,
  deck_highlight_t *highlights,
  uint32_t highlight_capacity
);
]])
local lib = ffi.load(lib_path)

local matcher = {}

local buf = buffer.new()

---@param query string
---@param text string
---@return number
function matcher.match(query, text)
  buf:reset():put(query, text)
  return lib.deck_match(buf:ref(), #query, #text)
end

local highlight_buf = buffer.new()
local highlight_ptr_t = ffi.typeof("deck_highlight_t *")
local sizeof_highlight = assert(ffi.sizeof("deck_highlight_t"))

---@param query string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function matcher.decor(query, text)
  local bytes, byte_capacity = highlight_buf:reserve(#query * sizeof_highlight)
  local highlights = ffi.cast(highlight_ptr_t, bytes)
  local highlight_capacity = math.floor(byte_capacity / sizeof_highlight)
  buf:reset():put(query, text)
  local highlight_count = lib.deck_decor(buf:ref(), #query, #text, highlights, highlight_capacity) ---@type integer
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
