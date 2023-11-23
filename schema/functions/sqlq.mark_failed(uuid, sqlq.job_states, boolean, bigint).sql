CREATE FUNCTION sqlq.mark_failed(id uuid, expectedstate sqlq.job_states, retry boolean DEFAULT false, run_after bigint DEFAULT 0) RETURNS SETOF sqlq.jobs
    LANGUAGE plpgsql
    AS $_$
BEGIN
    IF retry THEN
        RETURN QUERY
            UPDATE sqlq.jobs SET status = 'pending', last_queued_at = NOW(), run_after = $4
                WHERE jobs.id = $1 AND status = $2 RETURNING *;
    ELSE
        RETURN QUERY
            UPDATE sqlq.jobs SET status = 'errored', completed_at = NOW()
                WHERE jobs.id = $1 AND status = $2 RETURNING *;
    END IF;
END;
$_$;


