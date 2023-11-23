CREATE FUNCTION mergestat.update_repo_import_default_container_images(repo_import_id uuid, default_container_image_ids uuid[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    
    -- update the repo import by replacing the defaultContainerImages element from the settings object
    UPDATE mergestat.repo_imports SET settings = settings - 'defaultContainerImages' || jsonb_build_object('defaultContainerImages', default_container_image_ids)
    WHERE id = repo_import_id;
    
    RETURN TRUE;
    
END; $$;


