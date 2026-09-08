-- VS-DATABASE.sql
-- ============================================================================
-- WeVois Vendor Settlement - the whole database, in one file.
--
-- This replaces VS-SETUP.sql and the eight patch files. It is the same SQL in
-- the same order, so there is no order left to get wrong.
--
-- HOW TO RUN IT
--   Supabase dashboard -> SQL Editor -> new query -> paste the WHOLE file ->
--   Run. It prints a health check at the end; every line should read OK.
--
-- IT DOES NOT TOUCH YOUR DATA.
--   Every table is created only if it is not already there, and every seed row
--   is inserted only if it is missing. Statements you have shared with vendors,
--   their replies, your points, payments and the audit log all stay exactly as
--   they are. You can run this file again any time - on a database that is
--   already up to date it changes nothing at all.
--
-- WHAT IT DOES NOT INCLUDE
--   VS-IMPORT-HISTORY.sql, which loads your spreadsheet history, is a separate
--   file on purpose: it is a one-time import, not part of the structure.
--
-- Pure ASCII. No data is deleted anywhere in this file.
-- ============================================================================



-- ############################################################################
-- ##  PART 1 of 10 - VS-SETUP.sql
-- ##  the schema: tables, row-level security, and the functions every write goes through
-- ############################################################################

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


-- ############################################################################
-- ##  PART 2 of 10 - VS-PATCH-1.sql
-- ##  file attachments, the workbook importer, the manager releasing a payment
-- ############################################################################

-- VS-PATCH-1.sql
-- ============================================================================
-- Three changes, on top of VS-SETUP.sql:
--
--   1. The Vendor Manager can record payments, including for past months.
--   2. A way to load the historical months out of the workbook.
--   3. Payroll / PF / ESIC files (Excel, PDF) attached to a statement and
--      visible to the vendor.
--
-- Run in the Supabase SQL editor, selecting the whole file. Safe to re-run.
-- Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. The Vendor Manager can record payments
-- ---------------------------------------------------------------------------
-- Accounts keeps the capability too. Both can now enter a payment, which is
-- what the separation was really protecting: the vendor still has to approve
-- the amount first, and the payment can never exceed what he approved. That
-- gate is untouched.
insert into vs_caps (role, cap) values ('manager','pay') on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Documents attached to a statement
-- ---------------------------------------------------------------------------
create table if not exists vs_documents (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  path         text not null,
  filename     text not null,
  kind         text not null default 'other'
               check (kind in ('payroll','pf','esic','bill','other')),
  mime         text not null default '',
  size_bytes   bigint not null default 0,
  uploaded_by  text not null,
  uploaded_at  timestamptz not null default now()
);
create index if not exists vs_documents_stmt_idx on vs_documents (statement_id, uploaded_at);

alter table vs_documents enable row level security;
revoke all on table vs_documents from anon, authenticated;
grant select on table vs_documents to authenticated;

drop policy if exists p_docs_r on vs_documents;
create policy p_docs_r on vs_documents for select to authenticated using (vs_sees(statement_id));

-- The bucket. Private - every read goes through a signed URL, so a file can
-- never be guessed at from outside.
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present - skipping the bucket (fine outside Supabase)';
  else
    execute $b$ insert into storage.buckets (id, name, public, file_size_limit)
                values ('vs-docs','vs-docs', false, 26214400)
                on conflict (id) do nothing $b$;
  end if;
end $$;

-- Storage policies. The first folder in the path IS the statement id, so the
-- same vs_sees() rule that governs the statement governs its files: a vendor
-- can open the documents on his own shared statements and nothing else.
do $$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage schema not present - skipping storage policies (fine outside Supabase)';
    return;
  end if;

  execute 'drop policy if exists p_vsdocs_read   on storage.objects';
  execute 'drop policy if exists p_vsdocs_write  on storage.objects';
  execute 'drop policy if exists p_vsdocs_delete on storage.objects';

  execute $p$
    create policy p_vsdocs_read on storage.objects for select to authenticated
    using (
      bucket_id = 'vs-docs'
      and array_length(storage.foldername(name),1) >= 1
      and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
      and vs_sees(((storage.foldername(name))[1])::uuid)
    )$p$;

  -- writing needs the capability AND a path that begins with a real
  -- settlement id, so nothing can be parked in the bucket outside the rule
  -- that governs who may read it
  execute $p$
    create policy p_vsdocs_write on storage.objects for insert to authenticated
    with check (
      bucket_id = 'vs-docs'
      and (vs_can('edit_draft') or vs_can('post_payroll'))
      and array_length(storage.foldername(name),1) >= 1
      and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
      and exists (select 1 from vs_statements st
                   where st.id = ((storage.foldername(name))[1])::uuid)
    )$p$;

  execute $p$
    create policy p_vsdocs_delete on storage.objects for delete to authenticated
    using (
      bucket_id = 'vs-docs'
      and (vs_can('edit_draft') or vs_can('post_payroll'))
    )$p$;
end $$;

create or replace function vs_add_document(p_stmt uuid, p_path text, p_filename text,
                                           p_kind text, p_mime text, p_size bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; st text;
begin
  if not (vs_can('edit_draft') or vs_can('post_payroll')) then
    raise exception 'Your role (%) cannot attach documents.', coalesce(vs_role(),'none')
      using errcode = '42501';
  end if;
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if coalesce(trim(p_filename),'') = '' then
    raise exception 'The file needs a name.' using errcode='22023';
  end if;
  insert into vs_documents (statement_id, path, filename, kind, mime, size_bytes, uploaded_by)
  values (p_stmt, p_path, p_filename, coalesce(nullif(p_kind,''),'other'),
          coalesce(p_mime,''), coalesce(p_size,0), vs_actor())
  returning id into nid;
  perform vs_log(p_stmt, '', 'Document attached - ' || p_filename,
    'Kind: ' || coalesce(nullif(p_kind,''),'other') || '. The vendor can open this from his own statement.');
  return nid;
end $$;

create or replace function vs_remove_document(p_doc uuid, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
declare d vs_documents%rowtype;
begin
  if not (vs_can('edit_draft') or vs_can('post_payroll')) then
    raise exception 'Your role (%) cannot remove documents.', coalesce(vs_role(),'none')
      using errcode = '42501';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required. The vendor may already have opened this file.'
      using errcode='22023';
  end if;
  select * into d from vs_documents where id = p_doc;
  if not found then raise exception 'No such document.' using errcode='02000'; end if;
  delete from vs_documents where id = p_doc;
  perform vs_log(d.statement_id, 'warn', 'Document removed - ' || d.filename, trim(p_reason));
  return d.path;
end $$;

-- documents ride along with the statement, so the app gets them in one call
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
    'adj_types', (select coalesce(jsonb_agg(to_jsonb(t) order by t.sort),'[]'::jsonb)
                    from vs_adj_types t where t.active),
    'payroll', to_jsonb(pr),
    'paid_total', vs_paid_total(s.id),
    'documents', (select coalesce(jsonb_agg(to_jsonb(dc) order by dc.uploaded_at),'[]'::jsonb)
                    from vs_documents dc where dc.statement_id = s.id),
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

-- ---------------------------------------------------------------------------
-- 2. Loading a historical month out of the workbook
-- ---------------------------------------------------------------------------
-- One call per site-month. Heads are matched on their LABEL as it reads on
-- that site's sheet, so the import does not depend on any generated key.
-- Everything it creates carries a line in the record saying it was imported
-- and not raised through the portal.
create or replace function vs_import_month(
  p_site    text,
  p_period  date,
  p_gross   numeric,
  p_status  text,            -- 'paid' or anything else for approved-not-paid
  p_heads   jsonb,           -- {"r_m_exp": 12345, ...} keyed on the head key
  p_adj     jsonb,           -- [{"label":"...","effect":"add|deduct|note","amount":n}]
  p_hint    text default null -- 'incoming' picks the vendor who took over mid-month
) returns text
language plpgsql security definer set search_path = public as $$
declare
  sid uuid; cid uuid; stid uuid; vid uuid; per date; mend date;
  k text; n int := 0; miss text := ''; fin numeric; a jsonb; i int := 0;
begin
  perform vs_require('manage_settlements');
  per  := date_trunc('month', p_period)::date;
  mend := (per + interval '1 month - 1 day')::date;

  select id into sid from vs_sites where lower(name) = lower(p_site);
  if sid is null then return 'no such site: ' || p_site; end if;

  if p_hint = 'incoming' then
    select id into cid from vs_contracts
     where site_id = sid and from_date between per and mend
     order by from_date desc limit 1;
  else
    select id into cid from vs_contracts
     where site_id = sid
       and daterange(from_date, coalesce(to_date,'infinity'::date), '[]') && daterange(per, mend, '[]')
     order by from_date limit 1;
  end if;
  if cid is null then return 'no vendor on ' || p_site || ' in ' || vs_period_label(per); end if;

  if exists (select 1 from vs_statements where contract_id = cid and period = per) then
    return 'already there: ' || p_site || ' ' || vs_period_label(per);
  end if;

  insert into vs_statements (contract_id, period, covers_from, covers_to, created_by)
  select cid, per, greatest(c.from_date, per),
         least(coalesce(c.to_date,'infinity'::date), mend), auth.uid()
    from vs_contracts c where c.id = cid
  returning id into stid;

  insert into vs_versions (statement_id, v, gross_amount, gross_note, sent_at)
  values (stid, 1, coalesce(p_gross,0),
          'Imported from Operation Partners Payment Details 9.xlsx', now())
  returning id into vid;

  -- start from that site's own heads, then fill by label
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount)
    select vid, h.id, h.key, h.label, h.grp, 'manual', h.sort, 0
      from vs_heads h join vs_contracts c on c.site_id = h.site_id
     where c.id = cid and h.active;

  for k in select jsonb_object_keys(coalesce(p_heads,'{}'::jsonb)) loop
    -- matched on key, not label: several sites carry two rows both called
    -- "ESIC Pf (Employee Part)" (the vendor's own staff and the site staff),
    -- and matching on the label would collapse them into one figure
    update vs_version_lines set amount = (p_heads ->> k)::numeric
     where version_id = vid and head_key = k;
    if found then n := n + 1; else miss := miss || k || '; '; end if;
  end loop;

  for a in select * from jsonb_array_elements(coalesce(p_adj,'[]'::jsonb)) loop
    i := i + 1;
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (vid, a->>'label', coalesce(a->>'effect','deduct'), (a->>'amount')::numeric,
            'Imported from the workbook', i * 10);
  end loop;

  -- historical months did not go through the payroll posting, so mark it done
  -- and leave the figures where the sheet put them
  insert into vs_payroll (statement_id, status, posted_by, posted_at,
                          pf_trrn, esic_challan, not_processed_reason)
  values (stid, 'posted', 'Imported from workbook', now(), 'n/a - imported', 'n/a - imported',
          'Historical month loaded from the spreadsheet.')
  on conflict (statement_id) do nothing;

  fin := vs_version_final(vid);
  update vs_statements
     set status = case when lower(coalesce(p_status,'')) = 'paid' then 'paid' else 'approved' end,
         approved_at = now(), approved_by = 'Imported from workbook',
         approved_version = 1, approved_amount = fin
   where id = stid;

  if lower(coalesce(p_status,'')) = 'paid' and fin > 0 then
    insert into vs_payments (statement_id, amount, paid_on, utr, mode, note, recorded_by)
    values (stid, fin, mend, 'IMPORTED', 'n/a',
            'Marked paid on the spreadsheet. No UTR was recorded there.', 'Imported from workbook');
  end if;

  perform vs_log(stid, 'hi', 'Imported from the workbook',
    'Loaded from Operation Partners Payment Details 9.xlsx for ' || vs_period_label(per) ||
    '. Earned ' || coalesce(p_gross,0) || ', ' || n || ' expense heads, final ' || fin ||
    '. This month was settled on the spreadsheet, not raised through the portal.' ||
    case when miss <> '' then ' Heads not found on this site: ' || miss else '' end);

  return case when miss = '' then 'ok' else 'ok, but unmatched heads: ' || miss end;
end $$;

grant execute on function
  vs_add_document(uuid,text,text,text,text,bigint),
  vs_remove_document(uuid,text),
  vs_import_month(text,date,numeric,text,jsonb,jsonb,text)
to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table vs_documents; exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------------------------------------------------------------- verification
select
  (select count(*) from vs_caps where role='manager' and cap='pay')          as manager_can_pay,
  (select count(*) from information_schema.tables
     where table_name='vs_documents')                                        as documents_table,
  (select count(*) from pg_proc where proname='vs_import_month')             as import_function,
  (select count(*) from pg_proc where proname='vs_add_document')             as upload_function;
-- Expect: 1 - 1 - 1 - 1


-- ############################################################################
-- ##  PART 3 of 10 - VS-PATCH-2.sql
-- ##  each vendor sees only his own sites
-- ############################################################################

-- VS-PATCH-2.sql
-- ============================================================================
-- A vendor was able to read other vendors' sites, months and figures.
--
-- The row-level policies were right all along: reading vs_sites, vs_vendors,
-- vs_contracts or vs_statements directly, a vendor already saw only his own.
-- The hole was on the other side. Several reader functions are SECURITY
-- DEFINER, which is what lets them do the joins and the arithmetic without
-- every caller needing rights on every table - and being SECURITY DEFINER,
-- row-level security does not apply inside them. They never asked who was
-- calling. vs_list_statements, which is what fills the home screen, returned
-- EVERY settlement in the company to whoever asked.
--
-- Nine functions are corrected here. Each one now answers only for a
-- settlement, version or site the caller is entitled to, using the same
-- vs_sees() rule that governs the tables.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER
-- VS-PATCH-1.sql. Safe to re-run. Changes no data. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Can this person see this site at all?
-- ---------------------------------------------------------------------------
-- Staff see every site. A vendor sees a site only where he holds, or has held,
-- a tenure. Past tenures count: a partner who ran Nawa until April still has
-- settlements there to look at.
create or replace function vs_sees_site(p_site uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when vs_role() is null then false
    when vs_can('view_all') then true
    else exists (select 1 from vs_contracts c
                  where c.site_id = p_site and c.vendor_id = vs_my_vendor())
  end
$$;

-- and the same question about a version, which hangs off a statement
create or replace function vs_sees_version(p_ver uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select vs_sees((select statement_id from vs_versions where id = p_ver))
$$;

-- ---------------------------------------------------------------------------
-- 2. The home screen list - the one that was leaking
-- ---------------------------------------------------------------------------
-- One line added: "and vs_sees(s.id)". A vendor now gets his own shared
-- settlements and nothing else; every other role is unchanged.
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
      and vs_sees(s.id)
  ) q
$$;

-- ---------------------------------------------------------------------------
-- 3. The money helpers
-- ---------------------------------------------------------------------------
-- These take a version or a statement id and hand back a figure. They were
-- happy to price anybody's month. They now return null for a month the caller
-- is not entitled to, rather than raising - they are called inside aggregates
-- and a refusal there would break a legitimate screen for an illegitimate row
-- that should simply not be counted.
create or replace function vs_version_heads(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then (select coalesce(sum(amount),0) from vs_version_lines where version_id = p_ver)
  end
$$;

create or replace function vs_version_adj_total(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver) then
    (select coalesce(sum(case effect when 'add' then amount when 'deduct' then -amount else 0 end),0)
       from vs_version_adj where version_id = p_ver)
  end
$$;

create or replace function vs_version_total(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then coalesce((select gross_amount from vs_versions where id = p_ver),0) - vs_version_heads(p_ver)
  end
$$;

create or replace function vs_version_final(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then vs_version_total(p_ver) + vs_version_adj_total(p_ver)
  end
$$;

create or replace function vs_current_version(p_stmt uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select case when vs_sees(p_stmt)
    then (select id from vs_versions where statement_id = p_stmt order by v desc limit 1)
  end
$$;

create or replace function vs_paid_total(p_stmt uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees(p_stmt)
    then (select coalesce(sum(amount),0) from vs_payments where statement_id = p_stmt)
  end
$$;

-- ---------------------------------------------------------------------------
-- 4. Which vendor was running a site on a given day
-- ---------------------------------------------------------------------------
create or replace function vs_contract_at(p_site uuid, p_on date) returns uuid
language sql stable security definer set search_path = public as $$
  select case when vs_sees_site(p_site) then
    (select id from vs_contracts
      where site_id = p_site and p_on between from_date and coalesce(to_date,'infinity'::date)
      limit 1)
  end
$$;

-- ---------------------------------------------------------------------------
-- 5. The chain of tenures on a site
-- ---------------------------------------------------------------------------
-- Staff see the whole chain, which is the point of it - who ran this site,
-- when, and how many settlements each one had. A vendor sees only his own
-- stretch of it. He learns nothing about who came before him or after, and the
-- "this site has changed hands" banner simply does not appear for him.
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
    and vs_sees_site(p_site)
    and (vs_can('view_all') or c.vendor_id = vs_my_vendor())
$$;

-- ---------------------------------------------------------------------------
-- 6. The payroll correction diff
-- ---------------------------------------------------------------------------
-- This one raises rather than returning empty: it is called directly by a
-- screen, never inside an aggregate, so a refusal is the honest answer.
create or replace function vs_payroll_diff(p_stmt uuid, p_ver uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype; out jsonb := '[]'::jsonb; cur numeric;
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select * into pr from vs_payroll where statement_id = p_stmt;
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
  select coalesce(amount,0) into cur from vs_version_adj where version_id=p_ver and payroll_linked;
  if coalesce(cur,0) is distinct from pr.not_processed_amount then out := out || jsonb_build_array(jsonb_build_object(
    'kind','adj','key','not_processed','from',coalesce(cur,0),'to',pr.not_processed_amount,
    'why','Payroll correction posted by Accounts.')); end if;
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Booking heads, tightened the same way
-- ---------------------------------------------------------------------------
-- The old policy let a vendor read the heads of a site he currently runs. It
-- now uses the same rule as everything else, so a site he used to run stays
-- readable - otherwise his own old statements would render with blank labels.
drop policy if exists p_heads_r on vs_heads;
create policy p_heads_r on vs_heads for select to authenticated
  using (vs_sees_site(site_id));

drop policy if exists p_sites_r on vs_sites;
create policy p_sites_r on vs_sites for select to authenticated
  using (vs_sees_site(id));

grant execute on function vs_sees_site(uuid), vs_sees_version(uuid) to authenticated;

-- ---------------------------------------------------------------- verification
-- Every one of these should say t.
select
  (select count(*) = 0 from pg_proc
     where proname = 'vs_list_statements'
       and prosrc not like '%vs_sees(s.id)%')                     as list_is_filtered,
  (select count(*) = 2 from pg_proc
     where proname in ('vs_sees_site','vs_sees_version'))         as gates_exist,
  (select count(*) = 0 from pg_proc
     where proname in ('vs_version_heads','vs_version_total','vs_version_final',
                       'vs_version_adj_total','vs_current_version','vs_paid_total',
                       'vs_contract_at','vs_site_history','vs_payroll_diff')
       and prosrc not like '%vs_sees%')                           as helpers_are_gated,
  (select count(*) = 9 from pg_proc
     where proname in ('vs_version_heads','vs_version_total','vs_version_final',
                       'vs_version_adj_total','vs_current_version','vs_paid_total',
                       'vs_contract_at','vs_site_history','vs_payroll_diff'))
                                                                  as all_nine_present;
-- Expect: t | t | t | t


-- ############################################################################
-- ##  PART 4 of 10 - VS-PATCH-3.sql
-- ##  editing a site, its start and closing dates, and its tenures
-- ############################################################################

-- VS-PATCH-3.sql
-- ============================================================================
-- The administrator can now edit a site and a tenure after creating them.
--
-- Until now a site had a name and a city and nothing else, and neither could be
-- changed once typed - a misspelt site name was permanent. A tenure could have
-- its vehicle count changed and could be given an end date, but its START date
-- could never be corrected: the only way out was to delete the tenure, which
-- itself is refused once a single settlement exists under it.
--
-- This adds:
--   a site's own operating life  - the date WeVois started there and the date
--                                  it closed, separate from who ran it
--   vs_set_site(...)             - rename, re-city, re-date, in one call
--   vs_set_contract(...)         - change a tenure's start, end and vehicles
--   vs_reopen_contract(...)      - undo an end date set by mistake
--
-- Every one of them refuses rather than corrupts. A date change that would
-- strand an existing settlement outside its own tenure, or make two vendors
-- overlap on one site, or close a site before the last month settled under it,
-- is turned away with the months named.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-2.
-- Safe to re-run. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. A site gets a life of its own
-- ---------------------------------------------------------------------------
-- Distinct from the tenures. A site can be running with nobody assigned yet
-- (start_date set, no contract), and it can be closed while its history stays
-- readable. close_date null means still running.
alter table vs_sites add column if not exists start_date date;
alter table vs_sites add column if not exists close_date date;

do $do$
begin
  if not exists (select 1 from pg_constraint where conname = 'vs_sites_dates_ck') then
    alter table vs_sites add constraint vs_sites_dates_ck
      check (close_date is null or start_date is null or close_date >= start_date);
  end if;
end $do$;

-- Fill in what can be inferred, once, for sites that already have tenures.
update vs_sites s
   set start_date = (select min(c.from_date) from vs_contracts c where c.site_id = s.id)
 where s.start_date is null
   and exists (select 1 from vs_contracts c where c.site_id = s.id);

-- A site whose every tenure has ended is treated as closed on the last of them.
update vs_sites s
   set close_date = (select max(c.to_date) from vs_contracts c where c.site_id = s.id)
 where s.close_date is null
   and exists (select 1 from vs_contracts c where c.site_id = s.id)
   and not exists (select 1 from vs_contracts c where c.site_id = s.id and c.to_date is null);

-- ---------------------------------------------------------------------------
-- 2. Is this site open for this month?
-- ---------------------------------------------------------------------------
-- A month may be settled if it overlaps the site's operating window at all. A
-- site with no dates set is treated as always open, so nothing that exists
-- today suddenly stops working.
create or replace function vs_site_open_in(p_site uuid, p_period date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select daterange(coalesce(s.start_date,'-infinity'::date),
                     coalesce(s.close_date,'infinity'::date), '[]')
        && daterange(date_trunc('month', p_period)::date,
                     (date_trunc('month', p_period) + interval '1 month - 1 day')::date, '[]')
      from vs_sites s where s.id = p_site), true)
$$;

create or replace function vs_site_status(p_site uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when s.close_date is not null and s.close_date < current_date then 'closed'
    when s.start_date is not null and s.start_date > current_date then 'not_started'
    else 'running' end
  from vs_sites s where s.id = p_site
$$;

-- ---------------------------------------------------------------------------
-- 3. Edit a site
-- ---------------------------------------------------------------------------
create or replace function vs_set_site(p_site uuid, p_name text, p_city text,
                                       p_start date, p_close date)
returns text language plpgsql security definer set search_path = public as $$
declare s vs_sites%rowtype; nm text; earliest date; latest date; running int; changed text := '';
begin
  perform vs_require('manage_vendors');
  select * into s from vs_sites where id = p_site;
  if not found then raise exception 'No such site.' using errcode='02000'; end if;

  nm := coalesce(nullif(trim(p_name),''), s.name);
  if exists (select 1 from vs_sites x where x.id <> p_site and lower(x.name) = lower(nm)) then
    raise exception 'There is already a site called %. Two sites with the same name cannot be told apart on a settlement.', nm
      using errcode='23505';
  end if;

  -- the earliest thing that has actually happened at this site
  select least(
      (select min(c.from_date) from vs_contracts c where c.site_id = p_site),
      (select min(st.period) from vs_statements st
         join vs_contracts c on c.id = st.contract_id where c.site_id = p_site))
    into earliest;
  -- and the latest
  select greatest(
      (select max(c.to_date) from vs_contracts c where c.site_id = p_site),
      (select max((date_trunc('month', st.period) + interval '1 month - 1 day')::date)
         from vs_statements st join vs_contracts c on c.id = st.contract_id
        where c.site_id = p_site))
    into latest;

  if p_start is not null and earliest is not null and p_start > earliest then
    raise exception 'This site already has work recorded from %. The start date cannot be after that.',
      to_char(earliest,'DD Mon YYYY') using errcode='22023';
  end if;

  if p_close is not null then
    select count(*) into running from vs_contracts where site_id = p_site and to_date is null;
    if running > 0 then
      raise exception 'A vendor is still running this site with no end date. End that tenure first, then close the site.'
        using errcode='23503';
    end if;
    if latest is not null and p_close < latest then
      raise exception 'There is work recorded at this site up to %. The closing date cannot be before that.',
        to_char(latest,'DD Mon YYYY') using errcode='22023';
    end if;
  end if;

  if nm <> s.name then changed := changed || 'renamed from ' || s.name || ' to ' || nm || '; '; end if;
  if coalesce(nullif(trim(p_city),''), s.city) is distinct from s.city then
    changed := changed || 'city ' || coalesce(nullif(s.city,''),'(blank)') || ' -> ' || trim(p_city) || '; '; end if;
  if p_start is distinct from s.start_date then
    changed := changed || 'started ' || coalesce(to_char(s.start_date,'DD Mon YYYY'),'(not set)') ||
               ' -> ' || coalesce(to_char(p_start,'DD Mon YYYY'),'(not set)') || '; '; end if;
  if p_close is distinct from s.close_date then
    changed := changed || 'closed ' || coalesce(to_char(s.close_date,'DD Mon YYYY'),'(still running)') ||
               ' -> ' || coalesce(to_char(p_close,'DD Mon YYYY'),'(still running)') || '; '; end if;

  update vs_sites
     set name = nm,
         city = coalesce(nullif(trim(p_city),''), city),
         start_date = p_start,
         close_date = p_close,
         -- the legacy flag is kept in step with the dates so nothing reading it
         -- can disagree with what the screen shows
         active = (p_close is null or p_close >= current_date)
   where id = p_site;

  if changed = '' then return 'nothing changed'; end if;
  perform vs_audit_log('Site changed', nm || ': ' || rtrim(changed, '; '));
  return rtrim(changed, '; ');
end $$;

-- ---------------------------------------------------------------------------
-- 4. Edit a tenure - including the start date, which could not be touched
-- ---------------------------------------------------------------------------
create or replace function vs_set_contract(p_contract uuid, p_vehicles int,
                                           p_from date, p_to date)
returns text language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; f date; t date; clash text; bad text; s vs_sites%rowtype;
        redrawn int := 0; frozen int := 0; changed text := ''; vn text;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such tenure.' using errcode='02000'; end if;
  select * into s from vs_sites where id = c.site_id;

  f := coalesce(p_from, c.from_date);
  t := p_to;                                   -- null here genuinely means "no end date"
  if p_vehicles is not null and p_vehicles < 1 then
    raise exception 'Vehicle count must be at least 1.' using errcode='22023';
  end if;
  if t is not null and t < f then
    raise exception 'The end date cannot be before the start date.' using errcode='22023';
  end if;

  -- no two vendors on one site at the same time
  select v.name || ' (' || to_char(o.from_date,'DD Mon YYYY') || ' to ' ||
         coalesce(to_char(o.to_date,'DD Mon YYYY'),'current') || ')'
    into clash
    from vs_contracts o join vs_vendors v on v.id = o.vendor_id
   where o.site_id = c.site_id and o.id <> p_contract
     and daterange(o.from_date, coalesce(o.to_date,'infinity'::date), '[]')
      && daterange(f, coalesce(t,'infinity'::date), '[]')
   limit 1;
  if clash is not null then
    raise exception 'Those dates run into %. Two vendors cannot hold one site at the same time.', clash
      using errcode='23P01';
  end if;

  -- every settlement already raised under this tenure must still sit inside it
  select string_agg(vs_period_label(st.period), ', ' order by st.period) into bad
    from vs_statements st
   where st.contract_id = p_contract
     and not (daterange(f, coalesce(t,'infinity'::date), '[]')
           && daterange(st.period, (st.period + interval '1 month - 1 day')::date, '[]'));
  if bad is not null then
    raise exception 'That would leave % outside this tenure. Move the dates to cover it, or delete that settlement first.', bad
      using errcode='23503';
  end if;

  -- and inside the site's own operating life
  if s.start_date is not null and f < s.start_date then
    raise exception 'The site itself only starts on %. Change the site first if the partner really began earlier.',
      to_char(s.start_date,'DD Mon YYYY') using errcode='22023';
  end if;
  if s.close_date is not null and (t is null or t > s.close_date) then
    raise exception 'The site closed on %. A tenure cannot run past it.',
      to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;

  if f is distinct from c.from_date then
    changed := changed || 'start ' || to_char(c.from_date,'DD Mon YYYY') || ' -> ' || to_char(f,'DD Mon YYYY') || '; '; end if;
  if t is distinct from c.to_date then
    changed := changed || 'end ' || coalesce(to_char(c.to_date,'DD Mon YYYY'),'(open)') ||
               ' -> ' || coalesce(to_char(t,'DD Mon YYYY'),'(open)') || '; '; end if;
  if p_vehicles is not null and p_vehicles is distinct from c.vehicles then
    changed := changed || 'vehicles ' || c.vehicles || ' -> ' || p_vehicles || '; '; end if;

  update vs_contracts
     set from_date = f, to_date = t, vehicles = coalesce(p_vehicles, vehicles)
   where id = p_contract;

  -- A statement carries the days it covers, taken from the tenure the day it was
  -- opened. Redraw that on drafts, which nobody has seen yet. Leave anything
  -- shared, approved or paid exactly as the vendor received it - a settlement
  -- that has gone out is a record, not a view.
  update vs_statements st
     set covers_from = greatest(f, st.period),
         covers_to   = least(coalesce(t,'infinity'::date),
                             (st.period + interval '1 month - 1 day')::date)
   where st.contract_id = p_contract and st.status = 'draft';
  get diagnostics redrawn = row_count;
  select count(*) into frozen from vs_statements
   where contract_id = p_contract and status <> 'draft';

  if changed = '' then return 'nothing changed'; end if;
  select v.name into vn from vs_vendors v where v.id = c.vendor_id;
  perform vs_audit_log('Tenure changed', vn || ' at ' || s.name || ': ' || rtrim(changed,'; ') ||
    case when redrawn > 0 then ' (' || redrawn || ' draft settlement(s) redrawn)' else '' end ||
    case when frozen  > 0 then ' (' || frozen  || ' already sent, left untouched)' else '' end);
  return rtrim(changed,'; ') ||
    case when frozen > 0 then '. ' || frozen || ' settlement(s) already sent keep the dates the vendor saw.' else '' end;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Undo an end date
-- ---------------------------------------------------------------------------
create or replace function vs_reopen_contract(p_contract uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; clash text; s vs_sites%rowtype; vn text;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such tenure.' using errcode='02000'; end if;
  if c.to_date is null then raise exception 'That tenure is already open.' using errcode='22023'; end if;
  select * into s from vs_sites where id = c.site_id;
  if s.close_date is not null then
    raise exception 'The site is closed as of %. Reopen the site first.',
      to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;
  select v.name into clash from vs_contracts o join vs_vendors v on v.id = o.vendor_id
   where o.site_id = c.site_id and o.id <> p_contract and o.from_date > c.to_date limit 1;
  if clash is not null then
    raise exception '% took this site over afterwards. End or move that tenure first.', clash
      using errcode='23P01';
  end if;
  update vs_contracts set to_date = null where id = p_contract;
  select v.name into vn from vs_vendors v where v.id = c.vendor_id;
  perform vs_audit_log('Tenure reopened', vn || ' at ' || s.name || ' is running again, no end date');
end $$;

-- ---------------------------------------------------------------------------
-- 5b. Assigning and ending a tenure respect the site's life too
-- ---------------------------------------------------------------------------
-- vs_set_contract checks the site window, but vs_add_contract did not, so a
-- vendor could still be assigned to a site that had already closed - and even
-- given no end date, which vs_set_site refuses to allow in the other order.
-- Both doors now carry the same lock.
create or replace function vs_add_contract(p_vendor uuid, p_site uuid, p_vehicles int,
                                          p_from date default null, p_to date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; vn text; f date; t date; clash text; s vs_sites%rowtype;
begin
  perform vs_require('manage_contracts');
  if p_vehicles is null or p_vehicles < 1 then
    raise exception 'Vehicle count must be at least 1.' using errcode = '22023';
  end if;
  f := coalesce(p_from, current_date);
  t := p_to;

  select * into s from vs_sites where id = p_site;
  if not found then raise exception 'No such site.' using errcode='02000'; end if;
  if s.start_date is not null and f < s.start_date then
    raise exception '% only opens on %. Move the start date on the site first if the partner really began earlier.',
      s.name, to_char(s.start_date,'DD Mon YYYY') using errcode='22023';
  end if;
  if s.close_date is not null and (t is null or t > s.close_date) then
    raise exception '% closed on %. A tenure cannot run past it, and cannot be left open ended.',
      s.name, to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;

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
  perform vs_audit_log('Site assigned',
    vn || ' holds ' || s.name || ' with ' || p_vehicles || ' vehicles from ' || to_char(f,'DD Mon YYYY')
    || coalesce(' to ' || to_char(t,'DD Mon YYYY'), ''));
  return nid;
end $$;

create or replace function vs_end_contract(p_contract uuid, p_last_date date)
returns void language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; n int; vn text; s vs_sites%rowtype;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such contract.' using errcode='02000'; end if;
  if p_last_date < c.from_date then
    raise exception 'The last day cannot be before the tenure started (%).', to_char(c.from_date,'DD Mon YYYY')
      using errcode='22023';
  end if;
  select * into s from vs_sites where id = c.site_id;
  if s.close_date is not null and p_last_date > s.close_date then
    raise exception '% closed on %. The tenure cannot run past it.',
      s.name, to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;
  select count(*) into n from vs_statements
   where contract_id = p_contract and period > date_trunc('month', p_last_date)::date;
  if n > 0 then
    raise exception 'There are % settlement(s) for this vendor after %. Delete those first.',
      n, to_char(p_last_date,'Mon YYYY') using errcode='23503';
  end if;
  update vs_contracts set to_date = p_last_date where id = p_contract;
  select v.name into vn from vs_vendors v where v.id = c.vendor_id;
  perform vs_audit_log('Tenure ended', vn || ' ran ' || s.name || ' until ' || to_char(p_last_date,'DD Mon YYYY'));
end $$;

-- ---------------------------------------------------------------------------
-- 6. A month cannot be opened outside the site's own life
-- ---------------------------------------------------------------------------
create or replace function vs_add_statement(p_contract uuid, p_period date)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid; vid uuid; per date; lbl text; sname text;
begin
  perform vs_require('manage_settlements');
  per := date_trunc('month', p_period)::date;
  if not exists (select 1 from vs_contracts c where c.id = p_contract
                  and daterange(c.from_date, coalesce(c.to_date,'infinity'::date), '[]')
                   && daterange(per, (per + interval '1 month - 1 day')::date, '[]')) then
    raise exception 'That vendor was not running this site in %.', vs_period_label(per) using errcode = '22023';
  end if;
  select s.name into sname from vs_contracts c join vs_sites s on s.id = c.site_id where c.id = p_contract;
  if not (select vs_site_open_in(c.site_id, per) from vs_contracts c where c.id = p_contract) then
    raise exception '% was not open in % - check the site''s start and closing dates.',
      sname, vs_period_label(per) using errcode = '22023';
  end if;
  if exists (select 1 from vs_statements where contract_id = p_contract and period = per) then
    raise exception 'That vendor and site already has a settlement for %.', vs_period_label(per)
      using errcode = '23505';
  end if;
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
  for c in select vs_contracts.id from vs_contracts
           where daterange(from_date, coalesce(to_date,'infinity'::date), '[]')
              && daterange(per, (per + interval '1 month - 1 day')::date, '[]')
             and vs_site_open_in(site_id, per)
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

grant execute on function
  vs_set_site(uuid,text,text,date,date),
  vs_set_contract(uuid,int,date,date),
  vs_reopen_contract(uuid),
  vs_site_open_in(uuid,date),
  vs_site_status(uuid)
to authenticated;

-- ---------------------------------------------------------------- verification
select
  (select count(*) = 2 from information_schema.columns
    where table_name='vs_sites' and column_name in ('start_date','close_date'))  as site_dates,
  (select count(*) = 1 from pg_proc where proname='vs_set_site')                 as edit_site,
  (select count(*) = 1 from pg_proc where proname='vs_set_contract')             as edit_tenure,
  (select count(*) = 1 from pg_proc where proname='vs_reopen_contract')          as reopen,
  (select count(*) = 1 from pg_constraint where conname='vs_sites_dates_ck')     as date_check;
-- Expect: t | t | t | t | t


-- ############################################################################
-- ##  PART 5 of 10 - VS-PATCH-4.sql
-- ##  the vendor manager may post the payroll himself
-- ############################################################################

-- VS-PATCH-4.sql
-- ============================================================================
-- The vendor manager can post and correct the processed salary, PF and ESIC.
--
-- Until now only Accounts could, and the statement could not be shared until
-- they had. That gate is unchanged in mechanism - a statement still cannot go
-- to a vendor with the payroll unposted - but it is no longer a second pair of
-- eyes. The manager can now satisfy it himself.
--
-- What is deliberately NOT relaxed:
--   * PF TRRN and ESIC challan are still both compulsory. They are what the
--     vendor checks the deposit against, so a posting without them is refused
--     whoever is doing it.
--   * A figure for salary not processed from WeVois still needs a written
--     reason.
--   * A correction posted after the statement has been shared still parks
--     itself and only lands when the manager issues a new version, with every
--     changed figure listed. Nothing about a frozen version moves.
--   * The record names whoever actually posted it - vs_post_payroll writes
--     posted_by from the signed-in person, not from the role. If the manager
--     posts it, the statement says so, permanently.
--
-- The CEO, the VP and the vendor are all still refused.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-3.
-- Safe to re-run. Changes no data. Pure ASCII.
-- ============================================================================

insert into vs_caps (role, cap) values ('manager','post_payroll')
on conflict do nothing;

-- ---------------------------------------------------------------- verification
select
  (select count(*) from vs_caps where role='manager' and cap='post_payroll') as manager_can_post,
  (select count(*) from vs_caps where role='accounts' and cap='post_payroll') as accounts_still_can,
  (select count(*) from vs_caps where role in ('ceo','vp','vendor')
     and cap='post_payroll')                                                  as observers_cannot,
  (select count(*) from vs_caps where role='manager')                         as manager_caps_total;
-- Expect: 1 | 1 | 0 | 9


-- ############################################################################
-- ##  PART 6 of 10 - VS-PATCH-5.sql
-- ##  queries, vendor file uploads, points on the earned amount, payroll top-ups
-- ############################################################################

-- VS-PATCH-5.sql
-- ============================================================================
-- Five things, all of them about the vendor having a voice and the payroll
-- telling the truth when it arrives in pieces.
--
--   1. The vendor can raise a point on the EARNED amount itself, not just on
--      an expense head or an adjustment line.
--   2. A general query - anything not about a figure on this month's sheet -
--      with a written answer from the vendor manager and a running set of
--      remarks from either side.
--   3. The vendor can attach a file to his own statement. Until now only the
--      manager and Accounts could, so "send me the bill" stayed a phone call.
--   4. Salary processed late goes on as a TOP-UP entry with its own challan,
--      its own date and its own note, instead of overwriting the month.
--   5. Everything above rides along in vs_statement_json, so the app gets it
--      in the same single call.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-4.
-- Safe to re-run. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. What a point can be about, and what can become of it
-- ---------------------------------------------------------------------------
alter table vs_points drop constraint if exists vs_points_target_kind_check;
alter table vs_points add constraint vs_points_target_kind_check
  check (target_kind in ('head','adjustment','gross','general'));

alter table vs_points drop constraint if exists vs_points_status_check;
alter table vs_points add constraint vs_points_status_check
  check (status in ('open','awaiting_confirm','disputed_record',
                    'accepted','partial','rejected','carry_forward','answered'));

-- ---------------------------------------------------------------------------
-- 2. Remarks - a thread hanging off any point
-- ---------------------------------------------------------------------------
create table if not exists vs_point_remarks (
  id        uuid primary key default gen_random_uuid(),
  point_id  uuid not null references vs_points(id) on delete cascade,
  body      text not null,
  by_name   text not null,
  by_role   text not null,
  at        timestamptz not null default now()
);
create index if not exists vs_point_remarks_idx on vs_point_remarks (point_id, at);

alter table vs_point_remarks enable row level security;
revoke all on table vs_point_remarks from anon, authenticated;
grant select on table vs_point_remarks to authenticated;

drop policy if exists p_remarks_r on vs_point_remarks;
create policy p_remarks_r on vs_point_remarks for select to authenticated
  using (exists (select 1 from vs_points p where p.id = point_id and vs_sees(p.statement_id)));

-- ---------------------------------------------------------------------------
-- 3. A general query, and the answer to it
-- ---------------------------------------------------------------------------
-- Deliberately does NOT move the statement to "under query". A question about
-- a fuel card or next month's vehicles should not hold up a settlement whose
-- figures nobody is disputing. It also stays raisable after approval, because
-- that is exactly when people remember things.
create or replace function vs_raise_query(p_stmt uuid, p_note text, p_attach text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; vno int;
begin
  perform vs_require('raise');
  if not vs_sees(p_stmt) then
    raise exception 'That is not your statement.' using errcode='42501';
  end if;
  if coalesce(trim(p_note),'') = '' then
    raise exception 'Write the question down. That text is the record.' using errcode='22023';
  end if;
  select v into vno from vs_versions where id = vs_current_version(p_stmt);
  insert into vs_points (statement_id, target_kind, target_key, target_label, source,
                         raised_by, version_no, note, attachment, status)
  values (p_stmt, 'general', '', 'General query', 'portal', vs_actor(),
          coalesce(vno,1), trim(p_note), coalesce(p_attach,''), 'open')
  returning id into nid;
  perform vs_log(p_stmt, 'warn', 'Query raised', '"' || trim(p_note) || '"');
  return nid;
end $$;

create or replace function vs_answer_query(p_point uuid, p_reply text)
returns void language plpgsql security definer set search_path = public as $$
declare pt vs_points%rowtype;
begin
  perform vs_require('resolve');
  select * into pt from vs_points where id = p_point;
  if not found then raise exception 'No such query.' using errcode='02000'; end if;
  if pt.target_kind <> 'general' then
    raise exception 'That is a point on a figure. Answer it from the Points tab, where the amount can move.'
      using errcode='22023';
  end if;
  if coalesce(trim(p_reply),'') = '' then
    raise exception 'An answer is required. It is what the vendor sees.' using errcode='22023';
  end if;
  update vs_points
     set status = 'answered', decision = trim(p_reply),
         decided_by = vs_actor(), decided_at = now()
   where id = p_point;
  perform vs_log(pt.statement_id, 'ok', 'Query answered', '"' || trim(p_reply) || '"');
end $$;

-- Either side may add a remark, on a general query or on a point about a
-- figure. It never moves an amount and never changes a status - it is the
-- written trail of what was said around the decision.
create or replace function vs_add_remark(p_point uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare pt vs_points%rowtype; nid uuid; r text;
begin
  r := vs_role();
  if r is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  if r in ('ceo','vp') then
    raise exception 'Observer accounts cannot write on a settlement.' using errcode='42501';
  end if;
  select * into pt from vs_points where id = p_point;
  if not found then raise exception 'No such point.' using errcode='02000'; end if;
  if not vs_sees(pt.statement_id) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  if coalesce(trim(p_body),'') = '' then
    raise exception 'A remark cannot be blank.' using errcode='22023';
  end if;
  insert into vs_point_remarks (point_id, body, by_name, by_role)
  values (p_point, trim(p_body), vs_actor(), r)
  returning id into nid;
  perform vs_log(pt.statement_id, '', 'Remark added on ' || pt.target_label, '"' || trim(p_body) || '"');
  return nid;
end $$;

-- ---------------------------------------------------------------------------
-- 4. An accepted point on the earned amount moves the earned amount
-- ---------------------------------------------------------------------------
create or replace function vs_issue_revision(p_stmt uuid)
returns int language plpgsql security definer set search_path = public as $$
declare oldv uuid; oldn int; newv uuid; ch jsonb := '[]'::jsonb; n int := 0;
        pt record; fix jsonb; e jsonb; d int; opencount int; oldgross numeric; why text;
begin
  perform vs_require('revise');
  oldv := vs_current_version(p_stmt);
  select v, gross_amount into oldn, oldgross from vs_versions where id = oldv;

  -- whoever parked the correction wrote a reason; that is what the vendor
  -- should read, not a stock phrase naming a role that may not have done it
  select pending_fix, pending_fix_why into fix, why from vs_payroll where statement_id = p_stmt;
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

  if fix is not null then
    for e in select * from jsonb_array_elements(fix) loop
      if e->>'kind' = 'head' then
        update vs_version_lines set amount = (e->>'to')::numeric where version_id = newv and head_key = e->>'key';
        ch := ch || jsonb_build_array(jsonb_build_object('label',
          (select head_label from vs_version_lines where version_id = newv and head_key = e->>'key'),
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      else
        perform vs_apply_payroll(p_stmt, newv);
        ch := ch || jsonb_build_array(jsonb_build_object('label','Salary Not Processed From WeVois',
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      end if;
    end loop;
    update vs_payroll set pending_fix = null, pending_fix_why = null, pending_fix_by = null, pending_fix_at = null
     where statement_id = p_stmt;
  end if;

  for pt in select * from vs_points where statement_id = p_stmt and not published
             and status in ('accepted','partial','rejected','carry_forward','disputed_record')
  loop
    if pt.status in ('accepted','partial') then
      if pt.target_kind = 'gross' then
        -- what the partner earned, agreed after the vendor questioned it
        ch := ch || jsonb_build_array(jsonb_build_object('label','Total Expenses Should Be Paid',
          'from', oldgross, 'to', pt.new_amount, 'why', pt.decision));
        update vs_versions set gross_amount = pt.new_amount where id = newv;
      elsif pt.target_kind = 'head'
         and exists (select 1 from vs_version_lines
                      where version_id = newv and head_key = pt.target_key and src = 'manual') then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_lines where version_id=newv and head_key=pt.target_key),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_lines set amount = pt.new_amount where version_id = newv and head_key = pt.target_key;
      elsif pt.target_kind = 'adjustment' then
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
   where statement_id = p_stmt and status in ('open','awaiting_confirm')
     and target_kind <> 'general';
  update vs_statements
     set status = case when opencount > 0 then 'under_query' else 'sent' end,
         due_at = now() + (d + 2) * interval '1 day'
   where id = p_stmt;

  perform vs_log(p_stmt, 'hi', 'Statement v' || (oldn + 1) || ' shared',
    jsonb_array_length(ch) || ' amount change(s) from v' || oldn ||
    '. New final amount ' || vs_version_final(newv) || '.');
  return oldn + 1;
end $$;

-- ---------------------------------------------------------------------------
-- 5. The vendor can attach his own files
-- ---------------------------------------------------------------------------
alter table vs_documents add column if not exists uploaded_uid uuid;

create or replace function vs_add_document(p_stmt uuid, p_path text, p_filename text,
                                           p_kind text, p_mime text, p_size bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; st text; r text;
begin
  r := vs_role();
  if r is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  if not (vs_can('edit_draft') or vs_can('post_payroll') or r = 'vendor') then
    raise exception 'Your role (%) cannot attach documents.', r using errcode = '42501';
  end if;
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if coalesce(trim(p_filename),'') = '' then
    raise exception 'The file needs a name.' using errcode='22023';
  end if;
  insert into vs_documents (statement_id, path, filename, kind, mime, size_bytes,
                            uploaded_by, uploaded_uid)
  values (p_stmt, p_path, p_filename, coalesce(nullif(p_kind,''),'other'),
          coalesce(p_mime,''), coalesce(p_size,0), vs_actor(), auth.uid())
  returning id into nid;
  perform vs_log(p_stmt, '', 'Document attached - ' || p_filename,
    'Kind: ' || coalesce(nullif(p_kind,''),'other') || '. Attached by ' || vs_actor() || '.');
  return nid;
end $$;

-- A vendor may take back only what he himself put up. Staff may remove any of
-- it, with a reason, exactly as before.
create or replace function vs_remove_document(p_doc uuid, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
declare d vs_documents%rowtype; r text;
begin
  r := vs_role();
  select * into d from vs_documents where id = p_doc;
  if not found then raise exception 'No such document.' using errcode='02000'; end if;
  if vs_can('edit_draft') or vs_can('post_payroll') then
    null;
  elsif r = 'vendor' and d.uploaded_uid is not distinct from auth.uid() then
    null;
  else
    raise exception 'You can only remove a file you attached yourself.' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required. Somebody may already have opened this file.'
      using errcode='22023';
  end if;
  delete from vs_documents where id = p_doc;
  perform vs_log(d.statement_id, 'warn', 'Document removed - ' || d.filename, trim(p_reason));
  return d.path;
end $$;

do $do$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage schema not present - skipping storage policies';
    return;
  end if;
  execute 'drop policy if exists p_vsdocs_write  on storage.objects';
  execute 'drop policy if exists p_vsdocs_delete on storage.objects';
  execute $p$
    create policy p_vsdocs_write on storage.objects for insert to authenticated
    with check (
      bucket_id = 'vs-docs'
      and array_length(storage.foldername(name),1) >= 1
      and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
      and vs_sees(((storage.foldername(name))[1])::uuid)
      and (vs_can('edit_draft') or vs_can('post_payroll') or vs_role() = 'vendor')
    )$p$;
  execute $p$
    create policy p_vsdocs_delete on storage.objects for delete to authenticated
    using (
      bucket_id = 'vs-docs'
      and (vs_can('edit_draft') or vs_can('post_payroll') or vs_role() = 'vendor')
    )$p$;
end $do$;

-- ---------------------------------------------------------------------------
-- 6. Payroll that arrives in pieces
-- ---------------------------------------------------------------------------
-- The first posting is the month as Accounts or the manager knew it then. When
-- people left off that run are processed later, the top-up goes on as its own
-- entry with its own challan and date. vs_payroll keeps the running total, so
-- everything downstream - the derived heads, the statement, the vendor's copy -
-- is unchanged; the entries are what let you see how the total was reached.
create table if not exists vs_payroll_batches (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  seq          int  not null,
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
  pf_trrn      text not null default '',
  pf_paid_on   date,
  esic_challan text not null default '',
  esic_paid_on date,
  processed_on date,
  note         text not null default '',
  posted_by    text not null,
  posted_at    timestamptz not null default now(),
  unique (statement_id, seq)
);
create index if not exists vs_payroll_batches_idx on vs_payroll_batches (statement_id, seq);

alter table vs_payroll_batches enable row level security;
revoke all on table vs_payroll_batches from anon, authenticated;
grant select on table vs_payroll_batches to authenticated;
drop policy if exists p_prbatch_r on vs_payroll_batches;
create policy p_prbatch_r on vs_payroll_batches for select to authenticated
  using (vs_sees(statement_id));

create or replace function vs_add_payroll_batch(p_stmt uuid, p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare st text; nseq int; vid uuid; already bool; det text; heads int;
begin
  perform vs_require('post_payroll');
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st = 'paid' then raise exception 'This settlement is closed.' using errcode='42501'; end if;
  select (status = 'posted') into already from vs_payroll where statement_id = p_stmt;
  if not coalesce(already,false) then
    raise exception 'Post the month first. A top-up only makes sense on top of a posting.'
      using errcode='22023';
  end if;
  if coalesce(p->>'pf_trrn','') = '' or coalesce(p->>'esic_challan','') = '' then
    raise exception 'PF TRRN and ESIC challan are both required on a top-up too. They are what the vendor verifies against.'
      using errcode='22023';
  end if;
  if coalesce(trim(p->>'note'),'') = '' then
    raise exception 'Say why this batch is going on late. The vendor sees it.' using errcode='22023';
  end if;
  if coalesce((p->>'dh_pay')::numeric,0) + coalesce((p->>'stf_pay')::numeric,0) <= 0 then
    raise exception 'A top-up with no wages and no salary in it would change nothing.' using errcode='22023';
  end if;

  select coalesce(max(seq),1) + 1 into nseq from vs_payroll_batches where statement_id = p_stmt;

  insert into vs_payroll_batches (statement_id, seq,
    dh_pay, dh_heads, dh_pf_ee, dh_pf_er, dh_esic_ee, dh_esic_er,
    stf_pay, stf_heads, stf_pf_ee, stf_pf_er, stf_esic_ee, stf_esic_er,
    pf_trrn, pf_paid_on, esic_challan, esic_paid_on, processed_on, note, posted_by)
  values (p_stmt, nseq,
    coalesce((p->>'dh_pay')::numeric,0), coalesce((p->>'dh_heads')::int,0),
    coalesce((p->>'dh_pf_ee')::numeric,0), coalesce((p->>'dh_pf_er')::numeric,0),
    coalesce((p->>'dh_esic_ee')::numeric,0), coalesce((p->>'dh_esic_er')::numeric,0),
    coalesce((p->>'stf_pay')::numeric,0), coalesce((p->>'stf_heads')::int,0),
    coalesce((p->>'stf_pf_ee')::numeric,0), coalesce((p->>'stf_pf_er')::numeric,0),
    coalesce((p->>'stf_esic_ee')::numeric,0), coalesce((p->>'stf_esic_er')::numeric,0),
    p->>'pf_trrn', nullif(p->>'pf_paid_on','')::date,
    p->>'esic_challan', nullif(p->>'esic_paid_on','')::date,
    nullif(p->>'processed_on','')::date, trim(p->>'note'), vs_actor());

  update vs_payroll set
    dh_pay = dh_pay + coalesce((p->>'dh_pay')::numeric,0),
    dh_heads = dh_heads + coalesce((p->>'dh_heads')::int,0),
    dh_pf_ee = dh_pf_ee + coalesce((p->>'dh_pf_ee')::numeric,0),
    dh_pf_er = dh_pf_er + coalesce((p->>'dh_pf_er')::numeric,0),
    dh_esic_ee = dh_esic_ee + coalesce((p->>'dh_esic_ee')::numeric,0),
    dh_esic_er = dh_esic_er + coalesce((p->>'dh_esic_er')::numeric,0),
    stf_pay = stf_pay + coalesce((p->>'stf_pay')::numeric,0),
    stf_heads = stf_heads + coalesce((p->>'stf_heads')::int,0),
    stf_pf_ee = stf_pf_ee + coalesce((p->>'stf_pf_ee')::numeric,0),
    stf_pf_er = stf_pf_er + coalesce((p->>'stf_pf_er')::numeric,0),
    stf_esic_ee = stf_esic_ee + coalesce((p->>'stf_esic_ee')::numeric,0),
    stf_esic_er = stf_esic_er + coalesce((p->>'stf_esic_er')::numeric,0),
    posted_by = vs_actor(), posted_at = now()
  where statement_id = p_stmt;

  select dh_heads + stf_heads into heads from vs_payroll where statement_id = p_stmt;
  det := 'Top-up ' || nseq || ': ' ||
         coalesce((p->>'dh_heads')::int,0) + coalesce((p->>'stf_heads')::int,0) ||
         ' more person(s), wages ' || coalesce((p->>'dh_pay')::numeric,0) ||
         ', staff salary ' || coalesce((p->>'stf_pay')::numeric,0) ||
         '. PF TRRN ' || (p->>'pf_trrn') || ', ESIC challan ' || (p->>'esic_challan') ||
         '. The month now totals ' || heads || ' persons. "' || trim(p->>'note') || '"';

  vid := vs_current_version(p_stmt);
  if st = 'draft' then
    perform vs_apply_payroll(p_stmt, vid);
    perform vs_log(p_stmt, 'pay', 'Payroll top-up posted', det);
    return 'posted';
  end if;

  update vs_payroll
     set pending_fix = vs_payroll_diff(p_stmt, vid),
         pending_fix_why = 'Salary processed late: ' || trim(p->>'note'),
         pending_fix_by = vs_actor(), pending_fix_at = now()
   where statement_id = p_stmt;
  perform vs_log(p_stmt, 'warn', 'Payroll top-up parked for the next version', det);
  return 'parked';
end $$;

-- The first posting is batch 1, recorded the same way so the entries read as
-- one list rather than "the original, plus some others".
create or replace function vs_sync_first_batch(p_stmt uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype;
begin
  select * into pr from vs_payroll where statement_id = p_stmt;
  if not found or pr.status <> 'posted' then return; end if;
  insert into vs_payroll_batches (statement_id, seq,
    dh_pay, dh_heads, dh_pf_ee, dh_pf_er, dh_esic_ee, dh_esic_er,
    stf_pay, stf_heads, stf_pf_ee, stf_pf_er, stf_esic_ee, stf_esic_er,
    pf_trrn, pf_paid_on, esic_challan, esic_paid_on, processed_on, note, posted_by, posted_at)
  values (p_stmt, 1, pr.dh_pay, pr.dh_heads, pr.dh_pf_ee, pr.dh_pf_er, pr.dh_esic_ee, pr.dh_esic_er,
    pr.stf_pay, pr.stf_heads, pr.stf_pf_ee, pr.stf_pf_er, pr.stf_esic_ee, pr.stf_esic_er,
    pr.pf_trrn, pr.pf_paid_on, pr.esic_challan, pr.esic_paid_on, pr.processed_on,
    'The month as posted.', coalesce(pr.posted_by,'unknown'), coalesce(pr.posted_at, now()))
  on conflict (statement_id, seq) do update set
    dh_pay = excluded.dh_pay, dh_heads = excluded.dh_heads,
    dh_pf_ee = excluded.dh_pf_ee, dh_pf_er = excluded.dh_pf_er,
    dh_esic_ee = excluded.dh_esic_ee, dh_esic_er = excluded.dh_esic_er,
    stf_pay = excluded.stf_pay, stf_heads = excluded.stf_heads,
    stf_pf_ee = excluded.stf_pf_ee, stf_pf_er = excluded.stf_pf_er,
    stf_esic_ee = excluded.stf_esic_ee, stf_esic_er = excluded.stf_esic_er,
    pf_trrn = excluded.pf_trrn, esic_challan = excluded.esic_challan,
    posted_by = excluded.posted_by, posted_at = excluded.posted_at;
end $$;


-- The generic wording no longer names Accounts, because the vendor manager can
-- post a payroll too. Where a reason was written it is used instead of this.
create or replace function vs_payroll_diff(p_stmt uuid, p_ver uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype; out jsonb := '[]'::jsonb; cur numeric;
        w text := 'Payroll correction posted.';
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select * into pr from vs_payroll where statement_id = p_stmt;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages';
  if cur is distinct from pr.dh_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages','from',cur,'to',pr.dh_pay,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_ee';
  if cur is distinct from pr.dh_pf_ee + pr.dh_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_ee','from',cur,'to',pr.dh_pf_ee+pr.dh_esic_ee,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_er';
  if cur is distinct from pr.dh_pf_er + pr.dh_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_er','from',cur,'to',pr.dh_pf_er+pr.dh_esic_er,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='salary';
  if cur is distinct from pr.stf_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','salary','from',cur,'to',pr.stf_pay,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_ee';
  if cur is distinct from pr.stf_pf_ee + pr.stf_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_ee','from',cur,'to',pr.stf_pf_ee+pr.stf_esic_ee,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_er';
  if cur is distinct from pr.stf_pf_er + pr.stf_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_er','from',cur,'to',pr.stf_pf_er+pr.stf_esic_er,'why',w)); end if;
  select coalesce(amount,0) into cur from vs_version_adj where version_id=p_ver and payroll_linked;
  if coalesce(cur,0) is distinct from pr.not_processed_amount then out := out || jsonb_build_array(jsonb_build_object(
    'kind','adj','key','not_processed','from',coalesce(cur,0),'to',pr.not_processed_amount,'why',w)); end if;
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Remarks and payroll entries ride along in the same single call
-- ---------------------------------------------------------------------------
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
    'adj_types', (select coalesce(jsonb_agg(to_jsonb(t) order by t.sort),'[]'::jsonb)
                    from vs_adj_types t where t.active),
    'payroll', to_jsonb(pr),
    'payroll_batches', (select coalesce(jsonb_agg(to_jsonb(b) order by b.seq),'[]'::jsonb)
                    from vs_payroll_batches b where b.statement_id = s.id),
    'paid_total', vs_paid_total(s.id),
    'documents', (select coalesce(jsonb_agg(to_jsonb(dc) order by dc.uploaded_at),'[]'::jsonb)
                    from vs_documents dc where dc.statement_id = s.id),
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
    'points',   (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'target_kind', p.target_kind, 'target_key', p.target_key,
        'target_label', p.target_label, 'source', p.source, 'raised_by', p.raised_by,
        'raised_at', p.raised_at, 'version_no', p.version_no, 'claimed', p.claimed,
        'note', p.note, 'attachment', p.attachment, 'status', p.status,
        'confirmed_at', p.confirmed_at, 'decision', p.decision, 'decided_by', p.decided_by,
        'decided_at', p.decided_at, 'new_amount', p.new_amount, 'published', p.published,
        'published_in', p.published_in,
        'remarks', (select coalesce(jsonb_agg(to_jsonb(rm) order by rm.at),'[]'::jsonb)
                      from vs_point_remarks rm where rm.point_id = p.id)
      ) order by p.raised_at), '[]'::jsonb)
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

-- The original posting logic, unchanged, renamed so the wrapper below can add
-- the batch record without touching a line of the arithmetic.
create or replace function vs_post_payroll_base(p_stmt uuid, p jsonb)
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

-- the first posting records itself as batch 1, so the entries read as one list
create or replace function vs_post_payroll(p_stmt uuid, p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare r text;
begin
  r := vs_post_payroll_base(p_stmt, p);
  perform vs_sync_first_batch(p_stmt);
  return r;
end $$;

grant execute on function
  vs_raise_query(uuid,text,text), vs_answer_query(uuid,text), vs_add_remark(uuid,text),
  vs_add_payroll_batch(uuid,jsonb), vs_sync_first_batch(uuid),
  vs_post_payroll_base(uuid,jsonb)
to authenticated;

-- ---------------------------------------------------------------- verification
select
  (select count(*) = 1 from pg_proc where proname='vs_raise_query')        as query_fn,
  (select count(*) = 1 from pg_proc where proname='vs_answer_query')       as answer_fn,
  (select count(*) = 1 from pg_proc where proname='vs_add_remark')         as remark_fn,
  (select count(*) = 1 from pg_proc where proname='vs_add_payroll_batch')  as topup_fn,
  (select count(*) = 1 from information_schema.tables
     where table_name='vs_point_remarks')                                  as remarks_table,
  (select count(*) = 1 from information_schema.tables
     where table_name='vs_payroll_batches')                                as batches_table;
-- Expect: t | t | t | t | t | t


-- ############################################################################
-- ##  PART 7 of 10 - VS-PATCH-6.sql
-- ##  email when a month goes out, and confirmation from the CEO or the VP
-- ############################################################################

-- VS-PATCH-6.sql
-- ============================================================================
-- Two things:
--
--   1. When a monthly amount goes out, the people who should know are told by
--      email. The CEO and the VP hear about every site; each vendor hears only
--      about his own. The portal writes the mail into an outbox; a small
--      function on Supabase sends it from your office address. If the sender is
--      not set up yet, the mail still queues and is still visible - nothing is
--      lost, it just waits.
--
--   2. The vendor manager can put a question or a figure to the CEO or the VP
--      and get a written yes or no. Where the request carries an amount, an
--      approval writes that amount onto the statement itself as an adjustment,
--      with the approver's name and the date as its reason.
--
-- On the second one, read this before you run it. The CEO and the VP have been
-- strict observers until now: every write refused, proved by assertions that
-- try it as them. That does not change wholesale. They get exactly ONE new
-- thing they can do - answer a request that was put to them - and they are
-- still refused everything else, including raising the request in the first
-- place. Somebody has to ask before they can answer.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-5.
-- Safe to re-run. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Where the mail is addressed from, and what it links back to
-- ---------------------------------------------------------------------------
alter table vs_settings add column if not exists mail_from    text not null default '';
alter table vs_settings add column if not exists mail_from_nm text not null default 'WeVois Vendor Settlement';
alter table vs_settings add column if not exists portal_url   text not null default '';
alter table vs_settings add column if not exists mail_on      bool not null default true;

create or replace function vs_save_mail_settings(p_from text, p_name text, p_url text, p_on bool)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vs_require('manage_masters');
  update vs_settings
     set mail_from    = coalesce(trim(p_from), mail_from),
         mail_from_nm = coalesce(nullif(trim(p_name),''), mail_from_nm),
         portal_url   = coalesce(trim(p_url), portal_url),
         mail_on      = coalesce(p_on, mail_on)
   where id = 1;
  perform vs_audit_log('Mail settings changed',
    'From ' || coalesce(nullif(trim(p_from),''),'(not set)') ||
    ', notifications ' || case when coalesce(p_on,true) then 'ON' else 'OFF' end);
end $$;

-- ---------------------------------------------------------------------------
-- 2. The outbox
-- ---------------------------------------------------------------------------
-- Every message the portal wants sent, whether or not a sender is configured.
-- It is a record like everything else here: who it went to, what it said, and
-- whether it actually left.
create table if not exists vs_mail (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid references vs_statements(id) on delete set null,
  kind         text not null default 'shared',
  to_email     text not null,
  to_name      text not null default '',
  to_role      text not null default '',
  subject      text not null,
  body_text    text not null,
  body_html    text not null default '',
  status       text not null default 'queued' check (status in ('queued','sent','failed','skipped')),
  attempts     int  not null default 0,
  error        text not null default '',
  created_at   timestamptz not null default now(),
  sent_at      timestamptz
);
create index if not exists vs_mail_queue_idx on vs_mail (status, created_at);
create index if not exists vs_mail_stmt_idx  on vs_mail (statement_id);

alter table vs_mail enable row level security;
revoke all on table vs_mail from anon, authenticated;
grant select on table vs_mail to authenticated;
drop policy if exists p_mail_r on vs_mail;
-- staff see the outbox; a vendor does not need to watch other people's post
create policy p_mail_r on vs_mail for select to authenticated using (vs_can('view_all'));

create or replace function vs_queue_mail(p_stmt uuid, p_kind text, p_email text, p_name text,
                                         p_role text, p_subject text, p_text text, p_html text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; on_ bool;
begin
  select mail_on into on_ from vs_settings where id = 1;
  if coalesce(trim(p_email),'') = '' then return null; end if;
  insert into vs_mail (statement_id, kind, to_email, to_name, to_role, subject, body_text, body_html, status)
  values (p_stmt, p_kind, lower(trim(p_email)), coalesce(p_name,''), coalesce(p_role,''),
          p_subject, p_text, coalesce(p_html,''),
          case when coalesce(on_,true) then 'queued' else 'skipped' end)
  returning id into nid;
  return nid;
end $$;

-- ---------------------------------------------------------------------------
-- 3. The message itself
-- ---------------------------------------------------------------------------
create or replace function vs_notify_shared(p_stmt uuid, p_kind text default 'shared')
returns int language plpgsql security definer set search_path = public as $$
declare s record; vno int; fin numeric; n int := 0; r record; url text; org text;
        subj text; body text; html text; whatv text; whats text;
begin
  select st.id, st.period, st.covers_from, st.covers_to, v.name as vendor, v.id as vendor_id,
         si.name as site
    into s
    from vs_statements st
    join vs_contracts c on c.id = st.contract_id
    join vs_vendors   v on v.id = c.vendor_id
    join vs_sites    si on si.id = c.site_id
   where st.id = p_stmt;
  if not found then return 0; end if;

  select v into vno from vs_versions where id = vs_current_version(p_stmt);
  fin := vs_version_final(vs_current_version(p_stmt));
  select coalesce(nullif(portal_url,''),''), coalesce(nullif(org_name,''),'WeVois')
    into url, org from vs_settings where id = 1;

  whats := case when p_kind = 'revised' then 'Revised statement' else 'Statement' end;

  -- the vendor: his own site only
  subj := org || ' - ' || s.site || ' - ' || vs_period_label(s.period) || ' - ' ||
          to_char(fin, 'FM99,99,99,999') ;
  body := 'Dear ' || s.vendor || ',' || chr(10) || chr(10) ||
     whats || ' version ' || vno || ' for ' || s.site || ', ' || vs_period_label(s.period) ||
     ' is now on the portal.' || chr(10) || chr(10) ||
     'Amount for payment: ' || to_char(fin, 'FM99,99,99,999') || chr(10) ||
     'Covering: ' || to_char(s.covers_from,'DD Mon YYYY') || ' to ' || to_char(s.covers_to,'DD Mon YYYY') || chr(10) ||
     chr(10) ||
     'Please open the portal to check it line by line. If you disagree with any figure, raise a point on that '||
     'exact line so it can be checked and answered in writing. If anything else needs saying, use the Queries tab.' ||
     chr(10) || chr(10) ||
     case when url <> '' then url || chr(10) || chr(10) else '' end ||
     'This is an automatic message from the ' || org || ' vendor settlement portal.';
  html := '<p>Dear ' || s.vendor || ',</p><p>' || whats || ' <b>version ' || vno || '</b> for <b>' ||
     s.site || '</b>, ' || vs_period_label(s.period) || ' is now on the portal.</p>' ||
     '<p style="font-size:20px"><b>' || to_char(fin,'FM99,99,99,999') || '</b><br>' ||
     '<span style="color:#666;font-size:13px">covering ' || to_char(s.covers_from,'DD Mon YYYY') ||
     ' to ' || to_char(s.covers_to,'DD Mon YYYY') || '</span></p>' ||
     '<p>Please open the portal and check it line by line. If you disagree with a figure, raise a point on that ' ||
     'exact line so it can be checked and answered in writing.</p>' ||
     case when url <> '' then '<p><a href="' || url || '">Open the portal</a></p>' else '' end ||
     '<p style="color:#888;font-size:12px">Automatic message from the ' || org || ' vendor settlement portal.</p>';

  for r in select p.email, p.full_name from vs_profiles p
            where p.role = 'vendor' and p.active and p.vendor_id = s.vendor_id loop
    perform vs_queue_mail(p_stmt, p_kind, r.email, r.full_name, 'vendor', subj, body, html);
    n := n + 1;
  end loop;

  -- the CEO and the VP: every site
  whatv := whats || ' sent - ' || s.site || ' - ' || s.vendor;
  subj := org || ' - ' || whatv || ' - ' || vs_period_label(s.period);
  body := whats || ' version ' || vno || ' has gone to the vendor.' || chr(10) || chr(10) ||
     'Site: ' || s.site || chr(10) ||
     'Partner: ' || s.vendor || chr(10) ||
     'Month: ' || vs_period_label(s.period) || chr(10) ||
     'Amount for payment: ' || to_char(fin, 'FM99,99,99,999') || chr(10) || chr(10) ||
     case when url <> '' then url || chr(10) || chr(10) else '' end ||
     'You are receiving this because you have observer access to every site.';
  html := '<p>' || whats || ' <b>version ' || vno || '</b> has gone to the vendor.</p>' ||
     '<table style="font-size:14px"><tr><td style="color:#666;padding-right:14px">Site</td><td><b>' || s.site ||
     '</b></td></tr><tr><td style="color:#666">Partner</td><td>' || s.vendor ||
     '</td></tr><tr><td style="color:#666">Month</td><td>' || vs_period_label(s.period) ||
     '</td></tr><tr><td style="color:#666">Amount</td><td><b>' || to_char(fin,'FM99,99,99,999') ||
     '</b></td></tr></table>' ||
     case when url <> '' then '<p><a href="' || url || '">Open the portal</a></p>' else '' end ||
     '<p style="color:#888;font-size:12px">You receive this because you have observer access to every site.</p>';

  for r in select p.email, p.full_name, p.role from vs_profiles p
            where p.role in ('ceo','vp') and p.active loop
    perform vs_queue_mail(p_stmt, p_kind, r.email, r.full_name, r.role, subj, body, html);
    n := n + 1;
  end loop;

  return n;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Sharing tells people
-- ---------------------------------------------------------------------------
-- The mail is queued inside its own block. A settlement going out must never
-- fail because the post did not.
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
    raise exception 'The processed salary and PF/ESIC have not been posted for this month yet. The statement cannot go out until they are.'
      using errcode='42501';
  end if;
  vid := vs_current_version(p_stmt);
  select window_days into d from vs_settings where id = 1;
  update vs_versions set sent_at = now() where id = vid;
  update vs_statements set status = 'sent', due_at = now() + (d + 2) * interval '1 day' where id = p_stmt;
  perform vs_log(p_stmt, 'hi', 'Statement v' || (select v from vs_versions where id=vid) || ' shared',
    'Final amount ' || vs_version_final(vid) || '. Response window ' || d || ' working days.');
  begin
    perform vs_notify_shared(p_stmt, 'shared');
  exception when others then
    perform vs_log(p_stmt, 'warn', 'Notification could not be queued', sqlerrm);
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Asking the CEO or the VP
-- ---------------------------------------------------------------------------
create table if not exists vs_approvals (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  question     text not null,
  amount       numeric(14,2),
  effect       text check (effect in ('add','deduct')),
  adj_label    text not null default '',
  asked_by     text not null,
  asked_uid    uuid,
  asked_at     timestamptz not null default now(),
  status       text not null default 'open' check (status in ('open','approved','declined')),
  decided_by   text,
  decided_role text,
  decided_at   timestamptz,
  decision_note text not null default '',
  applied      bool not null default false,
  applied_in   int
);
create index if not exists vs_approvals_idx on vs_approvals (statement_id, asked_at);

alter table vs_approvals enable row level security;
revoke all on table vs_approvals from anon, authenticated;
grant select on table vs_approvals to authenticated;
drop policy if exists p_appr_r on vs_approvals;
-- the vendor does not see what WeVois asked its own leadership
create policy p_appr_r on vs_approvals for select to authenticated using (vs_can('view_all'));

insert into vs_caps (role, cap) values ('ceo','approve_request'), ('vp','approve_request')
on conflict do nothing;

create or replace function vs_request_approval(p_stmt uuid, p_question text, p_amount numeric,
                                               p_effect text, p_label text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; nm text; sn text; r record; url text; org text; subj text; body text; html text;
begin
  perform vs_require('revise');           -- the vendor manager, and the admin
  if not exists (select 1 from vs_statements where id = p_stmt) then
    raise exception 'No such settlement.' using errcode='02000';
  end if;
  if coalesce(trim(p_question),'') = '' then
    raise exception 'Write down what you are asking. That text is what they answer.' using errcode='22023';
  end if;
  if p_amount is not null then
    if p_amount = 0 then
      raise exception 'An amount of zero would change nothing. Leave it blank to ask a plain question.'
        using errcode='22023';
    end if;
    if coalesce(p_effect,'') not in ('add','deduct') then
      raise exception 'Say whether the amount is added to the partner or deducted from him.' using errcode='22023';
    end if;
    if coalesce(trim(p_label),'') = '' then
      raise exception 'The amount needs a label. It becomes the line the vendor reads.' using errcode='22023';
    end if;
  end if;

  insert into vs_approvals (statement_id, question, amount, effect, adj_label, asked_by, asked_uid)
  values (p_stmt, trim(p_question), p_amount, nullif(p_effect,''), coalesce(trim(p_label),''),
          vs_actor(), auth.uid())
  returning id into nid;

  perform vs_log(p_stmt, 'warn', 'Sent to the CEO and VP for confirmation',
    trim(p_question) ||
    case when p_amount is not null
      then ' [' || trim(p_label) || ' ' || p_effect || ' ' || p_amount || ']' else '' end);

  select v.name || ' - ' || si.name into sn
    from vs_statements st join vs_contracts c on c.id = st.contract_id
    join vs_vendors v on v.id = c.vendor_id join vs_sites si on si.id = c.site_id
   where st.id = p_stmt;
  select coalesce(nullif(portal_url,''),''), coalesce(nullif(org_name,''),'WeVois')
    into url, org from vs_settings where id = 1;

  subj := org || ' - your confirmation is needed - ' || sn;
  body := vs_actor() || ' has asked for your confirmation on ' || sn || '.' || chr(10) || chr(10) ||
    trim(p_question) || chr(10) || chr(10) ||
    case when p_amount is not null
      then 'Proposed: ' || trim(p_label) || ', ' ||
           case p_effect when 'add' then 'added to' else 'deducted from' end ||
           ' the partner, ' || to_char(p_amount,'FM99,99,99,999') || chr(10) ||
           'If you approve, that line is written onto the statement with your name against it.' || chr(10) || chr(10)
      else '' end ||
    case when url <> '' then url || chr(10) || chr(10) else '' end ||
    'Approve or decline it in the portal. Either way your answer is recorded in writing.';
  html := '<p><b>' || vs_actor() || '</b> has asked for your confirmation on <b>' || sn || '</b>.</p>' ||
    '<blockquote style="border-left:3px solid #ccc;padding-left:12px;color:#333">' || trim(p_question) || '</blockquote>' ||
    case when p_amount is not null
      then '<p>Proposed: <b>' || trim(p_label) || '</b>, ' ||
           case p_effect when 'add' then 'added to' else 'deducted from' end || ' the partner, <b>' ||
           to_char(p_amount,'FM99,99,99,999') || '</b><br><span style="color:#666;font-size:13px">' ||
           'If you approve, that line is written onto the statement with your name against it.</span></p>'
      else '' end ||
    case when url <> '' then '<p><a href="' || url || '">Open the portal</a></p>' else '' end;

  for r in select p.email, p.full_name, p.role from vs_profiles p
            where p.role in ('ceo','vp') and p.active loop
    perform vs_queue_mail(p_stmt, 'approval', r.email, r.full_name, r.role, subj, body, html);
  end loop;
  return nid;
end $$;

-- The one thing an observer may do. Note what it does NOT allow: raising the
-- request, editing the question, changing the amount, or touching anything else
-- on the settlement.
create or replace function vs_decide_approval(p_id uuid, p_ok bool, p_note text)
returns text language plpgsql security definer set search_path = public as $$
declare ap vs_approvals%rowtype; st text; vid uuid; org text; url text; r record;
begin
  perform vs_require('approve_request');
  select * into ap from vs_approvals where id = p_id;
  if not found then raise exception 'No such request.' using errcode='02000'; end if;
  if ap.status <> 'open' then
    raise exception 'That was already % by %.', ap.status, ap.decided_by using errcode='22023';
  end if;
  if p_ok is null then raise exception 'Approve it or decline it.' using errcode='22023'; end if;
  if not p_ok and coalesce(trim(p_note),'') = '' then
    raise exception 'Say why you are declining. That reason is the record.' using errcode='22023';
  end if;

  update vs_approvals
     set status = case when p_ok then 'approved' else 'declined' end,
         decided_by = vs_actor(), decided_role = vs_role(), decided_at = now(),
         decision_note = coalesce(trim(p_note),'')
   where id = p_id;

  perform vs_log(ap.statement_id, case when p_ok then 'ok' else 'warn' end,
    case when p_ok then 'Confirmed by ' || vs_actor() else 'Declined by ' || vs_actor() end,
    ap.question || case when coalesce(trim(p_note),'') <> '' then ' -- "' || trim(p_note) || '"' else '' end);

  if not p_ok or ap.amount is null then
    return case when p_ok then 'approved' else 'declined' end;
  end if;

  -- an approved amount becomes a line on the statement
  select status into st from vs_statements where id = ap.statement_id;
  vid := vs_current_version(ap.statement_id);
  if st = 'draft' then
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (vid, ap.adj_label, ap.effect, ap.amount,
            'Approved by ' || vs_actor() || ' (' || vs_role() || ') on ' ||
            to_char(now(),'DD Mon YYYY') || '. ' || ap.question, 900);
    update vs_approvals set applied = true where id = p_id;
    perform vs_log(ap.statement_id, 'ok', 'Approved amount added to the draft',
      ap.adj_label || ' ' || ap.effect || ' ' || ap.amount || ', on ' || vs_actor() || '''s approval.');
    return 'approved and applied';
  end if;

  perform vs_log(ap.statement_id, 'warn', 'Approved amount waiting for the next version',
    ap.adj_label || ' ' || ap.effect || ' ' || ap.amount ||
    ' will appear when the vendor manager issues the next version.');
  return 'approved, lands on the next version';
end $$;

-- ---------------------------------------------------------------------------
-- 6. An approved amount lands with the next version
-- ---------------------------------------------------------------------------
create or replace function vs_apply_approvals(p_stmt uuid, p_ver uuid, p_vno int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ap record; ch jsonb := '[]'::jsonb;
begin
  for ap in select * from vs_approvals
             where statement_id = p_stmt and status = 'approved' and not applied and amount is not null
             order by asked_at loop
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (p_ver, ap.adj_label, ap.effect, ap.amount,
            'Approved by ' || ap.decided_by || ' on ' || to_char(ap.decided_at,'DD Mon YYYY') || '. ' || ap.question, 900);
    ch := ch || jsonb_build_array(jsonb_build_object('label', ap.adj_label, 'from', 0, 'to',
            case ap.effect when 'deduct' then -ap.amount else ap.amount end,
            'why', 'Approved by ' || ap.decided_by || '. ' || ap.question));
    update vs_approvals set applied = true, applied_in = p_vno where id = ap.id;
  end loop;
  return ch;
end $$;


-- ---------------------------------------------------------------------------
-- 7. The revision picks up approved amounts, and tells people again
-- ---------------------------------------------------------------------------
create or replace function vs_issue_revision(p_stmt uuid)
returns int language plpgsql security definer set search_path = public as $$
declare oldv uuid; oldn int; newv uuid; ch jsonb := '[]'::jsonb; n int := 0;
        pt record; fix jsonb; e jsonb; d int; opencount int; oldgross numeric; why text;
        appr int;
begin
  perform vs_require('revise');
  oldv := vs_current_version(p_stmt);
  select v, gross_amount into oldn, oldgross from vs_versions where id = oldv;

  select pending_fix, pending_fix_why into fix, why from vs_payroll where statement_id = p_stmt;
  if fix is not null and jsonb_array_length(fix) > 0 then n := n + 1; end if;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and not published
     and status in ('accepted','partial','rejected','carry_forward','disputed_record');
  n := n + opencount;
  select count(*) into appr from vs_approvals
   where statement_id = p_stmt and status = 'approved' and not applied and amount is not null;
  n := n + appr;
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

  if fix is not null then
    for e in select * from jsonb_array_elements(fix) loop
      if e->>'kind' = 'head' then
        update vs_version_lines set amount = (e->>'to')::numeric where version_id = newv and head_key = e->>'key';
        ch := ch || jsonb_build_array(jsonb_build_object('label',
          (select head_label from vs_version_lines where version_id = newv and head_key = e->>'key'),
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      else
        perform vs_apply_payroll(p_stmt, newv);
        ch := ch || jsonb_build_array(jsonb_build_object('label','Salary Not Processed From WeVois',
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      end if;
    end loop;
    update vs_payroll set pending_fix = null, pending_fix_why = null, pending_fix_by = null, pending_fix_at = null
     where statement_id = p_stmt;
  end if;

  for pt in select * from vs_points where statement_id = p_stmt and not published
             and status in ('accepted','partial','rejected','carry_forward','disputed_record')
  loop
    if pt.status in ('accepted','partial') then
      if pt.target_kind = 'gross' then
        ch := ch || jsonb_build_array(jsonb_build_object('label','Total Expenses Should Be Paid',
          'from', oldgross, 'to', pt.new_amount, 'why', pt.decision));
        update vs_versions set gross_amount = pt.new_amount where id = newv;
      elsif pt.target_kind = 'head'
         and exists (select 1 from vs_version_lines
                      where version_id = newv and head_key = pt.target_key and src = 'manual') then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_lines where version_id=newv and head_key=pt.target_key),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_lines set amount = pt.new_amount where version_id = newv and head_key = pt.target_key;
      elsif pt.target_kind = 'adjustment' then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_adj where version_id=newv and label=pt.target_label),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_adj set amount = pt.new_amount
         where version_id = newv and label = pt.target_label;
      end if;
    end if;
    update vs_points set published = true, published_in = oldn + 1 where id = pt.id;
  end loop;

  -- anything the CEO or VP approved that has not gone on yet
  ch := ch || vs_apply_approvals(p_stmt, newv, oldn + 1);

  update vs_versions set changes = ch,
    note = n || ' item(s) answered. ' || jsonb_array_length(ch) || ' amount(s) changed.'
   where id = newv;

  select window_days into d from vs_settings where id = 1;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and status in ('open','awaiting_confirm')
     and target_kind <> 'general';
  update vs_statements
     set status = case when opencount > 0 then 'under_query' else 'sent' end,
         due_at = now() + (d + 2) * interval '1 day'
   where id = p_stmt;

  perform vs_log(p_stmt, 'hi', 'Statement v' || (oldn + 1) || ' shared',
    jsonb_array_length(ch) || ' amount change(s) from v' || oldn ||
    '. New final amount ' || vs_version_final(newv) || '.');
  begin
    perform vs_notify_shared(p_stmt, 'revised');
  exception when others then
    perform vs_log(p_stmt, 'warn', 'Notification could not be queued', sqlerrm);
  end;
  return oldn + 1;
end $$;

-- the app reads approvals and the outbox with everything else
create or replace function vs_statement_extra(p_stmt uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  return jsonb_build_object(
    'approvals', case when vs_can('view_all') then
       (select coalesce(jsonb_agg(to_jsonb(a) order by a.asked_at),'[]'::jsonb)
          from vs_approvals a where a.statement_id = p_stmt) else '[]'::jsonb end,
    'mail', case when vs_can('view_all') then
       (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'to_email',m.to_email,'to_name',m.to_name,
                'to_role',m.to_role,'subject',m.subject,'status',m.status,'error',m.error,
                'created_at',m.created_at,'sent_at',m.sent_at) order by m.created_at desc),'[]'::jsonb)
          from vs_mail m where m.statement_id = p_stmt) else '[]'::jsonb end);
end $$;

grant execute on function vs_statement_extra(uuid) to authenticated;

grant execute on function
  vs_save_mail_settings(text,text,text,bool), vs_queue_mail(uuid,text,text,text,text,text,text,text),
  vs_notify_shared(uuid,text), vs_request_approval(uuid,text,numeric,text,text),
  vs_decide_approval(uuid,bool,text), vs_apply_approvals(uuid,uuid,int),
  vs_statement_extra(uuid)
to authenticated;

-- ---------------------------------------------------------------- verification
select
  (select count(*) = 1 from information_schema.tables where table_name='vs_mail')       as outbox,
  (select count(*) = 1 from information_schema.tables where table_name='vs_approvals')  as approvals,
  (select count(*) = 2 from vs_caps where cap='approve_request')                        as ceo_and_vp,
  (select count(*) = 0 from vs_caps where cap='approve_request'
     and role not in ('ceo','vp'))                                                      as nobody_else,
  (select count(*) = 1 from pg_proc where proname='vs_notify_shared')                   as notifier,
  (select count(*) = 1 from pg_proc where proname='vs_decide_approval')                 as decider;
-- Expect: t | t | t | t | t | t


-- ############################################################################
-- ##  PART 8 of 10 - VS-PATCH-7.sql
-- ##  a head can credit him, or be recorded without being counted
-- ############################################################################

-- VS-PATCH-7.sql
-- ============================================================================
-- Each booking head gets an EFFECT - the same three choices the adjustment
-- lines under the Total already have:
--
--   reduces payment  the head is money WeVois spent for him, taken off what we
--                    pay. This is what every head has always done, and every
--                    head that exists today keeps doing it.
--   credits him      the head is added to what we pay instead of taken off.
--   recorded only    the row appears on the statement with its figure and does
--                    NOT move the Total. This is the payment-record case: a
--                    line that has to be on the sheet because it happened, but
--                    that must not be counted a second time.
--
-- The vendor manager chooses it per month, on the draft, beside the amount.
-- The administrator sets the site's standing choice under Sites & heads, so a
-- head that is always a credit is not re-chosen every month.
--
-- Payroll heads are not offered the choice. Those figures are posted by
-- Accounts out of the PF, ESIC and bank files, and money that has left the
-- company for his men is a deduction by definition. Anything else about a
-- payroll belongs in an adjustment line, where it already can go.
--
-- Run AFTER VS-PATCH-6.sql, in the Supabase SQL editor, selecting the whole
-- file. Safe to re-run. Nothing already shared changes: every line that exists
-- is written as 'deduct', which is exactly what it was, so every historical
-- Final amount stands to the rupee.
-- Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------- 1. columns
alter table vs_head_templates add column if not exists effect text not null default 'deduct';
alter table vs_heads          add column if not exists effect text not null default 'deduct';
alter table vs_version_lines  add column if not exists effect text not null default 'deduct';

do $do$ begin
  if not exists (select 1 from pg_constraint where conname = 'vs_head_templates_effect_ck') then
    alter table vs_head_templates add constraint vs_head_templates_effect_ck
      check (effect in ('add','deduct','note'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vs_heads_effect_ck') then
    alter table vs_heads add constraint vs_heads_effect_ck
      check (effect in ('add','deduct','note'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vs_version_lines_effect_ck') then
    alter table vs_version_lines add constraint vs_version_lines_effect_ck
      check (effect in ('add','deduct','note'));
  end if;
end $do$;

-- ---------------------------------------------------------- 2. the arithmetic
-- vs_version_heads keeps its meaning: THE NET AMOUNT TAKEN OFF the gross. So
-- Total = gross - heads still reads the same, and every screen, every stored
-- change diff and every mail that already quotes it stays correct. A credit
-- head lowers that net; a recorded-only head does not touch it at all.
create or replace function vs_version_heads(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then (select coalesce(sum(case effect when 'add'  then -amount
                                          when 'note' then 0
                                          else amount end), 0)
            from vs_version_lines where version_id = p_ver)
  end
$$;

-- What WeVois actually SPENT under the heads. Not the same number any more:
-- the per-vehicle memo exists to compare one site's running cost against
-- another's, and a credit back to the partner is not a cost of running a site.
create or replace function vs_version_spend(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then (select coalesce(sum(amount) filter (where effect = 'deduct'), 0)
            from vs_version_lines where version_id = p_ver)
  end
$$;

-- ------------------------------------------------- 3. carrying the choice forward
-- A new month starts from the site's standing choice. Payroll heads are
-- forced to reduces-payment whatever the site says.
create or replace function vs_add_statement(p_contract uuid, p_period date)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid; vid uuid; per date; lbl text; sname text;
begin
  perform vs_require('manage_settlements');
  per := date_trunc('month', p_period)::date;
  if not exists (select 1 from vs_contracts c where c.id = p_contract
                  and daterange(c.from_date, coalesce(c.to_date,'infinity'::date), '[]')
                   && daterange(per, (per + interval '1 month - 1 day')::date, '[]')) then
    raise exception 'That vendor was not running this site in %.', vs_period_label(per) using errcode = '22023';
  end if;
  select s.name into sname from vs_contracts c join vs_sites s on s.id = c.site_id where c.id = p_contract;
  if not (select vs_site_open_in(c.site_id, per) from vs_contracts c where c.id = p_contract) then
    raise exception '% was not open in % - check the site''s start and closing dates.',
      sname, vs_period_label(per) using errcode = '22023';
  end if;
  if exists (select 1 from vs_statements where contract_id = p_contract and period = per) then
    raise exception 'That vendor and site already has a settlement for %.', vs_period_label(per)
      using errcode = '23505';
  end if;
  insert into vs_statements (contract_id, period, covers_from, covers_to, created_by)
  select p_contract, per,
         greatest(c.from_date, per),
         least(coalesce(c.to_date,'infinity'::date), (per + interval '1 month - 1 day')::date),
         auth.uid()
    from vs_contracts c where c.id = p_contract
  returning id into sid;
  insert into vs_versions (statement_id, v) values (sid, 1) returning id into vid;
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount, effect)
    select vid, h.id, h.key, h.label, h.grp, h.src, h.sort, 0, h.effect
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

-- A revision inherits the choice that was on the version it corrects.
create or replace function vs_issue_revision(p_stmt uuid)
returns int language plpgsql security definer set search_path = public as $$
declare oldv uuid; oldn int; newv uuid; ch jsonb := '[]'::jsonb; n int := 0;
        pt record; fix jsonb; e jsonb; d int; opencount int; oldgross numeric; why text;
        appr int;
begin
  perform vs_require('revise');
  oldv := vs_current_version(p_stmt);
  select v, gross_amount into oldn, oldgross from vs_versions where id = oldv;

  select pending_fix, pending_fix_why into fix, why from vs_payroll where statement_id = p_stmt;
  if fix is not null and jsonb_array_length(fix) > 0 then n := n + 1; end if;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and not published
     and status in ('accepted','partial','rejected','carry_forward','disputed_record');
  n := n + opencount;
  select count(*) into appr from vs_approvals
   where statement_id = p_stmt and status = 'approved' and not applied and amount is not null;
  n := n + appr;
  if n = 0 then raise exception 'Nothing has been decided yet.' using errcode='22023'; end if;

  insert into vs_versions (statement_id, v, gross_amount, gross_note, sent_at)
    select p_stmt, oldn + 1, gross_amount, gross_note, now() from vs_versions where id = oldv
  returning id into newv;
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount, effect)
    select newv, head_id, head_key, head_label, grp, src, sort, amount, effect
      from vs_version_lines where version_id = oldv;
  insert into vs_version_adj (version_id, adj_type_id, label, effect, amount, reference, note, payroll_linked, sort)
    select newv, adj_type_id, label, effect, amount, reference, note, payroll_linked, sort
      from vs_version_adj where version_id = oldv;

  if fix is not null then
    for e in select * from jsonb_array_elements(fix) loop
      if e->>'kind' = 'head' then
        update vs_version_lines set amount = (e->>'to')::numeric where version_id = newv and head_key = e->>'key';
        ch := ch || jsonb_build_array(jsonb_build_object('label',
          (select head_label from vs_version_lines where version_id = newv and head_key = e->>'key'),
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      else
        perform vs_apply_payroll(p_stmt, newv);
        ch := ch || jsonb_build_array(jsonb_build_object('label','Salary Not Processed From WeVois',
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      end if;
    end loop;
    update vs_payroll set pending_fix = null, pending_fix_why = null, pending_fix_by = null, pending_fix_at = null
     where statement_id = p_stmt;
  end if;

  for pt in select * from vs_points where statement_id = p_stmt and not published
             and status in ('accepted','partial','rejected','carry_forward','disputed_record')
  loop
    if pt.status in ('accepted','partial') then
      if pt.target_kind = 'gross' then
        ch := ch || jsonb_build_array(jsonb_build_object('label','Total Expenses Should Be Paid',
          'from', oldgross, 'to', pt.new_amount, 'why', pt.decision));
        update vs_versions set gross_amount = pt.new_amount where id = newv;
      elsif pt.target_kind = 'head'
         and exists (select 1 from vs_version_lines
                      where version_id = newv and head_key = pt.target_key and src = 'manual') then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_lines where version_id=newv and head_key=pt.target_key),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_lines set amount = pt.new_amount where version_id = newv and head_key = pt.target_key;
      elsif pt.target_kind = 'adjustment' then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_adj where version_id=newv and label=pt.target_label),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_adj set amount = pt.new_amount
         where version_id = newv and label = pt.target_label;
      end if;
    end if;
    update vs_points set published = true, published_in = oldn + 1 where id = pt.id;
  end loop;

  -- anything the CEO or VP approved that has not gone on yet
  ch := ch || vs_apply_approvals(p_stmt, newv, oldn + 1);

  update vs_versions set changes = ch,
    note = n || ' item(s) answered. ' || jsonb_array_length(ch) || ' amount(s) changed.'
   where id = newv;

  select window_days into d from vs_settings where id = 1;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and status in ('open','awaiting_confirm')
     and target_kind <> 'general';
  update vs_statements
     set status = case when opencount > 0 then 'under_query' else 'sent' end,
         due_at = now() + (d + 2) * interval '1 day'
   where id = p_stmt;

  perform vs_log(p_stmt, 'hi', 'Statement v' || (oldn + 1) || ' shared',
    jsonb_array_length(ch) || ' amount change(s) from v' || oldn ||
    '. New final amount ' || vs_version_final(newv) || '.');
  begin
    perform vs_notify_shared(p_stmt, 'revised');
  exception when others then
    perform vs_log(p_stmt, 'warn', 'Notification could not be queued', sqlerrm);
  end;
  return oldn + 1;
end $$;

-- The workbook import carries the site's standing choice too, so re-importing
-- a month lands the same way a fresh month would.
create or replace function vs_import_month(
  p_site    text,
  p_period  date,
  p_gross   numeric,
  p_status  text,            -- 'paid' or anything else for approved-not-paid
  p_heads   jsonb,           -- {"r_m_exp": 12345, ...} keyed on the head key
  p_adj     jsonb,           -- [{"label":"...","effect":"add|deduct|note","amount":n}]
  p_hint    text default null -- 'incoming' picks the vendor who took over mid-month
) returns text
language plpgsql security definer set search_path = public as $$
declare
  sid uuid; cid uuid; stid uuid; vid uuid; per date; mend date;
  k text; n int := 0; miss text := ''; fin numeric; a jsonb; i int := 0;
begin
  perform vs_require('manage_settlements');
  per  := date_trunc('month', p_period)::date;
  mend := (per + interval '1 month - 1 day')::date;

  select id into sid from vs_sites where lower(name) = lower(p_site);
  if sid is null then return 'no such site: ' || p_site; end if;

  if p_hint = 'incoming' then
    select id into cid from vs_contracts
     where site_id = sid and from_date between per and mend
     order by from_date desc limit 1;
  else
    select id into cid from vs_contracts
     where site_id = sid
       and daterange(from_date, coalesce(to_date,'infinity'::date), '[]') && daterange(per, mend, '[]')
     order by from_date limit 1;
  end if;
  if cid is null then return 'no vendor on ' || p_site || ' in ' || vs_period_label(per); end if;

  if exists (select 1 from vs_statements where contract_id = cid and period = per) then
    return 'already there: ' || p_site || ' ' || vs_period_label(per);
  end if;

  insert into vs_statements (contract_id, period, covers_from, covers_to, created_by)
  select cid, per, greatest(c.from_date, per),
         least(coalesce(c.to_date,'infinity'::date), mend), auth.uid()
    from vs_contracts c where c.id = cid
  returning id into stid;

  insert into vs_versions (statement_id, v, gross_amount, gross_note, sent_at)
  values (stid, 1, coalesce(p_gross,0),
          'Imported from Operation Partners Payment Details 9.xlsx', now())
  returning id into vid;

  -- start from that site's own heads, then fill by label
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount, effect)
    select vid, h.id, h.key, h.label, h.grp, 'manual', h.sort, 0, h.effect
      from vs_heads h join vs_contracts c on c.site_id = h.site_id
     where c.id = cid and h.active;

  for k in select jsonb_object_keys(coalesce(p_heads,'{}'::jsonb)) loop
    -- matched on key, not label: several sites carry two rows both called
    -- "ESIC Pf (Employee Part)" (the vendor's own staff and the site staff),
    -- and matching on the label would collapse them into one figure
    update vs_version_lines set amount = (p_heads ->> k)::numeric
     where version_id = vid and head_key = k;
    if found then n := n + 1; else miss := miss || k || '; '; end if;
  end loop;

  for a in select * from jsonb_array_elements(coalesce(p_adj,'[]'::jsonb)) loop
    i := i + 1;
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (vid, a->>'label', coalesce(a->>'effect','deduct'), (a->>'amount')::numeric,
            'Imported from the workbook', i * 10);
  end loop;

  -- historical months did not go through the payroll posting, so mark it done
  -- and leave the figures where the sheet put them
  insert into vs_payroll (statement_id, status, posted_by, posted_at,
                          pf_trrn, esic_challan, not_processed_reason)
  values (stid, 'posted', 'Imported from workbook', now(), 'n/a - imported', 'n/a - imported',
          'Historical month loaded from the spreadsheet.')
  on conflict (statement_id) do nothing;

  fin := vs_version_final(vid);
  update vs_statements
     set status = case when lower(coalesce(p_status,'')) = 'paid' then 'paid' else 'approved' end,
         approved_at = now(), approved_by = 'Imported from workbook',
         approved_version = 1, approved_amount = fin
   where id = stid;

  if lower(coalesce(p_status,'')) = 'paid' and fin > 0 then
    insert into vs_payments (statement_id, amount, paid_on, utr, mode, note, recorded_by)
    values (stid, fin, mend, 'IMPORTED', 'n/a',
            'Marked paid on the spreadsheet. No UTR was recorded there.', 'Imported from workbook');
  end if;

  perform vs_log(stid, 'hi', 'Imported from the workbook',
    'Loaded from Operation Partners Payment Details 9.xlsx for ' || vs_period_label(per) ||
    '. Earned ' || coalesce(p_gross,0) || ', ' || n || ' expense heads, final ' || fin ||
    '. This month was settled on the spreadsheet, not raised through the portal.' ||
    case when miss <> '' then ' Heads not found on this site: ' || miss else '' end);

  return case when miss = '' then 'ok' else 'ok, but unmatched heads: ' || miss end;
end $$;

-- ------------------------------------------- 4. the vendor manager's choice
-- p_effects is {"head_key":"add|deduct|note"}.
drop function if exists vs_save_draft(uuid, numeric, text, jsonb, jsonb);
create or replace function vs_save_draft(p_stmt uuid, p_gross numeric, p_gross_note text,
                                         p_lines jsonb, p_adj jsonb,
                                         p_effects jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare vid uuid; st text; k text; a jsonb; i int := 0; eff text;
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

  -- the same two rules that govern the amounts govern the effect: only a
  -- manual head, only on a draft. A payroll figure belongs to Accounts.
  -- The AMOUNT of a payroll head is Accounts' and cannot be typed here. What
  -- that amount DOES is a different question and it is the vendor manager's:
  -- the employee's own PF and ESIC share, for one, is money already taken from
  -- his men rather than spent by the company, and some months it belongs on the
  -- sheet as a record without being counted again.
  for k in select jsonb_object_keys(coalesce(p_effects,'{}'::jsonb)) loop
    eff := p_effects ->> k;
    if eff not in ('add','deduct','note') then
      raise exception 'A head can only credit him, reduce the payment, or be recorded only. "%" is none of those.', eff
        using errcode='22023';
    end if;
    update vs_version_lines set effect = eff
     where version_id = vid and head_key = k;
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

-- ------------------------------------------- 5. the site's standing choice
drop function if exists vs_add_head(uuid, text, text, text, text, int);
create or replace function vs_add_head(p_site uuid, p_key text, p_label text, p_grp text,
                                       p_src text, p_sort int, p_effect text default 'deduct')
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; eff text;
begin
  perform vs_require('manage_masters');
  eff := coalesce(nullif(p_effect,''), 'deduct');
  if eff not in ('add','deduct','note') then
    raise exception 'A head can only credit him, reduce the payment, or be recorded only.' using errcode='22023';
  end if;
  insert into vs_heads (site_id, key, label, grp, src, sort, effect)
  values (p_site, p_key, p_label, coalesce(nullif(p_grp,''),'run'),
          coalesce(nullif(p_src,''),'manual'), coalesce(p_sort,900), eff)
  returning id into nid;
  perform vs_audit_log('Booking head added',
    p_label || ' at ' || (select name from vs_sites where id = p_site) || ' - ' ||
    case eff when 'add' then 'credits him' when 'note' then 'recorded only'
             else 'reduces payment' end);
  return nid;
end $$;

drop function if exists vs_set_head(uuid, text, int, bool);
create or replace function vs_set_head(p_head uuid, p_label text, p_sort int, p_active bool,
                                       p_effect text default null)
returns void language plpgsql security definer set search_path = public as $$
declare src text; was text;
begin
  perform vs_require('manage_masters');
  select h.src, h.effect into src, was from vs_heads h where h.id = p_head;
  if src is null then raise exception 'No such booking head.' using errcode='02000'; end if;
  if p_effect is not null and p_effect <> '' then
    if p_effect not in ('add','deduct','note') then
      raise exception 'A head can only credit him, reduce the payment, or be recorded only.' using errcode='22023';
    end if;
  end if;
  update vs_heads set label  = coalesce(nullif(p_label,''), label),
                      sort   = coalesce(p_sort, sort),
                      active = coalesce(p_active, active),
                      effect = coalesce(nullif(p_effect,''), effect)
   where id = p_head;
  perform vs_audit_log('Booking head changed', coalesce(p_label,'') ||
    ' at ' || (select st.name from vs_heads h join vs_sites st on st.id = h.site_id where h.id = p_head) ||
    case when p_effect is not null and p_effect <> '' and p_effect is distinct from was
         then ' - now ' || case p_effect when 'add' then 'credits him'
                                         when 'note' then 'recorded only'
                                         else 'reduces payment' end
         else '' end);
end $$;

-- --------------------------------------------------------------- 6. the payload
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
    'adj_types', (select coalesce(jsonb_agg(to_jsonb(t) order by t.sort),'[]'::jsonb)
                    from vs_adj_types t where t.active),
    'payroll', to_jsonb(pr),
    'payroll_batches', (select coalesce(jsonb_agg(to_jsonb(b) order by b.seq),'[]'::jsonb)
                    from vs_payroll_batches b where b.statement_id = s.id),
    'paid_total', vs_paid_total(s.id),
    'documents', (select coalesce(jsonb_agg(to_jsonb(dc) order by dc.uploaded_at),'[]'::jsonb)
                    from vs_documents dc where dc.statement_id = s.id),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', ve.id, 'v', ve.v, 'sent_at', ve.sent_at, 'viewed_at', ve.viewed_at,
        'note', ve.note, 'changes', ve.changes,
        'gross', ve.gross_amount, 'gross_note', ve.gross_note,
        'heads_total', vs_version_heads(ve.id),
        'spend_total', vs_version_spend(ve.id),
        'total', vs_version_total(ve.id), 'adj_total', vs_version_adj_total(ve.id),
        'final', vs_version_final(ve.id),
        'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.sort),'[]'::jsonb)
                    from vs_version_lines l where l.version_id = ve.id),
        'adjustments', (select coalesce(jsonb_agg(to_jsonb(a) order by a.sort),'[]'::jsonb)
                    from vs_version_adj a where a.version_id = ve.id)
      ) order by ve.v), '[]'::jsonb) from vs_versions ve where ve.statement_id = s.id),
    'points',   (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'target_kind', p.target_kind, 'target_key', p.target_key,
        'target_label', p.target_label, 'source', p.source, 'raised_by', p.raised_by,
        'raised_at', p.raised_at, 'version_no', p.version_no, 'claimed', p.claimed,
        'note', p.note, 'attachment', p.attachment, 'status', p.status,
        'confirmed_at', p.confirmed_at, 'decision', p.decision, 'decided_by', p.decided_by,
        'decided_at', p.decided_at, 'new_amount', p.new_amount, 'published', p.published,
        'published_in', p.published_in,
        'remarks', (select coalesce(jsonb_agg(to_jsonb(rm) order by rm.at),'[]'::jsonb)
                      from vs_point_remarks rm where rm.point_id = p.id)
      ) order by p.raised_at), '[]'::jsonb)
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

-- ---------------------------------------------------------------- 7. permission
grant execute on function
  vs_version_spend(uuid),
  vs_version_heads(uuid),
  vs_save_draft(uuid,numeric,text,jsonb,jsonb,jsonb),
  vs_add_head(uuid,text,text,text,text,int,text),
  vs_set_head(uuid,text,int,bool,text),
  vs_add_statement(uuid,date),
  vs_issue_revision(uuid),
  vs_import_month(text,date,numeric,text,jsonb,jsonb,text),
  vs_statement_json(uuid)
to authenticated;

-- ------------------------------------------------------------------ 8. proof
select 'every line that already exists reads as reduces-payment' as check,
       count(*) filter (where effect = 'deduct') as deduct,
       count(*) filter (where effect <> 'deduct') as other
  from vs_version_lines;


-- ############################################################################
-- ##  PART 9 of 10 - VS-PATCH-8.sql
-- ##  security: only a signed-in person can reach anything
-- ############################################################################

-- VS-PATCH-8.sql
-- ============================================================================
-- SECURITY. Run this one.
--
-- What was wrong
-- --------------
-- PostgreSQL grants EXECUTE on a new function to PUBLIC automatically. Every
-- "grant execute on function ... to authenticated" in the earlier files was
-- therefore decorative: anon already had it, because PUBLIC includes anon.
--
-- Most functions did not care - they start with vs_require(...), and an
-- anonymous caller has no profile, so vs_role() is null and they refuse. The
-- security model held everywhere it was actually written down.
--
-- vs_queue_mail had no such line. It is an internal helper, called by
-- vs_share, vs_notify_shared, vs_request_approval and vs_decide_approval, and
-- nobody expected it to be reachable from outside. It was. Anybody holding the
-- anon key - which is public by design and sits in supabase-config.js in every
-- browser that opens the portal - could call
--
--   POST /rest/v1/rpc/vs_queue_mail
--   {"p_email":"anyone@anywhere.com","p_subject":"...","p_html":"..."}
--
-- and put a row in the outbox. The send-mail function would then deliver it
-- over SMTP FROM YOUR OFFICE GMAIL, with their address, their subject and
-- their HTML. That is an open relay attached to your own mail account: spam or
-- phishing sent as WeVois, and a good chance of the account being suspended.
-- This was proved by doing it, not by reading the code - the row landed.
--
-- Three more internal helpers - vs_apply_payroll, vs_apply_approvals and
-- vs_sync_first_batch - were reachable the same way. They wrote nothing in the
-- test, but vs_apply_payroll can rewrite the six payroll heads on a version
-- that has already been shared and frozen, which is exactly the kind of silent
-- change this whole portal exists to prevent.
--
-- What this does
-- --------------
--   1. Takes EXECUTE away from PUBLIC on every vs_ function, so the grants
--      that follow are the only ones there are, and the ones already written
--      in the earlier files start meaning what they say.
--   2. Gives anon back the one function it must have: vs_needs_setup, which
--      answers "has an administrator been created yet" and nothing else.
--   3. Leaves the internal helpers granted to nobody. A SECURITY DEFINER
--      function runs as its owner, so vs_share can still call vs_queue_mail;
--      the difference is that a browser cannot.
--   4. Puts a real guard inside each of them anyway, so a future grant made by
--      mistake cannot open the same door twice.
--
-- Run AFTER VS-PATCH-7.sql. Safe to re-run. It changes no data at all - it
-- ends by printing who can execute what, so you can see it for yourself.
-- Pure ASCII.
-- ============================================================================

-- ------------------------------------- 1. guards inside the internal helpers
-- Written first, so that even between the two halves of this file there is no
-- moment when the door is open.

-- Every one of these is called from inside another vs_ function that has
-- already checked the caller. The guard here is the floor, not the ceiling:
-- the caller must be a real signed-in person of this portal.
create or replace function vs_queue_mail(p_stmt uuid, p_kind text, p_email text, p_name text,
                                         p_role text, p_subject text, p_text text, p_html text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; on_ bool;
begin
  -- an anonymous caller has no profile, so this is null and nothing is queued.
  -- Without it, anybody with the public anon key could send mail from the
  -- company's own address.
  if vs_role() is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  if p_stmt is not null and not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode = '42501';
  end if;
  select mail_on into on_ from vs_settings where id = 1;
  if coalesce(trim(p_email),'') = '' then return null; end if;
  insert into vs_mail (statement_id, kind, to_email, to_name, to_role, subject, body_text, body_html, status)
  values (p_stmt, p_kind, lower(trim(p_email)), coalesce(p_name,''), coalesce(p_role,''),
          p_subject, p_text, coalesce(p_html,''),
          case when coalesce(on_,true) then 'queued' else 'skipped' end)
  returning id into nid;
  return nid;
end $$;

create or replace function vs_log(p_stmt uuid, p_kind text, p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if vs_role() is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  insert into vs_events (statement_id, kind, title, body, actor_name, actor_role)
  values (p_stmt, coalesce(p_kind,''), p_title, coalesce(p_body,''), vs_actor(), vs_role());
end $$;

create or replace function vs_audit_log(p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if vs_role() is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  insert into vs_audit (title, body, actor_name, actor_role)
  values (p_title, coalesce(p_body,''), vs_actor(), vs_role());
end $$;

-- vs_apply_payroll can move six head amounts on a version. Everything that
-- calls it has already checked post_payroll or revise; this refuses anybody
-- who is not entitled to see the month at all.
do $do$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'vs_apply_payroll';
  if src is null then raise exception 'vs_apply_payroll is missing - run the earlier patches first'; end if;
  if position('vs_sees(p_stmt)' in src) = 0 then
    src := replace(src,
      'begin' || chr(10),
      'begin' || chr(10) ||
      '  if vs_role() is null or not vs_sees(p_stmt) then' || chr(10) ||
      '    raise exception ''Not visible to you.'' using errcode=''42501''; end if;' || chr(10));
    execute src;
  end if;
end $do$;

do $do$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'vs_sync_first_batch';
  if src is not null and position('vs_sees(p_stmt)' in src) = 0 then
    src := replace(src,
      'begin' || chr(10),
      'begin' || chr(10) ||
      '  if vs_role() is null or not vs_sees(p_stmt) then' || chr(10) ||
      '    raise exception ''Not visible to you.'' using errcode=''42501''; end if;' || chr(10));
    execute src;
  end if;
end $do$;

do $do$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'vs_apply_approvals';
  if src is not null and position('vs_sees(p_stmt)' in src) = 0 then
    src := replace(src,
      'begin' || chr(10),
      'begin' || chr(10) ||
      '  if vs_role() is null or not vs_sees(p_stmt) then' || chr(10) ||
      '    raise exception ''Not visible to you.'' using errcode=''42501''; end if;' || chr(10));
    execute src;
  end if;
end $do$;

do $do$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'vs_notify_shared';
  if src is not null and position('vs_role() is null' in src) = 0 then
    src := replace(src,
      'begin' || chr(10),
      'begin' || chr(10) ||
      '  if vs_role() is null or not vs_sees(p_stmt) then' || chr(10) ||
      '    raise exception ''Not visible to you.'' using errcode=''42501''; end if;' || chr(10));
    execute src;
  end if;
end $do$;

-- --------------------------------------------- 2. take back the free EXECUTE
do $do$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'vs\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $do$;

-- ------------------------------------------------- 3. give back exactly what
-- anon: one function, and it answers one question.
grant execute on function vs_needs_setup() to anon, authenticated;

-- authenticated: what the app calls, what the row policies call, and the
-- read-only money helpers the payload is built from.
do $do$
declare f record;
  keep text[] := array[
    -- called by the app
    'vs_add_adj_type','vs_add_contract','vs_add_document','vs_add_head','vs_add_payroll_batch',
    'vs_add_remark','vs_add_site','vs_add_statement','vs_add_vendor','vs_answer_query','vs_approve',
    'vs_change_vendor','vs_confirm_call_point','vs_decide_approval','vs_delete_statement','vs_invite',
    'vs_issue_revision','vs_list_statements','vs_log_call_point','vs_mark_viewed','vs_open_month',
    'vs_post_payroll','vs_raise_point','vs_raise_query','vs_record_payment','vs_remind',
    'vs_remove_document','vs_reopen_contract','vs_request_approval','vs_resolve_point','vs_save_draft',
    'vs_save_mail_settings','vs_save_settings','vs_set_active','vs_set_contract','vs_set_head',
    'vs_set_role','vs_set_site','vs_share','vs_statement_extra','vs_statement_json',
    -- named inside the row-level policies, so the caller must be able to run them
    'vs_can','vs_my_vendor','vs_role','vs_sees','vs_sees_site','vs_sees_version','vs_require',
    -- read-only, every one of them gated by vs_sees; the app reads them and the
    -- build-drift check asks the catalogue whether they exist
    'vs_actor','vs_contract_at','vs_current_version','vs_paid_total','vs_payroll_diff',
    'vs_period_label','vs_site_history','vs_site_open_in','vs_site_status',
    'vs_version_adj_total','vs_version_final','vs_version_heads','vs_version_spend','vs_version_total',
    -- administrator tools, each already behind vs_require
    'vs_end_contract','vs_remove_contract','vs_set_contract_vehicles','vs_import_month'
  ];
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any(keep)
  loop
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $do$;

-- Everything not in that list stays granted to nobody: vs_queue_mail,
-- vs_notify_shared, vs_log, vs_audit_log, vs_apply_payroll, vs_apply_approvals,
-- vs_sync_first_batch, vs_post_payroll_base, vs_handle_new_user. They are
-- called from inside other vs_ functions, which run as their owner, so they
-- keep working. A browser cannot reach them at all.

-- ----------------------------------------------------------------- 4. proof
select 'nobody' as who,
       string_agg(p.proname, ', ' order by p.proname) as functions
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname like 'vs\_%'
   and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
   and not has_function_privilege('anon', p.oid, 'EXECUTE')
union all
select 'anon',
       string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname like 'vs\_%'
   and has_function_privilege('anon', p.oid, 'EXECUTE');

select count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')) as signed_in_can_run,
       count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE'))          as anonymous_can_run,
       count(*)                                                                          as functions_in_total
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname like 'vs\_%';


-- ############################################################################
-- ##  PART 10 of 10 - site sheets
-- ##  each site's operating sheet, mirrored, with a query on any row or column
-- ############################################################################

-- ============================================================================
-- The daily working sheet each site already keeps in Google Sheets - the duty
-- log, the day counts, every penalty with its proof, and the month totals - is
-- where the settlement figure actually comes from. Until now the vendor was
-- shown the answer and not the working, so "why is my penalty 95,600" was a
-- phone call.
--
-- This mirrors those tabs into the portal, site by site, and lets the vendor
-- put a question on ANY ROW or ANY COLUMN of them. The vendor manager answers
-- in writing and the thread closes, exactly like the queries already on a
-- statement.
--
-- Three things this deliberately does:
--
--   A ROW IS NEVER DELETED. A sync that no longer finds a row marks it gone
--     instead of removing it, because a question may be hanging off it and the
--     vendor is entitled to see what he was looking at when he asked.
--   ROWS ARE MATCHED ON THEIR OWN KEY, not their position. The sheet is sorted
--     and re-sorted all day; a question asked on 1-Jun penalty 300 must still
--     be on that penalty tomorrow, not on whatever slid into row 14.
--   THE SHEET IS READ ONLY. Nothing here writes back to Google. The portal is
--     the record of the conversation, the sheet stays the operating tool.
-- ============================================================================

-- ------------------------------------------------------------------ 1. tables
create table if not exists vs_sheets (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references vs_sites(id) on delete cascade,
  title       text not null default '',
  url         text not null default '',
  active      bool not null default true,
  last_sync_at timestamptz,
  last_sync_by text not null default '',
  unique (site_id)
);

-- tab_key is a fixed vocabulary so the app knows how to read each one; the
-- COLUMNS are not fixed, they come from the sheet, because Vidisha and Bundi
-- do not keep identical sheets and pretending they do would lose figures.
create table if not exists vs_sheet_tabs (
  id        uuid primary key default gen_random_uuid(),
  sheet_id  uuid not null references vs_sheets(id) on delete cascade,
  tab_key   text not null check (tab_key in ('monthly','penalty','counts','duty')),
  label     text not null default '',
  sort      int  not null default 0,
  cols      jsonb not null default '[]'::jsonb,   -- [{key,label,kind}]
  synced_at timestamptz,
  unique (sheet_id, tab_key)
);

create table if not exists vs_sheet_rows (
  id        uuid primary key default gen_random_uuid(),
  tab_id    uuid not null references vs_sheet_tabs(id) on delete cascade,
  -- which file this row came from. Kuchaman and Bundi each keep two payment
  -- sheets, and most sites keep their penalties in a file of their own, so a
  -- sync must only ever speak for the file it is running inside. Without this
  -- the second file's sync would mark the first file's rows as gone.
  source    text not null default '',
  row_key   text not null,
  period    date,          -- the month this row belongs to
  on_date   date,          -- the row's own date, where it has one
  sort      int  not null default 0,
  data      jsonb not null default '{}'::jsonb,
  gone      bool not null default false,
  gone_at   timestamptz,
  first_seen timestamptz not null default now(),
  changed_at timestamptz not null default now(),
  unique (tab_id, source, row_key)
);
create index if not exists vs_sheet_rows_idx on vs_sheet_rows (tab_id, period, sort);

-- A question on a row, or on a whole column. Same words as the queries on a
-- statement: it opens, somebody answers it in writing, and it closes.
create table if not exists vs_sheet_points (
  id           uuid primary key default gen_random_uuid(),
  tab_id       uuid not null references vs_sheet_tabs(id) on delete cascade,
  row_id       uuid references vs_sheet_rows(id) on delete cascade,  -- null = the whole column
  col_key      text not null default '',                             -- '' = the whole row
  target_label text not null,
  period       date,
  raised_by    text not null,
  raised_uid   uuid,
  raised_at    timestamptz not null default now(),
  note         text not null,
  claimed      numeric(14,2),
  status       text not null default 'open' check (status in ('open','answered')),
  answer       text,
  answered_by  text,
  answered_at  timestamptz
);
create index if not exists vs_sheet_points_idx on vs_sheet_points (tab_id, status, raised_at);

create table if not exists vs_sheet_remarks (
  id       uuid primary key default gen_random_uuid(),
  point_id uuid not null references vs_sheet_points(id) on delete cascade,
  body     text not null,
  by_name  text not null,
  by_role  text not null,
  at       timestamptz not null default now()
);
create index if not exists vs_sheet_remarks_idx on vs_sheet_remarks (point_id, at);

-- ------------------------------------------------------------ 2. who may read
-- Reads by policy, writes only through the functions below - the same rule as
-- everything else here. A vendor sees a site's sheet only while he holds that
-- site, which vs_sees_site already decides.
do $do$
declare t text;
begin
  foreach t in array array['vs_sheets','vs_sheet_tabs','vs_sheet_rows','vs_sheet_points','vs_sheet_remarks']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on table %I from anon, authenticated', t);
    execute format('grant select on table %I to authenticated', t);
  end loop;
end $do$;

drop policy if exists p_sheets_r on vs_sheets;
create policy p_sheets_r on vs_sheets for select to authenticated
  using (vs_sees_site(site_id));

drop policy if exists p_sheet_tabs_r on vs_sheet_tabs;
create policy p_sheet_tabs_r on vs_sheet_tabs for select to authenticated
  using (exists (select 1 from vs_sheets s where s.id = sheet_id and vs_sees_site(s.site_id)));

drop policy if exists p_sheet_rows_r on vs_sheet_rows;
create policy p_sheet_rows_r on vs_sheet_rows for select to authenticated
  using (exists (select 1 from vs_sheet_tabs t join vs_sheets s on s.id = t.sheet_id
                  where t.id = tab_id and vs_sees_site(s.site_id)));

drop policy if exists p_sheet_points_r on vs_sheet_points;
create policy p_sheet_points_r on vs_sheet_points for select to authenticated
  using (exists (select 1 from vs_sheet_tabs t join vs_sheets s on s.id = t.sheet_id
                  where t.id = tab_id and vs_sees_site(s.site_id)));

drop policy if exists p_sheet_remarks_r on vs_sheet_remarks;
create policy p_sheet_remarks_r on vs_sheet_remarks for select to authenticated
  using (exists (select 1 from vs_sheet_points p
                   join vs_sheet_tabs t on t.id = p.tab_id
                   join vs_sheets s on s.id = t.sheet_id
                  where p.id = point_id and vs_sees_site(s.site_id)));

-- ------------------------------------------------------- 3. connecting a sheet
insert into vs_caps (role, cap) values ('admin','sync_sheets'), ('manager','sync_sheets')
on conflict do nothing;

create or replace function vs_set_sheet(p_site uuid, p_title text, p_url text, p_active bool default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; sn text;
begin
  perform vs_require('sync_sheets');
  select name into sn from vs_sites where id = p_site;
  if sn is null then raise exception 'No such site.' using errcode='02000'; end if;
  insert into vs_sheets (site_id, title, url, active)
  values (p_site, coalesce(trim(p_title),''), coalesce(trim(p_url),''), coalesce(p_active,true))
  on conflict (site_id) do update set
    title = coalesce(nullif(trim(excluded.title),''), vs_sheets.title),
    url   = coalesce(nullif(trim(excluded.url),''),   vs_sheets.url),
    active = excluded.active
  returning id into nid;
  perform vs_audit_log('Site sheet connected', sn || ' - ' || coalesce(nullif(trim(p_title),''),'(untitled)'));
  return nid;
end $$;

-- ---------------------------------------------------------------- 4. the sync
-- p_cols  [{"key":"amount","label":"Penalty Amount","kind":"money"}, ...]
-- p_rows  [{"key":"2026-06-01|300|D2D App off|Ward 4", "period":"2026-06-01",
--           "on_date":"2026-06-01", "sort":12, "data":{...}}, ...]
--
-- The key is the caller's job and it must be stable: it is what keeps a
-- vendor's question attached to the right row when the sheet is re-sorted.
create or replace function vs_import_sheet(p_site uuid, p_tab text, p_label text,
                                           p_cols jsonb, p_rows jsonb,
                                           p_source text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare shid uuid; tid uuid; r jsonb; seen text[] := '{}';
        n_new int := 0; n_upd int := 0; n_gone int := 0; sn text; k text;
        src text := coalesce(trim(p_source),'');
begin
  perform vs_require('sync_sheets');
  if p_tab not in ('monthly','penalty','counts','duty') then
    raise exception 'Unknown tab "%". The portal mirrors monthly, penalty, counts and duty.', p_tab
      using errcode='22023';
  end if;
  select name into sn from vs_sites where id = p_site;
  if sn is null then raise exception 'No such site.' using errcode='02000'; end if;

  select id into shid from vs_sheets where site_id = p_site;
  if shid is null then
    insert into vs_sheets (site_id) values (p_site) returning id into shid;
  end if;

  insert into vs_sheet_tabs (sheet_id, tab_key, label, cols, sort, synced_at)
  values (shid, p_tab, coalesce(nullif(trim(p_label),''), initcap(p_tab)), coalesce(p_cols,'[]'::jsonb),
          case p_tab when 'monthly' then 10 when 'penalty' then 20 when 'counts' then 30 else 40 end, now())
  on conflict (sheet_id, tab_key) do update set
    label = excluded.label, cols = excluded.cols, synced_at = now()
  returning id into tid;

  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    k := r->>'key';
    if coalesce(trim(k),'') = '' then
      raise exception 'Every row needs a key. Without one a question cannot stay attached to it.'
        using errcode='22023';
    end if;
    seen := seen || k;
    insert into vs_sheet_rows (tab_id, source, row_key, period, on_date, sort, data, gone, gone_at)
    values (tid, src, k, nullif(r->>'period','')::date, nullif(r->>'on_date','')::date,
            coalesce((r->>'sort')::int, 0), coalesce(r->'data','{}'::jsonb), false, null)
    on conflict (tab_id, source, row_key) do update set
      period = excluded.period, on_date = excluded.on_date, sort = excluded.sort,
      gone = false, gone_at = null,
      changed_at = case when vs_sheet_rows.data is distinct from excluded.data
                        then now() else vs_sheet_rows.changed_at end,
      data = excluded.data;
    if found then n_upd := n_upd + 1; end if;
  end loop;
  n_new := (select count(*) from vs_sheet_rows where tab_id = tid and first_seen > now() - interval '1 minute');

  -- a row that has left the sheet is marked, never removed: a question may be
  -- hanging off it, and the vendor is entitled to see what he was looking at
  update vs_sheet_rows set gone = true, gone_at = now()
   where tab_id = tid and source = src and not gone and not (row_key = any(seen));
  get diagnostics n_gone = row_count;

  update vs_sheets set last_sync_at = now(), last_sync_by = vs_actor() where id = shid;

  perform vs_audit_log('Site sheet synced',
    sn || ' - ' || p_tab || case when src <> '' then ' (' || src || ')' else '' end || ': ' ||
    jsonb_array_length(coalesce(p_rows,'[]'::jsonb)) ||
    ' row(s) in the sheet' || case when n_gone > 0 then ', ' || n_gone || ' no longer there' else '' end);

  return jsonb_build_object('tab_id', tid, 'rows', jsonb_array_length(coalesce(p_rows,'[]'::jsonb)),
                            'gone', n_gone);
end $$;

-- ------------------------------------------------------------- 5. reading it
create or replace function vs_site_sheet(p_site uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  if not vs_sees_site(p_site) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'sheet', to_jsonb(s),
    'tabs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'tab_key', t.tab_key, 'label', t.label, 'cols', t.cols,
        'synced_at', t.synced_at,
        'rows_live', (select count(*) from vs_sheet_rows r where r.tab_id = t.id and not r.gone),
        'open_points', (select count(*) from vs_sheet_points p where p.tab_id = t.id and p.status = 'open'),
        'periods', (select coalesce(jsonb_agg(distinct to_char(r.period,'YYYY-MM')),'[]'::jsonb)
                      from vs_sheet_rows r where r.tab_id = t.id and r.period is not null)
      ) order by t.sort), '[]'::jsonb) from vs_sheet_tabs t where t.sheet_id = s.id)
  ) into out
  from vs_sheets s where s.site_id = p_site;
  return coalesce(out, jsonb_build_object('sheet', null, 'tabs', '[]'::jsonb));
end $$;

-- One tab, one month. p_period null means every month the tab holds.
create or replace function vs_sheet_page(p_tab uuid, p_period date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb; ok bool;
begin
  select vs_sees_site(s.site_id) into ok
    from vs_sheet_tabs t join vs_sheets s on s.id = t.sheet_id where t.id = p_tab;
  if not coalesce(ok,false) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'tab', jsonb_build_object('id', t.id, 'tab_key', t.tab_key, 'label', t.label,
                              'cols', t.cols, 'synced_at', t.synced_at),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', r.id, 'row_key', r.row_key, 'source', r.source,
        'period', r.period, 'on_date', r.on_date,
        'sort', r.sort, 'data', r.data, 'gone', r.gone, 'gone_at', r.gone_at
      ) order by r.sort, r.on_date, r.row_key), '[]'::jsonb)
      from vs_sheet_rows r where r.tab_id = t.id
        and (p_period is null or r.period = date_trunc('month', p_period)::date)),
    'points', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'row_id', p.row_id, 'col_key', p.col_key, 'target_label', p.target_label,
        'period', p.period, 'raised_by', p.raised_by, 'raised_at', p.raised_at,
        'note', p.note, 'claimed', p.claimed, 'status', p.status,
        'answer', p.answer, 'answered_by', p.answered_by, 'answered_at', p.answered_at,
        'remarks', (select coalesce(jsonb_agg(to_jsonb(rm) order by rm.at),'[]'::jsonb)
                      from vs_sheet_remarks rm where rm.point_id = p.id)
      ) order by p.raised_at), '[]'::jsonb)
      from vs_sheet_points p where p.tab_id = t.id
        and (p_period is null or p.period is null or p.period = date_trunc('month', p_period)::date))
  ) into out
  from vs_sheet_tabs t where t.id = p_tab;
  return out;
end $$;

-- --------------------------------------------------- 6. a question, and its answer
-- p_row null asks about a whole column; p_col '' asks about a whole row.
create or replace function vs_raise_sheet_point(p_tab uuid, p_row uuid, p_col text,
                                                p_note text, p_claimed numeric default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; ok bool; lbl text; per date; cols jsonb; cl text;
begin
  perform vs_require('raise');
  select vs_sees_site(s.site_id), t.cols into ok, cols
    from vs_sheet_tabs t join vs_sheets s on s.id = t.sheet_id where t.id = p_tab;
  if not coalesce(ok,false) then
    raise exception 'That is not your site.' using errcode='42501';
  end if;
  if coalesce(trim(p_note),'') = '' then
    raise exception 'Write the question down. That text is the record.' using errcode='22023';
  end if;
  if p_row is not null and not exists (select 1 from vs_sheet_rows where id = p_row and tab_id = p_tab) then
    raise exception 'That row is not on this tab.' using errcode='22023';
  end if;

  select coalesce(c->>'label', p_col) into cl
    from jsonb_array_elements(coalesce(cols,'[]'::jsonb)) c where c->>'key' = nullif(p_col,'');

  if p_row is not null then
    select r.period into per from vs_sheet_rows r where r.id = p_row;
    lbl := coalesce(
      (select to_char(r.on_date,'DD Mon YYYY') from vs_sheet_rows r where r.id = p_row),
      (select r.row_key from vs_sheet_rows r where r.id = p_row))
      || case when nullif(p_col,'') is not null then ' - ' || coalesce(cl, p_col) else '' end;
  else
    if nullif(p_col,'') is null then
      raise exception 'Say which row or which column the question is about.' using errcode='22023';
    end if;
    lbl := 'Whole column - ' || coalesce(cl, p_col);
  end if;

  insert into vs_sheet_points (tab_id, row_id, col_key, target_label, period,
                               raised_by, raised_uid, note, claimed)
  values (p_tab, p_row, coalesce(p_col,''), lbl, per, vs_actor(), auth.uid(), trim(p_note), p_claimed)
  returning id into nid;
  return nid;
end $$;

create or replace function vs_answer_sheet_point(p_point uuid, p_reply text)
returns void language plpgsql security definer set search_path = public as $$
declare ok bool;
begin
  perform vs_require('resolve');
  select vs_sees_site(s.site_id) into ok
    from vs_sheet_points p join vs_sheet_tabs t on t.id = p.tab_id
    join vs_sheets s on s.id = t.sheet_id where p.id = p_point;
  if ok is null then raise exception 'No such question.' using errcode='02000'; end if;
  if not ok then raise exception 'Not visible to you.' using errcode='42501'; end if;
  if coalesce(trim(p_reply),'') = '' then
    raise exception 'An answer is required. It is what the vendor sees.' using errcode='22023';
  end if;
  update vs_sheet_points
     set status = 'answered', answer = trim(p_reply),
         answered_by = vs_actor(), answered_at = now()
   where id = p_point;
end $$;

create or replace function vs_add_sheet_remark(p_point uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; ok bool; r text;
begin
  r := vs_role();
  if r is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  if r in ('ceo','vp') then
    raise exception 'Observer accounts cannot write on a settlement.' using errcode='42501';
  end if;
  select vs_sees_site(s.site_id) into ok
    from vs_sheet_points p join vs_sheet_tabs t on t.id = p.tab_id
    join vs_sheets s on s.id = t.sheet_id where p.id = p_point;
  if ok is null then raise exception 'No such question.' using errcode='02000'; end if;
  if not ok then raise exception 'Not visible to you.' using errcode='42501'; end if;
  if coalesce(trim(p_body),'') = '' then
    raise exception 'A remark cannot be blank.' using errcode='22023';
  end if;
  insert into vs_sheet_remarks (point_id, body, by_name, by_role)
  values (p_point, trim(p_body), vs_actor(), r)
  returning id into nid;
  return nid;
end $$;

-- --------------------------------------------------------------- 7. permission
revoke all on function
  vs_set_sheet(uuid,text,text,bool), vs_import_sheet(uuid,text,text,jsonb,jsonb,text),
  vs_site_sheet(uuid), vs_sheet_page(uuid,date),
  vs_raise_sheet_point(uuid,uuid,text,text,numeric),
  vs_answer_sheet_point(uuid,text), vs_add_sheet_remark(uuid,text)
from public, anon, authenticated;

grant execute on function
  vs_set_sheet(uuid,text,text,bool), vs_import_sheet(uuid,text,text,jsonb,jsonb,text),
  vs_site_sheet(uuid), vs_sheet_page(uuid,date),
  vs_raise_sheet_point(uuid,uuid,text,text,numeric),
  vs_answer_sheet_point(uuid,text), vs_add_sheet_remark(uuid,text)
to authenticated;

-- ============================================================================
-- HEALTH CHECK - read-only. Every line should say OK.
-- ============================================================================
select item, state, detail from (
  select 1 as ord, 'schema' as item,
    case when to_regclass('public.vs_statements') is not null then 'OK' else 'MISSING' end as state,
    'the tables are in place' as detail
  union all select 2, 'vendor isolation',
    case when exists (select 1 from pg_proc where proname='vs_sees_site') then 'OK' else 'MISSING' end,
    'a vendor can only see his own sites'
  union all select 3, 'vendor uploads',
    case when exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
           and policyname='p_vsdocs_write'
           and coalesce(qual,'') || coalesce(with_check,'') like '%vendor%')
         then 'OK' else 'MISSING' end,
    'a vendor may attach a bill to his statement'
  union all select 4, 'payroll top-ups',
    case when to_regclass('public.vs_payroll_batches') is not null then 'OK' else 'MISSING' end,
    'salary processed late goes on as its own entry'
  union all select 5, 'email and CEO/VP confirmation',
    case when exists (select 1 from pg_proc where proname='vs_statement_extra') then 'OK' else 'MISSING' end,
    'sharing a month notifies people; the CEO and VP can confirm a figure'
  union all select 6, 'head effect',
    case when exists (select 1 from pg_proc where proname='vs_version_spend') then 'OK' else 'MISSING' end,
    'a head can reduce the payment, credit him, or be recorded only'
  union all select 7, 'manager posts payroll',
    case when exists (select 1 from vs_caps where role='manager' and cap='post_payroll') then 'OK' else 'MISSING' end,
    'the vendor manager does not have to wait for Accounts'
  union all select 8, 'SECURITY - who can reach the database',
    case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname='public' and p.proname like 'vs\_%'
                  and has_function_privilege('anon', p.oid, 'EXECUTE')) = 1
         then 'OK' else 'OPEN' end,
    'exactly one function may be called without signing in'
  union all select 9, 'SECURITY - the mail helper',
    case when not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname='public' and p.proname='vs_queue_mail'
                             and has_function_privilege('anon', p.oid, 'EXECUTE'))
         then 'OK' else 'OPEN - a stranger could send mail from your address' end,
    'nobody outside can queue mail from your address'
  union all select 10, 'SECURITY - row-level security',
    case when not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                           where n.nspname='public' and c.relkind='r' and c.relname like 'vs\_%'
                             and not c.relrowsecurity)
         then 'OK' else 'OFF ON SOME TABLES' end,
    'every table is behind row-level security'
  union all select 11, 'SECURITY - direct writes',
    case when not exists (select 1 from information_schema.role_table_grants
                           where grantee in ('authenticated','anon') and table_schema='public'
                             and table_name like 'vs\_%'
                             and privilege_type in ('INSERT','UPDATE','DELETE'))
         then 'OK' else 'A TABLE IS DIRECTLY WRITABLE' end,
    'no table can be written except through a vs_ function'
  union all select 12, 'site sheets',
    case when to_regclass('public.vs_sheet_rows') is not null then 'OK' else 'MISSING' end,
    'each site''s working sheet, with a query on any row or column'
  union all select 20, 'your data - sites',       (select count(*)::text from vs_sites),       'untouched by this file'
  union all select 21, 'your data - vendors',     (select count(*)::text from vs_vendors),     'untouched by this file'
  union all select 22, 'your data - tenures',     (select count(*)::text from vs_contracts),   'untouched by this file'
  union all select 23, 'your data - settlements', (select count(*)::text from vs_statements),  'untouched by this file'
  union all select 24, 'your data - shared with a vendor',
    (select count(*)::text from vs_statements where status <> 'draft'), 'untouched by this file'
  union all select 25, 'your data - vendor points and replies',
    (select count(*)::text from vs_points), 'untouched by this file'
  union all select 26, 'your data - payments',    (select count(*)::text from vs_payments),    'untouched by this file'
  union all select 27, 'your data - people with a login', (select count(*)::text from vs_profiles), 'untouched by this file'
  union all select 28, 'your data - sheet rows mirrored',
    (select count(*)::text from vs_sheet_rows), 'untouched by this file'
) h order by ord;
