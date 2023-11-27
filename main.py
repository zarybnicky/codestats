#!/usr/bin/env python3

from io import StringIO
import os
import subprocess

import streamlit as st
import pandas as pd

conn = st.connection("sql", url=os.environ["SQLALCHEMY_DATABASE_URL"])


def fetch_gitolite():
    host = os.environ["GITOLITE_HOST"]
    root_dir = os.environ["GITOLITE_ROOT_DIR"]
    st.write("Getting list of repos")
    result = subprocess.run(
        ['bash', '-c', f'ssh "{host}" 2>/dev/null | tail -n +3 | cut -b6-'],
        stdout=subprocess.PIPE
    )

    df = pd.DataFrame(result.stdout.decode('utf-8').splitlines(), columns=['repo'])
    df.insert(0, 'provider', conn.query("select id from mergestat.providers where name='Gitolite'")['id'][0])

    st.write("Inserting into the database")
    with conn.session as sess:
        s_buf = StringIO()
        df.to_csv(s_buf, sep=",", index=False, header=False)
        s_buf.seek(0)
        cursor = sess.connection().connection.cursor()
        cursor.execute("CREATE TEMP TABLE tmp_table (LIKE repos INCLUDING DEFAULTS) on commit drop")
        cursor.copy_expert("COPY tmp_table (provider, repo) FROM STDIN WITH (FORMAT CSV, delimiter ',')", s_buf)
        cursor.execute("INSERT INTO public.repos SELECT * FROM tmp_table ON CONFLICT DO NOTHING")
        sess.commit()


def fetch_gitlab():
    host = os.environ["GITLAB_HOST"]
    user = os.environ["GITLAB_USER"]
    token = os.environ["GITLAB_TOKEN"]
    root_dir = os.environ["GITLAB_ROOT_DIR"]


if st.button("Refresh Gitolite"):
    with st.status("Refreshing...", expanded=True) as status:
        fetch_gitolite()
        status.update(label="Done!", state="complete", expanded=False)
if st.button("Refresh Gitlab"):
    with st.spinner("Refreshing..."):
        fetch_gitlab()

df = conn.query("select * from mergestat.providers", ttl=0)
st.dataframe(df)

df = conn.query("select * from public.repos", ttl=0)
st.dataframe(df)
