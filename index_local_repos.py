#!/usr/bin/env python3

from io import StringIO
import os
import subprocess
import multiprocessing
import pandas as pd
import git
import git.exc
from sqlalchemy import Engine, select, text
from sqlalchemy.engine.interfaces import DBAPICursor
from sqlalchemy.orm import Session, scoped_session, sessionmaker
from schema import Repos

from utils import with_env_and_engine


def indexer(engine: Engine, queue: multiprocessing.Queue):
    while True:
        repo = queue.get(block=True)
        if repo is None:
            break
        with Session(engine) as sess:
            sess.execute(text("CREATE TEMP TABLE git_files_tmp (LIKE git_files INCLUDING DEFAULTS) on commit drop"))
            sess.execute(text("CREATE TEMP TABLE git_commits_tmp (LIKE git_commits INCLUDING DEFAULTS) on commit drop"))
            sess.execute(text("CREATE TEMP TABLE git_commit_stats_tmp (LIKE git_commit_stats INCLUDING DEFAULTS) on commit drop"))
            cursor = sess.connection().connection.cursor()

            root = repo.settings['root']
            print(f"{root}")
            try:
                gitrepo = git.Repo(root)
                _ = gitrepo.head.commit
            except git.exc.NoSuchPathError:
                continue
            except ValueError:
                continue

            index_commits(cursor, repo)
            index_current_files(cursor, repo, gitrepo)

            cursor.execute("DELETE FROM git_files where repo_id in (select distinct repo_id from git_files_tmp limit 1)")
            cursor.execute("with rows as (INSERT INTO git_files SELECT * FROM git_files_tmp ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows")
            cursor.execute("DELETE FROM git_commits where repo_id = (select repo_id from git_commits_tmp limit 1)")
            cursor.execute("with rows as (INSERT INTO git_commits SELECT * FROM git_commits_tmp ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows");
            cursor.execute("DELETE FROM git_commit_stats where repo_id = (select repo_id from git_commit_stats_tmp limit 1)")
            cursor.execute("with rows as (INSERT INTO git_commit_stats SELECT * FROM git_commit_stats_tmp ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows");

            sess.commit()


def index_local_repos(engine: Engine):
    the_queue = multiprocessing.Queue()

    with Session(engine) as sess:
        repos = sess.scalars(select(Repos)).all()
        for repo in repos:
            _ = repo.id
            _ = repo.settings
            the_queue.put(repo)

    engine.dispose()
    the_pool = multiprocessing.Pool(3, indexer, (engine, the_queue))

    the_queue.close()
    the_queue.join_thread()
    the_pool.close()
    the_pool.join()

    with Session(engine) as sess:
        cursor = sess.connection().connection.cursor()
        cursor.execute("""
        with exact_mirrors as (
          select unnest((array_agg(repo))[2:]) as dup
          from repos
          left join lateral (select hash as first_rev from git_commits where repo_id=repos.id and parents=0) t2 on true
          left join lateral (select count(*) as commit_count from git_commits where repo_id=repos.id) t1 on true
          group by first_rev, commit_count
          having count(first_rev) > 1
        ), reverted as (
          update repos set is_duplicate = false
        )
        update repos set is_duplicate = true where repo in (select dup from exact_mirrors)
        """)


def index_commits(cursor: DBAPICursor, repo: Repos):
    result = subprocess.Popen(
        ['git', 'log', "--pretty=format:|%H|%an|%ae|%at|%cn|%ce|%ct|%p|%s", '--numstat'],
        cwd=repo.settings['root'], stdout=subprocess.PIPE,
    )
    commits = []
    commit_stats = []
    last_commit = None
    for line in iter(lambda: result.stdout.readline(), b""):
        line = line.decode('utf-8').lstrip()
        if not line:
            continue
        if line.startswith('|'):
            x = line.split('|', maxsplit=10)
            commits.append([
                repo.id,
                x[1],
                x[9].strip(),
                x[2],
                x[3],
                int(x[4]),
                x[5],
                x[6],
                int(x[7]),
                len([y for y in x[8].split() if y.strip()]),
            ])
            last_commit = x[1]
        else:
            x = line.split()
            if x[0] == '-' and x[1] == '-':
                continue
            commit_stats.append([
                repo.id,
                last_commit,
                x[2],
                int(x[0]),
                int(x[1]),
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
    s_buf = StringIO()
    df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
    s_buf.seek(0)
    cursor.copy_expert("COPY git_commits_tmp (repo_id, hash, message, author_name, author_email, author_when, committer_name, committer_email, committer_when, parents) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)

    df = pd.DataFrame(commit_stats, columns=[
        'repo_id',
        'commit_hash',
        'file_path',
        'additions',
        'deletions',
    ])
    s_buf = StringIO()
    df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
    s_buf.seek(0)
    cursor.copy_expert("COPY git_commit_stats_tmp (repo_id, commit_hash, file_path, additions, deletions) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)


def index_current_files(cursor: DBAPICursor, repo: Repos, gitrepo: git.Repo):
    files = []

    # git ls-tree --full-name -rl HEAD

    for f in gitrepo.head.commit.tree.list_traverse():
        if f.type == 'blob':
            path = str(f.path).encode('utf-8','ignore').decode("utf-8")
            ext = os.path.splitext(path)[1] or os.path.basename(path)
            files.append([
                repo.id,
                path,
                f.file_mode & 0o100,
                f.size,
                ext,
            ])
    df = pd.DataFrame(files, columns=[
        'repo_id',
        'path',
        'executable',
        'size',
        'ext',
    ])
    s_buf = StringIO()
    df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
    s_buf.seek(0)
    cursor.copy_expert("COPY git_files_tmp (repo_id, path, executable, size, ext) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)


if __name__ == '__main__':
    with_env_and_engine(index_local_repos)
