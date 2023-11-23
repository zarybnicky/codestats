CREATE FUNCTION mergestat.update_repo_import_default_container_images(repo_import_id uuid, default_container_image_ids uuid[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN


