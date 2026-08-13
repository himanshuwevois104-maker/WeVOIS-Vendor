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
