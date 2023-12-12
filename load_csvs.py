#!/usr/bin/env python3

from dotenv import load_dotenv

import duckdb

def load_csvs():
    load_dotenv(override=False)

    conn = duckdb.connect("data/git.duckdb")
    with open('schema.sql') as f:
        conn.sql(f.read())

    conn.sql("TRUNCATE git_files")
    conn.sql("TRUNCATE git_commits")
    conn.sql("TRUNCATE git_commit_stats")
    conn.sql("TRUNCATE repos")
    conn.sql("TRUNCATE providers")

    conn.sql("COPY providers FROM 'data/providers.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY repos FROM 'data/repos*.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY git_files FROM 'data/git_files.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY git_commits FROM 'data/git_commits.csv' WITH (HEADER 1, DELIMITER E'\\t')")
    conn.sql("COPY git_commit_stats FROM 'data/git_commit_stats.csv' WITH (HEADER 1, DELIMITER E'\\t')")

    conn.sql("update repos set is_duplicate = false")
    conn.sql("""
    with exact_mirrors as (
      select unnest((array_agg(repo))[2:]) as dup
      from repos
      left join lateral (select hash as first_rev from git_commits where repo_id=repos.id and parents=0) t2 on true
      left join lateral (select count(*) as commit_count from git_commits where repo_id=repos.id) t1 on true
      group by first_rev, commit_count
      having count(first_rev) > 1
    )
    update repos set is_duplicate = true where repo in (select dup from exact_mirrors)
    """)


if __name__ == '__main__':
    load_csvs()
