#!/usr/bin/env bash
set -euo pipefail
# Generate Flutter's platform scaffolding without overwriting the authored lib/ source.
flutter create --platforms=android --project-name kulcskod .
