#!/usr/bin/env bash
# Talk to Almanac hosted events. Key stays in the config file; never printed.
# Commands: list | post | delete | feed
# WAF 403s HTTP PATCH. POST /events with uid in the body upserts.
set -u

fail() {
  printf 'ERROR:%s\n' "$1"
  exit 1
}

UA="${ALMANAC_UA:-Mozilla/5.0 dottie-calendar}"
CONFIG="${ALMANAC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/almanac/hosted-calendars.json}"
BASE="${ALMANAC_BASE:-https://almanac.dottie.ai}"
CMD=""
CAL=""
ITEM=""
BODYFILE=""

while (( $# > 0 )); do
  case "$1" in
    list|post|delete|feed)
      [[ -z $CMD ]] || fail "usage"
      CMD="$1"
      shift
      ;;
    --cal)
      CAL="${2-}"
      shift 2
      ;;
    --uid)
      ITEM="${2-}"
      shift 2
      ;;
    --body-file)
      BODYFILE="${2-}"
      shift 2
      ;;
    -*)
      fail "unknown option"
      ;;
    *)
      fail "usage"
      ;;
  esac
done

[[ -n $CMD ]] || fail "usage"
[[ -f $CONFIG ]] || fail "No Almanac calendar"
if [[ $CMD == post ]]; then
  [[ -n "$BODYFILE" && -f "$BODYFILE" ]] || fail "body file required"
fi
if [[ $CMD == delete ]]; then
  [[ -n "$ITEM" ]] || fail "uid required"
fi

export ALMANAC_CONFIG="$CONFIG"
export ALMANAC_CAL="$CAL"
CREDS=$(python3 - <<'PY'
import json, os, sys
from pathlib import Path
path = Path(os.environ["ALMANAC_CONFIG"])
want = os.environ.get("ALMANAC_CAL", "").strip()
try:
    raw = json.loads(path.read_text())
except Exception:
    sys.exit(1)
if isinstance(raw, list):
    rows = raw
elif isinstance(raw, dict) and isinstance(raw.get("calendars"), list):
    rows = raw["calendars"]
elif isinstance(raw, dict):
    rows = [raw]
else:
    rows = []
for row in rows:
    if not isinstance(row, dict):
        continue
    cid = str(row.get("id") or "")
    key = str(row.get("key") or "")
    write = str(row.get("write") or "")
    subscribe = str(row.get("subscribe") or "")
    if not cid or not key:
        continue
    if want and cid != want:
        continue
    sys.stdout.write(key + "\n" + cid + "\n" + write + "\n" + subscribe + "\n")
    sys.exit(0)
sys.exit(1)
PY
) || fail "No Almanac calendar"

KEY=$(printf '%s\n' "$CREDS" | sed -n '1p')
CAL_ID=$(printf '%s\n' "$CREDS" | sed -n '2p')
WRITE=$(printf '%s\n' "$CREDS" | sed -n '3p')
SUBSCRIBE=$(printf '%s\n' "$CREDS" | sed -n '4p')
unset CREDS

if [[ $WRITE == */events || $WRITE == */events/ ]]; then
  EVENTS="${WRITE%/}"
else
  EVENTS="${BASE%/}/v1/c/${CAL_ID}/events"
fi

if [[ $CMD == feed ]]; then
  [[ -n $SUBSCRIBE ]] || fail "No Almanac feed"
  printf '%s\n' "$SUBSCRIBE"
  exit 0
fi

URL="$EVENTS"
METHOD="GET"
if [[ $CMD == post ]]; then
  METHOD="POST"
elif [[ $CMD == delete ]]; then
  METHOD="DELETE"
  URL="${EVENTS}/${ITEM}"
fi

TMP=$(mktemp)
SEALFILE=""
trap 'rm -f "$TMP" "$SEALFILE"' EXIT

if [[ $CMD == post ]]; then
  INFO=$(curl -sS --max-time 20 -A "$UA" -H "Authorization: Bearer ${KEY}" "${EVENTS%/*}") || fail "Almanac request failed"
  FEED=$(printf '%s' "$INFO" | python3 -c 'import json,sys
try:
    data=json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(1)
sys.stdout.write(str(data.get("feed") or "plain") if isinstance(data, dict) else "plain")') || fail "Almanac request failed"
  if [[ $FEED == seal ]]; then
    supports_seal() {
      [[ -x $1 ]] && strings "$1" | grep -q 'almanac-seal-v1'
    }
    BIN=""
    if [[ -n ${ALMANAC_BIN:-} ]] && supports_seal "$ALMANAC_BIN"; then
      BIN="$ALMANAC_BIN"
    fi
    if [[ -z $BIN ]]; then
      BIN=$(command -v almanac || true)
      supports_seal "$BIN" || BIN=""
    fi
    if [[ -z $BIN ]]; then
      for BIN in "$HOME/Projects/almanac/target/release/almanac" "$HOME/Projects/almanac/target/debug/almanac"; do
        supports_seal "$BIN" && break
        BIN=""
      done
    fi
    [[ -n $BIN ]] || fail "sealed calendar needs the almanac binary"
    UID_VALUE=$(python3 -c 'import json,sys,uuid
raw=open(sys.argv[1]).read()
try:
    data=json.loads(raw)
except Exception:
    data={}
uid=str(data.get("uid") or "").strip() if isinstance(data, dict) else ""
if not uid:
    uid="evt-"+uuid.uuid4().hex
sys.stdout.write(uid)' "$BODYFILE") || fail "bad event"
    SEALFILE=$(mktemp)
    ALMANAC_CREDS="$CONFIG" "$BIN" seal --cal "$CAL_ID" --kind event --uid "$UID_VALUE" <"$BODYFILE" >"$SEALFILE" || fail "could not seal the event"
    python3 -c 'import json,sys
seal=open(sys.argv[1]).read().strip()
json.dump({"seal": seal}, sys.stdout)
' "$SEALFILE" >"$TMP.body"
    mv "$TMP.body" "$SEALFILE"
    URL="${EVENTS}/${UID_VALUE}"
    METHOD="PUT"
    BODYFILE="$SEALFILE"
  fi
fi

CURL_ARGS=(-sS --max-time 20 -A "$UA" -o "$TMP" -w "%{http_code}" -X "$METHOD" -H "Authorization: Bearer ${KEY}" "$URL")
if [[ $CMD == post ]]; then
  CURL_ARGS=(-sS --max-time 20 -A "$UA" -o "$TMP" -w "%{http_code}" -X "$METHOD" -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" --data-binary @"$BODYFILE" "$URL")
fi

CODE=$(curl "${CURL_ARGS[@]}") || fail "Almanac request failed"
BODY_TEXT=$(cat "$TMP")

if [[ $CODE == 204 ]]; then
  printf '%s\n' '{"ok":true}'
  exit 0
fi
if [[ $CODE == 200 || $CODE == 201 ]]; then
  if [[ -z $BODY_TEXT ]]; then
    printf '%s\n' '{"ok":true}'
  else
    printf '%s\n' "$BODY_TEXT"
  fi
  exit 0
fi

ERR=$(python3 -c 'import json,sys
raw=sys.stdin.read()
try:
    data=json.loads(raw)
except Exception:
    sys.exit(1)
err=data.get("error") if isinstance(data, dict) else None
if err:
    sys.stdout.write(str(err))
    sys.exit(0)
sys.exit(1)' <<<"$BODY_TEXT" 2>/dev/null || true)

if [[ $CODE == 401 ]]; then
  fail "${ERR:-Almanac key rejected}"
fi
if [[ $CODE == 403 ]]; then
  fail "${ERR:-Almanac blocked}"
fi
if [[ $CODE == 404 ]]; then
  fail "${ERR:-not found}"
fi
if [[ $CODE == 409 ]]; then
  fail "${ERR:-calendar is full}"
fi
if [[ $CODE == 429 ]]; then
  fail "${ERR:-rate limit exceeded}"
fi
if [[ $CODE == 400 ]]; then
  fail "${ERR:-bad event}"
fi
fail "${ERR:-Almanac HTTP ${CODE}}"
