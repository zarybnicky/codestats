#!/usr/bin/env python3

import streamlit as st

from utils import get_connection, get_sidebar_filters


def main():
    st.set_page_config(layout="wide")
    conn = get_connection()
    filters = get_sidebar_filters(conn)

    col1, col2, col3 = st.columns([3, 2, 4])
    with col1:
        st.markdown("### Most active repositories")
        most_active = conn.sql(f"""
        select repo, count(*) as commits
        from repos join git_commits on repo_id=repos.id
        WHERE {filters.commit_filter} group by repo order by count(hash) desc limit 100
        """, params=filters.commit_params).df()
        st.dataframe(most_active, hide_index=True)

    with col2:
        st.markdown("### Most active authors")
        authors = conn.sql(f"""
        select author_email, count(*) as commits
        from repos join git_commits on repo_id=repos.id
        WHERE {filters.commit_filter} group by author_email order by count(hash) desc limit 100
        """, params=filters.commit_params).df()
        st.dataframe(authors, hide_index=True)

    with col3:
        st.markdown("### Most changed files")
        active_files = conn.sql(f"""
        WITH {filters.t_commits}
        SELECT commits, repo, file_path FROM (
          SELECT COUNT(*) AS commits, s.repo_id, file_path
          FROM git_commit_stats s JOIN t_commits ON s.commit_hash=hash
          GROUP BY s.repo_id, s.file_path
          ORDER BY commits DESC LIMIT 100
        ) JOIN repos ON repo_id=repos.id
        """, params=filters.commit_params).df()
        st.dataframe(active_files, hide_index=True)


if __name__ == '__main__':
    main()
