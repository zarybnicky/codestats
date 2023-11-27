#!/usr/bin/env bash

set -euo pipefail

REPO_LINES=""
for ((i=1; ; i+=1)); do
    echo "Fetching page $i"
    contents=$(curl -s "https://$GITLAB_HOST/api/v4/projects?simple=true&private_token=$GITLAB_TOKEN&per_page=100&page=$i")
    if jq -e '. | length == 0' >/dev/null; then
       break
    fi <<< "$contents"
    REPO_LINES+=$(echo "$contents" | jq -r '.[].ssh_url_to_repo')
    REPO_LINES+=$'\n'
done

for REPO in $REPO_LINES; do
    REPO=$(echo "$REPO" | cut -d/ -f4-)
    DIR=$(dirname "$REPO")
    BASE=$(basename "$REPO")

    mkdir -p "$GITLAB_ROOT_DIR/$DIR"
    cd "$GITLAB_ROOT_DIR/$DIR"

    if [ -d "$BASE" ]; then
        echo "Fetching $REPO"
        cd "$BASE"
        git config remote.origin.fetch "+*:*"
        git fetch --prune
    else
        git clone --bare "https://$GITLAB_USER:$GITLAB_TOKEN@$GITLAB_HOST/$REPO"
    fi
done
