# Archived (Consider using [this](https://github.com/seblj/roslyn.nvim) instead)

After a very long time without being able to maintain this plugin I'm deciding to archive the repository. I've seen people mentioning [this fork](https://github.com/seblj/roslyn.nvim), which seems to be actively maintained. That's probably where I'll be contributing to if I find the time in the future.

# roslyn.nvim [Deprecated]

This plugin adds support for the new Roslyn-based C# language server [introduced](https://devblogs.microsoft.com/visualstudio/announcing-csharp-dev-kit-for-visual-studio-code) in the [vscode C# extension](https://github.com/dotnet/vscode-csharp).

## Dependencies

Ideally I would like to depend on the Dotnet SDK and everything else to be optional. But for now:

- Dotnet SDK (Tested with .net7).
- [`nvim-lspconfig`](https://github.com/neovim/nvim-lspconfig) for some path utility functions.
- Neovim nightly required. Tested on `831d662ac6756cab4fed6a9b394e68933b5fe325` but anything after August 2023 would probably work.
- `markdown_inline` tree-sitter parser for good hover support.

## Setup

Just install `jmederosalvarado/roslyn.nvim` using your plugin manager.

```lua
require("roslyn").setup({
    dotnet_cmd = "dotnet", -- this is the default
    roslyn_version = "4.8.0-3.23475.7", -- this is the default
    on_attach = <on_attach you would pass to nvim-lspconfig>, -- required
    capabilities = <capabilities you would pass to nvim-lspconfig>, -- required
})
```

## Usage

Before trying to use the language server you should install it. You can do so by running `:CSInstallRoslyn` which will install the configured version of the plugin in neovim's datadir.

1. Upon opening a C# file, the plugin will look for a `.sln` file in parent directories until it finds one. Make sure to have a `.sln` file somewhere in a parent dir, there is no support yet for `.csproj` only projects. 
2. If it only finds one `.sln` file, it will use that to start the server. If it finds multiple, it will ask you to choose one before starting the server. When multiple `.sln` files are found for a file, you can use the command `:CSTarget` to change the target for the buffer at any point.
3. You'll see two notifications if everything goes well. The first one will say `Roslyn client initialized for target <target>`, which means the server is running, but it will just start indexing your `sln`. The second one will say `Roslyn project initialization complete`, it means that the server indexed your `sln`, only after you see the second notification will the `go to definition` and other lsp features be available.

## Features

Please note that some features from the vscode extension might not yet be supported by this plugin. Most of them are part of the roadmap, however I don't use vscode myself, so I'm not aware of all the features available, feel free to open an issue if you notice something is missing.
