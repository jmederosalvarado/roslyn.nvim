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

local sysname2os = {
	["Darwin"] = "osx",
	["Linux"] = "linux",
	["Windows"] = "win",
}

local M = {}

function M.install(dotnet_cmd, roslyn_pkg_version)
	local server_path = vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn")

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

	local system_info = vim.uv.os_uname()
	local rid = sysname2os[system_info.sysname] .. "-" .. system_info.machine:lower()
	local roslyn_pkg_name = "microsoft.codeanalysis.languageserver." .. rid

	vim.fn.writefile(csproj, vim.fs.joinpath(download_path, "ServerDownload.csproj"))
	vim.fn.writefile(nuget, vim.fs.joinpath(download_path, "NuGet.config"))

	local waited = vim.system({
		dotnet_cmd,
		"restore",
		download_path,
		"/p:PackageName=" .. roslyn_pkg_name,
		"/p:PackageVersion=" .. roslyn_pkg_version,
	}, { stdout = false }, function(obj)
		if obj.code ~= 0 then
			vim.notify(
				"Failed to restore Roslyn package: " .. vim.inspect(obj),
				vim.log.levels.ERROR,
				{ title = "Roslyn" }
			)
		end
	end):wait()

	vim.fn.rename(
		vim.fs.joinpath(download_path, "out", roslyn_pkg_name, roslyn_pkg_version, "content", "LanguageServer", rid),
		server_path
	)

	vim.notify("Roslyn LSP installed", vim.log.levels.INFO, { title = "Roslyn" })
end

return M
