#!/usr/bin/env python3

import streamlit as st

from utils import get_connection, get_sidebar_filters


def main():
    st.set_page_config(layout="wide")
    conn = get_connection()
    filters = get_sidebar_filters(conn)

    last_commits = conn.sql(f"""
    SELECT repo, message, author_when, author_name, author_email
    FROM git_commits JOIN repos ON git_commits.repo_id=repos.id
    WHERE {filters.commit_filter} ORDER BY author_when DESC LIMIT 100
    """, params=filters.commit_params).df()
    st.markdown("### Last commit activity")
    st.dataframe(last_commits, hide_index=True)

    last_projects = conn.sql(f"""
    WITH maxdate AS (
      select (date_trunc('day', max(author_when)) - interval '3 day')::date as maxdate
      from git_commits JOIN repos ON git_commits.repo_id=repos.id
      WHERE {filters.commit_filter}
    )
    SELECT repo, count(hash), max(author_when)
    FROM git_commits JOIN repos ON git_commits.repo_id=repos.id
    WHERE {filters.commit_filter}
    AND author_when > (SELECT maxdate FROM maxdate)
    GROUP BY repo
    ORDER BY count(hash) DESC LIMIT 100
    """, params=filters.commit_params).df()
    st.markdown("### Most active in last 3 days")
    st.dataframe(last_projects, hide_index=True)

if __name__ == '__main__':
    main()
