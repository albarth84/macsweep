# Istruzioni per agenti e assistenti

Progetto: MacSweep, app SwiftUI per macOS (Swift Package, nessun progetto Xcode).

## Verifica prima del commit
- `swift build` deve terminare senza errori né warning.
- Non lanciare l'app con interfaccia per "provare": macOS mostra richieste di permesso
  all'utente. Usa le opzioni da riga di comando (`--report`, `--scan-types`, `--whatsapp`,
  `--check-fda`).

## Rilasciare un aggiornamento
Le app installate si aggiornano da Impostazioni › Aggiornamenti leggendo le GitHub Releases.

1. Committa le modifiche (messaggi in stile `feat: …`, `fix: …`).
2. Esegui **`scripts/release.sh X.Y.Z --local`**: aggiorna `VERSION`, crea commit e tag,
   fa il push, compila, firma e pubblica la release.
3. Se qualcosa si interrompe, rilancia lo stesso comando: riprende da dove si era fermato.

Numerazione: incrementa solo l'ultima cifra rispetto al file `VERSION` (0.1.4 → 0.1.5),
salvo indicazione esplicita di un aggiornamento importante.

Non fare `git push` o `gh release` a mano: lo script usa l'account giusto (`albarth84`)
anche se l'account `gh` attivo è un altro, e firma con il certificato
"MacSweep Self-Signed". Senza quella firma gli utenti dovrebbero ridare l'Accesso completo
al disco e l'aggiornamento in-app rifiuterebbe il pacchetto.
