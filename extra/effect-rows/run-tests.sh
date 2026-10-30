#!/usr/bin/env bash
# Load and test the effect-rows vocabularies. Usage: extra/effect-rows/run-tests.sh [log]
cd "$(dirname "$0")/../.."
log=${1:-$HOME/er-test.log}
./factor -e='USING: stack-checker.state prettyprint vocabs.loader tools.test kernel ; \ inference-observer . "effect-rows" require "effect-rows" test' </dev/null > "$log" 2>&1
echo "EXIT $?" >> "$log"
