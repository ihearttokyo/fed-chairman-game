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
parser.add_argument('--reference-set', required=True, type=Path, help='Trusted eight-case native reference directory used by the authored inventory')
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


# Trusted sidecar comes from the authored builder, never the candidate workbook/cache.
formula_inventory_path = args.map.with_suffix('.formulas.json')
require(formula_inventory_path.is_file(), 'missing authored formula inventory; run generate-formula-inventory.mjs')
formula_inventory = json.loads(formula_inventory_path.read_text())
require(formula_inventory.get('schema_version') == 2, 'unsupported authored formula inventory schema')
for name, key in [('build-policy-lab.mjs', 'builder_sha256'), ('generate-formula-inventory.mjs', 'generator_sha256')]:
    require(hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest() == formula_inventory.get(key),
            ('authored formula inventory source mismatch', name))
require(hashlib.sha256(json.dumps(rows, separators=(',', ':')).encode()).hexdigest() == formula_inventory.get('row_map_sha256'),
        'authored formula inventory row map mismatch')
require(set(formula_inventory.get('state_fields', [])) == set(flatten_state(reference['initial_state'])),
        'authored formula inventory state schema mismatch')
require(isinstance(formula_inventory.get('formulas'), dict), 'missing authored formula inventory formulas')
for field in formula_inventory['state_fields']:
    require(all(f'{column(q + 4)}{rows[field]}' in formula_inventory['formulas'] for q in range(49)),
            ('incomplete authored formula inventory', field))

# Exact full-set binding catches layout changes in nonactive cases as well.
reference_hashes = formula_inventory.get('reference_sha256', {})
require(isinstance(reference_hashes, dict) and len(reference_hashes) == 8, 'reference input binding: expected eight cases')
reference_cases = {}
for case, digest in reference_hashes.items():
    require(isinstance(case, str) and re.fullmatch(r'[a-z_]+', case) is not None, 'reference input binding: invalid case')
    path = args.reference_set / (case + '.json')
    require(path.is_file(), ('reference input binding: missing case', case))
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == digest, ('reference input binding: source set digest', case))
    document = json.loads(raw)
    require(document['scenario']['id'] == case and document['initial_state']['quarter_index'] == 0,
            ('reference input binding: cold source case', case))
    reference_cases[case] = document
case = reference['scenario']['id']
require(case in reference_cases, 'reference input binding: unknown active case')
if reference['initial_state']['quarter_index'] == 0:
    require(hashlib.sha256(args.reference.read_bytes()).hexdigest() == reference_hashes[case],
            'reference input binding: cold active digest')
else:
    def authored_inputs(document):
        return json.dumps({'parameters': document['parameters'], 'scenario': document['scenario'],
                           'initial_keys': list(document['scenario']['initial']),
                           'portfolio_reference_json': document['portfolio_reference_json'],
                           'portfolio_reference_sha256': document['portfolio_reference_sha256'],
                           'state_fields': list(flatten_state(document['initial_state']))}, sort_keys=True, separators=(',', ':'))
    require(authored_inputs(reference) == authored_inputs(reference_cases[case]),
            'reference input binding: checkpoint authored inputs/layout')
if args.campaign_reference:
    require(hashlib.sha256(args.campaign_reference.read_bytes()).hexdigest() == reference_hashes.get('mixed_crises'),
            'reference input binding: campaign source digest')
require(isinstance(formula_inventory.get('upstream_formulas'), dict)
        and all(isinstance(formula_inventory['upstream_formulas'].get(name), dict)
                and formula_inventory['upstream_formulas'][name] for name in ('Assumptions', 'Shocks')),
        'incomplete authored upstream formula inventory')

FORMULA_QUOTED = re.compile(r'("(?:[^"]|"")*"|\'(?:[^\']|\'\')*\'!)')
FORMULA_REFERENCE = re.compile(r'(?<![A-Z0-9_])(\$?)([A-Z]{1,3})(\$?)([1-9][0-9]*)(?![A-Z0-9_])', re.IGNORECASE | re.ASCII)


def canonical_formula(text):
    tokens = []
    for token in SAFE_FORMULA_TOKENS.findall(text.strip().removeprefix('=')):
        if token.isspace():
            continue
        if token.startswith('"'):
            tokens.append(token)
        elif token.startswith("'"):
            tokens.append(token[1:-2].replace("''", "'").upper() + '!')
        else:
            tokens.append(re.sub(r'\s+', '', token).replace('$', '').upper())
    return tokens


def translate_formula(text, origin, address):
    before, after = coordinates(origin), coordinates(address)
    def shift(match):
        col, row = coordinates(match[2].upper() + match[4])
        if not match[1]:
            col += after[0] - before[0]
        if not match[3]:
            row += after[1] - before[1]
        require(1 <= col <= 16384 and 1 <= row <= 1048576, 'authored formula mismatch: translated reference outside worksheet')
        return match[1] + column(col) + match[3] + str(row)
    pieces = FORMULA_QUOTED.split(text)
    for i in range(0, len(pieces), 2):
        pieces[i] = FORMULA_REFERENCE.sub(shift, pieces[i])
    return ''.join(pieces)


def validate_authored_formulas(cells, shared, expected_formulas=None):
    economy_contract = expected_formulas is None
    expected_formulas = formula_inventory['formulas'] if economy_contract else expected_formulas
    origins = {unsigned_integer(cell.find('s:f', NS).get('si'), 'shared formula group index'): address
               for address, cell in cells.items() if cell.find('s:f', NS) is not None
               and cell.find('s:f', NS).get('t') == 'shared' and cell.find('s:f', NS).get('ref') is not None}
    checkpoint_literals = {f'D{rows[field]}' for field in formula_inventory['state_fields']} if economy_contract and reference['initial_state']['quarter_index'] > 0 else set()
    for address, expected in expected_formulas.items():
        require(address in cells, ('authored formula mismatch', address, 'missing cell'))
        formula = cells[address].find('s:f', NS)
        if address in checkpoint_literals or expected is None:
            require(formula is None, ('authored formula mismatch', address, 'expected authored literal'))
            continue
        require(formula is not None, ('authored formula mismatch', address, 'missing formula'))
        actual = formula.text or ''
        if formula.get('t') == 'shared':
            index = unsigned_integer(formula.get('si'), 'shared formula group index')
            actual = translate_formula(shared[index].text, origins[index], address)
        require(actual.strip().removeprefix('=') == expected.strip().removeprefix('=')
                or canonical_formula(actual) == canonical_formula(expected), ('authored formula mismatch', address))


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
    r'|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:E[+-]?[0-9]+)?|<=|>=|<>|[\s+*/^&=<>():,-]',
    re.IGNORECASE | re.ASCII,
)


def validate_formulas(part, path):
    tags = {'{' + NS['s'] + '}' + name for name in ('f', 'formula', 'formula1', 'formula2', 'definedName')}
    tags.add('{' + NS['c'] + '}f')
    tags.add('{http://schemas.microsoft.com/office/excel/2006/main}f')
    for node in part.iter():
        if node.tag == '{' + NS['s'] + '}f':
            require(node.get('t', 'normal') in ('normal', 'shared'), ('unsupported cell formula type', path, node.attrib))
        if node.tag in tags:
            require(len(node) == 0, ('unsupported workbook formula structure', path))
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
    anchors = {}
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
                nonvisual = frame.findall('xdr:nvGraphicFramePr', NS)
                require(len(nonvisual) == 1 and len(frame.findall('.//xdr:nvGraphicFramePr', NS)) == 1,
                        ('chart frame visibility: nonvisual properties', target))
                properties = nonvisual[0].findall('xdr:cNvPr', NS)
                require(len(properties) == 1 and len(frame.findall('.//xdr:cNvPr', NS)) == 1,
                        ('chart frame visibility: drawing properties', target))
                require(properties[0].get('hidden', '0') in ('0', 'false'),
                        ('chart frame visibility: hidden or unsupported boolean', target))
                graphics = frame.findall('a:graphic', NS)
                require(len(graphics) == 1, ('chart reachability: invalid graphic count', target))
                payloads = graphics[0].findall('a:graphicData', NS)
                require(len(payloads) == 1, ('chart reachability: invalid chart data count', target))
                payload = payloads[0]
                require(payload.get('uri') == NS['c'] and len(payload) == 1 and payload[0].tag == '{' + NS['c'] + '}chart',
                        ('chart reachability: invalid chart data', target))
                frames.append((payload[0], anchor))
        require(len(frames) == len(drawing.findall('.//c:chart', NS)), ('chart reachability: non-frame chart', target))
        for frame, anchor in frames:
            chart_path = relationship_target(archive, parts, part_types, target, frame.get('{' + NS['r'] + '}id'), 'chart')
            displayed.append(chart_path)
            anchors[chart_path] = (source, anchor)
    declared_drawings = [parts[item.get('PartName', '').lstrip('/').translate(ASCII_LOWER)] for item in content_types
                         if item.get('ContentType', '').lower() == 'application/vnd.openxmlformats-officedocument.drawing+xml']
    require(len(drawings) == len(set(drawings)) == len(declared_drawings)
            and set(drawings) == set(declared_drawings), 'chart reachability: orphan or duplicated drawing')
    require(len(displayed) == len(set(displayed)) == len(charts) and set(displayed) == set(charts),
            'chart reachability: displayed charts differ from validated charts')
    return anchors


def chart_formula(series, name, types, path):
    nodes = series.findall('c:' + name, NS)
    require(len(nodes) == 1 and len(nodes[0]) == 1, (path, 'chart binding structure', name))
    reference = nodes[0][0]
    require(reference.tag in {'{' + NS['c'] + '}' + kind for kind in types}, (path, 'chart binding structure', name))
    formulas = reference.findall('c:f', NS)
    require(len(formulas) == 1, (path, 'chart binding structure', name))
    return formulas[0].text



# These bindings and zero-based anchors mirror build-policy-lab.mjs, including cleared checkpoint suffixes.
PLOT_FIELDS = ['four_quarter_inflation_pct', 'expected_short_inflation_pct', 'expected_long_inflation_pct',
               'unemployment_rate_pct', 'structural_unemployment_pct', 'policy_rate_pct', 'long_yield_pct',
               'public_support', 'credibility']
PLOT_LABELS = ['Inflation', 'Short expectations', 'Long expectations', 'Unemployment', 'Structural reference',
               'Policy rate', 'Long yield', 'Public support', 'Credibility × 100']
CHART_ANCHORS = {'Inflation and expectations (%)': (1, 19, 8, 35), 'Unemployment (%)': (8, 19, 16, 35),
                 'Policy and long yield (%)': (1, 36, 8, 52), 'Model confidence scores (0–100)': (8, 36, 16, 52)}


def saved_string(cell, strings, message):
    require(cell is not None and cell.find('s:f', NS) is None, message)
    kind = cell.get('t')
    if kind == 'inlineStr':
        return string_text(cell.find('s:is', NS), message)
    value = cell.find('s:v', NS)
    require(value is not None and kind in ('str', 's'), message)
    if kind == 's':
        index = unsigned_integer(value.text, message)
        require(index < len(strings), message)
        return strings[index]
    return value.text or ''


def saved_number(cell, message):
    require(cell is not None and cell.get('t', 'n') == 'n', message)
    value = cell.find('s:v', NS)
    require(value is not None, message)
    try:
        number = float(value.text)
    except (ValueError, TypeError):
        raise AssertionError(message)
    require(math.isfinite(number), message)
    return number


def chart_cache(ref, kind, values, message):
    cache_tag = '{' + NS['c'] + '}' + kind
    require(all(child.tag in {'{' + NS['c'] + '}f', cache_tag} for child in ref), message)
    caches = ref.findall('c:' + kind, NS)
    require(len(caches) <= 1, message)
    if not caches:
        return
    cache = caches[0]
    counts = cache.findall('c:ptCount', NS)
    require(len(counts) == 1 and len(cache.findall('c:formatCode', NS)) <= 1
            and all(child.tag in {'{' + NS['c'] + '}' + name for name in ('ptCount', 'pt', 'formatCode')} for child in cache), message)
    count = unsigned_integer(counts[0].get('val'), message)
    points = cache.findall('c:pt', NS)
    # The authored exporter defers caches with ptCount=0; populated caches may omit blank points.
    require(count == len(values) or (count == 0 and not points), message)
    seen = set()
    for point in points:
        index = unsigned_integer(point.get('idx'), message)
        require(index < len(values) and index not in seen and len(point) == 1
                and point[0].tag == '{' + NS['c'] + '}v' and len(point[0]) == 0, message)
        seen.add(index)
        expected = values[index]
        require(expected is not None, message)
        if kind == 'numCache':
            try:
                number = float(point[0].text)
            except (TypeError, ValueError):
                raise AssertionError(message)
            require(isinstance(expected, (float, int)) and math.isfinite(number) and abs(number - expected) < 1e-7, message)
        else:
            require((point[0].text or '') == expected, message)
    require(count == 0 or seen == {i for i, value in enumerate(values) if value is not None}, message)


def chart_title(series, col, label, path):
    message = (path, 'chart series title', col)
    titles = series.findall('c:tx', NS)
    require(len(titles) == 1 and len(titles[0]) == 1, message)
    title = titles[0][0]
    if title.tag == '{' + NS['c'] + '}v':
        require(len(title) == 0 and title.text == label, message)
    else:
        require(title.tag == '{' + NS['c'] + '}strRef'
                and chart_formula(series, 'tx', ('strRef',), path).replace('$', '') == f"'Policy Lab'!{col}57", message)
        chart_cache(title, 'strCache', [label], message)


def chart_axes(plot, line, path):
    message = (path, 'chart axis graph')
    cats, vals = plot.findall('c:catAx', NS), plot.findall('c:valAx', NS)
    require(len(cats) == len(vals) == 1
            and len([child for child in plot if child.tag.endswith('Ax')]) == 2, message)
    identities, crosses = [], []
    for axis in (cats[0], vals[0]):
        for name, result in (('axId', identities), ('crossAx', crosses)):
            nodes = axis.findall('c:' + name, NS)
            require(len(nodes) == 1 and len(nodes[0]) == 0, message)
            result.append(unsigned_integer(nodes[0].get('val'), message))
    line_ids = [
        unsigned_integer(node.get('val'), message) for node in line.findall('c:axId', NS)]
    require(len(set(identities)) == 2 and crosses == identities[::-1]
            and len(line_ids) == 2 and set(line_ids) == set(identities), message)


def chart_anchor(binding, sheet, title, path):
    source, anchor = binding
    message = (path, 'chart anchor geometry')
    require(source == sheet and anchor.tag == '{' + NS['xdr'] + '}twoCellAnchor', message)
    actual = []
    for end in ('from', 'to'):
        markers = anchor.findall('xdr:' + end, NS)
        require(len(markers) == 1 and len(markers[0]) == 4, message)
        marker = markers[0]
        for axis in ('col', 'row'):
            nodes = marker.findall('xdr:' + axis, NS)
            offsets = marker.findall('xdr:' + axis + 'Off', NS)
            require(len(nodes) == len(offsets) == 1 and len(nodes[0]) == len(offsets[0]) == 0, message)
            actual.append(unsigned_integer(nodes[0].text, message))
            require(unsigned_integer(offsets[0].text, message) == 0, message)
    require(tuple(actual) == CHART_ANCHORS[title], message)


def dashboard_values(lab, economy, strings):
    states = [reference['initial_state']] + [quarter['state'] for quarter in reference['quarters']]
    require(1 <= len(states) <= 49, 'dashboard horizon')
    data = {col: [] for col in 'BCDEFGHIJK'}
    for i, label in enumerate(PLOT_LABELS, 3):
        require(saved_string(lab.get(f'{column(i)}57'), strings, 'chart series title header') == label,
                'chart series title header')
    for q in range(49):
        row = q + 58
        if q >= len(states):
            for col in data:
                cell = lab.get(f'{col}{row}')
                require(cell is None or len(cell) == 0, ('dashboard cleared checkpoint suffix', col, row))
                data[col].append(None)
            continue
        label = saved_string(lab.get(f'B{row}'), strings, 'dashboard quarter label')
        require(label == f"Q{states[q]['quarter_index']}", ('dashboard quarter label', row))
        data['B'].append(label)
        for i, field in enumerate(PLOT_FIELDS, 3):
            col = column(i); address = f'{col}{row}'; cell = lab.get(address)
            source = f'{column(q + 4)}{rows[field]}'
            scale = 100 if field == 'credibility' else 1
            formula = f"'Economy'!{source}" + ('*100' if scale == 100 else '')
            require(cell is not None and cell.findtext('s:f', namespaces=NS) == formula,
                    ('dashboard source binding', address))
            value = saved_number(cell, ('dashboard numeric cache', address))
            expected = saved_number(economy.get(source), ('dashboard Economy source', source)) * scale
            require(abs(value - expected) < 1e-7, ('dashboard source cache parity', address))
            data[col].append(value)
    return data


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
            if sheet.get('name') in ('Policy Lab', 'Policy'):
                require(sheet.get('state', 'visible') == 'visible', ('interactive worksheet visibility', sheet.get('name')))
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
        sheet_data = {}
        for name, path in sheets.items():
            part = ET.fromstring(archive.read(path))
            require(part.tag == '{' + NS['s'] + '}worksheet', ('chart reachability: invalid worksheet root', path))
            sheet_cells = worksheet_cells(part, path)
            validate_formulas(part, path)
            sheet_data[name] = sheet_cells
            drawing_refs.extend((path, node.get('{' + NS['r'] + '}id')) for node in part.findall('s:drawing', NS))
            if name != 'Economy':
                sheet_shared = shared_formulas(sheet_cells)
                if name in formula_inventory['upstream_formulas']:
                    validate_authored_formulas(sheet_cells, sheet_shared, formula_inventory['upstream_formulas'][name])
            errors.extend((name, c.attrib['r'], c.find('s:v', NS).text)
                          for c in sheet_cells.values()
                          if c.attrib.get('t') == 'e')
        require(not errors, errors[:10])
        validate_authored_formulas(cells, shared)
        charts = [item.attrib['PartName'].lstrip('/') for item in content_types
                  if item.attrib.get('ContentType', '').lower() == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml']
        require(len(charts) == 4, 'validation failed')
        anchors = validate_chart_reachability(archive, parts, part_types, drawing_refs, content_types, charts)
        lab = sheet_data['Policy Lab']
        strings = shared_strings(archive, parts, part_types) if any(cell.get('t') == 's' for cell in lab.values()) else []
        plot_values = dashboard_values(lab, cells, strings)
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
            chart_axes(plots[0], lines[0], path)
            chart_anchor(anchors[path], sheets['Policy Lab'], title, path)
            require(series_numbers(series, 'order', path) == list(range(len(series))), (path, 'chart series order'))
            identities = series_numbers(series, 'idx', path)
            require(len(identities) == len(set(identities)), (path, 'chart series idx'))
            palettes.append([s.find('c:spPr/a:ln/a:solidFill/a:srgbClr', NS).attrib['val'] for s in series])
            for item, col in zip(series, expected_series[title]):
                chart_title(item, col, PLOT_LABELS[ord(col) - ord('C')], path)
                category = chart_formula(item, 'cat', ('strRef',), path)
                require(category == "'Policy Lab'!$B$58:$B$106",
                        (path, title, 'chart category binding'))
                value = chart_formula(item, 'val', ('numRef',), path)
                require(value == f"'Policy Lab'!${col}$58:${col}$106",
                        (path, title, 'chart value binding'))
                cat_ref = item.find('c:cat', NS)[0]
                chart_cache(cat_ref, 'strCache', plot_values['B'], (path, 'chart cache category'))
                chart_cache(item.find('c:val/c:numRef', NS), 'numCache', plot_values[col], (path, 'chart cache value', col))
        require(set(titles) == set(expected_series), 'Missing or duplicated chart')
        require(not any('vbaproject' in p.lower() or 'externallinks' in p.lower() for p in archive.namelist()), 'active content filename')
        receipt = dict(file=str(filename), max_absolute_error=worst, formula_errors=len(errors), charts=len(charts), colors=palettes)
        print('PASS', json.dumps(receipt))
