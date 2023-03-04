#!/usr/bin/env zsh
curl --cacert ../certificates/es01.crt \
  -u elastic \
  -H "Content-Type: application/x-ndjson" \
  -XPOST https://localhost:9211/products/_bulk \
  --data-binary "@resources/section-3/products-bulk.json"
