#!/usr/bin/env python3

import altair as alt
import streamlit as st
import pandas as pd

from utils import get_connection, get_sidebar_filters


def main():
    st.set_page_config(layout="wide")
    conn = get_connection()
    filters = get_sidebar_filters(conn)

    per_period = conn.sql(f"""
    select date_trunc($granularity, author_when) as author_when, providers.name as provider, count(*) as count
    from repos join git_commits on repo_id=repos.id join providers on provider=providers.name
    WHERE {filters.commit_filter}
    group by date_trunc($granularity, author_when), providers.name
    order by author_when desc, providers.name desc
    """, params=filters.commit_params | {'granularity':filters.granularity}).df()
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)

    st.markdown("### Commit count timeline")
    st.bar_chart(per_period, color='provider', y='count')

    st.markdown("### Lines added/removed timeline")
    per_period = conn.sql(f"""
    select date_trunc($granularity, author_when) as author_when, sum(additions) as added, sum(deletions) as deleted
    from repos join git_commits on repo_id=repos.id
    WHERE {filters.commit_filter}
    group by date_trunc($granularity, author_when)
    order by author_when desc
    """, params=filters.commit_params | {'granularity':filters.granularity}).df()
    per_period.set_index(keys=['author_when'], drop=True, inplace=True)
    st.bar_chart(per_period, y=['added', 'deleted'])

    st.markdown("### Activity chart (GitHub contribution graph)")
    per_period = conn.sql(f"""
    SELECT date_trunc('day', author_when) as date, count(*) as count
    FROM repos join git_commits on repo_id=repos.id
    WHERE {filters.commit_filter}
    GROUP BY date_trunc('day', author_when) order by date desc
    """, params=filters.commit_params).df()
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
                pd.date_range(f'01-01-{year}', f'12-31-{year}', name='date'),
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
    old_repos = conn.sql(f"""
    select max(date_trunc('day', author_when)) as last_touched, repo, count(*) as commits, max(files) as files
    from repos join git_commits on repo_id=repos.id
    left join lateral (select repo_id, count(*) as files from git_files group by repo_id) t on t.repo_id=repos.id
    WHERE {filters.commit_filter} group by repo order by last_touched desc
    """, params=filters.commit_params).df()
    c = alt.Chart(old_repos).mark_point().encode(
        alt.X('last_touched:T'),
        alt.Y('commits:Q'),
        size='files:Q',
        tooltip=['repo:N', 'commits:Q', 'files:Q', 'last_touched:T'],
    )
    st.altair_chart(c, use_container_width=True)


if __name__ == '__main__':
    main()
