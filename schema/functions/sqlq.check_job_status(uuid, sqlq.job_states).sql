CREATE FUNCTION sqlq.check_job_status(job_id uuid, state sqlq.job_states) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (SELECT COUNT(*) FROM sqlq.jobs WHERE id = job_id AND status = state) THEN 
       RETURN TRUE;
    ELSE
       RETURN FALSE;
    END IF;
END;
$$;


