#!/usr/bin/env python3

import os
from typing import Callable

from dotenv import load_dotenv
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from schema import VendorTypes, Vendors, Providers


def with_env_and_engine(fn: Callable[[Engine], None]):
    load_dotenv(override=False)

    engine = create_engine(url=os.environ["SQLALCHEMY_DATABASE_URL"])

    with Session(engine) as sess:
        prefill_and_reroot(sess)
        sess.commit()

    fn(engine)


def with_env_and_session(fn: Callable[[Session], None]):
    def f(engine: Engine):
        with Session(engine) as sess:
            fn(sess)
    with_env_and_engine(f)


def prefill_and_reroot(sess: Session):
    stmt = insert(VendorTypes).values([
        {'name': 'git', 'display_name': 'Git'}
    ])
    stmt = stmt.on_conflict_do_nothing()
    sess.execute(stmt)

    stmt = insert(Vendors).values([
        {'name': 'local', 'display_name': 'Local', 'type': 'git'}
    ])
    stmt = stmt.on_conflict_do_nothing()
    sess.execute(stmt)

    stmt = insert(Providers).values([
        {"name": "Gitolite", "vendor": "local", "settings": {
            'host': os.environ["GITOLITE_HOST"],
            'root': os.environ["GITOLITE_ROOT"],
            'origin': f"ssh://{os.environ['GITOLITE_HOST']}/",
        }},
        {"name": "Gitlab", "vendor": "local", "settings": {
            'host': os.environ["GITLAB_HOST"],
            'user': os.environ["GITLAB_USER"],
            'token': os.environ["GITLAB_TOKEN"],
            'root': os.environ["GITLAB_ROOT"],
            'origin': f"https://{os.environ['GITLAB_USER']}:{os.environ['GITLAB_TOKEN']}@{os.environ['GITLAB_HOST']}/",
        }}
    ])
    stmt = stmt.on_conflict_do_update(
        index_elements=[Providers.name],
        set_=dict(settings=stmt.excluded.settings)
    )
    sess.execute(stmt)

    sess.execute(text("update repos set settings = jsonb_set(settings, '{root}', to_jsonb((select settings->>'root' from mergestat.providers where id=repos.provider) || '/' || repo))"))

