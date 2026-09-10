# Contributing

Thanks for taking the time. This repository is a small collection of macOS
utilities that **ship as source you assemble locally** — no installer, no
notarized DMG to trust. Contributing here means writing something a stranger can
read end to end before running it on their own machine, and that constraint
shapes everything below.

## Before you open anything

* **Bug** → open an
  [issue](https://github.com/jul6art/macos-utils/issues/new/choose) with your
  macOS version, whether the Mac is Apple silicon or Intel, and the exact
  command you ran with its output.
* **A new utility** → open an issue first. The collection is deliberately small;
  a utility is worth adding when it solves a problem macOS makes genuinely
  awkward, the way `appify.sh` exists because GUI applications launched from the
  Finder do not inherit your shell environment.
* **A security problem** → do not open an issue. Follow
  [SECURITY.md](SECURITY.md), and read the *what is not in scope* section first:
  unsigned builds are a documented consequence here, not a defect.

## The shape of a utility

The README states it, and it is enforced in review:

* sources under `data/sources/<name>/`,
* a document under `data/doc/<NAME>.md` following the existing layout —
  requirements, sources table, installation, usage,
* a row in the utilities table of the README.

`APPIFY.md` and `AWAKE.md` are the reference for tone and structure. A utility
with no documentation is not a contribution, because nobody will run an
undocumented script from a stranger — and they would be right not to.

## Ground rules

1. **Source, not binaries.** A utility is contributed as source that the reader
   compiles or runs. `data/sources/custom_sourcetree.app.zip` is a finished
   example from before that rule, not a precedent: a committed binary is
   something nobody can audit, and new ones will be refused.

2. **A script must be readable end to end by someone deciding whether to trust
   it.** Keep it short, keep it linear, and say in a comment why each step
   exists. This is the single most important rule in the repository.

3. **`set -euo pipefail`, and quote every expansion.** `appify.sh` is the model.
   These scripts take paths and names from the command line and build file paths
   out of them, so an unquoted expansion is a security bug, not a style
   preference. Run `shellcheck data/sources/*.sh data/sources/*/*.sh` before
   opening a pull request and leave it clean.

4. **No `sudo`, and nothing written outside what the doc announces.** Install
   into `/Applications` only when the user asked for `--install`, and say so.
   Never touch a preference domain, a `LaunchAgents` entry or a login item that
   the documentation does not mention.

5. **Whatever you install, document how to remove it.** Including any
   launch-at-login registration — persistence that outlives uninstallation is a
   defect here.

6. **No `curl | sh`, ever.** Not in a script, not in a documentation snippet.
   The user clones the repository and reads what they are about to run; that is
   the entire security model of this project.

7. **No network access at build or run time** unless the utility's purpose
   requires it, in which case say exactly what it contacts and why.

8. **Vendored code keeps its attribution.** `appify.sh` carries a header
   crediting Thomas Aylott's original and stating its licence; anything vendored
   after it does the same, and stays compatible with the MIT licence of this
   repository.

## Testing a change

There is no CI here, and no test suite: these are shell scripts and a small
Swift application. So the validation is manual, and it is on you to do it:

```bash
shellcheck data/sources/*.sh data/sources/*/*.sh   # clean
sh data/sources/appify.sh ~/Desktop/probe.sh "Probe"   # on a throwaway script
sh data/sources/awake/build.sh                    # builds without --install
```

Say in the pull request which macOS version and which architecture you tested
on. A script that only ever ran on Apple silicon should say so rather than imply
both.

For Awake, requirements are **macOS 13+** and the Command Line Tools
(`xcode-select --install`); check that `build.sh` still succeeds from a clean
`build/` directory.

## Pull requests

* One utility, or one fix, per pull request.
* Fill in the [template](pull_request_template.md).
* Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  — `fix: …`, `feat: …`, `docs: …`, `chore: …`. This repository's history is
  written in French; French and English are both fine, and the scripts,
  comments and documentation stay in English.
* Update the README's utilities table in the same pull request when you add a
  utility.
* Rebase on `master` rather than merging it back in.

## Code of conduct

Participation is covered by our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Contributions are accepted under the [MIT license](../LICENSE) that covers this
repository.
