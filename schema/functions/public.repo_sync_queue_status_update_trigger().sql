CREATE FUNCTION public.repo_sync_queue_status_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF NEW.status = 'RUNNING' AND OLD.status = 'QUEUED' THEN
		NEW.started_at = now();
	ELSEIF NEW.status = 'DONE' AND OLD.status = 'RUNNING' THEN
		NEW.done_at = now();
	END IF;
	RETURN NEW;
END;
$$;


