CREATE FUNCTION mergestat.add_repo_import(provider_id uuid, import_type text, import_type_name text, default_container_image_ids uuid[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE 
    vendor_type TEXT;
    settings JSONB;
BEGIN
    
    -- get the vendor type
    SELECT vendor
    INTO
    vendor_type
    FROM mergestat.providers
    WHERE id = provider_id;
    
    -- set the settings by vendor
    SELECT 
        CASE
            WHEN vendor_type = 'github'
                THEN jsonb_build_object('type', import_type) || jsonb_build_object('userOrOrg', import_type_name) || jsonb_build_object('defaultContainerImages', default_container_image_ids)
            WHEN vendor_type = 'gitlab'
                THEN jsonb_build_object('type', import_type) || jsonb_build_object('userOrGroup', import_type_name) || jsonb_build_object('defaultContainerImages', default_container_image_ids)
            WHEN vendor_type = 'bitbucket' 
                THEN jsonb_build_object('owner', import_type_name) || jsonb_build_object('defaultContainerImages', default_container_image_ids)
            ELSE '{}'::JSONB
        END 
    INTO
    settings;

    -- add the repo import
    INSERT INTO mergestat.repo_imports (settings, provider) values (settings, provider_id);
    
    RETURN TRUE;
    
END; $$;

SET default_tablespace = '';

SET default_table_access_method = heap;


