# Research: WSUS downstream modes, autonomous versus replica

Question: the glossary has two roles (Upstream syncs from Microsoft, Replica copies from the Upstream).
`Set-WsusUpstreamConfig -UpstreamServer` sets `SyncFromMicrosoftUpdate = $false` plus the
`UpstreamWsusServer*` properties but never `IsReplicaServer`. Is that a valid third mode, or a
misconfiguration? Is "two modes" right?

## Verdict

Not quite two. Microsoft documents **three** shapes of Node: one that syncs from Microsoft Update,
and two downstream modes, **autonomous** and **replica**. The `-UpstreamServer` branch produces
exactly an autonomous downstream server: `SyncFromMicrosoftUpdate = false`, `IsReplicaServer = false`,
upstream name set. It is a valid, documented configuration, not a misconfiguration. It is a **third
role the module's glossary does not name**. Under the glossary's vocabulary it is neither an Upstream
(it does not sync from Microsoft) nor a Replica (it copies no approvals or computer groups). The
module's own `Get-WsusNodeRole` reports it as `Upstream`, because it tests only `IsReplicaServer`.

## Primary-source facts

### 1. The modes

| Claim | Source |
|---|---|
| In a hierarchy, "You can connect WSUS servers in Autonomous mode (to achieve distributed administration) or in Replica mode (to achieve centralized administration)", and a hierarchy may mix both | Plan Your WSUS Deployment: https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment |
| Autonomous mode (distributed administration) is "the default installation option for WSUS". An upstream server "shares updates with downstream servers during synchronization. Downstream WSUS servers are administered separately, and they don't receive update approval status or computer group information from the upstream server." Each administrator "selects update languages, creates computer groups, assigns computers to groups, tests and approves updates" | same |
| Replica mode (centralized administration): the upstream "shares updates, approval status, and computer groups with downstream servers. Replica servers inherit update approvals and aren't administered separately from the upstream WSUS server." | same |
| A downstream server "can be an autonomous server or a replica server" | IUpdateServerConfiguration.IsReplicaServer, Remarks: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms751943(v=vs.85) |
| Autonomous: "synchronizes the same updates as the upstream server; however, it can create its own target groups and manage its own approvals, and can download content from Microsoft Update or from the upstream server." | same |
| Replica: "replicates the upstream server. The only difference between an upstream server and the replica server is the clients they manage. The replica server synchronizes the same updates as the upstream server, and has the same target groups, approvals, accepted license agreements (EULAs), and declined status as the upstream server." "Automatic approval rules are disabled on the replica server." | same |
| Replica page: a replica "inherits the update approvals and computer groups created on an administration server". Computer group membership "is not distributed to replica servers, only the computer groups themselves", so groups arrive empty and the replica's own clients must be assigned | Running WSUS Replica mode: https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/manage/running-wsus-replica-mode |
| On a replica, administration is limited to: group membership, sync schedule, proxy settings, update source ("can be a server other than the administration server"), viewing updates, monitoring and reports | same |
| "If a WSUS server is running in replica mode, computer groups can't be created on that server"; they must be created on the root of the hierarchy | Plan Your WSUS Deployment (section 1.5): URL as above |

### 2. Properties that distinguish them

| Property | What the API reference says | Source |
|---|---|---|
| `IsReplicaServer` | Get or set whether the server is a replica | ms751943 (URL above) |
| `SyncFromMicrosoftUpdate` | `true` syncs from Microsoft Update, `false` syncs from a local WSUS server. "You cannot set this property to true if IsReplicaServer is true." If false, `UpstreamWsusServerName` must be given | https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms751957(v=vs.85) |
| `UpstreamWsusServerName` | "You must specify the server name when SyncFromMicrosoftUpdate is false." Name or IP, under 256 characters | https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms751959(v=vs.85) |
| `UpstreamWsusServerPortNumber` | Used if `SyncFromMicrosoftUpdate` is false. Default 80. "Typically, you specify port 80 for HTTP and 443 for HTTPS" | https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms751960(v=vs.85) |
| `UpstreamWsusServerUseSsl` | Used if `SyncFromMicrosoftUpdate` is false. If true, set the port "to the correct port number for SSL, which is typically 443" | https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms751961(v=vs.85) |
| `GetContentFromMU` | true: download binaries from Microsoft Update; false: from the upstream server. "This option applies only if the server is a downstream server and content is downloaded locally." | https://learn.microsoft.com/en-us/previous-versions/windows/desktop/aa352974(v=vs.85) |
| `TargetingMode` | Enum `Client` (clients choose their group) or `Server` (server decides). Says nothing about modes | https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms751958(v=vs.85) and https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms752787(v=vs.85) |

The cmdlet `Set-WsusServerSynchronization` has two parameter sets that mirror this: `-SyncFromMU`, and
`-UssServerName [-PortNumber] [-UseSsl] [-Replica]`. `-Replica` is an optional switch on the upstream
set, so the cmdlet itself treats "sync from another WSUS server, not a replica" as a normal call:
https://learn.microsoft.com/en-us/powershell/module/updateservices/set-wsusserversynchronization

Combination table (derived by reading the property pages together; the combinations are not
tabulated by Microsoft):

| `SyncFromMicrosoftUpdate` | `IsReplicaServer` | Upstream name | Meaning |
|---|---|---|---|
| true | false | unused | Syncs from Microsoft Update. The module's Upstream. |
| false | false | required | **Autonomous downstream.** Syncs updates from another WSUS server and manages its own groups and approvals. |
| false | true | required | **Replica.** Mirrors approvals, groups, EULAs and declines from the upstream. |
| true | true | n/a | Not allowed: the setter refuses `SyncFromMicrosoftUpdate = true` when `IsReplicaServer` is true. |

So `SyncFromMicrosoftUpdate = false` with `IsReplicaServer = false` is, per the `IsReplicaServer`
remarks, an autonomous downstream server.

### 3. Does an autonomous node still contact Microsoft?

For **update metadata**, no: it syncs from its upstream (`SyncFromMicrosoftUpdate = false`). For
**content**, it can: the `IsReplicaServer` remarks say an autonomous server "can download content from
Microsoft Update or from the upstream server", and `GetContentFromMU = true` selects Microsoft Update
(applies only to a downstream server that stores content locally). Microsoft's deploy guide also says
that on a slow link you can configure other servers "to receive update payloads directly from
Microsoft", needing "access to the same internet domains as the topmost server":
https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus
(section 2.1.2). The plan guide adds that clients can also be sent to Microsoft Update if the server
does not store content locally ("Remote storage on Microsoft Update servers").
That guide's branch-office note describes downstream servers that "get information about which updates
to install from the central WSUS server, but download the updates from Microsoft Update".

### 4. Computer groups, approvals, declines per mode

| | Autonomous | Replica |
|---|---|---|
| Update metadata | synced from upstream | synced from upstream |
| Computer groups (the groups) | created and owned locally | synced from the upstream; cannot be created locally |
| Group membership | local | not synced; replica's clients assigned locally to the inherited groups |
| Approvals | local | inherited |
| Declined status | not synced (see Unverified) | synced |
| Auto-approval rules | not stated as disabled | disabled |
| Targeting | local (server-side or client-side) | clients still join groups locally |

Sources: Plan Your WSUS Deployment, Running WSUS Replica mode, IsReplicaServer remarks (URLs above).
Answer to "computer groups synced only for replicas": yes, per the plan guide ("don't receive ... computer
group information") and the IsReplicaServer remarks ("can create its own target groups"). Membership
is never synced even for a replica.

Related: when syncing from an upstream server WSUS "ignores" `AllUpdateLanguagesEnabled`,
`SetEnabledUpdateLanguages`, `DownloadExpressPackages`, `DownloadUpdateBinariesAsNeeded` and
`HostBinariesOnMicrosoftUpdate` (SyncFromMicrosoftUpdate remarks, ms751957). Also, in a hierarchy
"WSUS automatically sets all downstream servers to use the deferred download setting" and the product
and classification filter of the root (plan guide section 1.6), and the languages chosen on a downstream
server are bounded by the upstream's.

### 5. Guidance, limits, deprecation

- Microsoft frames the choice as distributed administration (autonomous) versus centralized
  administration (replica); a hierarchy can mix both (plan guide).
- Hierarchy depth: recommended no more than three levels; only five levels tested. Downstream servers
  must be at the same or an earlier WSUS version than the upstream (plan guide).
- With several replicas of one upstream, do not schedule their syncs at the same time (plan guide).
- A deeply nested hierarchy with deferred downloads delays updates, because a downstream request for an
  unapproved update forces the upstream to download it first (plan guide, section 1.6).
- The replica page says replica servers "can be set up only during WSUS Setup". The object model and
  `Set-WsusServerSynchronization -Replica` expose a setter, so this statement and the API disagree; see
  Unverified.
- WSUS is deprecated: Microsoft announced it is no longer investing in new capabilities or accepting
  feature requests, preserves current functionality, and has no current plans to remove WSUS from
  in-market Windows Server versions including 2025. Announcement:
  https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-server-update-services-wsus-deprecation/4250436
  (the page body could not be fetched; the wording is from search-result summaries of that page, so
  treat the detail as Unverified until read in a browser). Neither mode is deprecated separately.

## Fit to the module

- `Set-WsusUpstreamConfig` lines 70-79 set exactly the autonomous-downstream property set when
  `-UpstreamServer` is given. It does not touch `IsReplicaServer`, and `Assert-WsusUpstream` is called
  first (so a Replica is refused with "Promote it first").
- `Get-WsusNodeRole.ps1` line 14 returns `Replica` if `IsReplicaServer` else `Upstream`, so an
  autonomous node reports `Upstream`. Nothing distinguishes the two by `SyncFromMicrosoftUpdate`.
- In the `-UpstreamServer` case, language, express-package and binary-download settings set at lines
  86-90 are ignored by WSUS per the remarks above (the property pages say ignored; the real effect on a
  live server was not tested).
- `UpstreamWsusServerUseSsl = ($UpstreamPort -eq 8531)` assumes the upstream's SSL port is 8531.
  Microsoft's property pages say "typically 443"; the guide gives 8530/8531 as the ports a WSUS server
  offers to downstream servers and clients (deploy guide 2.1.2, 2.3.2), which fits the module. Fine.
- The module's parameter comment says "for example to chain downstream of DISA". Chaining to a DISA
  server and keeping local groups and approvals is the autonomous case, and the glossary's "Upstream
  holds every approval, decline and computer group" is then true only locally.

## Recommendation (not a cited fact)

Keep the branch, but name what it is. Options in order of preference:

1. Keep `-UpstreamServer`, document it in `GLOSSARY.md` as an **autonomous** Upstream (a node that
   syncs from another WSUS server instead of Microsoft, and holds its own approvals and groups), and
   make `Get-WsusNodeRole` and the output object say so rather than printing `Upstream` with the DISA
   host as its source. This costs the least and matches the "chain downstream of DISA" use case already
   stated in the parameter comment.
2. If the owner wants strictly two roles, remove the branch. Do not leave it half-supported: today it
   silently produces a node the glossary has no word for.

It is not a misconfiguration, so do not "fix" it by setting `IsReplicaServer = $true`; that would change
the behaviour (approvals and groups would be inherited, and local group creation would be refused).

## Unverified

- Whether an autonomous server receives **declines** from its upstream. Microsoft says autonomous
  servers do not receive "approval status or computer group information" and that replicas get "declined
  status"; declines for autonomous are not stated. (Metadata revisions that expire an update still
  arrive with the update catalog; not read in a primary source.)
- Whether `IsReplicaServer = $true` can be set after setup. The replica page says replica servers "can
  be set up only during WSUS Setup"; the API and `Set-WsusServerSynchronization -Replica` suggest a
  setter exists. The module's own `Set-WsusReplicaConfig` and `ConvertTo-WsusUpstream` rely on it. This
  needs a live test.
- The full text of the 2024 WSUS deprecation announcement (see above).
- That the `-UpstreamServer` code path works end to end on a live Node (not run, and no primary source
  describes the module).
- Whether `GetContentFromMU` has any effect on a replica. The property page only says "downstream
  server"; no page ties it to autonomous only.
- The TechNet/WSUS 3.0 deployment guide the TargetingMode and UseSsl pages link to (go.microsoft.com
  fwlink) was not read.

## Sources read

- https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment
- https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus
- https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/manage/running-wsus-replica-mode
- https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms752728(v=vs.85) (IUpdateServerConfiguration)
- IUpdateServerConfiguration members: ms751943, ms751957, ms751959, ms751960, ms751961, ms751958, aa352974, ms752787 (same base URL as above)
- https://learn.microsoft.com/en-us/powershell/module/updateservices/set-wsusserversynchronization
- https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-server-update-services-wsus-deprecation/4250436 (listing only)
