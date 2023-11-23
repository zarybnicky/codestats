CREATE TABLE mergestat.service_auth_credential_types (
    type text NOT NULL,
    description text NOT NULL
);

GRANT ALL ON TABLE mergestat.service_auth_credential_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO readaccess;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.service_auth_credential_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.service_auth_credential_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.service_auth_credential_types
    ADD CONSTRAINT service_auth_credential_types_pkey PRIMARY KEY (type);

