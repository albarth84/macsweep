#!/usr/bin/env bash
# Pubblica una nuova versione: aggiorna VERSION, crea il commit e il tag, fa il push.
# GitHub Actions compila l'app e crea la release con .zip, .dmg e SHA256SUMS.txt.
#
# Uso: scripts/release.sh 0.1.1 [--local]
#   --local  compila e pubblica la release da questo Mac (utile se i runner macOS
#            di GitHub sono in coda); la CI poi salta la pubblicazione.
# Regola di numerazione: 0.1.0, poi 0.1.1, 0.1.2… finché non c'è un aggiornamento importante.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
LOCAL=0
[[ "${2:-}" == "--local" ]] && LOCAL=1
if ! [[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Uso: scripts/release.sh X.Y.Z" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ci sono modifiche non committate: fai prima il commit." >&2
    exit 1
fi
if git rev-parse "v$NEW" >/dev/null 2>&1; then
    echo "Il tag v$NEW esiste già." >&2
    exit 1
fi

echo "$NEW" > VERSION
git add VERSION
git commit -m "chore: release $NEW"
git tag -a "v$NEW" -m "MacSweep $NEW"
git push origin HEAD "v$NEW"

if [[ $LOCAL == 1 ]]; then
    VERSION="$NEW" scripts/build-app.sh --zip --dmg
    (cd build && shasum -a 256 "MacSweep-$NEW.zip" "MacSweep-$NEW.dmg" > SHA256SUMS.txt)
    gh release create "v$NEW" --verify-tag --title "MacSweep $NEW" --generate-notes \
        "build/MacSweep-$NEW.zip" "build/MacSweep-$NEW.dmg" build/SHA256SUMS.txt
    echo "✓ Release v$NEW pubblicata."
else
    echo "✓ Tag v$NEW pubblicato: la release apparirà su GitHub al termine della build."
fi
