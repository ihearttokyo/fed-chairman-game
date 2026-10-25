"""Reject malformed policy validation, charts or caches in real workbook copies."""
from pathlib import Path
import json
import argparse
import os
import posixpath
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def scenario_mutation_targets(row_map):
    """Locate scenario-dependent fixtures from the trusted authored inventory."""
    inventory = json.loads(row_map.with_suffix('.formulas.json').read_text())
    layout = inventory['upstream_cache_layout']
    count = len(inventory['case_order'])
    require(count > 0 and layout['case_stride'] == count + 2, 'Scenario mutation layout stride')
    literals = inventory['literal_inputs']['Assumptions']
    initial_literals = sorted(
        (f'D{row + offset}' for row in layout['initial_rows'].values()
         for offset in range(1, count + 1)
         if type(literals.get(f'D{row + offset}')) in (int, float)),
        key=lambda address: int(address[1:]))
    require(initial_literals, 'Scenario mutation layout needs numeric initial overrides')
    first_shock = min(layout['shock_rows'].values())
    last_shock = max(layout['shock_rows'].values())
    active_offset = inventory['case_order'].index('supply_shock') + 1
    start = layout['source_start']
    return {
        'campaign-note': f'B{last_shock + layout["case_stride"] + 2}',
        'shock-last-formula': f'AZ{last_shock}',
        'initial-first': initial_literals[0], 'initial-last': initial_literals[-1],
        'source-first': f'C{start}', 'source-last': f'C{start + 119}',
        'source-constant': f'C{start - 4}',
        'shock-active': f'E{first_shock + active_offset}',
        'shock-nonactive': f'E{first_shock + 1}',
        'shock-last': f'AZ{last_shock + count}',
        'shock-blank-zero': f'E{layout["shock_rows"]["potential_growth_pct"] + active_offset}',
    }


def validate_policy_inputs(archive):
    sheets = ET.fromstring(archive.read('xl/workbook.xml')).find('s:sheets', NS)
    policy = next(sheet for sheet in sheets if sheet.attrib['name'] == 'Policy')
    targets = {item.attrib['Id']: item.attrib['Target']
               for item in ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))}
    target = targets[policy.attrib['{' + NS['r'] + '}id']]
    path = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
    rules = ET.fromstring(archive.read(path)).findall('s:dataValidations/s:dataValidation', NS)
    expected = {'E6:AZ9': 'OR(ISBLANK(E6),AND(ISNUMBER(E6),NOT(ISLOGICAL(E6))))',
                'E10:AZ11': 'AND(ISNUMBER(E10),NOT(ISLOGICAL(E10)))'}
    require(len(rules) == 2 and {rule.get('sqref') for rule in rules} == set(expected), 'Policy input validation ranges')
    for rule in rules:
        require(rule.get('type') == 'custom', 'Policy input validation type')
        require(rule.findtext('s:formula1', namespaces=NS) == expected[rule.get('sqref')], 'Policy input validation relative formula')
        require(rule.get('allowBlank', 'false') in ('0', 'false'), 'Policy input validation must not ignore blanks')
        require(rule.get('showErrorMessage') in ('1', 'true'), 'Policy input validation alert disabled')
        require(rule.get('errorStyle', 'stop') == 'stop', 'Policy input validation must Stop')
    return path



NEW_CASES = {
    'upstream45-parameter': 'authored formula mismatch',
    'upstream45-initial': 'authored formula mismatch',
    'upstream45-source-check': 'authored formula mismatch',
    'upstream45-source-weight': 'authored formula mismatch',
    'upstream45-shock-first': 'authored formula mismatch',
    'upstream45-shock-last': 'authored formula mismatch',
    'upstream45-shock-shared-wrong': 'authored formula mismatch',
    'upstream45-shock-shared': None,
    'upstream45-shock-shared-backward': None,
    'upstream45-shock-scalar': None,

    'formula19-split-number': 'authored formula mismatch',
    'formula19-split-comparison': 'authored formula mismatch',
    'formula19-zero-state': 'authored formula mismatch',
    'formula19-safe-wrong-state': 'authored formula mismatch',
    'formula19-zero-helper': 'authored formula mismatch',
    'formula19-cold-wrong-zero': 'authored formula mismatch',
    'formula19-shared-wrong-master': 'authored formula mismatch',
    'formula19-short-suffix': 'authored formula mismatch',
    'formula19-xm-webservice': 'unsupported workbook formula',
    'formula19-xm-dde': 'unsupported workbook formula',
    'formula19-xm-benign': None,
    'formula19-xm-string': None,
    'formula19-scalar-format': None,
    'formula19-shared-relative': None,
    'formula19-shared-backward': None,
    'formula19-shared-quoted-string': None,

    'cells-policy-wrong-cell': 'worksheet cell structure',
    'cells-policy-wrong-formula': 'worksheet cell structure',
    'cells-policy-wrong-cache': 'worksheet cell structure',
    'cells-policy-nested-formula': 'worksheet cell structure',
    'cells-policy-nested-cache': 'worksheet cell structure',
    'formula-array': 'unsupported cell formula type',
    'formula-data-table': 'unsupported cell formula type',
    'formula-unknown': 'unsupported cell formula type',
    'formula-policy-array': 'unsupported cell formula type',
    'formula-normal-explicit': None,
    'graph-duplicate-target': 'chart reachability',
    'graph-missing-frame': 'chart reachability',
    'graph-duplicate-frame': 'chart reachability',
    'graph-alien-target': 'chart reachability',
    'graph-orphan-drawing': 'chart reachability',
    'graph-missing-worksheet-drawing': 'chart reachability',
    'graph-relative-targets': None,
    'graph-wrong-root': 'chart reachability',
    'graph-wrong-anchor': 'chart reachability',
    'graph-wrapped-anchor': 'chart reachability',
    'graph-wrong-uri': 'chart reachability',
    'graph-missing-uri': 'chart reachability',
    'graph-multiple-payload': 'chart reachability',
    'graph-multiple-containers': 'chart reachability',
    'graph-multiple-graphics': 'chart reachability',
    'graph-multiple-frames': 'chart reachability',
    'chart-wrong-root': 'chart structure',
    'chart-wrapped-line': 'chart structure',
    'chart-multiple-lines': 'chart structure',
    'chart-wrapped-series': 'chart structure',
    'graph-workbook-root': 'chart reachability',
    'graph-worksheet-root': 'chart reachability',
    'graph-worksheet-type': 'chart reachability',
    'graph-relationship-root': 'package relationships',
    'graph-relationship-child': 'package relationships',
    'graph-content-types-root': 'package content types',
    'graph-package-office-type': 'chart reachability',
    'graph-package-office-target': 'chart reachability',
    'graph-content-types-child': 'package content types',
    'graph-duplicate-office-edge': 'chart reachability',
    'graph-duplicate-sheet-edge': 'chart reachability',
    'chart-duplicate-value': 'chart binding structure',
    'chart-duplicate-category': 'chart binding structure',
    'chart-duplicate-reference': 'chart binding structure',
    'chart-duplicate-formula': 'chart binding structure',
    # Q-string categories are strRef in the builder and all resident exports; numRef requires numeric data.
    'chart-numeric-category': 'chart binding structure',
    'metadata-default-type': 'graph content type',
    'metadata-sheet-type': 'graph content type',
    'metadata-relationship-type': 'graph content type',
    'metadata-duplicate-default': 'duplicate content type declaration',
    'metadata-duplicate-override': 'duplicate content type declaration',
    'metadata-sheet-tag': 'worksheet inventory',
    'metadata-duplicate-sheet': 'worksheet inventory',
    'metadata-duplicate-container': 'worksheet inventory',
    'metadata-duplicate-name': 'worksheet inventory',
    'metadata-duplicate-rid': 'worksheet inventory',
    'metadata-duplicate-sheet-id': 'worksheet inventory',
    'metadata-missing-sheet': 'worksheet inventory',
    'types-slash-xml': 'graph content type',
    'types-slash-rels': 'graph content type',
    'types-double-slash-override': 'content type declaration',
    'cells-orphan-container': 'worksheet cell structure',
    'cells-orphan-row': 'worksheet cell structure',
    'cells-duplicate-address': 'worksheet cell structure',
    'cells-duplicate-formula': 'worksheet cell structure',
    'cells-duplicate-cache': 'worksheet cell structure',
    'cells-duplicate-row': 'worksheet cell structure',
    'cells-row-mismatch': 'worksheet cell structure',
    'numeric-shared-type': 'full-state parity numeric type',
    'numeric-string-type': 'full-state parity numeric type',
    'numeric-boolean-type': 'full-state parity numeric type',
    'numeric-unknown-type': 'full-state parity numeric type',
    'numeric-explicit-type': None,
    'numeric-default-type': None,
    'webextension-type': 'active content',
    'taskpanes-type': 'active content',
    'webextension-relationship': 'active content',
    'taskpanes-relationship': 'active content',
    'table-calculated': 'unexpected workbook table',
    'table-totals': 'unexpected workbook table',
    'table-renamed-type': 'unexpected workbook table',
    'table-renamed-relationship': 'unexpected workbook table',
    'uppercase-external-rels': 'active content relationship',
    'uppercase-safe-rels': None,
    'opc-case-duplicate': 'duplicate package part',
    'chart-order-swapped': 'chart series order',
    'chart-order-duplicated': 'chart series order',
    'chart-order-missing': 'chart series order',
    'chart-index-duplicated': 'chart series idx',
    'chart-safe-indices': None,
    'shared-master-no-ref': 'shared formula group',
    'shared-master-outside': 'shared formula group',
    'shared-master-reversed': 'shared formula group',
    'shared-master-no-index': 'shared formula group',
    'shared-master-duplicated': 'shared formula group',
    'shared-master-overlap': 'shared formula group',
    'shared-disjoint-groups': None,
    'shared-master-single-cell': None,
    'shared-follower-text': None,
    'shared-valid-follower': None,
}


CAMPAIGN_CASES = {
    **{name: 'worksheet cell structure' for name in (
        'campaign-numeric-inline', 'campaign-boolean-inline', 'campaign-missing-type-inline',
        'campaign-unknown-inline', 'campaign-inline-wrong-is', 'campaign-str-inline-ambiguous')},
    **{name: 'campaign string structure' for name in (
        'campaign-inline-wrapped-text', 'campaign-shared-wrong-root', 'campaign-shared-wrong-si',
        'campaign-shared-wrapped-text', 'campaign-shared-mixed-text')},
    'campaign-shared-negative': 'shared string index',
    'campaign-shared-outside': 'shared string index',
    'campaign-shared-fraction': 'shared string index',
    'campaign-shared-disconnected': 'shared string relationship',
    'campaign-shared-wrong-rel-type': 'shared string relationship',
    'campaign-shared-duplicate-edge': 'shared string relationship',
    'campaign-shared-wrong-content-type': 'graph content type',
    'campaign-inline-plain': None,
    'campaign-inline-rich': None,
    'campaign-shared-plain': None,
    'campaign-shared-rich': None,
    'campaign-shared-plus-zero': None,
    'campaign-shared-relative-renamed': None,
}



CHART19_CASES = {
    **{f'chart19-{name}': 'chart series title' for name in ('title-literal', 'title-reference', 'title-cache', 'title-cache-duplicate', 'header', 'header-formula')},
    **{f'chart19-{name}': 'chart cache' for name in ('num-stale', 'num-duplicate', 'num-count', 'num-index', 'num-nan', 'category-stale', 'missing-nonblank', 'empty-populated-cache')},
    **{f'chart19-{name}': 'dashboard' for name in ('joint-cache', 'source-formula', 'source-type', 'source-cache', 'credibility-scale', 'quarter-label', 'quarter-label-formula')},
    **{f'chart19-{name}': 'chart axis graph' for name in ('axis-missing', 'axis-duplicate', 'axis-same-id', 'axis-line', 'axis-cross')},
    **{f'chart19-{name}': 'interactive worksheet visibility' for name in ('lab-hidden', 'policy-very-hidden')},
    **{f'chart19-{name}': 'chart anchor geometry' for name in ('anchor-zero', 'anchor-reversed', 'anchor-far', 'anchor-offset', 'anchor-missing')},
    **{f'chart19-{name}': None for name in ('valid-ids', 'valid-caches', 'missing-caches', 'valid-title-reference', 'visible')},
}
NEW_CASES.update(CHART19_CASES)


def chart19_mutations(source, defect, row_map):
    ns = dict(NS, c='http://schemas.openxmlformats.org/drawingml/2006/chart',
              xdr='http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing')
    def tag(name):
        prefix, local = name.split(':')
        return '{' + ns[prefix] + '}' + local
    types = ET.fromstring(source.read('[Content_Types].xml'))
    path = next(p.get('PartName').lstrip('/') for p in types if p.get('ContentType', '').endswith('drawingml.chart+xml'))
    chart = ET.fromstring(source.read(path))
    wb = ET.fromstring(source.read('xl/workbook.xml'))
    rels = {r.get('Id'): r.get('Target') for r in ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))}
    sheet = next(x for x in wb.find('s:sheets', ns) if x.get('name') == 'Policy Lab')
    target = rels[sheet.get('{' + ns['r'] + '}id')]
    lab_path = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
    lab = ET.fromstring(source.read(lab_path))
    cells = {c.get('r'): c for c in lab.findall('.//s:c', ns)}
    ser = chart.find('.//c:ser', ns)
    name = defect.removeprefix('chart19-')
    changes = {path: chart}
    def populate(ref, cache_name, values):
        for old in ref.findall('c:' + cache_name, ns): ref.remove(old)
        cache = ET.SubElement(ref, tag('c:' + cache_name))
        ET.SubElement(cache, tag('c:ptCount'), val='49')
        for i, value in enumerate(values):
            if value is not None:
                point = ET.SubElement(cache, tag('c:pt'), idx=str(i))
                ET.SubElement(point, tag('c:v')).text = value
        return cache
    numeric = [cells[f'C{i}'].findtext('s:v', namespaces=ns) for i in range(58, 107)]
    labels = [cells[f'B{i}'].findtext('s:v', namespaces=ns) for i in range(58, 107)]
    if name in ('valid-caches', 'num-stale', 'num-duplicate', 'num-count', 'num-index', 'num-nan', 'joint-cache', 'missing-nonblank', 'empty-populated-cache'):
        cache = populate(ser.find('c:val/c:numRef', ns), 'numCache', numeric)
        if name == 'missing-nonblank': cache.remove(cache.findall('c:pt', ns)[-1])
        if name == 'empty-populated-cache':
            for point in cache.findall('c:pt', ns): cache.remove(point)
        point = cache.find('c:pt', ns)
        if name in ('num-stale', 'joint-cache'): point.find('c:v', ns).text = '777'
        elif name == 'num-duplicate': cache.append(ET.fromstring(ET.tostring(point)))
        elif name == 'num-count': cache.find('c:ptCount', ns).set('val', '50')
        elif name == 'num-index': point.set('idx', '49')
        elif name == 'num-nan': point.find('c:v', ns).text = 'NaN'
        if name == 'joint-cache':
            cells['C58'].find('s:v', ns).text = '777'; changes[lab_path] = lab
    if name in ('valid-caches', 'category-stale'):
        cache = populate(ser.find('c:cat/c:strRef', ns), 'strCache', labels)
        if name == 'category-stale': cache.find('c:pt/c:v', ns).text = 'Q999'
    if name == 'missing-caches':
        for ref in chart.findall('.//c:numRef', ns) + chart.findall('.//c:strRef', ns):
            for child in list(ref):
                if child.tag in (tag('c:numCache'), tag('c:strCache')): ref.remove(child)
    if name in ('title-reference', 'title-cache', 'title-cache-duplicate', 'valid-title-reference'):
        tx = ser.find('c:tx', ns); tx.clear()
        ref = ET.SubElement(tx, tag('c:strRef'))
        ET.SubElement(ref, tag('c:f')).text = "'Policy Lab'!$D$57" if name == 'title-reference' else "'Policy Lab'!$C$57"
        cache = ET.SubElement(ref, tag('c:strCache')); ET.SubElement(cache, tag('c:ptCount'), val='1')
        point = ET.SubElement(cache, tag('c:pt'), idx='0'); ET.SubElement(point, tag('c:v')).text = 'Wrong' if name == 'title-cache' else 'Inflation'
        if name == 'title-cache-duplicate': cache.append(ET.fromstring(ET.tostring(point)))
    elif name == 'title-literal': ser.find('c:tx/c:v', ns).text = 'Wrong'
    if name in ('source-formula', 'source-type', 'source-cache', 'credibility-scale', 'quarter-label', 'quarter-label-formula', 'header', 'header-formula'):
        cell = cells['K58' if name == 'credibility-scale' else 'B58' if name.startswith('quarter-label') else 'C57' if name.startswith('header') else 'C58']
        if name in ('header-formula', 'quarter-label-formula'): ET.SubElement(cell, tag('s:f')).text = '"Wrong"'
        elif name == 'source-formula': cell.find('s:f', ns).text = '777'
        elif name == 'credibility-scale': cell.find('s:f', ns).text = cell.find('s:f', ns).text.replace('*100', '')
        elif name == 'source-type': cell.set('t', 'str')
        else: cell.find('s:v', ns).text = 'Wrong' if name in ('quarter-label', 'header') else '777'
        changes[lab_path] = lab
    plot = chart.find('c:chart/c:plotArea', ns); line = plot.find('c:lineChart', ns)
    cat, val = plot.find('c:catAx', ns), plot.find('c:valAx', ns)
    if name == 'axis-missing': plot.remove(cat)
    elif name == 'axis-duplicate': plot.append(ET.fromstring(ET.tostring(cat)))
    elif name == 'axis-same-id': val.find('c:axId', ns).set('val', cat.find('c:axId', ns).get('val'))
    elif name == 'axis-line': line.find('c:axId', ns).set('val', '7654321')
    elif name == 'axis-cross': cat.find('c:crossAx', ns).set('val', '7654321')
    elif name == 'valid-ids':
        old = [cat.find('c:axId', ns).get('val'), val.find('c:axId', ns).get('val')]
        for node in chart.findall('.//c:axId', ns) + chart.findall('.//c:crossAx', ns): node.set('val', str(123 + old.index(node.get('val'))))
    if name in ('lab-hidden', 'policy-very-hidden', 'visible'):
        for x in wb.find('s:sheets', ns):
            if x.get('name') == ('Policy' if name == 'policy-very-hidden' else 'Policy Lab'): x.set('state', 'visible' if name == 'visible' else 'veryHidden' if name == 'policy-very-hidden' else 'hidden')
        changes['xl/workbook.xml'] = wb
    if name.startswith('anchor-'):
        drawing_path = next(p.get('PartName').lstrip('/') for p in types if p.get('ContentType', '').endswith('drawing+xml'))
        drawing = ET.fromstring(source.read(drawing_path)); anchor = drawing[0]
        if name == 'anchor-missing': anchor.remove(anchor.find('xdr:to', ns))
        elif name == 'anchor-zero':
            for axis in ('col', 'row'): anchor.find('xdr:to/xdr:' + axis, ns).text = anchor.find('xdr:from/xdr:' + axis, ns).text
        elif name == 'anchor-reversed': anchor.find('xdr:to/xdr:row', ns).text = '0'
        elif name == 'anchor-far': anchor.find('xdr:to/xdr:col', ns).text = '16383'
        elif name == 'anchor-offset': anchor.find('xdr:from/xdr:colOff', ns).text = '999999999'
        changes[drawing_path] = drawing
    return {p: ET.tostring(x, encoding='utf-8', xml_declaration=True) for p, x in changes.items()}



CHART45_CASES = {
    **{f'chart45-{name}': 'chart frame visibility' for name in (
        'hidden-one', 'hidden-true', 'hidden-empty', 'hidden-invalid', 'hidden-uppercase',
        'missing-nonvisual', 'wrapped-nonvisual', 'duplicate-nonvisual', 'shadow-nonvisual',
        'missing-properties', 'wrapped-properties', 'duplicate-properties', 'shadow-properties',
        'wrong-properties-namespace')},
    'chart45-numeric-category-no-cache': 'chart binding structure',
    **{f'chart45-{name}': None for name in ('visible-absent', 'visible-zero', 'visible-false', 'string-category-no-cache')},
}
NEW_CASES.update(CHART45_CASES)


def chart45_mutations(source, defect, row_map):
    ns = dict(NS, c='http://schemas.openxmlformats.org/drawingml/2006/chart',
              xdr='http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing')
    kind = defect.removeprefix('chart45-')
    types = ET.fromstring(source.read('[Content_Types].xml'))
    if kind in ('numeric-category-no-cache', 'string-category-no-cache'):
        path = next(p.get('PartName').lstrip('/') for p in types if p.get('ContentType', '').endswith('drawingml.chart+xml'))
        chart = ET.fromstring(source.read(path))
        ref = chart.find('.//c:ser/c:cat/c:strRef', ns)
        require(ref is not None, 'chart45 category mutation requires authored string reference')
        if kind == 'numeric-category-no-cache': ref.tag = '{' + ns['c'] + '}numRef'
        for child in list(ref):
            if child.tag != '{' + ns['c'] + '}f': ref.remove(child)
        return {path: ET.tostring(chart, encoding='utf-8', xml_declaration=True)}
    path = next(p.get('PartName').lstrip('/') for p in types if p.get('ContentType', '').endswith('drawing+xml'))
    drawing = ET.fromstring(source.read(path))
    frame = drawing.find('xdr:twoCellAnchor/xdr:graphicFrame', ns)
    require(frame is not None, 'chart45 visibility mutation requires actual chart frame')
    nonvisual = frame.find('xdr:nvGraphicFramePr', ns)
    require(nonvisual is not None, 'chart45 visibility mutation requires actual nonvisual properties')
    props = nonvisual.find('xdr:cNvPr', ns)
    require(props is not None, 'chart45 visibility mutation requires actual drawing properties')
    hidden = {'hidden-one': '1', 'hidden-true': 'true', 'hidden-empty': '', 'hidden-invalid': '2',
              'hidden-uppercase': 'False', 'visible-zero': '0', 'visible-false': 'false'}
    if kind in hidden: props.set('hidden', hidden[kind])
    elif kind == 'visible-absent': props.attrib.pop('hidden', None)
    elif kind == 'missing-nonvisual': frame.remove(nonvisual)
    elif kind == 'wrapped-nonvisual':
        frame.remove(nonvisual)
        ET.SubElement(frame, '{' + ns['xdr'] + '}wrapper').append(nonvisual)
    elif kind in ('duplicate-nonvisual', 'shadow-nonvisual'):
        copy = ET.fromstring(ET.tostring(nonvisual)); copy.find('xdr:cNvPr', ns).set('hidden', '1')
        parent = frame if kind == 'duplicate-nonvisual' else ET.SubElement(frame, '{' + ns['xdr'] + '}wrapper')
        parent.append(copy)
    elif kind == 'missing-properties': nonvisual.remove(props)
    elif kind == 'wrapped-properties':
        nonvisual.remove(props)
        ET.SubElement(nonvisual, '{' + ns['xdr'] + '}wrapper').append(props)
    elif kind in ('duplicate-properties', 'shadow-properties'):
        copy = ET.fromstring(ET.tostring(props)); copy.set('hidden', '1')
        parent = nonvisual if kind == 'duplicate-properties' else ET.SubElement(frame, '{' + ns['xdr'] + '}wrapper')
        parent.append(copy)
    elif kind == 'wrong-properties-namespace': props.tag = '{urn:unsupported}cNvPr'
    else: raise AssertionError('Unknown chart45 mutation: ' + defect)
    return {path: ET.tostring(drawing, encoding='utf-8', xml_declaration=True)}


INTERACTION54_CASES = {
    **{f'interaction54-hidden-{name}': 'interactive worksheet visibility' for name in ('assumptions', 'shocks')},
    **{f'interaction54-objects-{name}': 'workbook object visibility' for name in ('none', 'placeholders', 'invalid', 'duplicate', 'wrapped', 'shadow')},
    **{f'interaction54-calc-{name}': 'workbook automatic calculation' for name in ('manual', 'invalid', 'duplicate', 'wrapped', 'shadow', 'precision-false', 'iterate-true')},
    **{f'interaction54-protect-{name}': 'interactive sheet protection' for name in ('policy', 'lab', 'assumptions', 'shocks', 'true', 'invalid', 'uppercase', 'duplicate', 'wrapped', 'shadow')},
    **{f'interaction54-{name}': None for name in ('objects-default', 'objects-all', 'calc-default', 'calc-auto-no-table', 'calc-auto-flags-digits', 'calc-auto-flags-words', 'protection-default', 'economy-protected')},
    **{f'interaction54-unprotected-{name}-{flag}': None for name in ('policy', 'lab', 'assumptions', 'shocks') for flag in ('zero', 'false')},
}
NEW_CASES.update(INTERACTION54_CASES)


def interaction54_mutations(source, defect, row_map):
    kind = defect.removeprefix('interaction54-')
    namespace = '{' + NS['s'] + '}'
    workbook = ET.fromstring(source.read('xl/workbook.xml'))
    if kind.startswith('hidden-'):
        next(sheet for sheet in workbook.find('s:sheets', NS) if sheet.get('name') == kind.removeprefix('hidden-').title()).set('state', 'hidden')
        return {'xl/workbook.xml': ET.tostring(workbook, encoding='utf-8', xml_declaration=True)}
    if kind.startswith(('objects-', 'calc-')):
        objects = kind.startswith('objects-')
        tag = 'workbookPr' if objects else 'calcPr'
        action = kind.split('-', 1)[1]
        for old in workbook.findall('s:' + tag, NS): workbook.remove(old)
        attrs = {}
        if objects and action != 'default': attrs['showObjects'] = {'none': 'none', 'placeholders': 'placeholders', 'invalid': 'unexpected'}.get(action, 'all')
        if not objects and action != 'default': attrs['calcMode'] = {'manual': 'manual', 'invalid': 'unexpected', 'auto-no-table': 'autoNoTable'}.get(action, 'auto')
        if action == 'precision-false': attrs['fullPrecision'] = '0'
        elif action == 'iterate-true': attrs['iterate'] = 'true'
        elif action == 'auto-flags-digits': attrs.update(fullPrecision='1', iterate='0', fullCalcOnLoad='1', calcOnSave='0')
        elif action == 'auto-flags-words': attrs.update(fullPrecision='true', iterate='false', fullCalcOnLoad='false', calcOnSave='true')
        node = ET.Element(namespace + tag, attrs)
        # Preserve workbook sequence around sheets rather than relying on consumer repair.
        position = next(i for i, child in enumerate(workbook) if child.tag == namespace + 'sheets') if objects else len(workbook)
        if action == 'wrapped': ET.SubElement(workbook, namespace + 'wrapper').append(node)
        else:
            workbook.insert(position, node)
            if action in ('duplicate', 'shadow'):
                bad = ET.Element(namespace + tag, {'showObjects': 'none'} if objects else {'calcMode': 'manual'})
                if action == 'duplicate': workbook.insert(position + 1, bad)
                else: ET.SubElement(workbook, namespace + 'wrapper').append(bad)
        return {'xl/workbook.xml': ET.tostring(workbook, encoding='utf-8', xml_declaration=True)}
    rels = {x.get('Id'): x.get('Target') for x in ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))}
    names = {'policy': 'Policy', 'lab': 'Policy Lab', 'assumptions': 'Assumptions', 'shocks': 'Shocks'}
    suffix = kind.split('-')[1] if kind.startswith(('protect-', 'unprotected-')) else ''
    name = 'Economy' if kind == 'economy-protected' else names.get(suffix, 'Policy')
    sheet = next(x for x in workbook.find('s:sheets', NS) if x.get('name') == name)
    target = rels[sheet.get('{' + NS['r'] + '}id')]
    path = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
    root = ET.fromstring(source.read(path))
    for old in root.findall('s:sheetProtection', NS): root.remove(old)
    attrs = {'sheet': '1'}
    if kind.startswith('unprotected-'): attrs = {'sheet': '0' if kind.endswith('-zero') else 'false', 'objects': 'true', 'scenarios': '1', 'formatCells': 'false', 'selectLockedCells': '0'}
    elif kind == 'protection-default': attrs = {'objects': '1', 'scenarios': 'true'}
    elif suffix in ('true', 'invalid', 'uppercase'): attrs['sheet'] = {'true': 'true', 'invalid': '2', 'uppercase': 'False'}[suffix]
    node = ET.Element(namespace + 'sheetProtection', attrs)
    position = next(i for i, child in enumerate(root) if child.tag == namespace + 'sheetData') + 1
    if suffix == 'wrapped': ET.SubElement(root, namespace + 'wrapper').append(node)
    else:
        if suffix in ('duplicate', 'shadow'): node.set('sheet', 'false')
        root.insert(position, node)
        if suffix in ('duplicate', 'shadow'):
            bad = ET.Element(namespace + 'sheetProtection', sheet='true')
            if suffix == 'duplicate': root.insert(position + 1, bad)
            else: ET.SubElement(root, namespace + 'wrapper').append(bad)
    return {path: ET.tostring(root, encoding='utf-8', xml_declaration=True)}


DISPLAY58_CASES = {
    **{f'display58-{name}': 'authored formula mismatch' for name in ('summary-first-formula', 'summary-last-formula', 'case-header-policy', 'case-header-assumptions', 'case-header-economy', 'case-header-shocks')},
    **{f'display58-{name}': 'dashboard summary cache' for name in ('summary-first-cache', 'summary-last-cache', 'summary-logical-cache', 'summary-string-cache')},
}
NEW_CASES.update(DISPLAY58_CASES)


def display58_mutations(source, defect, row_map):
    kind = defect.removeprefix('display58-')
    targets = {'summary-first-formula': (1, 'C12', 'formula'), 'summary-last-formula': (1, 'C17', 'formula'),
               'summary-first-cache': (1, 'C12', 'cache'), 'summary-last-cache': (1, 'C17', 'cache'),
               'summary-logical-cache': (1, 'C14', 'logical'), 'summary-string-cache': (1, 'C16', 'string'),
               'case-header-policy': (2, 'D3', 'formula'), 'case-header-assumptions': (3, 'D3', 'formula'),
               'case-header-economy': (4, 'D3', 'formula'), 'case-header-shocks': (5, 'D3', 'formula')}
    index, address, action = targets[kind]
    path = f'xl/worksheets/sheet{index}.xml'; part = ET.fromstring(source.read(path))
    cell = part.find(f'.//s:c[@r="{address}"]', NS)
    require(cell is not None and cell.find('s:f', NS) is not None and cell.find('s:v', NS) is not None,
            'display58 requires an actual calculated display cell')
    if action == 'formula': cell.find('s:f', NS).text = '0'
    elif action == 'cache': cell.find('s:v', NS).text = str(float(cell.find('s:v', NS).text) + 0.5)
    else:
        cell.set('t', 'b' if action == 'logical' else 'str')
        if action == 'logical': cell.find('s:v', NS).text = '1'
    return {path: ET.tostring(part, encoding='utf-8', xml_declaration=True)}


LABEL60_CASES = {
    **{f'label60-selector-{name}': 'authored literal mismatch' for name in ('case', 'horizon', 'benchmark')},
    **{f'label60-{name}': 'dashboard cached label' for name in ('case-source-cache', 'benchmark-cache', 'case-source-type', 'benchmark-type', 'header-policy-type', 'header-policy', 'header-assumptions', 'header-economy', 'header-shocks')},
}
NEW_CASES.update(LABEL60_CASES)


def label60_mutations(source, defect, row_map):
    kind = defect.removeprefix('label60-')
    targets = {'selector-case': (1, 'C4', 'fraction'), 'selector-horizon': (1, 'C5', 'fraction'),
               'selector-benchmark': (1, 'C6', 'fraction'), 'case-source-cache': (1, 'E4', 'wrong'),
               'benchmark-cache': (1, 'E6', 'wrong'), 'case-source-type': (1, 'E4', 'bool'),
               'benchmark-type': (1, 'E6', 'number'), 'header-policy-type': (2, 'D3', 'number'),
               'header-policy': (2, 'D3', 'wrong'), 'header-assumptions': (3, 'D3', 'wrong'),
               'header-economy': (4, 'D3', 'wrong'), 'header-shocks': (5, 'D3', 'wrong')}
    index, address, action = targets[kind]
    path = f'xl/worksheets/sheet{index}.xml'; part = ET.fromstring(source.read(path))
    cell = part.find(f'.//s:c[@r="{address}"]', NS)
    require(cell is not None and cell.find('s:v', NS) is not None, 'label60 requires an actual saved selector/label')
    value = cell.find('s:v', NS)
    if action == 'fraction': value.text = repr(float(value.text) + (5e-13 if address == 'C6' else 1e-12))
    elif action == 'wrong':
        cell.set('t', 'str'); value.text = 'Funding stress' if address != 'E6' else 'Hold previous rate'
    else:
        cell.set('t', 'b' if action == 'bool' else 'n'); value.text = '1' if action == 'bool' else '0'
    return {path: ET.tostring(part, encoding='utf-8', xml_declaration=True)}


INPUT72_CASES = {
    **{f'input72-{name}': 'authored literal mismatch' for name in ('fixed-tiny', 'target-tiny', 'continuous-tiny')},
    'input72-numeric-spelling': None,
}
NEW_CASES.update(INPUT72_CASES)


def input72_mutations(source, defect, row_map):
    name = defect.removeprefix('input72-')
    address = {'fixed-tiny': 'C7', 'target-tiny': 'C6', 'continuous-tiny': 'C79', 'numeric-spelling': 'C7'}[name]
    path = 'xl/worksheets/sheet3.xml'; part = ET.fromstring(source.read(path))
    cell = part.find(f'.//s:c[@r="{address}"]', NS)
    require(cell is not None and cell.find('s:f', NS) is None and cell.find('s:v', NS) is not None,
            'input72 requires an actual authored numeric input')
    value = cell.find('s:v', NS); prior = float(value.text)
    value.text = format(prior, '.17e') if name == 'numeric-spelling' else repr(prior + abs(prior) * 1e-13)
    return {path: ET.tostring(part, encoding='utf-8', xml_declaration=True)}


UPSTREAM77_CASES = {
    **{f'upstream77-metadata-{name}': 'authored literal mismatch' for name in
       ('label', 'unit', 'classification', 'description', 'source', 'blank-source', 'missing', 'formula', 'numeric')},
    **{f'upstream77-header-{sheet}-{address}': 'authored literal mismatch'
       for sheet in ('policy', 'shocks') for address in ('E4', 'AZ4')},
    **{f'upstream77-checkpoint-{address}': 'authored literal mismatch' for address in ('B5', 'B8', 'B9')},
    **{f'upstream77-selector-{name}': 'authored data validation' for name in
       ('missing', 'removed', 'decimal', 'operator', 'minimum', 'maximum', 'horizon', 'benchmark',
        'overlap', 'extra', 'duplicate', 'wrapped', 'wrapped-container', 'duplicate-container', 'count',
        'duplicate-formula', 'blank', 'alert-missing', 'alert-false', 'warning', 'unknown-alert')},
    **{f'upstream77-{name}': None for name in
       ('metadata-str', 'metadata-inline', 'metadata-rich', 'metadata-shared', 'metadata-shared-rich',
        'selector-defaults', 'selector-words', 'selector-canonical')},
}
NEW_CASES.update(UPSTREAM77_CASES)


def upstream77_mutations(source, defect, row_map):
    kind = defect.removeprefix('upstream77-')
    path = 'xl/worksheets/' + ('sheet2.xml' if kind.startswith('header-policy-') else
                              'sheet5.xml' if kind.startswith('header-shocks-') else
                              'sheet3.xml' if kind.startswith('metadata-') else 'sheet1.xml')
    part = ET.fromstring(source.read(path)); namespace = '{' + NS['s'] + '}'
    changes = {}
    if kind.startswith('selector-'):
        action = kind.removeprefix('selector-')
        container = part.find('s:dataValidations', NS)
        require(container is not None and len(container) == 3, 'upstream77 requires actual three selector rules')
        rule = container[0]
        if action == 'missing': part.remove(container)
        elif action == 'removed': container.remove(rule); container.set('count', str(len(container)))
        elif action == 'decimal': rule.set('type', 'decimal')
        elif action == 'operator': rule.set('operator', 'equal')
        elif action == 'minimum': rule.find('s:formula1', NS).text = '0'
        elif action == 'maximum':
            maximum = rule.find('s:formula2', NS)
            maximum.text = str(int(maximum.text) + 1)
        elif action == 'horizon': container[1].find('s:formula2', NS).text = '48'
        elif action == 'benchmark': container[2].find('s:formula2', NS).text = '3'
        elif action == 'overlap': rule.set('sqref', 'C4:C6')
        elif action in ('extra', 'duplicate'):
            other = ET.fromstring(ET.tostring(rule))
            if action == 'extra': other.set('sqref', 'C4 C5')
            container.append(other); container.set('count', str(len(container)))
        elif action == 'wrapped': container.remove(rule); ET.SubElement(container, namespace + 'wrapper').append(rule)
        elif action == 'wrapped-container': part.remove(container); ET.SubElement(part, namespace + 'wrapper').append(container)
        elif action == 'duplicate-container': part.append(ET.fromstring(ET.tostring(container)))
        elif action == 'count': container.set('count', '2')
        elif action == 'duplicate-formula': rule.append(ET.fromstring(ET.tostring(rule[0])))
        elif action == 'blank': rule.set('allowBlank', 'true')
        elif action == 'alert-missing': rule.attrib.pop('showErrorMessage', None)
        elif action == 'alert-false': rule.set('showErrorMessage', 'false')
        elif action == 'warning': rule.set('errorStyle', 'warning')
        elif action == 'unknown-alert': rule.set('showErrorMessage', 'yes')
        elif action in ('defaults', 'words', 'canonical'):
            for rule in container:
                if action == 'defaults':
                    rule.attrib.pop('allowBlank', None); rule.attrib.pop('errorStyle', None); rule.attrib.pop('operator', None)
                elif action == 'words': rule.set('allowBlank', 'false'); rule.set('showErrorMessage', 'true')
                else:
                    for formula in rule: formula.text = ' = ' + formula.text.lower().replace(',', ', ')
            if action == 'defaults': container.attrib.pop('count', None)
        else: raise AssertionError(action)
    else:
        cells = {cell.get('r'): cell for cell in part.findall('s:sheetData/s:row/s:c', NS)}
        action = kind.removeprefix('metadata-')
        address = kind.rsplit('-', 1)[-1] if kind.startswith(('header-', 'checkpoint-')) else {
            'label': 'B6', 'unit': 'E6', 'classification': 'F6', 'description': 'H6', 'source': 'J6',
            'blank-source': 'J8'}.get(action, 'B6')
        cell = cells.get(address)
        if cell is None:
            row = next(row for row in part.findall('s:sheetData/s:row', NS) if row.get('r') == re.sub('[A-Z]', '', address))
            cell = ET.SubElement(row, namespace + 'c', r=address)
        if action == 'missing':
            next(row for row in part.findall('s:sheetData/s:row', NS) if cell in row).remove(cell)
        else:
            original = cell.findtext('s:v', namespaces=NS)
            inline = cell.find('s:is', NS)
            if inline is not None: original = ''.join(inline.itertext())
            attrs = dict(cell.attrib); cell.clear(); cell.attrib.update(attrs)
            text = original if action in ('str', 'inline', 'rich', 'shared', 'shared-rich') else 'Changed authored text'
            if action == 'numeric': cell.set('t', 'n'); ET.SubElement(cell, namespace + 'v').text = '2'
            elif action in ('inline', 'rich'):
                cell.set('t', 'inlineStr'); inline = ET.SubElement(cell, namespace + 'is')
                if action == 'rich':
                    for value in (text[:3], text[3:]): ET.SubElement(ET.SubElement(inline, namespace + 'r'), namespace + 't').text = value
                else: ET.SubElement(inline, namespace + 't').text = text
            elif action in ('shared', 'shared-rich'):
                exists = 'xl/sharedStrings.xml' in source.namelist()
                table = ET.fromstring(source.read('xl/sharedStrings.xml')) if exists else ET.Element(namespace + 'sst')
                index = len(table); item = ET.SubElement(table, namespace + 'si')
                if action == 'shared-rich':
                    for value in (text[:3], text[3:]): ET.SubElement(ET.SubElement(item, namespace + 'r'), namespace + 't').text = value
                else: ET.SubElement(item, namespace + 't').text = text
                if table.get('count') is not None: table.set('count', str(int(table.get('count')) + 1))
                if table.get('uniqueCount') is not None: table.set('uniqueCount', str(len(table)))
                changes['xl/sharedStrings.xml'] = ET.tostring(table, encoding='utf-8')
                if not exists:
                    rels = ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))
                    ET.SubElement(rels, '{http://schemas.openxmlformats.org/package/2006/relationships}Relationship',
                                  Id='upstream77Strings', Type=NS['r'] + '/sharedStrings', Target='sharedStrings.xml')
                    changes['xl/_rels/workbook.xml.rels'] = ET.tostring(rels, encoding='utf-8')
                    types = ET.fromstring(source.read('[Content_Types].xml'))
                    ET.SubElement(types, '{http://schemas.openxmlformats.org/package/2006/content-types}Override',
                                  PartName='/xl/sharedStrings.xml', ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml')
                    changes['[Content_Types].xml'] = ET.tostring(types, encoding='utf-8')
                cell.set('t', 's'); ET.SubElement(cell, namespace + 'v').text = str(index)
            else:
                cell.set('t', 'str')
                if action == 'formula': ET.SubElement(cell, namespace + 'f').text = '"' + original + '"'
                ET.SubElement(cell, namespace + 'v').text = text
    changes[path] = ET.tostring(part, encoding='utf-8')
    return changes


def validate_view77_guidance_oracle(checker):
    import ast
    import math
    definitions = [node for node in ast.parse(checker.read_text()).body
                   if isinstance(node, ast.FunctionDef) and node.name == 'native_prior_commitment']
    require(len(definitions) == 1, 'view77 native guidance oracle definition')
    namespace = {'math': math, 'require': require}
    exec(compile(ast.Module(body=definitions, type_ignores=[]), str(checker), 'exec'), namespace)
    oracle = namespace['native_prior_commitment']
    prior = dict(guidance_active=True, guidance_rate_pct=0, guidance_inflation_sensitivity=0,
                 four_quarter_inflation_pct=2, guidance_reference_inflation_pct=2,
                 guidance_output_gap_sensitivity=0, output_gap_pct=0, guidance_reference_output_gap_pct=0)
    state = {'policy_rate_pct': 3.5}
    for magnitude in (0.5, 1.5, 2.5, 3.5):
        for sign in (-1, 1):
            tie = sign * magnitude
            for value, expected in ((tie, sign * (math.floor(magnitude) + 1)),
                                    (math.nextafter(tie, 0), sign * math.floor(magnitude)),
                                    (math.nextafter(tie, math.copysign(math.inf, tie)), sign * (math.floor(magnitude) + 1))):
                prior['guidance_rate_pct'] = value
                require(oracle(prior, state, 1) == expected, ('view77 native half-away rounding', value, expected))
    for sign in (-1, 1):
        prior['guidance_rate_pct'] = sign * 0.005
        require(oracle(prior, state, 0.01) == sign * 0.01, 'view77 native rate increment')
    prior.update(guidance_rate_pct=2, guidance_inflation_sensitivity=0.5, four_quarter_inflation_pct=4,
                 guidance_output_gap_sensitivity=-0.25, output_gap_pct=-2, guidance_reference_output_gap_pct=2)
    require(oracle(prior, state, 0.01) == 4, 'view77 previous-state conditional guidance')
    prior['guidance_active'] = False
    require(oracle(prior, state, 0.01) == 3.5, 'view77 inactive guidance uses current applied rate')


VIEW77_CASES = {
    **{f'view77-policy-{name}': 'Policy output cache' for name in (
        'first', 'last', 'missing', 'empty', 'bool', 'string', 'nan', 'infinity', 'text',
        'helper-first', 'helper-last', 'helper-missing', 'helper-bool', 'helper-nan',
        'flow-ending-gdp', 'stock-meeting-gdp', 'helper-coherent', 'helper-only', 'economy-helper-missing', 'economy-helper-bool', 'economy-helper-nan', 'economy-helper-last')},
    **{f'view77-{name}': 'required cell visibility' for name in (
        'lab-row', 'policy-row', 'assumptions-row', 'shocks-row', 'economy-row',
        'lab-col', 'policy-col', 'assumptions-col', 'shocks-col', 'economy-col',
        'policy-last-input', 'policy-last-output', 'policy-output-label', 'assumptions-metadata',
        'shocks-header', 'title-row', 'chart-row', 'chart-col', 'policy-range',
        'zero-height', 'nan-height', 'infinity-height', 'negative-height',
        'zero-width', 'nan-width', 'infinity-width', 'negative-width',
        'default-zero-height', 'default-zero-width', 'default-hidden', 'default-hidden-height-only',
        'bad-row-hidden', 'bad-col-hidden', 'bad-default-hidden', 'overlap-col',
        'wrapped-cols', 'wrapped-col', 'wrapped-row', 'duplicate-format', 'wrapped-format')},
    **{f'view77-{name}': None for name in (
        'policy-spelling', 'policy-shared', 'visible-false', 'visible-zero',
        'missing-defaults', 'positive-overrides', 'default-hidden-overrides',
        'unrelated-unused', 'split-cols', 'policy-wide-column', 'dimension-spelling')},
}
NEW_CASES.update(VIEW77_CASES)


def view77_mutations(source, defect, row_map):
    kind = defect.removeprefix('view77-')
    if kind.startswith('policy-') and kind not in (
            'policy-row', 'policy-col', 'policy-last-input', 'policy-last-output',
            'policy-output-label', 'policy-range', 'policy-wide-column'):
        path = 'xl/worksheets/sheet2.xml'; part = ET.fromstring(source.read(path))
        cells = {cell.get('r'): cell for cell in part.findall('s:sheetData/s:row/s:c', NS)}
        native = json.loads(reference.read_text())
        states = [native['initial_state']] + [q['state'] for q in native['quarters']]
        inventory = json.loads(row_map.with_suffix('.formulas.json').read_text())
        fields, stocks = inventory['policy_output_fields'], set(inventory['ending_stock_fields'])
        def column(n):
            label = ''
            while n:
                n, remainder = divmod(n - 1, 26); label = chr(65 + remainder) + label
            return label
        if kind in ('policy-helper-coherent', 'policy-helper-only', 'policy-economy-helper-missing', 'policy-economy-helper-bool', 'policy-economy-helper-nan', 'policy-economy-helper-last'):
            q = len(states) - 1 if kind == 'policy-economy-helper-last' else 1
            economy_path = 'xl/worksheets/sheet4.xml'; economy = ET.fromstring(source.read(economy_path))
            address = f'{column(q + 4)}{json.loads(row_map.read_text())["prior_commitment"]}'
            helper = economy.find(f's:sheetData/s:row/s:c[@r="{address}"]', NS)
            cache = helper.find('s:v', NS)
            require(cache is not None and helper.find('s:f', NS) is not None, 'view77 requires an actual prior-commitment helper')
            if kind == 'policy-economy-helper-missing': helper.remove(cache)
            elif kind == 'policy-economy-helper-bool': helper.set('t', 'b'); cache.text = '1'
            elif kind == 'policy-economy-helper-nan': cache.text = 'NaN'
            else:
                cache.text = repr(float(cache.text) + 0.25)
                if kind == 'policy-helper-coherent': cells[f'{column(q + 4)}21'].find('s:v', NS).text = cache.text
            changes = {economy_path: ET.tostring(economy, encoding='utf-8', xml_declaration=True)}
            if kind == 'policy-helper-coherent': changes[path] = ET.tostring(part, encoding='utf-8', xml_declaration=True)
            return changes
        address = (f'{column(len(states) + 3)}{21 if kind == 'policy-helper-last' else 39}'
                   if kind in ('policy-last', 'policy-helper-last') else 'E21' if kind.startswith('policy-helper-') else 'E20')
        kind = kind.replace('policy-helper-', 'policy-')
        cell = cells[address]; cache = cell.find('s:v', NS)
        require(cache is not None and cell.find('s:f', NS) is not None, 'view77 requires a saved calculated output')
        if kind in ('policy-flow-ending-gdp', 'policy-stock-meeting-gdp'):
            candidates = []
            for q in range(1, len(states)):
                for i, field in enumerate(fields):
                    if field.endswith('_pct_initial_gdp') and ((field in stocks) == kind.startswith('policy-stock-')):
                        trace = native['quarters'][q - 1]['trace']
                        correct = states[q][field] / trace['ending_nominal_gdp_ratio' if field in stocks else 'decision_nominal_gdp_ratio']
                        wrong = states[q][field] / trace['decision_nominal_gdp_ratio' if field in stocks else 'ending_nominal_gdp_ratio']
                        if abs(correct - wrong) > 1e-6:
                            candidates.append((f'{column(q + 4)}{20 + i}', correct, wrong, q, field))
            require(candidates, 'view77 requires a real nonzero flow/stock with distinct meeting/ending GDP')
            address, correct, wrong, q, field = candidates[0]; cache = cells[address].find('s:v', NS)
            require(abs(float(cache.text) - correct) < 1e-7, 'view77 native unit-conversion fixture')
            cache.text = repr(wrong)
        elif kind == 'policy-missing': cell.remove(cache)
        elif kind == 'policy-empty': cache.text = None
        elif kind in ('policy-bool', 'policy-string'):
            cell.set('t', 'b' if kind == 'policy-bool' else 'str'); cache.text = '1'
        elif kind in ('policy-nan', 'policy-infinity', 'policy-text'):
            cache.text = {'policy-nan': 'NaN', 'policy-infinity': 'INF', 'policy-text': 'wrong'}[kind]
        elif kind == 'policy-spelling':
            cell.attrib.pop('t', None); cache.text = format(float(cache.text), '.17e')
        elif kind == 'policy-shared':
            master = cell.find('s:f', NS); master.set('t', 'shared'); master.set('si', '777001'); master.set('ref', 'E20:F20')
            follower = cells['F20'].find('s:f', NS); follower.text = None; follower.set('t', 'shared'); follower.set('si', '777001')
        else: cache.text = repr(float(cache.text) + 0.25)
        return {path: ET.tostring(part, encoding='utf-8', xml_declaration=True)}
    targets = {
        'lab-row': (1, 4, None), 'policy-row': (2, 6, None), 'assumptions-row': (3, 6, None),
        'shocks-row': (5, 7, None), 'economy-row': (4, 4, None),
        'lab-col': (1, None, 3), 'policy-col': (2, None, 5), 'assumptions-col': (3, None, 3),
        'shocks-col': (5, None, 5), 'economy-col': (4, None, 4),
        'policy-last-input': (2, 14, None), 'policy-last-output': (2, 39, None),
        'policy-output-label': (2, None, 2), 'assumptions-metadata': (3, None, 10),
        'shocks-header': (5, 4, None), 'title-row': (3, 2, None),
        'chart-row': (1, 35, None), 'chart-col': (1, None, 16),
    }
    index, row_index, col_index = targets.get(kind, (2 if kind in ('policy-range', 'policy-wide-column') else 1, 4, 3))
    path = f'xl/worksheets/sheet{index}.xml'; part = ET.fromstring(source.read(path))
    data = part.find('s:sheetData', NS); columns = part.find('s:cols', NS); fmt = part.find('s:sheetFormatPr', NS)
    row = data.find(f's:row[@r="{row_index}"]', NS) if row_index else None
    if row_index and row is None: row = ET.SubElement(data, '{' + NS['s'] + '}row', r=str(row_index))
    col = next((c for c in columns if int(c.get('min')) <= col_index <= int(c.get('max'))), None) if col_index else None
    if kind in targets:
        (row if row_index else col).set('hidden', '1')
    elif kind == 'policy-range':
        columns.clear(); ET.SubElement(columns, '{' + NS['s'] + '}col', min='5', max='52', hidden='1')
    elif kind.endswith('-height') and kind.split('-')[0] in ('zero', 'nan', 'infinity', 'negative'):
        row.set('ht', {'zero': '0', 'nan': 'NaN', 'infinity': 'INF', 'negative': '-1'}[kind.split('-')[0]])
    elif kind.endswith('-width') and kind.split('-')[0] in ('zero', 'nan', 'infinity', 'negative'):
        col.set('width', {'zero': '0', 'nan': 'NaN', 'infinity': 'INF', 'negative': '-1'}[kind.split('-')[0]])
    elif kind == 'default-zero-height':
        fmt.set('defaultRowHeight', '0'); row.attrib.pop('ht', None); row.attrib.pop('customHeight', None)
    elif kind == 'default-zero-width':
        fmt.set('defaultColWidth', '0'); col.attrib.pop('width', None); col.attrib.pop('customWidth', None)
    elif kind in ('default-hidden', 'default-hidden-height-only'):
        fmt.set('zeroHeight', 'true')
        if kind == 'default-hidden': row.attrib.pop('ht', None); row.attrib.pop('customHeight', None)
    elif kind == 'bad-row-hidden': row.set('hidden', 'maybe')
    elif kind == 'bad-col-hidden': col.set('hidden', 'maybe')
    elif kind == 'bad-default-hidden': fmt.set('zeroHeight', 'maybe')
    elif kind == 'overlap-col': ET.SubElement(columns, '{' + NS['s'] + '}col', min='3', max='3', hidden='0', width='15')
    elif kind in ('wrapped-cols', 'wrapped-col', 'wrapped-row', 'wrapped-format'):
        wrapper = ET.SubElement(part, '{' + NS['s'] + '}extLst')
        if kind == 'wrapped-cols': part.remove(columns); wrapper.append(columns)
        elif kind == 'wrapped-col': columns.remove(col); wrapper.append(col)
        elif kind == 'wrapped-row': ET.SubElement(wrapper, '{' + NS['s'] + '}row', r='4', hidden='1')
        else: part.remove(fmt); wrapper.append(fmt)
    elif kind == 'duplicate-format': ET.SubElement(part, '{' + NS['s'] + '}sheetFormatPr', defaultRowHeight='15')
    elif kind in ('visible-false', 'visible-zero'):
        value = 'false' if kind == 'visible-false' else '0'; fmt.set('zeroHeight', value)
        for node in list(data) + list(columns): node.set('hidden', value)
    elif kind == 'missing-defaults':
        part.remove(fmt); row.attrib.pop('ht', None); row.attrib.pop('customHeight', None)
        col.attrib.pop('width', None); col.attrib.pop('customWidth', None)
    elif kind in ('positive-overrides', 'default-hidden-overrides'):
        fmt.set('defaultRowHeight', '0'); fmt.set('defaultColWidth', '0')
        fmt.set('zeroHeight', 'true' if kind == 'default-hidden-overrides' else 'false')
        existing = {int(node.get('r')): node for node in data}
        for r in range(1, 107):
            node = existing.get(r)
            if node is None: node = ET.SubElement(data, '{' + NS['s'] + '}row', r=str(r))
            node.set('ht', '22'); node.set('hidden', 'false')
        for node in columns: node.set('width', '12'); node.set('hidden', 'false')
    elif kind == 'unrelated-unused':
        ET.SubElement(data, '{' + NS['s'] + '}row', r='1000', hidden='1', ht='0')
        ET.SubElement(columns, '{' + NS['s'] + '}col', min='1000', max='1001', hidden='1', width='0')
    elif kind == 'split-cols':
        columns.remove(col); other = ET.Element('{' + NS['s'] + '}cols')
        part.insert(list(part).index(columns) + 1, other); other.append(col)
    elif kind == 'policy-wide-column':
        columns.clear(); ET.SubElement(columns, '{' + NS['s'] + '}col', min='2', max='52', hidden='0', width='12')
    elif kind == 'dimension-spelling': row.set('ht', '+2.200e1'); col.set('width', '+1.500e1')
    else: raise AssertionError(('unknown view77 mutation', defect))
    return {path: ET.tostring(part, encoding='utf-8', xml_declaration=True)}


META89_CASES = {
    **{f'meta89-anchor-{row}-{kind}': 'authored data validation'
       for row in (6, 10) for kind in ('row', 'column', 'both')},
    **{f'meta89-label-{address}': 'authored literal mismatch' for address in
       ('B2', 'B4', 'B6', 'J4', 'J11', 'B12', 'B17', 'D12', 'D17', 'F12', 'F14', 'F16', 'B54', 'B57', 'B58', 'B106')},
    **{f'meta89-economy-{state}': 'interactive worksheet visibility' for state in ('hidden', 'veryHidden')},
    **{f'meta89-{name}': None for name in ('validation-canonical', 'scalar-anchors', 'label-str', 'label-inline',
                                        'label-rich', 'label-shared', 'label-shared-rich', 'economy-default', 'economy-visible')},
}
NEW_CASES.update(META89_CASES)
# Full source capture now catches these same saved-cell defects before chart presentation checks.
NEW_CASES.update({f'chart19-{name}': 'authored literal mismatch'
                  for name in ('header', 'header-formula', 'quarter-label', 'quarter-label-formula')})
NEW_CASES.update({f'chart19-{name}': 'authored formula mismatch' for name in ('source-formula', 'credibility-scale')})


def meta89_mutations(source, defect, row_map):
    kind = defect.removeprefix('meta89-')
    namespace = '{' + NS['s'] + '}'
    if kind.startswith('economy-'):
        part = ET.fromstring(source.read('xl/workbook.xml'))
        record = next(sheet for sheet in part.find('s:sheets', NS) if sheet.get('name') == 'Economy')
        state = kind.removeprefix('economy-')
        if state == 'default': record.attrib.pop('state', None)
        else: record.set('state', state)
        return {'xl/workbook.xml': ET.tostring(part, encoding='utf-8')}
    if kind.startswith('anchor-') or kind == 'validation-canonical':
        path = 'xl/worksheets/sheet2.xml'; part = ET.fromstring(source.read(path))
        rules = part.findall('s:dataValidations/s:dataValidation', NS)
        require(len(rules) == 2, 'meta89 actual Policy rules required')
        if kind == 'validation-canonical':
            for rule in rules:
                formula = rule.find('s:formula1', NS)
                formula.text = ' = ' + formula.text.lower().replace(',', ', ')
        else:
            _, row, anchor = kind.split('-')
            rule = next(rule for rule in rules if rule.get('sqref').startswith('E' + row + ':'))
            formula = rule.find('s:formula1', NS); original = 'E' + row
            require(original in formula.text and '$' not in formula.text, 'meta89 actual source rule is relative')
            formula.text = formula.text.replace(original, {'row': 'E$' + row, 'column': '$E' + row, 'both': '$E$' + row}[anchor])
        return {path: ET.tostring(part, encoding='utf-8')}
    path = 'xl/worksheets/sheet2.xml' if kind == 'scalar-anchors' else 'xl/worksheets/sheet1.xml'
    part = ET.fromstring(source.read(path))
    if kind == 'scalar-anchors':
        formula = part.find('.//s:c[@r="E20"]/s:f', NS)
        require(formula is not None and 'E20' in formula.text, 'meta89 actual scalar Policy formula required')
        formula.text = formula.text.replace('E20', '$E$20')
        return {path: ET.tostring(part, encoding='utf-8')}
    action = kind.removeprefix('label-')
    address = action if re.fullmatch('[A-Z]+[0-9]+', action) else 'B4'
    cell = part.find(f'.//s:c[@r="{address}"]', NS)
    require(cell is not None and cell.find('s:f', NS) is None, 'meta89 actual literal label required')
    original = cell.findtext('s:v', namespaces=NS)
    if cell.get('t') == 'inlineStr': original = ''.join(cell.find('s:is', NS).itertext())
    require(isinstance(original, str), 'meta89 saved label text required')
    attributes = dict(cell.attrib); cell.clear(); cell.attrib.update(attributes)
    changes = {}
    text = original if action in ('str', 'inline', 'rich', 'shared', 'shared-rich') else 'Changed source caption'
    if action in ('inline', 'rich'):
        cell.set('t', 'inlineStr'); inline = ET.SubElement(cell, namespace + 'is')
        for value in ([text] if action == 'inline' else [text[:3], text[3:]]):
            parent = inline if action == 'inline' else ET.SubElement(inline, namespace + 'r')
            ET.SubElement(parent, namespace + 't').text = value
    elif action in ('shared', 'shared-rich'):
        table = ET.fromstring(source.read('xl/sharedStrings.xml')); index = len(table)
        item = ET.SubElement(table, namespace + 'si')
        for value in ([text] if action == 'shared' else [text[:3], text[3:]]):
            parent = item if action == 'shared' else ET.SubElement(item, namespace + 'r')
            ET.SubElement(parent, namespace + 't').text = value
        if table.get('count') is not None: table.set('count', str(int(table.get('count')) + 1))
        if table.get('uniqueCount') is not None: table.set('uniqueCount', str(len(table)))
        changes['xl/sharedStrings.xml'] = ET.tostring(table, encoding='utf-8')
        cell.set('t', 's'); ET.SubElement(cell, namespace + 'v').text = str(index)
    else:
        cell.set('t', 'str'); ET.SubElement(cell, namespace + 'v').text = text
    changes[path] = ET.tostring(part, encoding='utf-8')
    return changes


def validate_cache89_oracles(checker, row_map):
    import ast
    import copy
    import math
    nodes = [node for node in ast.parse(checker.read_text()).body if isinstance(node, ast.FunctionDef)
             and node.name in ('column', 'upstream_cache_expectations')]
    require(len(nodes) == 2, 'cache89 oracle definitions')
    namespace = {'math': math, 'require': require}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(checker), 'exec'), namespace)
    oracle = namespace['upstream_cache_expectations']
    inventory = json.loads(row_map.with_suffix('.formulas.json').read_text())
    layout = inventory['upstream_cache_layout']; start = layout['source_start']; initial = inventory['literal_inputs']
    for selected in range(1, len(inventory['case_order']) + 1):
        inputs = copy.deepcopy(initial); inputs['Policy Lab']['C4'] = selected
        values = oracle(inventory, inputs, 'unit')
        require(all(set(values[sheet]) == set(inventory['upstream_formulas'][sheet]) for sheet in values), 'cache89 exact oracle coverage')
        for row in layout['parameter_rows'].values():
            require(values['Assumptions'][f'D{row}'] == inputs['Assumptions'][f'C{row}'], 'cache89 parameter identity')
        for key, row in layout['shock_rows'].items():
            for q in range(48):
                col = namespace['column'](q + 5); source = inputs['Shocks'][f'{col}{row + selected}']
                require(values['Shocks'][f'{col}{row}'] == ('unchanged' if source is None else source), 'cache89 raw source shock identity')
    for overlay in inventory['checkpoint_inputs']:
        inputs = {sheet: dict(values, **overlay['literals'][sheet]) for sheet, values in initial.items()}
        values = oracle(inventory, inputs, 'unit')
        for row in layout['parameter_rows'].values():
            require(values['Assumptions'][f'D{row}'] == inputs['Assumptions'][f'C{row}'], 'cache89 checkpoint C identity')
    # These six saved overlays have no parameter_overrides; exercise an explicit trusted C override separately.
    inputs = copy.deepcopy(initial)
    key = next(iter(layout['initial_parameter'])); row = layout['parameter_rows'][layout['initial_parameter'][key]]
    inputs['Assumptions'][f'C{row}'] += 0.5
    selected = next(case for case in range(len(inventory['case_order']))
                    if f'D{layout['initial_rows'][key] + case + 1}' not in inputs['Assumptions'])
    inputs['Policy Lab']['C4'] = selected + 1
    values = oracle(inventory, inputs, 'unit')
    require(values['Assumptions'][f'D{row}'] == inputs['Assumptions'][f'C{row}'], 'cache89 overridden parameter identity')
    require(values['Assumptions'][f'D{layout['initial_rows'][key]}'] == inputs['Assumptions'][f'C{row}'], 'cache89 overridden active initial alias')

    inputs = copy.deepcopy(initial); inputs['Assumptions'][f'C{start - 4}'] = 1e9; inputs['Assumptions'][f'C{start - 3}'] = 1
    for i in range(120): inputs['Assumptions'][f'C{start + i}'] = 0
    for weight, expected in ((1, True), (math.nextafter(1 + 1e-12, 1), True), (1 + 1e-12, False)):
        inputs['Assumptions'][f'C{start}'] = weight; values = oracle(inventory, inputs, 'unit')
        require(values['Assumptions'][f'D{start - 1}'] is expected, 'cache89 ladder tolerance boundary')
        require(values['Assumptions'][f'D{start - 2}'] == 0.5, 'cache89 source share units')
    inputs['Assumptions'][f'C{start}'] = -1; inputs['Assumptions'][f'C{start + 1}'] = 2
    require(oracle(inventory, inputs, 'unit')['Assumptions'][f'D{start - 1}'] is False, 'cache89 ladder nonnegative predicate')
    inputs['Assumptions'][f'C{start}'] = True
    require(oracle(inventory, inputs, 'unit')['Assumptions'][f'D{start - 1}'] is False, 'cache89 COUNT excludes boolean')
    for defect in ('missing-formula', 'extra-formula', 'missing-layout-key', 'missing-source-literal'):
        document = copy.deepcopy(inventory); inputs = copy.deepcopy(initial)
        if defect == 'missing-formula': document['upstream_formulas']['Assumptions'].pop('D6')
        elif defect == 'extra-formula': document['upstream_formulas']['Shocks']['BA999'] = '=0'
        elif defect == 'missing-layout-key': document['upstream_cache_layout'].pop('shock_defaults')
        else: inputs['Assumptions'].pop('C6')
        try: oracle(document, inputs, 'unit')
        except AssertionError as error: require('upstream calculated cache inventory' in str(error), ('cache89 fail-closed diagnostic', defect))
        else: raise AssertionError(('cache89 missing refusal', defect))


CACHE89_CASES = {
    **{f'cache89-{target}-{action}': 'upstream calculated cache' for target in
       ('parameter', 'initial', 'share', 'weight', 'shock', 'ladder', 'growth')
       for action in ('wrong', 'missing', 'empty', 'wrong-type', 'nan', 'infinity')},
    **{f'cache89-{target}-wrong': 'upstream calculated cache' for target in
       ('initial-coherent', 'parameter-last', 'initial-last', 'fallback-alias', 'fallback-zero', 'fallback-rstar', 'weight-last', 'shock-last', 'growth-last')},
    **{f'cache89-{name}': None for name in
       ('numeric-spelling', 'numeric-default-type', 'numeric-shared', 'boolean-one',
        'growth-string', 'growth-shared-rich')},
    **{f'cache89-{target}-string': 'upstream calculated cache' for target in
       ('parameter', 'initial', 'share', 'weight', 'shock', 'ladder')},
    'cache89-source-tamper': 'authored literal mismatch',
    'cache89-source-coherent': 'authored literal mismatch',
}
NEW_CASES.update(CACHE89_CASES)


def cache89_mutations(source, defect, row_map):
    name = defect.removeprefix('cache89-')
    inventory = json.loads(row_map.with_suffix('.formulas.json').read_text())
    layout = inventory['upstream_cache_layout']; parameters = layout['parameter_rows']; initials = layout['initial_rows']
    source_start = layout['source_start']; upstream = inventory['upstream_formulas']['Assumptions']
    target, action = name.rsplit('-', 1)
    if name.endswith('-wrong-type'): target, action = name[:-11], 'wrong-type'
    targets = {'parameter': 'D' + str(next(iter(parameters.values()))), 'parameter-last': 'D' + str(list(parameters.values())[-1]),
               'initial': 'D' + str(next(iter(initials.values()))), 'initial-last': 'D' + str(list(initials.values())[-1]),
               'share': f'D{source_start - 2}', 'ladder': f'D{source_start - 1}',
               'weight': f'D{source_start}', 'weight-last': f'D{source_start + 119}',
               'shock': 'E' + str(next(iter(layout['shock_rows'].values()))),
               'shock-last': 'AZ' + str(list(layout['shock_rows'].values())[-1]),
               'growth': 'E' + str(layout['shock_rows']['potential_growth_pct']),
               'growth-last': 'AZ' + str(layout['shock_rows']['potential_growth_pct'])}
    if name == 'initial-coherent-wrong':
        native = json.loads(reference.read_text()); selected = inventory['case_order'].index(native['scenario']['id']) + 1
        key = next(key for key, row in initials.items() if f'D{row + selected}' in upstream)
        target, action = 'initial', 'coherent'; targets['initial'] = f'D{initials[key]}'
        dependent_address = f'D{initials[key] + selected}'
    if target.startswith('fallback-'):
        key = next(iter(layout['initial_parameter'])) if target == 'fallback-alias' else ('r_star_reference_pct' if target == 'fallback-rstar' else 'deferred_demand_pct')
        targets[target] = next(f'D{initials[key] + i}' for i in range(1, layout['case_stride'] - 1)
                               if f'D{initials[key] + i}' in upstream)
    if name in ('numeric-spelling', 'numeric-default-type', 'numeric-shared', 'source-tamper', 'source-coherent'):
        target, action = 'parameter', name
    elif name.startswith('boolean-'): target, action = 'ladder', name
    elif name.startswith('growth-') and name in ('growth-string', 'growth-shared-rich'): target, action = 'growth', name
    path = 'xl/worksheets/sheet5.xml' if target.startswith(('shock', 'growth')) else 'xl/worksheets/sheet3.xml'
    part = ET.fromstring(source.read(path)); namespace = '{' + NS['s'] + '}'
    cells = {c.get('r'): c for c in part.findall('s:sheetData/s:row/s:c', NS)}; address = targets[target]; cell = cells[address]; value = cell.find('s:v', NS)
    require(value is not None and cell.find('s:f', NS) is not None, ('cache89 actual formula/cache', address))
    changes = {}
    if action == 'missing': cell.remove(value)
    elif action == 'empty': value.text = None
    elif action == 'string': cell.set('t', 'str'); value.text = '1'
    elif action == 'coherent':
        value.text = repr(float(value.text) + 0.25); cells[dependent_address].find('s:v', NS).text = value.text
    elif action == 'wrong-type':
        cell.set('t', 'n' if target in ('ladder', 'growth', 'growth-last') else 'b'); value.text = '1'
    elif action in ('nan', 'infinity'):
        cell.set('t', 'n'); value.text = 'NaN' if action == 'nan' else 'INF'
    elif action == 'numeric-spelling': value.text = format(float(value.text), '.17e')
    elif action == 'numeric-default-type': cell.attrib.pop('t', None)
    elif action == 'numeric-shared':
        formula = cell.find('s:f', NS); formula.set('t', 'shared'); formula.set('si', '890001'); formula.set('ref', address)
    elif action in ('source-tamper', 'source-coherent'):
        input_address = 'C' + address[1:]; saved = cells[input_address].find('s:v', NS); saved.text = repr(float(saved.text) + 0.25)
        if action == 'source-coherent': value.text = saved.text
    elif action in ('boolean-one',):
        require(cell.get('t') == 'b' and value.text == '1', 'cache89 genuine true ladder')
        value.text = '1'  # Boolean cache lexical values are 0/1, not XML attribute true/false.
    elif action == 'growth-string':
        require(cell.get('t') == 'str' and value.text == 'unchanged', 'cache89 actual unchanged growth')
    elif action == 'growth-shared-rich':
        require(cell.get('t') == 'str' and value.text == 'unchanged', 'cache89 actual unchanged growth')
        # Reuse the existing shared-string package authoring fixture, retaining this calculated cell's formula.
        changes = upstream77_mutations(source, 'upstream77-metadata-shared-rich', row_map)
        table = ET.fromstring(changes['xl/sharedStrings.xml']); item = table[-1]
        for node in list(item): item.remove(node)
        for text in ('un', 'changed'): ET.SubElement(ET.SubElement(item, namespace + 'r'), namespace + 't').text = text
        changes['xl/sharedStrings.xml'] = ET.tostring(table, encoding='utf-8')
        changes.pop('xl/worksheets/sheet3.xml')
        cell.set('t', 's'); value.text = str(len(table) - 1)
    elif target == 'ladder': value.text = '0'
    elif target.startswith('growth'):
        cell.set('t', 'str'); value.text = 'changed'
    else: value.text = repr(float(value.text) + 0.25)
    changes[path] = ET.tostring(part, encoding='utf-8', xml_declaration=True)
    return changes


DISPLAY105_CASES = {
    **{f'cf105-{name}': 'unsupported workbook formula' for name in ('attribute-webservice', 'attribute-dde', 'x14-attribute')},
    **{f'cf105-{name}': 'unsupported conditional formatting' for name in ('attribute-benign', 'attribute-quoted', 'dxf', 'x14-dxf', 'hide-values')},
    **{f'style105-{name}': 'required cell display style' for name in (
        'input-format', 'label-format', 'output-format', 'economy-format', 'constant-format', 'quoted-format',
        'label-white-font', 'input-same-paint', 'font-tiny', 'font-symbols', 'gradient-fill',
        'inherited-format', 'inherited-font', 'inherited-fill', 'row-hidden', 'column-hidden',
        'bad-cell-index', 'bad-row-index', 'bad-column-index', 'bad-parent-index', 'bad-font-index',
        'bad-fill-index', 'bad-format-index', 'builtin-collision', 'duplicate-format', 'duplicate-font-color',
        'ambiguous-inheritance', 'shrink-text', 'rotated-text', 'inline-run-color', 'shared-run-color',
        'checkbox-output', 'checkbox-bag', 'checkbox-parent')},
    **{f'style105-{name}': None for name in (
        'duplicate-xf', 'reindex-tables', 'builtin-equivalent', 'custom-format-reindex', 'lowercase-rgb',
        'explicit-auto-font', 'inherited-equivalent', 'row-equivalent', 'column-equivalent', 'alignment-defaults', 'checkbox-bag-reindex')},
}
DISPLAY105_CASES.update({'style105-inactive-row-over-column': 'required cell display style',
                         'style105-active-row-over-column': None})
NEW_CASES.update(DISPLAY105_CASES)


def display105_mutations(source, defect, row_map):
    import copy
    namespace = '{' + NS['s'] + '}'
    if defect in ('style105-inactive-row-over-column', 'style105-active-row-over-column'):
        changes = display105_mutations(source, 'style105-column-hidden', row_map)
        path = 'xl/worksheets/sheet1.xml'; part = ET.fromstring(changes[path])
        original = ET.fromstring(source.read(path)).find('s:sheetData/s:row/s:c[@r="C4"]', NS)
        row = part.find('s:sheetData/s:row[@r="4"]', NS)
        row.set('s', original.get('s', '0')); row.attrib.pop('customFormat', None)
        if defect == 'style105-active-row-over-column': row.set('customFormat', '1')
        changes[path] = ET.tostring(part, encoding='utf-8')
        return changes
    if defect.startswith('cf105-'):
        path = 'xl/worksheets/sheet1.xml'; part = ET.fromstring(source.read(path))
        extended = defect in ('cf105-x14-attribute', 'cf105-x14-dxf')
        ns = '{http://schemas.microsoft.com/office/spreadsheetml/2009/9/main}' if extended else namespace
        parent = part
        if extended:
            parent = ET.SubElement(ET.SubElement(ET.SubElement(part, namespace + 'extLst'), namespace + 'ext', uri='{105}'), ns + 'conditionalFormattings')
        formatting = ET.SubElement(parent, ns + 'conditionalFormatting', sqref='C4')
        if defect.endswith('dxf'):
            rule = ET.SubElement(formatting, ns + 'cfRule', type='expression', priority='1', dxfId='0')
            ET.SubElement(rule, '{http://schemas.microsoft.com/office/excel/2006/main}f' if extended else namespace + 'formula').text = 'ISNUMBER(C4)'
        else:
            rule = ET.SubElement(formatting, ns + 'cfRule', type='dataBar' if defect.endswith('hide-values') else 'colorScale', priority='1')
            scale = ET.SubElement(rule, ns + ('dataBar' if defect.endswith('hide-values') else 'colorScale'))
            if defect.endswith('hide-values'): scale.set('showValue', '0')
            value = {'cf105-attribute-dde': "'server'|'topic'!A1", 'cf105-attribute-benign': 'IF(C4>0,1,0)',
                     'cf105-attribute-quoted': 'IF("WEBSERVICE(""https://example.invalid/"")"="text",1,0)',
                     'cf105-hide-values': 'C4'}.get(defect, 'WEBSERVICE("https://example.invalid/105")')
            ET.SubElement(scale, ns + 'cfvo', type='formula', val=value)
            ET.SubElement(scale, ns + 'cfvo', type='max')
            ET.SubElement(scale, ns + 'color', rgb='FF000000'); ET.SubElement(scale, ns + 'color', rgb='FFFFFFFF')
        return {path: ET.tostring(part, encoding='utf-8')}
    if defect in ('style105-checkbox-bag', 'style105-checkbox-bag-reindex'):
        path = 'xl/featurePropertyBag/featurePropertyBag.xml'; bags = ET.fromstring(source.read(path))
        if defect == 'style105-checkbox-bag':
            next(node for node in bags if node.get('type') == 'Checkbox').set('type', 'Button')
        else:
            before = list(bags); bags[:] = before[::-1]
            for node in bags.iter():
                if node.tag.endswith('}bagId'): node.text = str(len(before) - 1 - int(node.text))
        return {path: ET.tostring(bags, encoding='utf-8')}
    styles = ET.fromstring(source.read('xl/styles.xml'))
    xfs = styles.find('s:cellXfs', NS); parents = styles.find('s:cellStyleXfs', NS)
    fonts = styles.find('s:fonts', NS); fills = styles.find('s:fills', NS); formats = styles.find('s:numFmts', NS)
    target = {'style105-label-format': (1, 'B4'), 'style105-label-white-font': (1, 'B4'),
              'style105-output-format': (2, 'E20'), 'style105-economy-format': (4, 'E6')}.get(defect, (1, 'C4'))
    if defect == 'style105-constant-format':
        inputs = json.loads(row_map.with_suffix('.formulas.json').read_text())['upstream_cache_layout']['parameter_rows']
        target = (3, 'C' + str(inputs['inflation_target_pct']))
    path = f'xl/worksheets/sheet{target[0]}.xml'; part = ET.fromstring(source.read(path))
    cell = part.find(f'.//s:c[@r="{target[1]}"]', NS); require(cell is not None, 'style105 requires an actual source cell')
    if defect in ('style105-checkbox-output', 'style105-checkbox-parent'):
        policy = ET.fromstring(source.read('xl/worksheets/sheet2.xml'))
        checkbox = policy.find('.//s:c[@r="E12"]', NS).get('s')
        if defect == 'style105-checkbox-output':
            policy.find('.//s:c[@r="E20"]', NS).set('s', checkbox)
            return {'xl/worksheets/sheet2.xml': ET.tostring(policy, encoding='utf-8')}
        parent = copy.deepcopy(xfs[int(checkbox)]); parent.attrib.pop('xfId', None)
        parents.append(parent); parents.set('count', str(len(parents)))
        return {'xl/styles.xml': ET.tostring(styles, encoding='utf-8')}
    original = xfs[int(cell.get('s', '0'))]; xf = copy.deepcopy(original)
    def add(table, node):
        index = len(table); table.append(node); table.set('count', str(len(table))); return str(index)
    def hidden_format(code=';;;'):
        index = max([164] + [int(node.get('numFmtId')) + 1 for node in formats])
        ET.SubElement(formats, namespace + 'numFmt', numFmtId=str(index), formatCode=code)
        formats.set('count', str(len(formats))); xf.set('numFmtId', str(index)); xf.set('applyNumberFormat', '1')
    if defect in ('style105-inline-run-color', 'style105-shared-run-color'):
        path = 'xl/worksheets/sheet1.xml'; part = ET.fromstring(source.read(path)); cell = part.find('.//s:c[@r="B4"]', NS)
        text = cell.findtext('s:v', namespaces=NS); require(text == 'Case number', 'style105 saved label')
        if defect == 'style105-shared-run-color':
            changes = upstream77_mutations(source, 'upstream77-metadata-shared-rich', row_map)
            table = ET.fromstring(changes['xl/sharedStrings.xml']); item = table[-1]
            for node in list(item): item.remove(node)
            cell.set('t', 's'); cell.find('s:v', NS).text = str(len(table) - 1)
        else:
            changes = {}; cell.set('t', 'inlineStr')
            for node in list(cell): cell.remove(node)
            item = ET.SubElement(cell, namespace + 'is')
        run = ET.SubElement(item, namespace + 'r'); properties = ET.SubElement(run, namespace + 'rPr')
        ET.SubElement(properties, namespace + 'color', rgb='FFFFFFFF'); ET.SubElement(run, namespace + 't').text = text
        if defect == 'style105-shared-run-color':
            changes.pop('xl/worksheets/sheet3.xml'); changes['xl/sharedStrings.xml'] = ET.tostring(table, encoding='utf-8')
        changes[path] = ET.tostring(part, encoding='utf-8'); return changes
    if defect == 'style105-reindex-tables':
        for table, attribute in [(fonts, 'fontId'), (fills, 'fillId')]:
            old = list(table); table[:] = old[::-1]
            for record in list(xfs) + list(parents): record.set(attribute, str(len(old) - 1 - int(record.get(attribute, '0'))))
        old = list(xfs); xfs[:] = old[::-1]; changes = {'xl/styles.xml': ET.tostring(styles, encoding='utf-8')}
        for name in source.namelist():
            if name.startswith('xl/worksheets/') and name.endswith('.xml'):
                sheet = ET.fromstring(source.read(name))
                for node in sheet.findall('.//s:c', NS): node.set('s', str(len(old) - 1 - int(node.get('s', '0'))))
                for node in sheet.findall('s:sheetData/s:row', NS):
                    if node.get('s') is not None: node.set('s', str(len(old) - 1 - int(node.get('s'))))
                for node in sheet.findall('s:cols/s:col', NS):
                    if node.get('style') is not None: node.set('style', str(len(old) - 1 - int(node.get('style'))))
                changes[name] = ET.tostring(sheet, encoding='utf-8')
        return changes
    if defect == 'style105-builtin-equivalent':
        ids = {node.get('numFmtId') for node in formats if node.get('formatCode') == '0.00'}
        for record in list(xfs) + list(parents):
            if record.get('numFmtId') in ids: record.set('numFmtId', '2')
    elif defect == 'style105-custom-format-reindex':
        mapping = {node.get('numFmtId'): str(450 + i) for i, node in enumerate(formats)}
        for node in formats: node.set('numFmtId', mapping[node.get('numFmtId')])
        for record in list(xfs) + list(parents):
            if record.get('numFmtId') in mapping: record.set('numFmtId', mapping[record.get('numFmtId')])
    elif defect == 'style105-lowercase-rgb':
        for node in styles.iter():
            if node.get('rgb'): node.set('rgb', node.get('rgb').lower())
    elif defect == 'style105-explicit-auto-font':
        ET.SubElement(fonts[0], namespace + 'color', auto='true')
    else:
        if defect.endswith('-format') and defect not in ('style105-inherited-format',):
            hidden_format('"";"";"";""' if defect == 'style105-quoted-format' else ';;;')
        elif defect in ('style105-label-white-font', 'style105-input-same-paint', 'style105-font-tiny', 'style105-font-symbols', 'style105-duplicate-font-color'):
            font = copy.deepcopy(fonts[int(xf.get('fontId'))]); color = font.find('s:color', NS)
            if color is None: color = ET.SubElement(font, namespace + 'color')
            if defect == 'style105-label-white-font': color.set('rgb', 'FFFFFFFF')
            elif defect == 'style105-input-same-paint': color.set('rgb', 'FFFFF2CC')
            elif defect == 'style105-font-tiny': font.find('s:sz', NS).set('val', '0.01')
            elif defect == 'style105-font-symbols': font.find('s:name', NS).set('val', 'Wingdings')
            else: ET.SubElement(font, namespace + 'color', rgb='FFFFFFFF')
            xf.set('fontId', add(fonts, font)); xf.set('applyFont', '1')
        elif defect == 'style105-gradient-fill':
            fill = ET.Element(namespace + 'fill'); ET.SubElement(fill, namespace + 'gradientFill')
            xf.set('fillId', add(fills, fill)); xf.set('applyFill', '1')
        elif defect.startswith('style105-inherited-'):
            parent = copy.deepcopy(xf); parent.attrib.pop('xfId', None)
            if defect == 'style105-inherited-format': hidden_format(); parent.set('numFmtId', xf.get('numFmtId'))
            elif defect == 'style105-inherited-font':
                font = copy.deepcopy(fonts[int(xf.get('fontId'))]); font.find('s:color', NS).set('rgb', 'FFFFFFFF'); parent.set('fontId', add(fonts, font))
            elif defect == 'style105-inherited-fill':
                fill = ET.Element(namespace + 'fill'); ET.SubElement(ET.SubElement(fill, namespace + 'patternFill', patternType='solid'), namespace + 'fgColor', rgb='FF2257A0'); parent.set('fillId', add(fills, fill))
            xf.set('xfId', add(parents, parent))
            for key, attribute in [('Font', 'fontId'), ('Fill', 'fillId'), ('NumberFormat', 'numFmtId'), ('Border', 'borderId')]:
                xf.attrib.pop(attribute, None); xf.set('apply' + key, '0')
            for node in list(xf): xf.remove(node)
            xf.set('applyAlignment', '0')
        elif defect in ('style105-row-hidden', 'style105-column-hidden'): hidden_format()
        elif defect == 'style105-bad-parent-index': xf.set('xfId', str(len(parents)))
        elif defect == 'style105-bad-font-index': xf.set('fontId', str(len(fonts)))
        elif defect == 'style105-bad-fill-index': xf.set('fillId', str(len(fills)))
        elif defect == 'style105-bad-format-index': xf.set('numFmtId', '98765')
        elif defect == 'style105-builtin-collision': ET.SubElement(formats, namespace + 'numFmt', numFmtId='0', formatCode=';;;'); formats.set('count', str(len(formats)))
        elif defect == 'style105-duplicate-format': formats.append(copy.deepcopy(formats[0])); formats.set('count', str(len(formats)))
        elif defect == 'style105-ambiguous-inheritance': xf.set('applyFont', '0')
        elif defect in ('style105-shrink-text', 'style105-rotated-text', 'style105-alignment-defaults'):
            node = xf.find('s:alignment', NS)
            if node is None: node = ET.SubElement(xf, namespace + 'alignment')
            if defect == 'style105-shrink-text': node.set('shrinkToFit', '1')
            elif defect == 'style105-rotated-text': node.set('textRotation', '255')
            else: node.set('shrinkToFit', 'false'); node.set('textRotation', '0'); node.set('indent', '0'); node.set('wrapText', 'false')
        index = add(xfs, xf); cell.set('s', index)
        if defect in ('style105-row-hidden', 'style105-row-equivalent', 'style105-bad-row-index'):
            cell.attrib.pop('s'); row = part.find('s:sheetData/s:row[@r="4"]', NS)
            row.set('s', str(len(xfs)) if defect == 'style105-bad-row-index' else index); row.set('customFormat', '1')
        elif defect in ('style105-column-hidden', 'style105-column-equivalent', 'style105-bad-column-index'):
            cell.attrib.pop('s'); node = next(n for n in part.findall('s:cols/s:col', NS) if int(n.get('min')) <= 3 <= int(n.get('max')))
            node.set('style', str(len(xfs)) if defect == 'style105-bad-column-index' else index)
        elif defect == 'style105-bad-cell-index': cell.set('s', '-1')
    return {path: ET.tostring(part, encoding='utf-8'), 'xl/styles.xml': ET.tostring(styles, encoding='utf-8')}


DISPLAY142_CASES = {
    **{f'display142-formula-{name}': None for name in ('quote', 'case', 'whitespace', 'anchors', 'shared', 'credibility-shared')},
    **{f'display142-label-{name}': 'authored literal mismatch' for name in ('state', 'helper')},
    **{f'display142-label-{name}': None for name in ('inline', 'shared', 'rich')},
    'display142-wrong-reference': 'authored formula mismatch',
    'display142-missing-scale': 'authored formula mismatch',
    'display142-wrong-cache': 'dashboard source cache parity',
}
NEW_CASES.update(DISPLAY142_CASES)


def display142_mutations(source, defect, row_map):
    namespace = '{' + NS['s'] + '}'
    label = defect.startswith('display142-label-')
    path = 'xl/worksheets/sheet4.xml' if label else 'xl/worksheets/sheet1.xml'
    part = ET.fromstring(source.read(path)); changes = {}
    address = 'B6' if label else ('K58' if defect in ('display142-formula-credibility-shared', 'display142-missing-scale') else 'C58')
    if defect == 'display142-label-helper':
        address = 'B' + str(json.loads(row_map.read_text())['net_rrp_collateral_credit_0'])
    cell = part.find(f'.//s:c[@r="{address}"]', NS)
    require(cell is not None, 'display142 actual saved target')
    if label:
        value = cell.find('s:v', NS); require(cell.get('t') == 'str' and value is not None, 'display142 actual scalar label')
        original = value.text
        if defect in ('display142-label-state', 'display142-label-helper'):
            value.text = 'four quarter inflation (%)' if defect.endswith('state') else 'unrelated helper label'
            require(value.text != original, 'display142 label must change')
        elif defect == 'display142-label-inline':
            cell.set('t', 'inlineStr'); cell.remove(value)
            ET.SubElement(ET.SubElement(cell, namespace + 'is'), namespace + 't').text = original
        else:
            changes = upstream77_mutations(source, 'upstream77-metadata-shared-rich', row_map)
            changes.pop('xl/worksheets/sheet3.xml')
            table = ET.fromstring(changes['xl/sharedStrings.xml']); item = table[-1]
            for node in list(item): item.remove(node)
            if defect == 'display142-label-rich':
                for text in (original[:len(original) // 2], original[len(original) // 2:]):
                    run = ET.SubElement(item, namespace + 'r'); ET.SubElement(run, namespace + 'rPr')
                    ET.SubElement(run, namespace + 't').text = text
            else:
                ET.SubElement(item, namespace + 't').text = original
            changes['xl/sharedStrings.xml'] = ET.tostring(table, encoding='utf-8')
            cell.set('t', 's'); value.text = str(len(table) - 1)
    else:
        formula = cell.find('s:f', NS); require(formula is not None, 'display142 actual plot formula')
        if defect == 'display142-wrong-reference': formula.text = "'Economy'!D14"
        elif defect == 'display142-missing-scale':
            require(formula.text.endswith('*100'), 'display142 original credibility scale'); formula.text = formula.text.removesuffix('*100')
        elif defect == 'display142-wrong-cache':
            value = cell.find('s:v', NS); value.text = repr(float(value.text) + 1)
        else:
            formula.text = {'display142-formula-quote': 'Economy!D13',
                            'display142-formula-case': "'economy'!d13",
                            'display142-formula-whitespace': "  'Economy'! D13  ",
                            'display142-formula-anchors': 'Economy!$D$13',
                            'display142-formula-shared': 'Economy!$D$13',
                            'display142-formula-credibility-shared': " 'economy'!$D$38 * 100 "}.get(defect)
            if defect == 'display142-formula-credibility-shared':
                row = json.loads(row_map.read_text())['credibility']; formula.text = f" 'economy'!$D${row} * 100 "
            if defect.endswith('shared'):
                # The plot transposes source columns into rows; a singleton shared group preserves its exact expression.
                used = [int(node.get('si')) for node in part.findall('.//s:f', NS) if node.get('t') == 'shared']
                formula.set('t', 'shared'); formula.set('si', str(max(used, default=-1) + 1)); formula.set('ref', address)
    changes[path] = ET.tostring(part, encoding='utf-8')
    return changes


def review_mutations(source, defect, row_map):
    if defect in DISPLAY142_CASES:
        return display142_mutations(source, defect, row_map)
    if defect in DISPLAY105_CASES:
        return display105_mutations(source, defect, row_map)
    if defect in CACHE89_CASES:
        return cache89_mutations(source, defect, row_map)
    if defect in META89_CASES:
        return meta89_mutations(source, defect, row_map)
    if defect in VIEW77_CASES:
        return view77_mutations(source, defect, row_map)
    if defect in UPSTREAM77_CASES:
        return upstream77_mutations(source, defect, row_map)
    if defect in INPUT72_CASES:
        return input72_mutations(source, defect, row_map)
    if defect in LABEL60_CASES:
        return label60_mutations(source, defect, row_map)
    if defect in DISPLAY58_CASES:
        return display58_mutations(source, defect, row_map)
    if defect in INTERACTION54_CASES:
        return interaction54_mutations(source, defect, row_map)
    if defect.startswith('input54-'):
        return input54_mutations(source, defect, row_map)
    if defect in CHART45_CASES:
        return chart45_mutations(source, defect, row_map)
    if defect in CHART19_CASES:
        return chart19_mutations(source, defect, row_map)
    if defect not in NEW_CASES and defect not in CAMPAIGN_CASES:
        return {}
    content_types = ET.fromstring(source.read('[Content_Types].xml'))
    rel_namespace = '{http://schemas.openxmlformats.org/package/2006/relationships}'
    if defect.startswith('numeric-'):
        path = 'xl/worksheets/sheet4.xml'; part = ET.fromstring(source.read(path))
        cell = part.find('.//s:c[@r="D6"]', NS)
        require(cell is not None and cell.findtext('s:v', namespaces=NS) == '100', 'Numeric type mutation requires native opening price level')
        if defect == 'numeric-default-type':
            cell.attrib.pop('t', None)
        else:
            cell.set('t', {'numeric-shared-type':'s', 'numeric-string-type':'str', 'numeric-boolean-type':'b', 'numeric-unknown-type':'unknown', 'numeric-explicit-type':'n'}[defect])
        return {path:ET.tostring(part, encoding='utf-8')}
    if defect in CAMPAIGN_CASES:
        import copy
        path = 'xl/worksheets/sheet5.xml'; part = ET.fromstring(source.read(path))
        address = scenario_mutation_targets(row_map)['campaign-note']
        cell = part.find(f'.//s:c[@r="{address}"]', NS)
        require(cell is not None and cell.get('t') == 'str', 'Campaign mutation requires the actual saved string note')
        note = cell.findtext('s:v', namespaces=NS)
        require(note and note.startswith('Recurring crises: '), 'Campaign mutation requires the actual explanation')
        for child in list(cell):
            cell.remove(child)
        namespace = '{' + NS['s'] + '}'
        def string_item(tag, rich):
            item = ET.Element(namespace + tag)
            if rich:
                for text in (note[:19], note[19:]):
                    run = ET.SubElement(item, namespace + 'r')
                    ET.SubElement(run, namespace + 'rPr')
                    ET.SubElement(run, namespace + 't').text = text
            else:
                ET.SubElement(item, namespace + 't').text = note
            return item
        if defect.startswith('campaign-shared-'):
            cell.set('t', 's')
            ET.SubElement(cell, namespace + 'v').text = {
                'campaign-shared-negative': '-1', 'campaign-shared-outside': '1',
                'campaign-shared-fraction': '0.0', 'campaign-shared-plus-zero': '+00',
            }.get(defect, '0')
            table = ET.Element(namespace + 'sst', count='1', uniqueCount='1')
            table.append(string_item('si', defect == 'campaign-shared-rich'))
            if defect == 'campaign-shared-wrong-root':
                table.tag = '{urn:unsupported}sst'
            elif defect == 'campaign-shared-wrong-si':
                table[0].tag = '{urn:unsupported}si'
            elif defect == 'campaign-shared-wrapped-text':
                text = table[0][0]; table[0].remove(text)
                ET.SubElement(table[0], '{urn:unsupported}wrapper').append(text)
            elif defect == 'campaign-shared-mixed-text':
                run = ET.SubElement(table[0], namespace + 'r'); ET.SubElement(run, namespace + 't').text = ''
            rels = ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))
            edge = next(rel for rel in rels if rel.get('Type') == NS['r'] + '/sharedStrings')
            if defect == 'campaign-shared-disconnected':
                rels.remove(edge)
            elif defect == 'campaign-shared-wrong-rel-type':
                edge.set('Type', NS['r'] + '/styles')
            elif defect == 'campaign-shared-duplicate-edge':
                duplicate = copy.deepcopy(edge); duplicate.set('Id', 'duplicate-shared'); rels.append(duplicate)
            table_path = 'xl/sharedStrings.xml'
            if defect == 'campaign-shared-relative-renamed':
                table_path = 'xl/strings/SharedTable.xml'; edge.set('Target', 'strings/SharedTable.xml')
                declaration = next(item for item in content_types if item.get('PartName') == '/xl/sharedStrings.xml')
                declaration.set('PartName', '/' + table_path)
            elif defect == 'campaign-shared-wrong-content-type':
                declaration = next(item for item in content_types if item.get('PartName') == '/xl/sharedStrings.xml')
                declaration.set('ContentType', 'application/xml')
            return {path: ET.tostring(part, encoding='utf-8'), table_path: ET.tostring(table, encoding='utf-8'),
                    'xl/_rels/workbook.xml.rels': ET.tostring(rels, encoding='utf-8'),
                    '[Content_Types].xml': ET.tostring(content_types, encoding='utf-8')}
        cell.set('t', 'inlineStr')
        inline = string_item('is', defect == 'campaign-inline-rich'); cell.append(inline)
        if defect in ('campaign-numeric-inline', 'campaign-boolean-inline', 'campaign-missing-type-inline', 'campaign-unknown-inline'):
            cell.set('t', {'campaign-numeric-inline': 'n', 'campaign-boolean-inline': 'b', 'campaign-unknown-inline': 'unsupported'}.get(defect, 'n'))
            if defect == 'campaign-missing-type-inline':
                cell.attrib.pop('t')
            ET.SubElement(cell, namespace + 'v').text = '0'
        elif defect == 'campaign-str-inline-ambiguous':
            cell.set('t', 'str'); ET.SubElement(cell, namespace + 'v').text = note
        elif defect == 'campaign-inline-wrong-is':
            inline.tag = '{urn:unsupported}is'
        elif defect == 'campaign-inline-wrapped-text':
            text = inline[0]; inline.remove(text); ET.SubElement(inline, '{urn:unsupported}wrapper').append(text)
        return {path: ET.tostring(part, encoding='utf-8')}
    if defect.startswith('formula19-'):
        path = 'xl/worksheets/sheet4.xml'; part = ET.fromstring(source.read(path))
        namespace = '{' + NS['s'] + '}'
        cells = {cell.get('r'): cell for cell in part.findall('s:sheetData/s:row/s:c', NS)}
        rows = json.loads(row_map.read_text())
        if defect.startswith('formula19-xm-'):
            extensions = part.find('s:extLst', NS)
            if extensions is None:
                extensions = ET.SubElement(part, namespace + 'extLst')
            extension = ET.SubElement(extensions, namespace + 'ext', uri='{78C0D931-6437-407D-A8EE-F0AAD7539E65}')
            x14 = '{http://schemas.microsoft.com/office/spreadsheetml/2009/9/main}'
            formatting = ET.SubElement(extension, x14 + 'conditionalFormattings')
            conditional = ET.SubElement(formatting, x14 + 'conditionalFormatting')
            rule = ET.SubElement(conditional, x14 + 'cfRule', type='expression', priority='1', id='{00000000-0000-0000-0000-000000000019}')
            formula = ET.SubElement(rule, '{http://schemas.microsoft.com/office/excel/2006/main}f')
            formula.text = {'formula19-xm-webservice': 'WEBSERVICE("https://example.invalid/")',
                            'formula19-xm-dde': "'server'|'topic'!A1",
                            'formula19-xm-benign': 'AND(E6>0,ISNUMBER(E6))',
                            'formula19-xm-string': 'IF("WEBSERVICE(""https://example.invalid/"")"="text",1,0)'}[defect]
        else:
            address = 'E' + str(rows['actual_output_index'])
            if defect == 'formula19-split-number':
                address = 'D' + str(rows['actual_output_index'])
            elif defect == 'formula19-split-comparison':
                address = 'E' + str(rows['policy_valid'])
            elif defect == 'formula19-zero-helper':
                address = 'E' + str(rows['net_bank_credit_0']) if 'net_bank_credit_0' in rows else 'E' + str(next(v for k,v in rows.items() if k.startswith('net_') and k.endswith('credit_0')))
            elif defect == 'formula19-cold-wrong-zero':
                address = 'D' + str(rows['sterilized_treasury_cohorts_pct_initial_gdp_0'])
            elif defect == 'formula19-short-suffix':
                address = 'AZ' + str(rows['price_h4'])
            elif defect.startswith('formula19-shared-'):
                address = ('F' if defect == 'formula19-shared-backward' else 'E') + str(rows['potential_growth_pct'] if defect == 'formula19-shared-quoted-string' else rows['treasury_cohorts_pct_initial_gdp_0'])
            cell = cells[address]; formula = cell.find('s:f', NS)
            require(formula is not None, 'formula19 requires an actual authored formula')
            if defect.startswith('formula19-shared-'):
                row = re.sub('[A-Z]', '', address)
                formula.set('t', 'shared'); formula.set('si', '999991'); formula.set('ref', 'E' + row + ':F' + row)
                follower = cells[('E' if address.startswith('F') else 'F') + row].find('s:f', NS)
                require(follower is not None, 'formula19 requires the actual shared-equivalent follower')
                follower.set('t', 'shared'); follower.set('si', '999991'); follower.text = None
                if defect == 'formula19-shared-wrong-master':
                    formula.text = '0'
            elif defect in ('formula19-split-number', 'formula19-split-comparison'):
                before, after = ('-100', '-1 00') if defect == 'formula19-split-number' else ('>=', '> =')
                require(before in formula.text, 'Split-token fixture must change an authored token')
                formula.text = formula.text.replace(before, after, 1)
            elif defect == 'formula19-scalar-format':
                formula.text = ' = ' + formula.text.lower().replace(',', ', ')
            else:
                formula.text = '1' if defect == 'formula19-cold-wrong-zero' else 'D4+1' if defect == 'formula19-safe-wrong-state' else '0'
        return {path: ET.tostring(part, encoding='utf-8')}
    if defect.startswith('upstream45-'):
        path = 'xl/worksheets/sheet5.xml' if '-shock-' in defect else 'xl/worksheets/sheet3.xml'
        part = ET.fromstring(source.read(path)); cells = {cell.get('r'): cell for cell in part.findall('s:sheetData/s:row/s:c', NS)}
        if defect == 'upstream45-parameter':
            address = 'D6'
        elif defect == 'upstream45-initial':
            address = next(cell.get('r') for cell in cells.values() if "CHOOSE('Policy Lab'!$C$4" in cell.findtext('s:f', '', NS))
        elif defect in ('upstream45-source-check', 'upstream45-source-weight'):
            check = next(cell for cell in cells.values() if 'COUNT(' in (cell.findtext('s:f', '', NS)))
            address = check.get('r') if defect.endswith('check') else 'D' + str(int(check.get('r')[1:]) + 1)
        else:
            address = scenario_mutation_targets(row_map)['shock-last-formula'] if defect == 'upstream45-shock-last' else 'F6' if defect == 'upstream45-shock-shared-backward' else 'E6'
        cell = cells[address]; formula = cell.find('s:f', NS)
        require(formula is not None, 'upstream45 must mutate the actual upstream authored formula')
        if '-shared' in defect:
            formula.set('t', 'shared'); formula.set('si', '999945'); formula.set('ref', 'E6:F6')
            follower = cells['E6' if address == 'F6' else 'F6'].find('s:f', NS)
            require(follower is not None, 'upstream45 shared form requires an actual follower')
            follower.text = None; follower.set('t', 'shared'); follower.set('si', '999945')
            if defect.endswith('wrong'):
                formula.text = '0'
        elif defect == 'upstream45-shock-scalar':
            formula.text = ' = ' + formula.text.replace(',', ', ')
        else:
            formula.text = '0'
        return {path: ET.tostring(part, encoding='utf-8')}
    if defect.startswith('types-'):
        field = 'PartName' if defect == 'types-double-slash-override' else 'Extension'
        value = '/xl/worksheets/sheet1.xml' if field == 'PartName' else 'xml' if defect == 'types-slash-xml' else 'rels'
        part = next(item for item in content_types if item.get(field) == value)
        part.set(field, '/' + value)
        return {'[Content_Types].xml':ET.tostring(content_types, encoding='utf-8')}
    if defect.startswith('cells-'):
        import copy
        path = 'xl/worksheets/sheet1.xml' if defect.startswith('cells-policy-') else 'xl/worksheets/sheet4.xml'
        part = ET.fromstring(source.read(path)); data = part.find('s:sheetData', NS)
        require(data is not None, 'Cell mutation requires actual sheetData')
        address = 'C58' if defect.startswith('cells-policy-') else 'E' + str(json.loads(row_map.read_text())['actual_output_index'])
        cell = part.find('.//s:c[@r="' + address + '"]', NS)
        require(cell is not None, 'Cell mutation requires actual output')
        row = next(row for row in data if cell in list(row))
        if defect.startswith('cells-policy-'):
            child = cell if defect == 'cells-policy-wrong-cell' else cell.find('s:f' if defect.endswith('formula') else 's:v', NS)
            require(child is not None, 'Policy Lab boundary requires an actual formula/cache')
            if '-nested-' in defect:
                ET.SubElement(child, '{urn:unsupported}payload').text = 'ignored'
            else:
                child.tag = '{urn:unsupported}' + child.tag.rsplit('}', 1)[-1]
        elif defect == 'cells-orphan-container':
            data.tag = '{urn:unsupported}sheetData'
        elif defect == 'cells-orphan-row':
            row.tag = '{urn:unsupported}row'
        elif defect == 'cells-duplicate-address':
            row.append(copy.deepcopy(cell))
        elif defect == 'cells-duplicate-row':
            ET.SubElement(data, '{' + NS['s'] + '}row', r=row.get('r'))
        elif defect == 'cells-row-mismatch':
            row.set('r', '999999')
        else:
            ET.SubElement(cell, '{' + NS['s'] + '}' + ('f' if defect == 'cells-duplicate-formula' else 'v')).text = '0'
        return {path:ET.tostring(part, encoding='utf-8')}
    if defect.startswith('metadata-'):
        import copy
        if defect in ('metadata-default-type', 'metadata-sheet-type', 'metadata-relationship-type', 'metadata-duplicate-default', 'metadata-duplicate-override'):
            if defect in ('metadata-sheet-type', 'metadata-duplicate-override'):
                entry = next(part for part in content_types if part.get('PartName') == '/xl/worksheets/sheet1.xml')
            else:
                entry = next(part for part in content_types if part.get('Extension') == ('rels' if defect == 'metadata-relationship-type' else 'xml'))
            if defect.startswith('metadata-duplicate-'):
                entry = copy.deepcopy(entry)
                field = 'Extension' if defect == 'metadata-duplicate-default' else 'PartName'
                entry.set(field, entry.get(field).upper())
                content_types.append(entry)
            entry.set('ContentType', 'application/xml')
            return {'[Content_Types].xml':ET.tostring(content_types, encoding='utf-8')}
        workbook = ET.fromstring(source.read('xl/workbook.xml')); sheets = workbook.find('s:sheets', NS)
        require(sheets is not None, 'Inventory mutation requires actual sheets')
        if defect == 'metadata-sheet-tag':
            sheets[0].tag = '{urn:unsupported}sheet'
        elif defect == 'metadata-duplicate-sheet':
            sheets.append(copy.deepcopy(sheets[0]))
        elif defect == 'metadata-duplicate-container':
            workbook.append(copy.deepcopy(sheets))
        elif defect == 'metadata-missing-sheet':
            sheets[0].set('name', 'Missing Policy Lab')
        else:
            original = next(sheet for sheet in sheets if sheet.get('name') == 'Economy')
            duplicate = copy.deepcopy(original)
            duplicate.set('name', 'economy' if defect == 'metadata-duplicate-name' else 'Alternate Economy')
            if defect in ('metadata-duplicate-name', 'metadata-duplicate-rid'):
                duplicate.set('sheetId', '99')
            if defect in ('metadata-duplicate-name', 'metadata-duplicate-sheet-id'):
                if defect == 'metadata-duplicate-sheet-id':
                    duplicate.set('sheetId', '0' + original.get('sheetId'))
                duplicate.set('{' + NS['r'] + '}id', 'alternate-economy')
                rels = ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))
                edge = copy.deepcopy(next(rel for rel in rels if rel.get('Id') == original.get('{' + NS['r'] + '}id')))
                edge.set('Id', 'alternate-economy')
                rels.append(edge)
            sheets.append(duplicate)
        changes = {'xl/workbook.xml':ET.tostring(workbook, encoding='utf-8')}
        if defect in ('metadata-duplicate-name', 'metadata-duplicate-sheet-id'):
            changes['xl/_rels/workbook.xml.rels'] = ET.tostring(rels, encoding='utf-8')
        return changes
    if defect == 'graph-content-types-child':
        part = next(item for item in content_types if item.get('ContentType', '').endswith('drawingml.chart+xml'))
        part.tag = '{urn:unsupported}Override'
        return {'[Content_Types].xml':ET.tostring(content_types, encoding='utf-8')}
    if defect in ('graph-duplicate-office-edge', 'graph-duplicate-sheet-edge'):
        import copy
        path = '_rels/.rels' if defect == 'graph-duplicate-office-edge' else 'xl/_rels/workbook.xml.rels'
        rels = ET.fromstring(source.read(path))
        kind = 'officeDocument' if defect == 'graph-duplicate-office-edge' else 'worksheet'
        edge = next(rel for rel in rels if rel.get('Type', '').endswith('/' + kind))
        rels.append(copy.deepcopy(edge))
        return {path:ET.tostring(rels, encoding='utf-8')}
    if defect in ('graph-workbook-root', 'graph-worksheet-root', 'graph-content-types-root'):
        path = {'graph-workbook-root':'xl/workbook.xml', 'graph-worksheet-root':'xl/worksheets/sheet1.xml', 'graph-content-types-root':'[Content_Types].xml'}[defect]
        part = ET.fromstring(source.read(path))
        part.tag = '{urn:unsupported}' + part.tag.rsplit('}', 1)[-1]
        return {path:ET.tostring(part, encoding='utf-8')}
    if defect in ('graph-worksheet-type', 'graph-relationship-root', 'graph-relationship-child', 'graph-package-office-type', 'graph-package-office-target'):
        path = 'xl/_rels/workbook.xml.rels' if defect == 'graph-worksheet-type' else '_rels/.rels' if defect.startswith('graph-package-') else 'xl/drawings/_rels/drawing1.xml.rels'
        rels = ET.fromstring(source.read(path))
        if defect == 'graph-relationship-root':
            rels.tag = '{urn:unsupported}Relationships'
        elif defect == 'graph-relationship-child':
            rels[0].tag = '{urn:unsupported}Relationship'
        else:
            kind = 'worksheet' if defect == 'graph-worksheet-type' else 'officeDocument'
            edge = next(rel for rel in rels if rel.get('Type', '').endswith('/' + kind))
            edge.set('Target' if defect.endswith('-target') else 'Type', '/xl/styles.xml' if defect.endswith('-target') else NS['r'] + '/styles')
        return {path:ET.tostring(rels, encoding='utf-8')}
    if defect.startswith('chart-duplicate-') or defect == 'chart-numeric-category':
        import copy
        path = 'xl/drawings/charts/chart1.xml'; chart = ET.fromstring(source.read(path))
        namespace = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
        series = chart.find('.//' + namespace + 'ser')
        require(series is not None, 'Binding mutation requires an actual series')
        category = series.find(namespace + 'cat'); value = series.find(namespace + 'val')
        require(category is not None and value is not None, 'Binding mutation requires actual references')
        if defect == 'chart-numeric-category':
            category[0].tag = namespace + 'numRef'
            for child in list(category[0]):
                if child.tag != namespace + 'f':
                    category[0].remove(child)
        else:
            parent = series if defect in ('chart-duplicate-value', 'chart-duplicate-category') else value if defect == 'chart-duplicate-reference' else value[0]
            node = category if defect == 'chart-duplicate-category' else value if defect == 'chart-duplicate-value' else value[0] if defect == 'chart-duplicate-reference' else value[0].find(namespace + 'f')
            require(node is not None, 'Binding mutation requires actual formula data')
            duplicate = copy.deepcopy(node)
            formula = duplicate if duplicate.tag == namespace + 'f' else duplicate.find('.//' + namespace + 'f')
            require(formula is not None, 'Binding mutation requires an actual formula')
            formula.text = "'Policy Lab'!$L$58:$L$106"
            parent.append(duplicate)
        return {path:ET.tostring(chart, encoding='utf-8')}
    if defect in ('chart-wrong-root', 'chart-wrapped-line', 'chart-multiple-lines', 'chart-wrapped-series'):
        path = 'xl/drawings/charts/chart1.xml'; chart = ET.fromstring(source.read(path))
        namespace = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
        plot = chart.find(namespace + 'chart/' + namespace + 'plotArea')
        require(plot is not None, 'Chart structure mutation requires an actual plot')
        line = plot.find(namespace + 'lineChart')
        require(line is not None, 'Chart structure mutation requires actual line data')
        if defect == 'chart-wrong-root':
            chart.tag = '{urn:unsupported}chart'
        elif defect == 'chart-multiple-lines':
            ET.SubElement(plot, namespace + 'lineChart')
        else:
            parent = plot if defect == 'chart-wrapped-line' else line
            child = line if defect == 'chart-wrapped-line' else line.find(namespace + 'ser')
            require(child is not None, 'Chart structure mutation requires actual series')
            position = list(parent).index(child)
            parent.remove(child)
            wrapper = ET.Element('{urn:unsupported}wrapper')
            wrapper.append(child)
            parent.insert(position, wrapper)
        return {path: ET.tostring(chart, encoding='utf-8')}
    if defect.startswith('formula-'):
        path = 'xl/worksheets/sheet2.xml' if defect == 'formula-policy-array' else 'xl/worksheets/sheet4.xml'
        data = source.read(path)
        address = 'E20' if defect == 'formula-policy-array' else f'E{json.loads(row_map.read_text())["actual_output_index"]}'
        match = re.search(rb'<(?:\w+:)?c\b[^>]*\br="' + address.encode() + rb'"[^>]*>.*?</(?:\w+:)?c>', data, re.S)
        require(match is not None, 'Formula type mutation requires an actual saved cell')
        declarations = b' '.join(re.findall(rb'xmlns(?::[\w]+)?="[^"]*"', data[:2000]))
        cell = ET.fromstring(b'<cells ' + declarations + b'>' + match.group() + b'</cells>')[0]
        formula = cell.find('s:f', NS)
        require(formula is not None, 'Formula type mutation requires an actual saved formula')
        formula.set('t', {'formula-array': 'array', 'formula-policy-array': 'array', 'formula-data-table': 'dataTable', 'formula-unknown': 'unknown', 'formula-normal-explicit': 'normal'}[defect])
        if defect != 'formula-normal-explicit':
            formula.set('ref', address + ':F' + re.sub(r'[^0-9]', '', address))
        return {path: data[:match.start()] + ET.tostring(cell, encoding='utf-8') + data[match.end():]}
    if defect.startswith('graph-'):
        path = 'xl/drawings/drawing1.xml'; drawing = ET.fromstring(source.read(path))
        rel_path = 'xl/drawings/_rels/drawing1.xml.rels'; rels = ET.fromstring(source.read(rel_path))
        if defect in ('graph-duplicate-target', 'graph-alien-target'):
            rels[1].set('Target', rels[0].get('Target') if defect == 'graph-duplicate-target' else '/xl/styles.xml')
            return {rel_path: ET.tostring(rels, encoding='utf-8')}
        if defect == 'graph-relative-targets':
            for rel in rels:
                rel.set('Target', posixpath.relpath(rel.get('Target').lstrip('/'), 'xl/drawings'))
            sheet_rels = ET.fromstring(source.read('xl/worksheets/_rels/sheet1.xml.rels'))
            sheet_rels[0].set('Target', '../drawings/drawing1.xml')
            return {rel_path: ET.tostring(rels, encoding='utf-8'), 'xl/worksheets/_rels/sheet1.xml.rels': ET.tostring(sheet_rels, encoding='utf-8')}
        if defect == 'graph-missing-worksheet-drawing':
            data = source.read('xl/worksheets/sheet1.xml')
            data, count = re.subn(rb'<(?:\w+:)?drawing\b[^>]*/>', b'', data)
            require(count == 1, 'Drawing mutation requires the actual worksheet reference')
            return {'xl/worksheets/sheet1.xml': data}
        if defect == 'graph-orphan-drawing':
            ET.SubElement(content_types, '{http://schemas.openxmlformats.org/package/2006/content-types}Override', PartName='/xl/drawings/orphan.xml', ContentType='application/vnd.openxmlformats-officedocument.drawing+xml')
            return {'xl/drawings/orphan.xml': source.read(path), '[Content_Types].xml': ET.tostring(content_types, encoding='utf-8')}
        if defect == 'graph-wrong-root':
            drawing.tag = '{urn:unsupported}drawing'
        elif defect == 'graph-wrong-anchor':
            for anchor in drawing:
                anchor.tag = '{urn:unsupported}anchor'
        elif defect == 'graph-wrapped-anchor':
            wrapper = ET.Element('{urn:unsupported}wrapper')
            for anchor in list(drawing):
                drawing.remove(anchor)
                wrapper.append(anchor)
            drawing.append(wrapper)
        elif defect == 'graph-multiple-frames':
            anchors = list(drawing)
            require(len(anchors) >= 2, 'Frame mutation requires two actual anchors')
            frame = anchors[0].find('{http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing}graphicFrame')
            require(frame is not None, 'Frame mutation requires an actual frame')
            anchors[0].remove(frame)
            anchors[1].append(frame)
        elif defect in ('graph-multiple-containers', 'graph-multiple-graphics'):
            parent_tag = 'graphic' if defect == 'graph-multiple-containers' else 'graphicFrame'
            namespace = 'http://schemas.openxmlformats.org/drawingml/2006/' + ('main' if parent_tag == 'graphic' else 'spreadsheetDrawing')
            parents = drawing.findall('.//{' + namespace + '}' + parent_tag)
            child_tag = '{http://schemas.openxmlformats.org/drawingml/2006/main}' + ('graphicData' if parent_tag == 'graphic' else 'graphic')
            require(len(parents) >= 2, 'Container mutation requires two actual chart frames')
            child = parents[0].find(child_tag)
            require(child is not None, 'Container mutation requires actual graphic content')
            parents[0].remove(child)
            parents[1].append(child)
        elif defect == 'graph-multiple-payload':
            payloads = drawing.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/main}graphicData')
            require(len(payloads) >= 2, 'Payload mutation requires two actual chart frames')
            chart = payloads[0][0]
            payloads[0].remove(chart)
            payloads[1].append(chart)
        elif defect in ('graph-wrong-uri', 'graph-missing-uri'):
            payload = drawing.find('.//{http://schemas.openxmlformats.org/drawingml/2006/main}graphicData')
            require(payload is not None, 'URI mutation requires actual chart data')
            if defect == 'graph-wrong-uri':
                payload.set('uri', 'urn:unsupported')
            else:
                payload.attrib.pop('uri')
        elif defect == 'graph-missing-frame':
            drawing.remove(list(drawing)[0])
        else:
            import copy
            drawing.append(copy.deepcopy(list(drawing)[0]))
        return {path: ET.tostring(drawing, encoding='utf-8')}
    if defect.startswith(('webextension-', 'taskpanes-')):
        label = 'webextension' if defect.startswith('webextension-') else 'webextensiontaskpanes'
        output = {'xl/opaque.xml': b'<payload/>'}
        if defect.endswith('-type'):
            ET.SubElement(content_types, '{http://schemas.openxmlformats.org/package/2006/content-types}Override', PartName='/xl/opaque.xml', ContentType='application/vnd.ms-office.' + label + '+xml')
            output['[Content_Types].xml'] = ET.tostring(content_types, encoding='utf-8')
        else:
            rels = ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))
            ET.SubElement(rels, rel_namespace + 'Relationship', Id='injected-addin', Type='http://schemas.microsoft.com/office/2011/relationships/' + label, Target='opaque.xml')
            output['xl/_rels/workbook.xml.rels'] = ET.tostring(rels, encoding='utf-8')
        return output
    if defect.startswith('table-'):
        path = 'xl/opaque.xml' if 'renamed' in defect else 'xl/tables/table1.xml'
        table = ET.Element('{' + NS['s'] + '}table', id='1', name='InjectedTable', displayName='InjectedTable', ref='E20:E21')
        columns = ET.SubElement(table, '{' + NS['s'] + '}tableColumns', count='1')
        col = ET.SubElement(columns, '{' + NS['s'] + '}tableColumn', id='1', name='External')
        ET.SubElement(col, '{' + NS['s'] + '}' + ('totalsRowFormula' if defect == 'table-totals' else 'calculatedColumnFormula')).text = 'WEBSERVICE("https://example.invalid/table")'
        output = {path: ET.tostring(table, encoding='utf-8')}
        if defect != 'table-renamed-relationship':
            ET.SubElement(content_types, '{http://schemas.openxmlformats.org/package/2006/content-types}Override', PartName='/' + path, ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml')
            output['[Content_Types].xml'] = ET.tostring(content_types, encoding='utf-8')
        if defect != 'table-renamed-type':
            rels = ET.Element(rel_namespace + 'Relationships')
            ET.SubElement(rels, rel_namespace + 'Relationship', Id='injected-table', Type=NS['r'] + '/table', Target='/' + path)
            output['xl/worksheets/_rels/sheet2.xml.rels'] = ET.tostring(rels, encoding='utf-8')
            table_parts = ET.Element('{' + NS['s'] + '}tableParts', count='1')
            ET.SubElement(table_parts, '{' + NS['s'] + '}tablePart', {'{' + NS['r'] + '}id': 'injected-table'})
            data, count = re.subn(rb'(</(?:\w+:)?worksheet>\s*)$',
                                  lambda match: ET.tostring(table_parts, encoding='utf-8') + match.group(1),
                                  source.read('xl/worksheets/sheet2.xml'))
            require(count == 1, 'Table mutation requires the actual worksheet closing tag')
            output['xl/worksheets/sheet2.xml'] = data
        return output
    if defect.startswith('uppercase-'):
        part = ET.Element(rel_namespace + 'Relationships')
        if defect == 'uppercase-external-rels':
            ET.SubElement(part, rel_namespace + 'Relationship', Id='external', Type=NS['r'] + '/hyperlink', Target='https://example.invalid', TargetMode='External')
        return {'xl/worksheets/_rels/sheet2.xml.RELS': ET.tostring(part, encoding='utf-8')}
    chart_path = next(part.get('PartName').lstrip('/') for part in content_types if part.get('ContentType', '').endswith('drawingml.chart+xml'))
    if defect == 'opc-case-duplicate':
        return {chart_path.upper(): source.read(chart_path)}
    if defect.startswith('chart-'):
        chart = ET.fromstring(source.read(chart_path)); ns = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
        series = chart.findall('.//' + ns + 'ser')
        if defect == 'chart-order-swapped':
            series[0].find(ns + 'order').set('val', '1'); series[1].find(ns + 'order').set('val', '0')
        elif defect == 'chart-order-duplicated':
            series[1].find(ns + 'order').set('val', '0')
        elif defect == 'chart-order-missing':
            series[0].remove(series[0].find(ns + 'order'))
        elif defect == 'chart-index-duplicated':
            series[1].find(ns + 'idx').set('val', '0')
        else:
            for i, item in enumerate(series):
                item.find(ns + 'idx').set('val', str(10 + i * 3))
                item.find(ns + 'order').set('val', '+00' if i == 0 else str(i))
        return {chart_path: ET.tostring(chart, encoding='utf-8')}
    path = 'xl/worksheets/sheet4.xml'; data = bytearray()
    with source.open(path) as stream:
        for chunk in iter(lambda: stream.read(131072), b''):
            data.extend(chunk)
    row = json.loads(row_map.read_text())['treasury_cohorts_pct_initial_gdp_0']
    addresses = [f'E{row}', f'G{row}'] if defect == 'shared-disjoint-groups' else [f'E{row}', f'F{row}'] if defect in ('shared-master-duplicated', 'shared-follower-text', 'shared-valid-follower', 'shared-master-overlap') else [f'E{row}']
    for address in addresses:
        match = re.search(rb'<(?:\w+:)?c\b[^>]*\br="' + address.encode() + rb'"[^>]*>.*?</(?:\w+:)?c>', data, re.S)
        require(match is not None, 'Shared mutation requires an actual saved cell')
        declarations = b' '.join(re.findall(rb'xmlns(?::[\w]+)?="[^"]*"', data[:2000]))
        cell = ET.fromstring(b'<cells ' + declarations + b'>' + match.group() + b'</cells>')[0]
        formula = cell.find('s:f', NS); require(formula is not None, 'Shared mutation requires an actual saved formula')
        formula.set('t', 'shared'); formula.set('si', '999998')
        formula.set('ref', f'E{row}:F{row}')
        if defect == 'shared-master-overlap' and address.startswith('F'):
            formula.set('si', '999999'); formula.set('ref', f'F{row}:G{row}')
        elif defect == 'shared-disjoint-groups' and address.startswith('G'):
            formula.set('si', '999999'); formula.set('ref', f'G{row}:H{row}')
        if defect == 'shared-master-no-ref':
            formula.attrib.pop('ref')
        elif defect == 'shared-master-outside':
            formula.set('ref', f'F{row}:F{row}')
        elif defect == 'shared-master-reversed':
            formula.set('ref', f'F{row}:E{row}')
        elif defect == 'shared-master-no-index':
            formula.attrib.pop('si')
        elif defect == 'shared-master-single-cell':
            formula.set('ref', address)
        if defect in ('shared-follower-text', 'shared-valid-follower') and address.startswith('F'):
            formula.attrib.pop('ref')
            if defect == 'shared-valid-follower':
                formula.text = None
        data[match.start():match.end()] = ET.tostring(cell, encoding='utf-8')
    return {path: data}


INPUT54_CASES = {
    **{f'input54-{kind}': 'authored formula mismatch' for kind in ('policy-first', 'policy-last', 'policy-middle')},
    **{f'input54-{kind}': 'authored literal mismatch' for kind in (
        'parameter-first', 'parameter-last', 'parameter-formula', 'parameter-string',
        'initial-first', 'initial-last', 'source-first', 'source-last', 'source-constant', 'fixed-weight',
        'shock-active', 'shock-nonactive', 'shock-last', 'shock-blank-zero',
        'selector-case', 'selector-quarter', 'selector-policy', 'policy-blank-zero', 'policy-zero-blank',
        'policy-bool-number', 'policy-bool-flip', 'policy-last-bool', 'policy-rate', 'policy-guidance', 'policy-guidance-rate', 'policy-guidance-inflation', 'policy-flow')},
    'input54-policy-shared': None,
    'input54-policy-scalar': None,
    'input54-numeric-explicit': None,
}
NEW_CASES.update(INPUT54_CASES)


def input54_mutations(source, defect, row_map):
    kind = defect.removeprefix('input54-')
    layout = scenario_mutation_targets(row_map)
    targets = {
        'policy-first': (2, 'E20', 'formula'), 'policy-last': (2, 'AZ39', 'formula'), 'policy-middle': (2, 'AA30', 'formula'),
        'parameter-first': (3, 'C6', 'number'), 'parameter-last': (3, 'C79', 'number'),
        'parameter-formula': (3, 'C6', 'add-formula'), 'parameter-string': (3, 'C6', 'string'),
        'initial-first': (3, layout['initial-first'], 'number'), 'initial-last': (3, layout['initial-last'], 'number'),
        'source-first': (3, layout['source-first'], 'number'), 'source-last': (3, layout['source-last'], 'number'),
        'source-constant': (3, layout['source-constant'], 'number'), 'fixed-weight': (3, 'D83', 'number'),
        'shock-active': (5, layout['shock-active'], 'number'), 'shock-nonactive': (5, layout['shock-nonactive'], 'number'), 'shock-last': (5, layout['shock-last'], 'number'),
        'shock-blank-zero': (5, layout['shock-blank-zero'], 'zero'),
        'selector-case': (1, 'C4', 'number'), 'selector-quarter': (1, 'C5', 'number'), 'selector-policy': (1, 'C6', 'number'),
        'policy-blank-zero': (2, 'E6', 'zero'), 'policy-zero-blank': (2, 'E10', 'blank'),
        'policy-bool-number': (2, 'E12', 'numeric-type'), 'policy-bool-flip': (2, 'E13', 'flip'),
        'policy-last-bool': (2, 'AZ14', 'flip'), 'policy-rate': (2, 'F6', 'zero'),
        'policy-guidance': (2, 'E9', 'zero'), 'policy-guidance-rate': (2, 'E7', 'zero'), 'policy-guidance-inflation': (2, 'E8', 'zero'), 'policy-flow': (2, 'AZ11', 'number'),
        'policy-shared': (2, 'E20', 'shared'), 'policy-scalar': (2, 'AZ39', 'scalar'),
        'numeric-explicit': (3, 'C6', 'numeric-type'),
    }
    sheet, address, action = targets[kind]
    path = f'xl/worksheets/sheet{sheet}.xml'; part = ET.fromstring(source.read(path))
    cell = part.find(f'.//s:c[@r="{address}"]', NS)
    require(cell is not None, 'input54 requires an actual saved input/output cell')
    formula = cell.find('s:f', NS); value = cell.find('s:v', NS)
    if action in ('formula', 'shared', 'scalar'):
        require(formula is not None, 'input54 requires an actual calculated output')
        if action == 'formula': formula.text = '0'
        elif action == 'scalar': formula.text = ' = ' + formula.text + ' '
        else:
            formula.set('t', 'shared'); formula.set('si', '54001'); formula.set('ref', 'E20:F20')
            follower = part.find('.//s:c[@r="F20"]/s:f', NS)
            require(follower is not None, 'input54 shared output follower')
            follower.attrib.clear(); follower.set('t', 'shared'); follower.set('si', '54001'); follower.text = None
    else:
        require(formula is None, 'input54 must change a saved literal, not a calculated cache')
        if action == 'add-formula': ET.SubElement(cell, '{' + NS['s'] + '}f').text = '0'
        elif action == 'blank':
            if value is not None: cell.remove(value)
            cell.attrib.pop('t', None)
        elif action == 'numeric-type': cell.set('t', 'n')
        elif action == 'string': cell.set('t', 'str')
        else:
            if value is None: value = ET.SubElement(cell, '{' + NS['s'] + '}v')
            value.text = '0' if action == 'zero' else ('0' if value.text == '1' else '1') if action == 'flip' else str(float(value.text) + 0.25)
            cell.set('t', 'b' if action == 'flip' else 'n')
    return {path: ET.tostring(part, encoding='utf-8', xml_declaration=True)}


source_parser = argparse.ArgumentParser(description=__doc__)
source_parser.add_argument('--reference-set', required=True, type=Path)
source_options, source_positionals = source_parser.parse_known_args()
sys.argv = [sys.argv[0], *source_positionals]
reference_set = source_options.reference_set

def upstream45_reference_cases(document):
    import copy
    for kind in ('parameter-order', 'parameter-value', 'scenario-layout', 'state-order'):
        changed = copy.deepcopy(document)
        if kind == 'parameter-order':
            changed['parameters'][0], changed['parameters'][1] = changed['parameters'][1], changed['parameters'][0]
        elif kind == 'parameter-value':
            changed['parameters'][0]['value'] += 0.25
        elif kind == 'scenario-layout':
            changed['scenario']['initial']['price_index'] = 123
        else:
            changed['initial_state'] = dict(reversed(list(changed['initial_state'].items())))
        yield 'upstream45-reference-' + kind, changed, None
    for kind, case in [('nonactive-layout', 'policy_career'), ('nonactive-parameter', 'base'), ('missing-case', 'policy_career')]:
        yield 'upstream45-reference-' + kind, document, (kind, case)


root = Path(__file__).resolve().parents[2]
require(len(sys.argv) in (4, 5), 'Supply workbook, reference, map and optional campaign reference')
workbook, reference, row_map = map(Path, sys.argv[1:4])
with zipfile.ZipFile(workbook) as archive:
    policy_part = validate_policy_inputs(archive)
campaign = Path(sys.argv[4]) if len(sys.argv) == 5 else None
checker = [sys.executable, str(root / 'scripts/spreadsheet/check-workbook.py'),
           str(workbook), '--reference', str(reference), '--map', str(row_map), '--reference-set', str(reference_set)]
validate_view77_guidance_oracle(Path(checker[1]))
validate_cache89_oracles(Path(checker[1]), row_map)
if campaign:
    checker += ['--campaign-reference', str(campaign)]
    expected_note = 'Recurring crises: ' + json.loads(campaign.read_text())['scenario']['description']
modes = [('normal', [], dict(os.environ, PYTHONOPTIMIZE='')),
         ('-O', ['-O'], dict(os.environ, PYTHONOPTIMIZE='')),
         ('inherited-optimize', [], dict(os.environ, PYTHONOPTIMIZE='1'))]
for mode, flags, environment in modes:
    valid = subprocess.run(checker[:1] + flags + checker[1:], capture_output=True, text=True, env=environment)
    require(valid.returncode == 0, (mode, valid.stdout + valid.stderr))
with tempfile.TemporaryDirectory(prefix='fed-chart-regression-') as directory:
    defects = [('cold-start-formula', 'Full-state parity missing formula'),
               ('removed-formula', 'Full-state parity missing formula'),
               ('empty-formula', 'Full-state parity missing formula'),
               ('orphan-shared-formula', 'Full-state parity missing formula'),
               ('shared-outside-range', 'Full-state parity missing formula'),
               ('shared-formula', None),
               ('category-range', 'chart category binding'),
               ('value-range', 'chart value binding'),
               ('series-order', 'chart value binding'),
               ('vba-content-type', 'active content'),
               ('xlm-content-type', 'active content'),
               ('xlm-relationship', 'active content'),
               ('vba-relationship', 'active content'),
               ('connections-type', 'active content'),
               ('connections-relationship', 'active content'),
               ('external-relationship', 'active content'),
               ('external-target', 'active content'),
               ('duplicate-relationship', 'duplicate package part'),
               ('duplicate-content-type', 'duplicate package part'),
               ('blank-chart', 'missing chart series'),
               ('axis-precision', 'ambiguous value-axis precision'),
               ('linked-axis', 'ambiguous value-axis precision'),
               ('cohort-cache', 'full-state parity'),
               ('logical-type', 'Full-state parity boolean type')]
    validation_defects = [('validation-count', 'Policy input validation ranges'),
                          ('validation-range', 'Policy input validation ranges'),
                          ('validation-type', 'Policy input validation type'),
                          ('validation-formula', 'Policy input validation relative formula'),
                          ('validation-blank', 'Policy input validation must not ignore blanks'),
                          ('validation-alert', 'Policy input validation alert disabled'),
                          ('validation-stop', 'Policy input validation must Stop')]
    formula_cases = {
        'external-webservice': ('WEBSERVICE("https://example.invalid/data")', 'economy'),
        'external-dde': ("'server'|'topic'!A1", 'economy'),
        'external-workbook': ("'[remote.xlsx]Economy'!A1", 'economy'),
        'external-hyperlink': ('HYPERLINK("https://example.invalid","open")', 'policy'),
        'external-prefixed': ('_xlfn.WEBSERVICE("https://example.invalid")', 'economy'),
        'external-rtd': ('RTD("server",,"topic")', 'economy'),
        'external-note': ('WEBSERVICE("https://example.invalid/note")', 'shocks'),
        'external-defined-name': ('WEBSERVICE("https://example.invalid/name")', 'name'),
        'external-validation': ('WEBSERVICE("https://example.invalid/validation")', 'validation'),
        'external-conditional': ('HYPERLINK("https://example.invalid/conditional")', 'conditional'),
        'safe-formula-literals': ('IF("DDE | [book] ! WEBSERVICE(""https://example.invalid"")"="unchanged",0,1)', 'shocks'),
        'safe-formula-reference': ("if(1e-3>0,'Economy'!$D$4+1,0)", 'shocks'),
        'safe-defined-name': ("'Policy Lab'!$B$58:$B$106", 'name'),
    }
    defects += [(name, None if name.startswith('safe-') else 'unsupported workbook formula') for name in formula_cases]
    defects += list(NEW_CASES.items())
    defects += validation_defects
    if campaign:
        defects += list(CAMPAIGN_CASES.items())
        defects.append(('campaign-note', 'stale or missing campaign explanation'))
    failures = []
    reference_ids = json.loads(row_map.with_suffix('.formulas.json').read_text())['reference_sha256']
    for name, altered, source_change in upstream45_reference_cases(json.loads(reference.read_text())):
        bad_reference = Path(directory) / (name + '.json')
        if source_change:
            bad_reference.write_bytes(reference.read_bytes())
        else:
            bad_reference.write_text(json.dumps(altered, indent=2) + '\n')
        source_directory = reference_set
        if source_change:
            import shutil
            kind, case = source_change
            source_directory = Path(directory) / name; source_directory.mkdir()
            for identity in reference_ids:
                if not (kind == 'missing-case' and identity == case):
                    shutil.copyfile(reference_set / (identity + '.json'), source_directory / (identity + '.json'))
            if kind != 'missing-case':
                path = source_directory / (case + '.json'); changed_source = json.loads(path.read_text())
                if kind == 'nonactive-layout':
                    changed_source['scenario']['initial']['price_index'] = 123
                else:
                    changed_source['parameters'][0], changed_source['parameters'][1] = changed_source['parameters'][1], changed_source['parameters'][0]
                path.write_text(json.dumps(changed_source, indent=2) + '\n')
        command = checker.copy()
        command[command.index('--reference') + 1] = str(bad_reference)
        command[command.index('--reference-set') + 1] = str(source_directory)
        for mode, flags, environment in modes:
            result = subprocess.run(command[:1] + flags + command[1:], capture_output=True, text=True, env=environment)
            diagnostic = ('reference input binding: missing case' if source_change[0] == 'missing-case'
                          else 'reference input binding: source set digest') if source_change else 'reference input binding'
            require(result.returncode != 0 and diagnostic in result.stderr,
                    f'{name} ({mode}) accepted wrong authored source inputs')
        print(f'PASS: rejected {name} in all checker modes')
    for defect, error in defects:
        if campaign and defect == 'cache89-growth-missing':
            # The campaign scan rejects missing string values before upstream cache checks.
            error = 'campaign string structure'
        broken = Path(directory) / f'{defect}.xlsx'
        changed = False
        with zipfile.ZipFile(workbook) as source, zipfile.ZipFile(broken, 'w') as target:
            review_changes = review_mutations(source, defect, row_map)
            charts = {part.attrib['PartName'].lstrip('/')
                      for part in ET.fromstring(source.read('[Content_Types].xml'))
                      if part.attrib.get('ContentType') == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml'}
            if defect in formula_cases:
                workbook_xml = ET.fromstring(source.read('xl/workbook.xml'))
                relationships = {item.get('Id'): item.get('Target') for item in ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))}
                sheet_paths = {}
                for sheet in workbook_xml.find('s:sheets', NS):
                    path = relationships[sheet.get('{' + NS['r'] + '}id')]
                    sheet_paths[sheet.get('name')] = path.lstrip('/') if path.startswith('/') else posixpath.normpath('xl/' + path)
                injected_formula, location = formula_cases[defect]
                formula_path = 'xl/workbook.xml' if location == 'name' else sheet_paths[{'economy': 'Economy', 'policy': 'Policy', 'shocks': 'Shocks', 'validation': 'Policy', 'conditional': 'Policy'}[location]]
            if defect.startswith('duplicate-'):
                path = 'xl/_rels/workbook.xml.rels' if defect == 'duplicate-relationship' else '[Content_Types].xml'
                part = ET.fromstring(source.read(path))
                if defect == 'duplicate-relationship':
                    ET.SubElement(part, '{http://schemas.openxmlformats.org/package/2006/relationships}Relationship',
                                  {'Id': 'duplicate-active', 'Type': 'https://example.test/external', 'Target': 'https://example.test/payload', 'TargetMode': 'External'})
                else:
                    ET.SubElement(part, '{http://schemas.openxmlformats.org/package/2006/content-types}Override',
                                  {'PartName': '/xl/opaque.bin', 'ContentType': 'application/vnd.ms-office.vbaProject'})
                target.writestr(path, ET.tostring(part, encoding='utf-8', xml_declaration=True))
                changed = True
            if defect == 'cold-start-formula':
                workbook_xml = ET.fromstring(source.read('xl/workbook.xml'))
                economy_sheet = next(sheet for sheet in workbook_xml.find('s:sheets', NS) if sheet.get('name') == 'Economy')
                relationships = {item.get('Id'): item.get('Target') for item in ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))}
                target_path = relationships[economy_sheet.get('{' + NS['r'] + '}id')]
                economy_path = target_path.lstrip('/') if target_path.startswith('/') else posixpath.normpath('xl/' + target_path)
            for info in source.infolist():
                if info.filename in review_changes:
                    data = review_changes.pop(info.filename)
                    changed = True
                else:
                    data = source.read(info.filename)
                if defect in formula_cases and info.filename == formula_path:
                    part = ET.fromstring(data)
                    if location == 'name':
                        names = part.find('s:definedNames', NS)
                        if names is None:
                            names = ET.SubElement(part, '{' + NS['s'] + '}definedNames')
                        formula = ET.SubElement(names, '{' + NS['s'] + '}definedName', name='FormulaGuardFixture')
                    elif location == 'validation':
                        formula = ET.SubElement(part.find('s:dataValidations/s:dataValidation', NS), '{' + NS['s'] + '}formula2')
                    elif location == 'conditional':
                        formatting = ET.SubElement(part, '{' + NS['s'] + '}conditionalFormatting', sqref='E4')
                        rule = ET.SubElement(formatting, '{' + NS['s'] + '}cfRule', type='expression', priority='1')
                        formula = ET.SubElement(rule, '{' + NS['s'] + '}formula')
                    else:
                        address = f'E{json.loads(row_map.read_text())["actual_output_index"]}' if location == 'economy' else 'E20' if location == 'policy' else 'E4'
                        # Lexer positives must leave authored decision headers intact.
                        if defect in ('safe-formula-literals', 'safe-formula-reference'):
                            address = 'C4'
                        cell = next(cell for cell in part.findall('.//s:c', NS) if cell.get('r') == address)
                        formula = cell.find('s:f', NS)
                        if formula is None:
                            formula = ET.SubElement(cell, '{' + NS['s'] + '}f')
                    formula.text = injected_formula
                    data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                    changed = True
                if defect == 'cold-start-formula' and info.filename == economy_path:
                    part = ET.fromstring(data)
                    address = f'D{json.loads(row_map.read_text())["actual_output_index"]}'
                    cell = next(cell for cell in part.findall('.//s:c', NS) if cell.get('r') == address)
                    formula = cell.find('s:f', NS)
                    require(formula is not None, 'Cold-start fixture must remove the actual calculated formula')
                    cell.remove(formula)
                    data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                    changed = True
                if defect.startswith('validation-') and info.filename == policy_part:
                    part = ET.fromstring(data)
                    validations = part.find('s:dataValidations', NS)
                    rule = next(item for item in validations if item.get('sqref') == 'E6:AZ9')
                    if defect == 'validation-count':
                        validations.remove(rule)
                    elif defect == 'validation-formula':
                        rule.find('s:formula1', NS).text = rule.find('s:formula1', NS).text.replace('E6', '$E$6')
                    else:
                        attribute, value = {'validation-range': ('sqref', 'E6:AZ14'),
                                            'validation-type': ('type', 'decimal'),
                                            'validation-blank': ('allowBlank', '1'),
                                            'validation-alert': ('showErrorMessage', '0'),
                                            'validation-stop': ('errorStyle', 'warning')}[defect]
                        rule.set(attribute, value)
                    data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                    changed = True
                if not changed and defect == 'campaign-note' and (info.filename == 'xl/sharedStrings.xml' or info.filename.startswith('xl/worksheets/')):
                    part = ET.fromstring(data)
                    for text in part.iter():
                        if text.tag in ('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t', '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}v') and text.text == expected_note:
                            text.text = 'Obsolete paired three-template generator.'
                            changed = True
                            break
                    if changed:
                        data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                if not changed and defect in ('removed-formula', 'empty-formula', 'orphan-shared-formula', 'shared-formula', 'shared-outside-range') and info.filename.startswith('xl/worksheets/'):
                    part = ET.fromstring(data)
                    target_row = json.loads(row_map.read_text())['treasury_cohorts_pct_initial_gdp_0']
                    saved_cells = {cell.get('r'): cell for cell in part.findall('.//s:c', NS)}
                    for cell in saved_cells.values():
                        if cell.get('r') == f'E{target_row}' and cell.find('s:f', NS) is not None:
                            formula = cell.find('s:f', NS)
                            if defect in ('shared-formula', 'shared-outside-range'):
                                formula.set('t', 'shared'); formula.set('si', '999998')
                                formula.set('ref', f'E{target_row}:F{target_row}' if defect == 'shared-formula' else f'E{target_row}:E{target_row}')
                                follower = saved_cells[f'F{target_row}'].find('s:f', NS)
                                require(follower is not None, 'Fault injection requires a shared formula follower')
                                follower.text = None
                                follower.set('t', 'shared'); follower.set('si', '999998')
                            elif defect == 'removed-formula':
                                cell.remove(formula)
                            else:
                                formula.text = None
                                if defect == 'orphan-shared-formula':
                                    formula.set('t', 'shared'); formula.set('si', '999999')
                            changed = True
                            break
                    if changed:
                        data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                if defect in ('vba-content-type', 'connections-type', 'xlm-content-type') and info.filename == '[Content_Types].xml':
                    part = ET.fromstring(data)
                    ET.SubElement(part, '{http://schemas.openxmlformats.org/package/2006/content-types}Override',
                                  PartName='/xl/opaque.bin', ContentType=('application/vnd.ms-office.vbaProject' if defect == 'vba-content-type' else 'application/vnd.ms-excel.macrosheet+xml' if defect == 'xlm-content-type' else 'application/vnd.openxmlformats-officedocument.spreadsheetml.connections+xml'))
                    data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                    changed = True
                if defect in ('vba-relationship', 'connections-relationship', 'xlm-relationship', 'external-relationship', 'external-target') and info.filename == 'xl/_rels/workbook.xml.rels':
                    part = ET.fromstring(data)
                    attrs = dict(Id='injected', Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/' + ('vbaProject' if defect == 'vba-relationship' else 'xlMacrosheet' if defect == 'xlm-relationship' else 'connections' if defect == 'connections-relationship' else 'hyperlink'), Target=('opaque.bin' if defect in ('vba-relationship', 'connections-relationship', 'xlm-relationship') else 'https://example.invalid/workbook'))
                    if defect == 'external-relationship':
                        attrs['TargetMode'] = 'External'
                    ET.SubElement(part, '{http://schemas.openxmlformats.org/package/2006/relationships}Relationship', attrs)
                    data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                    changed = True
                if not changed and defect == 'cohort-cache' and info.filename.startswith('xl/worksheets/'):
                    part = ET.fromstring(data)
                    target_row = json.loads(row_map.read_text())['treasury_cohorts_pct_initial_gdp_0']
                    for cell in part.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c'):
                        if cell.attrib.get('r') == f'E{target_row}':
                            value = cell.find('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}v')
                            if value is not None and cell.find('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}f') is not None:
                                value.text = str(float(value.text) + 0.01)
                                changed = True
                                break
                    if changed:
                        data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                if not changed and defect == 'logical-type' and info.filename.startswith('xl/worksheets/'):
                    part = ET.fromstring(data)
                    target_row = json.loads(row_map.read_text())['guidance_active']
                    for cell in part.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c'):
                        if cell.attrib.get('r') == f'E{target_row}' and cell.attrib.get('t') == 'b' and cell.find('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}f') is not None:
                            cell.set('t', 'n')
                            changed = True
                            break
                    if changed:
                        data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
                if not changed and not defect.startswith('validation-') and defect in ('blank-chart', 'axis-precision', 'linked-axis', 'category-range', 'value-range', 'series-order') and info.filename in charts:
                    chart = ET.fromstring(data)
                    namespace = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
                    if defect == 'blank-chart':
                        for parent in chart.iter():
                            for child in list(parent):
                                if child.tag == namespace + 'ser':
                                    parent.remove(child)
                                    changed = True
                    elif defect in ('category-range', 'value-range'):
                        series = chart.find(f'.//{namespace}ser')
                        formula = series.find(f'{namespace}cat/{namespace}strRef/{namespace}f') if defect == 'category-range' else series.find(f'{namespace}val/{namespace}numRef/{namespace}f')
                        if formula is None and defect == 'category-range':
                            formula = series.find(f'{namespace}cat/{namespace}numRef/{namespace}f')
                        require(formula is not None, 'Fault injection requires saved chart reference')
                        formula.text = "'Economy'!$B$58:$B$106"
                        changed = True
                    elif defect == 'series-order':
                        series = chart.findall(f'.//{namespace}ser')
                        first = series[0].find(f'{namespace}val/{namespace}numRef/{namespace}f')
                        second = series[1].find(f'{namespace}val/{namespace}numRef/{namespace}f')
                        first.text, second.text = second.text, first.text
                        changed = True
                    else:
                        axis = chart.find(f'.//{namespace}valAx/{namespace}numFmt')
                        require(axis is not None, 'Fault injection requires an actual saved value-axis format')
                        axis.set('formatCode' if defect == 'axis-precision' else 'sourceLinked',
                                 '0.0' if defect == 'axis-precision' else '1')
                        changed = True
                    data = ET.tostring(chart, encoding='utf-8', xml_declaration=True)
                target.writestr(info, data)
            for path, data in review_changes.items():
                target.writestr(path, data)
                changed = True
            if defect.startswith(('vba-', 'connections-', 'xlm-')):
                target.writestr('xl/opaque.bin', b'active-content-mutation')
        require(changed, 'Fault injection must corrupt actual saved workbook content')
        if defect.startswith('validation-'):
            try:
                with zipfile.ZipFile(broken) as archive:
                    validate_policy_inputs(archive)
            except AssertionError as failure:
                require(error in str(failure), f'{defect} did not fail for its intended policy validation check')
            else:
                raise AssertionError(f'{defect} accepted malformed policy validation')
            for mode, flags, environment in modes:
                result = subprocess.run([sys.executable] + flags + [__file__, str(broken), str(reference), str(row_map), '--reference-set', str(reference_set)], capture_output=True, text=True, env=environment)
                require(result.returncode != 0 and error in result.stderr, f'{defect} ({mode}) disabled file-test acceptance guard')
            print(f'PASS: rejected {defect} in all file-test modes')
            continue
        checker[2] = str(broken)
        for mode, flags, environment in modes:
            result = subprocess.run(checker[:1] + flags + checker[1:], capture_output=True, text=True, env=environment)
            if not (result.returncode == 0 if error is None else result.returncode != 0 and error in result.stderr):
                failures.append(f'{defect} ({mode}) did not fail for its intended check: {result.stdout}{result.stderr}')
        print(f'CHECKED: {defect} in all checker modes')
    require(not failures, '\n'.join(failures))
print('PASS: real workbook accepted; shared formulas accepted; formula, chart, active-content, policy validation and cache mutations rejected in normal/-O/inherited-optimize modes'
      + ('; stale saved campaign note rejected' if campaign else ''))
