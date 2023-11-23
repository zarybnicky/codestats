CREATE FUNCTION mergestat.user_mgmt_remove_user(username name) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN
    EXECUTE FORMAT('DROP USER IF EXISTS %I', username);
    RETURN 1;
END;
$$;


