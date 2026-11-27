"""Create the bundled Android previews from the web week's placeholder art."""

from pathlib import Path

from PIL import Image


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / 'app/static'
    target = root / 'android-app/assets/week_placeholders'
    target.mkdir(parents=True, exist_ok=True)

    def save(image, name):
        image.thumbnail((640, 640), Image.Resampling.LANCZOS)
        image.save(target / f'{name}.webp', quality=86, method=6)

    with Image.open(source / 'week-placeholder-four.png') as sheet:
        width, height = sheet.width // 2, sheet.height // 2
        for index, name in enumerate(('fastfood', 'sushi', 'pasta', 'abendbrot')):
            left = index % 2 * width
            top = index // 2 * height
            save(sheet.crop((left, top, left + width, top + height)), name)

    for filename, name in (
        ('week-placeholder-steak-v2.png', 'restaurant'),
        ('week-placeholder-resteessen.png', 'resteessen'),
    ):
        with Image.open(source / filename) as image:
            save(image, name)


if __name__ == '__main__':
    main()
