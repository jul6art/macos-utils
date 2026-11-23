#!/usr/bin/env python3
"""Bounce Report: the send failures reported in a Mail.app mailbox, as an Excel workbook.

Reads the messages of one mailbox through Mail's scripting interface (or .eml files), finds every failed delivery
they report and writes an .xlsx with one row per address and one row per failure. Two kinds of messages are read:

* the alerts a Symfony application sends through Monolog when a notification mail fails
  ("Error sending email notification "<subject>" to <address> with message <error>"), or when its worker gives up on
  a queued mail ("Mail "<subject>" to <addresses> not sent after <n> attempt(s): <error>"), as HTML or plain text;
* standard delivery status notifications (RFC 3464 bounces, as Exchange, Postfix or Gmail send them).

A message that reports no failure is listed on a sheet of its own, never dropped. Standard library only: the python3
of the Command Line Tools is enough.
"""

from __future__ import annotations

import argparse
import datetime as dt
import email
import html
import json
import os
import re
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from email import policy
from email.message import EmailMessage
from email.utils import parsedate_to_datetime
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr


# ---------------------------------------------------------------------------------------------------------------------
# What a message reports
# ---------------------------------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Failure:
    when: dt.datetime | None
    address: str
    subject: str
    expected: str
    # The SMTP code the server answered: None when it answered nothing at all, "" when the message does not say.
    received: str | None
    status: str
    error: str
    reported_by: str

    @property
    def domain(self) -> str:
        return self.address.rpartition('@')[2].lower() if '@' in self.address else ''


@dataclass(frozen=True)
class Unrecognized:
    when: dt.datetime | None
    sender: str
    subject: str


@dataclass(frozen=True)
class Source:
    """One message as read from Mail or from a file: its raw RFC 822 text and, from Mail, its reception date."""

    text: str
    received: dt.datetime | None = None


NOTIFICATION = re.compile(
    r'Error sending email notification(?: "(?P<subject>.*?)")? to (?P<address>\S+) with message (?P<error>.*)',
    re.S,
)
# When the mails go through a Messenger queue, the queue retries a refused one, and the alert comes only once the
# worker gives up: "Mail "<subject>" to <address>, <address> not sent after <n> attempt(s): <error>".
GAVE_UP = re.compile(
    r'Mail "(?P<subject>.*?)" to (?P<recipients>.*?) not sent after \d+ attempt\(s\): (?P<error>.*)',
    re.S,
)
SMTP_REPLY = re.compile(
    r'Expected response code "(?P<expected>[\d/]+)" but got (?:code "(?P<code>\d{3})"|(?P<empty>empty code))'
    r'(?:, with message "(?P<reply>.*?)")?\.?$',
    re.S,
)
ENHANCED_STATUS = re.compile(r'(?<![\d.])([245]\.\d{1,3}\.\d{1,3})(?![\d.])')
MONOLOG_FIELD = r'<th[^>]*>\s*{}:\s*</th>\s*<td[^>]*>\s*<pre>(.*?)</pre>'
MONOLOG_LINE = re.compile(
    r'^\[(?P<time>[^\]]+)\] [\w.-]+\.[A-Z]+: (?P<message>.*?)(?: (?:\{.*\}|\[.*\]) (?:\{.*\}|\[.*\]))?\s*$',
    re.M,
)


def analyse(sources: list[Source]) -> tuple[list[Failure], list[Unrecognized]]:
    failures: list[Failure] = []
    unrecognized: list[Unrecognized] = []

    for source in sources:
        message = email.message_from_string(source.text, policy=policy.default)
        sent = header_date(message) or source.received
        try:
            found = delivery_status_failures(message, sent) or monolog_failures(message, sent)
        except Exception:  # a malformed message must not stop the report: it is listed instead
            found = []

        if found:
            failures.extend(found)
        else:
            unrecognized.append(Unrecognized(sent, str(message.get('From', '')), str(message.get('Subject', ''))))

    return failures, unrecognized


def monolog_failures(message: EmailMessage, sent: dt.datetime | None) -> list[Failure]:
    """The notification failures of a Monolog alert: one record per mail, or several when the handler buffers."""
    reported_by = str(message.get('Subject', ''))
    records: list[tuple[str, str | None]] = []

    html_part = message.get_body(preferencelist=('html',))
    if html_part is not None:
        body = html_part.get_content()
        # HtmlFormatter opens every record with its level as a <h1>; a buffered alert holds several of them.
        for chunk in re.split(r'(?=<h1[\s>])', body):
            text = re.search(MONOLOG_FIELD.format('Message'), chunk, re.S | re.I)
            if text:
                time = re.search(MONOLOG_FIELD.format('Time'), chunk, re.S | re.I)
                records.append((html.unescape(text[1]).strip(), html.unescape(time[1]).strip() if time else None))

    if not records:
        text_part = message.get_body(preferencelist=('plain',))
        if text_part is not None:
            for line in MONOLOG_LINE.finditer(text_part.get_content()):
                records.append((line['message'].strip(), line['time']))

    failures = []
    for text, time in records:
        notification = NOTIFICATION.search(text)
        if notification is not None:
            mails = [(notification['address'], notification['subject'] or '', notification['error'])]
        else:
            gave_up = GAVE_UP.search(text)
            if gave_up is None:
                continue  # another record of the same alert, not a mail that failed
            mails = [(address.strip(), gave_up['subject'], gave_up['error'])
                     for address in gave_up['recipients'].split(',') if address.strip()]

        for address, subject, error in mails:
            error = error.strip()
            expected, received, status = smtp_codes(error)
            failures.append(Failure(
                when=parse_time(time) or sent,
                address=address,
                subject=subject,
                expected=expected,
                received=received,
                status=status,
                error=error,
                reported_by=reported_by,
            ))

    return failures


def delivery_status_failures(message: EmailMessage, sent: dt.datetime | None) -> list[Failure]:
    """The failed and delayed recipients of an RFC 3464 report (multipart/report; message/delivery-status)."""
    original_subject = ''
    reports = []
    for part in message.walk():
        content_type = part.get_content_type()
        if content_type == 'message/delivery-status':
            reports.append(part)
        elif content_type == 'message/rfc822' and not original_subject:
            original_subject = str(part.get_payload(0).get('Subject', ''))
        elif content_type == 'text/rfc822-headers' and not original_subject:
            original_subject = str(email.message_from_string(part.get_content()).get('Subject', ''))

    failures = []
    for report in reports:
        blocks = report.get_payload()
        arrival = header_date_value(blocks[0].get('Arrival-Date')) if blocks else None
        for block in blocks:
            recipient = block.get('Final-Recipient') or block.get('Original-Recipient')
            action = str(block.get('Action', '')).strip().lower()
            if not recipient or action not in ('failed', 'delayed'):
                continue

            status = str(block.get('Status', '')).strip()
            diagnostic = ' '.join(str(block.get('Diagnostic-Code', '')).partition(';')[2].split())
            code = re.match(r'(\d{3})\b', diagnostic)
            failures.append(Failure(
                when=arrival or sent,
                address=str(recipient).partition(';')[2].strip().strip('<>'),
                subject=original_subject,
                expected='',
                received=code[1] if code else '',
                status=status or first_enhanced_status(diagnostic),
                error=diagnostic or f'{action} ({status})',
                reported_by=str(message.get('Subject', '')),
            ))

    return failures


def smtp_codes(error: str) -> tuple[str, str | None, str]:
    """Expected code, received code and enhanced status of a Symfony Mailer error."""
    reply = SMTP_REPLY.search(error)
    if reply is None:
        return '', '', first_enhanced_status(error)

    return reply['expected'], None if reply['empty'] else reply['code'], first_enhanced_status(reply['reply'] or '')


def first_enhanced_status(text: str) -> str:
    status = ENHANCED_STATUS.search(text)
    return status[1] if status else ''


def header_date(message: EmailMessage) -> dt.datetime | None:
    return header_date_value(message.get('Date'))


def header_date_value(value: object) -> dt.datetime | None:
    if not value:
        return None
    try:
        return local(parsedate_to_datetime(str(value)))
    except (TypeError, ValueError):
        return None


def parse_time(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        return local(dt.datetime.fromisoformat(value.strip()))
    except ValueError:
        return None


def local(moment: dt.datetime) -> dt.datetime:
    """The wall-clock time of this Mac: a spreadsheet cell holds no time zone."""
    return moment.astimezone().replace(tzinfo=None) if moment.tzinfo else moment


# ---------------------------------------------------------------------------------------------------------------------
# Reading the messages
# ---------------------------------------------------------------------------------------------------------------------

# Bulk property reads (messages.source()) cost one Apple event for the whole mailbox; a date filter falls back to one
# read per message kept.
READ_MAILBOX = r'''
function run(argv) {
    const [wanted, accountWanted, since] = argv;
    const same = (a, b) => a.toLowerCase() === b.toLowerCase();
    const Mail = Application('Mail');
    const matches = [];
    const known = [];

    Mail.accounts.name().forEach((account, i) => {
        if (accountWanted && !same(account, accountWanted)) return;
        const boxes = Mail.accounts[i].mailboxes;
        boxes.name().forEach((name, j) => {
            known.push(account + ' / ' + name);
            if (same(name, wanted)) matches.push({account: account, name: name, box: boxes[j]});
        });
    });
    if (!accountWanted) {
        Mail.mailboxes.name().forEach((name, j) => {
            known.push('On My Mac / ' + name);
            if (same(name, wanted)) matches.push({account: 'On My Mac', name: name, box: Mail.mailboxes[j]});
        });
    }

    if (matches.length === 0) {
        throw new Error('No mailbox named "' + wanted + '". Mailboxes: ' + known.join(', '));
    }
    if (matches.length > 1) {
        throw new Error('Several mailboxes are named "' + wanted + '": '
            + matches.map(m => m.account + ' / ' + m.name).join(', ') + '. Name the account with --account.');
    }

    const {account, name, box} = matches[0];
    const messages = box.messages;
    const dates = messages.dateReceived();
    const from = since ? new Date(since) : null;
    const kept = dates.map((date, i) => i).filter(i => from === null || dates[i] >= from);
    const sources = kept.length === dates.length ? messages.source() : kept.map(i => messages[i].source());

    return JSON.stringify({
        account: account,
        mailbox: name,
        total: dates.length,
        messages: kept.map((i, k) => ({received: dates[i].toISOString(), source: sources[k]})),
    });
}
'''


class ReadError(Exception):
    pass


def read_mailbox(mailbox: str, account: str | None, since: dt.datetime | None) -> tuple[list[Source], str]:
    try:
        result = subprocess.run(
            ['osascript', '-l', 'JavaScript', '-e', READ_MAILBOX, mailbox, account or '',
             since.astimezone().isoformat() if since else ''],
            capture_output=True, text=True, timeout=900,
        )
    except FileNotFoundError:
        raise ReadError('osascript not found: reading Mail needs macOS (or export the messages and use --eml).')
    except subprocess.TimeoutExpired:
        raise ReadError('Mail did not answer within 15 minutes.')

    if result.returncode != 0:
        detail = result.stderr.strip()
        if '-1743' in detail:
            raise ReadError(
                'This terminal may not control Mail. Allow it in System Settings > Privacy & Security > Automation.'
            )
        # "execution error: Error: Error: <message> (-2700)" -> "<message>"
        raise ReadError(re.sub(r'^.*?Error: (?:Error: )?|\s*\(-?\d+\)$', '', detail) or 'osascript failed.')

    data = json.loads(result.stdout)
    sources = [
        Source(item['source'], local(dt.datetime.fromisoformat(item['received'].replace('Z', '+00:00'))))
        for item in data['messages']
    ]
    kept = f'{len(sources)} of {data["total"]}' if since else str(data['total'])
    return sources, f'{data["account"]} / {data["mailbox"]}: {kept} message(s) read'


def read_eml(paths: list[str], since: dt.datetime | None) -> tuple[list[Source], str]:
    files: list[Path] = []
    for path in map(Path, paths):
        if path.is_dir():
            files.extend(sorted(path.rglob('*.eml')))
        elif path.is_file():
            files.append(path)
        else:
            raise ReadError(f'No such file or directory: {path}')

    sources = []
    for file in files:
        text = file.read_bytes().decode('utf-8', errors='replace')
        sent = header_date(email.message_from_string(text, policy=policy.default))
        if since is None or sent is None or sent >= since:
            sources.append(Source(text))

    return sources, f'{len(sources)} .eml file(s) read'


# ---------------------------------------------------------------------------------------------------------------------
# The workbook
# ---------------------------------------------------------------------------------------------------------------------

LABELS = {
    'en': {
        'by_address': 'By address', 'details': 'Details', 'unrecognized': 'Unrecognized',
        'address': 'Address', 'domain': 'Domain', 'failures': 'Failures', 'codes': 'Codes received',
        'errors': 'Errors', 'first': 'First failure', 'last': 'Last failure', 'subjects': 'Subjects',
        'date': 'Date', 'subject': 'Subject', 'expected': 'Expected code', 'received': 'Code received',
        'status': 'Status', 'error': 'Error', 'reported_by': 'Reported by', 'sender': 'From',
        'no_reply': 'no reply', 'date_format': 'yyyy-mm-dd hh:mm', 'file': 'bounce-report',
    },
    'fr': {
        'by_address': 'Par adresse', 'details': 'Détail', 'unrecognized': 'Non reconnus',
        'address': 'Adresse', 'domain': 'Domaine', 'failures': 'Échecs', 'codes': 'Codes reçus',
        'errors': 'Erreurs', 'first': 'Premier échec', 'last': 'Dernier échec', 'subjects': 'Sujets',
        'date': 'Date', 'subject': 'Sujet', 'expected': 'Code attendu', 'received': 'Code reçu',
        'status': 'Statut', 'error': 'Erreur', 'reported_by': 'Signalé par', 'sender': 'Expéditeur',
        'no_reply': 'aucune réponse', 'date_format': 'dd/mm/yyyy hh:mm', 'file': 'erreurs-envoi',
    },
}


@dataclass(frozen=True)
class Formula:
    """A formula with the value it computes now, so that a viewer which does not calculate still shows it."""

    expression: str
    cached: int | float | dt.datetime | None


@dataclass(frozen=True)
class Sheet:
    name: str
    headers: list[str]
    rows: list[list[object]]
    date_columns: frozenset[int] = frozenset()


def report_sheets(failures: list[Failure], unrecognized: list[Unrecognized], labels: dict[str, str]) -> list[Sheet]:
    def received(failure: Failure) -> str:
        return labels['no_reply'] if failure.received is None else failure.received

    def code(failure: Failure) -> str:
        return ' '.join(part for part in (received(failure), failure.status) if part)

    def unique(values) -> str:
        return ' | '.join(dict.fromkeys(value for value in values if value))

    ordered = sorted(failures, key=lambda f: (f.when or dt.datetime.min, f.address.lower()))
    details = Sheet(
        labels['details'],
        [labels[key] for key in
         ('date', 'address', 'domain', 'subject', 'expected', 'received', 'status', 'error', 'reported_by')],
        [[f.when, f.address, f.domain, f.subject, f.expected, received(f), f.status, f.error, f.reported_by]
         for f in ordered],
        frozenset({0}),
    )

    groups: dict[str, list[Failure]] = {}
    for failure in ordered:
        groups.setdefault(failure.address.lower(), []).append(failure)

    # The counts and dates are formulas over the details sheet: delete a row there and this sheet follows. COUNTIF and
    # MINIFS ignore case, as the grouping does.
    target = "'" + labels['details'].replace("'", "''") + "'"
    by_address = []
    for row, group in enumerate(sorted(groups.values(), key=lambda g: (-len(g), g[0].address.lower())), start=2):
        dates = [f.when for f in group if f.when]
        by_address.append([
            group[0].address,
            group[0].domain,
            Formula(f'COUNTIF({target}!$B:$B,A{row})', len(group)),
            unique(code(f) for f in group),
            unique(f.error for f in group),
            Formula(f'_xlfn.MINIFS({target}!$A:$A,{target}!$B:$B,A{row})', min(dates) if dates else None),
            Formula(f'_xlfn.MAXIFS({target}!$A:$A,{target}!$B:$B,A{row})', max(dates) if dates else None),
            unique(f.subject for f in group),
        ])

    sheets = [
        Sheet(
            labels['by_address'],
            [labels[key] for key in ('address', 'domain', 'failures', 'codes', 'errors', 'first', 'last', 'subjects')],
            by_address,
            frozenset({5, 6}),
        ),
        details,
    ]
    if unrecognized:
        sheets.append(Sheet(
            labels['unrecognized'],
            [labels['date'], labels['sender'], labels['subject']],
            [[u.when, u.sender, u.subject] for u in sorted(unrecognized, key=lambda u: u.when or dt.datetime.min)],
            frozenset({0}),
        ))

    return sheets


MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PACKAGE_REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'
STYLE_HEADER, STYLE_DATE = 1, 2
EXCEL_EPOCH = dt.datetime(1899, 12, 30)
ILLEGAL_XML = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f￾￿]')
MAX_CELL_TEXT = 32767


def write_xlsx(path: Path, sheets: list[Sheet], date_format: str) -> None:
    strings: dict[str, int] = {}

    def shared(text: str) -> int:
        text = ILLEGAL_XML.sub('', text)[:MAX_CELL_TEXT]
        return strings.setdefault(text, len(strings))

    def number(value: int | float | dt.datetime) -> str:
        if isinstance(value, dt.datetime):
            value = (value - EXCEL_EPOCH).total_seconds() / 86400
        return repr(value)

    def cell(ref: str, value: object, style: int) -> str:
        style_attr = f' s="{style}"' if style else ''
        if isinstance(value, Formula):
            cached = f'<v>{number(value.cached)}</v>' if value.cached is not None else ''
            return f'<c r="{ref}"{style_attr}><f>{escape(value.expression)}</f>{cached}</c>'
        if value is None or value == '':
            return ''
        if isinstance(value, (int, float, dt.datetime)) and not isinstance(value, bool):
            return f'<c r="{ref}"{style_attr}><v>{number(value)}</v></c>'
        return f'<c r="{ref}" t="s"{style_attr}><v>{shared(str(value))}</v></c>'

    def worksheet(sheet: Sheet, selected: bool) -> str:
        last = f'{column(len(sheet.headers))}{len(sheet.rows) + 1}'
        widths = []
        for index, header in enumerate(sheet.headers):
            longest = max([len(header)] + [16 if index in sheet.date_columns else len(display(row[index]))
                                           for row in sheet.rows])
            widths.append(min(max(longest + 2, 10), 60))

        rows = ['<row r="1">' + ''.join(cell(f'{column(i + 1)}1', h, STYLE_HEADER)
                                        for i, h in enumerate(sheet.headers)) + '</row>']
        for number_, values in enumerate(sheet.rows, start=2):
            rows.append(f'<row r="{number_}">' + ''.join(
                cell(f'{column(i + 1)}{number_}', v, STYLE_DATE if i in sheet.date_columns else 0)
                for i, v in enumerate(values)) + '</row>')

        tab_selected = ' tabSelected="1"' if selected else ''
        return (
            f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            f'<worksheet xmlns="{MAIN_NS}" xmlns:r="{REL_NS}">'
            f'<dimension ref="A1:{last}"/>'
            f'<sheetViews><sheetView workbookViewId="0"{tab_selected}>'
            f'<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
            f'<selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>'
            f'<cols>' + ''.join(f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>'
                                for i, w in enumerate(widths, start=1)) + '</cols>'
            f'<sheetData>{"".join(rows)}</sheetData>'
            f'<autoFilter ref="A1:{last}"/>'
            f'</worksheet>'
        )

    parts = {f'xl/worksheets/sheet{i}.xml': worksheet(s, i == 1) for i, s in enumerate(sheets, start=1)}

    def sheet_ref(sheet: Sheet) -> str:
        return "'" + sheet.name.replace("'", "''") + "'!$A$1:$" + column(len(sheet.headers)) + f'${len(sheet.rows) + 1}'

    parts['xl/workbook.xml'] = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        f'<workbook xmlns="{MAIN_NS}" xmlns:r="{REL_NS}">'
        f'<bookViews><workbookView activeTab="0"/></bookViews><sheets>'
        + ''.join(f'<sheet name={quoteattr(s.name)} sheetId="{i}" r:id="rId{i}"/>' for i, s in enumerate(sheets, 1))
        + '</sheets><definedNames>'
        + ''.join(f'<definedName name="_xlnm._FilterDatabase" localSheetId="{i}" hidden="1">{escape(sheet_ref(s))}'
                  f'</definedName>' for i, s in enumerate(sheets))
        + '</definedNames><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>'
    )
    parts['xl/_rels/workbook.xml.rels'] = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="{PACKAGE_REL_NS}">'
        + ''.join(f'<Relationship Id="rId{i}" Type="{REL_NS}/worksheet" Target="worksheets/sheet{i}.xml"/>'
                  for i in range(1, len(sheets) + 1))
        + f'<Relationship Id="rId{len(sheets) + 1}" Type="{REL_NS}/styles" Target="styles.xml"/>'
        + f'<Relationship Id="rId{len(sheets) + 2}" Type="{REL_NS}/sharedStrings" Target="sharedStrings.xml"/>'
        + '</Relationships>'
    )
    parts['xl/styles.xml'] = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<styleSheet xmlns="{MAIN_NS}">'
        f'<numFmts count="1"><numFmt numFmtId="164" formatCode={quoteattr(date_format)}/></numFmts>'
        '<fonts count="2">'
        '<font><sz val="10"/><name val="Arial"/><family val="2"/></font>'
        '<font><b/><sz val="10"/><name val="Arial"/><family val="2"/></font>'
        '</fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFD9E2F3"/><bgColor indexed="64"/></patternFill></fill>'
        '</fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="3">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
        '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
        '</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>'
    )
    # Written last: the worksheets above fill the table of shared strings.
    parts['xl/sharedStrings.xml'] = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        f'<sst xmlns="{MAIN_NS}" count="{len(strings)}" uniqueCount="{len(strings)}">'
        + ''.join(f'<si><t xml:space="preserve">{escape(text)}</t></si>' for text in strings)
        + '</sst>'
    )
    parts['_rels/.rels'] = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="{PACKAGE_REL_NS}">'
        f'<Relationship Id="rId1" Type="{REL_NS}/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    )
    sheet_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml'
    parts['[Content_Types].xml'] = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f'<Override PartName="/xl/workbook.xml" ContentType="{sheet_type}.sheet.main+xml"/>'
        + ''.join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="{sheet_type}.worksheet+xml"/>'
                  for i in range(1, len(sheets) + 1))
        + f'<Override PartName="/xl/styles.xml" ContentType="{sheet_type}.styles+xml"/>'
        f'<Override PartName="/xl/sharedStrings.xml" ContentType="{sheet_type}.sharedStrings+xml"/>'
        '</Types>'
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in ('[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels',
                     'xl/styles.xml', 'xl/sharedStrings.xml', *(f'xl/worksheets/sheet{i}.xml'
                                                                  for i in range(1, len(sheets) + 1))):
            archive.writestr(name, parts[name])


def column(index: int) -> str:
    """1 -> A, 27 -> AA."""
    letters = ''
    while index:
        index, remainder = divmod(index - 1, 26)
        letters = chr(65 + remainder) + letters
    return letters


def display(value: object) -> str:
    if isinstance(value, Formula):
        return display(value.cached)
    return '' if value is None else str(value)


# ---------------------------------------------------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------------------------------------------------

def default_language() -> str:
    for variable in ('LC_ALL', 'LC_MESSAGES', 'LANG'):
        value = os.environ.get(variable)
        if value:
            return 'fr' if value.lower().startswith('fr') else 'en'
    return 'en'


def parse_since(value: str) -> dt.datetime:
    try:
        return local(dt.datetime.fromisoformat(value))
    except ValueError:
        raise argparse.ArgumentTypeError(f'not an ISO date: {value} (expected 2026-11-01 or 2026-11-01T08:00)')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description='Turn the send failures reported in a Mail.app mailbox into an Excel workbook.',
    )
    origin = parser.add_mutually_exclusive_group(required=True)
    origin.add_argument('--mailbox', help='name of the Mail mailbox to read, i.e. NO_REPLY (case does not matter)')
    origin.add_argument('--eml', nargs='+', metavar='PATH', help='.eml files, or folders of them, instead of Mail')
    parser.add_argument('--account', help='Mail account holding the mailbox, when several have one of that name')
    parser.add_argument('--since', type=parse_since, help='only the messages received from this date or time on')
    parser.add_argument('--output', type=Path, help='the .xlsx to write (default: on the Desktop, dated)')
    parser.add_argument('--lang', choices=sorted(LABELS), default=default_language(),
                        help='language of the workbook (default: from the locale)')
    args = parser.parse_args(argv)

    try:
        if args.mailbox:
            sources, origin_line = read_mailbox(args.mailbox, args.account, args.since)
        else:
            sources, origin_line = read_eml(args.eml, args.since)
    except ReadError as error:
        print(f'bounce-report: {error}', file=sys.stderr)
        return 1

    labels = LABELS[args.lang]
    failures, unrecognized = analyse(sources)
    slug = re.sub(r'[^\w.-]+', '-', args.mailbox or 'eml').strip('-').lower()
    output = args.output or Path.home() / 'Desktop' / f'{labels["file"]}-{slug}-{dt.date.today().isoformat()}.xlsx'
    write_xlsx(output, report_sheets(failures, unrecognized, labels), labels['date_format'])

    codes: dict[str, int] = {}
    for failure in failures:
        key = ' '.join(part for part in ('no reply' if failure.received is None else failure.received or 'no code',
                                         failure.status) if part)
        codes[key] = codes.get(key, 0) + 1

    print(origin_line)
    print(f'{len(failures)} failure(s), {len({f.address.lower() for f in failures})} address(es), '
          f'{len(unrecognized)} unrecognized message(s)')
    for key, count in sorted(codes.items(), key=lambda item: -item[1]):
        print(f'  {count:>5}  {key}')
    print(f'Written: {output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
