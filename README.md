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
},
```

## Usage

```lua
local zf_matcher = require("deck-zf").matcher({
    --- the default is inferred from 'ignorecase' and 'smartcase' options
    --- @type nil | true | "ignore" | "smart"
    case = true,
})

require("deck").setup({
    default_start_config = {
        matcher = zf_matcher,
    }
})
```

## License

[MIT](./LICENSE)
