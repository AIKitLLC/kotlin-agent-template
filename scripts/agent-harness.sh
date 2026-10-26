#!/usr/bin/env bash
# Runs the Embabel agents (animal, demo) against local Ollama and writes an
# agent-run evidence JSON (rc, duration, JSON-parse retries, sha256 of logs).
# Deterministic pass rule: rc==0 AND expected output marker present.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${OUT_DIR:-.attest-out}"; mkdir -p "$OUT"
MODEL="${EMBABEL_MODELS_DEFAULTLLM:-qwen3.5:4b}"
JAR=target/ProjectName-0.1.0-SNAPSHOT.jar
[ -f "$JAR" ] || mvn -q -B package -DskipTests
curl -sf http://127.0.0.1:11434/api/version >/dev/null || { echo "Ollama not running" >&2; exit 1; }
declare -A MARK=([animal]='Animal\(name=' [demo]='# Reviewer')
fail=0; rows=()
for c in animal demo; do
  s=$(date +%s); EMBABEL_MODELS_DEFAULTLLM=$MODEL timeout 900 java -jar "$JAR" "$c" > "$OUT/agent-$c.log" 2>&1; rc=$?
  d=$(( $(date +%s)-s )); retries=$(grep -c 'Retry attempt' "$OUT/agent-$c.log"); perr=$(grep -c 'Could not parse' "$OUT/agent-$c.log")
  if [ $rc -eq 0 ] && grep -Eq "${MARK[$c]}" "$OUT/agent-$c.log"; then st=pass; else st=fail; fail=1; fi
  rows+=("{\"agent\":\"$c\",\"status\":\"$st\",\"rc\":$rc,\"wall_s\":$d,\"retries\":$retries,\"parse_errors\":$perr,\"log_sha256\":\"$(sha256sum "$OUT/agent-$c.log"|cut -d' ' -f1)\"}")
  echo "agent=$c status=$st rc=$rc wall=${d}s retries=$retries"
done
python3 - "$MODEL" "${rows[@]}" > "$OUT/agent-runs.json" <<'P'
import json,sys,hashlib
runs=[json.loads(r) for r in sys.argv[2:]]
body={"schema":"embabel-agent-runs@1","model":sys.argv[1],"provider":"ollama","runs":runs,
      "verdict":"PASS" if all(r["status"]=="pass" for r in runs) else "FAIL"}
body["evidence_hash"]=hashlib.sha256(json.dumps(runs,sort_keys=True).encode()).hexdigest()
print(json.dumps(body,indent=2))
P
echo "agent-run evidence -> $OUT/agent-runs.json"; exit $fail
