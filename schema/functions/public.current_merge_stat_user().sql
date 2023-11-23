CREATE FUNCTION public.current_merge_stat_user() RETURNS name
    LANGUAGE sql STABLE
    AS $$ SELECT user $$;


