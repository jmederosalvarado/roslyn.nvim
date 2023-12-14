local nuget = {
	[[<?xml version="1.0" encoding="utf-8"?>]],
	[[<configuration>]],
	[[  <packageSources>]],
	[[    <clear />]],
	[[    <add key="msft_consumption" value="https://pkgs.dev.azure.com/azure-public/vside/_packaging/msft_consumption/nuget/v3/index.json" />]],
	[[  </packageSources>]],
	[[  <disabledPackageSources>]],
	[[    <clear />]],
	[[  </disabledPackageSources>]],
	[[</configuration>]],
}

local csproj = {
	[[<Project Sdk="Microsoft.Build.NoTargets/1.0.80">]],
	[[    <PropertyGroup>]],
	-- Changes the global packages folder
	[[        <RestorePackagesPath>out</RestorePackagesPath>]],
	-- This is not super relevant, as long as your SDK version supports it.
	[[        <TargetFramework>net7.0</TargetFramework>]],
	-- If a package is resolved to a fallback folder, it may not be downloaded
	[[        <DisableImplicitNuGetFallbackFolder>true</DisableImplicitNuGetFallbackFolder>]],
	-- We don't want to build this project, so we do not need the reference assemblies for the framework we chose
	[[        <AutomaticallyUseReferenceAssemblyPackages>false</AutomaticallyUseReferenceAssemblyPackages>]],
	[[    </PropertyGroup>]],
	[[    <ItemGroup>]],
	[[        <PackageDownload Include="$(PackageName)" version="[$(PackageVersion)]" />]],
	[[    </ItemGroup>]],
	[[</Project>]],
}

local function get_rid()
	local system_info = vim.uv.os_uname()
	local platform = system_info.sysname:lower()
	local arch = system_info.machine:lower()

	if platform == "darwin" then
		if arch == "x86_64" then
			return "osx-x64"
		elseif arch == "arm64" then
			return "osx-arm64"
		end
	end

	-- probably missing linux-musl/alpine
	if platform == "linux" then
		if arch == "x86_64" then
			return "linux-x64"
		elseif arch == "arm64" then
			return "linux-arm64"
		end
	end

	-- not sure about this one
	if platform == "windows_nt" then
		if arch == "x86_64" then
			return "win-x64"
		elseif arch == "x86" then
			return "win-x86"
		end
	end

	vim.notify("Unsupported platform: " .. vim.inspect(system_info), vim.log.levels.ERROR, { title = "Roslyn" })
end

local M = {}

function M.install(dotnet_cmd, roslyn_pkg_version)
	local server_path = vim.fs.joinpath(vim.fn.stdpath("data")--[[@as string]], "roslyn")

	if vim.fn.isdirectory(server_path) == 1 then
		local reinstall = false
		vim.ui.input(
			{ prompt = "Roslyn LSP is already installed. Do you want to reinstall it? [y/N] " },
			function(answer)
				if answer and answer:lower() ~= "y" and answer:lower() ~= "yes" then
					return
				end
				reinstall = true
			end
		)
		if not reinstall then
			return
		end
		vim.fn.delete(server_path, "rf")
	end

	local download_path = vim.fn.tempname()
	vim.fn.mkdir(download_path, "p")

	local rid = get_rid()
	if not rid then
		return
	end
	local roslyn_pkg_name = "microsoft.codeanalysis.languageserver." .. rid

	vim.fn.writefile(csproj, vim.fs.joinpath(download_path, "ServerDownload.csproj"))
	vim.fn.writefile(nuget, vim.fs.joinpath(download_path, "NuGet.config"))

	local waited = vim.system({
		dotnet_cmd,
		"restore",
		download_path,
		"/p:PackageName=" .. roslyn_pkg_name,
		"/p:PackageVersion=" .. roslyn_pkg_version,
	}, { stdout = false }, function(obj) end):wait()

	if waited.code ~= 0 then
		vim.notify(
			"Failed to restore Roslyn package: " .. vim.inspect(waited),
			vim.log.levels.ERROR,
			{ title = "Roslyn" }
		)
		return
	end

	vim.fn.rename(
		vim.fs.joinpath(download_path, "out", roslyn_pkg_name, roslyn_pkg_version, "content", "LanguageServer", rid),
		server_path
	)

	vim.notify("Roslyn LSP installed", vim.log.levels.INFO, { title = "Roslyn" })
end

return M
