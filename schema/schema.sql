--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


    provider uuid NOT NULL,
    is_duplicate boolean DEFAULT false NOT NULL
    old_file_mode text,
    new_file_mode text
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL,
    additions integer,
    deletions integer
    ADD CONSTRAINT commit_stats_pkey PRIMARY KEY (repo_id, file_path, commit_hash);
--
-- Name: repos_is_duplicate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repos_is_duplicate ON public.repos USING btree (is_duplicate);


REVOKE USAGE ON SCHEMA public FROM PUBLIC;