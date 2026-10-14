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
    'xdr': 'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing',
    'p': 'http://schemas.openxmlformats.org/package/2006/relationships',
    'ct': 'http://schemas.openxmlformats.org/package/2006/content-types',
}
ASCII_LOWER = str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')


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


def unsigned_integer(value, message):
    require(isinstance(value, str) and re.fullmatch(r'\+?[0-9]+', value) is not None, message)
    number = int(value)
    require(number <= 4294967295, message)
    return number


def worksheet_cells(part, path):
    data = part.findall('s:sheetData', NS)
    require(len(data) == 1 and all(row.tag == '{' + NS['s'] + '}row' for row in data[0]), ('worksheet cell structure', path))
    direct = data[0].findall('s:row/s:c', NS)
    require(len(direct) == len(part.findall('.//s:c', NS)), ('worksheet cell structure', path, 'orphaned cell'))
    cells = {}
    row_ids = set()
    for row in data[0]:
        identity = unsigned_integer(row.get('r'), ('worksheet cell structure', path, 'row identity'))
        require(identity > 0 and identity not in row_ids, ('worksheet cell structure', path, 'duplicate row'))
        row_ids.add(identity)
        require(all(cell.tag == '{' + NS['s'] + '}c' for cell in row), ('worksheet cell structure', path, 'noncanonical cell'))
        for cell in row:
            address = cell.get('r', '')
            require(re.fullmatch(r'[A-Z]+[1-9][0-9]*', address) is not None
                    and coordinates(address)[1] == identity and address not in cells, ('worksheet cell structure', path, address))
            supported = {'{' + NS['s'] + '}' + tag for tag in ('f', 'v', 'is')}
            require(all(child.tag in supported for child in cell)
                    and all(len(cell.findall('s:' + tag, NS)) <= 1 for tag in ('f', 'v', 'is'))
                    and all(len(child) == 0 for child in cell if child.tag != '{' + NS['s'] + '}is'),
                    ('worksheet cell structure', path, address, 'unsupported or ambiguous formula/cache/string'))
            inline = cell.find('s:is', NS)
            require((inline is None or cell.get('t') == 'inlineStr')
                    and (cell.get('t') != 'inlineStr' or (inline is not None and len(cell) == 1)),
                    ('worksheet cell structure', path, address, 'declared string source'))
            cells[address] = cell
    return cells


def has_formula(cell, shared):
    formula = cell.find('s:f', NS)
    if formula is None:
        return False
    if formula.get('t') != 'shared':
        return bool((formula.text or '').strip())
    index = unsigned_integer(formula.get('si'), 'Full-state parity missing formula: shared formula group index')
    anchor = shared.get(index)
    if anchor is None:
        return False
    bounds = anchor.get('ref', '').split(':')
    if len(bounds) not in (1, 2) or not all(re.fullmatch(r'\$?[A-Z]+\$?[1-9][0-9]*', address) for address in bounds):
        return False
    first, last = coordinates(bounds[0]), coordinates(bounds[-1])
    point = coordinates(cell.attrib['r'])
    return all(low <= value <= high for low, value, high in zip(first, point, last))


def shared_formulas(cells):
    shared = {}
    members = []
    for cell in cells.values():
        formula = cell.find('s:f', NS)
        if formula is None or formula.get('t') != 'shared':
            continue
        members.append(cell)
        index = unsigned_integer(formula.get('si'), 'Full-state parity missing formula: shared formula group index')
        # A follower can carry ignored text; only ref identifies a master.
        if formula.get('ref') is not None:
            require((formula.text or '').strip() and index not in shared,
                    'Full-state parity missing formula: duplicate or empty shared formula group master')
            shared[index] = formula
    for cell in members:
        require(has_formula(cell, shared), 'Full-state parity missing formula: shared formula group range or master')
    rectangles = []
    for anchor in shared.values():
        bounds = anchor.get('ref').split(':')
        first, last = coordinates(bounds[0]), coordinates(bounds[-1])
        require(all(any(last[axis] < prior_first[axis] or prior_last[axis] < first[axis]
                        for axis in (0, 1)) for prior_first, prior_last in rectangles),
                'Full-state parity missing formula: overlapping shared formula group ranges')
        rectangles.append((first, last))
    return shared


def series_numbers(series, tag, path):
    values = []
    for item in series:
        nodes = item.findall('c:' + tag, NS)
        require(len(nodes) == 1, (path, 'chart series ' + tag))
        values.append(unsigned_integer(nodes[0].get('val'), (path, 'chart series ' + tag)))
    return values


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
        if node.tag == '{' + NS['s'] + '}f':
            require(node.get('t', 'normal') in ('normal', 'shared'), ('unsupported cell formula type', path, node.attrib))
        if node.tag in tags:
            require(not SAFE_FORMULA_TOKENS.sub('', node.text or ''),
                    ('unsupported workbook formula', path, node.text))


def package_types(content_types, names):
    defaults = {}
    overrides = {}
    for part in content_types:
        override = part.tag == '{' + NS['ct'] + '}Override'
        table = overrides if override else defaults
        value = part.get('PartName' if override else 'Extension', '')
        require(not override or (value.startswith('/') and not value.startswith('//')), ('content type declaration', value))
        key = (value[1:] if override else value).translate(ASCII_LOWER)
        require(key and part.get('ContentType') and key not in table, ('duplicate content type declaration or missing fields', key))
        table[key] = part.get('ContentType').lower()
    types = {}
    for name in names:
        basename = posixpath.basename(name)
        extension = basename.rsplit('.', 1)[1].translate(ASCII_LOWER) if '.' in basename else ''
        types[name.translate(ASCII_LOWER)] = overrides.get(name.translate(ASCII_LOWER), defaults.get(extension))
    return types


GRAPH_TYPES = {
    'officeDocument': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
    'worksheet': 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
    'drawing': 'application/vnd.openxmlformats-officedocument.drawing+xml',
    'chart': 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml',
    'sharedStrings': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedstrings+xml',
}


def package_relationships(archive, path, part_types):
    require(part_types.get(path.translate(ASCII_LOWER)) == 'application/vnd.openxmlformats-package.relationships+xml', ('graph content type', path))
    rels = ET.fromstring(archive.read(path))
    require(rels.tag == '{' + NS['p'] + '}Relationships'
            and all(rel.tag == '{' + NS['p'] + '}Relationship' for rel in rels), ('package relationships', path))
    return rels


def relationship_target(archive, parts, part_types, source, identifier, kind):
    rel_path = posixpath.join(posixpath.dirname(source), '_rels', posixpath.basename(source) + '.rels')
    rel_key = rel_path.translate(ASCII_LOWER)
    require(rel_key in parts, ('chart reachability: missing relationships', source))
    rels = package_relationships(archive, parts[rel_key], part_types)
    matches = [rel for rel in rels if rel.get('Id') == identifier]
    require(len(matches) == 1 and matches[0].get('Type') == NS['r'] + '/' + kind,
            ('chart reachability: missing or ambiguous relationship', source, identifier))
    target = matches[0].get('Target', '')
    target = target.lstrip('/') if target.startswith('/') else posixpath.normpath(posixpath.join(posixpath.dirname(source), target))
    require(target.translate(ASCII_LOWER) in parts, ('chart reachability: missing target', source, target))
    require(part_types.get(target.translate(ASCII_LOWER)) == GRAPH_TYPES[kind], ('chart reachability: graph content type', target, kind))
    return parts[target.translate(ASCII_LOWER)]


def string_text(item, path):
    message = ('campaign string structure', path)
    text_tag = '{' + NS['s'] + '}t'
    if len(item) == 1 and item[0].tag == text_tag:
        require(len(item[0]) == 0, message)
        return item[0].text or ''
    require(len(item) > 0 and all(run.tag == '{' + NS['s'] + '}r' for run in item), message)
    values = []
    for run in item:
        texts = run.findall('s:t', NS)
        require(len(texts) == 1 and len(texts[0]) == 0 and len(run.findall('s:rPr', NS)) <= 1
                and all(child.tag in {text_tag, '{' + NS['s'] + '}rPr'} for child in run), message)
        values.append(texts[0].text or '')
    return ''.join(values)


def shared_strings(archive, parts, part_types):
    source = 'xl/workbook.xml'
    rels = package_relationships(archive, parts['xl/_rels/workbook.xml.rels'], part_types)
    edges = [rel for rel in rels if rel.get('Type') == NS['r'] + '/sharedStrings']
    require(len(edges) == 1, 'campaign shared string relationship must be unique')
    path = relationship_target(archive, parts, part_types, source, edges[0].get('Id'), 'sharedStrings')
    table = ET.fromstring(archive.read(path))
    require(table.tag == '{' + NS['s'] + '}sst'
            and all(item.tag == '{' + NS['s'] + '}si' for item in table), ('campaign string structure', path))
    return [string_text(item, path) for item in table]


def validate_chart_reachability(archive, parts, part_types, drawing_refs, content_types, charts):
    drawings = []
    displayed = []
    for source, identifier in drawing_refs:
        target = relationship_target(archive, parts, part_types, source, identifier, 'drawing')
        drawings.append(target)
        drawing = ET.fromstring(archive.read(target))
        require(drawing.tag == '{' + NS['xdr'] + '}wsDr', ('chart reachability: invalid drawing root', target))
        frames = []
        for kind in ('twoCellAnchor', 'oneCellAnchor', 'absoluteAnchor'):
            for anchor in drawing.findall(f'xdr:{kind}', NS):
                anchored_frames = anchor.findall('xdr:graphicFrame', NS)
                require(len(anchored_frames) == 1, ('chart reachability: invalid anchor frame count', target))
                frame = anchored_frames[0]
                graphics = frame.findall('a:graphic', NS)
                require(len(graphics) == 1, ('chart reachability: invalid graphic count', target))
                payloads = graphics[0].findall('a:graphicData', NS)
                require(len(payloads) == 1, ('chart reachability: invalid chart data count', target))
                payload = payloads[0]
                require(payload.get('uri') == NS['c'] and len(payload) == 1 and payload[0].tag == '{' + NS['c'] + '}chart',
                        ('chart reachability: invalid chart data', target))
                frames.append(payload[0])
        require(len(frames) == len(drawing.findall('.//c:chart', NS)), ('chart reachability: non-frame chart', target))
        for frame in frames:
            displayed.append(relationship_target(archive, parts, part_types, target, frame.get('{' + NS['r'] + '}id'), 'chart'))
    declared_drawings = [parts[item.get('PartName', '').lstrip('/').translate(ASCII_LOWER)] for item in content_types
                         if item.get('ContentType', '').lower() == 'application/vnd.openxmlformats-officedocument.drawing+xml']
    require(len(drawings) == len(set(drawings)) == len(declared_drawings)
            and set(drawings) == set(declared_drawings), 'chart reachability: orphan or duplicated drawing')
    require(len(displayed) == len(set(displayed)) == len(charts) and set(displayed) == set(charts),
            'chart reachability: displayed charts differ from validated charts')


def chart_formula(series, name, types, path):
    nodes = series.findall('c:' + name, NS)
    require(len(nodes) == 1 and len(nodes[0]) == 1, (path, 'chart binding structure', name))
    reference = nodes[0][0]
    require(reference.tag in {'{' + NS['c'] + '}' + kind for kind in types}, (path, 'chart binding structure', name))
    formulas = reference.findall('c:f', NS)
    require(len(formulas) == 1, (path, 'chart binding structure', name))
    return formulas[0].text


for filename in args.workbooks:
    with zipfile.ZipFile(filename) as archive:
        names = archive.namelist()
        require(len(names) == len({name.translate(ASCII_LOWER) for name in names}), ('duplicate package part', filename))
        require(not any('/tables/' in ('/' + name.translate(ASCII_LOWER)) for name in names), 'unexpected workbook table part')
        parts = {name.translate(ASCII_LOWER): name for name in names}
        content_types = ET.fromstring(archive.read('[Content_Types].xml'))
        require(content_types.tag == '{' + NS['ct'] + '}Types'
                and all(part.tag in {'{' + NS['ct'] + '}Default', '{' + NS['ct'] + '}Override'} for part in content_types),
                'package content types')
        part_types = package_types(content_types, names)
        forbidden = ('vba', 'macroenabled', 'macrosheet', 'activex', 'oleobject', 'externallink', 'connections', 'querytable', 'webextension', 'taskpane')
        for part in content_types:
            require('spreadsheetml.table' not in part.get('ContentType', '').lower(), 'unexpected workbook table type')
            require(not any(token in part.get('ContentType', '').lower() for token in forbidden),
                    ('active content type', part.attrib))
        relationship_parts = {name for name in names if name.translate(ASCII_LOWER).endswith('.rels')}
        relationship_parts.update(part.get('PartName', '').lstrip('/') for part in content_types
                                  if part.get('ContentType', '').lower() == 'application/vnd.openxmlformats-package.relationships+xml' and part.get('PartName'))
        for path in relationship_parts:
            for relationship in package_relationships(archive, path, part_types):
                require(relationship.get('Type', '').lower().rsplit('/', 1)[-1] != 'table', 'unexpected workbook table relationship')
                target = relationship.get('Target', '')
                require(relationship.get('TargetMode', '').lower() != 'external'
                        and not urlsplit(target).scheme and not target.startswith('//')
                        and not any(token in relationship.get('Type', '').lower() for token in forbidden),
                        ('active content relationship', path, relationship.attrib))
        require('_rels/.rels' in parts, 'chart reachability: missing package relationships')
        office = [rel for rel in package_relationships(archive, parts['_rels/.rels'], part_types) if rel.get('Type') == NS['r'] + '/officeDocument']
        require(len(office) == 1 and relationship_target(archive, parts, part_types, '', office[0].get('Id'), 'officeDocument') == parts.get('xl/workbook.xml'),
                'chart reachability: package workbook differs from validated workbook')
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        require(workbook.tag == '{' + NS['s'] + '}workbook', 'chart reachability: invalid workbook root')
        validate_formulas(workbook, 'xl/workbook.xml')
        containers = workbook.findall('s:sheets', NS)
        require(len(containers) == 1 and all(sheet.tag == '{' + NS['s'] + '}sheet' for sheet in containers[0]), 'worksheet inventory')
        records = list(containers[0])
        for attribute in ('name', '{' + NS['r'] + '}id'):
            values = [sheet.get(attribute, '') for sheet in records]
            keys = [value.casefold() for value in values] if attribute == 'name' else values
            require(all(values) and len(keys) == len(set(keys)), ('worksheet inventory', attribute))
        identities = [unsigned_integer(sheet.get('sheetId'), ('worksheet inventory', 'sheetId')) for sheet in records]
        require(len(identities) == len(set(identities)), ('worksheet inventory', 'sheetId'))
        sheets = {}
        for sheet in records:
            sheets[sheet.attrib['name']] = relationship_target(archive, parts, part_types, 'xl/workbook.xml', sheet.attrib['{' + NS['r'] + '}id'], 'worksheet')
        require({'Policy Lab', 'Policy', 'Assumptions', 'Economy', 'Shocks'} <= set(sheets), 'worksheet inventory: missing required sheet')
        if args.campaign_reference:
            campaign = json.loads(args.campaign_reference.read_text())
            require(campaign['scenario']['id'] == 'mixed_crises', 'Campaign reference must be Recurring crises')
            expected_note = 'Recurring crises: ' + campaign['scenario']['description']
            shock_cells = worksheet_cells(ET.fromstring(archive.read(sheets['Shocks'])), sheets['Shocks'])
            shared = shared_strings(archive, parts, part_types) if any(cell.get('t') == 's' for cell in shock_cells.values()) else []
            values = []
            for cell in shock_cells.values():
                kind = cell.get('t')
                if kind in ('s', 'str'):
                    value = cell.find('s:v', NS)
                    require(value is not None, ('campaign string structure', cell.get('r'), 'missing value'))
                    if kind == 's':
                        index = unsigned_integer(value.text, 'campaign shared string index')
                        require(index < len(shared), 'campaign shared string index outside table')
                        values.append(shared[index])
                    else:
                        values.append(value.text or '')
                elif kind == 'inlineStr':
                    values.append(string_text(cell.find('s:is', NS), sheets['Shocks']))
            require(expected_note in values, 'stale or missing campaign explanation')
        cells = worksheet_cells(ET.fromstring(archive.read(sheets['Economy'])), sheets['Economy'])
        shared = shared_formulas(cells)
        worst = 0
        for quarter, state in enumerate([reference['initial_state']] + [r['state'] for r in reference['quarters']]):
            for field, value in flatten_state(state).items():
                require(field in rows, f'Full-state parity unmapped native field: {field}')
                cell = cells[f'{column(quarter + 4)}{rows[field]}']
                # Cold starts calculate all state fields except the authored quarter literal.
                if quarter > 0 or (state['quarter_index'] == 0 and field != 'quarter_index'):
                    require(has_formula(cell, shared), f'Full-state parity missing formula: {field} at {cell.attrib["r"]}')
                require(cell.find('s:v', NS) is not None, f'Full-state parity missing cache: {field}')
                if not isinstance(value, bool):
                    require(cell.get('t', 'n') == 'n', ('full-state parity numeric type', field))
                actual = float(cell.find('s:v', NS).text)
                if isinstance(value, bool):
                    require(cell.attrib.get('t') == 'b' and actual in (0, 1), f'Full-state parity boolean type: {field}')
                error = abs(actual - float(value))
                worst = max(worst, error)
                require(math.isfinite(actual) and math.isfinite(float(value)) and error < 1e-7, ('full-state parity', filename, quarter, field, actual, value))
        errors = []
        drawing_refs = []
        for name, path in sheets.items():
            part = ET.fromstring(archive.read(path))
            require(part.tag == '{' + NS['s'] + '}worksheet', ('chart reachability: invalid worksheet root', path))
            validate_formulas(part, path)
            sheet_cells = worksheet_cells(part, path)
            drawing_refs.extend((path, node.get('{' + NS['r'] + '}id')) for node in part.findall('s:drawing', NS))
            if name != 'Economy':
                shared_formulas(sheet_cells)
            errors.extend((name, c.attrib['r'], c.find('s:v', NS).text)
                          for c in sheet_cells.values()
                          if c.attrib.get('t') == 'e')
        require(not errors, errors[:10])
        charts = [item.attrib['PartName'].lstrip('/') for item in content_types
                  if item.attrib.get('ContentType', '').lower() == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml']
        require(len(charts) == 4, 'validation failed')
        validate_chart_reachability(archive, parts, part_types, drawing_refs, content_types, charts)
        expected_series = {'Inflation and expectations (%)': ['C', 'D', 'E'], 'Unemployment (%)': ['F', 'G'],
                           'Policy and long yield (%)': ['H', 'I'], 'Model confidence scores (0–100)': ['J', 'K']}
        palettes = []
        titles = []
        for path in charts:
            chart = ET.fromstring(archive.read(path))
            validate_formulas(chart, path)
            chart_nodes = chart.findall('c:chart', NS)
            require(chart.tag == '{' + NS['c'] + '}chartSpace' and len(chart_nodes) == 1, (path, 'chart structure'))
            plots = chart_nodes[0].findall('c:plotArea', NS)
            require(len(plots) == 1, (path, 'chart structure'))
            lines = plots[0].findall('c:lineChart', NS)
            require(len(lines) == 1, (path, 'chart structure'))
            title = ''.join(node.text or '' for node in chart.findall('c:chart/c:title//a:t', NS))
            titles.append(title)
            formats = plots[0].findall('c:valAx/c:numFmt', NS)
            require(formats and all(f.attrib.get('formatCode') == '0.00'
                                   and f.attrib.get('sourceLinked') in ('0', 'false') for f in formats), (path, title, 'ambiguous value-axis precision'))
            series = lines[0].findall('c:ser', NS)
            require(len(series) == len(chart.findall('.//c:ser', NS)), (path, 'chart structure'))
            require(title in expected_series and len(series) == len(expected_series[title]), (path, title, 'missing chart series'))
            require(series_numbers(series, 'order', path) == list(range(len(series))), (path, 'chart series order'))
            identities = series_numbers(series, 'idx', path)
            require(len(identities) == len(set(identities)), (path, 'chart series idx'))
            palettes.append([s.find('c:spPr/a:ln/a:solidFill/a:srgbClr', NS).attrib['val'] for s in series])
            for item, col in zip(series, expected_series[title]):
                category = chart_formula(item, 'cat', ('strRef', 'numRef'), path)
                require(category == "'Policy Lab'!$B$58:$B$106",
                        (path, title, 'chart category binding'))
                value = chart_formula(item, 'val', ('numRef',), path)
                require(value == f"'Policy Lab'!${col}$58:${col}$106",
                        (path, title, 'chart value binding'))
        require(set(titles) == set(expected_series), 'Missing or duplicated chart')
        require(not any('vbaproject' in p.lower() or 'externallinks' in p.lower() for p in archive.namelist()), 'active content filename')
        receipt = dict(file=str(filename), max_absolute_error=worst, formula_errors=len(errors), charts=len(charts), colors=palettes)
        print('PASS', json.dumps(receipt))
