"""Reject blank series or ambiguous axis formats in real workbook copies."""
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
with tempfile.TemporaryDirectory(prefix='fed-chart-regression-') as directory:
    for defect, error in [('blank-chart', 'missing chart series'),
                          ('axis-precision', 'ambiguous value-axis precision'),
                          ('linked-axis', 'ambiguous value-axis precision')]:
        broken = Path(directory) / f'{defect}.xlsx'
        changed = False
        with zipfile.ZipFile(workbook) as source, zipfile.ZipFile(broken, 'w') as target:
            charts = {part.attrib['PartName'].lstrip('/')
                      for part in ET.fromstring(source.read('[Content_Types].xml'))
                      if part.attrib.get('ContentType') == 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml'}
            for info in source.infolist():
                data = source.read(info.filename)
                if not changed and info.filename in charts:
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
        assert changed, 'Fault injection must corrupt actual chart content'
        checker[2] = str(broken)
        result = subprocess.run(checker, capture_output=True, text=True)
        assert result.returncode != 0 and error in result.stderr, f'{defect} did not fail for its intended chart check'
print('PASS: real workbook accepted; blank series and ambiguous axis formats rejected')
