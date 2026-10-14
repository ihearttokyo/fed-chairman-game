"""Reject malformed policy validation, charts or caches in real workbook copies."""
from pathlib import Path
import json
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
    'chart-numeric-category': None,
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


def review_mutations(source, defect, row_map):
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
        cell = part.find('.//s:c[@r="B158"]', NS)
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


root = Path(__file__).resolve().parents[2]
require(len(sys.argv) in (4, 5), 'Supply workbook, reference, map and optional campaign reference')
workbook, reference, row_map = map(Path, sys.argv[1:4])
with zipfile.ZipFile(workbook) as archive:
    policy_part = validate_policy_inputs(archive)
campaign = Path(sys.argv[4]) if len(sys.argv) == 5 else None
checker = [sys.executable, str(root / 'scripts/spreadsheet/check-workbook.py'),
           str(workbook), '--reference', str(reference), '--map', str(row_map)]
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
    for defect, error in defects:
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
                result = subprocess.run([sys.executable] + flags + [__file__, str(broken), str(reference), str(row_map)], capture_output=True, text=True, env=environment)
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
