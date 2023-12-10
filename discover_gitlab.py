#!/usr/bin/env python3

import os

import requests
from sqlalchemy import select
from sqlalchemy.orm import Session
from sqlalchemy.dialects.postgresql import insert
from schema import Providers, Repos

from utils import with_env_and_session

def discover_gitlab(sess: Session):
    provider = sess.scalar(select(Providers).where(Providers.name == "Gitlab"))
    assert provider
    settings = provider.settings

    host = settings['host']
    token = settings['token']

    page = 1
    repo_list = []
    while True:
        print(f"Fetching page {page}")
        results = requests.get(f"https://{host}/api/v4/projects?simple=true&private_token={token}&per_page=100&page={page}").json()
        if not results:
            break
        repo_list.extend('/'.join(x['ssh_url_to_repo'].split('/')[3:]) for x in results)
        page += 1

    stmt = insert(Repos).returning(Repos.repo).values([
        {'repo': repo, 'provider': provider.id, 'settings': {
            'root': os.path.join(settings['root'], repo),
            'origin': os.path.join(settings['origin'], repo),
        }}
        for repo in repo_list
    ])
    stmt = stmt.on_conflict_do_nothing()

    result = sess.execute(stmt).all()

    sess.commit()

    print(f"Discovered {len(repo_list)} repos")
    print(f"Inserted {len(result)} new repos")


if __name__ == '__main__':
    with_env_and_session(discover_gitlab)
