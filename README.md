# roslyn.nvim

This plugin adds support for the new Roslyn-based C# language server [introduced](https://devblogs.microsoft.com/visualstudio/announcing-csharp-dev-kit-for-visual-studio-code) in the [vscode C# extension](https://github.com/dotnet/vscode-csharp).

## Setup

You need to install the language server yourself. I did this by installing C# dev kit on vscode. I then checked `htop` and found the .dll file that was ran.
Move the entire directory with all the binaries to `~/.local/share/nvim/roslyn`.

Install `seblj/roslyn.nvim` using your plugin manager.

```lua
require("roslyn").setup({
    -- Optional. Will use `vim.lsp.protocol.make_client_capabilities()`,
    -- and it will also try to merge that with `nvim-cmp` LSP capabilities
    capabilities = nil,
})
```

## Usage

1. The plugin will look for a `.sln` file in parent
   directories until it finds one. Make sure to have a `.sln` file somewhere in
   a parent dir.
2. If it only finds one `.sln` file, it will use that to start the server.
   If it finds multiple, you have to run `CSTarget` to choose which target you want to use.
3. You'll see two notifications if everything goes well. The first one will say
   `Roslyn client initialized for target <target>`, which means the server is
   running, but it will just start indexing your `sln`. The second one will say
   `Roslyn project initialization complete`, it means that the server indexed
   your `sln`, only after you see the second notification will the `go to definition`
   and other lsp features be available.

## Features

Please note that some features from the vscode extension might not be supported by this plugin.
