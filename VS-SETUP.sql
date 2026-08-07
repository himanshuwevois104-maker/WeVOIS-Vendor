-- VS-SETUP.sql  (WeVois Vendor Settlement Portal)
-- Run this WHOLE file in the Supabase SQL editor. Select all of it first.
-- Pure ASCII on purpose. Re-runnable: safe to run twice.
-- ============================================================================

-- ---------------------------------------------------------------- extensions
create extension if not exists "pgcrypto";
create extension if not exists btree_gist;

-- ------------------------------------------------------------------ settings
create table if not exists vs_settings (
  id              int primary key default 1,
  window_days     int  not null default 5,
  deemed_approve  bool not null default true,
  variance_pct    numeric not null default 15,
  org_name        text not null default 'WeVois',
  constraint vs_settings_single check (id = 1)
);
insert into vs_settings (id) values (1) on conflict (id) do nothing;

-- --------------------------------------------------------------- capabilities
create table if not exists vs_caps (
  role text not null,
  cap  text not null,
  primary key (role, cap)
);

insert into vs_caps (role, cap) values
  ('admin','view_all'), ('admin','manage_users'), ('admin','manage_vendors'),
  ('admin','manage_contracts'), ('admin','manage_settlements'), ('admin','manage_masters'),
  ('manager','view_all'), ('manager','edit_draft'), ('manager','share'),
  ('manager','logcall'), ('manager','resolve'), ('manager','revise'), ('manager','remind'),
  ('accounts','view_all'), ('accounts','post_payroll'), ('accounts','pay'),
  ('ceo','view_all'),
  ('vp','view_all'),
  ('vendor','raise'), ('vendor','confirm'), ('vendor','approve')
on conflict do nothing;

-- ------------------------------------------------------------------ profiles
create table if not exists vs_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  email       text not null default '',
  role        text not null check (role in ('admin','manager','accounts','ceo','vp','vendor')),
  vendor_id   uuid,
  active      bool not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists vs_invites (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  full_name   text not null default '',
  role        text not null check (role in ('admin','manager','accounts','ceo','vp','vendor')),
  vendor_id   uuid,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);
create index if not exists vs_invites_email_idx on vs_invites (lower(email)) where used_at is null;

-- ------------------------------------------------------- vendors sites contracts
create table if not exists vs_vendors (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  code          text unique,
  contact_name  text not null default '',
  contact_email text not null default '',
  contact_phone text not null default '',
  active        bool not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists vs_sites (
  id      uuid primary key default gen_random_uuid(),
  name    text not null,
  city    text not null default '',
  active  bool not null default true
);

-- One vendor can hold many sites, and a site can change hands over time.
-- A contract is therefore a TENURE: this vendor ran this site from this month
-- to that day. from_date / to_date are real dates, because a handover does not
-- wait for the 1st - Nawa changed hands on 16 April. to_date null means "still
-- running". Two vendors can never overlap on the
-- same site - the exclusion constraint below makes that impossible, not just
-- discouraged.
create table if not exists vs_contracts (
  id         uuid primary key default gen_random_uuid(),
  vendor_id  uuid not null references vs_vendors(id) on delete restrict,
  site_id    uuid not null references vs_sites(id)   on delete restrict,
  vehicles   int  not null check (vehicles > 0),
  from_date  date not null default current_date,
  to_date    date,
  active     bool generated always as (to_date is null) stored,
  check (to_date is null or to_date >= from_date)
);

alter table vs_contracts drop constraint if exists vs_contracts_vendor_id_site_id_key;
alter table vs_contracts drop constraint if exists vs_contracts_no_overlap;
alter table vs_contracts add constraint vs_contracts_no_overlap
  exclude using gist (
    site_id with =,
    daterange(from_date, coalesce(to_date, 'infinity'::date), '[]') with &&
  );

alter table vs_profiles
  drop constraint if exists vs_profiles_vendor_fk;
alter table vs_profiles
  add constraint vs_profiles_vendor_fk foreign key (vendor_id) references vs_vendors(id) on delete set null;

-- --------------------------------------------------------------- master lists
-- Booking heads are PER SITE. Every site sheet in the real workbook has its own
-- list (Chirawa splits R&M into "by the OP" and "by WeVois", Bundi has loader and
-- tractor fuel and tractor rent, Jhunjhunu has parking rent, Sujalpur has water
-- and building rent). A new site starts from the template below and is then edited.
create table if not exists vs_head_templates (
  key   text primary key,
  label text not null,
  grp   text not null,
  src   text not null check (src in ('manual','payroll')),
  sort  int  not null default 0
);

insert into vs_head_templates (key,label,grp,src,sort) values
  ('rm',      'R&M Exp.',                        'run',   'manual', 10),
  ('misc',    'Misc. Exp',                       'run',   'manual', 20),
  ('maint_sp','Maint. Exp by Shyam Ji / Punit',  'run',   'manual', 30),
  ('fuel_adj','Fuel Exp. (Adj)',                 'run',   'manual', 40),
  ('print',   'Print Exp',                       'run',   'manual', 50),
  ('fuel',    'Fuel Exp.',                       'run',   'manual', 60),
  ('wages',   'Wages Exp. (Driver / Helper)',    'wages', 'payroll',70),
  ('wages_ee','ESIC / PF - Employee Part',       'wages', 'payroll',80),
  ('wages_er','ESIC / PF - Employer Part',       'wages', 'payroll',90),
  ('salary',  'Salary Exp. (Staff)',             'staff', 'payroll',100),
  ('staff_ee','ESIC / PF - Employee Part',       'staff', 'payroll',110),
  ('staff_er','ESIC / PF - Employer Part',       'staff', 'payroll',120),
  ('other',   'Other Exp',                       'other', 'manual', 130)
on conflict (key) do nothing;

create table if not exists vs_heads (
  id      uuid primary key default gen_random_uuid(),
  site_id uuid not null references vs_sites(id) on delete cascade,
  key     text not null,
  label   text not null,
  grp     text not null default 'run',
  src     text not null check (src in ('manual','payroll')),
  sort    int  not null default 0,
  active  bool not null default true,
  unique (site_id, key)
);

-- Anything that moves the Final amount away from the Total. Open by design:
-- deductions, advances, part payments already made, recoveries, additions back.
-- effect: 'add' credits the OP, 'deduct' reduces what we pay him, and 'note'
-- records the line on the statement WITHOUT moving the Final amount. That last
-- one exists because the real sheet does exactly that in places, and the rule is
-- to record what happened rather than force it into a formula.
create table if not exists vs_adj_types (
  id             uuid primary key default gen_random_uuid(),
  label          text not null,
  effect         text not null default 'deduct' check (effect in ('add','deduct','note')),
  payroll_linked bool not null default false,
  needs_ref      bool not null default false,
  sort           int  not null default 0,
  active         bool not null default true
);

insert into vs_adj_types (label, effect, payroll_linked, needs_ref, sort)
select v.label, v.eff, v.pl, v.nr, v.s from (values
  ('Paid Through OP or Company Exp.',   'add',    false, false, 10),
  ('Salary Not Processed From WeVois',  'add',    true,  false, 20),
  ('Reimbursement to Vendor',           'add',    false, false, 30),
  ('Arrears Payable',                   'add',    false, false, 40),
  ('Extra Amount Per Month',            'add',    false, false, 50),
  ('Direct Payment to OP',              'deduct', false, true,  60),
  ('Paid Through WeVois to OP',         'deduct', false, true,  70),
  ('Advance Paid to Vendor',            'deduct', false, true,  80),
  ('Penalty / Damage Recovery',         'deduct', false, false, 90),
  ('Ward Swipe Penalty',                'deduct', false, false, 100),
  ('Fuel Card Recovery',                'deduct', false, false, 110),
  ('Security Deposit Deduction',        'deduct', false, false, 120),
  ('TDS',                               'deduct', false, false, 130),
  ('Previous Month Balance Recovered',  'deduct', false, false, 140),
  ('Payment Made Against This Bill',    'note',   false, true,  150),
  ('Other Adjustment',                  'deduct', false, false, 200)
) as v(label, eff, pl, nr, s)
where not exists (select 1 from vs_adj_types t where t.label = v.label);

-- ---------------------------------------------------------------- statements
create table if not exists vs_statements (
  id               uuid primary key default gen_random_uuid(),
  contract_id      uuid not null references vs_contracts(id) on delete restrict,
  period           date not null,
  covers_from      date,
  covers_to        date,
  status           text not null default 'draft'
                   check (status in ('draft','sent','under_query','approved','part_paid','paid')),
  due_at           timestamptz,
  approved_at      timestamptz,
  approved_by      text,
  approved_version int,
  approved_amount  numeric(14,2),
  deemed           bool not null default false,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  unique (contract_id, period)
);

create table if not exists vs_versions (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  v            int  not null,
  gross_amount numeric(14,2) not null default 0,
  gross_note   text not null default '',
  sent_at      timestamptz,
  viewed_at    timestamptz,
  note         text not null default '',
  changes      jsonb not null default '[]'::jsonb,
  created_at   timestamptz not null default now(),
  unique (statement_id, v)
);

-- A version freezes the head LABELS too, not just the amounts. Renaming a head
-- next year must not change what a vendor approved last year.
create table if not exists vs_version_lines (
  id         uuid primary key default gen_random_uuid(),
  version_id uuid not null references vs_versions(id) on delete cascade,
  head_id    uuid,
  head_key   text not null,
  head_label text not null default '',
  grp        text not null default 'run',
  src        text not null default 'manual',
  sort       int  not null default 0,
  amount     numeric(14,2) not null default 0,
  unique (version_id, head_key)
);

-- the open adjustment ledger under the Total
create table if not exists vs_version_adj (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references vs_versions(id) on delete cascade,
  adj_type_id uuid references vs_adj_types(id),
  label       text not null,
  effect      text not null default 'deduct' check (effect in ('add','deduct','note')),
  amount      numeric(14,2) not null default 0,
  reference   text not null default '',
  note        text not null default '',
  payroll_linked bool not null default false,
  sort        int not null default 0
);

create table if not exists vs_payroll (
  statement_id         uuid primary key references vs_statements(id) on delete cascade,
  status               text not null default 'pending' check (status in ('pending','posted')),
  posted_by            text,
  posted_at            timestamptz,
  processed_on         date,
  dh_pay      numeric(14,2) not null default 0,
  dh_heads    int not null default 0,
  dh_pf_ee    numeric(14,2) not null default 0,
  dh_pf_er    numeric(14,2) not null default 0,
  dh_esic_ee  numeric(14,2) not null default 0,
  dh_esic_er  numeric(14,2) not null default 0,
  stf_pay     numeric(14,2) not null default 0,
  stf_heads   int not null default 0,
  stf_pf_ee   numeric(14,2) not null default 0,
  stf_pf_er   numeric(14,2) not null default 0,
  stf_esic_ee numeric(14,2) not null default 0,
  stf_esic_er numeric(14,2) not null default 0,
  pf_trrn         text not null default '',
  pf_paid_on      date,
  esic_challan    text not null default '',
  esic_paid_on    date,
  not_processed_amount numeric(14,2) not null default 0,
  not_processed_reason text not null default '',
  pending_fix     jsonb,
  pending_fix_why text,
  pending_fix_by  text,
  pending_fix_at  timestamptz
);

create table if not exists vs_points (
  id            uuid primary key default gen_random_uuid(),
  statement_id  uuid not null references vs_statements(id) on delete cascade,
  target_kind   text not null check (target_kind in ('head','adjustment')),
  target_key    text not null default '',
  target_label  text not null,
  source        text not null check (source in ('portal','call')),
  raised_by     text not null,
  raised_at     timestamptz not null default now(),
  version_no    int  not null,
  claimed       numeric(14,2),
  note          text not null,
  attachment    text not null default '',
  status        text not null default 'open'
                check (status in ('open','awaiting_confirm','disputed_record',
                                  'accepted','partial','rejected','carry_forward')),
  confirmed_at  timestamptz,
  decision      text,
  decided_by    text,
  decided_at    timestamptz,
  new_amount    numeric(14,2),
  published     bool not null default false,
  published_in  int,
  carried_from  uuid
);

create table if not exists vs_payments (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  amount       numeric(14,2) not null check (amount > 0),
  paid_on      date not null,
  utr          text not null,
  mode         text not null default 'NEFT',
  note         text not null default '',
  recorded_by  text not null,
  recorded_at  timestamptz not null default now()
);

create table if not exists vs_events (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  at           timestamptz not null default now(),
  actor_name   text not null,
  actor_role   text not null,
  kind         text not null default '',
  title        text not null,
  body         text not null default ''
);
create index if not exists vs_events_stmt_idx on vs_events (statement_id, at);

-- organisation log. Deliberately NOT tied to vs_statements, so it survives a
-- deleted settlement. Nothing in the app can update or delete a row here.
create table if not exists vs_audit (
  id         uuid primary key default gen_random_uuid(),
  at         timestamptz not null default now(),
  actor_name text not null,
  actor_role text not null,
  title      text not null,
  body       text not null default ''
);

-- ============================================================================
-- helpers
-- ============================================================================

create or replace function vs_role() returns text
language sql stable security definer set search_path = public as $$
  select p.role from vs_profiles p where p.id = auth.uid() and p.active
$$;

create or replace function vs_my_vendor() returns uuid
language sql stable security definer set search_path = public as $$
  select p.vendor_id from vs_profiles p where p.id = auth.uid() and p.active
$$;

create or replace function vs_can(p_cap text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from vs_caps c where c.role = vs_role() and c.cap = p_cap)
$$;

create or replace function vs_require(p_cap text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not vs_can(p_cap) then
    raise exception 'Your role (%) is not allowed to do this (%).', coalesce(vs_role(),'none'), p_cap
      using errcode = '42501';
  end if;
end $$;

create or replace function vs_actor() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.full_name,''), p.email, 'unknown') from vs_profiles p where p.id = auth.uid()
$$;

-- can the caller see this statement at all
create or replace function vs_sees(p_stmt uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when vs_can('view_all') then true
    else exists (
      select 1 from vs_statements s
      join vs_contracts c on c.id = s.contract_id
      where s.id = p_stmt and c.vendor_id = vs_my_vendor() and s.status <> 'draft')
  end
$$;

-- one boolean for the sign-in screen, before anybody is logged in
create or replace function vs_needs_setup() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from vs_profiles)
$$;
grant execute on function vs_needs_setup() to anon, authenticated;

create or replace function vs_period_label(p date) returns text
language sql immutable as $$ select to_char(p, 'FMMonth YYYY') $$;

-- first account created becomes the Admin; after that an account only gets a
-- profile if an unused invite matches its email. No invite -> no profile ->
-- every policy below fails closed and the person sees nothing at all.
create or replace function vs_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare inv vs_invites%rowtype;
begin
  if not exists (select 1 from vs_profiles) then
    insert into vs_profiles (id, full_name, email, role)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email, 'admin');
    insert into vs_audit (actor_name, actor_role, title, body)
    values (coalesce(new.email,'first user'), 'admin', 'First administrator created',
            'Bootstrap account for ' || coalesce(new.email,''));
    return new;
  end if;

  select * into inv from vs_invites
   where lower(email) = lower(new.email) and used_at is null
   order by created_at limit 1;

  if found then
    insert into vs_profiles (id, full_name, email, role, vendor_id)
    values (new.id, coalesce(nullif(inv.full_name,''), coalesce(new.raw_user_meta_data->>'full_name','')),
            new.email, inv.role, inv.vendor_id);
    update vs_invites set used_at = now() where id = inv.id;
  end if;
  return new;
end $$;

drop trigger if exists vs_on_auth_user_created on auth.users;
create trigger vs_on_auth_user_created
  after insert on auth.users
  for each row execute function vs_handle_new_user();

-- ============================================================================
-- row level security
--   SELECT is granted per role below.
--   INSERT / UPDATE / DELETE are granted to NOBODY. Every write in the app goes
--   through a security-definer function further down, which checks capability
--   and the business rules first. A vendor cannot edit a frozen version even by
--   calling the REST API directly, because there is no write policy to use.
-- ============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'vs_settings','vs_caps','vs_profiles','vs_invites','vs_vendors','vs_sites','vs_contracts',
    'vs_heads','vs_head_templates','vs_adj_types','vs_statements','vs_versions','vs_version_lines','vs_version_adj',
    'vs_payroll','vs_points','vs_payments','vs_events','vs_audit']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on table %I from anon, authenticated', t);
    execute format('grant select on table %I to authenticated', t);
  end loop;
end $$;

-- masters: any signed-in person with a profile may read
drop policy if exists p_settings_r on vs_settings;
create policy p_settings_r on vs_settings for select to authenticated using (vs_role() is not null);
drop policy if exists p_caps_r on vs_caps;
create policy p_caps_r on vs_caps for select to authenticated using (vs_role() is not null);
drop policy if exists p_heads_r on vs_heads;
create policy p_heads_r on vs_heads for select to authenticated
  using (vs_can('view_all')
         or exists (select 1 from vs_contracts c where c.site_id = vs_heads.site_id and c.vendor_id = vs_my_vendor()));
drop policy if exists p_headtpl_r on vs_head_templates;
create policy p_headtpl_r on vs_head_templates for select to authenticated using (vs_role() is not null);
drop policy if exists p_adjtypes_r on vs_adj_types;
create policy p_adjtypes_r on vs_adj_types for select to authenticated using (vs_role() is not null);

-- people
drop policy if exists p_profiles_r on vs_profiles;
create policy p_profiles_r on vs_profiles for select to authenticated
  using (vs_can('view_all') or id = auth.uid());

drop policy if exists p_invites_r on vs_invites;
create policy p_invites_r on vs_invites for select to authenticated using (vs_can('manage_users'));

-- vendors / sites / contracts
drop policy if exists p_vendors_r on vs_vendors;
create policy p_vendors_r on vs_vendors for select to authenticated
  using (vs_can('view_all') or id = vs_my_vendor());

drop policy if exists p_sites_r on vs_sites;
create policy p_sites_r on vs_sites for select to authenticated
  using (vs_can('view_all')
         or exists (select 1 from vs_contracts c where c.site_id = vs_sites.id and c.vendor_id = vs_my_vendor()));

drop policy if exists p_contracts_r on vs_contracts;
create policy p_contracts_r on vs_contracts for select to authenticated
  using (vs_can('view_all') or vendor_id = vs_my_vendor());

-- statements and everything hanging off them
drop policy if exists p_stmt_r on vs_statements;
create policy p_stmt_r on vs_statements for select to authenticated
  using (vs_can('view_all')
         or (status <> 'draft'
             and exists (select 1 from vs_contracts c where c.id = contract_id and c.vendor_id = vs_my_vendor())));

drop policy if exists p_ver_r on vs_versions;
create policy p_ver_r on vs_versions for select to authenticated using (vs_sees(statement_id));

drop policy if exists p_vlines_r on vs_version_lines;
create policy p_vlines_r on vs_version_lines for select to authenticated
  using (exists (select 1 from vs_versions v where v.id = version_id and vs_sees(v.statement_id)));

drop policy if exists p_vadj_r on vs_version_adj;
create policy p_vadj_r on vs_version_adj for select to authenticated
  using (exists (select 1 from vs_versions v where v.id = version_id and vs_sees(v.statement_id)));

drop policy if exists p_payroll_r on vs_payroll;
create policy p_payroll_r on vs_payroll for select to authenticated using (vs_sees(statement_id));

drop policy if exists p_points_r on vs_points;
create policy p_points_r on vs_points for select to authenticated using (vs_sees(statement_id));

drop policy if exists p_payments_r on vs_payments;
create policy p_payments_r on vs_payments for select to authenticated using (vs_sees(statement_id));

drop policy if exists p_events_r on vs_events;
create policy p_events_r on vs_events for select to authenticated using (vs_sees(statement_id));

drop policy if exists p_audit_r on vs_audit;
create policy p_audit_r on vs_audit for select to authenticated using (vs_can('view_all'));

-- ============================================================================
-- writes: security definer functions only
-- ============================================================================

create or replace function vs_log(p_stmt uuid, p_kind text, p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into vs_events (statement_id, actor_name, actor_role, kind, title, body)
  values (p_stmt, vs_actor(), coalesce(vs_role(),'?'), p_kind, p_title, coalesce(p_body,''))
$$;

create or replace function vs_audit_log(p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into vs_audit (actor_name, actor_role, title, body)
  values (vs_actor(), coalesce(vs_role(),'?'), p_title, coalesce(p_body,''))
$$;

-- ---- money helpers ---------------------------------------------------------
-- What WeVois spent on the operating partner's behalf this month. This is the
-- "Expenses Paid By Company" memo row in the workbook.
create or replace function vs_version_heads(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount),0) from vs_version_lines where version_id = p_ver
$$;

-- The "Total" row: what the operating partner EARNED for the month, less
-- everything WeVois already spent for him. It goes negative, and that is normal.
create or replace function vs_version_total(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select gross_amount from vs_versions where id = p_ver),0) - vs_version_heads(p_ver)
$$;

-- 'add' credits him, 'deduct' reduces the payment, 'note' is recorded and does
-- not move the figure at all.
create or replace function vs_version_adj_total(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(case effect when 'add' then amount when 'deduct' then -amount else 0 end),0)
    from vs_version_adj where version_id = p_ver
$$;

-- Final Amount For Payment.
create or replace function vs_version_final(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select vs_version_total(p_ver) + vs_version_adj_total(p_ver)
$$;

create or replace function vs_current_version(p_stmt uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from vs_versions where statement_id = p_stmt order by v desc limit 1
$$;

create or replace function vs_paid_total(p_stmt uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount),0) from vs_payments where statement_id = p_stmt
$$;

-- ---- admin: vendors, sites, contracts --------------------------------------
create or replace function vs_add_vendor(p_name text, p_code text, p_contact text, p_email text, p_phone text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid;
begin
  perform vs_require('manage_vendors');
  insert into vs_vendors (name, code, contact_name, contact_email, contact_phone)
  values (p_name, nullif(p_code,''), coalesce(p_contact,''), coalesce(p_email,''), coalesce(p_phone,''))
  returning id into nid;
  perform vs_audit_log('Vendor added', p_name || coalesce(' (' || p_code || ')',''));
  return nid;
end $$;

create or replace function vs_add_site(p_name text, p_city text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid;
begin
  perform vs_require('manage_vendors');
  insert into vs_sites (name, city) values (p_name, coalesce(p_city,'')) returning id into nid;
  insert into vs_heads (site_id, key, label, grp, src, sort)
    select nid, key, label, grp, src, sort from vs_head_templates;
  perform vs_audit_log('Site added', p_name || ' (started with the standard booking heads)');
  return nid;
end $$;

create or replace function vs_add_head(p_site uuid, p_key text, p_label text, p_grp text, p_src text, p_sort int)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid;
begin
  perform vs_require('manage_masters');
  insert into vs_heads (site_id, key, label, grp, src, sort)
  values (p_site, p_key, p_label, coalesce(nullif(p_grp,''),'run'), coalesce(nullif(p_src,''),'manual'), coalesce(p_sort,900))
  returning id into nid;
  perform vs_audit_log('Booking head added',
    p_label || ' at ' || (select name from vs_sites where id = p_site));
  return nid;
end $$;

create or replace function vs_set_head(p_head uuid, p_label text, p_sort int, p_active bool)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vs_require('manage_masters');
  update vs_heads set label = coalesce(nullif(p_label,''), label),
                      sort = coalesce(p_sort, sort),
                      active = coalesce(p_active, active)
   where id = p_head;
  perform vs_audit_log('Booking head changed', coalesce(p_label,'') ||
    ' at ' || (select st.name from vs_heads h join vs_sites st on st.id = h.site_id where h.id = p_head));
end $$;

create or replace function vs_add_contract(p_vendor uuid, p_site uuid, p_vehicles int,
                                          p_from date default null, p_to date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; vn text; sn text; f date; t date; clash text;
begin
  perform vs_require('manage_contracts');
  if p_vehicles is null or p_vehicles < 1 then
    raise exception 'Vehicle count must be at least 1.' using errcode = '22023';
  end if;
  f := coalesce(p_from, current_date);
  t := p_to;

  select v.name || ' (' || to_char(c.from_date,'DD Mon YYYY') || ' to ' ||
         coalesce(to_char(c.to_date,'DD Mon YYYY'), 'current') || ')'
    into clash
    from vs_contracts c join vs_vendors v on v.id = c.vendor_id
   where c.site_id = p_site
     and daterange(c.from_date, coalesce(c.to_date,'infinity'::date), '[]')
      && daterange(f, coalesce(t,'infinity'::date), '[]')
   limit 1;
  if clash is not null then
    raise exception 'This site is already held over that period by %. End that tenure first.', clash
      using errcode = '23P01';
  end if;

  insert into vs_contracts (vendor_id, site_id, vehicles, from_date, to_date)
  values (p_vendor, p_site, p_vehicles, f, t) returning id into nid;
  select name into vn from vs_vendors where id = p_vendor;
  select name into sn from vs_sites   where id = p_site;
  perform vs_audit_log('Site assigned',
    vn || ' holds ' || sn || ' with ' || p_vehicles || ' vehicles from ' || to_char(f,'DD Mon YYYY')
    || coalesce(' to ' || to_char(t,'DD Mon YYYY'), ''));
  return nid;
end $$;

-- The vendor at a site changes. End the old tenure at p_last_period and start
-- the new one the month after. Everything already settled under the old vendor
-- stays exactly where it is.
create or replace function vs_end_contract(p_contract uuid, p_last_date date)
returns void language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; n int; vn text; sn text;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such contract.' using errcode='02000'; end if;
  if p_last_date < c.from_date then
    raise exception 'The last day cannot be before the tenure started (%).', to_char(c.from_date,'DD Mon YYYY')
      using errcode='22023';
  end if;
  select count(*) into n from vs_statements
   where contract_id = p_contract and period > date_trunc('month', p_last_date)::date;
  if n > 0 then
    raise exception 'There are % settlement(s) for this vendor after %. Delete those first.',
      n, to_char(p_last_date,'Mon YYYY') using errcode='23503';
  end if;
  update vs_contracts set to_date = p_last_date where id = p_contract;
  select v.name, s.name into vn, sn from vs_vendors v, vs_sites s where v.id = c.vendor_id and s.id = c.site_id;
  perform vs_audit_log('Tenure ended', vn || ' ran ' || sn || ' until ' || to_char(p_last_date,'DD Mon YYYY'));
end $$;

-- The handover. p_from is the exact day the new vendor takes over - it does not
-- have to be the 1st. Nawa really did change hands on 16 April, mid month.
create or replace function vs_change_vendor(p_site uuid, p_new_vendor uuid, p_vehicles int, p_from date)
returns uuid language plpgsql security definer set search_path = public as $$
declare cur vs_contracts%rowtype; nid uuid; oldv text; newv text; sn text;
begin
  perform vs_require('manage_contracts');
  select * into cur from vs_contracts where site_id = p_site and to_date is null;
  if found then
    if p_from <= cur.from_date then
      raise exception 'The new vendor cannot start on or before the day the previous one started (%).',
        to_char(cur.from_date,'DD Mon YYYY') using errcode='22023';
    end if;
    perform vs_end_contract(cur.id, p_from - 1);
    select name into oldv from vs_vendors where id = cur.vendor_id;
  end if;
  nid := vs_add_contract(p_new_vendor, p_site, p_vehicles, p_from, null);
  select name into newv from vs_vendors where id = p_new_vendor;
  select name into sn from vs_sites where id = p_site;
  perform vs_audit_log('Vendor changed at a site',
    sn || ': ' || coalesce(oldv,'(none)') || ' -> ' || newv || ' from ' || to_char(p_from,'DD Mon YYYY'));
  return nid;
end $$;

-- which contract was running this site in this month
create or replace function vs_contract_at(p_site uuid, p_on date) returns uuid
language sql stable security definer set search_path = public as $$
  select id from vs_contracts
   where site_id = p_site and p_on between from_date and coalesce(to_date,'infinity'::date)
   limit 1
$$;

create or replace function vs_site_history(p_site uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'contract_id', c.id, 'vendor_id', v.id, 'vendor_name', v.name, 'vehicles', c.vehicles,
    'from_date', c.from_date, 'to_date', c.to_date,
    'from_label', to_char(c.from_date,'DD Mon YYYY'),
    'to_label', coalesce(to_char(c.to_date,'DD Mon YYYY'),'current'),
    'settlements', (select count(*) from vs_statements s where s.contract_id = c.id)
  ) order by c.from_date), '[]'::jsonb)
  from vs_contracts c join vs_vendors v on v.id = c.vendor_id
  where c.site_id = p_site
$$;

create or replace function vs_remove_contract(p_contract uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n int; vn text; sn text;
begin
  perform vs_require('manage_contracts');
  select count(*) into n from vs_statements where contract_id = p_contract;
  if n > 0 then
    raise exception 'This tenure still has % settlement(s). End it with a last month instead, or delete those settlements first.', n
      using errcode = '23503';
  end if;
  select v.name, s.name into vn, sn
    from vs_contracts c join vs_vendors v on v.id = c.vendor_id join vs_sites s on s.id = c.site_id
   where c.id = p_contract;
  delete from vs_contracts where id = p_contract;
  perform vs_audit_log('Site unassigned', vn || ' removed from ' || sn);
end $$;

create or replace function vs_set_contract_vehicles(p_contract uuid, p_vehicles int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vs_require('manage_contracts');
  if p_vehicles < 1 then raise exception 'Vehicle count must be at least 1.' using errcode='22023'; end if;
  update vs_contracts set vehicles = p_vehicles where id = p_contract;
  perform vs_audit_log('Vehicle count changed', 'Contract set to ' || p_vehicles || ' vehicles');
end $$;

-- ---- admin: people ---------------------------------------------------------
create or replace function vs_invite(p_email text, p_name text, p_role text, p_vendor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid;
begin
  perform vs_require('manage_users');
  if p_role = 'vendor' and p_vendor is null then
    raise exception 'A vendor login must be tied to a vendor.' using errcode='22023';
  end if;
  if p_role <> 'vendor' and p_vendor is not null then
    raise exception 'Only a vendor login can be tied to a vendor.' using errcode='22023';
  end if;
  insert into vs_invites (email, full_name, role, vendor_id, created_by)
  values (lower(p_email), coalesce(p_name,''), p_role, p_vendor, auth.uid())
  returning id into nid;
  perform vs_audit_log('Person invited', coalesce(p_name,'') || ' <' || lower(p_email) || '> as ' || p_role);
  return nid;
end $$;

create or replace function vs_set_role(p_profile uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare admins int; old_role text; nm text;
begin
  perform vs_require('manage_users');
  select role, full_name into old_role, nm from vs_profiles where id = p_profile;
  if old_role = 'admin' and p_role <> 'admin' then
    select count(*) into admins from vs_profiles where role = 'admin' and active;
    if admins <= 1 then raise exception 'Cannot remove the last administrator.' using errcode='23514'; end if;
  end if;
  update vs_profiles set role = p_role, vendor_id = case when p_role = 'vendor' then vendor_id else null end
   where id = p_profile;
  perform vs_audit_log('Role changed', coalesce(nm,'') || ': ' || old_role || ' -> ' || p_role);
end $$;

create or replace function vs_set_active(p_profile uuid, p_active bool)
returns void language plpgsql security definer set search_path = public as $$
declare nm text; admins int;
begin
  perform vs_require('manage_users');
  select full_name into nm from vs_profiles where id = p_profile;
  if not p_active then
    select count(*) into admins from vs_profiles where role = 'admin' and active and id <> p_profile;
    if admins = 0 and (select role from vs_profiles where id = p_profile) = 'admin' then
      raise exception 'Cannot deactivate the last administrator.' using errcode='23514';
    end if;
  end if;
  update vs_profiles set active = p_active where id = p_profile;
  perform vs_audit_log(case when p_active then 'Person reactivated' else 'Person deactivated' end, coalesce(nm,''));
end $$;

create or replace function vs_save_settings(p_days int, p_deemed bool, p_var numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vs_require('manage_masters');
  update vs_settings set window_days = p_days, deemed_approve = p_deemed, variance_pct = p_var where id = 1;
  perform vs_audit_log('Settlement rules changed',
    'window ' || p_days || ' days, deemed-approve ' || p_deemed || ', variance ' || p_var || '%');
end $$;

create or replace function vs_add_adj_type(p_label text, p_effect text, p_needs_ref bool)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid;
begin
  perform vs_require('manage_masters');
  insert into vs_adj_types (label, effect, needs_ref, sort)
  values (p_label, coalesce(p_effect,'deduct'), coalesce(p_needs_ref,false), 150) returning id into nid;
  perform vs_audit_log('Adjustment type added', p_label || ' (' || coalesce(p_effect,'deduct') || ')');
  return nid;
end $$;

-- ---- admin: settlement lifecycle ------------------------------------------
create or replace function vs_add_statement(p_contract uuid, p_period date)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid; vid uuid; per date; lbl text;
begin
  perform vs_require('manage_settlements');
  per := date_trunc('month', p_period)::date;
  if not exists (select 1 from vs_contracts c where c.id = p_contract
                  and daterange(c.from_date, coalesce(c.to_date,'infinity'::date), '[]')
                   && daterange(per, (per + interval '1 month - 1 day')::date, '[]')) then
    raise exception 'That vendor was not running this site in %.', vs_period_label(per) using errcode = '22023';
  end if;
  if exists (select 1 from vs_statements where contract_id = p_contract and period = per) then
    raise exception 'That vendor and site already has a settlement for %.', vs_period_label(per)
      using errcode = '23505';
  end if;
  -- a handover month is settled only for the days that vendor actually ran
  insert into vs_statements (contract_id, period, covers_from, covers_to, created_by)
  select p_contract, per,
         greatest(c.from_date, per),
         least(coalesce(c.to_date,'infinity'::date), (per + interval '1 month - 1 day')::date),
         auth.uid()
    from vs_contracts c where c.id = p_contract
  returning id into sid;
  insert into vs_versions (statement_id, v) values (sid, 1) returning id into vid;
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount)
    select vid, h.id, h.key, h.label, h.grp, h.src, h.sort, 0
      from vs_heads h join vs_contracts c on c.site_id = h.site_id
     where c.id = p_contract and h.active;
  insert into vs_payroll (statement_id) values (sid);
  select v.name || ' - ' || s.name into lbl
    from vs_contracts c join vs_vendors v on v.id = c.vendor_id join vs_sites s on s.id = c.site_id
   where c.id = p_contract;
  perform vs_log(sid, 'hi', 'Settlement opened for ' || vs_period_label(per),
    'Created by the administrator for ' || lbl || '. Heads start at zero; Accounts posts the payroll, the vendor manager fills the running heads.');
  perform vs_audit_log('Settlement opened', lbl || ' - ' || vs_period_label(per));
  return sid;
end $$;

create or replace function vs_open_month(p_period date)
returns int language plpgsql security definer set search_path = public as $$
declare c record; n int := 0; per date;
begin
  perform vs_require('manage_settlements');
  per := date_trunc('month', p_period)::date;
  for c in select id from vs_contracts
           where daterange(from_date, coalesce(to_date,'infinity'::date), '[]')
              && daterange(per, (per + interval '1 month - 1 day')::date, '[]')
             and not exists (select 1 from vs_statements s where s.contract_id = vs_contracts.id and s.period = per)
  loop
    perform vs_add_statement(c.id, per);
    n := n + 1;
  end loop;
  if n > 0 then
    perform vs_audit_log('Month opened', n || ' settlement(s) created for ' || vs_period_label(per));
  end if;
  return n;
end $$;

create or replace function vs_delete_statement(p_stmt uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare d text; st vs_statements%rowtype; nv int; np int; ne int; pay text;
begin
  perform vs_require('manage_settlements');
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required. It is the only thing that survives the deletion.' using errcode='22023';
  end if;
  select * into st from vs_statements where id = p_stmt;
  if not found then raise exception 'No such settlement.' using errcode='02000'; end if;
  select count(*) into nv from vs_versions where statement_id = p_stmt;
  select count(*) into np from vs_points   where statement_id = p_stmt;
  select count(*) into ne from vs_events   where statement_id = p_stmt;
  select string_agg(utr || ' ' || amount::text, ', ') into pay from vs_payments where statement_id = p_stmt;
  select v.name || ' - ' || s.name || ', ' || vs_period_label(st.period) into d
    from vs_contracts c join vs_vendors v on v.id = c.vendor_id join vs_sites s on s.id = c.site_id
   where c.id = st.contract_id;
  delete from vs_statements where id = p_stmt;
  perform vs_audit_log('Settlement DELETED',
    d || ' (status ' || st.status || ', ' || nv || ' versions, ' || np || ' points, ' || ne || ' record entries'
      || coalesce(', payments ' || pay, '') || '). Reason: ' || p_reason);
end $$;

-- ---- vendor manager: the draft --------------------------------------------
-- p_gross is "Total Expenses Should Be Paid" - what the operating partner earned
-- this month. It is typed in, exactly as it is in the workbook today.
create or replace function vs_save_draft(p_stmt uuid, p_gross numeric, p_gross_note text,
                                         p_lines jsonb, p_adj jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare vid uuid; st text; k text; a jsonb; i int := 0;
begin
  perform vs_require('edit_draft');
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st <> 'draft' then
    raise exception 'This version has already gone to the vendor. It is frozen; corrections go out as a new version.'
      using errcode='42501';
  end if;
  vid := vs_current_version(p_stmt);

  update vs_versions set gross_amount = coalesce(p_gross, gross_amount),
                         gross_note   = coalesce(p_gross_note, gross_note)
   where id = vid;

  for k in select jsonb_object_keys(coalesce(p_lines,'{}'::jsonb)) loop
    update vs_version_lines set amount = (p_lines ->> k)::numeric
     where version_id = vid and head_key = k and src = 'manual';
  end loop;

  if p_adj is not null then
    delete from vs_version_adj where version_id = vid and not payroll_linked;
    for a in select * from jsonb_array_elements(p_adj) loop
      i := i + 1;
      insert into vs_version_adj (version_id, adj_type_id, label, effect, amount, reference, note, sort)
      values (vid, nullif(a->>'adj_type_id','')::uuid, a->>'label',
              coalesce(a->>'effect','deduct'), (a->>'amount')::numeric,
              coalesce(a->>'reference',''), coalesce(a->>'note',''), i * 10);
    end loop;
  end if;
end $$;

-- ---- accounts: payroll -----------------------------------------------------
create or replace function vs_post_payroll(p_stmt uuid, p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare vid uuid; st text; already bool; ch jsonb := '[]'::jsonb; nowline numeric;
        was_np numeric; det text; np_label text := 'Salary Not Processed From WeVois';
        np_type uuid; heads int;
begin
  perform vs_require('post_payroll');
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st = 'paid' then raise exception 'This settlement is closed.' using errcode='42501'; end if;

  if coalesce(p->>'pf_trrn','') = '' or coalesce(p->>'esic_challan','') = '' then
    raise exception 'PF TRRN and ESIC challan number are both required. They are what the vendor verifies against.'
      using errcode='22023';
  end if;
  if (p->>'not_processed_amount')::numeric > 0 and coalesce(p->>'not_processed_reason','') = '' then
    raise exception 'A reason is required for salary not processed from WeVois.' using errcode='22023';
  end if;

  select (status = 'posted') into already from vs_payroll where statement_id = p_stmt;
  vid := vs_current_version(p_stmt);
  select amount into was_np from vs_version_adj where version_id = vid and payroll_linked limit 1;

  update vs_payroll set
    status='posted', posted_by = vs_actor(), posted_at = now(),
    processed_on = nullif(p->>'processed_on','')::date,
    dh_pay=(p->>'dh_pay')::numeric, dh_heads=(p->>'dh_heads')::int,
    dh_pf_ee=(p->>'dh_pf_ee')::numeric, dh_pf_er=(p->>'dh_pf_er')::numeric,
    dh_esic_ee=(p->>'dh_esic_ee')::numeric, dh_esic_er=(p->>'dh_esic_er')::numeric,
    stf_pay=(p->>'stf_pay')::numeric, stf_heads=(p->>'stf_heads')::int,
    stf_pf_ee=(p->>'stf_pf_ee')::numeric, stf_pf_er=(p->>'stf_pf_er')::numeric,
    stf_esic_ee=(p->>'stf_esic_ee')::numeric, stf_esic_er=(p->>'stf_esic_er')::numeric,
    pf_trrn=p->>'pf_trrn', pf_paid_on=nullif(p->>'pf_paid_on','')::date,
    esic_challan=p->>'esic_challan', esic_paid_on=nullif(p->>'esic_paid_on','')::date,
    not_processed_amount=(p->>'not_processed_amount')::numeric,
    not_processed_reason=coalesce(p->>'not_processed_reason','')
  where statement_id = p_stmt;

  select dh_heads + stf_heads into heads from vs_payroll where statement_id = p_stmt;
  det := heads || ' persons. Wages ' || (p->>'dh_pay') || ', staff salary ' || (p->>'stf_pay')
       || '. PF TRRN ' || (p->>'pf_trrn') || ', ESIC challan ' || (p->>'esic_challan')
       || '. Not processed from WeVois ' || (p->>'not_processed_amount') || '.';

  if not already and st = 'draft' then
    perform vs_apply_payroll(p_stmt, vid);
    perform vs_log(p_stmt, 'pay', 'Payroll posted for ' ||
      vs_period_label((select period from vs_statements where id = p_stmt)), det);
    return 'posted';
  end if;

  -- correction after the statement has gone out: park it, do not touch the frozen version
  ch := vs_payroll_diff(p_stmt, vid);
  if jsonb_array_length(ch) = 0 then
    perform vs_log(p_stmt, 'pay', 'Payroll re-posted', det || ' No figure changed.');
    return 'nochange';
  end if;
  update vs_payroll set pending_fix = ch,
    pending_fix_why = jsonb_array_length(ch) || ' manpower figure(s) corrected after the statement went out.',
    pending_fix_by = vs_actor(), pending_fix_at = now()
   where statement_id = p_stmt;
  perform vs_log(p_stmt, 'pay', 'Payroll correction posted', det || ' Reaches the vendor with the next version.');
  return 'parked';
end $$;

-- write the six derived heads and the payroll-linked adjustment into a version
create or replace function vs_apply_payroll(p_stmt uuid, p_ver uuid)
returns void language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype; t uuid;
begin
  select * into pr from vs_payroll where statement_id = p_stmt;
  update vs_version_lines set amount = pr.dh_pay                     where version_id = p_ver and head_key='wages';
  update vs_version_lines set amount = pr.dh_pf_ee + pr.dh_esic_ee   where version_id = p_ver and head_key='wages_ee';
  update vs_version_lines set amount = pr.dh_pf_er + pr.dh_esic_er   where version_id = p_ver and head_key='wages_er';
  update vs_version_lines set amount = pr.stf_pay                    where version_id = p_ver and head_key='salary';
  update vs_version_lines set amount = pr.stf_pf_ee + pr.stf_esic_ee where version_id = p_ver and head_key='staff_ee';
  update vs_version_lines set amount = pr.stf_pf_er + pr.stf_esic_er where version_id = p_ver and head_key='staff_er';

  select id into t from vs_adj_types where payroll_linked limit 1;
  delete from vs_version_adj where version_id = p_ver and payroll_linked;
  if pr.not_processed_amount <> 0 then
    -- WeVois did not actually pay this salary, so it is credited back to the OP
    insert into vs_version_adj (version_id, adj_type_id, label, effect, amount, note, payroll_linked, sort)
    values (p_ver, t, 'Salary Not Processed From WeVois', 'add', pr.not_processed_amount,
            pr.not_processed_reason, true, 5);
  end if;
end $$;

create or replace function vs_payroll_diff(p_stmt uuid, p_ver uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype; out jsonb := '[]'::jsonb; cur numeric;
begin
  select * into pr from vs_payroll where statement_id = p_stmt;
  -- head by head
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages';
  if cur is distinct from pr.dh_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages','from',cur,'to',pr.dh_pay,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_ee';
  if cur is distinct from pr.dh_pf_ee + pr.dh_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_ee','from',cur,'to',pr.dh_pf_ee+pr.dh_esic_ee,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_er';
  if cur is distinct from pr.dh_pf_er + pr.dh_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_er','from',cur,'to',pr.dh_pf_er+pr.dh_esic_er,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='salary';
  if cur is distinct from pr.stf_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','salary','from',cur,'to',pr.stf_pay,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_ee';
  if cur is distinct from pr.stf_pf_ee + pr.stf_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_ee','from',cur,'to',pr.stf_pf_ee+pr.stf_esic_ee,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_er';
  if cur is distinct from pr.stf_pf_er + pr.stf_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_er','from',cur,'to',pr.stf_pf_er+pr.stf_esic_er,'why','Payroll correction posted by Accounts.')); end if;
  -- the payroll-linked adjustment
  select coalesce(amount,0) into cur from vs_version_adj where version_id=p_ver and payroll_linked;
  if coalesce(cur,0) is distinct from pr.not_processed_amount then out := out || jsonb_build_array(jsonb_build_object(
    'kind','adj','key','not_processed','from',coalesce(cur,0),'to',pr.not_processed_amount,
    'why','Payroll correction posted by Accounts.')); end if;
  return out;
end $$;

-- ---- vendor manager: share, points, revisions ------------------------------
create or replace function vs_share(p_stmt uuid)
returns void language plpgsql security definer set search_path = public as $$
declare st text; pr text; vid uuid; d int;
begin
  perform vs_require('share');
  select status into st from vs_statements where id = p_stmt;
  select status into pr from vs_payroll    where statement_id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st <> 'draft' then raise exception 'Only a draft can be shared.' using errcode='42501'; end if;
  if pr <> 'posted' then
    raise exception 'Accounts has not posted the payroll for this month yet. The statement cannot go out until they do.'
      using errcode='42501';
  end if;
  vid := vs_current_version(p_stmt);
  select window_days into d from vs_settings where id = 1;
  update vs_versions set sent_at = now() where id = vid;
  update vs_statements set status = 'sent', due_at = now() + (d + 2) * interval '1 day' where id = p_stmt;
  perform vs_log(p_stmt, 'hi', 'Statement v' || (select v from vs_versions where id=vid) || ' shared',
    'Final amount ' || vs_version_final(vid) || '. Response window ' || d || ' working days.');
end $$;

create or replace function vs_mark_viewed(p_stmt uuid)
returns void language plpgsql security definer set search_path = public as $$
declare vid uuid; already timestamptz;
begin
  if not vs_sees(p_stmt) then return; end if;
  if vs_role() <> 'vendor' then return; end if;
  vid := vs_current_version(p_stmt);
  select viewed_at into already from vs_versions where id = vid;
  if already is null then
    update vs_versions set viewed_at = now() where id = vid;
    perform vs_log(p_stmt, '', 'Vendor opened the statement',
      'First view of version ' || (select v from vs_versions where id = vid) || '.');
  end if;
end $$;

create or replace function vs_raise_point(p_stmt uuid, p_kind text, p_key text, p_label text,
                                          p_claimed numeric, p_note text, p_attach text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; st text; vno int; mine bool;
begin
  perform vs_require('raise');
  select s.status, exists(select 1 from vs_contracts c where c.id = s.contract_id and c.vendor_id = vs_my_vendor())
    into st, mine from vs_statements s where s.id = p_stmt;
  if not coalesce(mine,false) then raise exception 'That is not your statement.' using errcode='42501'; end if;
  if st not in ('sent','under_query') then
    raise exception 'You can only raise a point while the statement is open for response.' using errcode='42501';
  end if;
  if coalesce(trim(p_note),'') = '' then
    raise exception 'Describe the issue. That text is the record.' using errcode='22023';
  end if;
  select v into vno from vs_versions where id = vs_current_version(p_stmt);
  insert into vs_points (statement_id, target_kind, target_key, target_label, source, raised_by,
                         version_no, claimed, note, attachment, status)
  values (p_stmt, p_kind, coalesce(p_key,''), p_label, 'portal', vs_actor(), vno,
          p_claimed, p_note, coalesce(p_attach,''), 'open')
  returning id into nid;
  update vs_statements set status = 'under_query' where id = p_stmt;
  perform vs_log(p_stmt, 'warn', 'Point raised on ' || p_label,
    coalesce('Claimed ' || p_claimed || '. ','') || '"' || p_note || '"' ||
    coalesce(' Attachment: ' || nullif(p_attach,''), ''));
  return nid;
end $$;

create or replace function vs_log_call_point(p_stmt uuid, p_kind text, p_key text, p_label text,
                                             p_claimed numeric, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; st text; vno int; who text;
begin
  perform vs_require('logcall');
  select status into st from vs_statements where id = p_stmt;
  if st not in ('sent','under_query') then
    raise exception 'The statement must be with the vendor to log a point against it.' using errcode='42501';
  end if;
  if coalesce(trim(p_note),'') = '' then
    raise exception 'Write down what he said. That is the whole point.' using errcode='22023';
  end if;
  select v.contact_name into who from vs_statements s
    join vs_contracts c on c.id = s.contract_id join vs_vendors v on v.id = c.vendor_id where s.id = p_stmt;
  select v into vno from vs_versions where id = vs_current_version(p_stmt);
  insert into vs_points (statement_id, target_kind, target_key, target_label, source, raised_by,
                         version_no, claimed, note, status)
  values (p_stmt, p_kind, coalesce(p_key,''), p_label, 'call',
          coalesce(who,'vendor') || ' (by phone, logged by ' || vs_actor() || ')', vno, p_claimed, p_note,
          'awaiting_confirm')
  returning id into nid;
  update vs_statements set status = 'under_query' where id = p_stmt;
  perform vs_log(p_stmt, 'warn', 'Point logged from phone call - ' || p_label,
    '"' || p_note || '" Sent to the vendor for confirmation.');
  return nid;
end $$;

create or replace function vs_confirm_call_point(p_point uuid, p_ok bool)
returns void language plpgsql security definer set search_path = public as $$
declare pt vs_points%rowtype; mine bool;
begin
  perform vs_require('confirm');
  select * into pt from vs_points where id = p_point;
  if not found then raise exception 'No such point.' using errcode='02000'; end if;
  select exists(select 1 from vs_statements s join vs_contracts c on c.id = s.contract_id
                 where s.id = pt.statement_id and c.vendor_id = vs_my_vendor()) into mine;
  if not mine then raise exception 'That is not your statement.' using errcode='42501'; end if;
  if pt.status <> 'awaiting_confirm' then
    raise exception 'That point is not waiting for your confirmation.' using errcode='42501';
  end if;
  if p_ok then
    update vs_points set status='open', confirmed_at=now() where id = p_point;
    perform vs_log(pt.statement_id, '', 'Vendor confirmed the phone point',
      '"Yes, this is what I said." The point is now live with WeVois.');
  else
    update vs_points set status='disputed_record', confirmed_at=now(),
      decision='Vendor says the written record does not match what he said. To be re-logged after speaking again.',
      decided_by='system', decided_at=now() where id = p_point;
    perform vs_log(pt.statement_id, 'warn', 'Vendor says the phone note is not what he said',
      'Point parked. Speak again and log it afresh.');
  end if;
end $$;

create or replace function vs_resolve_point(p_point uuid, p_decision text, p_amount numeric, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare pt vs_points%rowtype;
begin
  perform vs_require('resolve');
  select * into pt from vs_points where id = p_point;
  if not found then raise exception 'No such point.' using errcode='02000'; end if;
  if pt.status <> 'open' then raise exception 'Only an open point can be resolved.' using errcode='42501'; end if;
  if p_decision not in ('accepted','partial','rejected','carry_forward') then
    raise exception 'Unknown decision.' using errcode='22023';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is compulsory. It is what stops the same argument next month.' using errcode='22023';
  end if;
  update vs_points set status = p_decision, decision = p_reason, decided_by = vs_actor(),
         decided_at = now(), published = false,
         new_amount = case when p_decision in ('accepted','partial') then p_amount else null end
   where id = p_point;
  perform vs_log(pt.statement_id, case when p_decision='rejected' then '' else 'ok' end,
    'Point ' || replace(p_decision,'_',' ') || ' - ' || pt.target_label, p_reason);
end $$;

create or replace function vs_issue_revision(p_stmt uuid)
returns int language plpgsql security definer set search_path = public as $$
declare oldv uuid; oldn int; newv uuid; ch jsonb := '[]'::jsonb; n int := 0;
        pt record; fix jsonb; e jsonb; d int; opencount int;
begin
  perform vs_require('revise');
  oldv := vs_current_version(p_stmt);
  select v into oldn from vs_versions where id = oldv;

  select pending_fix into fix from vs_payroll where statement_id = p_stmt;
  if fix is not null and jsonb_array_length(fix) > 0 then n := n + 1; end if;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and not published
     and status in ('accepted','partial','rejected','carry_forward','disputed_record');
  n := n + opencount;
  if n = 0 then raise exception 'Nothing has been decided yet.' using errcode='22023'; end if;

  insert into vs_versions (statement_id, v, gross_amount, gross_note, sent_at)
    select p_stmt, oldn + 1, gross_amount, gross_note, now() from vs_versions where id = oldv
  returning id into newv;
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount)
    select newv, head_id, head_key, head_label, grp, src, sort, amount
      from vs_version_lines where version_id = oldv;
  insert into vs_version_adj (version_id, adj_type_id, label, effect, amount, reference, note, payroll_linked, sort)
    select newv, adj_type_id, label, effect, amount, reference, note, payroll_linked, sort
      from vs_version_adj where version_id = oldv;

  -- payroll correction first
  if fix is not null then
    for e in select * from jsonb_array_elements(fix) loop
      if e->>'kind' = 'head' then
        update vs_version_lines set amount = (e->>'to')::numeric where version_id = newv and head_key = e->>'key';
        ch := ch || jsonb_build_array(jsonb_build_object('label',
          (select head_label from vs_version_lines where version_id = newv and head_key = e->>'key'),
          'from', e->'from', 'to', e->'to', 'why', e->>'why'));
      else
        perform vs_apply_payroll(p_stmt, newv);
        ch := ch || jsonb_build_array(jsonb_build_object('label','Salary Not Processed From WeVois',
          'from', e->'from', 'to', e->'to', 'why', e->>'why'));
      end if;
    end loop;
    update vs_payroll set pending_fix = null, pending_fix_why = null, pending_fix_by = null, pending_fix_at = null
     where statement_id = p_stmt;
  end if;

  -- accepted points: manual heads and adjustment lines only. A payroll head can
  -- only move through an Accounts correction, which is handled above.
  for pt in select * from vs_points where statement_id = p_stmt and not published
             and status in ('accepted','partial','rejected','carry_forward','disputed_record')
  loop
    if pt.status in ('accepted','partial') then
      if pt.target_kind = 'head'
         and exists (select 1 from vs_version_lines
                      where version_id = newv and head_key = pt.target_key and src = 'manual') then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_lines where version_id=newv and head_key=pt.target_key),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_lines set amount = pt.new_amount where version_id = newv and head_key = pt.target_key;
      elsif pt.target_kind = 'adjustment' then
        -- adjustment rows are copied into each new version with fresh ids, so a
        -- point is matched back by its label, which is what the vendor saw
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_adj where version_id=newv and label=pt.target_label),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_adj set amount = pt.new_amount
         where version_id = newv and label = pt.target_label;
      end if;
    end if;
    update vs_points set published = true, published_in = oldn + 1 where id = pt.id;
  end loop;

  update vs_versions set changes = ch,
    note = n || ' item(s) answered. ' || jsonb_array_length(ch) || ' amount(s) changed.'
   where id = newv;

  select window_days into d from vs_settings where id = 1;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and status in ('open','awaiting_confirm');
  update vs_statements
     set status = case when opencount > 0 then 'under_query' else 'sent' end,
         due_at = now() + (d + 2) * interval '1 day'
   where id = p_stmt;

  perform vs_log(p_stmt, 'hi', 'Statement v' || (oldn + 1) || ' shared',
    jsonb_array_length(ch) || ' amount change(s) from v' || oldn ||
    '. New final amount ' || vs_version_final(newv) || '.');
  return oldn + 1;
end $$;

-- ---- vendor: approval ------------------------------------------------------
create or replace function vs_approve(p_stmt uuid)
returns numeric language plpgsql security definer set search_path = public as $$
declare mine bool; st text; vid uuid; vno int; amt numeric; opencount int;
begin
  perform vs_require('approve');
  select s.status, exists(select 1 from vs_contracts c where c.id = s.contract_id and c.vendor_id = vs_my_vendor())
    into st, mine from vs_statements s where s.id = p_stmt;
  if not coalesce(mine,false) then raise exception 'That is not your statement.' using errcode='42501'; end if;
  if st not in ('sent','under_query') then
    raise exception 'This statement is not open for approval.' using errcode='42501';
  end if;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and status in ('open','awaiting_confirm');
  if opencount > 0 then
    raise exception 'You have % point(s) still open. Approval opens once WeVois has answered them.', opencount
      using errcode='42501';
  end if;
  vid := vs_current_version(p_stmt);
  select v into vno from vs_versions where id = vid;
  amt := vs_version_final(vid);
  update vs_statements set status='approved', approved_at=now(), approved_by=vs_actor(),
         approved_version=vno, approved_amount=amt where id = p_stmt;
  perform vs_log(p_stmt, 'ok', 'Vendor APPROVED v' || vno,
    amt || ' accepted as full and final for ' ||
    vs_period_label((select period from vs_statements where id=p_stmt)) ||
    '. Snapshot locked. Sent to Accounts for payment.');
  return amt;
end $$;

-- ---- accounts: part payments ----------------------------------------------
create or replace function vs_record_payment(p_stmt uuid, p_amount numeric, p_on date,
                                             p_utr text, p_mode text, p_note text)
returns numeric language plpgsql security definer set search_path = public as $$
declare st vs_statements%rowtype; paid numeric; bal numeric;
begin
  perform vs_require('pay');
  select * into st from vs_statements where id = p_stmt;
  if not found then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st.status not in ('approved','part_paid') then
    raise exception 'Money can only move against a settlement the vendor has approved.' using errcode='42501';
  end if;
  if coalesce(trim(p_utr),'') = '' then
    raise exception 'A UTR or reference is required. It is what the vendor sees.' using errcode='22023';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be more than zero.' using errcode='22023';
  end if;
  paid := vs_paid_total(p_stmt);
  if paid + p_amount > st.approved_amount + 0.005 then
    raise exception 'That would pay % against an approved amount of % (already paid %).',
      paid + p_amount, st.approved_amount, paid using errcode='22023';
  end if;
  insert into vs_payments (statement_id, amount, paid_on, utr, mode, note, recorded_by)
  values (p_stmt, p_amount, p_on, p_utr, coalesce(nullif(p_mode,''),'NEFT'), coalesce(p_note,''), vs_actor());
  paid := vs_paid_total(p_stmt);
  bal := st.approved_amount - paid;
  update vs_statements set status = case when bal <= 0.005 then 'paid' else 'part_paid' end where id = p_stmt;
  perform vs_log(p_stmt, 'pay',
    case when bal <= 0.005 then 'Payment released - settled in full' else 'Part payment released' end,
    'UTR ' || p_utr || ' - ' || p_amount || ' paid on ' || p_on ||
    case when bal > 0.005 then '. Balance outstanding ' || bal || '.' else '.' end);
  return bal;
end $$;

create or replace function vs_remind(p_stmt uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vs_require('remind');
  perform vs_log(p_stmt, '', 'Reminder sent', 'Email and SMS reminder to the vendor.');
end $$;

-- ---- reading: one call that returns a whole statement ----------------------
create or replace function vs_statement_json(p_stmt uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'statement', to_jsonb(s) - 'created_by',
    'period_label', vs_period_label(s.period),
    'vendor', to_jsonb(v), 'site', to_jsonb(si), 'contract', to_jsonb(c),
    'site_history', vs_site_history(si.id),
    'adj_types', (select coalesce(jsonb_agg(to_jsonb(t) order by t.sort),'[]'::jsonb) from vs_adj_types t where t.active),
    'payroll', to_jsonb(pr),
    'paid_total', vs_paid_total(s.id),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', ve.id, 'v', ve.v, 'sent_at', ve.sent_at, 'viewed_at', ve.viewed_at,
        'note', ve.note, 'changes', ve.changes,
        'gross', ve.gross_amount, 'gross_note', ve.gross_note,
        'heads_total', vs_version_heads(ve.id),
        'total', vs_version_total(ve.id), 'adj_total', vs_version_adj_total(ve.id),
        'final', vs_version_final(ve.id),
        'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.sort),'[]'::jsonb)
                    from vs_version_lines l where l.version_id = ve.id),
        'adjustments', (select coalesce(jsonb_agg(to_jsonb(a) order by a.sort),'[]'::jsonb)
                    from vs_version_adj a where a.version_id = ve.id)
      ) order by ve.v), '[]'::jsonb) from vs_versions ve where ve.statement_id = s.id),
    'points',   (select coalesce(jsonb_agg(to_jsonb(p) order by p.raised_at),'[]'::jsonb)
                   from vs_points p where p.statement_id = s.id),
    'payments', (select coalesce(jsonb_agg(to_jsonb(pm) order by pm.paid_on),'[]'::jsonb)
                   from vs_payments pm where pm.statement_id = s.id),
    'events',   (select coalesce(jsonb_agg(to_jsonb(e) order by e.at),'[]'::jsonb)
                   from vs_events e where e.statement_id = s.id)
  ) into out
  from vs_statements s
  join vs_contracts c on c.id = s.contract_id
  join vs_vendors  v  on v.id = c.vendor_id
  join vs_sites    si on si.id = c.site_id
  left join vs_payroll pr on pr.statement_id = s.id
  where s.id = p_stmt;
  return out;
end $$;

create or replace function vs_list_statements(p_period date default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'vendor_name', x->>'site_name', x->>'period'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', s.id, 'period', s.period, 'period_label', vs_period_label(s.period),
      'status', s.status, 'contract_id', c.id, 'vehicles', c.vehicles,
      'tenure_from', c.from_date, 'tenure_to', c.to_date,
      'covers_from', s.covers_from, 'covers_to', s.covers_to,
      'gross', (select gross_amount from vs_versions ve where ve.id = vs_current_version(s.id)),
      'heads_total', vs_version_heads(vs_current_version(s.id)),
      'vendor_id', v.id, 'vendor_name', v.name, 'vendor_code', v.code,
      'site_id', si.id, 'site_name', si.name,
      'version', (select max(ve.v) from vs_versions ve where ve.statement_id = s.id),
      'final', vs_version_final(vs_current_version(s.id)),
      'total', vs_version_total(vs_current_version(s.id)),
      'payroll_status', coalesce(pr.status,'pending'),
      'open_points', (select count(*) from vs_points p where p.statement_id = s.id
                       and p.status in ('open','awaiting_confirm')),
      'point_count', (select count(*) from vs_points p where p.statement_id = s.id),
      'version_count', (select count(*) from vs_versions ve where ve.statement_id = s.id),
      'event_count', (select count(*) from vs_events e where e.statement_id = s.id),
      'approved_amount', s.approved_amount, 'approved_at', s.approved_at,
      'paid_total', vs_paid_total(s.id), 'due_at', s.due_at
    ) as x
    from vs_statements s
    join vs_contracts c on c.id = s.contract_id
    join vs_vendors  v  on v.id = c.vendor_id
    join vs_sites    si on si.id = c.site_id
    left join vs_payroll pr on pr.statement_id = s.id
    where (p_period is null or s.period = date_trunc('month', p_period)::date)
  ) q
$$;

grant execute on function
  vs_role(), vs_my_vendor(), vs_can(text), vs_actor(), vs_sees(uuid), vs_period_label(date),
  vs_version_total(uuid), vs_version_adj_total(uuid), vs_version_final(uuid), vs_version_heads(uuid),
  vs_current_version(uuid), vs_paid_total(uuid),
  vs_add_vendor(text,text,text,text,text), vs_add_site(text,text),
  vs_add_contract(uuid,uuid,int,date,date), vs_remove_contract(uuid), vs_set_contract_vehicles(uuid,int),
  vs_end_contract(uuid,date), vs_change_vendor(uuid,uuid,int,date), vs_contract_at(uuid,date), vs_site_history(uuid),
  vs_invite(text,text,text,uuid), vs_set_role(uuid,text), vs_set_active(uuid,bool),
  vs_save_settings(int,bool,numeric), vs_add_adj_type(text,text,bool),
  vs_add_statement(uuid,date), vs_open_month(date), vs_delete_statement(uuid,text),
  vs_save_draft(uuid,numeric,text,jsonb,jsonb),
  vs_add_head(uuid,text,text,text,text,int), vs_set_head(uuid,text,int,bool), vs_post_payroll(uuid,jsonb), vs_share(uuid), vs_mark_viewed(uuid),
  vs_raise_point(uuid,text,text,text,numeric,text,text),
  vs_log_call_point(uuid,text,text,text,numeric,text),
  vs_confirm_call_point(uuid,bool), vs_resolve_point(uuid,text,numeric,text),
  vs_issue_revision(uuid), vs_approve(uuid),
  vs_record_payment(uuid,numeric,date,text,text,text), vs_remind(uuid),
  vs_statement_json(uuid), vs_list_statements(date)
to authenticated;

-- ------------------------------------------------------------------- realtime
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table vs_statements; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table vs_points;     exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table vs_versions;   exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table vs_payments;   exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table vs_payroll;    exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table vs_events;     exception when duplicate_object then null; end;
  end if;
end $$;

-- ----------------------------------------------------------------- verification
select
  (select count(*) from vs_head_templates) as head_template,
  (select count(*) from vs_adj_types)  as adjustment_types,
  (select count(*) from vs_caps)       as capability_rows,
  (select count(*) from vs_profiles)   as people,
  (select count(*) from vs_vendors)    as vendors,
  (select count(*) from vs_statements) as settlements,
  vs_needs_setup()                     as needs_first_admin;
-- Expect: 13 - 16 - 21 - 0 - 0 - 0 - true   (before you add your own data)
