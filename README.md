# nvim-deck-zf

[zf](https://github.com/natecraddock/zf) wrapper for [nvim-deck](https://github.com/hrsh7th/nvim-deck)

## Installation

Requirements:

- Neovim built with LuaJIT
- Zig

Lazy.nvim example:

```lua
{
    "futsuuu/nvim-deck-zf",
    build = "zig build --release",
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
