<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton-generator/blob/master/public/img/logo.png?raw=true" alt="logo dev in the hood"></a>
</p>

<p align="center">
    <a href="https://opensource.org/licenses/MIT" target="_blank"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
    <img src="https://img.shields.io/static/v1?label=stable&message=v1&color=orange" alt="Version">
</p>

MACOS-UTILS
===========
Bounce Report
-------------

Point it at a Mail.app mailbox full of send-failure messages and get an Excel
workbook back: one row per address that could not be reached, with its SMTP
codes, its errors, its first and last failure — the list to hand over to
whoever runs the mail servers.

It reads two kinds of messages:

* **Monolog alerts from a Symfony application** — the
  `Error sending email notification "<subject>" to <address> with message <error>`
  records, HTML or plain text, one record per mail or several when the handler
  buffers them;
* **standard bounces** — RFC 3464 delivery status notifications, as Exchange,
  Postfix or Gmail send them.

A message that reports no failure lands on a sheet of its own: nothing is
silently dropped.

Requirements
------------

* **macOS** with **Mail** holding the mailbox
* **python3** — the Command Line Tools one is enough (`xcode-select --install`);
  standard library only, nothing to `pip install`
* The first run asks to let your terminal **control Mail** (System Settings →
  Privacy & Security → Automation). No Full Disk Access needed: the messages
  are read through Mail, not from `~/Library/Mail`.

Sources
-------

| File | Role |
| --- | --- |
| [bounce_report.py](/data/sources/bounce-report/bounce_report.py) | Reads the mailbox, finds the failures, writes the `.xlsx` |
| [test_bounce_report.py](/data/sources/bounce-report/test_bounce_report.py) | Tests on synthetic messages — no Mail needed |

Usage
-----

```shell
python3 data/sources/bounce-report/bounce_report.py --mailbox NO_REPLY
```

```
Exchange / NO_REPLY: 55 message(s) read
55 failure(s), 37 address(es), 0 unrecognized message(s)
     55  no reply
Written: /Users/you/Desktop/bounce-report-no_reply-2026-11-23.xlsx
```

| Option | Effect |
| --- | --- |
| `--mailbox NAME` | The mailbox to read; case does not matter. An unknown name lists the mailboxes Mail has |
| `--account NAME` | The account holding it, when several accounts have a mailbox of that name |
| `--since DATE` | Only the messages received from that date (`2026-11-01`) or time (`2026-11-01T08:00`) on |
| `--eml PATH…` | `.eml` files, or folders of them, instead of Mail — drag messages out of Mail to get some |
| `--output FILE` | Where to write; by default on the Desktop, named after the mailbox and the day |
| `--lang en\|fr` | Language of the workbook; by default the one of your locale |

For a regular report, keep the date of the last one and pass it to `--since`.

What you get
------------

| Sheet | One row per | Columns |
| --- | --- | --- |
| **By address** | address, most failures first | address, domain, failures, codes received, errors, first and last failure, subjects |
| **Details** | failure, oldest first | date, address, domain, subject, expected code, code received, enhanced status, error, the alert's subject |
| **Unrecognized** | message reporting no failure — only when there is one | date, sender, subject |

The counts and the first and last dates of *By address* are formulas over
*Details* (`COUNTIF`, `MINIFS`, `MAXIFS`), stored with their values: delete
the rows of a false alarm in *Details* and the summary follows, while a viewer
that computes nothing — Quick Look, a mail preview — still shows the numbers.

Every header is frozen and filterable. Addresses are grouped regardless of
case.

Reading the codes
-----------------

Symfony Mailer words its SMTP errors as
`Expected response code "250" but got code "550", with message "550 5.1.1 …"`:
the report splits that into the *expected* code, the code *received* and the
enhanced status (`5.1.1`). **`no reply`** means the server answered nothing at
all — Symfony's `got empty code`, raised when the connection is closed by the
time it reads the answer: look at the connection between the application and
its SMTP server before looking at the address.

A bounce gives no expected code: its received code and status come from its
`Diagnostic-Code` and `Status` fields.

Tests
-----

```shell
python3 -m unittest discover -s data/sources/bounce-report
```

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2026 [jul6art](https://devinthehood.com)
