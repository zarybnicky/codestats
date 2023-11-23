CREATE TABLE sqlq.queues (
    name text NOT NULL,
    description text,
    concurrency integer DEFAULT 1,
    priority integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

GRANT ALL ON TABLE sqlq.queues TO mergestat_admin WITH GRANT OPTION;
GRANT ALL ON TABLE sqlq.queues TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sqlq.queues TO mergestat_role_user;
GRANT SELECT ON TABLE sqlq.queues TO mergestat_role_readonly;
GRANT SELECT ON TABLE sqlq.queues TO mergestat_role_demo;
GRANT SELECT ON TABLE sqlq.queues TO mergestat_role_queries_only;

ALTER TABLE ONLY sqlq.queues
    ADD CONSTRAINT queues_pkey PRIMARY KEY (name);

