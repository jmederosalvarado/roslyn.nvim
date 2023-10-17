# roslyn.nvim

This plugin adds support for the new Roslyn-based C# language server [introduced](https://devblogs.microsoft.com/visualstudio/announcing-csharp-dev-kit-for-visual-studio-code) in the [vscode C# extension](https://github.com/dotnet/vscode-csharp).

## Setup

```lua
require("roslyn").setup({
	dotnet_cmd = "dotnet", -- this is the default
	roslyn_version = "4.8.0-3.23475.7", -- this is the default
    on_attach = <on_attach you would pass to nvim-lspconfig>, -- required
    capabilities = <capabilities you would pass to nvim-lspconfig>, -- required
})
```


## Features

Please note that some features from the vscode extension might not yet be supported by this plugin. Most of them are part of the roadmap, however I don't use vscode myself, so I'm not aware of all the features available, feel free to open an issue if you notice something is missing.
