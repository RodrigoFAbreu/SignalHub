# Drawing sources

These are the approved drawings for the users feature: the same `.dc.html`
sources as the Claude Design project, downloaded byte for byte, except that
the external URLs were changed to local `vendor/` paths (see
`vendor/LICENSES.md` and `vendor/URL-EDITS.md`). The `.dc.html` pages are the
source of truth. The images in `../images/` are previews of them.

## View

```sh
python3 -m http.server      # in this folder
```

Open `http://127.0.0.1:8000/` and a page, for example
`http://127.0.0.1:8000/Web%20-%20Sign%20in.dc.html`. The two `Prototype - ...`
pages are clickable: pick a flow, then click the outlined element.

They need no network: fonts (Roboto, Roboto Mono, Material Symbols), React and
Babel are in `vendor/`. Serve them over HTTP; opening the files directly with
`file://` may not work.

## Use

Implementers read the page source for the exact CSS values and copy, and
render the pages to compare their work with the drawing.
