#!/bin/zsh
# Verifica che la tastiera non contenga codice di rete né i motori di trascrizione.
# Uso: scripts/verify-keyboard-privacy.sh [percorso/LoquiKeyboard.appex]
set -euo pipefail
appex="${1:-build/Build/Products/Debug-iphoneos/Loqui.app/PlugIns/LoquiKeyboard.appex}"
[[ -d "$appex" ]] || { echo "Tastiera non trovata: $appex" >&2; exit 2 }

# Il codice può stare nell'eseguibile o, nelle build Debug, in una libreria accanto.
binaries=("$appex/LoquiKeyboard")
[[ -f "$appex/LoquiKeyboard.debug.dylib" ]] && binaries+=("$appex/LoquiKeyboard.debug.dylib")

failed=0
network='URLSession|NSURLConnection|NSURLRequest|URLRequest|CFNetwork|CFHTTP|CFSocket|CFStream|nw_connection|nw_endpoint|NWConnection|NWPathMonitor|WKWebView|_socket$|_connect$|_getaddrinfo$|_sendto$|_recvfrom$'
for binary in "${binaries[@]}"; do
  echo "== $(basename "$binary")"
  if found=$(nm -u "$binary" | grep -E "$network"); then
    echo "VIETATO, simboli di rete:"; echo "$found"; failed=1
  fi
  if found=$(otool -L "$binary" | grep -E 'Network\.framework|CFNetwork|WebKit'); then
    echo "VIETATO, framework di rete:"; echo "$found"; failed=1
  fi
  if found=$(nm "$binary" | grep -E 'FluidAudio|WhisperKit|CoreML|LoquiEngines|AVAudioEngine'); then
    echo "VIETATO, motori o audio nella tastiera:"; echo "$found" | head -5; failed=1
  fi
done

if [[ -d "$appex/Frameworks" ]] && [[ -n "$(ls -A "$appex/Frameworks")" ]]; then
  echo "VIETATO, framework incorporati:"; ls "$appex/Frameworks"; failed=1
fi

if (( failed )); then
  echo "Verifica privacy fallita." >&2
  exit 1
fi
echo "Verifica privacy superata: nessun simbolo di rete, nessun motore."
