# Glossary

**Node**: A single WSUS server with its own Windows Internal Database and content disk. Nothing is shared between nodes.

**Upstream**: The node that syncs from Microsoft and holds every approval, decline and computer group.

**Replica**: A node that copies approvals, declines and content from the upstream. It takes client traffic only when the upstream is down.

**Promote**: Turn a replica into an upstream. Used only when the original upstream is lost for good.

**Sync source**: Where a node gets its updates from: Microsoft Update, or an Upstream.

**Ring**: A computer group that receives approved updates at a stage of the rollout (Packer, Pilot, Workstations, Servers, VDI).

**Approval rule**: An automatic rule on the upstream that approves arriving updates for a ring. Rules are created off and turned on deliberately.

**Maintenance run**: The weekly job on each node that declines, cleans up and reindexes.

**Decline run**: The 15-minute job on the upstream that declines unwanted updates soon after they arrive.

**Gate**: The check an update must pass before it is promoted from one ring to the next: soaked long enough, tested by at least one computer, installed on enough computers, and not failed on any.
