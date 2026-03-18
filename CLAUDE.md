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

## Port mapping — CRITICAL

This container only has a few ports forwarded to the host Mac. **You MUST
use one of these ports for ANY server you start** — random/arbitrary ports
are completely inaccessible from the host.

Available container ports (check env vars to confirm):
- **3000** → `$CLODE_PORT_3000`
- **5173** → `$CLODE_PORT_5173`
- **8080** → `$CLODE_PORT_8080`
- **8888** → `$CLODE_PORT_8888`

### Rules

1. **Always pass an explicit port** to any server, script, or tool you start.
   Never let a tool pick a random port — it won't be reachable.
2. **Use `--port`, `-p`, or the tool's port flag** to force one of the above.
3. **Tell the user the host URL**, not the container URL:
   `http://localhost:$CLODE_PORT_3000` (not `localhost:3000`).
4. If you need multiple servers simultaneously, use different mapped ports
   (e.g., app on 3000, API on 8080, docs on 8888).
5. **If a tool/script picks a random port** and you can't override it, proxy
   it through a mapped port:
   ```bash
   socat TCP-LISTEN:8080,fork,reuseaddr,bind=0.0.0.0 TCP:localhost:<random-port> &
   ```
   Then tell the user: `http://localhost:$CLODE_PORT_8080`

## Clipboard

Images cannot be pasted directly. The user runs `cpaste` on their Mac to
save the clipboard image to `/tmp/clode-clipboard/clipboard.png`, which is
readable here.

## Chrome

- Headless Chromium: available via Playwright (`PLAYWRIGHT_BROWSERS_PATH` is set)
- Mac Chrome: connect via `$CHROME_CDP_URL` when user has run `chrome-debug`
