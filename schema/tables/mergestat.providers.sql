CREATE TABLE mergestat.providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    vendor text NOT NULL,
    settings jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    description text
);

GRANT SELECT ON TABLE mergestat.providers TO readaccess;
GRANT ALL ON TABLE mergestat.providers TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.providers TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.providers TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.providers TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.providers TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.providers TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.providers
    ADD CONSTRAINT uq_providers_name UNIQUE (name);
ALTER TABLE ONLY mergestat.providers
    ADD CONSTRAINT fk_vendors_providers_vendor FOREIGN KEY (vendor) REFERENCES mergestat.vendors(name);

