from pathlib import Path

from PIL import Image, ImageDraw

directory = Path(__file__).resolve().parents[1] / 'app/static'
for size, maskable in ((192, False), (512, False), (512, True)):
    scale = 4
    canvas = Image.new('RGB', (size * scale, size * scale), '#234d3c')
    draw = ImageDraw.Draw(canvas)
    def points(values):
        factor = size * scale / 64
        return tuple(round(value * factor) for value in values)
    # Original code-native bowl/leaf identity, with generous maskable safe area.
    draw.pieslice(points((15, 19, 49, 52)), 0, 180, fill='#f7f3e8')
    draw.ellipse(points((28, 13, 46, 29)), fill='#b4cb82')
    draw.line(points((28, 31, 41, 18)), fill='#234d3c', width=max(2, round(size * scale / 28)))
    draw.line(points((24, 53, 40, 53)), fill='#f7f3e8', width=max(2, round(size * scale / 24)))
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(directory / (f'icon-maskable-{size}.png' if maskable else f'icon-{size}.png'))
