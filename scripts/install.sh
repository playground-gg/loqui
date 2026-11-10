#!/bin/zsh
# Compila Loqui e lo installa sull'iPhone collegato. Lo stesso comando serve per il rinnovo
# settimanale con Apple ID gratuito.
# Uso: scripts/install.sh
#
# Le scelte (prefisso degli identificativi, team) restano in .env.local e Config/Local.xcconfig,
# entrambi esclusi da git. Per ripartire da zero basta cancellarli.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1 }
step() { echo "\n==> $*" }

[[ "$(uname)" == Darwin ]] || die "Loqui can only be built on a Mac with Xcode."
command -v xcodebuild >/dev/null || die "Xcode not found. Install it from the App Store and open it once."
command -v xcodegen >/dev/null || die "XcodeGen not found. Install it with: brew install xcodegen"

# --- Impostazioni salvate ---------------------------------------------------------------------
ID_PREFIX="" TEAM_ID="" DEVICE_UDID="" BUNDLE_ID=""
if [[ -f .env.local ]]; then set -a; source .env.local; set +a; fi

save() { # save NOME valore: aggiunge la riga a .env.local se manca
  grep -q "^$1=" .env.local 2>/dev/null || echo "$1=$2" >> .env.local
}

# Chi ha già un BUNDLE_ID in .env.local tiene lo stesso prefisso, così l'app installata non cambia.
if [[ -z "$ID_PREFIX" && "$BUNDLE_ID" == *.loqui ]]; then ID_PREFIX="${BUNDLE_ID%.loqui}"; fi

if [[ -z "$ID_PREFIX" ]]; then
  suggested="com.$(whoami | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
  echo "Choose a prefix for the app identifiers. It must be unique to you and you should"
  echo "never change it afterwards (a free Apple ID can register only 10 identifiers a week)."
  read "ID_PREFIX?Prefix [$suggested]: "
  ID_PREFIX="${ID_PREFIX:-$suggested}"
fi
[[ "$ID_PREFIX" =~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' ]] \
  || die "'$ID_PREFIX' is not a valid prefix. Use something like com.yourname (letters, digits, dots)."

if [[ -z "$TEAM_ID" ]]; then
  # Il Team ID è il campo OU del certificato di sviluppo che Xcode crea nel portachiavi.
  TEAM_ID="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' || true)"
  if [[ -n "$TEAM_ID" ]]; then
    echo "Found a development certificate for team $TEAM_ID."
    read "answer?Use it? [Y/n] "
    [[ "$answer" == [nN]* ]] && TEAM_ID=""
  fi
fi
if [[ -z "$TEAM_ID" ]]; then
  echo "No Team ID yet. If you have never signed an app on this Mac:"
  echo "  1. Open Xcode > Settings > Accounts and sign in with your Apple ID."
  echo "  2. Select your team, click 'Manage Certificates...', then '+' > 'Apple Development'."
  echo "  3. Run this script again: it will find the team by itself."
  read "TEAM_ID?Or type your 10-character Team ID now (empty to quit): "
  [[ -n "$TEAM_ID" ]] || exit 1
fi
[[ "$TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || die "'$TEAM_ID' doesn't look like a Team ID (10 letters and digits)."

save ID_PREFIX "$ID_PREFIX"
save TEAM_ID "$TEAM_ID"
BUNDLE_ID="$ID_PREFIX.loqui"

# Xcode legge lo stesso file: così anche aprendo il progetto a mano gli identificativi coincidono.
cat > Config/Local.xcconfig <<EOF
// Generato da scripts/install.sh. Escluso da git.
LOQUI_ID_PREFIX = $ID_PREFIX
DEVELOPMENT_TEAM = $TEAM_ID
EOF

# --- iPhone -----------------------------------------------------------------------------------
if [[ -z "$DEVICE_UDID" ]]; then
  step "Looking for a connected iPhone"
  json="$(mktemp "${TMPDIR:-/tmp}/loqui-devices.XXXXXX")"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
  found="$(xcrun python3 - "$json" <<'PY' || true
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") != "iOS" or hw.get("reality", "physical") != "physical":
        continue
    if conn.get("tunnelState") == "unavailable" or not hw.get("udid"):
        continue
    print(hw["udid"] + "\t" + d.get("deviceProperties", {}).get("name", "iPhone"))
PY
  )"
  devices=("${(@f)found}")
  rm -f "$json"
  devices=("${(@)devices:#}")
  case ${#devices} in
    0) die "No iPhone found. Connect it with a cable, unlock it, tap 'Trust' and try again.
       You can also set DEVICE_UDID in .env.local (see: xcrun devicectl list devices)." ;;
    1) choice=1 ;;
    *) for i in {1..${#devices}}; do echo "  $i) ${devices[$i]#*$'\t'}"; done
       read "choice?Which one? "
       [[ "$choice" =~ '^[0-9]+$' ]] && (( choice >= 1 && choice <= ${#devices} )) || die "Invalid choice." ;;
  esac
  DEVICE_UDID="${devices[$choice]%%$'\t'*}"
  echo "Using ${devices[$choice]#*$'\t'}."
fi

# --- Build, verifica, installazione -----------------------------------------------------------
step "Generating the Xcode project"
xcodegen generate --quiet

step "Building (the first time takes several minutes)"
xcodebuild -project Loqui.xcodeproj -scheme Loqui -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_UDID" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" -quiet build

step "Checking that the keyboard contains no networking code"
scripts/verify-keyboard-privacy.sh

step "Installing on the iPhone"
xcrun devicectl device install app --device "$DEVICE_UDID" \
  build/Build/Products/Debug-iphoneos/Loqui.app

step "Launching"
if ! xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing "$BUNDLE_ID"; then
  echo "\nInstalled, but it couldn't be opened. Usually one of these:"
  echo "  - the iPhone is locked: unlock it and open Loqui;"
  echo "  - first install: trust your certificate in"
  echo "    Settings > General > VPN & Device Management, then open Loqui."
fi

echo "\nDone. With a free Apple ID the app stops opening after 7 days:"
echo "connect the iPhone and run scripts/install.sh again to renew it."
