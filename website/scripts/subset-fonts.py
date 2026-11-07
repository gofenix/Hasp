"""Rebuild self-hosted web fonts. pip install fonttools[woff]==4.68.0."""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT.parent / 'build/website-fonts'
CACHE.mkdir(parents=True, exist_ok=True)
SOURCE = 'https://raw.githubusercontent.com/lxgw/LxgwWenKai/048a6a97c7f354437670d6b92276073cd75e8a5d/'
text = ''.join((ROOT / path).read_text() for path in ['src/App.jsx', 'index.html'])
text += ''.join(chr(i) for i in range(32, 127)) + '＋−'
for weight in ['Regular', 'Medium']:
    path = CACHE / f'{weight}.ttf'
    if not path.exists():
        urllib.request.urlretrieve(SOURCE + f'fonts/TTF/LXGWWenKai-{weight}.ttf', path)
    font = TTFont(path)
    options = subset.Options()
    options.flavor = 'woff2'
    sub = subset.Subsetter(options=options)
    sub.populate(text=text)
    sub.subset(font)
    # Give the subset its own family name; preserve upstream copyright/license.
    for record in font['name'].names:
        names = {1: 'Hasp WenKai Subset', 4: f'Hasp WenKai Subset {weight}',
                 6: f'HaspWenKaiSubset-{weight}', 16: 'Hasp WenKai Subset'}
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    font.flavor = 'woff2'
    target = ROOT / f'public/assets/fonts/wenkai-{weight.lower()}.woff2'
    font.save(target)
    print(target.name, target.stat().st_size)
