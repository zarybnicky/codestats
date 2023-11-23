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


