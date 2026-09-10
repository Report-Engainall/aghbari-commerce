-- Read-only runtime overlay for the canonical baseline.
-- Execute against the canonical source with psql; redirect stdout to a file.
\pset tuples_only on
\pset format unaligned
\pset pager off

-- RLS enablement is normally included by pg_dump; keep this explicit for parity.
select format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', c.relname)
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relrowsecurity
order by c.relname;

-- Realtime publication membership.
select format('ALTER PUBLICATION %I ADD TABLE public.%I;', p.pubname, c.relname)
from pg_publication p
join pg_publication_rel pr on pr.prpubid=p.oid
join pg_class c on c.oid=pr.prrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
order by p.pubname,c.relname;

-- Table ACLs; owner privileges are implicit and therefore excluded.
select format('GRANT %s ON TABLE public.%I TO %s;',
  string_agg(x.privilege_type, ', ' order by x.privilege_type), c.relname,
  case when x.grantee=0 then 'PUBLIC' else quote_ident(r.rolname) end)
from pg_class c join pg_namespace n on n.oid=c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x
left join pg_roles r on r.oid=x.grantee
where n.nspname='public' and c.relkind='r' and x.grantee <> c.relowner
group by c.relname,x.grantee,r.rolname order by c.relname,x.grantee;

-- Sequence ACLs.
select format('GRANT %s ON SEQUENCE public.%I TO %s;',
  string_agg(x.privilege_type, ', ' order by x.privilege_type), c.relname,
  case when x.grantee=0 then 'PUBLIC' else quote_ident(r.rolname) end)
from pg_class c join pg_namespace n on n.oid=c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('S', c.relowner))) x
left join pg_roles r on r.oid=x.grantee
where n.nspname='public' and c.relkind='S' and x.grantee <> c.relowner
group by c.relname,x.grantee,r.rolname order by c.relname,x.grantee;

-- Function EXECUTE grants, preserving overloaded signatures.
select format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO %s;',
  p.proname, pg_get_function_identity_arguments(p.oid),
  case when x.grantee=0 then 'PUBLIC' else quote_ident(r.rolname) end)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
left join pg_roles r on r.oid=x.grantee
where n.nspname='public' and p.prokind='f'
  and x.privilege_type='EXECUTE' and x.grantee <> p.proowner
order by p.proname,pg_get_function_identity_arguments(p.oid),x.grantee;
