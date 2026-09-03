# Fonts

**Pixel Operator 8**, by Jayvee Enaguas (HarvettFox96), released under **CC0 1.0 Universal** —
the full licence text is in `LICENSE.txt`, copied verbatim from the archive the fonts came in
(fontlibrary.org/en/font/pixel-operator, downloaded 2026-09-03). CC0 asks for nothing: no
attribution, no notice, no share-alike. It is credited here anyway because a project that
gates the LICENCE of every pixel of its art should say where its letters came from too.

Two faces ship, and only the **8** variants: Pixel Operator's plain and Mono families are drawn
for 16px, and this game's whole interface is laid out against a 320x180 design size where body
text is 8 pixels tall. A 16px face asked for 8px is a scaled bitmap, which is the blur the
font was brought in to remove.

| File | Face | Used for |
| --- | --- | --- |
| `pixel_operator_8.ttf` | Pixel Operator 8 | everything: rows, captions, help lines |
| `pixel_operator_8_bold.ttf` | Pixel Operator 8 Bold | a window's header band, and the title |

**The whole project draws in this font, through one project setting** — `gui/theme/custom_font`
in `project.godot`, which Godot loads into `ThemeDB.fallback_font` and the default theme. No
screen names a font, because the screen that forgot to would draw in the engine's own face and
look almost right. `tools/smoke_boot.gd` pins the setting and `tests/unit/test_ui_chrome.gd`
pins the rendering: **antialiasing off, hinting off, subpixel positioning off**. Those three are
what keep a pixel font crisp, they live in the committed `.import` sidecars, and nothing else in
the build can see them - a blurred font is not a failure any other gate has a way to notice.
