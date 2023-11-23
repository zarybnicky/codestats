CREATE FUNCTION mergestat.user_mgmt_add_user(username name, password text, role text) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN


