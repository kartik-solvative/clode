# Contributing to clode

Thanks for your interest in contributing!

## How to contribute

1. **Fork** the repo and clone your fork
2. **Create a branch** from `master`: `git checkout -b my-fix`
3. **Make your changes** — keep them focused and minimal
4. **Test locally**:
   ```bash
   source clode.sh
   type clode          # confirm function loaded
   ./install.sh        # confirm idempotent
   ```
5. **Open a PR** against `master` — fill in the PR template

## Guidelines

- **One change per PR** — don't bundle unrelated fixes
- **No secrets** — never commit tokens, keys, or `.env` files
- **Shell compatibility** — functions must work in both `zsh` and `bash`
- **Security first** — don't weaken the hardening defaults (`--cap-drop`, `--security-opt`, resource limits) without a strong reason

## Reporting issues

Use the GitHub issue templates. Include your OS, Docker version, and the exact error output.
