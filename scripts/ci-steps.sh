#!/usr/bin/env bash
# Shared body of the decision-gate workflow (runs in GitHub Actions or locally).
# Needs: BASE_SHA HEAD_SHA DECISION_RECORD LANGUAGE ATTEST_PORT OLLAMA_URL OLLAMA_MODEL
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.attest-out; rm -rf "$OUT"; mkdir -p "$OUT"; T=$(mktemp -d)
mkdir -p "$T/base" "$T/head"
git archive "$BASE_SHA" | tar -x -C "$T/base"; git archive "$HEAD_SHA" | tar -x -C "$T/head"
echo "base=$BASE_SHA head=$HEAD_SHA"
nohup arcade-attest serve --host 127.0.0.1 --port "$ATTEST_PORT" > "$OUT/attest-api.log" 2>&1 & API=$!
trap 'kill $API 2>/dev/null; rm -rf "$T"' EXIT
for i in $(seq 1 30); do curl -sf "http://127.0.0.1:$ATTEST_PORT/health" >/dev/null && break; sleep 1; done
BASE_TREE="$T/base" HEAD_TREE="$T/head" python3 - <<'P'
import json,os,urllib.request
rec=json.load(open(os.environ["DECISION_RECORD"]))
p={"repo":rec["repo"],"base_path":os.environ["BASE_TREE"],"head_path":os.environ["HEAD_TREE"],"language":os.environ["LANGUAGE"],"decision_record":rec}
r=urllib.request.Request(f"http://127.0.0.1:{os.environ['ATTEST_PORT']}/v1/decisions:evaluate",data=json.dumps(p).encode(),headers={"content-type":"application/json"})
pack=json.load(urllib.request.urlopen(r)); json.dump(pack,open(".attest-out/evidence-pack.json","w"),indent=2)
print("verdict:",pack["verdict"],"| overall_score:",pack.get("overall_score"),"| evidence_hash:",pack["hashes"]["evidence_hash"])
P
arcade-attest payload --pack "$OUT/evidence-pack.json" --base-commit "$BASE_SHA" --head-commit "$HEAD_SHA" > "$OUT/eas-payload.json"
arcade-attest render-comment --pack "$OUT/evidence-pack.json" --out "$OUT/comment.md"
if [ "${LLM_EXPLAIN:-true}" = true ]; then
  arcade-attest explain-qxotic --pack "$OUT/evidence-pack.json" --base-url "$OLLAMA_URL" --model "${EXPLAIN_MODEL:-qwen2.5:1.5b}" --timeout 300 --out "$OUT/llm-explanation.md" \
    && cat "$OUT/llm-explanation.md" >> "$OUT/comment.md" || echo "LLM explanation unavailable; continuing."
fi
hrc=0
if [ "${RUN_AGENTS:-true}" = true ]; then OUT_DIR=$OUT bash scripts/agent-harness.sh || hrc=$?; fi
V=$(python3 -c "import json;print(json.load(open('$OUT/evidence-pack.json'))['verdict'])")
echo "Decision verdict: $V (llm_in_verdict: false); agent harness rc=$hrc"
[ "$V" = BLOCK ] && [ "${ENFORCE_BLOCK:-true}" = true ] && exit 1
exit $hrc
