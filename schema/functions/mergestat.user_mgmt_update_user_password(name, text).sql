CREATE FUNCTION mergestat.user_mgmt_update_user_password(username name, password text) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN


