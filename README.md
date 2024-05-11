# roslyn.nvim

This plugin adds support for the new Roslyn-based C# language server [introduced](https://devblogs.microsoft.com/visualstudio/announcing-csharp-dev-kit-for-visual-studio-code) in the [vscode C# extension](https://github.com/dotnet/vscode-csharp).

Requires Neovim 0.10

## Setup

### Installing Roslyn
1. Navigate to https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl to see the latest package feed for `Microsoft.CodeAnalysis.LanguageServer`
2. Locate the version matching your OS + Arch and click to open it, for example `Microsoft.CodeAnalysis.LanguageServer.linux-x64` (Note that some OS/Arch specific packages may have an extra version ahead of the "core" non specific package)
3. On the package page, click the "Download" button to begin downloading it's .nupkg
   a. (Note, if you need to get a copyable link for the download you can obtain it on chrome by then opening the downloads page, right clicking the file just downloaded, and hitting "copy link address"
4. `.nupkg` files can be opened the same as a zip, in the case of linux you can just use `unzip` on the downloaded the file as if it was a `.zip`.
5. Copy the contents of `<zip root>/content/LanguageServer/<yourArch/` to `~/.local/share/nvim/roslyn`
   a. if you did it right the file `~/.local/share/nvim/roslyn/Microsoft.CodeAnalysis.LanguageServer.dll` should exist (along with many other .dlls and etc in that dir)
6. To test it is working, `cd` into the aformentioned roslyn directory and invoke `dotnet Microsoft.CodeAnalysis.LanguageServer.dll --version`, it should output its version

### Installing the nvim plugin

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

## Importan note!

Roslyn requires that `.csproj` projects are referenced by the matched `.sln` it discovers, otherwise it won't actually discover and load suggestions for `.cs` files under the `.csproj`. Ensure you `dotnet sln add` your projects to the `.sln` or Roslyn won't load up properly!

## Features

Please note that some features from the vscode extension might not be supported by this plugin.
