#!/bin/sh
set -e

: "${ADO_ORG:?ADO_ORG is required (your Azure DevOps organization name)}"
: "${ADO_MCP_AUTH_TOKEN:?ADO_MCP_AUTH_TOKEN is required (set this to your Azure DevOps PAT)}"

# Build -d domain flags from ADO_DOMAINS (comma-separated, e.g. "core,work,wiki")
domain_flags=""
if [ -n "$ADO_DOMAINS" ]; then
    for domain in $(echo "$ADO_DOMAINS" | tr ',' ' '); do
        domain_flags="$domain_flags -d $domain"
    done
fi

# shellcheck disable=SC2086
exec mcp-server-azuredevops "$ADO_ORG" --authentication envvar $domain_flags "$@"
