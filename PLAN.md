# Loqui: piano

Stato: **M3 ridotta e funzionante, sviluppo in pausa per scelta dell'utente.** Confermati sul telefono: dettatura, cambio
di lingua, download in background, eliminazione, dettatura dalla tastiera, partenza automatica, ritorno istantaneo e
annulla. Tastiera a 11,6 MB all'apertura (obiettivo sotto 40 MB, picco in uso non misurato), script di privacy verde e
provato anche su un binario con codice di rete. Misure: [modelli](docs/benchmarks/2026-11-06-iphone17pro.md),
[lingue](docs/benchmarks/2026-11-06-multilingua.md), [background](docs/benchmarks/2026-11-06-background.md).
Ultima revisione: 2026-11-06.

**Sospesi su decisione dell'utente:** Action Button, Centro di Controllo e Live Activity. Non si costruiscono per ora.

**Da provare:** batteria con il microfono pronto (`--auto-battery-check`, pronta, non eseguita; il default di 3 minuti
resta provvisorio), dettatura in modalità aereo, dettatura oltre il minuto, tocco a vuoto.

**Da rivedere:** all'utente non piacciono le notifiche automatiche del download in background.

**Decisione: tastiera (opzione A).** Mini-tastiera: scegliendola dal globo la dettatura parte da sola, e all'inserimento
si torna subito a quella abituale. Il microfono resta pronto per un tempo scelto dall'utente: default provvisorio 3
minuti, da rivedere dopo la prova sulla batteria. Senza pausa di ritorno non c'è "annulla pulizia" sulla tastiera: da
ripensare in M4. Annulla scarta la dettatura in corso; stop automatico dopo 10 minuti. Limite: con più di due tastiere
attive il ritorno va alla successiva, non per forza a quella di prima.

**Da rivedere:** all'utente non piacciono le notifiche automatiche del download in background. Si riprende più avanti.

Dispositivo di test: iPhone 17 Pro, iOS 27.0. Toolchain: Xcode 27.2, Swift 6.4, XcodeGen 2.46.

**Account:** per ora Apple gratuito (team personale). L'app firmata scade dopo 7 giorni e va reinstallata;
limiti di 3 app sul dispositivo e 10 App ID ogni 7 giorni [V, forum e aiuto Apple]. Conviene quindi non
cambiare i bundle ID. Da verificare in M2 che App Group funzioni col team personale [I]: se non funziona,
tastiera e IPC richiedono l'account a pagamento. TestFlight (M5) lo richiede comunque.

**Microfono silenziato da iOS.** Il 2026-11-06 l'ingresso ha dato zeri esatti in ogni configurazione, anche con
`AVAudioRecorder` e permesso concesso; poco dopo è tornato a funzionare senza modifiche che lo spieghino. Causa non
accertata; sospetto: una sessione di DeviceHub (Xcode) sull'iPhone. L'app ora lo segnala con un messaggio dedicato.

**Decisione: multilingua.** Ogni utente sceglie "le mie lingue" tra 31 e cambia quella attiva dalla dettatura. Il
consigliato dipende dalla lingua attiva. Parakeet riconosce la lingua da solo e, nella prova con voci sintetiche,
regge italiano e inglese mescolati; Whisper può perdere frasi intere
([risultati](docs/benchmarks/2026-11-06-multilingua.md)). L'utente ha confermato il cambio di lingua con la propria voce.

**Decisione: dettatura a tocchi.** Un tocco avvia, il secondo ferma, e l'audio viene trascritto tutto insieme.
Le pause non interrompono nulla. L'obiettivo diventa: testo entro 1 s dallo stop. Il testo non compare mentre
parli: l'anteprima durante la dettatura è da valutare in M2. Il tempo di trascrizione cresce con la durata
dell'audio, quindi va misurato anche su dettature lunghe. Silero VAD non serve alla segmentazione: torna in
M3 solo per il rilascio del microfono e il pre-roll, se la sessione calda li richiede.

## 1. Vincoli scoperti in fase di verifica

Cambiano il progetto rispetto al brief iniziale. Legenda: [V] verificato su una fonte,
[M] da memoria e da ricontrollare, [I] ipotesi da misurare.

### Rischi che possono cambiare il prodotto

1. **Regola App Store 4.4.1.** Le tastiere non devono lanciare altre app oltre a Impostazioni [M, citata
   anche nel thread 843118]. "La prima dettatura apre l'app" è quindi a rischio rifiuto. Non risulta una
   risposta scritta di Apple su un percorso ammesso [V]. Alcune app concorrenti lo fanno, ma non sappiamo
   come né con quali conseguenze [V].
2. **Nessun ritorno automatico all'app ospite.** Da iOS 26.4 non esiste un'API pubblica per identificare
   l'app ospite o tornarci (risposta di Apple DTS, giugno 2026) [V]. La freccia "← App" di sistema risulta
   assente dopo un lancio partito da un'estensione [V, segnalazione di uno sviluppatore]. Il ritorno
   resta manuale, e lo swipe sulla barra home va provato su iOS 27 [I].
3. **Microfono acceso contro ripartenza dal background.** La tastiera non può usare il microfono, con o
   senza Accesso completo [V]. Per partire dal background l'app tiene aperta la sessione audio [V], e di
   conseguenza:
   - durante la sessione calda l'indicatore arancione resta acceso [M];
   - scaduto il timeout, serve di nuovo l'app oppure un intent [I];
   - il pre-roll esiste solo mentre il microfono è aperto [I].

   Timeout e consumi vanno misurati e il comportamento va spiegato all'utente. Audio del pre-roll solo
   in un buffer circolare in RAM.

### Precisazioni al brief

4. **Accesso completo obbligatorio per il mic.** Senza, il container dell'App Group non è utilizzabile
   dalla tastiera [V, thread 841057]. iOS mostra il suo avviso generico sui dati digitati, quindi la
   privacy va dimostrata: test sui simboli del binario, build riproducibile, modulo separato.
5. **Parakeet v3 lavora in batch.** Il testo definitivo arriva a fine frase rilevata dal VAD, mentre
   l'anteprima usa la finestra scorrevole di FluidAudio [V]. L'obiettivo di 1 s è plausibile, ma non è
   ancora misurato su iPhone [I].
6. **SpeechAnalyzer "0 MB" vale solo per il pacchetto dell'app.** Gli asset della lingua li scarica iOS
   [M]. Nel selettore: "gestito da iOS". Non esiste un WER italiano pubblicato [V], quindi il badge
   mostrerà "solo misurato".
7. **Qwen3-ASR escluso dalla v1.** Secondo Handy la 0.6B ha WER italiano 5,19% contro 3,02% di Parakeet
   v3, ed è segnata come sperimentale con una variante f32 da circa 2,5 GB [V]. La 1.7B (2,68%) resta
   dietro a Parakeet Ultra e ha solo un pacchetto Core ML di terzi [V]. Nessuno spike in M0.
8. **Vocabolario FluidAudio.** Funziona solo in batch, con un secondo encoder CTC da 110M e circa 130 MB
   complessivi [V]. Il limite "solo inglese" non è scritto nella documentazione e va verificato in 2a.
9. **Il pacchetto WhisperKit ora è `argmax-oss-swift`.** Su iPhone si consiglia la variante
   `large-v3-v20240930_626MB` [V]. `promptTokens` non è citato nel README: da verificare nei sorgenti
   prima di 2a.
10. **AudioRecordingIntent.** Pare che richieda di avviare una Live Activity [M]. Se la dettatura parte
    da Action Button e la tastiera Loqui non è attiva, il testo non si può inserire: resta in sospeso
    nell'app e in cronologia, senza toccare gli appunti salvo scelta dell'utente.
11. **Copertura test.** L'unico iPhone è su iOS 27, quindi il minimo iOS 26 si potrà provare solo in
    simulatore, senza microfono reale né misure ANE affidabili. I benchmark valgono per questo telefono.

## 2. Dati di partenza del catalogo

**Decisione: l'accuratezza nel catalogo viene dalle valutazioni di Handy**, senza un corpus nostro.
WER italiano su FLEURS, stessa pipeline per tutti (transcribe.cpp, quantizzazione Q8) [V]. Il runtime è
diverso da Core ML e il parlato è letto, quindi la scheda del modello lo dichiara. Velocità e RAM di
Handy non valgono per iPhone: quelle si misurano sul dispositivo.

| Modello | WER IT | Peso (ggml) | Motore su iOS | Vocabolario |
|---|---|---:|---|---|
| Parakeet Ultra | 2,34% | 0,69 GB (encoder Core ML int8: 595 MB) | fluidaudio | da verificare |
| Whisper large-v3-turbo | 2,77% | 0,83 GB (Core ML: 626 MB) | whisperkit | prompt, da verificare |
| Parakeet TDT v3 | 3,02% | 0,69 GB | fluidaudio | CTC, da verificare |
| Whisper small | 7,97% | 0,25 GB | whisperkit | prompt, da verificare |
| Apple SpeechAnalyzer | non valutato da Handy | gestito da iOS | apple | `contextualStrings` |

Parakeet Ultra è il candidato consigliato per l'italiano, salvo smentite su latenza o RAM in M0.
SpeechAnalyzer non è un modello che Handy può valutare: nessun badge di accuratezza, solo "non valutato".
Il catalogo cita sempre la fonte e il dataset di ogni valore.

**Regole di ottimizzazione per iPhone:**

- Solo varianti Core ML su Neural Engine, compresse dove disponibili (encoder int8 di Parakeet Ultra,
  turbo da 626 MB). I file ggml valutati da Handy non si usano: i pesi in tabella sono indicativi e il
  catalogo userà quelli reali misurati in M1.
- Unità di calcolo dichiarate esplicitamente. Il benchmark riporta dove gira ogni parte. Un modello il cui
  encoder non gira su ANE non può essere il consigliato. Il vincolo vale per l'encoder perché è la parte più
  pesante: in Parakeet decoder, joint e preprocessor sono preferiti su CPU (misura M0).
- Inferenza solo dopo lo stop: mentre parli lavora solo la cattura audio.
- Cattura a 16 kHz mono, senza copie inutili del buffer audio.
- Reazione a memoria bassa e temperatura: scarica il modello su avviso di memoria, ricarica alla
  dettatura successiva. Se il telefono scalda, va ridotto il lavoro di anteprima.
- La compilazione ANE avviene durante il download, così la prima dettatura non la paga.

## 3. Struttura

```
project.yml
Apps/Loqui/              motore: audio, modelli, UI, intent
Apps/LoquiKeyboard/      solo UI, nessuna dipendenza da motori
Apps/LoquiLiveActivity/
Packages/LoquiCore/
  LoquiShared            protocollo IPC, stato, tipi. Unico modulo linkato dalla tastiera
  LoquiEngines           protocollo TranscriptionEngine, adapter apple/fluidaudio/whisperkit, VAD
  LoquiCatalog           models.json, badge, raccomandazione
  LoquiCleanup           Exact/Basic, dizionario. Smart in fase 2
scripts/verify-keyboard-privacy.sh
```

**Verifica privacy (da M2):** lo script ispeziona i simboli importati dal binario della tastiera
(`nm -u`, `otool -L`), fallisce se trova `URLSession`, `NSURLConnection`, `Network.framework`, socket o
`CFNetwork` diretto, e controlla che nel target non ci siano FluidAudio o WhisperKit. I controlli sono
documentati nel README, così chiunque può ripeterli. Anche l'app avrà un test: dopo il download i motori
girano in modalità offline.

**Identificativi:** `com.giovannigiofre.loqui`, gruppo `group.com.giovannigiofre.loqui`. Il prefisso sta in un
solo punto, `Config/Identifiers.xcconfig`; chi compila con un altro team lo sostituisce in
`Config/Local.xcconfig` (escluso da git), che `scripts/install.sh` crea da solo. Il codice legge l'App Group
da Info.plist. Non ancora verificato sul dispositivo.

**Licenze (M5):** app MIT, FluidAudio Apache 2.0, WhisperKit MIT, file NOTICE. I modelli si scaricano e
non sono nel repo. Licenza di ciascun modello da riportare nel catalogo (Parakeet: CC-BY-4.0 [M]).

## 4. Fase 1

`[MANUALE]` indica un punto in cui mi fermo e ti chiedo un gesto sul dispositivo.

### M0: spike e benchmark in italiano

Obiettivo: decidere con i dati se l'architettura regge.

- App minima, `TranscriptionEngine`, adapter SpeechAnalyzer, Parakeet v3 e Parakeet Ultra, dettatura a tocchi.
- Schermata con dettatura e testo, senza rifiniture.
- Benchmark ripetibile: stesse clip per tutti i motori, generate con una voce italiana di sistema (non
  servono registrazioni e non si misura l'accuratezza). Misura caricamento a freddo (compilazione ANE
  inclusa) e a caldo, latenza dallo stop al testo, RTF, picco di `phys_footprint`.
- `[MANUALE]` Login in Xcode e Team ID; fiducia nel certificato; permesso microfono.
- `[MANUALE]` Qualche dettatura a voce tua, come controllo a occhio e per la latenza reale.

**Uscita:** tabella misurata in `docs/benchmarks/` e conferma del modello consigliato per l'italiano
(WER di Handy più latenza e RAM misurate). Se nessun modello Parakeet resta sotto 1 s dallo stop al testo
sulle dettature brevi, ci fermiamo a rivedere il piano.

### M1: selettore modelli e download

- `models.json`, adapter WhisperKit, badge +/− per lingua, consigliato evidenziato.
- Download in background, eliminazione, spazio occupato, pre-compilazione ANE.
- "Benchmark sul mio iPhone" nell'app, con i risultati accanto ai valori pubblicati.
- Download in background con `BGContinuedProcessingTask`. Una chiusura forzata interrompe il download: va
  rilanciato.
- `[MANUALE]` Selettore e badge; download mandando l'app in background; eliminazione; dettatura in modalità aereo.

**Uscita:** tutti i modelli v1 si scaricano, caricano, trascrivono e si eliminano sul telefono.

### M2: tastiera e IPC

- Tastiera: mic, waveform, anteprima, annulla, globo. App Group + Darwin notification.
- Script di verifica privacy nel flusso di build.
- Buffer di sessione per annulla, pulizia e fase 2.
- `[MANUALE]` Attivare tastiera e Accesso completo in Impostazioni.

`devicectl` non mostra i file nel contenitore dell'App Group: per leggerli serve `--auto-group-check`.

**Uscita:** tastiera sotto 40 MB misurati e script verde. Dettatura con app in primo piano e rientro
manuale.

### M3: sessione calda, Live Activity, intent

- Spike iniziale sui rischi 1, 2 e 3 della sezione 1: lancio da tastiera su iOS 27, rientro, ripartenza
  dal background, timeout, recupero dopo terminazione da parte del sistema.
- Audio in background, pre-roll, rilascio del microfono, Live Activity, `AudioRecordingIntent` per Action
  Button e Centro di Controllo, push-to-talk e toggle.
- Percorso per la release senza lancio dalla tastiera: istruzioni e avvio da intent.
- Spike sul caricamento: da app chiusa Parakeet richiede oltre 10 s, quindi va misurato quanto iOS tiene vivo
  il processo in background e come ripiegare se lo chiude. Primi dati in
  [background](docs/benchmarks/2026-11-06-background.md): solo con il microfono acceso l'app resta viva e riparte.
- `[MANUALE]` Configurare Action Button e controllo; prova d'uso reale in più app.
- `[MANUALE]` Sessione di consumo a telefono scollegato, 30 minuti, con sessione calda attiva.

**Uscita:** seconda dettatura in poi senza cambiare app; 1 s rispettato in uso reale; costo orario della
sessione calda misurato e mostrato nelle impostazioni.

### M4: pulizia, dizionario, cronologia

- Exact e Basic con "annulla pulizia". Basic non riformula: punteggiatura, maiuscole, esitazioni.
- Dizionario personale con le sostituzioni di base. Il biasing è in 2a.
- Cronologia con retention configurabile, anche a zero. A zero non resta nulla nell'App Group dopo
  l'inserimento: da verificare con un test.
- Interfaccia post-processing pluggable, predisposta per Smart.

**Uscita:** test su Basic con corpus italiano; retention zero verificata sui file.

### M5: rifinitura, README, TestFlight

- Onboarding, accessibilità, gestione errori, comportamento con poca memoria.
- README con le verifiche privacy e le misure, LICENSE, NOTICE.
- Togliere dalla release clip di prova e lanci `--auto-*`.
- `[MANUALE]` App Store Connect (serve Apple Developer a pagamento) e invito tester.

**Uscita:** build su TestFlight interno. La distribuzione esterna e l'App Store dipendono dalla decisione
sul rischio 1.

## 5. Fase 2 (solo con fase 1 stabile)

**2a, nomi e termini.** Biasing dove il motore lo supporta (`promptTokens`, `contextualStrings`,
vocabolario CTC), poi per tutti i motori correzione fuzzy/fonetica sul dizionario e decisione di un LLM
locale in base al testo prima del cursore. Il dizionario propone di imparare dalle correzioni manuali.

**2b, modifica vocale.** Tasto ✏️ che mette in pausa la dettatura. L'utente dice l'istruzione, l'LLM
modifica il buffer e la tastiera sostituisce il blocco cancellando e reinserendo. Annulla sempre
disponibile, poi si torna al mic. Da verificare: il testo modificato nel frattempo dall'utente, che
potrebbe non combaciare più con il buffer.

**2c, adattamento al contesto.** Selettore rapido di stile e segnali dal tipo di campo e dal testo
esistente. Niente rilevamento dell'app ospite.

**LLM.** Apple Foundation Models di default (richiede Apple Intelligence attiva e dispositivo
compatibile), modelli scaricabili opzionali con lo stesso selettore e gli stessi badge. Modalità Smart
qui, mai attiva per default.

## 6. Fonti

- Apple Developer Forums: [host app e ritorno, 826851](https://developer.apple.com/forums/thread/826851),
  [host bundle id nil, 836168](https://developer.apple.com/forums/thread/836168),
  [4.4.1 e dettatura, 843118](https://developer.apple.com/forums/thread/843118),
  [ritorno e App Group, 841057](https://developer.apple.com/forums/thread/841057)
- [Apple: Open Access per le tastiere](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Handy models, italiano](https://models.handy.computer/languages/it)
- [FluidAudio](https://github.com/FluidInference/FluidAudio),
  [elenco modelli](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md),
  [custom vocabulary](https://docs.fluidinference.com/asr/custom-vocabulary),
  [PR Qwen3](https://github.com/FluidInference/FluidAudio/pull/281)
- [WhisperKit / argmax-oss-swift](https://github.com/argmaxinc/WhisperKit)
