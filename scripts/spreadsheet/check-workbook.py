"""Read-only checks of exported formulas, cached native calculations and charts."""
import json
import hashlib
import math
import argparse
import posixpath
import re
from urllib.parse import urlsplit
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
def require(condition, message):
    if not condition:
        raise AssertionError(message)


reference = json.loads(args.reference.read_text())
rows = json.loads(args.map.read_text())
portfolio = json.loads(reference['portfolio_reference_json'])
require(len(portfolio['treasury_maturity_weights']) == 120, 'validation failed')
if args.portfolio_reference:
    require(args.portfolio_reference.read_bytes() == reference['portfolio_reference_json'].encode(), 'portfolio reference bytes differ from native source')
    require(json.loads(args.portfolio_reference.read_text()) == portfolio, 'portfolio reference differs from native source')
    require(hashlib.sha256(args.portfolio_reference.read_bytes()).hexdigest() == reference['portfolio_reference_sha256'], 'portfolio reference hash mismatch')


def flatten_state(state):
    fields = {}
    shapes = {'price_history': 5, 'treasury_cohorts_pct_initial_gdp': 120,
              'sterilized_treasury_cohorts_pct_initial_gdp': 120, 'bill_cohorts_pct_initial_gdp': 4}
    for key, value in state.items():
        if isinstance(value, list):
            require(key in shapes and len(value) == shapes[key], f'Native array schema mismatch: {key}')
            fields.update({f'price_h{i}' if key == 'price_history' else f'{key}_{i}': item
                           for i, item in enumerate(value)})
        else:
            fields[key] = value
    require(all(key in state for key in shapes), 'Native state lacks required arrays')
    return fields


def column(n):
    label = ''
    while n:
        n, remainder = divmod(n - 1, 26)
        label = chr(65 + remainder) + label
    return label


def coordinates(address):
    match = re.fullmatch(r'([A-Z]+)([1-9]\d*)', address.replace('$', ''))
    require(match is not None, f'Invalid shared formula range: {address}')
    col = 0
    for letter in match[1]:
        col = col * 26 + ord(letter) - ord('A') + 1
    return col, int(match[2])


def has_formula(cell, shared):
    formula = cell.find('s:f', NS)
    if formula is None:
        return False
    if (formula.text or '').strip():
        return True
    if formula.get('t') != 'shared' or formula.get('si') not in shared:
        return False
    anchor = shared[formula.get('si')]
    bounds = anchor.get('ref', '').split(':')
    if len(bounds) != 2:
        return False
    first, last = map(coordinates, bounds)
    point = coordinates(cell.attrib['r'])
    return all(low <= value <= high for low, value, high in zip(first, point, last))


# Fixed builder dialect: literals, arithmetic, local A1 references and these pure functions.
SAFE_FORMULA_TOKENS = re.compile(
    r'"(?:[^"]|"")*"'
    r"|(?:'(?:Policy Lab|Policy|Assumptions|Economy|Shocks)'|Policy|Assumptions|Economy|Shocks)!"
    r'|(?:ABS|AND|CHOOSE|COUNT|COUNTA|EXP|IF|IFERROR|INDEX|INT|ISBLANK|ISLOGICAL|ISNUMBER|LARGE|LN|MAX|MIN|NA|NOT|OR|POWER|ROUND|SIGN|SUM|TANH)\s*(?=\()'
    r'|(?:TRUE|FALSE)(?![A-Z0-9_])|\$?[A-Z]{1,3}\$?[1-9][0-9]*'
    r'|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:E[+-]?[0-9]+)?|[\s+*/^&=<>():,-]',
    re.IGNORECASE | re.ASCII,
)


def validate_formulas(part, path):
    tags = {'{' + NS['s'] + '}' + name for name in ('f', 'formula', 'formula1', 'formula2', 'definedName')}
    tags.add('{' + NS['c'] + '}f')
    for node in part.iter():
        if node.tag in tags:
            require(not SAFE_FORMULA_TOKENS.sub('', node.text or ''),
                    ('unsupported workbook formula', path, node.text))


for filename in args.workbooks:
    with zipfile.ZipFile(filename) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), ('duplicate package part', filename))
        content_types = ET.fromstring(archive.read('[Content_Types].xml'))
        forbidden = ('vba', 'macroenabled', 'macrosheet', 'activex', 'oleobject', 'externallink', 'connections', 'querytable')
        for part in content_types:
            require(not any(token in part.get('ContentType', '').lower() for token in forbidden),
                    ('active content type', part.attrib))
        relationship_parts = {name for name in names if name.endswith('.rels')}
        relationship_parts.update(part.get('PartName', '').lstrip('/') for part in content_types
                                  if part.get('ContentType') == 'application/vnd.openxmlformats-package.relationships+xml' and part.get('PartName'))
        for path in relationship_parts:
            for relationship in ET.fromstring(archive.read(path)):
                target = relationship.get('Target', '')
                require(relationship.get('TargetMode', '').lower() != 'external'
                        and not urlsplit(target).scheme and not target.startswith('//')
                        and not any(token in relationship.get('Type', '').lower() for token in forbidden),
                        ('active content relationship', path, relationship.attrib))
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        validate_formulas(workbook, 'xl/workbook.xml')
        relationships = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        targets = {r.attrib['Id']: r.attrib['Target'] for r in relationships}
        sheets = {}
        for sheet in workbook.find('s:sheets', NS):
            target = targets[sheet.attrib['{' + NS['r'] + '}id']]
            sheets[sheet.attrib['name']] = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
        if args.campaign_reference:
            campaign = json.loads(args.campaign_reference.read_text())
            require(campaign['scenario']['id'] == 'mixed_crises', 'Campaign reference must be Recurring crises')
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
            require(expected_note in values, 'stale or missing campaign explanation')
        cells = {c.attrib['r']: c for c in ET.fromstring(archive.read(sheets['Economy'])).findall('.//s:c', NS)}
        shared = {formula.get('si'): formula for cell in cells.values()
                  if (formula := cell.find('s:f', NS)) is not None
                  and formula.get('t') == 'shared' and (formula.text or '').strip()}
        worst = 0
        for quarter, state in enumerate([reference['initial_state']] + [r['state'] for r in reference['quarters']]):
            for field, value in flatten_state(state).items():
                require(field in rows, f'Full-state parity unmapped native field: {field}')
                cell = cells[f'{column(quarter + 4)}{rows[field]}']
                # Cold starts calculate all state fields except the authored quarter literal.
                if quarter > 0 or (state['quarter_index'] == 0 and field != 'quarter_index'):
                    require(has_formula(cell, shared), f'Full-state parity missing formula: {field} at {cell.attrib["r"]}')
                require(cell.find('s:v', NS) is not None, f'Full-state parity missing cache: {field}')
                actual = float(cell.find('s:v', NS).text)
                if isinstance(value, bool):
                    require(cell.attrib.get('t') == 'b' and actual in (0, 1), f'Full-state parity boolean type: {field}')
                error = abs(actual - float(value))
                worst = max(worst, error)
                require(math.isfinite(actual) and math.isfinite(float(value)) and error < 1e-7, ('full-state parity', filename, quarter, field, actual, value))
        errors = []
        for name, path in sheets.items():
            part = ET.fromstring(archive.read(path))
            validate_formulas(part, path)
            errors.extend((name, c.attrib['r'], c.find('s:v', NS).text)
                          for c in part.findall('.//s:c', NS)
                          if c.attrib.get('t') == 'e')
        require(not errors, errors[:10])
        charts = [item.attrib['PartName'].lstrip('/') for item in content_types
                  if item.attrib.get('ContentType') == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml']
        require(len(charts) == 4, 'validation failed')
        expected_series = {'Inflation and expectations (%)': ['C', 'D', 'E'], 'Unemployment (%)': ['F', 'G'],
                           'Policy and long yield (%)': ['H', 'I'], 'Model confidence scores (0–100)': ['J', 'K']}
        palettes = []
        titles = []
        for path in charts:
            chart = ET.fromstring(archive.read(path))
            validate_formulas(chart, path)
            title = ''.join(node.text or '' for node in chart.findall('c:chart/c:title//a:t', NS))
            titles.append(title)
            formats = chart.findall('.//c:valAx/c:numFmt', NS)
            require(formats and all(f.attrib.get('formatCode') == '0.00'
                                   and f.attrib.get('sourceLinked') in ('0', 'false') for f in formats), (path, title, 'ambiguous value-axis precision'))
            series = chart.findall('.//c:ser', NS)
            require(title in expected_series and len(series) == len(expected_series[title]), (path, title, 'missing chart series'))
            palettes.append([s.find('c:spPr/a:ln/a:solidFill/a:srgbClr', NS).attrib['val'] for s in series])
            for item, col in zip(series, expected_series[title]):
                category = item.find('c:cat/c:strRef/c:f', NS)
                if category is None:
                    category = item.find('c:cat/c:numRef/c:f', NS)
                require(category is not None and category.text == "'Policy Lab'!$B$58:$B$106",
                        (path, title, 'chart category binding'))
                value = item.find('c:val/c:numRef/c:f', NS)
                require(value is not None and value.text == f"'Policy Lab'!${col}$58:${col}$106",
                        (path, title, 'chart value binding'))
        require(set(titles) == set(expected_series), 'Missing or duplicated chart')
        require(not any('vbaproject' in p.lower() or 'externallinks' in p.lower() for p in archive.namelist()), 'active content filename')
        receipt = dict(file=str(filename), max_absolute_error=worst, formula_errors=len(errors), charts=len(charts), colors=palettes)
        print('PASS', json.dumps(receipt))
