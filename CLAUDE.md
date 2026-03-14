# Claude Code — Docker environment

## Dev servers must bind to 0.0.0.0

This session runs inside Docker. Port mapping only works when servers listen
on `0.0.0.0` (all interfaces), not `127.0.0.1` (loopback-only).

The `HOST=0.0.0.0` env var is already set, which many frameworks pick up
automatically. For frameworks that don't, always pass the explicit flag:

| Tool | Command |
|---|---|
| Vite | `vite --host` or `HOST=0.0.0.0` (auto) |
| Next.js | `next dev -H 0.0.0.0` |
| CRA | `HOST=0.0.0.0` (auto) |
| Python http.server | `python -m http.server --bind 0.0.0.0 <port>` |
| Flask | `app.run(host='0.0.0.0')` |
| FastAPI/uvicorn | `uvicorn main:app --host 0.0.0.0 --port <port>` |
| Express / Node | `app.listen(port, '0.0.0.0')` |

## Port mapping

Each container port listed in `CLODE_EXPOSE_PORTS` is mapped to a dynamic
host port. The env var `CLODE_PORT_<n>` tells you the host-side port:

- `CLODE_PORT_3000` → host port for container port 3000
- `CLODE_PORT_5173` → host port for container port 5173
- etc.

When you start a server, tell the user the correct URL:
`http://localhost:$CLODE_PORT_3000` (not `localhost:3000`).

## Clipboard

Images cannot be pasted directly. The user runs `cpaste` on their Mac to
save the clipboard image to `/tmp/clode-clipboard/clipboard.png`, which is
readable here.

## Chrome

- Headless Chromium: available via Playwright (`PLAYWRIGHT_BROWSERS_PATH` is set)
- Mac Chrome: connect via `$CHROME_CDP_URL` when user has run `chrome-debug`
