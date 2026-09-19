# taskflow-web

The front end: a single static HTML page served by Nginx, which also reverse-proxies
API calls so the browser only ever talks to one origin.

## Files

| File | Purpose |
|---|---|
| `index.html` | The whole front end — vanilla HTML and JS, no build step |
| `nginx.conf` | Server block: static root plus the `/api/` and `/health` proxy rules |
| `Dockerfile` | Copies both into `nginx:1.27-alpine` |

## How the proxy works

`index.html` fetches the relative path `/api/tasks`, so every API call arrives at
Nginx first and is forwarded to the API container:

```nginx
location /api/ {
    proxy_pass http://taskflow-api:4000;
}

location = /health {
    proxy_pass http://taskflow-api:4000;
}
```

Three consequences, all of them the point:

- The API's address never reaches the browser, so it never needs rebuilding into
  the page when the API moves.
- There is no cross-origin request, so no CORS preflight.
- The API does not need to be published to the host at all.

It is also the shape that maps onto a Kubernetes Ingress in Phase 2.

## Four things that are easy to get wrong here

- **No trailing slash on `proxy_pass`.** `proxy_pass http://taskflow-api:4000;`
  preserves the full URI, so `/api/tasks` is forwarded as `/api/tasks`. Adding a
  slash would strip the `/api` prefix and request `/tasks`, which the API does
  not serve.
- **`/health` needs its own rule.** It sits outside the `/api/` prefix, so
  without one it would fall through to `location /` and 404 against the static
  root. The `=` makes it an exact match, so it cannot also swallow `/healthz`.
- **The config must overwrite `default.conf`.** The stock image already does
  `include /etc/nginx/conf.d/*.conf`, so the server block belongs in `conf.d` —
  and if it is added under a different name, the image's stock welcome-page
  server is left behind competing for port 80.
- **`proxy_set_header` inheritance is all-or-nothing.** Nginx inherits the
  `server`-level headers into a location only when that location declares none
  of its own. Adding a single header inside `location /api/` would silently drop
  the other four, so re-declare all of them if you add one.

## Ports

Nginx listens on **80 inside the container**. Compose publishes it as `"8080:80"`,
so the application is reached at `http://localhost:8080`. Getting that mapping
backwards (`"80:8080"`) is one of the defects fixed in the Part 5 exercise — it
points at a dead port and tries to bind a privileged host port.

## Editing the page

`docker-compose.override.yml` bind-mounts both files, so during development you
can edit `index.html` and just refresh. `nginx.conf` is read once at startup, so
after changing it:

```bash
docker compose exec taskflow-web nginx -s reload
```
