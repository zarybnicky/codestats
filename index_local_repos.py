#!/usr/bin/env python3

from io import StringIO
import io
import os
import subprocess
import multiprocessing
from queue import Empty
import sys
from typing import List
import pandas as pd
import rich
from sqlalchemy import Engine, select
from sqlalchemy.engine.interfaces import DBAPICursor
from sqlalchemy.orm import Session
from rich.progress import BarColumn, MofNCompleteColumn, Progress

from schema import Repos
from utils import with_env_and_engine


def index_local_repos(engine: Engine):
    queue = multiprocessing.JoinableQueue()
    updates = multiprocessing.JoinableQueue()
    repos = 0
    with Session(engine) as sess:
        for repo in sess.scalars(select(Repos)).all():
            _ = repo.id
            _ = repo.repo
            _ = repo.settings
            queue.put(repo)
            repos += 1
    engine.dispose()

    workers: List[multiprocessing.Process] = []
    for _ in range(4):
        process = multiprocessing.Process(target=indexer, args=(engine, queue, updates))
        process.start()
        workers.append(process)

    ui_worker = multiprocessing.Process(target=ui, args=(updates, repos))
    ui_worker.start()

    queue.join()
    for process in workers:
        process.join()
    ui_worker.terminate()

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

def ui(updates: multiprocessing.JoinableQueue, repos: int):
    with Progress(
        "[progress.description]{task.description}",
        BarColumn(),
        MofNCompleteColumn(),
    ) as progress:
        skipped = 0
        tasks = {
            'parse': progress.add_task("Parse repo", total=repos),
            'db': progress.add_task("Write to DB", total=repos),
            'skipped': progress.add_task("Skipped/empty", total=None),
        }
        while True:
            update = updates.get(block=True)
            if update is None:
                break
            if update[0] == 'advance':
                progress.advance(tasks[update[1]], 1)
                if update[1] == 'skipped':
                    skipped += 1
                    progress.update(tasks['parse'], total=repos - skipped)
                    progress.update(tasks['db'], total=repos - skipped)
            else:
                rich.print(update)
            updates.task_done()


def indexer(engine: Engine, queue: multiprocessing.JoinableQueue, updates: multiprocessing.Queue):
    while True:
        try:
            repo = queue.get(block=False)
        except Empty:
            break

        root = repo.settings['root']
        try:
            result = subprocess.Popen(
                ['git', 'rev-parse', "HEAD"],
                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            if result.stdout.readline() == b'HEAD\n':
                updates.put(('advance', 'skipped'))
                queue.task_done()
                continue

        except FileNotFoundError:
            updates.put(('advance', 'skipped'))
            queue.task_done()
            continue

        with Session(engine) as sess:
            cursor = sess.connection().connection.cursor()
            cursor.execute("CREATE TEMP TABLE git_files_tmp (LIKE git_files INCLUDING DEFAULTS) ON COMMIT DROP")
            cursor.execute("CREATE TEMP TABLE git_commits_tmp (LIKE git_commits INCLUDING DEFAULTS) ON COMMIT DROP")
            cursor.execute("CREATE TEMP TABLE git_commit_stats_tmp (LIKE git_commit_stats INCLUDING DEFAULTS) ON COMMIT DROP")

            index_commits(cursor, repo)
            index_current_files(cursor, repo)
            updates.put(('advance', 'parse'))

            cursor.execute("DELETE FROM git_files where repo_id in (select distinct repo_id from git_files_tmp limit 1)")
            cursor.execute("with rows as (INSERT INTO git_files SELECT * FROM git_files_tmp ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows")
            cursor.execute("DELETE FROM git_commits where repo_id = (select repo_id from git_commits_tmp limit 1)")
            cursor.execute("with rows as (INSERT INTO git_commits SELECT * FROM git_commits_tmp ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows");
            cursor.execute("DELETE FROM git_commit_stats where repo_id = (select repo_id from git_commit_stats_tmp limit 1)")
            cursor.execute("with rows as (INSERT INTO git_commit_stats SELECT * FROM git_commit_stats_tmp ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows");

            sess.commit()
            updates.put(('advance', 'db'))

        queue.task_done()


def index_commits(cursor: DBAPICursor, repo: Repos):
    result = subprocess.Popen(
        ['git', 'log', "--pretty=format:|%H|%an|%ae|%at|%cn|%ce|%ct|%p|%s", '--numstat'],
        cwd=repo.settings['root'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
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


def index_current_files(cursor: DBAPICursor, repo: Repos):
    files = []

    result = subprocess.Popen(
        ['git', 'ls-tree', '-r', '--format=%(objectmode)|%(objecttype)|%(objectname)|%(objectsize)|%(path)', 'HEAD'],
        cwd=repo.settings['root'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    for line in iter(lambda: result.stdout.readline(), b""):
        line = line.decode('utf-8').encode('utf-8','ignore').decode("utf-8").strip()
        x = line.split('|', maxsplit=5)
        files.append([
            repo.id,
            x[4],
            bool(int(x[0], 8) & 0o100),
            pd.NA if x[3] == '-' else int(x[3]),
            os.path.splitext(x[4])[1] or os.path.basename(x[4]),
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
