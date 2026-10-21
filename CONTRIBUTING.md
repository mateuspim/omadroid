# Contributing to OmaDroid

Thanks for helping. OmaDroid is a small project; issues and focused pull
requests are welcome.

## Before you start

- Bugs and ideas: open an issue first for anything larger than a small fix.
- Security problems: follow [SECURITY.md](SECURITY.md), not a public issue.
- Read [AGENTS.md](AGENTS.md): it holds the code rules for people and coding
  agents alike. [docs/architecture.md](docs/architecture.md) says how the
  parts fit, and [docs/specs](docs/specs/) the contracts between them.

## Set up

Clone the repository, link it in place of the installed plugin and enable it:

```bash
git clone https://github.com/mateuspim/omadroid
ln -s "$PWD/omadroid" ~/.config/omarchy/plugins/pym.omadroid
omarchy plugin enable pym.omadroid --section right
```

The [development runbook](docs/runbooks/development.md) has the details:
test requirements, logs and offscreen previews.

## Make a change

1. Branch from `master`.
2. Keep the change focused; update the README section or doc it affects.
3. Add or update tests: every new function gets one, a bug fix gets a
   regression test, and external tools are faked with `tests/mock-*.sh`. Run
   `bash tests/run-all.sh` (it must print `OMADROID_ALL_OK`) and
   `omarchy plugin validate .`.
4. For UI changes, attach an offscreen render
   (`OMADROID_PREVIEW_DIR=<dir> bash tests/smoke.sh`, see the
   [development runbook](docs/runbooks/development.md#offscreen-previews)),
   never a desktop screenshot with personal data.
5. Durable design choice? Add an ADR under [docs/adr](docs/adr/README.md).

## Commit style

Plain imperative subject ("Add …", "Keep …"), under ~72 characters, and a
body that explains why.

## Pull request checklist

- [ ] `bash tests/run-all.sh` prints `OMADROID_ALL_OK` and `omarchy plugin validate .` exits 0
- [ ] Docs and CHANGELOG (Unreleased) updated
- [ ] No personal paths, device names, serials or addresses in tracked files

CI runs every suite except the two QML ones, which need a desktop with the
Omarchy shell; run the full command locally.

## License

By contributing you agree your work is released under the [MIT License](LICENSE).
