#!/usr/bin/env python3

import os
import os.path

import altair as alt
import git
import git.exc
import humanize
import streamlit as st
import pandas as pd
from streamlit.connections import SQLConnection

st.set_page_config(layout="wide")
conn: SQLConnection = st.connection("sql", url=os.environ["SQLALCHEMY_DATABASE_URL"])


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
        providers = conn.query('select id, name, settings from mergestat.providers', ttl=3600)
        provider_name = st.selectbox("Forge", options=providers['name'], index=None)
        selected = providers[providers['name'] == provider_name]
        provider = None if selected.empty else selected.iloc[0]

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
        with t_repos as (
          select repos.* from repos join mergestat.providers on provider=providers.id
          where not is_duplicate
          and case when :id is null then true else provider = :id end
          and repo ~* :p_repo and repo !~* :p_negrepo
        ), t_commits as (
          select git_commits.* from git_commits join t_repos on t_repos.id=repo_id
          where (author_name ~* :p_author or author_email ~* :p_author)
          and (author_name !~* :p_negauthor and author_email !~* :p_negauthor)
          and author_when between :from and date_trunc('month', :to + interval '31 day')
        )
        select count(*) as commits, repo, file_path
        from git_commit_stats s join t_commits on s.commit_hash=hash join t_repos on t_commits.repo_id=t_repos.id
        group by s.file_path, repo order by count(*) desc limit 100
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
        alt.Y('commits:Q'),
        size='files:Q',
        tooltip=['repo:N', 'commits:Q', 'files:Q', 'last_touched:T'],
    )
    st.altair_chart(c, use_container_width=True)

    st.markdown("### Technologies")
    most_active = conn.query(f"""
    with techs as (
    select repo_id, path, ext, size, case ext
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
    ) select tech, sum(size) as bytes,
      (select repo from repos where id=(array_agg(repo_id order by size desc))[1]) as biggest_repo,
      (array_agg(size order by size desc))[1] as biggest_size,
      (array_agg(path order by size desc))[1] as biggest_path
    from techs
    where tech is not null and tech <> 'Image' and tech <> 'Text' and tech <> 'Artifact'
    group by tech
    order by sum(size) desc limit 100
    """, params=params, ttl=3600)
    most_active['human_bytes'] = most_active['bytes'].apply(humanize.naturalsize)
    most_active['biggest_size'] = most_active['biggest_size'].apply(humanize.naturalsize)

    col1, col2 = st.columns(2)
    with col1:
        c = alt.Chart(most_active).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("bytes:Q"),
            color=alt.Color("tech:N").sort(field='bytes:Q').scale(scheme="category20"),
            order="bytes:Q",
            tooltip=['human_bytes', 'tech', 'biggest_size', 'biggest_repo', 'biggest_path'],
        )
        st.altair_chart(c)

    most_active = conn.query("""
    select ext as tech, sum(size) as bytes,
      (select repo from repos where id=(array_agg(repo_id order by size desc))[1]) as biggest_repo,
      (array_agg(size order by size desc))[1] as biggest_size,
      (array_agg(path order by size desc))[1] as biggest_path
    from git_files
    group by ext
    order by bytes desc limit 20
    """, params=params, ttl=3600)
    most_active['human_bytes'] = most_active['bytes'].apply(humanize.naturalsize)
    most_active['biggest_size'] = most_active['biggest_size'].apply(humanize.naturalsize)
    with col2:
        c = alt.Chart(most_active).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("bytes:Q"),
            color=alt.Color("tech:N").sort(field='bytes:Q').scale(scheme="category20"),
            order="bytes:Q",
            tooltip=['human_bytes', 'tech', 'biggest_size', 'biggest_repo', 'biggest_path'],
        )
        st.altair_chart(c)


def sizeof_fmt(num, suffix="B"):
    for unit in ("", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"):
        if abs(num) < 1024.0:
            return f"{num:3.1f}{unit}{suffix}"
        num /= 1024.0
    return f"{num:.1f}Yi{suffix}"


if __name__ == '__main__':
    main()
