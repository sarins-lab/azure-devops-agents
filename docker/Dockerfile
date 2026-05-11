FROM node:22-alpine

RUN apk add --no-cache tini

# Keep npm current to reduce transitive vulnerability exposure in bundled npm dependencies.
RUN npm install -g npm@latest

# Pin the package version at build time; override with --build-arg PACKAGE_VERSION=x.y.z
ARG PACKAGE_VERSION=2.7.0
RUN npm install -g @azure-devops/mcp@${PACKAGE_VERSION}

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Injected by the launcher from .ado-mcp.json
ENV ado_mcp_project=""
ENV ado_mcp_team=""

USER node
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
