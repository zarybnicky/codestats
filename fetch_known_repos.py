#!/usr/bin/env python3

from pathlib import Path
import subprocess

from sqlalchemy import select
from sqlalchemy.orm import Session

from schema import Repos
from utils import with_env_and_session

def fetch_known_repos(sess: Session):
    repos = sess.scalars(select(Repos)).all()

    for repo in repos:
        root = Path(repo.settings['root'])
        origin = repo.settings['origin']

        dir_path = root.parent
        dir_path.mkdir(parents=True, exist_ok=True)

        if root.is_dir():
            print(f"Fetching {repo.repo}")

            result = subprocess.Popen(["git", "fetch", "--prune"], cwd=root, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
            for line in iter(lambda: result.stdout.readline(), b""):
                print(line.decode("utf-8"))
            if result.wait() != 0:
                print("Failed to fetch")
        else:
            print(f"Cloning {repo.repo}")

            result = subprocess.Popen(["git", "clone", "--bare", origin], cwd=dir_path, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
            for line in iter(lambda: result.stdout.readline(), b""):
                print(line.decode("utf-8"))
            try:
                subprocess.run(["git", "config", "remote.origin.fetch", "+*:*"], cwd=root)
            except FileNotFoundError:
                print("Clone failed")


if __name__ == '__main__':
    with_env_and_session(fetch_known_repos)
