CREATE FUNCTION sqlq.reap(queues text[]) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
    jobs UUID[];
    count INTEGER;
BEGIN
    WITH dead AS (SELECT id, attempt, max_retries
                  FROM sqlq.jobs
                  WHERE status = 'running'
                    AND (ARRAY_LENGTH($1, 1) IS NULL OR queue = ANY ($1))
                    AND (NOW() > last_keepalive + make_interval(secs => keepalive_interval / 1e9))),
         reaped AS (
             UPDATE sqlq.jobs
                 SET status = (CASE
                                   WHEN dead.attempt < dead.max_retries THEN 'pending'::sqlq.job_states
                                   ELSE 'errored'::sqlq.job_states END),
                     completed_at = NOW()
                 FROM dead WHERE jobs.id = dead.id
                 RETURNING jobs.id)
    SELECT ARRAY_AGG(id) INTO jobs FROM reaped;

    -- emit a log line
    INSERT INTO sqlq.job_logs(job, level, message)
    SELECT u.id, 'warn'::sqlq.log_level, 'job has timed out and is now marked as errored'
    FROM UNNEST(jobs) u(id);

    SELECT array_length(jobs, 1) INTO count FROM unnest(jobs) u(id);
    RETURN count;
END;
$_$;


