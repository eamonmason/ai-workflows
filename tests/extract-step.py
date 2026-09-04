#!/usr/bin/env python3
"""Print the exact `run:` body of a step, so the tests exercise the bytes that
actually run on the runner rather than a copy that can drift from them.

usage: extract-step.py <workflow.yml> <job> <step-id-or-name>
"""
import sys
import yaml

wf, job, want = sys.argv[1], sys.argv[2], sys.argv[3]
steps = yaml.safe_load(open(wf))["jobs"][job]["steps"]
for step in steps:
    if want in (step.get("id"), step.get("name")):
        sys.stdout.write(step["run"])
        break
else:
    sys.exit(f"no step {want!r} in {wf}:{job}")
