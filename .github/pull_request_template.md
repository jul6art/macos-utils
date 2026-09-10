## What this changes

<!-- One utility, or one fix, per pull request. -->

Closes #

## Type

- [ ] Fix to an existing utility
- [ ] New utility — sources under `data/sources/`, doc under `data/doc/`, row in
      the README table
- [ ] Documentation only

## What it touches on the machine

<!-- Paths written, preference domains, login items, network access. "Nothing
     outside what the doc announces" is the rule; say what the doc announces. -->

- [ ] Nothing is written outside what the documentation announces
- [ ] No `sudo` anywhere
- [ ] No `curl | sh`, in the script or in the doc
- [ ] Whatever it installs, the doc says how to remove it — launch-at-login
      registration included
- [ ] No new committed binary (source only)

## Validation

Tested on macOS ______ , ☐ Apple silicon ☐ Intel

```
shellcheck data/sources/*.sh data/sources/*/*.sh
```

- [ ] `shellcheck` is clean
- [ ] Every script keeps `set -euo pipefail` and quotes its expansions
- [ ] I ran the utility on a throwaway target and it did what the doc says
- [ ] For Awake: `build.sh` succeeds from a clean `build/` directory

<details>
<summary>Output</summary>

```
```

</details>

## Notes for the reviewer

<!-- Vendored code and its attribution, anything left out on purpose. -->
