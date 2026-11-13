# Old Fluidd builds

Earlier builds of the Fluidd panel, kept in case you need to go back. The installer does **not** use these.

| Folder | Fluidd | Panel releases | Files |
|---|---|---|---|
| `1.37.7/` | v1.37.7 | 1.5.x to 1.6.1 | `fluidd-v1.37.7-zr-ace.zip` (ready build), `.zip.sha256`, `.patch` (git format-patch series from v1.37.7) |

To go back to one: `mkdir ~/fluidd && unzip fluidd-v1.37.7-zr-ace.zip -d ~/fluidd` (move the current `~/fluidd` away first), after checking it with `sha256sum -c fluidd-v1.37.7-zr-ace.zip.sha256`.
