# Drawing sources

These are the approved drawings for the users feature and, since R73, for the
operator's admin page, and, since R81, for answering an event: the same `.dc.html`
sources as the Claude Design project, downloaded byte for byte, except that
the external URLs were changed to local `vendor/` paths (see
`vendor/LICENSES.md` and `vendor/URL-EDITS.md`). The `.dc.html` pages are the
source of truth. The images in `../images/` are previews of them.

## The pages

| Pages | What they draw |
| --- | --- |
| `SignalHub Design System.dc.html` | The design system, including the *Admin page* section (R73). |
| `App - ...`, `Web - Sign in`, `Web - Inbox and producers`, `Web - Settings, people and states` | The users' app and web page (R64). |
| `Web - New producer action` | The users' web page's New producer button: three options, A chosen (R73). |
| `Admin - Shell and Producers`, `Admin - Events`, `Admin - Events states`, `Admin - Events dialogs`, `Admin - Devices`, `Admin - Devices dialogs`, `Admin - Users`, `Admin - Users dialogs`, `Admin - Status and sign-in`, `Admin - Status`, `Admin - Status states`, `Admin - Light theme check` | The operator's admin page at `/admin/` (R73). Previews are in `../../admin/images/`. |
| `admin-events.css`, `admin-people.css`, `admin-status.css`, `admin-fix-a.css`, `admin-fix-b.css` | The admin pages' shared stylesheets, loaded in this order. `admin-events.css` holds the dark and the light token sets. |
| `App - Answering an event`, `App - Notification actions`, `Web - Answering an event` | A producer's question and its answer in the app, in the Android notification and on the users' web page: option A chosen, B and C kept (R81). Previews are in `../../answers/images/`. |
| `Admin - Questions and answers`, `admin-answers.css` | How the operator reads a question and its answer on the admin page, the list markers, the test event's *Ask for an answer* section and the producer's *Who can answer* (R81). `admin-answers.css` is loaded after `admin-events.css` and `admin-fix-a.css`. Previews are in `../../answers/images/admin/`. |
| `Prototype - App`, `Prototype - Web` | The clickable prototypes (R64). |

## View

```sh
python3 -m http.server      # in this folder
```

Open `http://127.0.0.1:8000/` and a page, for example
`http://127.0.0.1:8000/Web%20-%20Sign%20in.dc.html`. The two `Prototype - ...`
pages are clickable: pick a flow, then click the outlined element.

The admin pages are plain drawings, not prototypes: read them, do not click
through them. They need no network: fonts (Roboto, Roboto Mono, Material Symbols), React and
Babel are in `vendor/`. Serve them over HTTP; opening the files directly with
`file://` may not work.

## Use

Implementers read the page source for the exact CSS values and copy, and
render the pages to compare their work with the drawing.
