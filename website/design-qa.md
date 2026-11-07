# Hasp website design QA

- Source: the generated warm editorial direction, refined by the user's later
  choice of [Kami](https://kami.tw93.fun/index-zh.html). The generated image is a
  structural reference, not an approved pixel-for-pixel typeface specification.
- Implementation: local Vite preview, `/`, overview and automatic-appearance states.
- Comparison: source and browser screenshot normalized to 1374 × 1145 CSS pixels,
  combined in a single side-by-side comparison. Browser screenshot scale: CSS.
  The desktop browser reserves 15 px for its scrollbar; content width is 1359 px.
- Full-page captures reviewed at desktop 1374 × 1145 and mobile 390 × 844.
- Responsive checks: 320, 390, 768 and 1440 CSS px. No horizontal overflow after fix.

## Fidelity surfaces

- Typography: Charter/Georgia Latin with self-hosted regular/medium WenKai Chinese.
  Chinese Kai style follows the later Kami choice. Commercial TsangerJinKai is
  intentionally not redistributed. Type hierarchy, wrapping and small labels checked.
- Layout: pill navigation, left-aligned brand/hero, blue primary action, wide image
  stage, caption and tabs. Additional content uses definition rows, numbered setup
  steps and restrained dividers. Mobile layout preserves the same content order.
- Color: Kami parchment #F5F4ED, ink blue #1B365D, warm neutral text and hairlines.
- Imagery: original paper wallpaper, actual app icon and production SwiftUI panel
  renders. Fixtures are clearly marked synthetic. No Mole assets redistributed.
  The mock's invented system menu strip is intentionally omitted.
- Copy: real capabilities, macOS 26 minimum, preview lane and missing notarization
  are explicit. No invented counters, testimonials, prices or working-device claims.

## Findings and iterations

1. P2, 320 px: the single-line hero heading exceeded the available width.
   Reduced the <=360 px font size from 28 px to 24 px. Browser recheck showed
   document/client widths 305/305, 375/375, 753/753 and 1425/1425 at the four
   viewports. Re-captured desktop and reviewed the mobile full page after this fix.
2. The first automatic-appearance capture was taken during the fade and was not
   valid final-state evidence. Waited for panel opacity 1 and the completed wallpaper
   filter, then reviewed the settled dark panel. No remaining visual defect.

Focused checks: native panel labels, hero typography/actions, mobile navigation
and gallery tabs inspected in the viewport captures; full-page captures establish
section rhythm. Original source and implementation were viewed in one composite.
Local evidence is kept in the ignored build/ and .playwright-mcp/ directories.

## Interaction checks

- All four gallery tabs; ArrowRight, Home and focus movement.
- Mobile navigation opening, link navigation and closing.
- FAQ native disclosure expansion.
- All images load; web fonts load.
- Browser console: no errors or warnings on the local preview.
- Download target matches the release asset name; public download readback is part
  of the release verification, separate from visual QA.
- Production build, four packaging tests and dependency audit pass.

final result: passed
