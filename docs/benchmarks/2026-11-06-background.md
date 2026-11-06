# Restare pronti in background: iPhone 17 Pro

iPhone18,1, iOS 27.0, 2026-11-06, build Debug, telefono collegato. Ogni scenario è una prova singola di circa
70 s in background: i numeri danno l'ordine di grandezza, non una media.

| Scenario | L'app resta viva? | Il microfono riparte in background? |
|---|---|---|
| A: microfono sempre acceso | Sì | Sì, con segnale |
| B: sessione attiva, microfono spento | **No**, sospesa da iOS | Non provato: la prova è rimasta ferma |
| C: audio silenzioso, senza microfono | Sì | **No**, errore e zero campioni |

Solo A soddisfa entrambe le condizioni, ed è anche lo schema delle "Flow Session" di Wispr.

## Costo dello scenario A

Con Parakeet Ultra in memoria: 0,56 s di CPU al minuto e circa 1,3 mW attribuiti al processo Loqui
(`TASK_POWER_INFO_V2`). **Non è il costo totale:** non comprende microfono, sistema audio di iOS e Neural Engine.
Il consumo reale va misurato sulla batteria.

## Correzione sulla RAM

Il benchmark M0 riportava circa 620 MB "a modello caricato" e leggeva il calo dopo lo scaricamento come un
rilascio lento. La lettura era sbagliata: qui il modello resta caricato e la RAM di Loqui scende comunque da 614 MB
a circa 37 MB entro 15 s, poi a 26 MB. I 620 MB sono quindi un picco di caricamento, non la memoria stabile del
processo. Non si sa quanta memoria resti al sistema fuori da Loqui, per esempio per il Neural Engine.

Non ancora verificato: quanto iOS lasci viva l'app oltre questi 70 s, e se un modello rimasto così sia subito
pronto dopo una sospensione.
