# Contributing to koha-autoinstall

Thank you for helping improve this installer!

## Before You Start

- Test every change on a **clean Ubuntu 24.04.4 LTS VM or container** — not just a syntax check.
- The script must run fully unattended from start to finish without stalling.
- The live dashboard (fixed header + scrolling feed) must remain functional.

## How to Contribute

1. **Fork** the repository and create a branch: `git checkout -b feature/my-improvement`
2. Make your changes to `koha-install.sh`
3. Run the syntax check: `bash -n koha-install.sh`
4. Test a **full clean install** on Ubuntu 24.04 (fresh VM recommended)
5. Test a **reinstall over an existing installation** to verify detection + purge works
6. Update `README.md` if you add a new feature or change behaviour
7. Submit a **Pull Request** with a clear description of what changed and why

## Code Style

- Functions use `snake_case`
- All output to the terminal goes through `ui()`, `feed_line()`, or `tag_*()` — never raw `echo` after fd3 is set up
- Every command that can fail must use `|| fatal "step" "cmd"` or `|| true` — never left bare
- Use `run_hard` for commands that must succeed, `run_soft` for optional/best-effort operations
- Add `log "..."` calls for anything significant so the log file is useful
- Keep the ANSI colour variables (`F1`–`F8`, `BG*`) — don't add raw escape codes

## Testing Checklist

Before submitting a PR, verify:

- [ ] `bash -n koha-install.sh` passes with no errors
- [ ] Fresh install completes successfully on Ubuntu 24.04
- [ ] Reinstall (running script twice) correctly detects, purges, and reinstalls all components
- [ ] Ctrl+C mid-install shows error panel and rolls back cleanly
- [ ] Killing the script with `kill -9` (simulate crash) — re-run after clearing lock file works
- [ ] Credentials file is created with `chmod 600` and contains correct values
- [ ] Log file is created in `/var/log/` and contains full output
- [ ] Koha web installer is accessible at `:8080` after script completes
- [ ] OPAC is accessible at `:80`

## Reporting Bugs

Open an issue with:
- Ubuntu version (`lsb_release -a`)
- The full log file (`/var/log/koha-install-*.log`)
- What step failed and any error message shown
- Whether it was a fresh install or reinstall

## Feature Ideas Welcome

See the "Known Improvement Areas" list in README.md for things we'd love help with.
