Open up a powershell terminal and run this command to install GlistEngine:

```ps
irm "https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/scripts/windows/install-glist.ps1" | iex
```

## Options

The installer takes these as environment variables, which also work with `irm ... | iex`, or as flags when the script is run with `powershell -File`:

| Flag | Environment variable | Effect |
| --- | --- | --- |
| `--github-user NAME` | `GLIST_GITHUB_USERNAME=NAME` | Clone GlistEngine and GlistApp from NAME's forks instead of GlistEngine's own. Without it, GlistEngine's are used. |
| `--unattended` | `GLIST_UNATTENDED=1` | Ask no questions. The installer then also does not wait for Enter when something fails. |
| `--no-eclipse` | `GLIST_NO_ECLIPSE=1` | Skip the Eclipse desktop shortcut, and do not start Eclipse at the end. |

It reports each step as `==> [n/total] name` and ends with `==> Done: ...` or `==> Failed: ...`, so a program running it, such as Glist Studio, can show progress.

For example, without questions or Eclipse:

```ps
$env:GLIST_UNATTENDED = "1"; $env:GLIST_NO_ECLIPSE = "1"
irm "https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/scripts/windows/install-glist.ps1" | iex
```
