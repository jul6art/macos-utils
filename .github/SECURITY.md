# Security Policy

## What this repository asks of you

Every utility here ships as **source you assemble locally** — no installer, no
notarized DMG. That is the point, and it is also the risk: using this repository
means running shell scripts and compiling Swift on your own machine, with your
own privileges. A defect in one of those scripts runs as you.

So the security of this repository is not about a service being attacked. It is
about whether what you are told to run does only what the documentation says it
does.

## Supported versions

Only the tip of `master` is maintained. There are no releases to backport to.

| Version | Supported |
| --- | --- |
| `master` | ✅ |
| any older commit or fork | ❌ |

## What is in scope

* **A script that does more than its documentation says.** `appify.sh`,
  `custom_macos_app.sh` and `awake/build.sh` are meant to be readable end to
  end; anything in them that touches a path, a preference or a login item the
  doc does not mention is a defect worth reporting.
* **Injection through an argument.** These scripts take a script path and an
  application name and build paths from them. A name or path that escapes its
  quoting and executes is exactly the class of bug to report.
* **A script writing outside its declared scope** — installing into
  `/Applications`, a `LaunchAgents` entry or a preference domain that the doc
  never announced, or leaving a world-writable file behind.
* **Privilege escalation.** Nothing here should need `sudo`. A script that asks
  for it, or that writes somewhere only an administrator can, is in scope.
* **Persistence that outlives uninstallation** — Awake's launch-at-login entry
  surviving the removal of the app, for instance.
* **The pre-built example.** `data/sources/custom_sourcetree.app.zip` is a
  finished example committed as a binary: nobody can read it the way they can
  read a script. If its contents do not match what `custom_macos_app.sh`
  produces, that is a serious report, and it is the kind of thing worth
  checking.
* **A `.app` produced by `appify.sh` being trivially repointed** at a different
  payload once installed, since the bundle is unsigned by construction.

## What is *not* in scope

* **Unsigned and un-notarized applications.** Everything built here is
  unsigned; Gatekeeper will say so, and you will have to allow it yourself. That
  is a documented consequence of shipping source instead of a signed installer,
  not a vulnerability. If you need a signed build, sign it yourself.
* **Vulnerabilities in macOS, Xcode or the Command Line Tools** — report those
  to Apple.
* **`appify.sh` being able to wrap a malicious script.** It wraps whatever you
  hand it; that is its whole function. Read the payload before wrapping it.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Use [GitHub's private vulnerability reporting](https://github.com/jul6art/macos-utils/security/advisories/new)
(the **Security** tab → *Report a vulnerability*). It opens a draft advisory only
you and the maintainers can read, and it is the channel this project prefers —
no email address needs to be published for it to work.

Please include:

* which utility and which file, with the line number,
* your macOS version and whether the Mac is Apple silicon or Intel,
* the exact command you ran and what it did that the documentation does not
  describe,
* for the pre-built example: how you inspected it, and what you found.

## What to expect

* An acknowledgement within **7 days**.
* An assessment — accepted, out of scope, or needing more detail — within
  **14 days**.
* For an accepted report: a fix on `master`, credit in the commit unless you ask
  otherwise, and an [advisory](https://github.com/jul6art/macos-utils/security/advisories)
  when the problem affected anyone who already ran the script — because a fix
  here does not reach a `.app` already sitting in someone's `/Applications`.

Please give the maintainers a reasonable window to ship a fix before disclosing
publicly. This project runs no bug-bounty programme and offers no payment.
