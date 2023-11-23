CREATE TABLE mergestat.container_images (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    type text DEFAULT 'docker'::text NOT NULL,
    url text NOT NULL,
    version text DEFAULT 'latest'::text NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    description text,
    queue text DEFAULT 'default'::text NOT NULL
);

GRANT SELECT ON TABLE mergestat.container_images TO readaccess;
GRANT ALL ON TABLE mergestat.container_images TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_images TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_images TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_images TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_images TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_images TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT container_images_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT unique_container_images_name UNIQUE (name);
ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT unique_container_images_url UNIQUE (url);
ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT fk_container_image_type FOREIGN KEY (type) REFERENCES mergestat.container_image_types(name);

