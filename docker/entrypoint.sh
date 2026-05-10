#!/bin/sh
set -e

: "${ADO_ORG:?ADO_ORG environment variable is required (your Azure DevOps organization name)}"

ADO_AUTH="${ADO_AUTH:-pat}"

exec npx --yes -- @azure-devops/mcp "$ADO_ORG" --authentication "$ADO_AUTH" "$@"
