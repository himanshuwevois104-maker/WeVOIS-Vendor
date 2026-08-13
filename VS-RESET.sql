-- VS-RESET.sql
-- ============================================================================
-- Empties the portal completely and leaves it exactly as it is the moment
-- after VS-SETUP.sql has run: no data, no people, no history, waiting at the
-- "Create the first administrator" screen.
--
-- THIS CANNOT BE UNDONE. It deletes every settlement, every version, every
-- point, every payment, every attached file, every vendor, every site, every
-- login and the whole audit trail. There is no soft delete and no tombstone -
-- you asked for a clean sheet, so nothing is kept back.
--
-- If you only meant to clear the months and keep your sites and vendors, STOP
-- and say so; that is a different and much smaller file.
--
-- Run in the Supabase SQL editor, selecting the whole file. It needs no
-- signed-in user - it deletes rows directly rather than going through the
-- portal's own functions, which is why it works from the editor where the
-- import file needed to borrow your administrator's identity.
--
-- Pure ASCII. Safe to run twice; the second time it deletes nothing.
-- ============================================================================

-- ---------------------------------------------------------------- before
select 'BEFORE' as when_,
  (select count(*) from vs_statements) as statements,
  (select count(*) from vs_versions)   as versions,
  (select count(*) from vs_payments)   as payments,
  (select count(*) from vs_contracts)  as tenures,
  (select count(*) from vs_sites)      as sites,
  (select count(*) from vs_vendors)    as vendors,
  (select count(*) from vs_profiles)   as logins,
  (select count(*) from vs_audit)      as audit_rows;

-- ---------------------------------------------------------------------------
-- 1. The settlements and everything hanging off them
-- ---------------------------------------------------------------------------
-- vs_versions, vs_version_lines, vs_version_adj, vs_payroll, vs_points,
-- vs_payments, vs_events and vs_documents all cascade from vs_statements, but
-- they are named explicitly so the count at the end is honest rather than
-- inferred.
delete from vs_version_adj;
delete from vs_version_lines;
delete from vs_versions;
delete from vs_documents;
delete from vs_payments;
delete from vs_points;
delete from vs_payroll;
delete from vs_events;
delete from vs_statements;

-- ---------------------------------------------------------------------------
-- 2. The org
-- ---------------------------------------------------------------------------
-- Tenures are RESTRICT against sites and vendors, so they go first. Booking
-- heads cascade from their site.
delete from vs_contracts;
delete from vs_heads;
delete from vs_sites;

-- a profile points at a vendor with ON DELETE SET NULL, so vendor logins would
-- survive as orphans pointing at nothing. They are going anyway in step 4.
delete from vs_vendors;

-- ---------------------------------------------------------------------------
-- 3. The people
-- ---------------------------------------------------------------------------
delete from vs_invites;
delete from vs_profiles;
delete from vs_audit;

-- The accounts themselves. A profile cascades from auth.users, so this alone
-- would have cleared vs_profiles; both are done so the count reads true either
-- way. If your Supabase project refuses this line, delete the users by hand in
-- Authentication -> Users instead - it is the same thing through the dashboard.
do $do$
begin
  if to_regclass('auth.users') is null then
    raise notice 'no auth schema here - skipping the accounts';
  else
    execute $b$ delete from auth.users $b$;
    raise notice 'every account deleted - the next signup becomes the administrator';
  end if;
exception when others then
  raise notice 'could not delete the accounts from SQL (%). Delete them in Authentication -> Users.', sqlerrm;
end $do$;

-- ---------------------------------------------------------------------------
-- 4. What is deliberately KEPT
-- ---------------------------------------------------------------------------
-- These are not your data, they are the shape of the system, and the app does
-- not work without them:
--   vs_caps            who may do what - deleting it locks everybody out
--   vs_settings        the reply window, deemed approval, variance flag
--   vs_adj_types       the adjustment list the manager picks from
--   vs_head_templates  the standard booking heads a NEW site starts with
-- All four are editable from the Administration screens, so change them there
-- rather than here. The block below only puts back anything that went missing.
insert into vs_settings (id) values (1) on conflict (id) do nothing;

insert into vs_caps (role, cap) values
  ('admin','view_all'),('admin','manage_users'),('admin','manage_vendors'),
  ('admin','manage_contracts'),('admin','manage_settlements'),('admin','manage_masters'),
  ('manager','view_all'),('manager','edit_draft'),('manager','share'),('manager','logcall'),
  ('manager','resolve'),('manager','revise'),('manager','remind'),('manager','pay'),
  ('accounts','view_all'),('accounts','post_payroll'),('accounts','pay'),
  ('ceo','view_all'),('vp','view_all'),
  ('vendor','raise'),('vendor','confirm'),('vendor','approve')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 5. The files, last of all
-- ---------------------------------------------------------------------------
-- Supabase refuses a direct DELETE on storage.objects - a trigger called
-- storage.protect_delete() raises 42501 - because removing the row would strip
-- the only reference to the file behind it and leave that file stranded in the
-- bucket forever. So this is attempted, not assumed, and a refusal is reported
-- rather than allowed to stop the reset. It runs last for the same reason:
-- everything above has already gone through by the time we get here.
--
-- Nothing in the portal points at these files any more regardless - the
-- vs_documents rows went with their settlements in step 1.
do $do$
declare n bigint;
begin
  if to_regclass('storage.objects') is null then
    raise notice 'FILES: no storage schema here, nothing to do';
    return;
  end if;
  execute $b$ select count(*) from storage.objects where bucket_id = 'vs-docs' $b$ into n;
  if n = 0 then
    raise notice 'FILES: the vs-docs bucket is already empty';
    return;
  end if;
  begin
    execute $b$ delete from storage.objects where bucket_id = 'vs-docs' $b$;
    raise notice 'FILES: vs-docs emptied, % removed', n;
  exception when others then
    raise notice 'FILES: Supabase will not let SQL delete storage rows (%).', sqlerrm;
    raise notice 'FILES: % file(s) are still sitting in the vs-docs bucket. The portal no longer', n;
    raise notice 'FILES: points at any of them, so nobody can reach them through the app. To remove';
    raise notice 'FILES: the files themselves: Storage -> vs-docs -> select all -> Delete.';
  end;
end $do$;

-- ---------------------------------------------------------------- after
select 'AFTER' as when_,
  (select count(*) from vs_statements) as statements,
  (select count(*) from vs_versions)   as versions,
  (select count(*) from vs_version_lines) as lines,
  (select count(*) from vs_payments)   as payments,
  (select count(*) from vs_documents)  as documents,
  (select count(*) from vs_contracts)  as tenures,
  (select count(*) from vs_sites)      as sites,
  (select count(*) from vs_vendors)    as vendors,
  (select count(*) from vs_profiles)   as logins,
  (select count(*) from vs_audit)      as audit_rows;

select 'KEPT' as what,
  (select count(*) from vs_caps)           as capability_rows,
  (select count(*) from vs_settings)       as settings_row,
  (select count(*) from vs_adj_types)      as adjustment_types,
  (select count(*) from vs_head_templates) as standard_heads,
  vs_needs_setup()                          as shows_first_run_screen;
-- Expect every count in AFTER to be 0, and shows_first_run_screen to be t.
--
-- Now open the app. It will ask you to create the first administrator, and
-- that account becomes Admin. From there: Vendors, then Sites & tenures, then
-- the logins, then open your first month.

-- ============================================================================
-- AFTERWARDS
-- ============================================================================
-- 1. Sign out in the browser, or hard-refresh (Ctrl+Shift+R). Your old session
--    token is still in the browser even though the account behind it is gone,
--    so the app may look stuck until you do.
--
-- 2. Do NOT run VS-SEED-ALL.sql or VS-IMPORT-HISTORY.sql again unless you want
--    the old sites, vendors and the 84 spreadsheet months back. Those two files
--    are the old data. Everything else is safe:
--       VS-SETUP.sql, VS-PATCH-1.sql, VS-PATCH-2.sql   already applied, and
--                                                       re-running them changes
--                                                       nothing
--
-- 3. Open the app. It asks you to create the first administrator, and that
--    account becomes Admin. Then, in order:
--       Administration > Vendors            add each operating partner
--       Administration > Sites & tenures    add each site, assign its vendor
--                                           with the date he started, and set
--                                           the vehicle count
--       Administration > Booking heads      adjust the heads per site, since
--                                           a new site starts with the 13
--                                           standard ones
--       Administration > Users & roles      create a login for each person and
--                                           each vendor
--       Administration > Settlements        open your first month
--
-- 4. On the files: step 5 tells you whether the vs-docs bucket still holds
--    anything. Supabase does not allow SQL to delete storage rows, so if it
--    reports files left over, clear them in Storage > vs-docs in the dashboard.
--    They are already unreachable from the app either way.
