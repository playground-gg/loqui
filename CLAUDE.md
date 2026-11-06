# Loqui

App iOS open source (MIT) di dettatura on-device, stile Wispr Flow/Handy.
iOS 26+, Swift 6, SwiftUI. Piano, milestone e stato: `PLAN.md`.

## Principi non negoziabili

- **Privacy verificabile.** La tastiera non contiene codice di rete. L'app usa la rete solo per
  scaricare modelli. Niente account, analytics, telemetria, cattura dello schermo. Cronologia con
  retention configurabile, anche a zero. L'audio resta in RAM e non si scrive su disco.
- **Efficienza.** Neural Engine prima di tutto, modello caldo, microfono rilasciato dopo un timeout di
  inattività. Dettatura a tocchi: il secondo tocco ferma e le pause non interrompono nulla. Obiettivo:
  testo visibile entro 1 s dallo stop.
  Si misurano anche RAM e batteria, non solo la velocità.
- **Ottimizzato per iPhone.** Solo varianti Core ML su ANE, con le regole in `PLAN.md` (sezione 2). Un
  modello il cui encoder non gira su ANE non può essere il consigliato.
- **Qualità.** Pulizia Exact / Basic / Smart con "annulla pulizia". Mai riscrivere in modo aggressivo
  per default.
- **Semplicità.** Codice facile da forkare. Ogni motore di trascrizione sta dietro un protocollo comune.

## Architettura

- XcodeGen (`project.yml`): `Loqui.xcodeproj` è generato e non va modificato né committato.
- Target: `Loqui` (app), `LoquiKeyboard`, `LoquiLiveActivity`, pacchetto SPM `LoquiCore`.
- L'app è il motore (modello, audio, Live Activity, intent). La tastiera è solo UI (< 40 MB).
- IPC: App Group + Darwin notification, niente polling.
- La tastiera linka solo `LoquiShared`, mai FluidAudio, WhisperKit o Network. Dopo ogni build esegui
  `scripts/verify-keyboard-privacy.sh`: se fallisce, la modifica non è finita.

## Build e installazione sull'iPhone

Team ID e UDID stanno in `.env.local`, escluso da git. Se `TEAM_ID` è vuoto, chiederlo all'utente.

```sh
set -a; source .env.local; set +a

xcodegen generate

xcodebuild -project Loqui.xcodeproj -scheme Loqui -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_UDID" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" -quiet build

xcrun devicectl device install app --device "$DEVICE_UDID" \
  build/Build/Products/Debug-iphoneos/Loqui.app

xcrun devicectl device process launch --device "$DEVICE_UDID" \
  --terminate-existing "$BUNDLE_ID"
```

Il lancio fallisce se l'iPhone è bloccato: in quel caso chiedere di sbloccarlo.

## Regole di lavoro

- **Dopo ogni modifica compila e installa sull'iPhone** con i comandi qui sopra. Una modifica non è
  finita finché non gira sul dispositivo.
- **Correggi da solo gli errori di build**, senza chiedere e senza aggirarli disattivando controlli
  (concorrenza stretta di Swift 6 compresa).
- **Fermati e chiedi quando serve un gesto manuale**: login in Xcode, fiducia nel certificato,
  permessi, attivazione della tastiera e di Accesso completo, registrazioni, test sul campo.
  Di' esattamente cosa fare e dove.
- Compilare non vuol dire funzionare: se un comportamento si può verificare solo a mano sul telefono,
  dichiaralo non verificato finché l'utente non conferma.
- Accuratezza dei modelli: valutazioni di Handy (WER su FLEURS), con la fonte indicata. Velocità, RAM e
  batteria: solo misurate sul dispositivo, indicando dispositivo, versione iOS e modello.
- Non committare UDID, Team ID, modelli o registrazioni vocali.
- A fine milestone aggiorna lo stato in `PLAN.md`. La fase 2 parte solo quando la fase 1 è stabile.
