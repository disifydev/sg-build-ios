#!/usr/bin/env python3
# Промо-кадры App Store 6.9": 1320×2868 PNG без альфы. Кремовый фон, заголовок Unbounded, экран со скруглёнными углами.
import os, sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1320, 2868
BG = (0xEC, 0xE6, 0xDC)
INK = (0x14, 0x21, 0x1F)
FONT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Fonts", "Unbounded-700.ttf")
SHOTS = [
    ("01", "messages", "Все переписки\nв одном окне"),
    ("02", "chat-menu", "Отвечайте\nкак в Telegram"),
    ("03", "profile", "Карточка клиента\nвсегда под рукой"),
    ("04", "payments", "Кто оплатил,\nа кто обещал"),
    ("05", "schedule", "Расписание\nзанятий"),
    ("06", "home", "Сводка за день\nи неделю"),
    ("07", "voice", "Голосовые\nи кружки"),
]

def font_for(lines, maxw):
    size = 104
    while size > 50:
        f = ImageFont.truetype(FONT, size)
        if max(f.getlength(l) for l in lines) <= maxw:
            return f
        size -= 4
    return ImageFont.truetype(FONT, size)

def frame(src, title, out):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    lines = title.split("\n")
    f = font_for(lines, W - 160)
    y = 150
    for l in lines:
        w = f.getlength(l)
        d.text(((W - w) / 2, y), l, font=f, fill=INK)
        y += int(f.size * 1.2)
    shot = Image.open(src).convert("RGB")
    sw = 1080
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    top = y + 70
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=110, fill=255)
    x = (W - sw) // 2
    ImageDraw.Draw(img).rounded_rectangle((x - 3, top + 10, x + sw + 3, top + sh + 16), radius=113, fill=(0xDA, 0xD2, 0xC6))
    img.paste(shot, (x, top), mask)
    img.save(out, "PNG")
    print(out, img.size, img.mode)

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for n, name, title in SHOTS:
        p = os.path.join(src, name + ".png")
        if os.path.exists(p):
            frame(p, title, os.path.join(dst, f"{n}-{name}.png"))
        else:
            print("нет снимка", p); sys.exit(1)
