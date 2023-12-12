#!/usr/bin/env python3

import datetime
import os
import os.path
from typing import NamedTuple

import altair as alt
import humanize
from sqlalchemy import text
import streamlit as st
import pandas as pd
from streamlit.connections import SQLConnection


class Filters(NamedTuple):
    provider: str | None
    pos_repo: str | None
    neg_repo: str | None
    pos_author: str | None
    neg_author: str | None
    granularity: str
    time_from: datetime.datetime
    time_to: datetime.datetime

    @property
    def t_repos(self):
        return f"""
        t_repos as (
          SELECT repos.* FROM repos
          WHERE NOT is_duplicate
          AND {"provider = :provider" if self.provider else "TRUE"}
          AND {"repo ~* :pos_repo" if self.pos_repo else "TRUE"}
          AND {"repo !~* :neg_repo" if self.neg_repo else "TRUE"}
        )
        """
    @property
    def t_commits(self):
        return f"""
        t_commits as (
          SELECT git_commits.*
          FROM git_commits JOIN t_repos on t_repos.id=repo_id
          WHERE author_when BETWEEN :time_from AND date_trunc('month', :time_to + INTERVAL '31 day')
          AND {"(author_name ~* :pos_author OR author_email ~* :pos_author)" if self.pos_author else "TRUE"}
          AND {"(author_name !~* :neg_author AND author_email !~* :neg_author)" if self.neg_author else "TRUE"}
        )
        """

    @property
    def repo_filter(self):
        return f"""
        NOT is_duplicate
        AND {"provider = :provider" if self.provider else "TRUE"}
        AND {"repo ~* :pos_repo" if self.pos_repo else "TRUE"}
        AND {"repo !~* :neg_repo" if self.neg_repo else "TRUE"}
        """

    @property
    def commit_filter(self):
        return f"""
        {self.repo_filter}
        AND {"(author_name ~* :pos_author OR author_email ~* :pos_author)" if self.pos_author else "TRUE"}
        AND {"(author_name !~* :neg_author AND author_email !~* :neg_author)" if self.neg_author else "TRUE"}
        and author_when between :time_from and date_trunc('month', :time_to + interval '31 day')
        """

def main():
    st.set_page_config(layout="wide")
    conn: SQLConnection = st.connection("sql", url=os.environ["SQLALCHEMY_DATABASE_URL"], echo=True)

    with st.sidebar:
        providers = conn.query('select id, name, settings from mergestat.providers', ttl=3600)
        provider_name = st.selectbox("Forge", options=providers['name'], index=None)
        selected = providers[providers['name'] == provider_name]
        provider = None if selected.empty else selected.iloc[0]

        p_provider = provider['id'] if provider is not None and not provider.empty else None
        p_repo = st.text_input('Repository (regex)', '')
        p_negrepo = st.text_input('Repository exclusion (regex)', 'mautic|matomo|imagemagick|osm2pgsql|simplesamle-php-upstream')
        p_author = st.text_input('Author name/email (regex)', '')
        p_negauthor = st.text_input('Author name/email exclusion (regex)', 'lctl.gov|immerda.ch|unige.ch|bastelfreak.de|kohlvanwijngaarden.nl')
        granularity = st.selectbox("Graph granularity", options=['year', 'month', 'week', 'day']) or 'week'
        time_range = conn.query("select date_trunc('month', min(author_when) - interval '15 day')::date as min, date_trunc('month', max(author_when) + interval '15 day')::date as max from git_commits", ttl=3600)
        time_range = pd.date_range(start=time_range['min'][0], end=time_range['max'][0], freq='MS')
        time_range = st.select_slider(
            "Month range",
            options=time_range,
            value=(time_range[0], time_range[-1]),
            format_func=lambda x: str(x)[0:7]
        )

    filters = Filters(
        provider=p_provider,
        pos_repo=p_repo,
        neg_repo=p_negrepo,
        pos_author=p_author,
        neg_author=p_negauthor,
        time_from=time_range[0],
        time_to=time_range[1],
        granularity=granularity,
    )
    params = filters._asdict()

    st.markdown("### Last commit activity")
    last_commits = conn.query(f"""
    SELECT repo, message, author_when, author_name, author_email
    FROM git_commits JOIN repos ON git_commits.repo_id=repos.id
    WHERE {filters.commit_filter} ORDER BY author_when DESC LIMIT 100
    """, params=params, ttl=3600)
    st.dataframe(last_commits, hide_index=True)

    col1, col2, col3 = st.columns([3, 2, 4])
    with col1:
        st.markdown("### Most active repositories")
        most_active = conn.query(f"""
        select repo, count(*) as commits
        from repos join git_commits on repo_id=repos.id
        WHERE {filters.commit_filter} group by repo order by count(hash) desc limit 100
        """, params=params, ttl=3600)
        st.dataframe(most_active, hide_index=True)

    with col2:
        st.markdown("### Most active authors")
        authors = conn.query(f"""
        select author_email, count(*) as commits
        from repos join git_commits on repo_id=repos.id
        WHERE {filters.commit_filter} group by author_email order by count(hash) desc limit 100
        """, params=params, ttl=3600)
        st.dataframe(authors, hide_index=True)

    with col3:
        st.markdown("### Most active files")
        if st.checkbox("Calculate active files (slow)"):
            active_files = conn.query(f"""
            WITH {filters.t_repos}, {filters.t_commits}
            SELECT commits, repo, file_path FROM (
              SELECT COUNT(*) AS commits, s.repo_id, file_path
              FROM git_commit_stats s JOIN t_commits ON s.commit_hash=hash
              GROUP BY s.repo_id, s.file_path
              ORDER BY commits DESC LIMIT 100
            ) JOIN repos ON repo_id=repos.id
            """, params=params, ttl=3600)
            st.dataframe(active_files)

    per_period = conn.query(f"""
    select date_trunc(:granularity, author_when) as author_when, providers.name as provider, count(*)
    from repos join git_commits on repo_id=repos.id join mergestat.providers on provider=providers.id
    WHERE {filters.commit_filter}
    group by date_trunc(:granularity, author_when), providers.name
    order by author_when desc, providers.name desc
    """, params=params, ttl=3600)
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)
    
    st.markdown("### Commit count timeline")
    st.bar_chart(per_period, color='provider', y='count')

    st.markdown("### Lines added/removed timeline")
    per_period = conn.query(f"""
    select date_trunc(:granularity, author_when) as author_when, sum(s.additions) as added, sum(s.deletions) as deleted
    from repos join git_commits on repo_id=repos.id join git_commit_stats s on hash=s.commit_hash
    WHERE {filters.commit_filter}
    group by date_trunc(:granularity, author_when)
    order by author_when desc
    """, params=params, ttl=3600)
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)
    st.bar_chart(per_period, y=['added', 'deleted'])

    st.markdown("### Activity chart (GitHub contribution graph)")
    per_period = conn.query(f"""
    select date_trunc('day', author_when) as date, count(*) as count
    from repos join git_commits on repo_id=repos.id
    WHERE {filters.commit_filter} group by date_trunc('day', author_when) order by date desc
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
    WHERE {filters.commit_filter} group by repo order by last_touched desc
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
    select git_files.*, case ext
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
    FROM git_files LEFT JOIN repos ON repo_id=repos.id
    WHERE {filters.repo_filter}
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

    most_active = conn.query(f"""
    select ext as tech, sum(size) as bytes,
      (select repo from repos where id=(array_agg(repo_id order by size desc))[1]) as biggest_repo,
      (array_agg(size order by size desc))[1] as biggest_size,
      (array_agg(path order by size desc))[1] as biggest_path
    FROM git_files LEFT JOIN repos ON repo_id=repos.id
    WHERE {filters.repo_filter} group by ext order by bytes desc limit 20
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

    largest_files = conn.query(f"""
    select repo, path, size, t.*
    FROM git_files JOIN repos ON repo_id=repos.id
    LEFT JOIN LATERAL
      (SELECT author_when, author_name, author_email
        FROM git_commit_stats
        JOIN git_commits on hash=commit_hash
        WHERE git_commit_stats.repo_id=repos.id AND file_path=path
        ORDER BY author_when LIMIT 1
      ) t on true
    WHERE {filters.repo_filter} ORDER BY size DESC LIMIT 20
    """, params=params, ttl=3600)
    largest_files['size'] = largest_files['size'].apply(humanize.naturalsize)
    st.dataframe(largest_files, hide_index=True)

    largest_repos = conn.query(f"""
    select repo, sum(size) as size
    FROM git_files JOIN repos ON repo_id=repos.id
    WHERE {filters.repo_filter} GROUP BY repo ORDER BY SUM(size) DESC LIMIT 20
    """, params=params, ttl=3600)
    largest_repos['size'] = largest_repos['size'].apply(humanize.naturalsize)
    st.dataframe(largest_repos, hide_index=True)


def sizeof_fmt(num, suffix="B"):
    for unit in ("", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"):
        if abs(num) < 1024.0:
            return f"{num:3.1f}{unit}{suffix}"
        num /= 1024.0
    return f"{num:.1f}Yi{suffix}"


if __name__ == '__main__':
    main()
