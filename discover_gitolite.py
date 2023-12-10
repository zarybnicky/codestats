#!/usr/bin/env python3

import os
import subprocess

from sqlalchemy import select
from sqlalchemy.orm import Session
from sqlalchemy.dialects.postgresql import insert
from schema import Providers, Repos

from utils import with_env_and_session

def discover_gitolite(sess: Session):
    provider = sess.scalar(select(Providers).where(Providers.name == "Gitolite"))
    assert provider
    settings = provider.settings

    cmd_result = subprocess.run(
        ['bash', '-c', f"ssh {settings['host']} 2>/dev/null | tail -n +3 | cut -b6-"],
        stdout=subprocess.PIPE
    ).stdout.decode('utf-8')
    repos = [f"{repo}.git" for repo in cmd_result.splitlines()]

    stmt = insert(Repos).returning(Repos.repo).values([
        {'repo': repo, 'provider': provider.id, 'settings': {
            'root': os.path.join(settings['root'], repo),
            'origin': os.path.join(settings['origin'], repo),
        }}
        for repo in repos
    ])
    stmt = stmt.on_conflict_do_nothing()
    result = sess.execute(stmt).all()

    sess.commit()

    print(f"Discovered {len(repos)} repos")
    print(f"Inserted {len(result)} new repos")


if __name__ == '__main__':
    with_env_and_session(discover_gitolite)
