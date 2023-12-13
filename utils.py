import datetime
from typing import NamedTuple
import duckdb

import pandas as pd
import streamlit as st


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
    def t_commits(self):
        return f"""
        t_commits as (
          SELECT git_commits.*
          FROM git_commits JOIN repos on repos.id=repo_id
          WHERE {self.commit_filter}
        )
        """

    @property
    def repo_params(self):
        return {
            key: self.__getattribute__(key)
            for key in ['provider', 'pos_repo', 'neg_repo']
            if self.__getattribute__(key)
        }

    @property
    def commit_params(self):
        return {
            key: self.__getattribute__(key)
            for key in ['provider', 'pos_repo', 'neg_repo', 'pos_author', 'neg_author', 'time_from', 'time_to']
            if self.__getattribute__(key)
        }

    @property
    def repo_filter(self):
        return f"""
        NOT is_duplicate
        AND {"provider = $provider" if self.provider else "TRUE"}
        AND {"repo ~ $pos_repo" if self.pos_repo else "TRUE"}
        AND {"repo !~ $neg_repo" if self.neg_repo else "TRUE"}
        """

    @property
    def commit_filter(self):
        return f"""
        {self.repo_filter}
        AND {"(author_name ~ $pos_author OR author_email ~ $pos_author)" if self.pos_author else "TRUE"}
        AND {"(author_name !~ $neg_author AND author_email !~ $neg_author)" if self.neg_author else "TRUE"}
        and author_when between $time_from and date_trunc('month', $time_to + interval '31 day')
        """

def get_sidebar_filters(conn):
    st.markdown("""
    <style>
    [data-testid="stSidebarNavItems"] {
      padding-top: 20px;
    }
    </style>
    """, unsafe_allow_html=True)

    time_range = conn.sql("select date_trunc('month', min(author_when) - interval '15 day')::date as min, date_trunc('month', max(author_when) + interval '15 day')::date as max from git_commits").df()
    time_range = pd.date_range(start=time_range['min'][0], end=time_range['max'][0], freq='MS')

    if 'provider' not in st.session_state:
        st.session_state['provider'] = None
    if 'granularity' not in st.session_state:
        st.session_state['granularity'] = 'week'
    if 'time_from' not in st.session_state:
        st.session_state['time_from'] = time_range[0]
    if 'time_to' not in st.session_state:
        st.session_state['time_to'] = time_range[-1]
    if 'pos_repo' not in st.session_state:
        st.session_state['pos_repo'] = None
    if 'neg_repo' not in st.session_state:
        st.session_state['neg_repo'] = 'mautic|matomo|imagemagick|osm2pgsql|simplesamle-php-upstream'
    if 'pos_author' not in st.session_state:
        st.session_state['pos_author'] = None
    if 'neg_author' not in st.session_state:
        st.session_state['neg_author'] = 'lctl.gov|immerda.ch|unige.ch|bastelfreak.de|kohlvanwijngaarden.nl'

    with st.sidebar:
        time_range = st.select_slider(
            "Month range",
            options=time_range,
            value=(st.session_state['time_from'], st.session_state['time_to']),
            format_func=lambda x: str(x)[0:7]
        )

        pos_repo = st.text_input('Repository (regex)', st.session_state['pos_repo'])
        neg_repo = st.text_input('Repository exclusion (regex)', st.session_state['neg_repo'])
        pos_author = st.text_input('Author name/email (regex)', st.session_state['pos_author'])
        neg_author = st.text_input('Author name/email exclusion (regex)', st.session_state['neg_author'])

        g_options = ['week', 'month', 'year', 'day']
        g_index = g_options.index(st.session_state['granularity']) if st.session_state['granularity'] in g_options else None
        granularity = st.selectbox("Graph granularity", options=g_options, index=g_index)

        p_options = list(conn.sql('select name from providers').df()['name'])
        p_index = p_options.index(st.session_state['provider']) if st.session_state['provider'] in p_options else None
        p_provider = st.selectbox("Forge", options=p_options, index=p_index)

    st.session_state['provider'] = p_provider
    st.session_state['granularity'] = granularity
    st.session_state['time_from'] = time_range[0]
    st.session_state['time_to'] = time_range[1]
    st.session_state['pos_repo'] = pos_repo
    st.session_state['neg_repo'] = neg_repo
    st.session_state['pos_author'] = pos_author
    st.session_state['neg_author'] = neg_author

    return Filters(
        provider=p_provider,
        pos_repo=f".*({pos_repo}).*" if pos_repo else None,
        neg_repo=f".*({neg_repo}).*" if neg_repo else None,
        pos_author=f".*({pos_author}).*" if pos_author else None,
        neg_author=f".*({neg_author}).*" if neg_author else None,
        time_from=time_range[0],
        time_to=time_range[1],
        granularity=granularity or 'week',
    )


@st.cache_resource
def get_connection():
    return duckdb.connect("data/git.duckdb", read_only=True)
