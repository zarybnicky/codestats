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


