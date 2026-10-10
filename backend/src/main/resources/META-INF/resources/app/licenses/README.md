# Bundled third-party files

The users' web page loads nothing from the network: the fonts, the icons and the QR code
encoder below are served from this folder. They are not SignalHub code.

| What | Files | Version and source | Licence |
|---|---|---|---|
| Roboto (variable, every Unicode subset the page may need) | `../fonts/roboto-v51-*.woff2` | v51, Google Fonts (`fonts.gstatic.com/s/roboto/v51/`) | SIL Open Font License 1.1, `Roboto-OFL.txt` |
| Roboto Mono (variable) | `../fonts/robotomono-v31-*.woff2` | v31, Google Fonts | SIL Open Font License 1.1, `RobotoMono-OFL.txt` |
| Material Symbols Outlined (variable: weight 400, FILL 0 to 1) | `../fonts/materialsymbolsoutlined-v377-*.woff2` | v377, Google Fonts | Apache License 2.0, `MaterialSymbols-Apache-2.0.txt` |
| qrcode-generator (the QR code of a sign-in and of an invitation) | `../vendor/qrcode.mjs` | 2.0.4, `dist/qrcode.mjs` of the npm package, the same release the admin page loads from its WebJar | MIT, `qrcode-generator-MIT.txt` |

`../fonts/fonts.css` is the CSS the Google Fonts API returns for a desktop browser, with each
`url(https://fonts.gstatic.com/...)` changed to the file next to it.

The fonts are not subset: event text may be in any script, so every Unicode range of Roboto is kept
(the browser fetches only the ranges a page uses), and the icon font keeps its FILL axis, which the
selected tab and the subscribed bell use. `AppPageTest` checks that `qrcode.mjs` is byte for byte the
file of the WebJar version the backend depends on, so updating one without the other fails the build.
