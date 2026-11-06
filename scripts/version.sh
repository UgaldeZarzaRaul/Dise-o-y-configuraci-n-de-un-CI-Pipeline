#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Calcula la versión de la liberación siguiendo Versionado Semántico (SemVer).
#   - Push de un tag vMAJOR.MINOR.PATCH  -> versión final   (ej. v1.2.0)
#   - Push a rama / ejecución manual     -> release candidate del siguiente
#                                           PATCH (ej. v1.2.1-rc.37)
# Salida en formato clave=valor (compatible con $GITHUB_OUTPUT).
# -----------------------------------------------------------------------------
set -euo pipefail

SEMVER_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
REF_TYPE="${GITHUB_REF_TYPE:-branch}"
REF_NAME="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo local)}"
RUN_NUMBER="${GITHUB_RUN_NUMBER:-0}"
SHORT_SHA="$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"

if [[ "$REF_TYPE" == "tag" ]]; then
  if [[ ! "$REF_NAME" =~ $SEMVER_RE ]]; then
    echo "::error::El tag '$REF_NAME' no cumple el formato vMAJOR.MINOR.PATCH" >&2
    exit 1
  fi
  VERSION="$REF_NAME"
  CHANNEL="release"
else
  LAST_TAG="$(git tag --list 'v*.*.*' --sort=-v:refname 2>/dev/null | grep -E "$SEMVER_RE" | head -n1 || true)"
  LAST_TAG="${LAST_TAG:-v0.0.0}"
  IFS=. read -r MAJOR MINOR PATCH <<< "${LAST_TAG#v}"
  VERSION="v${MAJOR}.${MINOR}.$((PATCH + 1))-rc.${RUN_NUMBER}"
  CHANNEL="candidate"
fi

echo "version=${VERSION}"
echo "channel=${CHANNEL}"
echo "sha=${SHORT_SHA}"
echo "artifact=laravel-release-${VERSION}"
