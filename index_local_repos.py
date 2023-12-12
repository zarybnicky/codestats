#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess
from dotenv import load_dotenv

import duckdb
import pandas as pd
from rich.progress import track

def index_local_repos():
    load_dotenv(override=False)

    conn = duckdb.connect(":memory:")
    with open('schema.sql') as f:
        conn.sql(f.read())

    conn.sql("COPY providers FROM 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY repos FROM 'data/repos*.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    repos = conn.sql("SELECT repos.id, repos.repo, root || '/' || repo as root, origin || '/' || repo as origin FROM repos JOIN providers ON provider=providers.name").df()

    f_files = open('data/git_files.csv', 'a')
    f_commits = open('data/git_commits.csv', 'a')
    f_commit_stats = open('data/git_commit_stats.csv', 'a')

    for _, repo in track(list(repos.iterrows())):
        root = Path(repo['root'])
        try:
            result = subprocess.Popen(
                ['git', 'rev-parse', "HEAD"],
                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            if result.stdout.readline() == b'HEAD\n':
                continue
        except FileNotFoundError:
            continue

        index_commits(repo, f_commits, f_commit_stats)
        index_current_files(repo, f_files)

        print(f"Processed {repo['repo']}")

    f_files.close()
    f_commits.close()
    f_commit_stats.close()

    # conn.sql("START TRANSACTION")
    # conn.sql("COMMIT")
    # conn.sql("INSERT INTO git_files (repo_id, path, executable, size, ext) SELECT * FROM df")
    # conn.sql("INSERT INTO git_commits (repo_id, hash, message, author_name, author_email, author_when, committer_name, committer_email, committer_when, parents, additions, deletions) SELECT * FROM df")
    # conn.sql("INSERT INTO git_commit_stats (repo_id, commit_hash, file_path, additions, deletions) SELECT * FROM df")

    # conn.sql("""
    # with exact_mirrors as (
    #   select unnest((array_agg(repo))[2:]) as dup
    #   from repos
    #   left join lateral (select hash as first_rev from git_commits where repo_id=repos.id and parents=0) t2 on true
    #   left join lateral (select count(*) as commit_count from git_commits where repo_id=repos.id) t1 on true
    #   group by first_rev, commit_count
    #   having count(first_rev) > 1
    # ), reverted as (
    #   update repos set is_duplicate = false
    # )
    # update repos set is_duplicate = true where repo in (select dup from exact_mirrors)
    # """)


def index_commits(repo: pd.Series, f_commits, f_commit_stats):
    result = subprocess.Popen(
        ['git', 'log', "--pretty=format:|%H|%an|%ae|%at|%cn|%ce|%ct|%p|%s", '--numstat', '--no-renames'],
        cwd=repo['root'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    commits = []
    commit_stats = []
    last_commit = None
    for line in iter(lambda: result.stdout.readline(), b""):
        line = line.decode('utf-8').strip()
        if not line:
            continue
        if line.startswith('|'):
            x = line.split('|', maxsplit=10)
            commits.append([
                repo['id'],
                x[1],
                x[9].strip(),
                x[2],
                x[3],
                int(x[4]),
                x[5],
                x[6],
                int(x[7]),
                len([y for y in x[8].split() if y.strip()]),
                0,
                0,
            ])
            last_commit = x[1]
        else:
            x = line.split(maxsplit=2)
            if x[0] == '-' and x[1] == '-':
                continue
            added = int(x[0])
            deleted = int(x[1])
            commit_stats.append([
                repo['id'],
                last_commit,
                x[2],
                added,
                deleted,
            ])
            commits[-1][-2] += added
            commits[-1][-1] += deleted

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
        'parents',
        'additions',
        'deletions',
    ])
    df['author_when'] = pd.to_datetime(df['author_when'], unit='s', origin='unix')
    df['committer_when'] = pd.to_datetime(df['committer_when'], unit='s', origin='unix')
    df.to_csv(f_commits, sep="\t", index=False, header=f_commits.tell() == 0, date_format='%Y-%m-%dT%H:%M:%S')

    df = pd.DataFrame(commit_stats, columns=[
        'repo_id',
        'commit_hash',
        'file_path',
        'additions',
        'deletions',
    ])
    df.to_csv(f_commit_stats, sep="\t", index=False, header=f_commit_stats.tell() == 0, date_format='%Y-%m-%dT%H:%M:%S')


def index_current_files(repo: pd.Series, f_files):
    files = []

    result = subprocess.Popen(
        ['git', 'ls-tree', '-r', '--format=%(objectmode)|%(objecttype)|%(objectname)|%(objectsize)|%(path)', 'HEAD'],
        cwd=repo['root'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    for line in iter(lambda: result.stdout.readline(), b""):
        line = line.decode('utf-8').encode('utf-8','ignore').decode("utf-8").strip()
        x = line.split('|', maxsplit=5)
        files.append([
            repo['id'],
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
    df.to_csv(f_files, sep="\t", header=f_files.tell() == 0, index=False, date_format='%Y-%m-%dT%H:%M:%S')


if __name__ == '__main__':
    index_local_repos()
