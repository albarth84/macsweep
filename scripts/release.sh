#!/usr/bin/env bash
# Pubblica una nuova versione: aggiorna VERSION, crea il commit e il tag, fa il push.
#
# Uso: scripts/release.sh 0.1.5 [--local]
#
# Prima di rilasciare scrivi le note in italiano in release-notes/X.Y.Z.md (elenco puntato,
# per l'utente: cosa cambia, non come). Compaiono in Impostazioni › Aggiornamenti.
#   --local  compila, firma e pubblica la release da questo Mac (consigliato: i runner macOS
#            di GitHub restano spesso in coda); la CI poi salta la pubblicazione.
#
# Regola di numerazione: 0.1.0, poi 0.1.1, 0.1.2… finché non c'è un aggiornamento importante.
#
# Lo script è riprendibile: se si interrompe (push fallito, firma, upload…), rilancialo con la
# stessa versione e salta i passaggi già fatti.
#
# Funziona qualunque sia l'account `gh` attivo: usa sempre il proprietario del repository.
set -euo pipefail
cd "$(dirname "$0")/.."

OWNER="albarth84"
REPO="$OWNER/macsweep"
IDENTITY="MacSweep Self-Signed"

NEW="${1:-}"
LOCAL=0
[[ "${2:-}" == "--local" ]] && LOCAL=1
if ! [[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Uso: scripts/release.sh X.Y.Z [--local]" >&2
    exit 1
fi

# Token del proprietario del repo, indipendente dall'account gh attivo.
if ! GH_TOKEN="$(gh auth token -u "$OWNER" 2>/dev/null)"; then
    echo "gh non ha un login per $OWNER: esegui 'gh auth login' con quell'account." >&2
    exit 1
fi
export GH_TOKEN
# Git usa l'utente nel remote per scegliere le credenziali giuste (gh auth git-credential).
git remote set-url origin "https://$OWNER@github.com/$REPO.git"

if [[ $LOCAL == 1 ]] && ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    echo "Manca il certificato \"$IDENTITY\" nel portachiavi: vedi README › Firma." >&2
    exit 1
fi

NOTES="release-notes/$NEW.md"
if [[ ! -s "$NOTES" ]]; then
    echo "Mancano le note di rilascio: scrivi in italiano $NOTES (elenco puntato) e committalo." >&2
    exit 1
fi

if gh release view "v$NEW" -R "$REPO" >/dev/null 2>&1; then
    echo "La release v$NEW esiste già su GitHub." >&2
    exit 1
fi

# 1. Commit di release (saltato se già fatto in un tentativo precedente).
CURRENT="$(tr -d '[:space:]' < VERSION)"
if [[ "$CURRENT" == "$NEW" && "$(git log -1 --format=%s)" == "chore: release $NEW" ]]; then
    echo "▸ Commit di release già presente: riprendo."
else
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Ci sono modifiche non committate: fai prima il commit." >&2
        exit 1
    fi
    echo "$NEW" > VERSION
    git add VERSION
    git commit -m "chore: release $NEW"
fi

# 2. Tag.
if git rev-parse "v$NEW" >/dev/null 2>&1; then
    echo "▸ Tag v$NEW già presente."
else
    git tag -a "v$NEW" -m "MacSweep $NEW"
fi

# 3. Push di branch e tag.
git push origin HEAD "v$NEW"

if [[ $LOCAL == 0 ]]; then
    echo "✓ Tag v$NEW pubblicato: la release apparirà su GitHub al termine della build."
    exit 0
fi

# 4. Build firmata e pubblicazione.
REQUIRE_SIGNING=1 VERSION="$NEW" scripts/build-app.sh --zip --dmg
(cd build && shasum -a 256 "MacSweep-$NEW.zip" "MacSweep-$NEW.dmg" > SHA256SUMS.txt)
gh release create "v$NEW" -R "$REPO" --verify-tag --title "MacSweep $NEW" --notes-file "$NOTES" \
    "build/MacSweep-$NEW.zip" "build/MacSweep-$NEW.dmg" build/SHA256SUMS.txt
echo "✓ Release v$NEW pubblicata: le app installate la riceveranno da Impostazioni › Aggiornamenti."
