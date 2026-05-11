FROM node:alpine AS builder

RUN apk add --no-cache tini

# Pin the package version at build time; override with --build-arg PACKAGE_VERSION=x.y.z
ARG PACKAGE_VERSION=2.7.0
RUN npm install -g @azure-devops/mcp@${PACKAGE_VERSION}

FROM node:alpine

RUN apk add --no-cache tini

COPY --from=builder /usr/local/lib/node_modules/@azure-devops /usr/local/lib/node_modules/@azure-devops
COPY --from=builder /usr/local/bin/mcp-server-azuredevops /usr/local/bin/mcp-server-azuredevops

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Injected by the launcher from .ado-mcp.json
ENV ado_mcp_project=""
ENV ado_mcp_team=""

USER node
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
