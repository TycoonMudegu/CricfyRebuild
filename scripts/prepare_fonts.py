"""Build static Inter faces for consistent Android 7+ rendering."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1]
source = root / 'design/fonts/inter-variable.ttf'
destination = root / 'ui-res/font'
destination.mkdir(parents=True, exist_ok=True)
for weight, name in ((400, 'regular'), (500, 'medium'), (600, 'semibold'), (700, 'bold')):
    font = TTFont(source)
    font = instantiateVariableFont(font, {'wght': weight, 'opsz': 24}, inplace=True)
    font.save(destination / f'ui_inter_{name}.ttf')
    print(f'Prepared Inter {weight}')
