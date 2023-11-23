CREATE TABLE mergestat.service_auth_credentials (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    type text NOT NULL,
    credentials bytea,
    provider uuid NOT NULL,
    is_default boolean DEFAULT false,
    username bytea
);

GRANT ALL ON TABLE mergestat.service_auth_credentials TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO readaccess;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.service_auth_credentials TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.service_auth_credentials TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.service_auth_credentials
    ADD CONSTRAINT service_auth_credentials_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.service_auth_credentials
    ADD CONSTRAINT fk_providers_credentials_provider FOREIGN KEY (provider) REFERENCES mergestat.providers(id) ON DELETE CASCADE;
ALTER TABLE ONLY mergestat.service_auth_credentials
    ADD CONSTRAINT service_auth_credentials_type_fkey FOREIGN KEY (type) REFERENCES mergestat.service_auth_credential_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;

CREATE UNIQUE INDEX ix_single_default_per_provider ON mergestat.service_auth_credentials USING btree (provider, is_default) WHERE (is_default = true);