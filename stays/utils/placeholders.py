from pathlib import Path
from django.conf import settings

def ensure_placeholder_image():
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return

    target_dir = Path(settings.MEDIA_ROOT) / "stays_photos"
    target_dir.mkdir(parents=True, exist_ok=True)
    target_path = target_dir / "placeholder.jpg"
    if target_path.exists():
        return

    w, h = 400, 300
    img = Image.new("RGB", (w, h), (210, 210, 210))
    d = ImageDraw.Draw(img)
    text = "No Photo"
    tw = d.textlength(text)
    th = 16
    d.text(((w - tw) / 2, (h - th) / 2), text, fill=(0, 0, 0))
    img.save(target_path, format="JPEG", quality=88)
