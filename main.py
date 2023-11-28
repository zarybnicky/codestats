#!/usr/bin/env python3

from io import StringIO
import os
from pathlib import Path
import subprocess

import git
import git.exc
import numpy as np
import gitpandas
import requests
import streamlit as st
import pandas as pd
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.automap import automap_base

conn = st.connection("sql", url=os.environ["SQLALCHEMY_DATABASE_URL"])

Base = automap_base()
Base.prepare(conn.engine)
Base.prepare(conn.engine, schema="mergestat")

Provider = Base.classes.providers

with conn.session as sess:
    stmt = insert(Provider).values([
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
        index_elements=[Provider.name],
        set_=dict(settings=stmt.excluded.settings)
    )
    sess.execute(stmt)
    sess.commit()

providers = conn.query('select * from mergestat.providers', ttl=3600)


def get_repo_paths(provider, repo):
    settings = provider['settings']
    root = Path(settings['root'])
    dir_path = root / '/'.join(repo.split('/')[:-1])
    repo_path = dir_path / repo.split('/')[-1]
    return dir_path, repo_path


def upsert_repo_list(repos):
    with conn.session as sess:
        s_buf = StringIO()
        repos.to_csv(s_buf, sep=",", index=False, header=False)
        s_buf.seek(0)
        cursor = sess.connection().connection.cursor()
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE repos INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo, provider) FROM STDIN WITH (FORMAT CSV, delimiter ',')", s_buf)
        cursor.execute("INSERT INTO repos SELECT * FROM tmp_table ON CONFLICT DO NOTHING RETURNING repo")
        inserted = cursor.fetchall()
        count = len(inserted)
        st.write([x[0] for x in inserted])
        sess.commit()
        return count


def clone_repo_list(provider):
    settings = provider['settings']
    origin = settings['origin']
    repos = conn.query("select repo from public.repos where provider = :id", params={'id': provider['id']}, ttl=0)['repo']

    progress = st.progress(0, text=f"0/{len(repos)} repos")
    done = 0
    with st.status("Cloning...", expanded=True) as status:
        for repo in repos:
            dir_path, repo_path = get_repo_paths(provider, repo)

            dir_path.mkdir(parents=True, exist_ok=True)
            if repo_path.is_dir():
                st.write(f"Fetching {repo}")
                subprocess.run(["git", "config", "remote.origin.fetch", "+*:*"], cwd=repo_path)

                result = subprocess.Popen(["git", "fetch", "--prune"], cwd=repo_path, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
                for line in iter(lambda: result.stdout.readline(), b""):
                    st.text(line.decode("utf-8"))
            else:
                repo_url = f"{origin}{repo}"
                st.write(f"Cloning from {repo_url}")

                result = subprocess.Popen(["git", "clone", "--bare", repo_url], cwd=dir_path, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
                for line in iter(lambda: result.stdout.readline(), b""):
                    st.text(line.decode("utf-8"))

            done += 1
            progress.progress(done / len(repos), text=f"{done}/{len(repos)} repos")
        progress.empty()
        status.update(label=f"Cloned/fetched {done} repos", state="complete", expanded=False)


def fetch_gitolite(provider):
    st.write(provider)
    settings = provider['settings']
    host = settings['host']

    repo_list = subprocess.run(
        ['bash', '-c', f'ssh "{host}" 2>/dev/null | tail -n +3 | cut -b6-'],
        stdout=subprocess.PIPE
    ).stdout.decode('utf-8').splitlines()

    df = pd.DataFrame(f"{x}.git" for x in repo_list)
    df['provider'] = provider['id']
    return df


def fetch_gitlab(provider):
    st.write(provider)
    settings = provider['settings']
    host = settings['host']
    token = settings['token']

    page = 1
    repo_list = []
    while True:
        results = requests.get(f"https://{host}/api/v4/projects?simple=true&private_token={token}&per_page=100&page={page}").json()
        if not results:
            break
        repo_list.extend('/'.join(x['ssh_url_to_repo'].split('/')[3:]) for x in results)
        page += 1

    df = pd.DataFrame(repo_list)
    df['provider'] = provider['id']
    return df


def main():
    refresh_gitolite = st.sidebar.button("List Gitolite")
    clone_gitolite = st.sidebar.button("Clone/fetch Gitolite")
    refresh_gitlab = st.sidebar.button("List Gitlab")
    clone_gitlab = st.sidebar.button("Clone Gitlab")

    if refresh_gitolite or refresh_gitlab:
        with st.status("Refreshing...", expanded=True) as status:
            provider_name = "Gitolite" if refresh_gitolite else "Gitlab"
            provider = providers[providers['name'] == provider_name].iloc[0]

            repos = fetch_gitolite(provider) if refresh_gitolite else fetch_gitlab(provider)
            st.write(f"Found {len(repos)} repos")
            count = upsert_repo_list(repos)
            st.write(f"Inserted new {count} repos")
            status.update(label=f"Found {count} new repos", state="complete", expanded=False)

    if clone_gitlab or clone_gitolite:
        provider_name = "Gitolite" if clone_gitolite else "Gitlab"
        provider = providers[providers['name'] == provider_name].iloc[0]
        clone_repo_list(provider)

    provider_name = st.selectbox("Provider", options=providers['name'])
    provider = providers[providers['name'] == provider_name].iloc[0]

    df = conn.query("select id, repo from public.repos where provider = :id", params={'id': provider['id']}, ttl=0)
    st.write(f"Total: {len(df)} repos")

    repo_ix = st.selectbox("Repo", options=df.index, format_func=lambda x: df.loc[x]['repo'])
    repo_name = df.loc[repo_ix]['repo']

    try:
        repo = git.Repo(get_repo_paths(provider, repo_name)[1])
    except git.exc.NoSuchPathError:
        st.write("No local repo")
        return

    try:
        head = repo.head.commit
    except ValueError:
        st.write("Local repo is empty")
        return

    try:
        repo = gitpandas.Repository(str(get_repo_paths(provider, repo_name)[1]))
    except git.exc.NoSuchPathError:
        st.write("No local repo")
        return

    blame = repo.blame(include_globs=['*'])
    st.write(blame)
    st.write(repo.commit_history('master', limit=None))


if __name__ == '__main__':
    main()
