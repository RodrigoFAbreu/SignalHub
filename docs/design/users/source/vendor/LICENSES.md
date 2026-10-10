# Vendored third-party resources

These files are copies of the public resources the drawings load, kept here so
the pages render with no network. They are not SignalHub code.

| Resource | Version / source | Licence | Licence text |
|---|---|---|---|
| Roboto (variable, woff2, `fonts/roboto-*`) | Google Fonts CSS API v2, files `fonts.gstatic.com/s/roboto/v51/` | SIL Open Font License 1.1 (as published by Google Fonts) | `licenses/Roboto-OFL.txt` |
| Roboto Mono (variable, woff2, `fonts/robotomono-*`) | Google Fonts CSS API v2, files `fonts.gstatic.com/s/robotomono/` | SIL Open Font License 1.1 (as published by Google Fonts) | `licenses/RobotoMono-OFL.txt` |
| Material Symbols Outlined (variable, one woff2, `fonts/materialsymbolsoutlined-v377-*`) | Google Fonts CSS API v2, `fonts.gstatic.com/s/materialsymbolsoutlined/v377/` | Apache License 2.0 | `licenses/MaterialSymbols-Apache-2.0.txt` |
| React | 18.3.1, `https://unpkg.com/react@18.3.1/umd/react.production.min.js` | MIT | `licenses/react-LICENSE.txt` |
| ReactDOM | 18.3.1, `https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js` | MIT | `licenses/react-dom-LICENSE.txt` |
| Babel standalone | 7.29.0, `https://unpkg.com/@babel/standalone@7.29.0/babel.min.js` | MIT | `licenses/babel-standalone-LICENSE.txt` |

The OFL texts are the ones in the `google/fonts` repository (`ofl/roboto`,
`ofl/robotomono`); the Apache text is the `google/material-design-icons`
LICENSE. The font CSS in `css/` is what the Google Fonts CSS API returned for
a desktop Chrome user agent, with each `url(https://fonts.gstatic.com/...)`
changed to `url(../fonts/<file>)`.

The JavaScript files are byte for byte what unpkg served; `support.js` still
checks their SHA-384 integrity hashes, so a wrong file would not load.

## Which CSS file replaces which URL

- `css/roboto-roboto-mono.css`: `css2?family=Roboto:wght@400;500;700&family=Roboto+Mono&display=swap`
- `css/roboto-roboto-mono-400-500.css`: `css2?family=Roboto:wght@400;500;700&family=Roboto+Mono:wght@400;500&display=swap`
- `css/material-symbols-outlined.css`: `css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0..1,0&display=block`

`_ds/*/styles.css` (not loaded by any page) still has an `@import` of Inter
from Google Fonts. It is the design-system source file, left as downloaded.
