#!/usr/bin/env python3

import streamlit as st

from utils import get_connection, get_sidebar_filters


def main():
    st.set_page_config(layout="wide")
    conn = get_connection()
    filters = get_sidebar_filters(conn)

    p_path = st.text_input('File path (regex)', 'Makefile')
    p_path = f".*({p_path}).*" if p_path else None

    last_commits = conn.sql(f"""
    SELECT repo, path, first(size)
    FROM git_files JOIN repos ON repo_id=repos.id
    WHERE ($path IS NULL OR path ~ $path) AND {filters.repo_filter}
    GROUP BY repo, path
    ORDER BY path DESC LIMIT 500
    """, params=filters.repo_params | {'path': p_path}).df()
    st.markdown(f"### Files ({len(last_commits)})")
    st.dataframe(last_commits, hide_index=True, use_container_width=True)


if __name__ == '__main__':
    main()
