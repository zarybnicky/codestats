CREATE FUNCTION mergestat.enable_container_sync(repo_id_param uuid, container_image_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    container_sync_id UUID;
BEGIN

    INSERT INTO mergestat.container_syncs (repo_id, image_id) VALUES (repo_id_param, container_image_id)
        ON CONFLICT (repo_id, image_id) DO UPDATE SET repo_id = EXCLUDED.repo_id, image_id = EXCLUDED.image_id
        RETURNING id INTO container_sync_id;
    
    INSERT INTO mergestat.container_sync_schedules (sync_id) VALUES (container_sync_id) ON CONFLICT DO NOTHING;
    
    PERFORM mergestat.sync_now(container_sync_id);
    
    RETURN TRUE;
    
END; $$;


