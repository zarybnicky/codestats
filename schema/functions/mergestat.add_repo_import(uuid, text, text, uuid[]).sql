CREATE FUNCTION mergestat.add_repo_import(provider_id uuid, import_type text, import_type_name text, default_container_image_ids uuid[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE 
    vendor_type TEXT;
    settings JSONB;
BEGIN


