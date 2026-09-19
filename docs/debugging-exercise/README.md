# Part 5 — the debugging exercise

`docker-compose.broken.yml` is the file supplied in the brief. The brief says it
contains "at least six distinct issues"; seventeen were found. It is kept here
unchanged so the fixes can be walked through against the working
`docker-compose.yml` at the project root.

The full analysis — what each defect was, why it matters and how it was fixed —
is §5 of the submission report. This is the short index.

## Defects that stop the stack from starting

| # | Defect | Effect |
|---|---|---|
| 1 | Duplicate `environment:` mapping key (lines 5 and 15) | The file does not parse at all |
| 2 | Inconsistent indentation | Keys attach to the wrong service, or fail to parse |
| 8 | `DB_HOST: postgres` | No service has that name, so the API cannot resolve its database |
| 6 | `DB_PASSWROD` misspelled | The password never arrives; Postgres rejects the auth |
| 13 | `ports: "80:8080"` reversed | Points at a dead port and binds a privileged host port |

## Defects that let it start but break it

| # | Defect | Effect |
|---|---|---|
| 9 | No volume on the database | `docker compose down` destroys every task |
| 10 | `init.sql` never mounted | The `tasks` table is never created; `GET /api/tasks` returns 500 |
| 11 | No health checks | Readiness cannot be expressed |
| 12 | `depends_on` without a condition | The API starts hammering a Postgres that is still initialising |
| 17 | API does not depend on the cache | Redis may be absent at connect time |

## Bad practices that would ship

| # | Defect | Effect |
|---|---|---|
| 3 | `version: "3.9"` | Obsolete under Compose v2 |
| 4 | DB config hard-coded in the compose file | Credentials disclosed to anyone with repository access |
| 5 | `DB_PASSWORD` in the compose file | A secret in a tracked file |
| 7 | `ports: - "4000"` | Publishes on a random ephemeral host port |
| 14 | `image: postgres:latest` | An unpinned tag can jump a major version |
| 15 | Database published on `5432:5432` | Exposes PostgreSQL to the host and LAN |
| 16 | No explicitly-named network | Services land on the implicit default network |

## Reproducing the failure

```bash
# from the project root
docker compose -f docs/debugging-exercise/docker-compose.broken.yml config
```

`docker compose config` is the fastest way to see the parse and schema errors
without waiting for anything to start.

The trailing comments inside the file are the original working notes taken while
diagnosing it, kept as they were written.
