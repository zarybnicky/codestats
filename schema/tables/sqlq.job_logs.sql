CREATE TABLE sqlq.job_logs (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    job uuid DEFAULT public.gen_random_uuid() NOT NULL,
    logged_at timestamp with time zone DEFAULT now(),
    level sqlq.log_level,
    message text,
    "position" smallint DEFAULT nextval('sqlq.job_log_ordering'::regclass) NOT NULL
);

GRANT ALL ON TABLE sqlq.job_logs TO mergestat_admin WITH GRANT OPTION;
GRANT ALL ON TABLE sqlq.job_logs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sqlq.job_logs TO mergestat_role_user;
GRANT SELECT ON TABLE sqlq.job_logs TO mergestat_role_readonly;
GRANT SELECT ON TABLE sqlq.job_logs TO mergestat_role_demo;
GRANT SELECT ON TABLE sqlq.job_logs TO mergestat_role_queries_only;

ALTER TABLE ONLY sqlq.job_logs
    ADD CONSTRAINT job_logs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY sqlq.job_logs
    ADD CONSTRAINT job_logs_job_fkey FOREIGN KEY (job) REFERENCES sqlq.jobs(id) ON DELETE CASCADE;

CREATE INDEX ix_job_logs_job_level ON sqlq.job_logs USING btree (job, level);
CREATE INDEX ix_logs_job ON sqlq.job_logs USING btree (job);