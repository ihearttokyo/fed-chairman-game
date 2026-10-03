"""Reject blank series or ambiguous axis formats in real workbook copies."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[2]
assert len(sys.argv) in (4, 5), 'Supply workbook, reference, map and optional campaign reference'
workbook, reference, row_map = map(Path, sys.argv[1:4])
campaign = Path(sys.argv[4]) if len(sys.argv) == 5 else None
checker = [sys.executable, str(root / 'scripts/spreadsheet/check-workbook.py'),
           str(workbook), '--reference', str(reference), '--map', str(row_map)]
if campaign:
    checker += ['--campaign-reference', str(campaign)]
    expected_note = 'Recurring crises: ' + json.loads(campaign.read_text())['scenario']['description']
valid = subprocess.run(checker, capture_output=True, text=True)
assert valid.returncode == 0, valid.stdout + valid.stderr
with tempfile.TemporaryDirectory(prefix='fed-chart-regression-') as directory:
    defects = [('blank-chart', 'missing chart series'),
               ('axis-precision', 'ambiguous value-axis precision'),
               ('linked-axis', 'ambiguous value-axis precision'),
               ('cohort-cache', 'full-state parity')]
    if campaign:
        defects.append(('campaign-note', 'stale or missing campaign explanation'))
    for defect, error in defects:
        broken = Path(directory) / f'{defect}.xlsx'
        changed = False
        with zipfile.ZipFile(workbook) as source, zipfile.ZipFile(broken, 'w') as target:
            charts = {part.attrib['PartName'].lstrip('/')
                      for part in ET.fromstring(source.read('[Content_Types].xml'))
                      if part.attrib.get('ContentType') == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml'}
            for info in source.infolist():
                data = source.read(info.filename)
                if not changed and defect == 'campaign-note' and (info.filename == 'xl/sharedStrings.xml' or info.filename.startswith('xl/worksheets/')):
                    part = ET.fromstring(data)
                    for text in part.iter():
                        if text.tag in ('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t', '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}v') and text.text == expected_note:
                            text.text = 'Obsolete paired three-template generator.'
                            changed = True
                            break
                    if changed:
                        data = ET.tostring(part, encoding='utf-8', xml_declaration=True)
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
                if not changed and defect not in ('campaign-note', 'cohort-cache') and info.filename in charts:
                    chart = ET.fromstring(data)
                    namespace = '{http://schemas.openxmlformats.org/drawingml/2006/chart}'
                    if defect == 'blank-chart':
                        for parent in chart.iter():
                            for child in list(parent):
                                if child.tag == namespace + 'ser':
                                    parent.remove(child)
                                    changed = True
                    else:
                        axis = chart.find(f'.//{namespace}valAx/{namespace}numFmt')
                        assert axis is not None, 'Fault injection requires an actual saved value-axis format'
                        axis.set('formatCode' if defect == 'axis-precision' else 'sourceLinked',
                                 '0.0' if defect == 'axis-precision' else '1')
                        changed = True
                    data = ET.tostring(chart, encoding='utf-8', xml_declaration=True)
                target.writestr(info, data)
        assert changed, 'Fault injection must corrupt actual saved workbook content'
        checker[2] = str(broken)
        result = subprocess.run(checker, capture_output=True, text=True)
        assert result.returncode != 0 and error in result.stderr, f'{defect} did not fail for its intended chart check'
print('PASS: real workbook accepted; blank series and ambiguous axis formats rejected'
      + ('; stale saved campaign note rejected' if campaign else ''))
