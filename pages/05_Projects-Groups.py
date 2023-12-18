#!/usr/bin/env python3

import altair as alt
import streamlit as st

from utils import get_connection, get_sidebar_filters


def main():
    st.set_page_config(layout="wide")
    conn = get_connection()
    filters = get_sidebar_filters(conn)

    colors = """
    [
      IF(repo ilike '%hakka%', 'hakka', NULL),
      IF(repo ilike '%o11y%', 'o11y', NULL),
      IF(repo ilike '%mundomosa%' or repo ilike '%mundosalsa%' or repo ilike '%mundoscaldis%', 'mundomosa', NULL),
      IF(repo ilike '%mediamosa%' or repo ilike '%mediasalsa%', 'mediamosa', NULL),
      IF(repo ilike '%-dams%', 'dams', NULL),
      IF(repo ilike '%cinvio%', 'cinvio', NULL),
      IF(repo ilike '%sportoase%', 'sportoase', NULL),
      IF(repo ilike '%sqs%', 'sqs', NULL),
      IF(repo ilike '%digitrans%', 'digitrans', NULL),
      IF(repo ilike '%jenkins%', 'jenkins', NULL),
   -- IF(repo ilike '%puppet%' or repo ilike '%hiera%', 'puppet', NULL),
      IF(repo ilike '%terraform%' or repo ilike '%consul%' or repo ilike '%-nomad%', 'nomad', NULL),
    ]
    """

    per_period = conn.sql(f"""
    with colored as (
      select repos.*, unnest(list_distinct({colors})) as color from repos where {filters.repo_filter}
    )
    select date_trunc($granularity, author_when) as author_when, color, count(*) as count
    from colored join git_commits on repo_id=colored.id
    WHERE {filters.commit_filter} and color is not null
    group by date_trunc($granularity, author_when), color
    order by author_when desc
    """, params=filters.commit_params | {'granularity':filters.granularity}).df()
    # per_period.set_index(keys=['author_when'], drop=True, inplace=True)

    st.markdown("### Commit count timeline")
    c = alt.Chart(per_period).mark_bar().encode(
        x=alt.X('author_when:T'),
        y=alt.Y('count:Q', stack="normalize"),
        color='color:N'
    )
    st.altair_chart(c, use_container_width=True)

    last_commits = conn.sql(f"""
    with colored as (
      select repos.*, unnest(list_distinct({colors})) as color from repos where {filters.repo_filter}
    )
    SELECT repo, count(*) as count FROM repos join git_commits on repo_id=repos.id
    WHERE {filters.commit_filter} AND id not in (SELECT id FROM colored)
    group by repo ORDER BY count(*) DESC LIMIT 500
    """, params=filters.commit_params).df()
    st.markdown(f"### Uncategorized")
    st.dataframe(last_commits, hide_index=True, use_container_width=True)


if __name__ == '__main__':
    main()
