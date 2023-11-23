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


