#!/usr/bin/env bash
set -euo pipefail

docker_image=""
build_docker=0
push_docker=0
publish=0
allow_dirty=0
remote="origin"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy.sh [options]

Options:
  --docker-image <image>  Docker image name to build or push.
  --build-docker          Build Docker image.
  --push-docker           Push Docker image.
  --publish               Create and push release artifacts.
  --allow-dirty           Allow publish with dirty working tree.
  --remote <name>         Git remote for Claude plugin tag push. Default: origin.
  -h, --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-image)
      docker_image="${2:-}"
      shift 2
      ;;
    --build-docker)
      build_docker=1
      shift
      ;;
    --push-docker)
      push_docker=1
      shift
      ;;
    --publish)
      publish=1
      shift
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    --remote)
      remote="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
cd "$repo_root"

dry_run=1
if [[ $publish -eq 1 ]]; then
  dry_run=0
fi

echo "Azure DevOps Planning Assistant deployment"
if [[ $dry_run -eq 1 ]]; then
  echo "Mode: dry-run. Pass --publish to create tags or push artifacts."
else
  echo "Mode: publish"
fi
echo

if [[ $publish -eq 1 && $allow_dirty -eq 0 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or stash changes, or rerun with --allow-dirty." >&2
    exit 1
  fi
fi

bash -n scripts/install.sh scripts/install-ado-mcp-user.sh scripts/ado-mcp-launcher.sh scripts/deploy.sh
node --check scripts/ado-mcp-launcher.mjs

node - <<'NODE'
const fs = require("fs");
const files = [
  ".mcp.json",
  ".claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json",
  ".agents/plugins/marketplace.json",
  "plugins/azure-devops-agents-codex/.codex-plugin/plugin.json",
  "plugins/azure-devops-agents-vscode/package.json"
];
for (const file of files) {
  JSON.parse(fs.readFileSync(file, "utf8"));
  console.log(`OK JSON: ${file}`);
}
NODE

claude plugin validate .claude-plugin/marketplace.json

if [[ $publish -eq 1 ]]; then
  claude plugin tag --remote "$remote" --push .
else
  claude plugin tag --dry-run --force .
fi

if [[ $build_docker -eq 1 || -n "$docker_image" ]]; then
  if [[ -z "$docker_image" ]]; then
    echo "--docker-image is required when --build-docker is used." >&2
    exit 1
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo ">> docker build -t $docker_image ./docker"
    echo "   dry-run: skipped"
  else
    docker build -t "$docker_image" ./docker
  fi

  if [[ $push_docker -eq 1 ]]; then
    if [[ $dry_run -eq 1 ]]; then
      echo ">> docker push $docker_image"
      echo "   dry-run: skipped"
    else
      docker push "$docker_image"
    fi
  fi
fi

echo
if [[ $dry_run -eq 1 ]]; then
  echo "Dry-run completed. No deployment artifacts were pushed."
else
  echo "Deployment completed."
fi
