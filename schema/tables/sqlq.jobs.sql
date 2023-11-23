CREATE TABLE sqlq.jobs (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    queue text NOT NULL,
    typename text NOT NULL,
    status sqlq.job_states DEFAULT 'pending'::sqlq.job_states NOT NULL,
    priority integer DEFAULT 10 NOT NULL,
    parameters jsonb,
    result jsonb,
    max_retries integer DEFAULT 1,
    attempt integer DEFAULT 0,
    last_queued_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    keepalive_interval bigint DEFAULT ((30)::numeric * '1000000000'::numeric) NOT NULL,
    last_keepalive timestamp with time zone,
    run_after bigint DEFAULT 0,
    retention_ttl bigint DEFAULT 0 NOT NULL
);

GRANT ALL ON TABLE sqlq.jobs TO mergestat_admin WITH GRANT OPTION;
GRANT ALL ON TABLE sqlq.jobs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sqlq.jobs TO mergestat_role_user;
GRANT SELECT ON TABLE sqlq.jobs TO mergestat_role_readonly;
GRANT SELECT ON TABLE sqlq.jobs TO mergestat_role_demo;
GRANT SELECT ON TABLE sqlq.jobs TO mergestat_role_queries_only;

ALTER TABLE ONLY sqlq.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY sqlq.jobs
    ADD CONSTRAINT jobs_queue_fkey FOREIGN KEY (queue) REFERENCES sqlq.queues(name) ON DELETE CASCADE;

CREATE INDEX ix_jobs_queue_type_status ON sqlq.jobs USING btree (queue, typename, status);