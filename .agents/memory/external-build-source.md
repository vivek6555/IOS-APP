---
name: External build source
description: External CI source is separate from the task workspace, even when the user reports uploading the whole project.
---

Treat an external CI checkout as separate from the task workspace. Verify its actual tree and configuration before changing build paths or recommending another hosted run.

**Why:** Repeated missing-directory reports could not be resolved from local files. A repository archive eventually showed that the Swift source was absent and the YAML was older, despite the local tree containing both and the user reporting a full upload.

**How to apply:** Inspect the selected branch's tree or archive first. Do not infer remote synchronization from local tracked files or promise that a local change has reached GitHub. Never hide missing source by skipping tests.
