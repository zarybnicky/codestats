#!/usr/bin/env python3

import altair as alt
import humanize
import streamlit as st

from utils import get_connection, get_sidebar_filters


def main():
    st.set_page_config(layout="wide")
    conn = get_connection()
    filters = get_sidebar_filters(conn)

    st.markdown("### Largest files and their authors")
    largest_files = conn.sql(f"""
    WITH big AS (
      select id, repo, path, size
      FROM git_files JOIN repos ON repo_id=repos.id
      WHERE {filters.repo_filter} AND size IS NOT NULL ORDER BY size DESC NULLS LAST LIMIT 50
    )
    SELECT DISTINCT ON (repo, path) repo, path, size, author_when, author_name || ' <' || author_email || '>' as author, message
    FROM big
    JOIN git_commits ON repo_id=big.id
    JOIN git_commit_stats ON git_commit_stats.repo_id=big.id AND commit_hash=hash
    ORDER BY size DESC, author_when DESC
    """, params=filters.repo_params).df()
    largest_files['size'] = largest_files['size'].fillna(0).apply(humanize.naturalsize)
    st.dataframe(largest_files, hide_index=True)

    col1, col2, col3 = st.columns(3)
    with col1:
        st.markdown("### Largest repos")
        largest_repos = conn.sql(f"""
        select repo, sum(coalesce(size, 0)) as size
        FROM git_files JOIN repos ON repo_id=repos.id
        WHERE {filters.repo_filter} GROUP BY repo ORDER BY SUM(size) DESC LIMIT 20
        """, params=filters.repo_params).df()
        largest_repos['size'] = largest_repos['size'].apply(humanize.naturalsize)
        st.dataframe(largest_repos, hide_index=True)
    with col2:
        st.markdown("### Size by technologies")
        most_active = conn.sql(f"""
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
        """, params=filters.repo_params).df()
        most_active['human_bytes'] = most_active['bytes'].fillna(0).apply(humanize.naturalsize)
        most_active['biggest_size'] = most_active['biggest_size'].apply(humanize.naturalsize)

        c = alt.Chart(most_active).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("bytes:Q"),
            color=alt.Color("tech:N").sort(field='bytes:Q').scale(scheme="category20"),
            order="bytes:Q",
            tooltip=['human_bytes', 'tech', 'biggest_size', 'biggest_repo', 'biggest_path'],
        )
        st.altair_chart(c)

    with col3:
        st.markdown("### Size by extensions")
        most_active = conn.sql(f"""
        WITH exts AS (
          SELECT ext, SUM(size) AS bytes,
          FROM git_files LEFT JOIN repos ON repo_id=repos.id
          WHERE {filters.repo_filter} AND size IS NOT NULL GROUP BY ext ORDER BY bytes DESC LIMIT 20
        )
        SELECT DISTINCT ON (exts.ext) exts.ext, bytes, repo as biggest_repo, size as biggest_size, path as biggest_path
        FROM exts
        JOIN git_files on exts.ext=git_files.ext
        JOIN repos ON repo_id=repos.id
        ORDER BY bytes DESC, size DESC
        """, params=filters.repo_params).df()
        most_active['human_bytes'] = most_active['bytes'].fillna(0).apply(humanize.naturalsize)
        most_active['biggest_size'] = most_active['biggest_size'].fillna(0).apply(humanize.naturalsize)

        c = alt.Chart(most_active).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("bytes:Q"),
            color=alt.Color("ext:N").sort(field='bytes:Q').scale(scheme="category20"),
            order="bytes:Q",
            tooltip=['human_bytes', 'ext', 'biggest_size', 'biggest_repo', 'biggest_path'],
        )
        st.altair_chart(c)


if __name__ == '__main__':
    main()
