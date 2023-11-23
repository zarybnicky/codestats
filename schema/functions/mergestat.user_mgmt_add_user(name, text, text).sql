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


