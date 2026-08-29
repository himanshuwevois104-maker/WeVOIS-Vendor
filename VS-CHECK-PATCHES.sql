-- VS-CHECK-PATCHES.sql
-- ============================================================================
-- Which patches have actually been run against this database.
--
-- Run it in the Supabase SQL editor any time something in the app is refused
-- with a message that makes no sense. The app and the database are deployed
-- separately, so a new build can end up talking to a database that has not had
-- the matching patch run - and the only symptom is a raw error at the moment
-- somebody uses the feature.
--
-- Reads nothing but the catalogue. Changes nothing.
-- ============================================================================
select
  p.file,
  case when p.present then 'RUN' else 'NOT RUN' end as state,
  p.what
from (
  values
    ('VS-SETUP.sql   ', (select count(*) > 0 from pg_proc where proname='vs_share'),
     'the schema itself'),
    ('VS-PATCH-1.sql ', (select count(*) > 0 from pg_proc where proname='vs_add_document'),
     'file attachments, the workbook importer, manager can pay'),
    ('VS-PATCH-2.sql ', (select count(*) > 0 from pg_proc where proname='vs_sees_site'),
     'each vendor sees only his own sites'),
    ('VS-PATCH-3.sql ', (select count(*) > 0 from pg_proc where proname='vs_set_site'),
     'editing a site and its tenures'),
    ('VS-PATCH-4.sql ', (select count(*) > 0 from vs_caps where role='manager' and cap='post_payroll'),
     'the vendor manager posts payroll'),
    ('VS-PATCH-5.sql ', (select count(*) > 0 from pg_proc where proname='vs_raise_query'),
     'queries, VENDOR FILE UPLOADS, points on the earned amount, payroll top-ups'),
    ('VS-PATCH-6.sql ', (select count(*) > 0 from pg_proc where proname='vs_statement_extra'),
     'email notifications and CEO/VP confirmation')
) as p(file, present, what);

-- The storage rule that decides whether a VENDOR may attach a file.
-- If this says the vendor is not mentioned, VS-PATCH-5.sql has not been run,
-- and a vendor attaching a bill will see
--   "new row violates row-level security policy"
select
  case when exists (select 1 from pg_policies
                     where schemaname='storage' and tablename='objects' and policyname='p_vsdocs_write')
       then 'the upload policy exists' else 'NO UPLOAD POLICY - run VS-PATCH-1.sql' end as policy_state,
  case when exists (select 1 from pg_policies
                     where schemaname='storage' and tablename='objects' and policyname='p_vsdocs_write'
                       and qual || with_check like '%vendor%')
       then 'vendors CAN attach' else 'vendors CANNOT attach - run VS-PATCH-5.sql' end as vendor_uploads;
