Open up a terminal and run this command to install GlistEngine:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/scripts/linux/install-glist.sh)"
```

## Options

The installer asks nothing it does not have to when given these, as flags or as environment variables:

| Flag | Environment variable | Effect |
| --- | --- | --- |
| `--github-user NAME` | `GLIST_GITHUB_USERNAME=NAME` | Clone GlistEngine and GlistApp from NAME's forks instead of GlistEngine's own. Without it, the installer asks on a terminal and uses GlistEngine's. |
| `--unattended` | `GLIST_UNATTENDED=1` | Ask no questions. sudo may still ask for your password. |
| `--no-eclipse` | `GLIST_NO_ECLIPSE=1` | Skip the Eclipse desktop shortcut. |

It reports each step as `==> [n/total] name` and ends with `==> Done: ...` or `==> Failed: ...`, so a program running it, such as Glist Studio, can show progress.

For example, without questions or Eclipse:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/scripts/linux/install-glist.sh)" -- --unattended --no-eclipse
```
