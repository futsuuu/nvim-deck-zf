# nvim-deck-zf

[zf](https://github.com/natecraddock/zf) matcher for [nvim-deck](https://github.com/hrsh7th/nvim-deck)

## Installation

Build dependencies:

- Zig latest

Runtime dependencies:

- Neovim built with LuaJIT 2.1+

Lazy.nvim example:

```lua
{
    "futsuuu/nvim-deck-zf",
    build = "zig build --release",
    -- build = "mise x -- zig build --release",
},
```

## Usage

```lua
require("deck").setup({
    default_start_config = {
        matcher = require("deck-zf").matcher,
    }
})
```

## License

[MIT](./LICENSE)
