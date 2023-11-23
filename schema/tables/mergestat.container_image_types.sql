CREATE TABLE mergestat.container_image_types (
    name text NOT NULL,
    display_name text NOT NULL,
    description text
);

GRANT SELECT ON TABLE mergestat.container_image_types TO readaccess;
GRANT ALL ON TABLE mergestat.container_image_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_image_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_image_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_image_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_image_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_image_types TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.container_image_types
    ADD CONSTRAINT container_image_types_pkey PRIMARY KEY (name);

