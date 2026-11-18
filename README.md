# MacSweep

App nativa macOS (SwiftUI) per capire **dove finisce lo spazio sul disco** e fare pulizia in sicurezza.

## Funzioni

- **Panoramica**: anello di occupazione del disco, spazio recuperabile in sicurezza e accesso rapido agli strumenti.
- **Scansione file**: scegli un'unità (interna o esterna) o una cartella; MacSweep classifica ogni file per tipo (immagini, video, audio, documenti, archivi/dischi/VM, app, codice e dati) con avanzamento circolare, contatori in tempo reale, pausa e interruzione. Nei risultati: categorie, ricerca, filtri per dimensione ed età, tabella ordinabile, miniature e anteprima Quick Look, spostamento multiplo nel Cestino.
- **Mappa disco**: grafico sunburst interattivo (clic per entrare in una cartella, clic al centro per risalire), lista ordinata per dimensione, vista "file più grandi", barra del volume con spazio usato / eliminabile dal sistema / libero.
- **Pulizia**: cache utente, log, cache delle app Electron/Chromium, Xcode DerivedData e DeviceSupport, cache dei package manager (npm, pip, uv, Gradle, Cargo…), `node_modules`, installer nei Download, backup iOS, Cestino.
- **Pulizia dati IA**: cache e log di Claude, Claude Code, ChatGPT, Codex, Cursor, LM Studio; cronologia delle sessioni degli agenti; modelli locali scaricati (Ollama, LM Studio, Hugging Face, Whisper, PyTorch, VM di Claude). Ogni categoria ha un livello di rischio.
- **Disinstallazione completa delle app**: scegli un'app installata e MacSweep trova preferenze, cache, container, group container, stato salvato, log, cookie, LaunchAgent/Daemon e helper privilegiati collegati, da selezionare e spostare nel Cestino.
- **File orfani**: trova dati lasciati da app non più installate, con un livello di confidenza (alta / media / bassa). I servizi di avvio che puntano a eseguibili inesistenti vengono segnalati come orfani certi.

## Sicurezza

- Tutto viene **spostato nel Cestino**, mai cancellato direttamente (tranne lo svuotamento del Cestino stesso).
- Percorsi di sistema e cartelle principali (`/System`, `/usr`, `~/Library`, `~/Documents`…) sono bloccati da una protezione interna.
- Per i file di sistema (es. `/Library/LaunchDaemons`) l'app chiede la password tramite il prompt standard di macOS.
- Gli elementi a rischio o a confidenza bassa non sono mai preselezionati.

## Requisiti

- macOS 14 Sonoma o successivo
- Xcode 16+ (o Swift 5.10+ da riga di comando) per compilare

## Compilare ed eseguire

```bash
# esecuzione rapida in sviluppo
swift run

# bundle .app in build/MacSweep.app (aggiungi --dmg per l'immagine disco)
scripts/build-app.sh
open build/MacSweep.app
```

Per aprire il progetto in Xcode: `open Package.swift`.

### Report da terminale (non elimina nulla)

```bash
swift run MacSweep --report            # categorie di pulizia e file orfani
swift run MacSweep --report "Slack"    # anche i file collegati a un'app
swift run MacSweep --scan-types ~      # statistiche per tipo di file
```

In sviluppo puoi aprire direttamente una sezione: `swift run MacSweep -page deepScan`
(`overview`, `diskMap`, `deepScan`, `cleanup`, `apps`, `orphans`).

### Icona

L'icona è generata in codice: `swift scripts/make-icon.swift` produce `Resources/AppIcon.icns`.

## Permessi

Per analizzare tutte le cartelle concedi **Accesso completo al disco**:
Impostazioni di Sistema › Privacy e sicurezza › Accesso completo al disco › aggiungi MacSweep.
L'app mostra un avviso con il collegamento diretto quando il permesso manca.

L'app non è firmata con un certificato Developer ID: al primo avvio fai clic destro › Apri.

## Release

Un tag `vX.Y.Z` avvia GitHub Actions, che compila l'app universale (Apple Silicon + Intel) e pubblica il `.dmg` nella release.

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Struttura

```
Sources/MacSweep/
├── App/        entry point e navigazione
├── Models/     stato osservabile delle viste e modelli dati
├── Services/   scansione disco, pulizia, ricerca app e orfani, cestino
└── Views/      SwiftUI (sunburst, pulizia, app, orfani)
```

## Licenza

MIT
