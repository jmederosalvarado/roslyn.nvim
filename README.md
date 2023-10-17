# roslyn.nvim

This plugin adds support for the new Roslyn-based C# language server [introduced](https://devblogs.microsoft.com/visualstudio/announcing-csharp-dev-kit-for-visual-studio-code) in the [vscode C# extension](https://github.com/dotnet/vscode-csharp).

## Dependencies

The plugin doesn't depend on any other neovim plugins, not even `nvim-lspconfig`. It's enough to have dotnet installed.

## Setup

```lua
require("roslyn").setup({
	dotnet_cmd = "dotnet", -- this is the default
	roslyn_version = "4.8.0-3.23475.7", -- this is the default
    on_attach = <on_attach you would pass to nvim-lspconfig>, -- required
    capabilities = <capabilities you would pass to nvim-lspconfig>, -- required
})
```

## Usage

1. Upon opening a C# file, the plugin will look for a `.sln` file in parent directories until it finds one. Make sure to have a `.sln` file somewhere in a parent dir, there is no support yet for `.csproj` only projects. 
2. If it only finds one `.sln` file, it will use that to start the server. If it finds multiple, it will ask you to choose one before starting the server. When multiple `.sln` files are found for a file, you can use the command `:CSTarget` to change the target for the buffer at any point.
3. You'll see two notifications if everything goes well. The first one will say `Roslyn client initialized for target <target>`, which means the server is running, but it will just start indexing your `sln`. The second one will say `Roslyn project initialization complete`, it means that the server indexed your `sln`, only after you see the second notification will the `go to definition` and other lsp features be available.

## Features

Please note that some features from the vscode extension might not yet be supported by this plugin. Most of them are part of the roadmap, however I don't use vscode myself, so I'm not aware of all the features available, feel free to open an issue if you notice something is missing.
