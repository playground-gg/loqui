# Prova multilingua: iPhone 17 Pro

iPhone18,1, iOS 27.0, 2026-11-06. Clip generate con voci di sistema di macOS: prova indicativa, più pulita di una
voce reale, soprattutto nei cambi di lingua. Ripetibile con `scripts/generate-language-clips.sh` e i lanci
`--auto-language-check` e `--auto-mixed-check`.

## Una lingua per clip

Stessa frase in 13 lingue, con i motori che le supportano.

| Motore | Lingue provate | Esito |
|---|---:|---|
| Parakeet Ultra | 10 | Nessun errore visibile, lingua riconosciuta senza indicarla |
| Whisper small | 13 | Un errore visibile in greco ("Άβριο") |
| SpeechAnalyzer | 6 riuscite su 9 | Inglese sbagliato ("back to the sandwich"); coreano, portoghese e cinese falliti per il limite di 5 lingue riservate |

## Due lingue nella stessa dettatura

| Motore | Parole inglesi in frase italiana | Frasi alternate it/en/it | Inglese con parole italiane |
|---|---|---|---|
| Parakeet Ultra | Corretto | Corretto | Corretto, "Ottobre" maiuscolo |
| Whisper turbo | Corretto, ma con punti a caso | **Frase inglese persa** | Corretto |
| Whisper small | Tradotto in italiano ("con la team di marketing"), "ho" perso | **Frase inglese persa** | Con italiano imposto: testo vuoto. Con lingua automatica: "Fatura d'October" |
| SpeechAnalyzer | Corretto | Parole perse ("We need ship", "they will the contract") | Corretto |

Per Whisper il riconoscimento automatico della lingua non recupera la frase persa: sceglie una lingua sola.

## Conclusioni

- Per chi mescola le lingue il motore giusto è Parakeet Ultra. Va confermato con una voce reale.
- Whisper può togliere testo senza alcun avviso: il rischio è scritto nella sua scheda.
- SpeechAnalyzer tiene al massimo 5 lingue riservate: `AssetInventory.maximumReservedLocales`.
