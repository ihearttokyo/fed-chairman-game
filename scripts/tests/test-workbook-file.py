"""Reject a blank chart in a disposable copy of a real exported workbook."""
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[2]
workbook, reference, row_map = map(Path, sys.argv[1:])
checker = [sys.executable, str(root / 'scripts/spreadsheet/check-workbook.py'),
           str(workbook), '--reference', str(reference), '--map', str(row_map)]
valid = subprocess.run(checker, capture_output=True, text=True)
assert valid.returncode == 0, valid.stdout + valid.stderr
with tempfile.TemporaryDirectory(prefix='fed-blank-chart-') as directory:
    broken = Path(directory) / 'blank-chart.xlsx'
    changed = False
    with zipfile.ZipFile(workbook) as source, zipfile.ZipFile(broken, 'w') as target:
        charts = {part.attrib['PartName'].lstrip('/')
                  for part in ET.fromstring(source.read('[Content_Types].xml'))
                  if part.attrib.get('ContentType') == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml'}
        for info in source.infolist():
            data = source.read(info.filename)
            if not changed and info.filename in charts:
                chart = ET.fromstring(data)
                for parent in chart.iter():
                    for child in list(parent):
                        if child.tag == '{http://schemas.openxmlformats.org/drawingml/2006/chart}ser':
                            parent.remove(child)
                            changed = True
                data = ET.tostring(chart, encoding='utf-8', xml_declaration=True)
            target.writestr(info, data)
    assert changed, 'Fault injection must remove actual chart series'
    checker[2] = str(broken)
    result = subprocess.run(checker, capture_output=True, text=True)
    assert result.returncode != 0 and 'missing chart series' in result.stderr, 'Empty chart did not fail for the intended series check'
print('PASS: real workbook accepted; actual blank-chart corruption rejected')
