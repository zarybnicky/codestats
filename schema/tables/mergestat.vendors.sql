CREATE TABLE mergestat.vendors (
    name text NOT NULL,
    display_name text NOT NULL,
    description text,
    type text NOT NULL
);

GRANT SELECT ON TABLE mergestat.vendors TO readaccess;
GRANT ALL ON TABLE mergestat.vendors TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.vendors TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.vendors TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.vendors TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.vendors TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.vendors TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (name);
ALTER TABLE ONLY mergestat.vendors
    ADD CONSTRAINT fk_vendors_type FOREIGN KEY (type) REFERENCES mergestat.vendor_types(name);

