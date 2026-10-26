#!/usr/bin/env bash
# Local equivalent of .github/workflows/ci-full.yml (push event).
# Uses the box's arcade-attest venv + running Ollama; never pushes or comments.
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ATTEST_VENV:-/workspace/embabel/arcade-attest/.venv}/bin/activate"
export DECISION_RECORD=.arcade-attest/decision-record.json LANGUAGE=kotlin ENFORCE_BLOCK=true \
  ATTEST_PORT=8787 LLM_EXPLAIN=true OLLAMA_MODEL=${OLLAMA_MODEL:-qwen3.5:4b} EXPLAIN_MODEL=${EXPLAIN_MODEL:-qwen2.5:1.5b} OLLAMA_URL=http://127.0.0.1:11434 RUN_AGENTS=${RUN_AGENTS:-true}
export BASE_SHA=${BASE_SHA:-$(git rev-parse HEAD~1)} HEAD_SHA=${HEAD_SHA:-$(git rev-parse HEAD)}
exec bash scripts/ci-steps.sh
