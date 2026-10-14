# Internal PowerShell repository options on Windows PowerShell 5.1

Research for issue #5 (parent map #1). Question: realistic ways to host an internal repository for the `WSUS` module so Server Core nodes on Windows PowerShell 5.1 can `Install-Module` into the all-users path; prerequisites; update flow; what SYSTEM-run scheduled tasks need.

Claims cite Microsoft Learn, JFrog docs, or the PSResourceGet repo. Items marked **Not verified** were not found in a primary source and should not be relied on.

## Summary

| Option | Client on 5.1 | Fit |
|---|---|---|
| File share + PowerShellGet v2 | PowerShellGet 2.2.5 + PackageManagement 1.4.8.1 (upgrade from in-box 1.0.0.1) | Simplest; no server to run; no record of who published |
| NuGet feed (Artifactory / Azure Artifacts) + PowerShellGet v2 | Same; feed must expose a **v2** URL | Adds auth, search, retention; needs a service |
| PSResourceGet | README states "PowerShell 5.0 or higher" | Possible, but one more module on every node; no Server Core guidance |

Recommendation for the map: file share + PowerShellGet v2 is the realistic default for a two-node estate. A NuGet feed only pays off if one already exists.

## 1. File-share repository (PowerShellGet v2)

- Two local-repo types are documented: NuGet server or file share. File share pros: easy to set up/back up, share permissions are the security model. Cons: no UI, limited security, no record of who updated what. [Working with local PSRepositories](https://learn.microsoft.com/en-us/powershell/gallery/how-to/working-with-local-psrepositories?view=powershellget-2.x)
- Register: `Register-PSRepository -Name X -SourceLocation '\\host\share\' -ScriptSourceLocation '\\host\share\' -InstallationPolicy Trusted`. For file shares `SourceLocation` and `ScriptSourceLocation` must match (for web feeds they must differ). Same source.
- Publish: `Publish-Module -Path <module folder> -Repository X -NuGetApiKey <any non-blank string>`. For a file share any non-blank key works. Same source. The folder must have the same name as the module; the manifest needs name, version, description and author. [Publish-Module](https://learn.microsoft.com/en-us/powershell/module/powershellget/publish-module?view=powershellget-2.x)
- `Publish-*` uses `nuget.exe` or `dotnet.exe`; if neither exists PowerShellGet installs `nuget.exe`. [Install PowerShellGet](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/install-powershellget?view=powershellget-2.x) This applies to the publisher (admin workstation or CI), not the consuming nodes.
- Consumers need read access to the share; Microsoft says to follow SMB security guidance. Local-repo article.

## 2. NuGet feeds

### Artifactory
- Supports PowerShell client "Version 1.0.5 and above" via `Register-PSRepository`, `Install-Module`, `Publish-Module` with a NuGet API key. URL form `https://<domain>/artifactory/api/nuget/<repo>` (v2 style, no `/v3/`). Credentials are a username plus API token as a `PSCredential`. [JFrog NuGet repositories](https://docs.jfrog.com/artifactory/docs/nuget-repositories)

### Azure Artifacts
- PowerShellGet v2 route: use the **v2** URL (`.../_packaging/<feed>/nuget/v2`); the tutorial says NuGet V3 is not supported for this route. `Register-PSRepository -SourceLocation ... -PublishLocation ... -InstallationPolicy Trusted -Credential <PAT credential>`. The tutorial lists the Azure Artifacts Credential Provider, nuget.exe 4.8.0.5385+ and .NET runtime 8.0.x as prerequisites (publishing path) and recommends PowerShell 6+ for suitable PowerShellGet versions; PowerShellGet 2.2.5 can still be installed on 5.1 per the install page. The manifest version must equal the `.nuspec` version. [Azure Artifacts private PowerShell library](https://learn.microsoft.com/en-us/azure/devops/artifacts/tutorials/private-powershell-library?view=azure-devops)
- Auth is a PAT (Packaging read for consumers; read, write and manage for publishing) wrapped in a `PSCredential`. A PAT has an expiry, so this is a recurring operational task. Same source.
- PSResourceGet route uses a v3 URL and SecretManagement/SecretStore for credentials; the Credential Provider is not supported with PSResourceGet. Same source.

Net: both feeds work with PowerShellGet v2 on 5.1 but add a credential to manage on every node. Worth it only if a feed already exists and both nodes can reach it.

## 3. Microsoft.PowerShell.PSResourceGet on 5.1 / Server Core

- README: "PowerShell 5.0 or higher"; included in PowerShell 7.4+; otherwise from the PowerShell Gallery. [PSResourceGet README](https://github.com/PowerShell/PSResourceGet/blob/master/README.md)
- Microsoft states PSResourceGet replaces PowerShellGet/PackageManagement and is standalone. Current: PSResourceGet 1.2.0 (1.3.0-preview1 in preview); PowerShellGet 2.2.5 + PackageManagement 1.4.8.1 also current. [Package management overview](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/overview?view=powershellget-3.x)
- On 5.1 it is not in-box, so first contact still needs `Install-Module Microsoft.PowerShell.PSResourceGet` (needs in-box PowerShellGet upgraded first, or an internal copy). [Install page](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/install-powershellget?view=powershellget-2.x)
- `Register-PSResourceRepository` accepts `https://`, `http://`, `ftp://`, `file://` URIs; `ApiVersion Local` is for file-system repos. [Register-PSResourceRepository](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/register-psresourcerepository?view=powershellget-3.x) UNC-path use is not demonstrated (**Not verified**).
- `Install-PSResource` default scope is `CurrentUser`; use `-Scope AllUsers`. The doc's AllUsers example path is the PowerShell 7 one; the 5.1 path is **Not verified** there. [Install-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/install-psresource?view=powershellget-3.x)
- Server Core: **Not verified**. No fetched primary source mentions Server Core. A one-node smoke test is needed before relying on it.

Net: workable in principle, but adds a deployment step and has thinner 5.1 documentation. The map already settled on `Install-Module`, which is consistent with PowerShellGet v2.

## 4. Prerequisites on each node (PowerShellGet v2 path)

- In-box 5.1 ships PowerShellGet and PackageManagement **1.0.0.1**, unsupported per Microsoft; upgrade to PowerShellGet 2.2.5 (`Install-Module PowerShellGet -Repository PSGallery -Force -AllowClobber`). [Install page](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/install-powershellget?view=powershellget-2.x)
- NuGet provider **>= 2.8.5.201** is required to interact with NuGet-based repositories, in `C:\Program Files\PackageManagement\ProviderAssemblies` (or the per-user location). `Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force`; `-Scope AllUsers` targets `$env:ProgramFiles\PackageManagement\ProviderAssemblies`. Install page and [Install-PackageProvider](https://learn.microsoft.com/en-us/powershell/module/packagemanagement/install-packageprovider?view=powershellget-2.x).
- TLS 1.2 is required to reach the PowerShell Gallery: `[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12`. Install page. A pure `\\share` repository does not use HTTP, so TLS matters only for the one-time bootstrap and any HTTPS feed (inference).
- Disconnected nodes: Microsoft documents `OfflinePowerShellGetDeploy` (`Save-PowerShellGetForOffline`, `Install-PowerShellGetOffline`); the result can also be published into the local repo. PowerShellGet must not be loaded in the session when running it. [Local PSRepositories](https://learn.microsoft.com/en-us/powershell/gallery/how-to/working-with-local-psrepositories?view=powershellget-2.x)
- `-InstallationPolicy Trusted` avoids the untrusted-repository prompt, needed for unattended installs. [Register-PSRepository](https://learn.microsoft.com/en-us/powershell/module/powershellget/register-psrepository?view=powershellget-2.x)

## 5. Scope, per-user registration, and SYSTEM

- **Repository registrations are per user**: "Registered repositories are user-specific. They are not registered in a system-wide context." [Register-PSRepository](https://learn.microsoft.com/en-us/powershell/module/powershellget/register-psrepository?view=powershellget-2.x) Registering as an admin does not register for SYSTEM, and vice versa.
- **Scope**: docs say PowerShellGet 1.x defaults to AllUsers; v2 defaults are documented for PowerShell 6+ (CurrentUser unless elevated). The 5.1 default for v2 is not stated, so pass `-Scope AllUsers` explicitly from an elevated session. [Install-Module](https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershellget-2.x) The Windows PowerShell all-users module folder is `C:\Program Files\WindowsPowerShell\Modules` (shown in the install page output); the Install-Module page's `$env:ProgramFiles\PowerShell\Modules` is the PowerShell 7 path.
- **What the SYSTEM scheduled tasks need**: only the module already installed at the all-users path. They do not need PowerShellGet, the NuGet provider, a registered repository or share access at run time; those are needed only by the elevated admin who installs or updates. (Inference from the per-user-registration and module-path facts.)
- If SYSTEM ever had to self-update it would need its own `Register-PSRepository` run as SYSTEM and share read access as the computer account (`DOMAIN\NODE$`). No fetched source documents this pattern (**Not verified**); prefer admin-driven updates.

## 6. Update / rebuild flow

1. Bump `ModuleVersion` in the `.psd1` (must match the package version on NuGet-backed feeds).
2. `Publish-Module -Path src\WSUS -Repository <name> -NuGetApiKey <string>` from an admin workstation or CI runner with write access. On a share each version is a separate `.nupkg`; the docs note no constraints such as replacing existing items. [Local PSRepositories](https://learn.microsoft.com/en-us/powershell/gallery/how-to/working-with-local-psrepositories?view=powershellget-2.x)
3. On each node, elevated: `Install-Module WSUS -Repository <name> -Scope AllUsers -Force` (or `Update-Module WSUS`). `-Force` allows side-by-side versions; if the same name and version is already installed `Install-Module` silently does nothing. [Install-Module](https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershellget-2.x)
4. `Install-Module` does not import. Scheduled tasks start a fresh `powershell.exe` each run, so they pick up the new version next run; open sessions keep the old one.

## Open items (not answerable from primary docs)

- Server Core smoke test: PowerShellGet 2.2.5 + NuGet provider + file-share install.
- Whether nodes can reach the PowerShell Gallery for the PowerShellGet bootstrap, or the offline route is required.
- Which identity and ACL give nodes read access to the share (computer accounts vs. an admin `-Credential`).
