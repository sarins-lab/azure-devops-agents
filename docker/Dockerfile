FROM node:20-alpine

RUN apk add --no-cache tini

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ENV vars the official package reads for project/team context
# (injected by the launcher from .ado-mcp.json)
ENV ado_mcp_project=""
ENV ado_mcp_team=""

USER node
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
