#!/usr/bin/env bash

set -euo pipefail

REPO_LINES=$(ssh "$GITOLITE_HOST" 2>/dev/null | tail -n +3 | cut -b6-)

declare -Ai blacklist
for i in "${!REPO_BLACKLIST[@]}"; do
  ((blacklist["${REPO_BLACKLIST[i]%$'\r'}"] = i + 1))  # domain without \r -> line
done

for REPO in $REPO_LINES; do
    if ((blacklist["$REPO"])); then
        continue;
    fi

    DIR=$(dirname "$REPO")
    BASE=$(basename "$REPO")

    mkdir -p "$GITOLITE_ROOT_DIR/$DIR"
    cd "$GITOLITE_ROOT_DIR/$DIR"

    if [ -d "$BASE.git" ]; then
        echo "Fetching $REPO"
        cd "$BASE.git"
        git config remote.origin.fetch "+*:*"
        git fetch --prune
    else
        git clone --bare "ssh://$GITOLITE_HOST/$REPO.git"
    fi
done
