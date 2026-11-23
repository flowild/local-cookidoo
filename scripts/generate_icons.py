from pathlib import Path

from PIL import Image, ImageOps

root = Path(__file__).resolve().parents[1]
static = root / 'app/static'
with Image.open(static / 'icon-512.png') as source:
    icon = source.convert('RGB')

icon.resize((192, 192), Image.Resampling.LANCZOS).save(static / 'icon-192.png', optimize=True)
maskable = icon.resize((472, 472), Image.Resampling.LANCZOS)
ImageOps.expand(maskable, border=20, fill=icon.getpixel((0, 0))).save(
    static / 'icon-maskable-512.png', optimize=True,
)

android = root / 'android-app'
if android.is_dir():
    icon.resize((192, 192), Image.Resampling.LANCZOS).save(android / 'assets/icon.png', optimize=True)
    resources = android / 'android/app/src/main/res'
    for density, size in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(
            resources / f'mipmap-{density}/ic_launcher.png', optimize=True,
        )
