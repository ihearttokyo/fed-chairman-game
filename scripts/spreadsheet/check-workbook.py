"""Read-only checks of exported formulas, cached native calculations and charts."""
import json
import hashlib
import math
import argparse
import posixpath
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('workbooks', nargs='+', type=Path)
parser.add_argument('--reference', required=True, type=Path)
parser.add_argument('--map', required=True, type=Path)
parser.add_argument('--campaign-reference', type=Path, help='Validate saved campaign explanation against its native export')
parser.add_argument('--portfolio-reference', type=Path, help='Resident source copy bound by the native export hash')
args = parser.parse_args()
NS = {
    's': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'c': 'http://schemas.openxmlformats.org/drawingml/2006/chart',
    'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
}
reference = json.loads(args.reference.read_text())
rows = json.loads(args.map.read_text())
portfolio = json.loads(reference['portfolio_reference_json'])
assert len(portfolio['treasury_maturity_weights']) == 120
if args.portfolio_reference:
    assert args.portfolio_reference.read_bytes() == reference['portfolio_reference_json'].encode(), 'portfolio reference bytes differ from native source'
    assert json.loads(args.portfolio_reference.read_text()) == portfolio, 'portfolio reference differs from native source'
    assert hashlib.sha256(args.portfolio_reference.read_bytes()).hexdigest() == reference['portfolio_reference_sha256'], 'portfolio reference hash mismatch'


def flatten_state(state):
    fields = {}
    shapes = {'price_history': 5, 'treasury_cohorts_pct_initial_gdp': 120,
              'sterilized_treasury_cohorts_pct_initial_gdp': 120, 'bill_cohorts_pct_initial_gdp': 4}
    for key, value in state.items():
        if isinstance(value, list):
            assert key in shapes and len(value) == shapes[key], f'Native array schema mismatch: {key}'
            fields.update({f'price_h{i}' if key == 'price_history' else f'{key}_{i}': item
                           for i, item in enumerate(value)})
        else:
            fields[key] = value
    assert all(key in state for key in shapes), 'Native state lacks required arrays'
    return fields


def column(n):
    label = ''
    while n:
        n, remainder = divmod(n - 1, 26)
        label = chr(65 + remainder) + label
    return label


for filename in args.workbooks:
    with zipfile.ZipFile(filename) as archive:
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        relationships = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        targets = {r.attrib['Id']: r.attrib['Target'] for r in relationships}
        sheets = {}
        for sheet in workbook.find('s:sheets', NS):
            target = targets[sheet.attrib['{' + NS['r'] + '}id']]
            sheets[sheet.attrib['name']] = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
        if args.campaign_reference:
            campaign = json.loads(args.campaign_reference.read_text())
            assert campaign['scenario']['id'] == 'mixed_crises', 'Campaign reference must be Recurring crises'
            expected_note = 'Recurring crises: ' + campaign['scenario']['description']
            shared = [ ''.join(t.text or '' for t in item.findall('.//s:t', NS))
                       for item in ET.fromstring(archive.read('xl/sharedStrings.xml')) ] if 'xl/sharedStrings.xml' in archive.namelist() else []
            values = []
            for cell in ET.fromstring(archive.read(sheets['Shocks'])).findall('.//s:c', NS):
                if cell.attrib.get('t') == 's':
                    values.append(shared[int(cell.find('s:v', NS).text)])
                elif cell.attrib.get('t') == 'str':
                    values.append(cell.find('s:v', NS).text or '')
                else:
                    values.append(''.join(t.text or '' for t in cell.findall('.//s:t', NS)))
            assert expected_note in values, 'stale or missing campaign explanation'
        cells = {c.attrib['r']: c for c in ET.fromstring(archive.read(sheets['Economy'])).findall('.//s:c', NS)}
        worst = 0
        for quarter, state in enumerate([reference['initial_state']] + [r['state'] for r in reference['quarters']]):
            for field, value in flatten_state(state).items():
                assert field in rows, f'Full-state parity unmapped native field: {field}'
                cell = cells[f'{column(quarter + 4)}{rows[field]}']
                assert cell.find('s:v', NS) is not None, f'Full-state parity missing cache: {field}'
                actual = float(cell.find('s:v', NS).text)
                if isinstance(value, bool):
                    assert cell.attrib.get('t') == 'b' and actual in (0, 1), f'Full-state parity boolean type: {field}'
                error = abs(actual - float(value))
                worst = max(worst, error)
                assert math.isfinite(actual) and math.isfinite(float(value)) and error < 1e-7, ('full-state parity', filename, quarter, field, actual, value)
        errors = []
        for name, path in sheets.items():
            errors.extend((name, c.attrib['r'], c.find('s:v', NS).text)
                          for c in ET.fromstring(archive.read(path)).findall('.//s:c', NS)
                          if c.attrib.get('t') == 'e')
        assert not errors, errors[:10]
        charts = [item.attrib['PartName'].lstrip('/') for item in ET.fromstring(archive.read('[Content_Types].xml'))
                  if item.attrib.get('ContentType') == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml']
        assert len(charts) == 4
        expected_series = {'Inflation and expectations (%)': 3, 'Unemployment (%)': 2,
                           'Policy and long yield (%)': 2, 'Model confidence scores (0–100)': 2}
        palettes = []
        titles = []
        for path in charts:
            chart = ET.fromstring(archive.read(path))
            title = ''.join(node.text or '' for node in chart.findall('c:chart/c:title//a:t', NS))
            titles.append(title)
            formats = chart.findall('.//c:valAx/c:numFmt', NS)
            assert formats and all(f.attrib.get('formatCode') == '0.00'
                                   and f.attrib.get('sourceLinked') in ('0', 'false') for f in formats), (path, title, 'ambiguous value-axis precision')
            series = chart.findall('.//c:ser', NS)
            assert len(series) == expected_series.get(title), (path, title, 'missing chart series')
            palettes.append([s.find('c:spPr/a:ln/a:solidFill/a:srgbClr', NS).attrib['val'] for s in series])
            assert all(s.find('.//c:numRef/c:f', NS) is not None for s in series)
        assert set(titles) == set(expected_series), 'Missing or duplicated chart'
        assert not any('vbaProject' in p or 'externalLinks' in p for p in archive.namelist())
        receipt = dict(file=str(filename), max_absolute_error=worst, formula_errors=len(errors), charts=len(charts), colors=palettes)
        print('PASS', json.dumps(receipt))
