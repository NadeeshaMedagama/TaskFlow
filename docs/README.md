# docs

Everything that describes the work rather than being part of the running
application.

| Path | What it is |
|---|---|
| `TaskFlow_Docker_Mentoring_Task.pdf` | The original brief — Phase 1 of the Cloud-Native Engineering Mentoring Track |
| `TaskFlow_Phase1_Docker_Submission_Report.docx` | **The submission.** 18 pages: measured image sizes, the Part 5 defect analysis, verification evidence and the reflection answers |
| `debugging-exercise/` | The broken compose file from Part 5, kept so the fixes can be walked through side by side |
| `evidence/` | The 14 screenshots referenced as Figures 2–16 in the report |

## Start here

Read the submission report. It is self-contained and answers the brief section
by section:

| Report section | Covers |
|---|---|
| §1 | Summary and the deliverables checklist |
| §2 | Architecture |
| §3 | Parts 1–3 — the two images and the Compose stack |
| §4 | Part 4 — measured before/after image sizes and build-cache behaviour |
| §5 | Part 5 — all 17 defects found in the broken compose file |
| §6 | Part 6 — resource limits, published images, override split, smoke test |
| §7 | Verification |
| §8 | The four reflection questions |

## Published images

Both are public on Docker Hub:

- https://hub.docker.com/r/nadeeshamedagama/taskflow-api
- https://hub.docker.com/r/nadeeshamedagama/taskflow-web

```bash
docker pull nadeeshamedagama/taskflow-api:1.0.0
docker pull nadeeshamedagama/taskflow-web:1.0.0
```

A `taskflow-api:debian` tag also exists. It is not a deployment target — it is
the single-stage build on the full Node base, kept so the 1.63 GB vs 246 MB
comparison in the report can be reproduced.

## Phase 2

Not started. Phase 2 takes these same images to Kubernetes. The report answers
the Phase 2 *reflection* question in §8.1, but no manifests exist yet.
