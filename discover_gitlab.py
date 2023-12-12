#!/usr/bin/env python3

import os
from dotenv import load_dotenv

import duckdb
import pandas as pd
import requests

def discover_gitlab():
    load_dotenv(override=False)

    conn = duckdb.connect(":memory:")
    with open('schema.sql') as f:
        conn.sql(f.read())
    if os.path.exists('data/providers.csv'):
        conn.sql("COPY providers FROM 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")

    token = os.environ["GITLAB_TOKEN"]
    host = os.environ["GITLAB_HOST"]
    conn.sql(
        "INSERT OR IGNORE INTO providers (name, root, origin) values ($name, $root, $origin)",
        params={
            "name": "GitLab",
            'root': os.environ["GITLAB_ROOT"],
            'origin': f"https://{os.environ['GITLAB_USER']}:{token}@{host}/",
        }
    )

    page = 1
    repos = []
    while True:
        print(f"Fetching page {page}")
        results = requests.get(f"https://{host}/api/v4/projects?simple=true&private_token={token}&per_page=100&page={page}").json()
        if not results:
            break
        repos.extend('/'.join(x['ssh_url_to_repo'].split('/')[3:]) for x in results)
        page += 1

    df = pd.DataFrame({'repo': repo, 'provider': 'GitLab'} for repo in repos)
    res = conn.sql("INSERT INTO repos (repo, provider) SELECT repo, provider FROM df RETURNING 1").fetchall()

    print(f"Discovered {len(res)} repos")

    conn.sql("COPY (FROM providers) TO 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY (FROM repos) TO 'data/repos-gitlab.csv' WITH (HEADER 1, DELIMITER E'\\t')")

if __name__ == '__main__':
    discover_gitlab()
