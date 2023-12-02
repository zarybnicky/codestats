#!/usr/bin/env python3

from concurrent.futures import ThreadPoolExecutor, as_completed
from io import StringIO
import json
import os
import os.path
from pathlib import Path
import subprocess

import git
import git.exc
import requests
import streamlit as st
import pandas as pd
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.automap import automap_base
from streamlit.connections import SQLConnection
from streamlit.runtime.scriptrunner import add_script_run_ctx

st.set_page_config(layout="wide")
conn: SQLConnection = st.connection("sql", url=os.environ["SQLALCHEMY_DATABASE_URL"])


def init():
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

    return conn


def clone_repo_list(conn: SQLConnection) -> None:
    repos = conn.query("select repo, settings->>'root' as root, settings->>'origin' as origin from repos", ttl=0)['repo']

    progress = st.progress(0, text=f"0/{len(repos)} repos")
    done = 0
    with st.status("Cloning...", expanded=True) as status:
        for repo in repos:
            repo_path = Path(repo['root'])

            dir_path = repo_path.parent
            dir_path.mkdir(parents=True, exist_ok=True)

            if repo_path.is_dir():
                st.write(f"Fetching {repo['repo']}")

                result = subprocess.Popen(["git", "fetch", "--prune"], cwd=repo_path, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
                for line in iter(lambda: result.stdout.readline(), b""):
                    st.text(line.decode("utf-8"))
            else:
                repo_url = repo['origin']
                st.write(f"Cloning from {repo_url}")

                result = subprocess.Popen(["git", "clone", "--bare", repo_url], cwd=dir_path, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)
                for line in iter(lambda: result.stdout.readline(), b""):
                    st.text(line.decode("utf-8"))
                subprocess.run(["git", "config", "remote.origin.fetch", "+*:*"], cwd=repo_path)

            done += 1
            progress.progress(done / len(repos), text=f"{done}/{len(repos)} repos")
        progress.empty()
        status.update(label=f"Cloned/fetched {done} repos", state="complete", expanded=False)


def fetch_gitolite(provider_id: str, settings: dict) -> pd.DataFrame:
    host = settings['host']

    repo_list = subprocess.run(
        ['bash', '-c', f'ssh "{host}" 2>/dev/null | tail -n +3 | cut -b6-'],
        stdout=subprocess.PIPE
    ).stdout.decode('utf-8').splitlines()

    df = pd.DataFrame((f"{x}.git" for x in repo_list), columns=['repo'])
    df['provider'] = provider_id
    df['settings'] = df['repo'].map(lambda n: json.dumps({
        'root': os.path.join(settings['root'], n),
        'origin': os.path.join(settings['origin'], n),
    }))
    return df


def fetch_gitlab(provider_id: str, settings: dict) -> pd.DataFrame:
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

    df = pd.DataFrame(repo_list, columns=['repo'])
    df['provider'] = provider_id
    df['settings'] = df['repo'].map(lambda n: json.dumps({
        'root': os.path.join(settings['root'], n),
        'origin': os.path.join(settings['origin'], n),
    }))
    return df


def index_current_files(repo_object):
    try:
        repo = git.Repo(repo_object['root'])
        head = repo.head.commit
    except git.exc.NoSuchPathError:
        return 0
    except ValueError:
        return 0

    files = []
    for f in head.tree.list_traverse():
        if f.type == 'blob':
            files.append([
                repo_object['id'],
                str(f.path).encode('utf-8','ignore').decode("utf-8"),
                f.file_mode & 0o100,
            ])
    df = pd.DataFrame(files, columns=['repo_id', 'path', 'executable']);

    if df.empty:
        return 0

    with conn.engine.connect() as conn2:
        cursor = conn2.connection.cursor()

        s_buf = StringIO()
        df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
        s_buf.seek(0)
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE git_files INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo_id, path, executable) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)
        cursor.execute("DELETE FROM git_files where repo_id = (select repo_id from tmp_table limit 1)")
        cursor.execute("INSERT INTO git_files SELECT * FROM tmp_table ON CONFLICT DO NOTHING RETURNING 1")
        inserted = cursor.fetchall()
        count = len(inserted)
        conn2.commit()
        return count


def get_repo(root: str) -> git.Repo | None:
    try:
        repo = git.Repo(root)
        _ = repo.head.commit
        return repo
    except git.exc.NoSuchPathError:
        return None
    except ValueError:
        return None


def index_commit_stats(repo_object: dict) -> int:
    repo = get_repo(repo_object['root'])
    if repo is None:
        return 0

    commit_stats = []
    for x in repo.iter_commits():
        for path, stats in x.stats.files.items():
            commit_stats.append([
                repo_object['id'],
                x.hexsha,
                path,
                stats['insertions'],
                stats['deletions'],
            ])

    df = pd.DataFrame(commit_stats, columns=[
        'repo_id',
        'commit_hash',
        'file_path',
        'additions',
        'deletions',
    ])

    if df.empty:
        return 0

    with conn.engine.begin() as conn2:
        cursor = conn2.connection.cursor()

        s_buf = StringIO()
        df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
        s_buf.seek(0)
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE git_commit_stats INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo_id, commit_hash, file_path, additions, deletions) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)
        cursor.execute("DELETE FROM git_commit_stats where repo_id = (select repo_id from tmp_table limit 1)")
        cursor.execute("INSERT INTO git_commit_stats SELECT * FROM tmp_table ON CONFLICT DO NOTHING RETURNING 1")
        inserted = cursor.fetchall()
        count = len(inserted)
        return count

def index_commits(repo_object: dict) -> int:
    repo = get_repo(repo_object['root'])
    if repo is None:
        return 0

    commits = []
    for x in repo.iter_commits():
        commits.append([
            repo_object['id'],
            x.hexsha,
            x.message,
            x.author.name,
            x.author.email,
            x.authored_date,
            x.committer.name,
            x.committer.email,
            x.committed_date,
            len(x.parents),
        ])

    df = pd.DataFrame(commits, columns=[
        'repo_id',
        'hash',
        'message',
        'author_name',
        'author_email',
        'author_when',
        'committer_name',
        'committer_email',
        'committer_when',
        'parents'
    ])
    df['author_when'] = pd.to_datetime(df['author_when'], unit='s', origin='unix')
    df['committer_when'] = pd.to_datetime(df['committer_when'], unit='s', origin='unix')

    if df.empty:
        return 0

    with conn.engine.begin() as conn2:
        cursor = conn2.connection.cursor()

        s_buf = StringIO()
        df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
        s_buf.seek(0)
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE git_commits INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo_id, hash, message, author_name, author_email, author_when, committer_name, committer_email, committer_when, parents) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)
        cursor.execute("DELETE FROM git_commits where repo_id = (select repo_id from tmp_table limit 1)")
        cursor.execute("INSERT INTO git_commits SELECT * FROM tmp_table ON CONFLICT DO NOTHING RETURNING 1")
        inserted = cursor.fetchall()
        count = len(inserted)
        return count


def select_provider(conn):
    providers = conn.query('select id, name, settings from mergestat.providers', ttl=3600)
    provider_name = st.selectbox("Forge", options=providers['name'], index=None)
    selected = providers[providers['name'] == provider_name]
    return None if selected.empty else selected.iloc[0]


def select_repo(conn, provider) -> str | None:
    df = conn.query("select id, repo, settings->>'root' as root from repos where provider = :id", params={'id': provider['id']}, ttl=0)
    st.write(f"Total: {len(df)} repos")

    repo_ix = st.selectbox("Repo", options=df.index, format_func=lambda x: df.loc[x]['repo'])
    repo_object = df.loc[repo_ix]

    try:
        repo = git.Repo(repo_object['root'])
        _ = repo.head.commit
    except git.exc.NoSuchPathError:
        st.write("No local repo")
        return
    except ValueError:
        st.write("Local repo is empty")
        return


def main():
    conn = init()

    providers = conn.query('select * from mergestat.providers', ttl=3600)
    refresh_gitolite = st.sidebar.button("List Gitolite")
    refresh_gitlab = st.sidebar.button("List Gitlab")
    should_clone = st.sidebar.button("Clone/fetch all repos")
    should_index_commits = st.sidebar.button("Index commits")
    should_index_files = st.sidebar.button("Index current files")
    should_index_commit_stats = st.sidebar.button("Index commit+file stats (WIP)")

    if refresh_gitolite or refresh_gitlab:
        with st.status("Refreshing...", expanded=True) as status:
            provider_name = "Gitolite" if refresh_gitolite else "Gitlab"
            provider = providers[providers['name'] == provider_name].iloc[0]
            st.write(provider)
            fetcher = fetch_gitolite if refresh_gitolite else fetch_gitlab
            repos = fetcher(provider['id'], provider['settings'])
            st.write(f"Found {len(repos)} repos")

            with conn.session as sess:
                cursor = sess.connection().connection.cursor()
                s_buf = StringIO()
                repos.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
                s_buf.seek(0)
                cursor.execute("CREATE TEMP TABLE tmp_table (LIKE repos INCLUDING DEFAULTS) on commit drop")
                cursor.copy_expert("COPY tmp_table (repo, provider, settings) FROM STDIN WITH (FORMAT CSV, delimiter E'\\t')", s_buf)
                cursor.execute("INSERT INTO repos SELECT * FROM tmp_table on conflict do nothing RETURNING repo")
                inserted = cursor.fetchall()
                count = len(inserted)
                st.write([x[0] for x in inserted])
                sess.commit()

            st.write(f"Inserted new {count} repos")
            status.update(label=f"Found {count} new repos", state="complete", expanded=False)

    if should_clone:
        clone_repo_list(conn)

    if should_index_commits:
        repos = conn.query("select id, repo, settings->>'root' as root from repos", ttl=0)

        progress = st.progress(0, text=f"0/{len(repos)} repos")
        with st.status("Indexing...", expanded=True) as status:
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = {executor.submit(index_commits, dict(repo)): repo for _, repo in repos.iterrows()}
                for t in executor._threads:
                    add_script_run_ctx(t)
                for idx, future in enumerate(as_completed(futures), start=1):
                    repo = futures[future]
                    count = future.result()
                    st.write(f"{repo['repo']}: {count} commits")
                    progress.progress(idx / len(repos), text=f"{idx}/{len(repos)} repos")
        progress.empty()
        status.update(label=f"Indexed {len(repos)} repos", state="complete", expanded=False)

    if should_index_commit_stats:
        repos = conn.query("select id, repo, settings->>'root' as root from repos", ttl=0)

        progress = st.progress(0, text=f"0/{len(repos)} repos")
        with st.status("Indexing...", expanded=True) as status:
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = {executor.submit(index_commit_stats, dict(repo)): repo for _, repo in repos.iterrows()}
                for t in executor._threads:
                    add_script_run_ctx(t)
                for idx, future in enumerate(as_completed(futures), start=1):
                    repo = futures[future]
                    count = future.result()
                    st.write(f"{repo['repo']}: {count} commits")
                    progress.progress(idx / len(repos), text=f"{idx}/{len(repos)} repos")
        progress.empty()
        status.update(label=f"Indexed {len(repos)} repos", state="complete", expanded=False)

    if should_index_files:
        repos = conn.query("select id, repo, settings->>'root' as root from repos", ttl=0)

        progress = st.progress(0, text=f"0/{len(repos)} repos")
        with st.status("Indexing...", expanded=True) as status:
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = {executor.submit(index_current_files, dict(repo)): repo for _, repo in repos.iterrows()}
                for t in executor._threads:
                    add_script_run_ctx(t)

                for idx, future in enumerate(as_completed(futures), start=1):
                    repo = futures[future]
                    count = future.result()
                    st.write(f"{repo['repo']}: {count} files")
                    progress.progress(idx / len(repos), text=f"{idx}/{len(repos)} repos")
        progress.empty()
        status.update(label=f"Indexed {len(repos)} repos", state="complete", expanded=False)

    provider = select_provider(conn)
    p_provider = provider['id'] if provider is not None and not provider.empty else None
    p_repo = st.text_input('Repository (SQL-like, with % as *)', '') or "%"
    p_author = st.text_input('Author e-mail (SQL-like, with % as *)', '') or "%"

    last_active = conn.query("""
    select repo, message, author_when, author_name, author_email
    from repos join git_commits on repo_id=repos.id
    where case when :id is null then true else provider = :id end and repo like :p_repo and author_email like :p_author
    order by author_when desc limit 100
    """, params={'id': p_provider, 'p_repo': p_repo, 'p_author': p_author}, ttl=0)
    last_active.set_index(keys=['author_when'], drop=True, inplace=True)
    st.markdown("### Last commit activity")
    st.write(last_active)

    col1, col2, col3 = st.columns(3)
    with col1:
        most_active = conn.query("""
        select repos.repo, count(hash)
        from repos join git_commits on repo_id=repos.id
        where case when :id is null then true else provider = :id end and repo like :p_repo and author_email like :p_author
        group by repos.repo order by count(hash) desc limit 100
        """, params={'id': p_provider, 'p_repo': p_repo, 'p_author': p_author}, ttl=0)
        st.markdown("### Most active repositories")
        st.write(most_active)
    with col2:
        authors = conn.query("""
        select author_email, count(hash)
        from repos join git_commits on repo_id=repos.id
        where case when :id is null then true else provider = :id end and repo like :p_repo and author_email like :p_author
        group by author_email order by count(hash) desc limit 100
        """, params={'id': p_provider, 'p_repo': p_repo, 'p_author': p_author}, ttl=0)
        st.markdown("### Most active authors")
        st.write(authors)
    with col3:
        authors = conn.query("""
        select committer_email, count(hash)
        from repos join git_commits on repo_id=repos.id
        where case when :id is null then true else provider = :id end and repo like :p_repo and author_email like :p_author
        group by committer_email order by count(hash) desc limit 100
        """, params={'id': p_provider, 'p_repo': p_repo, 'p_author': p_author}, ttl=0)
        st.markdown("### Most active committers")
        st.write(authors)

    st.markdown("### Commit count timeline")
    granularity = st.selectbox("Graph granularity", options=['month', 'week', 'day']) or 'week'
    per_period = conn.query("""
    select date_trunc(:granularity, author_when) as author_when, provider, count(hash)
    from repos join git_commits on repo_id=repos.id
    where case when :id is null then true else provider = :id end and repo like :p_repo and author_email like :p_author
    group by date_trunc(:granularity, author_when), provider order by author_when desc
    """, params={'id': p_provider, 'p_repo': p_repo, 'p_author': p_author, 'granularity': granularity}, ttl=0)
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)
    st.bar_chart(per_period, color='provider', y='count')


if __name__ == '__main__':
    main()
