# Hasp website

Chinese product landing page using Kami's parchment/ink-blue palette and a
serif hierarchy, with real production panel renders and an original wallpaper.
Chinese web fonts use OFL-licensed LXGW WenKai instead of Kami's commercial
TsangerJinKai. See [third-party notices](THIRD_PARTY_NOTICES.md).

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4173
npm run build
npm run test:sites
```

The Vite build emits a standalone static site in `dist/client` plus the
preserved optional Sites worker wrapper. No analytics, API keys, accounts or
backend are required. The website is not automatically deployed by a push.

Download links are pinned to GitHub Release `v0.1.0-preview.1`. Update the
version and asset filename together in `src/App.jsx` for the next release.
Do not advertise signing, notarization or system verification that the actual
release package has not passed.

To refresh production panel images, compile `scripts/render-assets.swift`
with all `../Hasp/*.swift` except `HaspApp.swift`, then run the resulting binary
with `public/assets` as its output directory. It uses isolated preferences,
synthetic devices and invisible windows; it never starts live model services.

To refresh font subsets after editing Chinese copy, create a local Python
venv under the ignored root `build` directory, install `fonttools[woff]==4.68.0`,
and run `scripts/subset-fonts.py`. Font sources are pinned to an upstream commit.
