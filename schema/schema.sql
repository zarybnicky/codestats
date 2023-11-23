--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4
-- Dumped by pg_dump version 15.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: mergestat; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA mergestat;


--
-- Name: sqlq; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA sqlq;


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: job_states; Type: TYPE; Schema: sqlq; Owner: -
--

CREATE TYPE sqlq.job_states AS ENUM (
    'pending',
    'running',
    'success',
    'errored',
    'cancelling',
    'cancelled'
);


--
-- Name: log_level; Type: TYPE; Schema: sqlq; Owner: -
--

CREATE TYPE sqlq.log_level AS ENUM (
    'debug',
    'info',
    'warn',
    'error'
);


--
-- Name: add_repo_import(uuid, text, text, uuid[]); Type: FUNCTION; Schema: mergestat; Owner: -
--

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

--
-- Name: service_auth_credentials; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.service_auth_credentials (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    type text NOT NULL,
    credentials bytea,
    provider uuid NOT NULL,
    is_default boolean DEFAULT false,
    username bytea
);


--
-- Name: add_service_auth_credential(text, text, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.add_service_auth_credential(credential_type text, credentials text, secret text) RETURNS mergestat.service_auth_credentials
    LANGUAGE plpgsql
    AS $$
DECLARE _inserted_row mergestat.SERVICE_AUTH_CREDENTIALS;
BEGIN
  INSERT INTO mergestat.service_auth_credentials (type, credentials) VALUES (credential_type, pgp_sym_encrypt(credentials, secret)) RETURNING * INTO _inserted_row;
  RAISE NOTICE 'INSERT INTO mergestat.service_auth_credentials by user(%), type(%s), id(%s)', user, credential_type, _inserted_row.id;
  RETURN(_inserted_row);
END;
$$;


--
-- Name: add_service_auth_credential(uuid, text, text, text, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.add_service_auth_credential(provider_id uuid, credential_type text, username text, token text, secret text) RETURNS mergestat.service_auth_credentials
    LANGUAGE plpgsql
    AS $$
DECLARE _inserted_row mergestat.service_auth_credentials;
BEGIN
    INSERT INTO mergestat.service_auth_credentials (provider, type, username, credentials)
        VALUES (provider_id, credential_type, pgp_sym_encrypt(username, secret), pgp_sym_encrypt(token, secret)) RETURNING * INTO _inserted_row;

    RETURN _inserted_row;
END;
$$;


--
-- Name: sync_variables; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.sync_variables (
    repo_id uuid NOT NULL,
    key public.citext NOT NULL,
    value bytea
);


--
-- Name: add_sync_variable(uuid, text, text, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.add_sync_variable(repo_id uuid, key text, value text, secret text) RETURNS mergestat.sync_variables
    LANGUAGE plpgsql
    AS $$
DECLARE _inserted_row mergestat.sync_variables;
BEGIN
    INSERT INTO mergestat.sync_variables(repo_id, key, value)
        VALUES (repo_id, key, pgp_sym_encrypt(value, secret)) RETURNING * INTO _inserted_row;

    RETURN _inserted_row;
END;
$$;


--
-- Name: container_syncs; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.container_syncs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    repo_id uuid NOT NULL,
    image_id uuid NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: container_syncs_latest_sync_runs(mergestat.container_syncs); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.container_syncs_latest_sync_runs(container_syncs mergestat.container_syncs) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   response JSONB;
BEGIN
    WITH last_completed_syncs AS(
        SELECT
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.created_at,
            j.started_at,
            j.completed_at,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'warn') warning_count,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'error') error_count
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.id = container_syncs.id
        ORDER BY cs.id, j.created_at DESC
        LIMIT 15
    )
    SELECT 
        JSONB_OBJECT_AGG(job_id, TO_JSONB(t) - 'job_id')
    INTO response
    FROM (
        SELECT job_id, created_at, started_at, completed_at, ((EXTRACT('epoch' FROM completed_at)-EXTRACT('epoch' FROM started_at))*1000)::INTEGER AS duration_ms, status FROM last_completed_syncs    
    )t;

    RETURN response;
END; $$;


--
-- Name: enable_container_sync(uuid, uuid); Type: FUNCTION; Schema: mergestat; Owner: -
--

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


--
-- Name: fetch_service_auth_credential(uuid, text, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.fetch_service_auth_credential(provider_id uuid, credential_type text, secret text) RETURNS TABLE(id uuid, username text, token text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT c.id, pgp_sym_decrypt(c.username, secret), pgp_sym_decrypt(c.credentials, secret) AS token, c.created_at
        FROM mergestat.service_auth_credentials c
    WHERE c.provider = provider_id AND
        (credential_type IS NULL OR c.type = credential_type)
    ORDER BY is_default DESC, created_at DESC;
END;
$$;


--
-- Name: fetch_sync_variable(uuid, text, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.fetch_sync_variable(uuid, text, text) RETURNS TABLE(repo_id uuid, key text, value text)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY SELECT var.repo_id, var.key::text, pgp_sym_decrypt(var.value, $3)
        FROM mergestat.sync_variables var
    WHERE var.repo_id = $1 AND var.key = $2;
END;
$_$;


--
-- Name: get_repos_page_header_stats(); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.get_repos_page_header_stats() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   response JSONB;
BEGIN
    WITH last_completed_syncs AS(
        SELECT DISTINCT ON (cs.id) 
            cs.id AS sync_id,
            j.id AS job_id,
            j.status,
            j.completed_at, 
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'error') error_count
        FROM mergestat.container_sync_schedules css 
        INNER JOIN mergestat.container_syncs cs ON css.sync_id = cs.id
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE j.status NOT IN ('pending','running')
        ORDER BY cs.id, j.created_at DESC
    )
    SELECT 
        (ROW_TO_JSON(t)::JSONB)
    INTO response
    FROM (
        SELECT
            (SELECT COUNT(1) FROM public.repos) AS repo_count,
            (SELECT COUNT(1) FROM mergestat.container_sync_schedules) AS repo_sync_count,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE error_count > 0 OR status = 'errored') AS syncs_with_error_count
    )t;

    RETURN response;
END; $$;


--
-- Name: get_repos_syncs_by_status(uuid, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.get_repos_syncs_by_status(repo_id_param uuid, status_param text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   response JSONB;
BEGIN
    WITH last_completed_syncs AS(
        SELECT DISTINCT ON (cs.id) 
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.completed_at AS sync_last_completed_at,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'warn') warning_count,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'error') error_count
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.repo_id = repo_id_param AND j.status NOT IN ('pending','running')
        ORDER BY cs.id, j.created_at DESC
    ),
    current_syncs AS(
        SELECT DISTINCT ON (cs.id)
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.completed_at AS sync_last_completed_at
        FROM mergestat.container_syncs cs
        LEFT JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        LEFT JOIN mergestat.container_images ci ON cs.image_id = ci.id
        LEFT JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.repo_id = repo_id_param AND j.status IN ('pending','running')
        ORDER BY cs.id, j.created_at DESC
    ),
    selected_sync AS(
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'running' AS selection FROM current_syncs WHERE status = 'running'
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'pending' AS selection FROM current_syncs WHERE status = 'pending'
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'success' AS selection FROM last_completed_syncs WHERE status = 'success'
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'warning' AS selection FROM last_completed_syncs WHERE warning_count > 0
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'errored' AS selection FROM last_completed_syncs WHERE status = 'errored' OR error_count > 0
    )
    SELECT 
        JSONB_OBJECT_AGG(job_id, TO_JSONB(t) - 'job_id')
    INTO response
    FROM (
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at FROM selected_sync WHERE selection = status_param
    )t;

    RETURN response;
END; $$;


--
-- Name: repo_sync_queue; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_queue (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    repo_sync_id uuid NOT NULL,
    status text NOT NULL,
    started_at timestamp with time zone,
    done_at timestamp with time zone,
    last_keep_alive timestamp with time zone,
    priority integer DEFAULT 0 NOT NULL,
    type_group text DEFAULT 'DEFAULT'::text NOT NULL
);


--
-- Name: repo_sync_queue_has_error(mergestat.repo_sync_queue); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.repo_sync_queue_has_error(job mergestat.repo_sync_queue) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (SELECT * FROM mergestat.repo_sync_logs WHERE repo_sync_queue_id = job.id AND log_type = 'ERROR')
$$;


--
-- Name: set_current_timestamp_updated_at(); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


--
-- Name: set_sync_job_status(text, bigint); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.set_sync_job_status(new_status text, repo_sync_queue_id bigint) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE _repo_sync_id UUID;
BEGIN
    IF new_status = 'DONE' THEN
            WITH update_queue AS (
                UPDATE mergestat.repo_sync_queue SET "status" = new_status WHERE mergestat.repo_sync_queue.id = repo_sync_queue_id
                RETURNING *
            )
            UPDATE mergestat.repo_syncs set last_completed_repo_sync_queue_id = repo_sync_queue_id
            FROM update_queue
            WHERE mergestat.repo_syncs.id = update_queue.repo_sync_id
            RETURNING mergestat.repo_syncs.id INTO _repo_sync_id;
    ELSE    
            UPDATE mergestat.repo_sync_queue SET "status" = new_status WHERE mergestat.repo_sync_queue.id = repo_sync_queue_id
            RETURNING repo_sync_id INTO _repo_sync_id;
    END IF;
    
    RETURN _repo_sync_id;    
END;
$$;


--
-- Name: simple_repo_sync_queue_cleanup(integer); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.simple_repo_sync_queue_cleanup(days_to_retain_param integer DEFAULT 30) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare _rows_deleted INTEGER;
begin
    DELETE FROM mergestat.repo_sync_queue WHERE created_at < CURRENT_DATE - days_to_retain_param;
    GET DIAGNOSTICS _rows_deleted = ROW_COUNT;
    
    RETURN _rows_deleted;
end;
$$;


--
-- Name: simple_sqlq_cleanup(integer); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.simple_sqlq_cleanup(days_to_retain_param integer DEFAULT 30) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare _rows_deleted INTEGER;
begin
    DELETE FROM sqlq.jobs WHERE created_at < CURRENT_DATE - days_to_retain_param;
    GET DIAGNOSTICS _rows_deleted = ROW_COUNT;
    
    RETURN _rows_deleted;
end;
$$;


--
-- Name: sync_now(uuid); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.sync_now(container_sync_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE 
    queue_name TEXT;
    queue_concurrency INTEGER;
    queue_priority INTEGER;
    job_id UUID;
    is_sync_already_running BOOLEAN;
BEGIN
    --Check if a sync run is already queued
    WITH sync_running(id, queue, job, status) AS (
        SELECT DISTINCT ON (syncs.id) syncs.id, (image.queue || '-' || repo.provider) AS queue, exec.job_id, job.status,
            CASE WHEN image.queue = 'github' THEN 1 ELSE 0 END AS concurrency
            FROM mergestat.container_syncs syncs
                INNER JOIN mergestat.container_images image ON image.id = syncs.image_id
                INNER JOIN public.repos repo ON repo.id = syncs.repo_id
                LEFT OUTER JOIN mergestat.container_sync_executions exec ON exec.sync_id = syncs.id
                LEFT OUTER JOIN sqlq.jobs job ON job.id = exec.job_id
        WHERE syncs.id = container_sync_id
        ORDER BY syncs.id, exec.created_at DESC
    )
    SELECT CASE WHEN (SELECT COUNT(*) FROM sync_running WHERE status IN ('pending','running')) > 0 THEN TRUE ELSE FALSE END
    INTO is_sync_already_running;
    
    
    IF is_sync_already_running = FALSE
    THEN    
        --Get the queue name
        SELECT DISTINCT (ci.queue || '-' || r.provider)
        INTO queue_name
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_images ci ON ci.id = cs.image_id
        INNER JOIN public.repos r ON r.id = cs.repo_id
        WHERE cs.id = container_sync_id;
        
        --Get the queue concurrency
        SELECT DISTINCT CASE WHEN ci.queue = 'github' THEN 1 ELSE NULL END
        INTO queue_concurrency
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_images ci ON ci.id = cs.image_id
        INNER JOIN public.repos r ON r.id = cs.repo_id
        WHERE cs.id = container_sync_id;

        --Get the queue priority
        SELECT DISTINCT CASE WHEN ci.queue = 'github' THEN 1 ELSE 2 END
        INTO queue_priority
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_images ci ON ci.id = cs.image_id
        INNER JOIN public.repos r ON r.id = cs.repo_id
        WHERE cs.id = container_sync_id;
        
        --Add the queue if missing
        INSERT INTO sqlq.queues (name, concurrency, priority) VALUES (queue_name, queue_concurrency, queue_priority) ON CONFLICT (name) DO UPDATE SET concurrency = excluded.concurrency, priority = excluded.priority;
        
        --Add the job
        INSERT INTO sqlq.jobs (queue, typename, parameters, priority) VALUES (queue_name, 'container/sync', jsonb_build_object('ID', container_sync_id), 0) RETURNING id INTO job_id;
        
        --Add the container sync execution
        INSERT INTO mergestat.container_sync_executions (sync_id, job_id) VALUES (container_sync_id, job_id);
    END IF;
    
    RETURN TRUE;
    
END; $$;


--
-- Name: update_repo_import_default_container_images(uuid, uuid[]); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.update_repo_import_default_container_images(repo_import_id uuid, default_container_image_ids uuid[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    
    -- update the repo import by replacing the defaultContainerImages element from the settings object
    UPDATE mergestat.repo_imports SET settings = settings - 'defaultContainerImages' || jsonb_build_object('defaultContainerImages', default_container_image_ids)
    WHERE id = repo_import_id;
    
    RETURN TRUE;
    
END; $$;


--
-- Name: user_mgmt_add_user(name, text, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.user_mgmt_add_user(username name, password text, role text) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN
    -- Create the user with the given password
    EXECUTE FORMAT('CREATE USER %I WITH PASSWORD %L', username, password);
    EXECUTE FORMAT('GRANT %I TO mergestat_admin', username);
    EXECUTE FORMAT('GRANT %I TO readaccess', username);
    EXECUTE FORMAT('SELECT mergestat.user_mgmt_set_user_role(%L, %L)', username, role);
    RETURN 1;
END;
$$;


--
-- Name: user_mgmt_remove_user(name); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.user_mgmt_remove_user(username name) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN
    EXECUTE FORMAT('DROP USER IF EXISTS %I', username);
    RETURN 1;
END;
$$;


--
-- Name: user_mgmt_set_user_role(name, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.user_mgmt_set_user_role(username name, role text) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN
    -- first revoke all existing mergestat roles and CREATEROLE from the user
    EXECUTE FORMAT('REVOKE mergestat_role_demo FROM %I', username);
    EXECUTE FORMAT('REVOKE mergestat_role_readonly FROM %I', username);
    EXECUTE FORMAT('REVOKE mergestat_role_queries_only FROM %I', username);
    EXECUTE FORMAT('REVOKE mergestat_role_user FROM %I', username);
    EXECUTE FORMAT('REVOKE mergestat_role_admin FROM %I', username);    
    EXECUTE FORMAT('ALTER USER %I WITH NOCREATEROLE', username);
    CASE
        WHEN role = 'ADMIN' THEN
            EXECUTE FORMAT('GRANT mergestat_role_admin TO %I', username);
            EXECUTE FORMAT('ALTER USER %I WITH CREATEROLE', username);
        WHEN role = 'USER' THEN
            EXECUTE FORMAT('GRANT mergestat_role_user TO %I', username);
        WHEN role = 'QUERIES_ONLY' THEN
            EXECUTE FORMAT('GRANT mergestat_role_queries_only TO %I', username);
        WHEN role = 'READ_ONLY' THEN
            EXECUTE FORMAT('GRANT mergestat_role_readonly TO %I', username);
        WHEN role = 'DEMO' THEN
            EXECUTE FORMAT('GRANT mergestat_role_demo TO %I', username);
        ELSE
            RAISE EXCEPTION 'Invalid role %', role;
    END CASE;
    RETURN 1;
END;
$$;


--
-- Name: user_mgmt_update_user_password(name, text); Type: FUNCTION; Schema: mergestat; Owner: -
--

CREATE FUNCTION mergestat.user_mgmt_update_user_password(username name, password text) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN
    --Check if user has role of mergestat_role_demo and raise and error if they do
    IF EXISTS (
        SELECT 
            a.oid AS user_role_id
            , a.rolname AS user_role_name
            , b.roleid AS other_role_id
            , c.rolname AS other_role_name
        FROM pg_roles a
        INNER JOIN pg_auth_members b ON a.oid=b.member
        INNER JOIN pg_roles c ON b.roleid=c.oid 
        WHERE a.rolname = username AND c.rolname = 'mergestat_role_demo'
    )
    THEN RAISE EXCEPTION 'permission denied to change password';
    END IF;

    EXECUTE FORMAT('ALTER USER %I WITH PASSWORD %L', username, password);
    RETURN 1;
END;
$$;


--
-- Name: current_merge_stat_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_merge_stat_user() RETURNS name
    LANGUAGE sql STABLE
    AS $$ SELECT user $$;


--
-- Name: explore_ui(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.explore_ui(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   RESPONSE JSONB;
   RESPONSE_TYPE TEXT;
   FILE_PATH_PATTERN_PARAM TEXT;
   FILE_CONTENTS_PATTERN_PARAM TEXT;
   AUTHOR_NAME_PATTERN_PARAM TEXT;
   DAYS_SINCE_REPO_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_FILE_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_AUTHORED_LAST_PARAM INTEGER;
   DAYS_SINCE_NOT_AUTHORED_LAST_PARAM INTEGER;
   DAYS_SINCE_COMMITTED_LAST_PARAM INTEGER;
   DAYS_SINCE_NOT_COMMITTED_LAST_PARAM INTEGER;
   REPO_PATTERN_PARAM TEXT;
BEGIN
    SELECT COALESCE(params->>'RESPONSE_TYPE', 'DEFAULT') INTO RESPONSE_TYPE;
    SELECT params->>'file_path_pattern' INTO FILE_PATH_PATTERN_PARAM;
    SELECT params->>'file_contents_pattern' INTO FILE_CONTENTS_PATTERN_PARAM;
    SELECT params->>'author_name_pattern' INTO AUTHOR_NAME_PATTERN_PARAM;
    SELECT params->>'days_since_repo_modified_last' INTO DAYS_SINCE_REPO_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_repo_not_modified_last' INTO DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_file_modified_last' INTO DAYS_SINCE_FILE_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_file_not_modified_last' INTO DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_authored_last' INTO DAYS_SINCE_AUTHORED_LAST_PARAM;
    SELECT params->>'days_since_not_authored_last' INTO DAYS_SINCE_NOT_AUTHORED_LAST_PARAM;
    SELECT params->>'days_since_committed_last' INTO DAYS_SINCE_COMMITTED_LAST_PARAM;
    SELECT params->>'days_since_not_committed_last' INTO DAYS_SINCE_NOT_COMMITTED_LAST_PARAM;
    SELECT params->>'repo_pattern' INTO REPO_PATTERN_PARAM;

    WITH base_query AS (
        SELECT 
            repos.repo,
            git_files.path AS file_path,
            git_commits.author_when,
            git_commits.author_name,
            git_commits.committer_when,
            git_commits.committer_name,
            git_commits.hash,
            _mergestat_explore_repo_metadata.last_commit_committer_when AS repo_last_modified,
            _mergestat_explore_file_metadata.last_commit_committer_when AS file_last_modified
        FROM git_commits 
        INNER JOIN repos ON git_commits.repo_id = repos.id 
        INNER JOIN git_commit_stats ON git_commit_stats.repo_id = git_commits.repo_id AND git_commit_stats.commit_hash = git_commits.hash and parents < 2
        INNER JOIN git_files ON git_commit_stats.repo_id = git_files.repo_id AND git_commit_stats.file_path = git_files.path
        INNER JOIN _mergestat_explore_repo_metadata ON git_commits.repo_id = _mergestat_explore_repo_metadata.repo_id
        INNER JOIN _mergestat_explore_file_metadata ON git_commits.repo_id = _mergestat_explore_file_metadata.repo_id AND _mergestat_explore_file_metadata.path = git_files.path
        WHERE
            (FILE_PATH_PATTERN_PARAM IS NULL OR git_files.path LIKE FILE_PATH_PATTERN_PARAM)
            AND
            (FILE_CONTENTS_PATTERN_PARAM IS NULL OR git_files.contents LIKE FILE_CONTENTS_PATTERN_PARAM)
            AND
            (AUTHOR_NAME_PATTERN_PARAM IS NULL OR git_commits.author_name LIKE AUTHOR_NAME_PATTERN_PARAM)
            AND
            (REPO_PATTERN_PARAM IS NULL OR repos.repo LIKE REPO_PATTERN_PARAM)
            AND
            (DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_repo_metadata.last_commit_committer_when < NOW() - (DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_file_metadata.last_commit_committer_when < NOW() - (DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_NOT_AUTHORED_LAST_PARAM IS NULL OR git_commits.author_when < NOW() - (DAYS_SINCE_NOT_AUTHORED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_NOT_COMMITTED_LAST_PARAM IS NULL OR git_commits.committer_when < NOW() - (DAYS_SINCE_NOT_COMMITTED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_REPO_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_repo_metadata.last_commit_committer_when >= NOW() - (DAYS_SINCE_REPO_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_FILE_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_file_metadata.last_commit_committer_when >= NOW() - (DAYS_SINCE_FILE_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_AUTHORED_LAST_PARAM IS NULL OR git_commits.author_when >= NOW() - (DAYS_SINCE_AUTHORED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_COMMITTED_LAST_PARAM IS NULL OR git_commits.committer_when >= NOW() - (DAYS_SINCE_COMMITTED_LAST_PARAM || ' day')::INTERVAL)
    )
    SELECT
        CASE
        WHEN RESPONSE_TYPE = 'FILES'
            THEN (
                SELECT jsonb_agg(b) AS agg
                FROM (
                    SELECT DISTINCT
                        repo,
                        file_path,
                        file_last_modified
                    FROM base_query
                    ORDER BY 3 DESC
                    LIMIT 1001
                )b
            )
        WHEN RESPONSE_TYPE = 'REPOS'
            THEN (
                SELECT jsonb_agg(b) AS agg
                FROM (
                    SELECT
                        repo,
                        repo_last_modified,
                        COUNT(DISTINCT file_path) AS file_count 
                    FROM base_query
                    GROUP BY 1, 2
                    ORDER BY 3 DESC
                    LIMIT 1001
                )b
            )
        WHEN RESPONSE_TYPE = 'AUTHORS'
            THEN (
                SELECT jsonb_agg(b) AS agg
                FROM (
                    SELECT 
                        author_name,
                        COUNT(DISTINCT hash) AS commits_count 
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 2 DESC
                    LIMIT 1001
                )b
            )
        ELSE (
            jsonb_build_object('top_10_repos', (SELECT JSON_AGG(TO_JSONB(top_10_repos)) FROM (
                SELECT
                    base_query.repo,
                    providers.vendor,
                    providers.settings->>'url' AS vendor_url,
                    COUNT(DISTINCT file_path) AS file_count 
                FROM base_query
                INNER JOIN repos ON base_query.repo = repos.repo
                INNER JOIN mergestat.providers ON repos.provider = providers.id
                GROUP BY 1, 2, 3
                ORDER BY 4 DESC
                LIMIT 10
            )top_10_repos)) ||
            jsonb_build_object('top_10_authors', (SELECT JSON_AGG(TO_JSONB(top_10_authors)) FROM (
                SELECT 
                    author_name,
                    COUNT(DISTINCT hash) AS commits_count 
                FROM base_query
                GROUP BY 1
                ORDER BY 2 DESC
                LIMIT 10
            )top_10_authors)) ||
            jsonb_build_object('repo_last_modified', 
                jsonb_build_object('month', (SELECT JSON_AGG(TO_JSONB(repo_last_modified_by_year_month)) FROM (
                    SELECT
                        TO_CHAR(repo_last_modified, 'YYYY-MM') AS year_month,
                        COUNT(DISTINCT repo) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )repo_last_modified_by_year_month)) || 
                jsonb_build_object('year', (SELECT JSON_AGG(TO_JSONB(repo_last_modified_by_year)) FROM (
                    SELECT
                        TO_CHAR(repo_last_modified, 'YYYY') AS year,
                        COUNT(DISTINCT repo) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )repo_last_modified_by_year))) ||
            jsonb_build_object('file_last_modified', 
                jsonb_build_object('month', (SELECT JSON_AGG(TO_JSONB(file_last_modified_by_year_month)) FROM (
                    SELECT
                        TO_CHAR(file_last_modified, 'YYYY-MM') AS year_month,
                        COUNT(DISTINCT repo || file_path) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )file_last_modified_by_year_month)) || 
                jsonb_build_object('year', (SELECT JSON_AGG(TO_JSONB(file_last_modified_by_year)) FROM (
                    SELECT
                        TO_CHAR(file_last_modified, 'YYYY') AS year,
                        COUNT(DISTINCT repo || file_path) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )file_last_modified_by_year))) ||
            jsonb_build_object('repos', (SELECT COUNT(DISTINCT repo) AS count FROM base_query)) ||
            jsonb_build_object('files', (SELECT COUNT(DISTINCT repo || file_path) AS count FROM base_query)) ||
            jsonb_build_object('authors', (SELECT COUNT(DISTINCT author_name) AS count FROM base_query))
        )
        END
    INTO RESPONSE;
    
    RETURN RESPONSE;
END; $$;


--
-- Name: getfilesolderthan(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getfilesolderthan(file_pattern text, older_than_days integer) RETURNS TABLE(repo text, file_path text, author_when timestamp with time zone, author_name text, author_email text, hash text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH top_author_when AS (
        SELECT DISTINCT ON (repos.repo, git_commit_stats.file_path) repos.repo, git_commit_stats.file_path, git_commits.author_when, git_commits.author_name, git_commits.author_email, git_commits.hash
        FROM git_commits 
        INNER JOIN repos ON git_commits.repo_id = repos.id 
        INNER JOIN git_commit_stats ON git_commit_stats.repo_id = git_commits.repo_id AND git_commit_stats.commit_hash = git_commits.hash and parents < 2
        WHERE git_commit_stats.file_path LIKE file_pattern
        ORDER BY repos.repo, git_commit_stats.file_path, git_commits.author_when DESC
    )
    SELECT * FROM top_author_when
    WHERE top_author_when.author_when < NOW() - (older_than_days || ' day')::INTERVAL
    ORDER BY top_author_when.author_when DESC;
END
$$;


--
-- Name: jsonb_recursive_merge(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_recursive_merge(a jsonb, b jsonb) RETURNS jsonb
    LANGUAGE sql
    AS $$
SELECT
    jsonb_object_agg(
        coalesce(ka, kb),
        CASE
            WHEN va ISNULL THEN vb
            WHEN vb ISNULL THEN va
            WHEN jsonb_typeof(va) <> 'object' OR jsonb_typeof(vb) <> 'object' THEN vb
            ELSE jsonb_recursive_merge(va, vb) END
        )
    FROM jsonb_each(a) e1(ka, va)
    FULL JOIN jsonb_each(b) e2(kb, vb) ON ka = kb
$$;


--
-- Name: repo_sync_queue_status_update_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

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


--
-- Name: repos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.repos (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    repo text NOT NULL,
    ref text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    settings jsonb DEFAULT jsonb_build_object() NOT NULL,
    tags jsonb DEFAULT jsonb_build_array() NOT NULL,
    repo_import_id uuid,
    provider uuid NOT NULL
);


--
-- Name: TABLE repos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.repos IS 'git repositories to track';


--
-- Name: COLUMN repos.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.id IS 'MergeStat identifier for the repo';


--
-- Name: COLUMN repos.repo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.repo IS 'URL for the repo';


--
-- Name: COLUMN repos.ref; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.ref IS 'ref for the repo';


--
-- Name: COLUMN repos.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.created_at IS 'timestamp of when the MergeStat repo entry was created';


--
-- Name: COLUMN repos.settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.settings IS 'JSON settings for the repo';


--
-- Name: COLUMN repos.tags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.tags IS 'array of tags for the repo for topics in GitHub as well as tags added in MergeStat';


--
-- Name: COLUMN repos.repo_import_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.repos.repo_import_id IS 'foreign key for mergestat.repo_imports.id';


--
-- Name: repos_stats(public.repos); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.repos_stats(repos public.repos) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   response JSONB;
BEGIN
    WITH last_completed_syncs AS(
        SELECT DISTINCT ON (cs.id) 
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.completed_at AS sync_last_completed_at,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'warn') warning_count,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'error') error_count
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.repo_id = repos.id AND j.status NOT IN ('pending','running')
        ORDER BY cs.id, j.created_at DESC
    ),
    current_syncs AS(
        SELECT DISTINCT ON (cs.id)
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.completed_at AS sync_last_completed_at
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id AND j.status IN ('pending','running')
        WHERE cs.repo_id = repos.id
        ORDER BY cs.id, j.created_at DESC
    ),
    scheduled_syncs AS(
        SELECT COUNT(DISTINCT css.id) as sync_count
        FROM mergestat.container_sync_schedules css 
        INNER JOIN mergestat.container_syncs cs ON css.sync_id = cs.id
        WHERE cs.repo_id = repos.id
    )
    SELECT 
        (ROW_TO_JSON(t)::JSONB)
    INTO response
    FROM (
        SELECT
            (SELECT sync_count from scheduled_syncs) AS sync_count,
            (SELECT MAX(sync_last_completed_at) FROM last_completed_syncs) AS last_sync_time,
            (SELECT COUNT(1) FROM current_syncs WHERE status = 'running') AS running,
            (SELECT COUNT(1) FROM current_syncs WHERE status = 'pending') AS pending,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE status = 'errored' OR error_count > 0) AS error,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE status = 'success' AND error_count = 0 AND warning_count = 0) AS success,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE warning_count > 0 AND status = 'success' AND error_count = 0) AS warning
    )t;

    RETURN response;
END; $$;


--
-- Name: track_applied_migration(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.track_applied_migration() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE _current_version BIGINT;
BEGIN
    SELECT COALESCE(MAX(version),0) FROM public.schema_migrations_history INTO _current_version;
    IF new.dirty = false AND new.version > _current_version THEN
        INSERT INTO public.schema_migrations_history(version) VALUES (new.version);
    ELSE
        UPDATE public.schema_migrations SET version = (SELECT MAX(version) FROM public.schema_migrations_history), dirty = false;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: cancelling_job(uuid); Type: FUNCTION; Schema: sqlq; Owner: -
--

CREATE FUNCTION sqlq.cancelling_job(job_id uuid) RETURNS sqlq.job_states
    LANGUAGE sql
    AS $$
  UPDATE sqlq.jobs 
        SET status = 'cancelling'
   WHERE id = job_id AND status = 'running' OR status ='pending'
        RETURNING status;
$$;


--
-- Name: check_job_status(uuid, sqlq.job_states); Type: FUNCTION; Schema: sqlq; Owner: -
--

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


--
-- Name: jobs; Type: TABLE; Schema: sqlq; Owner: -
--

CREATE TABLE sqlq.jobs (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    queue text NOT NULL,
    typename text NOT NULL,
    status sqlq.job_states DEFAULT 'pending'::sqlq.job_states NOT NULL,
    priority integer DEFAULT 10 NOT NULL,
    parameters jsonb,
    result jsonb,
    max_retries integer DEFAULT 1,
    attempt integer DEFAULT 0,
    last_queued_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    keepalive_interval bigint DEFAULT ((30)::numeric * '1000000000'::numeric) NOT NULL,
    last_keepalive timestamp with time zone,
    run_after bigint DEFAULT 0,
    retention_ttl bigint DEFAULT 0 NOT NULL
);


--
-- Name: dequeue_job(text[], text[]); Type: FUNCTION; Schema: sqlq; Owner: -
--

CREATE FUNCTION sqlq.dequeue_job(queues text[], jobtypes text[]) RETURNS SETOF sqlq.jobs
    LANGUAGE sql
    AS $_$
WITH queues AS (
    SELECT name, concurrency, priority FROM sqlq.queues WHERE (ARRAY_LENGTH($1, 1) IS NULL OR name = ANY($1))
), running (name, count) AS (
    SELECT queue, COUNT(*) FROM sqlq.jobs, queues
    WHERE jobs.queue = queues.name AND status = 'running'
    GROUP BY queue
), queue_with_capacity AS (
    SELECT queues.name, queues.priority FROM queues LEFT OUTER JOIN running USING(name)
    WHERE (concurrency IS NULL OR (concurrency - COALESCE(running.count, 0) > 0))
), dequeued(id) AS (
    SELECT job.id FROM sqlq.jobs job, queue_with_capacity q
    WHERE job.status = 'pending'
      AND (job.last_queued_at+make_interval(secs => job.run_after/1e9)) <= NOW() -- value in run_after is stored as nanoseconds
      AND job.queue = q.name
      AND (ARRAY_LENGTH($2, 1) IS NULL OR job.typename = ANY($2))
    ORDER BY q.priority ASC, job.priority ASC, job.created_at ASC
    LIMIT 1
)
UPDATE sqlq.jobs
SET status = 'running', started_at = NOW(), last_keepalive = NOW(), attempt = attempt + 1
FROM dequeued dq
WHERE jobs.id = dq.id
RETURNING jobs.*
$_$;


--
-- Name: mark_failed(uuid, sqlq.job_states, boolean, bigint); Type: FUNCTION; Schema: sqlq; Owner: -
--

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


--
-- Name: mark_success(uuid, sqlq.job_states); Type: FUNCTION; Schema: sqlq; Owner: -
--

CREATE FUNCTION sqlq.mark_success(id uuid, expectedstate sqlq.job_states) RETURNS SETOF sqlq.jobs
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY UPDATE sqlq.jobs SET status = 'success', completed_at = NOW()
        WHERE jobs.id = $1 AND status = $2
    RETURNING *;
END;
$_$;


--
-- Name: reap(text[]); Type: FUNCTION; Schema: sqlq; Owner: -
--

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


--
-- Name: container_image_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.container_image_types (
    name text NOT NULL,
    display_name text NOT NULL,
    description text
);


--
-- Name: container_images; Type: TABLE; Schema: mergestat; Owner: -
--

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


--
-- Name: container_sync_executions; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.container_sync_executions (
    sync_id uuid NOT NULL,
    job_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: container_sync_schedules; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.container_sync_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sync_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: latest_repo_syncs; Type: VIEW; Schema: mergestat; Owner: -
--

CREATE VIEW mergestat.latest_repo_syncs AS
 SELECT DISTINCT ON (repo_sync_queue.repo_sync_id) repo_sync_queue.id,
    repo_sync_queue.created_at,
    repo_sync_queue.repo_sync_id,
    repo_sync_queue.status,
    repo_sync_queue.started_at,
    repo_sync_queue.done_at
   FROM mergestat.repo_sync_queue
  WHERE (repo_sync_queue.status = 'DONE'::text)
  ORDER BY repo_sync_queue.repo_sync_id, repo_sync_queue.created_at DESC;


--
-- Name: providers; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    vendor text NOT NULL,
    settings jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    description text
);


--
-- Name: query_history; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.query_history (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    run_at timestamp with time zone DEFAULT now(),
    run_by text NOT NULL,
    query text NOT NULL
);


--
-- Name: repo_import_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_import_types (
    type text NOT NULL,
    description text NOT NULL
);


--
-- Name: TABLE repo_import_types; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TABLE mergestat.repo_import_types IS 'Types of repo imports';


--
-- Name: repo_imports; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_imports (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    settings jsonb DEFAULT jsonb_build_object() NOT NULL,
    last_import timestamp with time zone,
    import_interval interval DEFAULT '00:30:00'::interval,
    last_import_started_at timestamp with time zone,
    import_status text,
    import_error text,
    provider uuid NOT NULL,
    CONSTRAINT repo_imports_import_interval_check CHECK ((import_interval > '00:00:30'::interval))
);


--
-- Name: TABLE repo_imports; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TABLE mergestat.repo_imports IS 'Table for "dynamic" repo imports - regularly loading from a GitHub org for example';


--
-- Name: repo_sync_log_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_log_types (
    type text NOT NULL,
    description text
);


--
-- Name: repo_sync_logs; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_logs (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    log_type text NOT NULL,
    message text NOT NULL,
    repo_sync_queue_id bigint NOT NULL
);


--
-- Name: repo_sync_logs_id_seq; Type: SEQUENCE; Schema: mergestat; Owner: -
--

CREATE SEQUENCE mergestat.repo_sync_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: repo_sync_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: mergestat; Owner: -
--

ALTER SEQUENCE mergestat.repo_sync_logs_id_seq OWNED BY mergestat.repo_sync_logs.id;


--
-- Name: repo_sync_queue_id_seq; Type: SEQUENCE; Schema: mergestat; Owner: -
--

CREATE SEQUENCE mergestat.repo_sync_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: repo_sync_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: mergestat; Owner: -
--

ALTER SEQUENCE mergestat.repo_sync_queue_id_seq OWNED BY mergestat.repo_sync_queue.id;


--
-- Name: repo_sync_queue_status_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_queue_status_types (
    type text NOT NULL,
    description text
);


--
-- Name: repo_sync_type_groups; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_type_groups (
    "group" text NOT NULL,
    concurrent_syncs integer
);


--
-- Name: repo_sync_type_label_associations; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_type_label_associations (
    label text NOT NULL,
    repo_sync_type text NOT NULL
);


--
-- Name: TABLE repo_sync_type_label_associations; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TABLE mergestat.repo_sync_type_label_associations IS '@name labelAssociations';


--
-- Name: repo_sync_type_labels; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_type_labels (
    label text NOT NULL,
    description text,
    color text DEFAULT '#dddddd'::text NOT NULL,
    CONSTRAINT repo_sync_type_labels_color_check CHECK (((color IS NULL) OR (color ~* '^#[a-f0-9]{2}[a-f0-9]{2}[a-f0-9]{2}$'::text)))
);


--
-- Name: TABLE repo_sync_type_labels; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TABLE mergestat.repo_sync_type_labels IS '@name labels';


--
-- Name: repo_sync_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_sync_types (
    type text NOT NULL,
    description text,
    short_name text DEFAULT ''::text NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    type_group text DEFAULT 'DEFAULT'::text NOT NULL
);


--
-- Name: repo_syncs; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.repo_syncs (
    repo_id uuid NOT NULL,
    sync_type text NOT NULL,
    settings jsonb DEFAULT jsonb_build_object() NOT NULL,
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    schedule_enabled boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    last_completed_repo_sync_queue_id bigint
);


--
-- Name: saved_explores; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.saved_explores (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_by text,
    created_at timestamp with time zone,
    name text,
    description text,
    metadata jsonb
);


--
-- Name: TABLE saved_explores; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TABLE mergestat.saved_explores IS 'Table to save explores';


--
-- Name: COLUMN saved_explores.created_by; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_explores.created_by IS 'explore creator';


--
-- Name: COLUMN saved_explores.created_at; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_explores.created_at IS 'timestamp when explore was created';


--
-- Name: COLUMN saved_explores.name; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_explores.name IS 'explore name';


--
-- Name: COLUMN saved_explores.description; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_explores.description IS 'explore description';


--
-- Name: COLUMN saved_explores.metadata; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_explores.metadata IS 'explore metadata';


--
-- Name: saved_queries; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.saved_queries (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_by text,
    created_at timestamp with time zone,
    name text NOT NULL,
    description text,
    sql text NOT NULL,
    metadata jsonb
);


--
-- Name: TABLE saved_queries; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TABLE mergestat.saved_queries IS 'Table to save queries';


--
-- Name: COLUMN saved_queries.created_by; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_queries.created_by IS 'query creator';


--
-- Name: COLUMN saved_queries.created_at; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_queries.created_at IS 'timestamp when query was created';


--
-- Name: COLUMN saved_queries.name; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_queries.name IS 'query name';


--
-- Name: COLUMN saved_queries.description; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_queries.description IS 'query description';


--
-- Name: COLUMN saved_queries.sql; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_queries.sql IS 'query sql';


--
-- Name: COLUMN saved_queries.metadata; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON COLUMN mergestat.saved_queries.metadata IS 'query metadata';


--
-- Name: schema_introspection; Type: VIEW; Schema: mergestat; Owner: -
--

CREATE VIEW mergestat.schema_introspection AS
 SELECT t.table_schema AS schema,
    t.table_name,
    t.table_type,
    c.column_name,
    c.ordinal_position,
    c.is_nullable,
    c.data_type,
    c.udt_name,
    col_description(((format('%s.%s'::text, c.table_schema, c.table_name))::regclass)::oid, (c.ordinal_position)::integer) AS column_description
   FROM (information_schema.tables t
     JOIN information_schema.columns c ON ((((t.table_name)::name = (c.table_name)::name) AND ((t.table_schema)::name = (c.table_schema)::name))))
  WHERE (((t.table_schema)::name = ANY (ARRAY['public'::name, 'mergestat'::name, 'sqlq'::name])) AND ((t.table_name)::name !~~ 'g\_%'::text) AND ((t.table_name)::name !~~ 'google\_%'::text) AND ((t.table_name)::name !~~ 'hypopg\_%'::text))
  ORDER BY (array_position(ARRAY['public'::text, 'mergestat'::text, 'sqlq'::text], (t.table_schema)::text)), t.table_name, c.column_name;


--
-- Name: service_auth_credential_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.service_auth_credential_types (
    type text NOT NULL,
    description text NOT NULL
);


--
-- Name: user_mgmt_pg_users; Type: VIEW; Schema: mergestat; Owner: -
--

CREATE VIEW mergestat.user_mgmt_pg_users AS
 WITH users AS (
         SELECT r.rolname,
            r.rolsuper,
            r.rolinherit,
            r.rolcreaterole,
            r.rolcreatedb,
            r.rolcanlogin,
            r.rolconnlimit,
            r.rolvaliduntil,
            r.rolreplication,
            r.rolbypassrls,
            ARRAY( SELECT b.rolname
                   FROM (pg_auth_members m
                     JOIN pg_roles b ON ((m.roleid = b.oid)))
                  WHERE (m.member = r.oid)) AS memberof
           FROM pg_roles r
          WHERE ((r.rolname !~ '^pg_'::text) AND r.rolcanlogin)
          ORDER BY r.rolname
        )
 SELECT users.rolname,
    users.rolsuper,
    users.rolinherit,
    users.rolcreaterole,
    users.rolcreatedb,
    users.rolcanlogin,
    users.rolconnlimit,
    users.rolvaliduntil,
    users.rolreplication,
    users.rolbypassrls,
    users.memberof
   FROM users
  WHERE ((users.memberof && ARRAY['mergestat_role_admin'::name, 'mergestat_role_user'::name, 'mergestat_role_queries_only'::name, 'mergestat_role_readonly'::name]) AND (users.rolname <> 'mergestat_admin'::name));


--
-- Name: vendor_types; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.vendor_types (
    name text NOT NULL,
    display_name text NOT NULL,
    description text
);


--
-- Name: vendors; Type: TABLE; Schema: mergestat; Owner: -
--

CREATE TABLE mergestat.vendors (
    name text NOT NULL,
    display_name text NOT NULL,
    description text,
    type text NOT NULL
);


--
-- Name: _mergestat_explore_file_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._mergestat_explore_file_metadata (
    repo_id uuid NOT NULL,
    path text NOT NULL,
    last_commit_hash text,
    last_commit_message text,
    last_commit_author_name text,
    last_commit_author_email text,
    last_commit_author_when timestamp with time zone,
    last_commit_committer_name text,
    last_commit_committer_email text,
    last_commit_committer_when timestamp with time zone,
    last_commit_parents integer,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE _mergestat_explore_file_metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public._mergestat_explore_file_metadata IS 'file metadata for explore experience';


--
-- Name: COLUMN _mergestat_explore_file_metadata.repo_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.repo_id IS 'foreign key for public.repos.id';


--
-- Name: COLUMN _mergestat_explore_file_metadata.path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.path IS 'path to the file';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_hash IS 'hash based reference to last commit';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_message IS 'message of the commit';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_author_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_author_name IS 'name of the author of the the modification';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_author_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_author_email IS 'email of the author of the modification';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_author_when; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_author_when IS 'timestamp of when the modifcation was authored';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_committer_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_committer_name IS 'name of the author who committed the modification';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_committer_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_committer_email IS 'email of the author who committed the modification';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_committer_when; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_committer_when IS 'timestamp of when the commit was made';


--
-- Name: COLUMN _mergestat_explore_file_metadata.last_commit_parents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata.last_commit_parents IS 'the number of parents of the commit';


--
-- Name: COLUMN _mergestat_explore_file_metadata._mergestat_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_file_metadata._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';


--
-- Name: _mergestat_explore_repo_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._mergestat_explore_repo_metadata (
    repo_id uuid NOT NULL,
    last_commit_hash text,
    last_commit_message text,
    last_commit_author_name text,
    last_commit_author_email text,
    last_commit_author_when timestamp with time zone,
    last_commit_committer_name text,
    last_commit_committer_email text,
    last_commit_committer_when timestamp with time zone,
    last_commit_parents integer,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE _mergestat_explore_repo_metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public._mergestat_explore_repo_metadata IS 'repo metadata for explore experience';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.repo_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.repo_id IS 'foreign key for public.repos.id';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_hash IS 'hash based reference to last commit';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_message IS 'message of the commit';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_author_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_author_name IS 'name of the author of the the modification';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_author_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_author_email IS 'email of the author of the modification';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_author_when; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_author_when IS 'timestamp of when the modifcation was authored';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_committer_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_committer_name IS 'name of the author who committed the modification';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_committer_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_committer_email IS 'email of the author who committed the modification';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_committer_when; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_committer_when IS 'timestamp of when the commit was made';


--
-- Name: COLUMN _mergestat_explore_repo_metadata.last_commit_parents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_parents IS 'the number of parents of the commit';


--
-- Name: COLUMN _mergestat_explore_repo_metadata._mergestat_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public._mergestat_explore_repo_metadata._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';


--
-- Name: git_commit_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.git_commit_stats (
    repo_id uuid NOT NULL,
    commit_hash text NOT NULL,
    file_path text NOT NULL,
    additions integer NOT NULL,
    deletions integer NOT NULL,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL,
    old_file_mode text DEFAULT 'unknown'::text NOT NULL,
    new_file_mode text DEFAULT 'unknown'::text NOT NULL
);


--
-- Name: TABLE git_commit_stats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.git_commit_stats IS 'git commit stats of a repo';


--
-- Name: COLUMN git_commit_stats.repo_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.repo_id IS 'foreign key for public.repos.id';


--
-- Name: COLUMN git_commit_stats.commit_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.commit_hash IS 'hash of the commit';


--
-- Name: COLUMN git_commit_stats.file_path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.file_path IS 'path of the file the modification was made in';


--
-- Name: COLUMN git_commit_stats.additions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.additions IS 'the number of additions in this path of the commit';


--
-- Name: COLUMN git_commit_stats.deletions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.deletions IS 'the number of deletions in this path of the commit';


--
-- Name: COLUMN git_commit_stats._mergestat_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';


--
-- Name: COLUMN git_commit_stats.old_file_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.old_file_mode IS 'old file mode derived from git mode. possible values (unknown, none, regular_file, symbolic_link, git_link)';


--
-- Name: COLUMN git_commit_stats.new_file_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commit_stats.new_file_mode IS 'new file mode derived from git mode. possible values (unknown, none, regular_file, symbolic_link, git_link)';


--
-- Name: git_commits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.git_commits (
    repo_id uuid NOT NULL,
    hash text NOT NULL,
    message text,
    author_name text,
    author_email text,
    author_when timestamp with time zone NOT NULL,
    committer_name text,
    committer_email text,
    committer_when timestamp with time zone NOT NULL,
    parents integer NOT NULL,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE git_commits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.git_commits IS 'git commit history of a repo';


--
-- Name: COLUMN git_commits.repo_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.repo_id IS 'foreign key for public.repos.id';


--
-- Name: COLUMN git_commits.hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.hash IS 'hash of the commit';


--
-- Name: COLUMN git_commits.message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.message IS 'message of the commit';


--
-- Name: COLUMN git_commits.author_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.author_name IS 'name of the author of the the modification';


--
-- Name: COLUMN git_commits.author_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.author_email IS 'email of the author of the modification';


--
-- Name: COLUMN git_commits.author_when; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.author_when IS 'timestamp of when the modifcation was authored';


--
-- Name: COLUMN git_commits.committer_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.committer_name IS 'name of the author who committed the modification';


--
-- Name: COLUMN git_commits.committer_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.committer_email IS 'email of the author who committed the modification';


--
-- Name: COLUMN git_commits.committer_when; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.committer_when IS 'timestamp of when the commit was made';


--
-- Name: COLUMN git_commits.parents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits.parents IS 'the number of parents of the commit';


--
-- Name: COLUMN git_commits._mergestat_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_commits._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';


--
-- Name: git_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.git_files (
    repo_id uuid NOT NULL,
    path text NOT NULL,
    executable boolean NOT NULL,
    contents text,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE git_files; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.git_files IS 'git files (content and paths) of a repo';


--
-- Name: COLUMN git_files.repo_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_files.repo_id IS 'foreign key for public.repos.id';


--
-- Name: COLUMN git_files.path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_files.path IS 'path of the file';


--
-- Name: COLUMN git_files.executable; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_files.executable IS 'boolean to determine if the file is an executable';


--
-- Name: COLUMN git_files.contents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_files.contents IS 'contents of the file';


--
-- Name: COLUMN git_files._mergestat_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.git_files._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    dirty boolean NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.schema_migrations IS 'MergeStat internal table to track schema migrations';


--
-- Name: schema_migrations_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations_history (
    id integer NOT NULL,
    version bigint NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE schema_migrations_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.schema_migrations_history IS 'MergeStat internal table to track schema migrations history';


--
-- Name: schema_migrations_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.schema_migrations_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schema_migrations_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.schema_migrations_history_id_seq OWNED BY public.schema_migrations_history.id;


--
-- Name: job_log_ordering; Type: SEQUENCE; Schema: sqlq; Owner: -
--

CREATE SEQUENCE sqlq.job_log_ordering
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
    CYCLE;


--
-- Name: job_logs; Type: TABLE; Schema: sqlq; Owner: -
--

CREATE TABLE sqlq.job_logs (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    job uuid DEFAULT public.gen_random_uuid() NOT NULL,
    logged_at timestamp with time zone DEFAULT now(),
    level sqlq.log_level,
    message text,
    "position" smallint DEFAULT nextval('sqlq.job_log_ordering'::regclass) NOT NULL
);


--
-- Name: queues; Type: TABLE; Schema: sqlq; Owner: -
--

CREATE TABLE sqlq.queues (
    name text NOT NULL,
    description text,
    concurrency integer DEFAULT 1,
    priority integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: repo_sync_logs id; Type: DEFAULT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_logs ALTER COLUMN id SET DEFAULT nextval('mergestat.repo_sync_logs_id_seq'::regclass);


--
-- Name: repo_sync_queue id; Type: DEFAULT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_queue ALTER COLUMN id SET DEFAULT nextval('mergestat.repo_sync_queue_id_seq'::regclass);


--
-- Name: schema_migrations_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations_history ALTER COLUMN id SET DEFAULT nextval('public.schema_migrations_history_id_seq'::regclass);


--
-- Name: container_image_types container_image_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_image_types
    ADD CONSTRAINT container_image_types_pkey PRIMARY KEY (name);


--
-- Name: container_images container_images_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT container_images_pkey PRIMARY KEY (id);


--
-- Name: container_sync_executions container_sync_executions_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_sync_executions
    ADD CONSTRAINT container_sync_executions_pkey PRIMARY KEY (sync_id, job_id);


--
-- Name: container_sync_schedules container_sync_schedules_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_sync_schedules
    ADD CONSTRAINT container_sync_schedules_pkey PRIMARY KEY (id);


--
-- Name: container_syncs container_syncs_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT container_syncs_pkey PRIMARY KEY (id);


--
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- Name: query_history query_history_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.query_history
    ADD CONSTRAINT query_history_pkey PRIMARY KEY (id);


--
-- Name: repo_import_types repo_import_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_import_types
    ADD CONSTRAINT repo_import_types_pkey PRIMARY KEY (type);


--
-- Name: repo_imports repo_imports_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_imports
    ADD CONSTRAINT repo_imports_pkey PRIMARY KEY (id);


--
-- Name: repo_sync_log_types repo_sync_log_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_log_types
    ADD CONSTRAINT repo_sync_log_types_pkey PRIMARY KEY (type);


--
-- Name: repo_sync_logs repo_sync_logs_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_logs
    ADD CONSTRAINT repo_sync_logs_pkey PRIMARY KEY (id);


--
-- Name: repo_sync_queue repo_sync_queue_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_pkey PRIMARY KEY (id);


--
-- Name: repo_sync_queue_status_types repo_sync_queue_status_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_queue_status_types
    ADD CONSTRAINT repo_sync_queue_status_types_pkey PRIMARY KEY (type);


--
-- Name: repo_syncs repo_sync_settings_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_sync_settings_pkey PRIMARY KEY (id);


--
-- Name: repo_sync_type_groups repo_sync_type_groups_group_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_type_groups
    ADD CONSTRAINT repo_sync_type_groups_group_pkey PRIMARY KEY ("group");


--
-- Name: repo_sync_type_label_associations repo_sync_type_label_associations_label_repo_sync_type_key; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_type_label_associations
    ADD CONSTRAINT repo_sync_type_label_associations_label_repo_sync_type_key UNIQUE (label, repo_sync_type);


--
-- Name: repo_sync_type_labels repo_sync_type_labels_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_type_labels
    ADD CONSTRAINT repo_sync_type_labels_pkey PRIMARY KEY (label);


--
-- Name: repo_sync_types repo_sync_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_types
    ADD CONSTRAINT repo_sync_types_pkey PRIMARY KEY (type);


--
-- Name: repo_syncs repo_syncs_repo_id_sync_type_key; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_syncs_repo_id_sync_type_key UNIQUE (repo_id, sync_type);


--
-- Name: saved_explores saved_explores_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.saved_explores
    ADD CONSTRAINT saved_explores_pkey PRIMARY KEY (id);


--
-- Name: saved_queries saved_queries_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.saved_queries
    ADD CONSTRAINT saved_queries_pkey PRIMARY KEY (id);


--
-- Name: service_auth_credential_types service_auth_credential_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.service_auth_credential_types
    ADD CONSTRAINT service_auth_credential_types_pkey PRIMARY KEY (type);


--
-- Name: service_auth_credentials service_auth_credentials_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.service_auth_credentials
    ADD CONSTRAINT service_auth_credentials_pkey PRIMARY KEY (id);


--
-- Name: sync_variables sync_variables_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.sync_variables
    ADD CONSTRAINT sync_variables_pkey PRIMARY KEY (repo_id, key);


--
-- Name: container_images unique_container_images_name; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT unique_container_images_name UNIQUE (name);


--
-- Name: container_images unique_container_images_url; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT unique_container_images_url UNIQUE (url);


--
-- Name: container_sync_schedules unique_container_sync_schedule; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_sync_schedules
    ADD CONSTRAINT unique_container_sync_schedule UNIQUE (sync_id);


--
-- Name: container_syncs unq_repo_image; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT unq_repo_image UNIQUE (repo_id, image_id);


--
-- Name: providers uq_providers_name; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.providers
    ADD CONSTRAINT uq_providers_name UNIQUE (name);


--
-- Name: vendor_types vendor_types_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.vendor_types
    ADD CONSTRAINT vendor_types_pkey PRIMARY KEY (name);


--
-- Name: vendors vendors_pkey; Type: CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (name);


--
-- Name: _mergestat_explore_file_metadata _mergestat_explore_file_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._mergestat_explore_file_metadata
    ADD CONSTRAINT _mergestat_explore_file_metadata_pkey PRIMARY KEY (repo_id, path);


--
-- Name: _mergestat_explore_repo_metadata _mergestat_explore_repo_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._mergestat_explore_repo_metadata
    ADD CONSTRAINT _mergestat_explore_repo_metadata_pkey PRIMARY KEY (repo_id);


--
-- Name: git_commit_stats commit_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.git_commit_stats
    ADD CONSTRAINT commit_stats_pkey PRIMARY KEY (repo_id, file_path, commit_hash, new_file_mode);


--
-- Name: git_commits commits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.git_commits
    ADD CONSTRAINT commits_pkey PRIMARY KEY (repo_id, hash);


--
-- Name: git_files files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.git_files
    ADD CONSTRAINT files_pkey PRIMARY KEY (repo_id, path);


--
-- Name: repos repos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repos
    ADD CONSTRAINT repos_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations_history schema_migrations_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations_history
    ADD CONSTRAINT schema_migrations_history_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: job_logs job_logs_pkey; Type: CONSTRAINT; Schema: sqlq; Owner: -
--

ALTER TABLE ONLY sqlq.job_logs
    ADD CONSTRAINT job_logs_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: sqlq; Owner: -
--

ALTER TABLE ONLY sqlq.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: queues queues_pkey; Type: CONSTRAINT; Schema: sqlq; Owner: -
--

ALTER TABLE ONLY sqlq.queues
    ADD CONSTRAINT queues_pkey PRIMARY KEY (name);


--
-- Name: idx_repo_sync_logs_repo_sync_created_at; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_logs_repo_sync_created_at ON mergestat.repo_sync_logs USING btree (created_at DESC);


--
-- Name: idx_repo_sync_logs_repo_sync_queue_id; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_logs_repo_sync_queue_id ON mergestat.repo_sync_logs USING btree (repo_sync_queue_id DESC);


--
-- Name: idx_repo_sync_logs_repo_sync_queue_id_fkey; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_logs_repo_sync_queue_id_fkey ON mergestat.repo_sync_logs USING btree (repo_sync_queue_id);


--
-- Name: idx_repo_sync_queue_created_at; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_queue_created_at ON mergestat.repo_sync_queue USING btree (created_at DESC);


--
-- Name: idx_repo_sync_queue_done_at; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_queue_done_at ON mergestat.repo_sync_queue USING btree (done_at DESC);


--
-- Name: idx_repo_sync_queue_repo_sync_id_fkey; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_queue_repo_sync_id_fkey ON mergestat.repo_sync_queue USING btree (repo_sync_id);


--
-- Name: idx_repo_sync_queue_status; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_queue_status ON mergestat.repo_sync_queue USING btree (status DESC);


--
-- Name: idx_repo_sync_settings_repo_id_fkey; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE INDEX idx_repo_sync_settings_repo_id_fkey ON mergestat.repo_syncs USING btree (repo_id);


--
-- Name: ix_single_default_per_provider; Type: INDEX; Schema: mergestat; Owner: -
--

CREATE UNIQUE INDEX ix_single_default_per_provider ON mergestat.service_auth_credentials USING btree (provider, is_default) WHERE (is_default = true);


--
-- Name: commits_author_when_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commits_author_when_idx ON public.git_commits USING btree (repo_id, author_when);


--
-- Name: idx_commit_stats_repo_id_fkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_commit_stats_repo_id_fkey ON public.git_commit_stats USING btree (repo_id);


--
-- Name: idx_commits_repo_id_fkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_commits_repo_id_fkey ON public.git_commits USING btree (repo_id);


--
-- Name: idx_files_repo_id_fkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_files_repo_id_fkey ON public.git_files USING btree (repo_id);


--
-- Name: idx_gist_git_files_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gist_git_files_path ON public.git_files USING gist (path public.gist_trgm_ops);


--
-- Name: idx_git_commit_stats_repo_id_hash_file_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_git_commit_stats_repo_id_hash_file_path ON public.git_commit_stats USING btree (repo_id, commit_hash, file_path);


--
-- Name: idx_git_commits_repo_id_hash_parents; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_git_commits_repo_id_hash_parents ON public.git_commits USING btree (repo_id, hash, parents);


--
-- Name: idx_repos_repo_import_id_fkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_repos_repo_import_id_fkey ON public.repos USING btree (repo_import_id);


--
-- Name: repos_repo_ref_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX repos_repo_ref_unique ON public.repos USING btree (repo, ((ref IS NULL))) WHERE (ref IS NULL);


--
-- Name: ix_job_logs_job_level; Type: INDEX; Schema: sqlq; Owner: -
--

CREATE INDEX ix_job_logs_job_level ON sqlq.job_logs USING btree (job, level);


--
-- Name: ix_jobs_queue_type_status; Type: INDEX; Schema: sqlq; Owner: -
--

CREATE INDEX ix_jobs_queue_type_status ON sqlq.jobs USING btree (queue, typename, status);


--
-- Name: ix_logs_job; Type: INDEX; Schema: sqlq; Owner: -
--

CREATE INDEX ix_logs_job ON sqlq.job_logs USING btree (job);


--
-- Name: repo_sync_queue repo_sync_queue_status_update_trigger; Type: TRIGGER; Schema: mergestat; Owner: -
--

CREATE TRIGGER repo_sync_queue_status_update_trigger BEFORE UPDATE ON mergestat.repo_sync_queue FOR EACH ROW EXECUTE FUNCTION public.repo_sync_queue_status_update_trigger();


--
-- Name: repo_imports set_mergestat_repo_imports_updated_at; Type: TRIGGER; Schema: mergestat; Owner: -
--

CREATE TRIGGER set_mergestat_repo_imports_updated_at BEFORE UPDATE ON mergestat.repo_imports FOR EACH ROW EXECUTE FUNCTION mergestat.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_mergestat_repo_imports_updated_at ON repo_imports; Type: COMMENT; Schema: mergestat; Owner: -
--

COMMENT ON TRIGGER set_mergestat_repo_imports_updated_at ON mergestat.repo_imports IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: schema_migrations track_applied_migrations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER track_applied_migrations AFTER INSERT ON public.schema_migrations FOR EACH ROW EXECUTE FUNCTION public.track_applied_migration();


--
-- Name: container_images fk_container_image_type; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_images
    ADD CONSTRAINT fk_container_image_type FOREIGN KEY (type) REFERENCES mergestat.container_image_types(name);


--
-- Name: container_sync_executions fk_execution_job; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_sync_executions
    ADD CONSTRAINT fk_execution_job FOREIGN KEY (job_id) REFERENCES sqlq.jobs(id) ON DELETE CASCADE;


--
-- Name: container_sync_executions fk_execution_sync; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_sync_executions
    ADD CONSTRAINT fk_execution_sync FOREIGN KEY (sync_id) REFERENCES mergestat.container_syncs(id) ON DELETE CASCADE;


--
-- Name: service_auth_credentials fk_providers_credentials_provider; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.service_auth_credentials
    ADD CONSTRAINT fk_providers_credentials_provider FOREIGN KEY (provider) REFERENCES mergestat.providers(id) ON DELETE CASCADE;


--
-- Name: repo_imports fk_providers_repo_imports_provider; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_imports
    ADD CONSTRAINT fk_providers_repo_imports_provider FOREIGN KEY (provider) REFERENCES mergestat.providers(id) ON DELETE CASCADE;


--
-- Name: container_sync_schedules fk_schedule_sync; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_sync_schedules
    ADD CONSTRAINT fk_schedule_sync FOREIGN KEY (sync_id) REFERENCES mergestat.container_syncs(id) ON DELETE CASCADE;


--
-- Name: container_syncs fk_sync_container; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT fk_sync_container FOREIGN KEY (image_id) REFERENCES mergestat.container_images(id) ON DELETE CASCADE;


--
-- Name: container_syncs fk_sync_repository; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT fk_sync_repository FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON DELETE CASCADE;


--
-- Name: providers fk_vendors_providers_vendor; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.providers
    ADD CONSTRAINT fk_vendors_providers_vendor FOREIGN KEY (vendor) REFERENCES mergestat.vendors(name);


--
-- Name: vendors fk_vendors_type; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.vendors
    ADD CONSTRAINT fk_vendors_type FOREIGN KEY (type) REFERENCES mergestat.vendor_types(name);


--
-- Name: repo_syncs last_completed_repo_sync_queue_id_fk; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT last_completed_repo_sync_queue_id_fk FOREIGN KEY (last_completed_repo_sync_queue_id) REFERENCES mergestat.repo_sync_queue(id) ON DELETE SET NULL;


--
-- Name: repo_sync_logs repo_sync_logs_log_type_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_logs
    ADD CONSTRAINT repo_sync_logs_log_type_fkey FOREIGN KEY (log_type) REFERENCES mergestat.repo_sync_log_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: repo_sync_logs repo_sync_logs_repo_sync_queue_id_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_logs
    ADD CONSTRAINT repo_sync_logs_repo_sync_queue_id_fkey FOREIGN KEY (repo_sync_queue_id) REFERENCES mergestat.repo_sync_queue(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: repo_sync_queue repo_sync_queue_repo_sync_id_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_repo_sync_id_fkey FOREIGN KEY (repo_sync_id) REFERENCES mergestat.repo_syncs(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: repo_sync_queue repo_sync_queue_status_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_status_fkey FOREIGN KEY (status) REFERENCES mergestat.repo_sync_queue_status_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: repo_sync_queue repo_sync_queue_type_group_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_type_group_fkey FOREIGN KEY (type_group) REFERENCES mergestat.repo_sync_type_groups("group") ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: repo_syncs repo_sync_settings_repo_id_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_sync_settings_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: repo_sync_type_label_associations repo_sync_type_label_associations_label_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_type_label_associations
    ADD CONSTRAINT repo_sync_type_label_associations_label_fkey FOREIGN KEY (label) REFERENCES mergestat.repo_sync_type_labels(label) ON DELETE CASCADE;


--
-- Name: repo_sync_type_label_associations repo_sync_type_label_associations_repo_sync_type_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_type_label_associations
    ADD CONSTRAINT repo_sync_type_label_associations_repo_sync_type_fkey FOREIGN KEY (repo_sync_type) REFERENCES mergestat.repo_sync_types(type) ON DELETE CASCADE;


--
-- Name: repo_sync_types repo_sync_types_type_group_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_sync_types
    ADD CONSTRAINT repo_sync_types_type_group_fkey FOREIGN KEY (type_group) REFERENCES mergestat.repo_sync_type_groups("group") ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: repo_syncs repo_syncs_sync_type_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_syncs_sync_type_fkey FOREIGN KEY (sync_type) REFERENCES mergestat.repo_sync_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: service_auth_credentials service_auth_credentials_type_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.service_auth_credentials
    ADD CONSTRAINT service_auth_credentials_type_fkey FOREIGN KEY (type) REFERENCES mergestat.service_auth_credential_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: sync_variables sync_variables_repo_id_fkey; Type: FK CONSTRAINT; Schema: mergestat; Owner: -
--

ALTER TABLE ONLY mergestat.sync_variables
    ADD CONSTRAINT sync_variables_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id);


--
-- Name: _mergestat_explore_file_metadata _mergestat_explore_file_metadata_repo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._mergestat_explore_file_metadata
    ADD CONSTRAINT _mergestat_explore_file_metadata_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: _mergestat_explore_repo_metadata _mergestat_explore_repo_metadata_repo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._mergestat_explore_repo_metadata
    ADD CONSTRAINT _mergestat_explore_repo_metadata_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: repos fk_repos_provider; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repos
    ADD CONSTRAINT fk_repos_provider FOREIGN KEY (provider) REFERENCES mergestat.providers(id) ON DELETE CASCADE;


--
-- Name: git_commit_stats git_commit_stats_repo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.git_commit_stats
    ADD CONSTRAINT git_commit_stats_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: git_commits git_commits_repo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.git_commits
    ADD CONSTRAINT git_commits_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: git_files git_files_repo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.git_files
    ADD CONSTRAINT git_files_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: repos repos_repo_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repos
    ADD CONSTRAINT repos_repo_import_id_fkey FOREIGN KEY (repo_import_id) REFERENCES mergestat.repo_imports(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: job_logs job_logs_job_fkey; Type: FK CONSTRAINT; Schema: sqlq; Owner: -
--

ALTER TABLE ONLY sqlq.job_logs
    ADD CONSTRAINT job_logs_job_fkey FOREIGN KEY (job) REFERENCES sqlq.jobs(id) ON DELETE CASCADE;


--
-- Name: jobs jobs_queue_fkey; Type: FK CONSTRAINT; Schema: sqlq; Owner: -
--

ALTER TABLE ONLY sqlq.jobs
    ADD CONSTRAINT jobs_queue_fkey FOREIGN KEY (queue) REFERENCES sqlq.queues(name) ON DELETE CASCADE;


--
-- Name: query_history; Type: ROW SECURITY; Schema: mergestat; Owner: -
--

ALTER TABLE mergestat.query_history ENABLE ROW LEVEL SECURITY;

--
-- Name: query_history query_history_access; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY query_history_access ON mergestat.query_history USING ((run_by = CURRENT_USER));


--
-- Name: saved_explores; Type: ROW SECURITY; Schema: mergestat; Owner: -
--

ALTER TABLE mergestat.saved_explores ENABLE ROW LEVEL SECURITY;

--
-- Name: saved_explores saved_explores_all_access; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY saved_explores_all_access ON mergestat.saved_explores USING ((created_by = CURRENT_USER));


--
-- Name: saved_explores saved_explores_all_access_admin; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY saved_explores_all_access_admin ON mergestat.saved_explores TO mergestat_role_admin USING (true);


--
-- Name: saved_explores saved_explores_all_view; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY saved_explores_all_view ON mergestat.saved_explores FOR SELECT USING (true);


--
-- Name: saved_queries; Type: ROW SECURITY; Schema: mergestat; Owner: -
--

ALTER TABLE mergestat.saved_queries ENABLE ROW LEVEL SECURITY;

--
-- Name: saved_queries saved_queries_all_access; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY saved_queries_all_access ON mergestat.saved_queries USING ((created_by = CURRENT_USER));


--
-- Name: saved_queries saved_queries_all_access_admin; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY saved_queries_all_access_admin ON mergestat.saved_queries TO mergestat_role_admin USING (true);


--
-- Name: saved_queries saved_queries_all_view; Type: POLICY; Schema: mergestat; Owner: -
--

CREATE POLICY saved_queries_all_view ON mergestat.saved_queries FOR SELECT USING (true);


--
-- Name: SCHEMA mergestat; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA mergestat TO mergestat_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA mergestat TO readaccess;
GRANT USAGE ON SCHEMA mergestat TO mergestat_role_readonly;
GRANT USAGE ON SCHEMA mergestat TO mergestat_role_user;
GRANT USAGE ON SCHEMA mergestat TO mergestat_role_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA mergestat TO mergestat_role_demo;
GRANT USAGE ON SCHEMA mergestat TO mergestat_role_queries_only;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO readaccess;
GRANT USAGE ON SCHEMA public TO mergestat_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA public TO mergestat_role_readonly;
GRANT USAGE ON SCHEMA public TO mergestat_role_user;
GRANT USAGE ON SCHEMA public TO mergestat_role_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA public TO mergestat_role_demo;
GRANT USAGE ON SCHEMA public TO mergestat_role_queries_only;


--
-- Name: SCHEMA sqlq; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA sqlq TO mergestat_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA sqlq TO mergestat_role_admin WITH GRANT OPTION;
GRANT USAGE ON SCHEMA sqlq TO mergestat_role_user;
GRANT USAGE ON SCHEMA sqlq TO mergestat_role_readonly;
GRANT USAGE ON SCHEMA sqlq TO mergestat_role_demo;
GRANT USAGE ON SCHEMA sqlq TO mergestat_role_queries_only;


--
-- Name: TABLE service_auth_credentials; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.service_auth_credentials TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO readaccess;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.service_auth_credentials TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.service_auth_credentials TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.service_auth_credentials TO mergestat_role_queries_only;


--
-- Name: TABLE sync_variables; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.sync_variables TO readaccess;
GRANT ALL ON TABLE mergestat.sync_variables TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.sync_variables TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.sync_variables TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.sync_variables TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.sync_variables TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.sync_variables TO mergestat_role_queries_only;


--
-- Name: TABLE container_syncs; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.container_syncs TO readaccess;
GRANT ALL ON TABLE mergestat.container_syncs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_syncs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_syncs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_syncs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_syncs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_syncs TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_queue; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_sync_queue TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_queue TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_queue TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO mergestat_role_queries_only;


--
-- Name: TABLE repos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.repos TO readaccess;
GRANT ALL ON TABLE public.repos TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.repos TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.repos TO mergestat_role_user;
GRANT ALL ON TABLE public.repos TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.repos TO mergestat_role_demo;
GRANT SELECT ON TABLE public.repos TO mergestat_role_queries_only;


--
-- Name: TABLE jobs; Type: ACL; Schema: sqlq; Owner: -
--

GRANT ALL ON TABLE sqlq.jobs TO mergestat_admin WITH GRANT OPTION;
GRANT ALL ON TABLE sqlq.jobs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sqlq.jobs TO mergestat_role_user;
GRANT SELECT ON TABLE sqlq.jobs TO mergestat_role_readonly;
GRANT SELECT ON TABLE sqlq.jobs TO mergestat_role_demo;
GRANT SELECT ON TABLE sqlq.jobs TO mergestat_role_queries_only;


--
-- Name: TABLE container_image_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.container_image_types TO readaccess;
GRANT ALL ON TABLE mergestat.container_image_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_image_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_image_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_image_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_image_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_image_types TO mergestat_role_queries_only;


--
-- Name: TABLE container_images; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.container_images TO readaccess;
GRANT ALL ON TABLE mergestat.container_images TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_images TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_images TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_images TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_images TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_images TO mergestat_role_queries_only;


--
-- Name: TABLE container_sync_executions; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.container_sync_executions TO readaccess;
GRANT ALL ON TABLE mergestat.container_sync_executions TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_executions TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_sync_executions TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_sync_executions TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_executions TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_sync_executions TO mergestat_role_queries_only;


--
-- Name: TABLE container_sync_schedules; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.container_sync_schedules TO readaccess;
GRANT ALL ON TABLE mergestat.container_sync_schedules TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_schedules TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_sync_schedules TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_sync_schedules TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_schedules TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_sync_schedules TO mergestat_role_queries_only;


--
-- Name: TABLE latest_repo_syncs; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.latest_repo_syncs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO readaccess;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.latest_repo_syncs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.latest_repo_syncs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO mergestat_role_queries_only;


--
-- Name: TABLE providers; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.providers TO readaccess;
GRANT ALL ON TABLE mergestat.providers TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.providers TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.providers TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.providers TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.providers TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.providers TO mergestat_role_queries_only;


--
-- Name: TABLE query_history; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.query_history TO readaccess;
GRANT ALL ON TABLE mergestat.query_history TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT,INSERT ON TABLE mergestat.query_history TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.query_history TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.query_history TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT ON TABLE mergestat.query_history TO mergestat_role_demo;
GRANT SELECT,INSERT ON TABLE mergestat.query_history TO mergestat_role_queries_only;


--
-- Name: TABLE repo_import_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_import_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_import_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_import_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_import_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_import_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_import_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_import_types TO mergestat_role_queries_only;


--
-- Name: TABLE repo_imports; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_imports TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_imports TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_imports TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_imports TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_imports TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_imports TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_imports TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_log_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_sync_log_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_log_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_log_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_log_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_log_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_log_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_log_types TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_logs; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_sync_logs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_logs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_logs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO mergestat_role_queries_only;


--
-- Name: SEQUENCE repo_sync_logs_id_seq; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON SEQUENCE mergestat.repo_sync_logs_id_seq TO readaccess;
GRANT USAGE ON SEQUENCE mergestat.repo_sync_logs_id_seq TO mergestat_role_user;
GRANT ALL ON SEQUENCE mergestat.repo_sync_logs_id_seq TO mergestat_role_admin WITH GRANT OPTION;
GRANT ALL ON SEQUENCE mergestat.repo_sync_logs_id_seq TO mergestat_admin WITH GRANT OPTION;


--
-- Name: SEQUENCE repo_sync_queue_id_seq; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON SEQUENCE mergestat.repo_sync_queue_id_seq TO readaccess;
GRANT USAGE ON SEQUENCE mergestat.repo_sync_queue_id_seq TO mergestat_role_user;
GRANT ALL ON SEQUENCE mergestat.repo_sync_queue_id_seq TO mergestat_role_admin WITH GRANT OPTION;
GRANT ALL ON SEQUENCE mergestat.repo_sync_queue_id_seq TO mergestat_admin WITH GRANT OPTION;


--
-- Name: TABLE repo_sync_queue_status_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_type_groups; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_admin WITH GRANT OPTION;
GRANT ALL ON TABLE mergestat.repo_sync_type_groups TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_type_label_associations; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO readaccess;
GRANT ALL ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_type_labels; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO readaccess;
GRANT ALL ON TABLE mergestat.repo_sync_type_labels TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_queries_only;


--
-- Name: TABLE repo_sync_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_sync_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO mergestat_role_queries_only;


--
-- Name: TABLE repo_syncs; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.repo_syncs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_syncs TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_syncs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_syncs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_syncs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_syncs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_syncs TO mergestat_role_queries_only;


--
-- Name: TABLE saved_explores; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.saved_explores TO readaccess;
GRANT ALL ON TABLE mergestat.saved_explores TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_explores TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.saved_explores TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.saved_explores TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_explores TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.saved_explores TO mergestat_role_queries_only;


--
-- Name: TABLE saved_queries; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.saved_queries TO readaccess;
GRANT ALL ON TABLE mergestat.saved_queries TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_queries TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.saved_queries TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.saved_queries TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_queries TO mergestat_role_demo;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.saved_queries TO mergestat_role_queries_only;


--
-- Name: TABLE schema_introspection; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.schema_introspection TO readaccess;
GRANT ALL ON TABLE mergestat.schema_introspection TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.schema_introspection TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.schema_introspection TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.schema_introspection TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.schema_introspection TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.schema_introspection TO mergestat_role_queries_only;


--
-- Name: TABLE service_auth_credential_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT ALL ON TABLE mergestat.service_auth_credential_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO readaccess;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.service_auth_credential_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.service_auth_credential_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.service_auth_credential_types TO mergestat_role_queries_only;


--
-- Name: TABLE user_mgmt_pg_users; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO readaccess;
GRANT ALL ON TABLE mergestat.user_mgmt_pg_users TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_queries_only;


--
-- Name: TABLE vendor_types; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.vendor_types TO readaccess;
GRANT ALL ON TABLE mergestat.vendor_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.vendor_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.vendor_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.vendor_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.vendor_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.vendor_types TO mergestat_role_queries_only;


--
-- Name: TABLE vendors; Type: ACL; Schema: mergestat; Owner: -
--

GRANT SELECT ON TABLE mergestat.vendors TO readaccess;
GRANT ALL ON TABLE mergestat.vendors TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.vendors TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.vendors TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.vendors TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.vendors TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.vendors TO mergestat_role_queries_only;


--
-- Name: TABLE _mergestat_explore_file_metadata; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public._mergestat_explore_file_metadata TO readaccess;
GRANT ALL ON TABLE public._mergestat_explore_file_metadata TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public._mergestat_explore_file_metadata TO mergestat_role_readonly;
GRANT SELECT ON TABLE public._mergestat_explore_file_metadata TO mergestat_role_user;
GRANT ALL ON TABLE public._mergestat_explore_file_metadata TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public._mergestat_explore_file_metadata TO mergestat_role_demo;
GRANT SELECT ON TABLE public._mergestat_explore_file_metadata TO mergestat_role_queries_only;


--
-- Name: TABLE _mergestat_explore_repo_metadata; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO readaccess;
GRANT ALL ON TABLE public._mergestat_explore_repo_metadata TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_readonly;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_user;
GRANT ALL ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_demo;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_queries_only;


--
-- Name: TABLE git_commit_stats; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.git_commit_stats TO readaccess;
GRANT ALL ON TABLE public.git_commit_stats TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_user;
GRANT ALL ON TABLE public.git_commit_stats TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_demo;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_queries_only;


--
-- Name: TABLE git_commits; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.git_commits TO readaccess;
GRANT ALL ON TABLE public.git_commits TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_user;
GRANT ALL ON TABLE public.git_commits TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_demo;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_queries_only;


--
-- Name: TABLE git_files; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.git_files TO readaccess;
GRANT ALL ON TABLE public.git_files TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_user;
GRANT ALL ON TABLE public.git_files TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_demo;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_queries_only;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.schema_migrations TO readaccess;
GRANT ALL ON TABLE public.schema_migrations TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_user;
GRANT ALL ON TABLE public.schema_migrations TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_demo;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_queries_only;


--
-- Name: TABLE schema_migrations_history; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.schema_migrations_history TO readaccess;
GRANT ALL ON TABLE public.schema_migrations_history TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_user;
GRANT ALL ON TABLE public.schema_migrations_history TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_demo;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_queries_only;


--
-- Name: SEQUENCE schema_migrations_history_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON SEQUENCE public.schema_migrations_history_id_seq TO readaccess;
GRANT ALL ON SEQUENCE public.schema_migrations_history_id_seq TO mergestat_role_admin WITH GRANT OPTION;
GRANT ALL ON SEQUENCE public.schema_migrations_history_id_seq TO mergestat_admin WITH GRANT OPTION;


--
-- Name: SEQUENCE job_log_ordering; Type: ACL; Schema: sqlq; Owner: -
--

GRANT USAGE ON SEQUENCE sqlq.job_log_ordering TO mergestat_admin;
GRANT USAGE ON SEQUENCE sqlq.job_log_ordering TO mergestat_role_admin;
GRANT USAGE ON SEQUENCE sqlq.job_log_ordering TO mergestat_role_user;
GRANT USAGE ON SEQUENCE sqlq.job_log_ordering TO mergestat_role_readonly;


--
-- Name: TABLE job_logs; Type: ACL; Schema: sqlq; Owner: -
--

GRANT ALL ON TABLE sqlq.job_logs TO mergestat_admin WITH GRANT OPTION;
GRANT ALL ON TABLE sqlq.job_logs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sqlq.job_logs TO mergestat_role_user;
GRANT SELECT ON TABLE sqlq.job_logs TO mergestat_role_readonly;
GRANT SELECT ON TABLE sqlq.job_logs TO mergestat_role_demo;
GRANT SELECT ON TABLE sqlq.job_logs TO mergestat_role_queries_only;


--
-- Name: TABLE queues; Type: ACL; Schema: sqlq; Owner: -
--

GRANT ALL ON TABLE sqlq.queues TO mergestat_admin WITH GRANT OPTION;
GRANT ALL ON TABLE sqlq.queues TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sqlq.queues TO mergestat_role_user;
GRANT SELECT ON TABLE sqlq.queues TO mergestat_role_readonly;
GRANT SELECT ON TABLE sqlq.queues TO mergestat_role_demo;
GRANT SELECT ON TABLE sqlq.queues TO mergestat_role_queries_only;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: mergestat; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT SELECT ON SEQUENCES  TO readaccess;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT ALL ON SEQUENCES  TO mergestat_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT USAGE ON SEQUENCES  TO mergestat_role_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT ALL ON SEQUENCES  TO mergestat_role_admin WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: mergestat; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT SELECT ON TABLES  TO readaccess;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT ALL ON TABLES  TO mergestat_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT SELECT ON TABLES  TO mergestat_role_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO mergestat_role_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT ALL ON TABLES  TO mergestat_role_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT SELECT ON TABLES  TO mergestat_role_demo;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mergestat GRANT SELECT ON TABLES  TO mergestat_role_queries_only;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON SEQUENCES  TO readaccess;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO mergestat_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO mergestat_role_admin WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES  TO readaccess;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO mergestat_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES  TO mergestat_role_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES  TO mergestat_role_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO mergestat_role_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES  TO mergestat_role_demo;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES  TO mergestat_role_queries_only;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: sqlq; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT USAGE ON SEQUENCES  TO mergestat_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT USAGE ON SEQUENCES  TO mergestat_role_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT USAGE ON SEQUENCES  TO mergestat_role_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT USAGE ON SEQUENCES  TO mergestat_role_admin;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: sqlq; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT ALL ON TABLES  TO mergestat_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT SELECT ON TABLES  TO mergestat_role_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO mergestat_role_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT ALL ON TABLES  TO mergestat_role_admin WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT SELECT ON TABLES  TO mergestat_role_demo;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA sqlq GRANT SELECT ON TABLES  TO mergestat_role_queries_only;


--
-- PostgreSQL database dump complete
--

