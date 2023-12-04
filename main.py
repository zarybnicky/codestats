#!/usr/bin/env python3

from concurrent.futures import ThreadPoolExecutor, as_completed
from io import StringIO
import os
import os.path
import subprocess
from typing import Tuple

import altair as alt
import git
import git.exc
import streamlit as st
import pandas as pd
from streamlit.connections import SQLConnection
from streamlit.runtime.scriptrunner import add_script_run_ctx

st.set_page_config(layout="wide")
conn: SQLConnection = st.connection("sql", url=os.environ["SQLALCHEMY_DATABASE_URL"])


def index_current_files(repo_object):
    if not (repo := get_repo(repo_object['root'])):
        return 0

    files = []
    for f in repo.head.commit.tree.list_traverse():
        if f.type == 'blob':
            path = str(f.path).encode('utf-8','ignore').decode("utf-8")
            ext = os.path.splitext(path)[1] or os.path.basename(path)
            files.append([
                repo_object['id'],
                path,
                f.file_mode & 0o100,
                f.size,
                ext,
            ])
    df = pd.DataFrame(files, columns=['repo_id', 'path', 'executable', 'size', 'ext']);

    with conn.engine.begin() as conn2:
        cursor = conn2.connection.cursor()

        s_buf = StringIO()
        df.to_csv(s_buf, sep="\t", index=False, header=False, date_format='%Y-%m-%dT%H:%M:%S')
        s_buf.seek(0)
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE git_files INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo_id, path, executable, size, ext) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)
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


def index_commits(repo_object: dict) -> Tuple[int, int]:
    root = repo_object['root']
    if get_repo(root) is None:
        return (0, 0)

    result = subprocess.Popen(
        ['git', 'log', "--pretty=format:|%H|%an|%ae|%at|%cn|%ce|%ct|%p|%s", '--numstat'],
        cwd=root, stdout=subprocess.PIPE,
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
                repo_object['id'],
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
                repo_object['id'],
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

    with conn.engine.begin() as conn2:
        cursor = conn2.connection.cursor()
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE git_commits INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo_id, hash, message, author_name, author_email, author_when, committer_name, committer_email, committer_when, parents) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)
        cursor.execute("DELETE FROM git_commits where repo_id = (select repo_id from tmp_table limit 1)")
        cursor.execute("with rows as (INSERT INTO git_commits SELECT * FROM tmp_table ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows");
        commit_count = cursor.fetchone()[0]
        conn2.commit()

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

    with conn.engine.begin() as conn2:
        cursor = conn2.connection.cursor()
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE git_commit_stats INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (repo_id, commit_hash, file_path, additions, deletions) FROM STDIN (FORMAT CSV, delimiter E'\\t')", s_buf)
        cursor.execute("DELETE FROM git_commit_stats where repo_id = (select repo_id from tmp_table limit 1)")
        cursor.execute("with rows as (INSERT INTO git_commit_stats SELECT * FROM tmp_table ON CONFLICT DO NOTHING RETURNING 1) select count(*) from rows")
        patch_count = cursor.fetchone()[0]
        conn2.commit()

    return commit_count, patch_count


def select_provider(conn):
    providers = conn.query('select id, name, settings from mergestat.providers', ttl=3600)
    provider_name = st.selectbox("Forge", options=providers['name'], index=None)
    selected = providers[providers['name'] == provider_name]
    return None if selected.empty else selected.iloc[0]


def select_repo(conn, provider) -> str | None:
    df = conn.query("select id, repo, settings->>'root' as root from repos where provider = :id", params={'id': provider['id']}, ttl=3600)
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
    with st.sidebar:
        should_index_commits = st.button("Index commits")
        should_index_files = st.button("Index current files")
        should_find_duplicates = st.button("Find duplicates")
        provider = select_provider(conn)
        p_provider = provider['id'] if provider is not None and not provider.empty else None
        p_repo = st.text_input('Repository (regex)', '') or ""
        p_negrepo = st.text_input('Repository exclusion (regex)', 'mautic|matomo|imagemagick|osm2pgsql|simplesamle-php-upstream') or "^$"
        p_author = st.text_input('Author name/email (regex)', '') or ""
        p_negauthor = st.text_input('Author name/email exclusion (regex)', 'lctl.gov|immerda.ch|unige.ch|bastelfreak.de|kohlvanwijngaarden.nl') or "^$"
        granularity = st.selectbox("Graph granularity", options=['year', 'month', 'week', 'day']) or 'week'
        time_range = conn.query("select date_trunc('month', min(author_when) - interval '15 day')::date as min, date_trunc('month', max(author_when) + interval '15 day')::date as max from git_commits", ttl=3600)
        time_range = pd.date_range(start=time_range['min'][0], end=time_range['max'][0], freq='MS')
        time_range = st.select_slider(
            "Month range",
            options=time_range,
            value=(time_range[0], time_range[-1]),
            format_func=lambda x: str(x)[0:7]
        )
        basic_filter = """
        where not is_duplicate
        and case when :id is null then true else provider = :id end
        and repo ~* :p_repo and repo !~* :p_negrepo
        and (author_name ~* :p_author or author_email ~* :p_author)
        and (author_name !~* :p_negauthor and author_email !~* :p_negauthor)
        and author_when between :from and date_trunc('month', :to + interval '31 day')
        """
        params = {
            'id': p_provider,
            'p_repo': p_repo,
            'p_negrepo': p_negrepo,
            'p_author': p_author,
            'p_negauthor': p_negauthor,
            'from': time_range[0],
            'to': time_range[1],
            'granularity': granularity,
        }

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
                    commit_count, patch_count = future.result()
                    st.write(f"{repo['repo']}: {commit_count} commits and {patch_count} patches")
                    progress.progress(int(idx) / len(repos), text=f"{idx}/{len(repos)} repos")
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

    if should_find_duplicates:
        with conn.session as sess:
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
            ) update repos set is_duplicate = true where repo in (select dup from exact_mirrors)
            """)
            sess.commit()

    st.markdown("### Last commit activity")
    last_active = conn.query(f"""
    select repo, message, author_when, author_name, author_email
    from repos join git_commits on repo_id=repos.id
    {basic_filter} order by author_when desc limit 100
    """, params=params, ttl=3600)
    last_active.set_index(keys=['author_when'], drop=True, inplace=True)
    st.write(last_active)

    col1, col2, col3 = st.columns([3, 2, 4])
    with col1:
        st.markdown("### Most active repositories")
        most_active = conn.query(f"""
        select repos.repo, count(*) as commits
        from repos join git_commits on repo_id=repos.id
        {basic_filter} group by repos.repo order by count(hash) desc limit 100
        """, params=params, ttl=3600)
        st.dataframe(most_active, hide_index=True)
    with col2:
        st.markdown("### Most active authors")
        authors = conn.query(f"""
        select author_email, count(*) as commits
        from repos join git_commits on repo_id=repos.id
        {basic_filter} group by author_email order by count(hash) desc limit 100
        """, params=params, ttl=3600)
        st.dataframe(authors, hide_index=True)
    with col3:
        st.markdown("### Most active files")
        files = conn.query(f"""
        select count(*) as commits, repo, s.file_path
        from repos join git_commits on repo_id=repos.id join git_commit_stats s on hash=s.commit_hash
        {basic_filter} group by file_path, repo order by count(*) desc limit 100
        """, params=params, ttl=3600)
        st.dataframe(files, hide_index=True)

    st.markdown("### Commit count timeline")
    per_period = conn.query(f"""
    select date_trunc(:granularity, author_when) as author_when, providers.name as provider, count(*)
    from repos join git_commits on repo_id=repos.id join mergestat.providers on provider=providers.id
    {basic_filter} group by date_trunc(:granularity, author_when), providers.name order by author_when desc, providers.name desc
    """, params=params, ttl=3600)
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)
    st.bar_chart(per_period, color='provider', y='count')

    st.markdown("### Lines added/removed timeline")
    per_period = conn.query(f"""
    select date_trunc(:granularity, author_when) as author_when, sum(s.additions) as added, sum(s.deletions) as deleted
    from repos join git_commits on repo_id=repos.id join git_commit_stats s on hash=s.commit_hash
    {basic_filter} group by date_trunc(:granularity, author_when), provider order by author_when desc
    """, params=params, ttl=3600)
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)
    st.bar_chart(per_period, y=['added', 'deleted'])

    st.markdown("### Activity chart (GitHub contribution graph)")
    per_period = conn.query(f"""
    select date_trunc('day', author_when) as date, count(*) as count
    from repos join git_commits on repo_id=repos.id
    {basic_filter} group by date_trunc('day', author_when) order by date desc
    """, params=params, ttl=3600)
    per_period.set_index(keys=['date'], drop=False, inplace=True)

    if per_period.empty:
        per_period = pd.DataFrame(columns=['date', 'count'])
        years = pd.Series()
        year_range = [2023]
    else:
        years = per_period['date'].dt.year
        year_range = range(years.max(), years.min() - 1, -1)
    tabs = st.tabs([str(year) for year in year_range])
    for idx, year in enumerate(year_range):
        with tabs[idx]:
            per_year = per_period[years == year]['count']
            scale = alt.Scale(domain=[1, per_year.quantile(.95) or 30])
            per_year = per_year.reindex(
                pd.date_range(f'01-01-{year}', f'12-31-{year}', tz='UTC', name='date'),
                fill_value=0
            ).reset_index()

            chart = alt.Chart(per_year, title=f"Activity chart for year {year}").mark_rect().encode(
                alt.X("week(date):O").title("Month"),
                alt.Y('day(date):O').title("Day"),
                alt.Color("count:Q", scale=scale).title(None),
                tooltip=[
                    alt.Tooltip("monthdate(date)", title="Date"),
                    alt.Tooltip("count:Q", title="Commits"),
                ],
            ).configure_axis(domain=False).configure_view(step=25, strokeWidth=0).configure_scale(
                bandPaddingInner=0.1
            )
            st.altair_chart(chart, use_container_width=True)

    st.markdown("### Last touched vs commits/files")
    old_repos = conn.query(f"""
    select max(date_trunc('day', author_when)) as last_touched, repo, count(*) as commits, max(files) as files
    from repos join git_commits on repo_id=repos.id
    left join lateral (select repo_id, count(*) as files from git_files group by repo_id) t on t.repo_id=repos.id
    {basic_filter} group by repo order by last_touched desc
    """, params=params, ttl=3600)
    c = alt.Chart(old_repos).mark_point().encode(
        alt.X('last_touched:T'),
        alt.Y('files:Q'),
        size='commits:Q',
        tooltip=['repo:N', 'commits:Q', 'files:Q', 'last_touched:T'],
    )
    st.altair_chart(c, use_container_width=True)

    st.markdown("### Technologies")
    most_active = conn.query(f"""
    with techs as (
    select path, ext,
    case ext
    when 'Dockerfile' then 'Docker'
    when '.js' then 'JavaScript'
    when '.ts' then 'TypeScript'
    when '.tsx' then 'TypeScript'
    when '.vue' then 'TypeScript'
    when '.tf' then 'Terraform'
    when '.rb' then 'Ruby'
    when '.erb' then 'Ruby'
    when '.pp' then 'Puppet'
    when '.go' then 'Go'
    when '.py' then 'Python'
    when '.java' then 'Java-like'
    when '.groovy' then 'Java-like'
    when '.pyc' then 'Artifact'
    when '.map' then 'Artifact'
    when '.ico' then 'Image'
    when '.JPG' then 'Image'
    when '.jpg' then 'Image'
    when '.webp' then 'Image'
    when '.svg' then 'Image'
    when '.gif' then 'Image'
    when '.png' then 'Image'
    when '.module' then 'Drupal'
    when '.info' then 'Drupal'
    when '.test' then 'Drupal'
    when '.install' then 'Drupal'
    when '.php' then 'PHP'
    when '.inc' then 'PHP template'
    when '.tpl' then 'PHP template'
    when '.phpt' then 'PHP template'
    when '.twig' then 'PHP template'
    when '.html' then 'HTML'
    when '.htm' then 'HTML'
    when '.xhtml' then 'HTML'
    when '.css' then 'CSS'
    when '.scss' then 'CSS'
    when '.less' then 'CSS'
    when '.markdown' then 'Document'
    when '.md' then 'Document'
    when '.pdf' then 'Document'
    when '.PDF' then 'Document'
    when '.rst' then 'Document'
    when '.txt' then 'Document'
    when '.xml' then 'Configuration'
    when '.yml' then 'Configuration'
    when '.yaml' then 'Configuration'
    when '.json' then 'Configuration'
    when '.conf' then 'Configuration'
    when '.sh' then 'Shell script'
    when '.gitignore' then null
    when 'LICENSE' then null
    else null end as tech
    from git_files
    ) select tech, count(*)
    from techs
    where tech is not null and tech <> 'Image' and tech <> 'Text' and tech <> 'Artifact'
    group by tech
    having count(*) > 2000
    order by count(*) desc limit 100
    """, params=params, ttl=3600)

    col1, col2 = st.columns(2)
    with col1:
        c = alt.Chart(most_active).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("count:Q"),
            color=alt.Color("tech:N").sort(field='count:Q').scale(scheme="category20"),
            order="count:Q",
        )
        st.altair_chart(c)

    with col2:
        most_active = conn.query("""
        select ext as tech, count(*)
        from git_files
        group by ext
        order by count(*) desc limit 20
        """, params=params, ttl=3600)
        c = alt.Chart(most_active).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("count:Q"),
            color=alt.Color("tech:N").sort(field='count:Q').scale(scheme="category20"),
            order="count:Q",
        )
        st.altair_chart(c)


if __name__ == '__main__':
    main()
