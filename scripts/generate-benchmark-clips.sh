#!/bin/zsh
# Genera le clip italiane del benchmark con una voce di sistema di macOS.
# Le clip non vanno nel repo: servono solo a misurare velocità e RAM, non l'accuratezza.
set -euo pipefail
out="$(dirname "$0")/../Apps/Loqui/Resources/BenchmarkClips"
mkdir -p "$out"
voice="Alice"
gen() { say -v "$voice" --file-format=WAVE --data-format=LEI16@16000 -o "$out/$1.wav" "$2"; }
gen 01-breve "Ci vediamo domani."
gen 02-frase "Ricordami di chiamare il dentista giovedì mattina alle nove e mezza."
gen 03-messaggio "Ciao, arrivo tra venti minuti perché ho trovato traffico in tangenziale. Se volete iniziate pure senza di me."
gen 04-nomi "La riunione con Giulia Ferrari e Marco De Luca è spostata a Bologna, in via Indipendenza 12, martedì 18 novembre."
gen 05-email "Gentile dottoressa, le scrivo per confermare l'appuntamento della prossima settimana. Le allego il preventivo aggiornato e la documentazione richiesta dal commercialista. Se avesse bisogno di ulteriori chiarimenti, può contattarmi in qualsiasi momento."
gen 06-lunga "Stamattina ho riletto il progetto con calma e credo che ci siano ancora tre punti da chiarire prima di presentarlo al cliente. Il primo riguarda i tempi di consegna, che secondo me sono troppo stretti. Il secondo è il budget per la parte grafica, che non abbiamo mai discusso davvero. Il terzo è chi si occuperà della manutenzione dopo il lancio, perché senza un responsabile rischiamo di ritrovarci con un sito che nessuno aggiorna."
