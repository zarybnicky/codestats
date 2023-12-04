#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess

from dotenv import load_dotenv
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from schema import Repos
from utils import prefill_and_reroot

def main():
    load_dotenv(override=False)

    engine = create_engine(url=os.environ["SQLALCHEMY_DATABASE_URL"])

    with Session(engine) as sess:
        prefill_and_reroot(sess)
        sess.commit()

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
    main()
