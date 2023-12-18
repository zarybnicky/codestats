#!/usr/bin/env python3

from pathlib import Path
import subprocess

from dotenv import load_dotenv
import duckdb
from rich.progress import track

def fetch_known_repos():
    load_dotenv(override=False)

    conn = duckdb.connect(":memory:")
    with open('schema.sql') as f:
        conn.sql(f.read())

    conn.sql("COPY providers FROM 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY repos FROM 'data/repos*.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    repos = conn.sql("SELECT repos.repo, root || repo as root, origin || repo as origin FROM repos JOIN providers ON provider=providers.name").df()

    for _, repo in track(list(repos.iterrows())):
        root = Path(repo['root'])
        origin = repo['origin']

        dir_path = root.parent
        dir_path.mkdir(parents=True, exist_ok=True)

        if root.is_dir():
            print(f"Fetching {repo.repo} in {root}")

            result = subprocess.Popen(["git", "fetch", "--prune"], cwd=root, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
            for line in iter(lambda: result.stdout.readline(), b""):
                print(line.decode("utf-8"))
            if result.wait() != 0:
                print("Failed to fetch")
        else:
            print(f"Cloning {repo['repo']} from {origin} at {dir_path}")

            result = subprocess.Popen(["git", "clone", "--bare", origin], cwd=dir_path, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
            for line in iter(lambda: result.stdout.readline(), b""):
                print(line.decode("utf-8"))
            try:
                subprocess.run(["git", "config", "remote.origin.fetch", "+*:*"], cwd=root)
            except FileNotFoundError:
                print("Clone failed")


if __name__ == '__main__':
    fetch_known_repos()
