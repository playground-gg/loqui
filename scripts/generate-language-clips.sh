#!/bin/zsh
# Genera una clip per lingua con le voci di sistema di macOS, per la prova multilingua.
# Le clip non vanno nel repo.
set -euo pipefail
out="$(dirname "$0")/../Apps/Loqui/Resources/LanguageClips"
mkdir -p "$out"
gen() {
  local voice
  voice=$(say -v '?' | grep -E "[[:space:]]$2_[A-Z]{2}[[:space:]]" | grep -vE 'Eddy|Flo|Grandma|Grandpa|Reed|Rocko|Sandy|Shelley|Bahh|Bells|Boing|Bubbles|Cellos|Wobble' | head -1 | sed -E "s/[[:space:]]+$2_.*//")
  [[ -n "$voice" ]] || { echo "Nessuna voce per $2" >&2; return }
  say -v "$voice" --file-format=WAVE --data-format=LEI16@16000 -o "$out/$2.wav" "$3"
  echo "$2 → $voice"
}
gen it it "Domani mattina devo andare in banca e poi passo a prendere i bambini a scuola."
gen en en "Tomorrow morning I have to go to the bank and then pick up the kids from school."
gen es es "Mañana por la mañana tengo que ir al banco y luego recoger a los niños del colegio."
gen fr fr "Demain matin, je dois aller à la banque puis chercher les enfants à l'école."
gen de de "Morgen früh muss ich zur Bank gehen und danach die Kinder von der Schule abholen."
gen pt pt "Amanhã de manhã tenho de ir ao banco e depois buscar as crianças à escola."
gen nl nl "Morgenochtend moet ik naar de bank en daarna de kinderen van school halen."
gen pl pl "Jutro rano muszę iść do banku, a potem odebrać dzieci ze szkoły."
gen ru ru "Завтра утром мне нужно сходить в банк, а потом забрать детей из школы."
gen el el "Αύριο το πρωί πρέπει να πάω στην τράπεζα και μετά να πάρω τα παιδιά από το σχολείο."
gen ja ja "明日の朝は銀行に行って、そのあと子供たちを学校に迎えに行きます。"
gen zh zh "明天早上我要去银行,然后去学校接孩子。"
gen ko ko "내일 아침에 은행에 갔다가 학교에서 아이들을 데려와야 합니다."

# Clip miste: la voce cambia nella stessa frase, come quando si passa da una lingua all'altra.
part() {
  count=$((count + 1))
  local file="$tmp/$(printf '%03d' "$count").wav"
  say -v "$1" --file-format=WAVE --data-format=LEI16@16000 -o "$file" "$2"
}
join_parts() {
  /usr/bin/python3 -I -c '
import sys, wave
out, parts = sys.argv[1], sys.argv[2:]
with wave.open(out, "wb") as target:
    for index, path in enumerate(parts):
        with wave.open(path, "rb") as source:
            if index == 0:
                target.setparams(source.getparams())
            target.writeframes(source.readframes(source.getnframes()))
' "$out/$1.wav" "$tmp"/*.wav
  rm -f "$tmp"/*.wav
  count=0
}
tmp=$(mktemp -d)
count=0
italian="Alice"
english="Samantha"
say -v '?' | grep -q '^Samantha' || english="Albert"

part "$italian" "Domani ho una riunione"
part "$english" "with the marketing team"
part "$italian" "e poi ti mando il"
part "$english" "report"
join_parts mix-parole

part "$italian" "Ho parlato con il cliente e mi ha detto una cosa interessante."
part "$english" "We need to ship the new version by Friday, otherwise they will cancel the contract."
part "$italian" "Quindi secondo me conviene partire subito."
join_parts mix-frasi

part "$english" "Let me check the"
part "$italian" "fattura di ottobre"
part "$english" "and I will get back to you."
join_parts mix-inglese-prima
rmdir "$tmp"
