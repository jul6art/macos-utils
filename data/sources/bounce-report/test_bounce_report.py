"""Tests of bounce_report.py: python3 -m unittest discover data/sources/bounce-report"""

import datetime as dt
import html
import sys
import tempfile
import unittest
import zipfile
from email.message import EmailMessage
from pathlib import Path
from xml.etree import ElementTree

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bounce_report as br  # noqa: E402

NS = {'m': br.MAIN_NS}


def monolog_record(level: str, message: str, time: str) -> str:
    """One record as Monolog's HtmlFormatter writes it, nested context table included."""
    row = ('<tr style="padding: 4px;text-align: left;">\n<th style="vertical-align: top;background: #ccc;color: #000" '
           'width="100">{}:</th>\n<td style="padding: 4px;text-align: left;vertical-align: top;background: #eee;'
           'color: #000"><pre>{}</pre></td>\n</tr>')
    context = '<table cellspacing="1" width="100%">' + row.format('exception', '{&quot;code&quot;: 0}') + '</table>'
    return (
        f'<h1 style="background: #DC3545;color: #ffffff;padding: 5px;" class="monolog-output">{level}</h1>'
        '<table cellspacing="1" width="100%" class="monolog-output">'
        + row.format('Message', html.escape(message))
        + row.format('Time', time.replace('+', '&#43;'))
        + row.format('Channel', 'app')
        + '<tr style="padding: 4px;text-align: left;">\n<th>Context:</th>\n<td>' + context + '</td>\n</tr>'
        + '</table>'
    )


def alert(body: str, subtype: str = 'html', subject: str = 'prod | Shop error') -> br.Source:
    message = EmailMessage()
    message['From'] = 'no_reply@example.com'
    message['To'] = 'ops@example.com'
    message['Subject'] = subject
    message['Date'] = 'Mon, 23 Nov 2026 08:46:31 +0100'
    message.set_content(body, subtype=subtype)
    return br.Source(message.as_string())


EMPTY_CODE = 'Expected response code "250" but got empty code.'
REJECTED = ('Expected response code "250/251/252" but got code "550", with message '
            '"550 5.1.1 <ghost@example.org>: Recipient address rejected: User unknown".')

DSN = '''From: Mail Delivery System <MAILER-DAEMON@mx.example.net>
To: no_reply@example.com
Subject: Undelivered Mail Returned to Sender
Date: Sat, 21 Nov 2026 10:00:00 +0000
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status; boundary="B"

--B
Content-Type: text/plain

The mail could not be delivered.

--B
Content-Type: message/delivery-status

Reporting-MTA: dns; mx.example.net
Arrival-Date: Sat, 21 Nov 2026 09:59:58 +0000

Final-Recipient: rfc822; ghost@example.org
Original-Recipient: rfc822;ghost@example.org
Action: failed
Status: 5.1.1
Diagnostic-Code: smtp; 550 5.1.1 <ghost@example.org>: Recipient address
    rejected: User unknown

Final-Recipient: rfc822; fine@example.org
Action: delivered
Status: 2.0.0

--B
Content-Type: text/rfc822-headers

From: shop@example.com
To: ghost@example.org
Subject: Your invoice

--B--
'''


class SmtpCodesTest(unittest.TestCase):

    def test_an_empty_reply_has_no_received_code(self):
        self.assertEqual(('250', None, ''), br.smtp_codes(EMPTY_CODE))

    def test_a_rejection_gives_its_code_and_enhanced_status(self):
        self.assertEqual(('250/251/252', '550', '5.1.1'), br.smtp_codes(REJECTED))

    def test_an_error_without_smtp_reply_has_no_code(self):
        self.assertEqual(('', '', ''), br.smtp_codes('Connection to "smtp.example.net:25" has been closed unexpectedly.'))


class AnalyseTest(unittest.TestCase):

    def test_a_monolog_html_alert(self):
        source = alert(monolog_record(
            'CRITICAL',
            f'Error sending email notification "Shop: new invoice" to jane@example.org with message {EMPTY_CODE}',
            '2026-11-23T08:46:31.657385+01:00',
        ))

        failures, unrecognized = br.analyse([source])

        self.assertEqual([], unrecognized)
        self.assertEqual(1, len(failures))
        failure = failures[0]
        self.assertEqual('jane@example.org', failure.address)
        self.assertEqual('example.org', failure.domain)
        self.assertEqual('Shop: new invoice', failure.subject)
        self.assertEqual(('250', None, ''), (failure.expected, failure.received, failure.status))
        self.assertEqual(EMPTY_CODE, failure.error)
        self.assertEqual('prod | Shop error', failure.reported_by)
        self.assertEqual(br.local(dt.datetime(2026, 11, 23, 7, 46, 31, 657385, dt.timezone.utc)), failure.when)

    def test_a_buffered_alert_gives_one_failure_per_mail_record(self):
        source = alert(
            monolog_record('CRITICAL', f'Error sending email notification "A" to a@example.org with message {REJECTED}',
                           '2026-11-21T11:04:23.000000+01:00')
            + monolog_record('CRITICAL', 'Database is down', '2026-11-21T11:05:00.000000+01:00')
            + monolog_record('CRITICAL', f'Error sending email notification to b@example.org with message {EMPTY_CODE}',
                             '2026-11-21T11:06:00.000000+01:00')
        )

        failures, unrecognized = br.analyse([source])

        self.assertEqual([], unrecognized)
        self.assertEqual(['a@example.org', 'b@example.org'], [f.address for f in failures])
        self.assertEqual(('550', '5.1.1'), (failures[0].received, failures[0].status))
        self.assertEqual('', failures[1].subject)

    def test_a_queued_mail_the_worker_gave_up_on_names_each_recipient(self):
        source = alert(monolog_record(
            'CRITICAL',
            f'Mail "Shop: new invoice" to jane@example.org, bob@example.org not sent after 4 attempt(s): {REJECTED}',
            '2026-11-24T09:00:00.000000+01:00',
        ))

        failures, unrecognized = br.analyse([source])

        self.assertEqual([], unrecognized)
        self.assertEqual(['jane@example.org', 'bob@example.org'], [f.address for f in failures])
        self.assertEqual({'Shop: new invoice'}, {f.subject for f in failures})
        self.assertEqual({('550', '5.1.1')}, {(f.received, f.status) for f in failures})

    def test_a_monolog_plain_text_alert(self):
        source = alert(
            '[2026-11-21T11:04:23.123456+01:00] app.CRITICAL: Error sending email notification "Invoice" to '
            'jane@example.org with message Connection to "smtp.example.net:25" has been closed unexpectedly. '
            '{"exception":"[object] (TransportException(code: 0))"} []\n',
            subtype='plain',
        )

        failures, _ = br.analyse([source])

        self.assertEqual(1, len(failures))
        self.assertEqual('Connection to "smtp.example.net:25" has been closed unexpectedly.', failures[0].error)
        self.assertEqual('', failures[0].received)

    def test_a_delivery_status_notification(self):
        failures, unrecognized = br.analyse([br.Source(DSN)])

        self.assertEqual([], unrecognized)
        self.assertEqual(1, len(failures))
        failure = failures[0]
        self.assertEqual('ghost@example.org', failure.address)
        self.assertEqual('Your invoice', failure.subject)
        self.assertEqual(('', '550', '5.1.1'), (failure.expected, failure.received, failure.status))
        self.assertEqual('550 5.1.1 <ghost@example.org>: Recipient address rejected: User unknown', failure.error)
        self.assertEqual(br.local(dt.datetime(2026, 11, 21, 9, 59, 58, tzinfo=dt.timezone.utc)), failure.when)

    def test_a_message_reporting_no_failure_is_listed_not_dropped(self):
        failures, unrecognized = br.analyse([alert('Hello, the backup ran.', subtype='plain', subject='Backup')])

        self.assertEqual([], failures)
        self.assertEqual(['Backup'], [u.subject for u in unrecognized])


class WorkbookTest(unittest.TestCase):

    def failure(self, address: str, day: int, received=None) -> br.Failure:
        return br.Failure(dt.datetime(2026, 11, day, 8, 0), address, 'Invoice', '250', received, '', 'error', 'alert')

    def write(self, failures, unrecognized=(), lang='fr'):
        labels = br.LABELS[lang]
        directory = tempfile.mkdtemp()
        path = Path(directory) / 'report.xlsx'
        br.write_xlsx(path, br.report_sheets(list(failures), list(unrecognized), labels), labels['date_format'])
        with zipfile.ZipFile(path) as archive:
            return {name: ElementTree.fromstring(archive.read(name)) for name in archive.namelist()}

    def strings(self, parts) -> list[str]:
        return [t.text or '' for t in parts['xl/sharedStrings.xml'].iterfind('m:si/m:t', NS)]

    def cell(self, parts, sheet: int, ref: str):
        return parts[f'xl/worksheets/sheet{sheet}.xml'].find(f".//m:c[@r='{ref}']", NS)

    def text(self, parts, sheet: int, ref: str) -> str:
        return self.strings(parts)[int(self.cell(parts, sheet, ref).find('m:v', NS).text)]

    def test_every_part_is_well_formed_and_declared(self):
        parts = self.write([self.failure('jane@example.org', 21)])

        types = parts['[Content_Types].xml']
        declared = {o.get('PartName') for o in types}
        for name in parts:
            if name.endswith('.xml') and name != '[Content_Types].xml':
                self.assertIn('/' + name, declared)
        sheets = parts['xl/workbook.xml'].iterfind('m:sheets/m:sheet', NS)
        self.assertEqual(['Par adresse', 'Détail'], [s.get('name') for s in sheets])

    def test_addresses_are_grouped_whatever_their_case_and_counted_by_formula(self):
        parts = self.write([
            self.failure('jane@example.org', 21),
            self.failure('Jane@Example.org', 22),
            self.failure('bob@example.org', 20, received='550'),
        ])

        self.assertEqual('jane@example.org', self.text(parts, 1, 'A2'))
        count = self.cell(parts, 1, 'C2')
        self.assertEqual("COUNTIF('Détail'!$B:$B,A2)", count.find('m:f', NS).text)
        self.assertEqual('2', count.find('m:v', NS).text)
        self.assertEqual('aucune réponse', self.text(parts, 1, 'D2'))
        self.assertEqual('bob@example.org', self.text(parts, 1, 'A3'))
        self.assertEqual('550', self.text(parts, 1, 'D3'))
        self.assertIsNone(self.cell(parts, 1, 'A4'))

    def test_dates_are_serial_numbers_with_a_date_style(self):
        parts = self.write([self.failure('jane@example.org', 21), self.failure('jane@example.org', 22)])

        first = self.cell(parts, 1, 'F2')
        self.assertTrue(first.find('m:f', NS).text.startswith("_xlfn.MINIFS('Détail'!$A:$A"))
        self.assertEqual(str(br.STYLE_DATE), first.get('s'))
        serial = float(first.find('m:v', NS).text)
        self.assertEqual(dt.datetime(2026, 11, 21, 8, 0), br.EXCEL_EPOCH + dt.timedelta(days=serial))
        self.assertEqual(str(br.STYLE_DATE), self.cell(parts, 2, 'A2').get('s'))
        number_format = parts['xl/styles.xml'].find('m:numFmts/m:numFmt', NS)
        self.assertEqual('dd/mm/yyyy hh:mm', number_format.get('formatCode'))

    def test_the_header_is_styled_frozen_and_filtered(self):
        parts = self.write([self.failure('jane@example.org', 21)])

        sheet = parts['xl/worksheets/sheet2.xml']
        self.assertEqual(str(br.STYLE_HEADER), self.cell(parts, 2, 'A1').get('s'))
        self.assertEqual('frozen', sheet.find('.//m:pane', NS).get('state'))
        self.assertEqual('A1:I2', sheet.find('m:autoFilter', NS).get('ref'))

    def test_unrecognized_messages_get_their_own_sheet(self):
        parts = self.write([], [br.Unrecognized(None, 'cron@example.com', 'Backup')], lang='en')

        sheets = parts['xl/workbook.xml'].iterfind('m:sheets/m:sheet', NS)
        self.assertEqual(['By address', 'Details', 'Unrecognized'], [s.get('name') for s in sheets])
        self.assertEqual('Backup', self.text(parts, 3, 'C2'))

    def test_control_characters_never_reach_the_xml(self):
        failure = br.Failure(None, 'jane@example.org', 'In\x0bvoice', '', '', '', 'bad\x00reply', 'alert')

        parts = self.write([failure])

        self.assertIn('Invoice', self.strings(parts))


class ColumnTest(unittest.TestCase):

    def test_letters(self):
        self.assertEqual(['A', 'Z', 'AA', 'AZ', 'BA'], [br.column(i) for i in (1, 26, 27, 52, 53)])


if __name__ == '__main__':
    unittest.main()
