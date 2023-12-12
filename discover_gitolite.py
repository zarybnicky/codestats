#!/usr/bin/env python3

import os
import subprocess
from dotenv import load_dotenv

import duckdb
import pandas as pd

def discover_gitolite():
    load_dotenv(override=False)

    conn = duckdb.connect(":memory:")
    with open('schema.sql') as f:
        conn.sql(f.read())
    if os.path.exists('data/providers.csv'):
        conn.sql("COPY providers FROM 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")

    host = os.environ["GITOLITE_HOST"]
    conn.sql(
        "INSERT OR IGNORE INTO providers (name, root, origin) values ($name, $root, $origin)",
        params={
            "name": "Gitolite",
            'root': os.environ["GITOLITE_ROOT"],
            'origin': f"ssh://{host}/",
        },
    )

    repos = subprocess.run(
        ['bash', '-c', f"ssh {host} 2>/dev/null | tail -n +3 | cut -b6-"],
        stdout=subprocess.PIPE
    ).stdout.decode('utf-8').splitlines()

    df = pd.DataFrame({'repo': f"{repo}.git", 'provider': 'Gitolite'} for repo in repos)
    res = conn.sql("INSERT INTO repos (repo, provider) SELECT repo, provider FROM df RETURNING 1").fetchall()

    print(f"Discovered {len(res)} repos from Gitolite")

    conn.sql("COPY (FROM providers) TO 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY (FROM repos) TO 'data/repos-gitolite.csv' WITH (HEADER 1, DELIMITER E'\\t')")


if __name__ == '__main__':
    discover_gitolite()
