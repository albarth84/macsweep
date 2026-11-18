#!/usr/bin/env bash
# Pubblica una nuova versione: aggiorna VERSION, crea il commit e il tag, fa il push.
# GitHub Actions compila l'app e crea la release con .zip, .dmg e SHA256SUMS.txt.
#
# Uso: scripts/release.sh 0.1.1
# Regola di numerazione: 0.1.0, poi 0.1.1, 0.1.2… finché non c'è un aggiornamento importante.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
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
echo "✓ Tag v$NEW pubblicato: la release apparirà su GitHub al termine della build."
