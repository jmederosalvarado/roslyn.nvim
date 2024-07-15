# roslyn.nvim

This plugin adds support for the new Roslyn-based C# language server [introduced](https://devblogs.microsoft.com/visualstudio/announcing-csharp-dev-kit-for-visual-studio-code) in the [VS Code C# extension](https://github.com/dotnet/vscode-csharp).

Requires at least Neovim 0.10

## Setup

### Install the Roslyn Language Server

1. Navigate to https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl to see the latest package feed for `Microsoft.CodeAnalysis.LanguageServer`
2. Locate the version matching your OS + Arch and click to open it. For example, `Microsoft.CodeAnalysis.LanguageServer.linux-x64` matches Linux-based OS in x64 architecture. Note that some OS/Arch specific packages may have an extra version ahead of the "core" non specific package.
3. On the package page, click the "Download" button to begin downloading its `.nupkg`
   a. (Note, if you need to get a copyable link for the download you can obtain it on chrome by then opening the downloads page, right clicking the file just downloaded, and hitting "copy link address"
4. `.nupkg` files are basically zip archives. In the case of Linux, you can use `unzip` on the downloaded file to unpack it.
5. Copy the contents of `<zip root>/content/LanguageServer/<yourArch/` to `~/.local/share/nvim/roslyn`
   a. if you did it right, the file `~/.local/share/nvim/roslyn/Microsoft.CodeAnalysis.LanguageServer.dll` should exist now (along with many other .dlls and etc in that dir).
   You can also specify a custom path to it in the setup function.
6. To test it is working, `cd` into the aforementioned roslyn directory and invoke `dotnet Microsoft.CodeAnalysis.LanguageServer.dll --version`. It should output server's version.

### Install the Plugin

Install `seblj/roslyn.nvim` using your plugin manager.

Example:

```lua
require("roslyn").setup({
    config = {
        -- Here you can pass in any options that that you would like to pass to `vim.lsp.start`
        -- The only options that I explicitly override are, which means won't have any effect of setting here are:
        --     - `name`
        --     - `cmd`
        --     - `root_dir`
        --     - `on_init`
    },
    exe = vim.fs.joinpath(
        vim.fn.stdpath("data") --[[@as string]],
        "roslyn",
        "Microsoft.CodeAnalysis.LanguageServer.dll"
    ),
    -- NOTE: Set `filewatching` to false if you experience performance problems.
    -- Defaults to true, since turning it off is a hack.
    -- If you notice that the server is _super_ slow, it is probably because of file watching
    -- I noticed that neovim became super unresponsive on some large codebases, and that was because
    -- it schedules the file watching on the event loop.
    -- This issue went away by disabling that capability. However, roslyn will fallback to its own
    -- file watching, which can make the server super slow to initialize.
    -- Setting this option to false will indicate to the server that neovim will do the file watching.
    -- However, in `hacks.lua` I will also just don't start off any watchers, which seems to make the server
    -- a lot faster to initialize.
    filewatching = true,
})
```

## Usage

1. The plugin will look for a `.sln` file in the parent
   directories of cwd, until it finds one.
2. If only one `.sln` file is found, it will be used to start the server.
   If multiple `.sln`s are found, you have to run `CSTarget` to choose the proper solution file.
3. You should see two notifications, if everything goes well. The first one will say
   `Roslyn client initialized for target <target>`. It means the server is
   running and it has started to index your `sln`. The second one will say
   `Roslyn project initialization complete`. It means that the server has finished indexing of
   your `sln`.
4. The LSP features (like Go To Definition) will be available only after the mentioned notifications get shown.

## Notes

- Roslyn requires that `.csproj` projects are referenced by the matched `.sln` it discovers. Otherwise, it won't discover and load suggestions for `.cs` files under the `.csproj`. Make sure you add your projects to the `.sln` (`dotnet sln add <path-to-csproj>`) or Roslyn won't load up properly!

## Features

Please note that some features from the [VS Code extension](https://github.com/dotnet/vscode-csharp) might not be supported by this plugin.
