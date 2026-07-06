#!/usr/bin/env bash
# Print the embedded `run:` script of a step, so shellcheck and bats can
# exercise exactly what ships inside the YAML instead of a drifting copy.
#
# usage: extract-step.sh FILE             first step of a composite action
#        extract-step.sh FILE STEP_NAME   named step in any workflow job
set -euo pipefail

file="$1"
if [ $# -eq 1 ]; then
  yq -r '.runs.steps[0].run' "$file"
else
  name="$2" yq -r '.jobs[].steps[] | select(.name == strenv(name)) | .run' "$file"
fi
