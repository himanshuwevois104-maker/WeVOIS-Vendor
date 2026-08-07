-- VS-IMPORT-HISTORY.sql
-- ============================================================================
-- Every month in 'Operation Partners Payment Details 9.xlsx', loaded as a
-- closed settlement so the portal shows the same history your sheet does.
--
-- Run AFTER VS-SETUP.sql, VS-SEED-ALL.sql and VS-PATCH-1.sql, in the Supabase
-- SQL editor, selecting the whole file. Safe to re-run: a month that is
-- already there is skipped and says so.
--
-- YOU MUST HAVE SIGNED INTO THE APP ONCE FIRST, so an administrator exists.
-- The SQL editor is not a signed-in user, so every write function refuses it -
-- that refusal is the security model working. The block below tells the
-- database to act as your administrator for the length of this script, and
-- hands the identity back at the end.
--
-- Months the sheet marks Paid or Done come in as PAID, with a payment row
-- referenced 'IMPORTED' because the spreadsheet carries no UTR. The rest come
-- in as APPROVED and not yet paid, which is what the sheet implies. Every one
-- carries a line in its record saying it was imported rather than raised
-- through the portal.
-- Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------- who am I
do $do$
declare a uuid; n text;
begin
  select id, full_name into a, n
    from vs_profiles where role = 'admin' and active
   order by created_at limit 1;
  if a is null then
    raise exception 'No administrator exists yet. Open the app, create the first
 account (the first one to sign up becomes the administrator), then run this file.'
      using errcode = '42501';
  end if;
  -- auth.uid() reads these; setting them makes this script act as that person,
  -- so the import is attributed to a real name in every record it writes
  perform set_config('request.jwt.claim.sub', a::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', a::text)::text, false);
  raise notice 'Importing as %', n;
end $do$;

create temp table if not exists vs_import_log(n serial, site text, period date, result text);

-- ---------------------------------------------------------------- Kuchaman
--   23 months, 2024-08 to 2026-06
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2024-08-01', vs_import_month('Kuchaman', date '2024-08-01', 738150.0, 'paid',
  '{"fuel_exp": 113411.0, "wages_exp_driver_helper": 197258.0, "salary_exp_staff": 28400.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 113411.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2024-09-01', vs_import_month('Kuchaman', date '2024-09-01', 862200.0, 'paid',
  '{"fuel_exp": 169873.0, "wages_exp_driver_helper": 287137.0, "esic_pf_employee_part": 13906.0, "esic_pf_employer_part": 19036.0, "salary_exp_staff": 32515.0, "esic_pf_employee_part_2": 1485.0, "esic_pf_employer_part_2": 2035.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 504779.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2024-10-01', vs_import_month('Kuchaman', date '2024-10-01', 980250.0, 'paid',
  '{"fuel_exp": 195291.0, "wages_exp_driver_helper": 306890.0, "esic_pf_employee_part": 13915.0, "esic_pf_employer_part": 19043.0, "salary_exp_staff": 37380.0, "esic_pf_employee_part_2": 1485.0, "esic_pf_employer_part_2": 2035.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 502181.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2024-11-01', vs_import_month('Kuchaman', date '2024-11-01', 805200.0, 'paid',
  '{"r_m_exp": 79401.0, "miss_exp": 2230.0, "print_exp": 6855.0, "fuel_exp": 161852.0, "wages_exp_driver_helper": 238293.0, "esic_pf_employee_part": 13556.0, "esic_pf_employer_part": 18558.0, "salary_exp_staff": 37047.0, "esic_pf_employee_part_2": 1485.0, "esic_pf_employer_part_2": 2035.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 163164.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2024-12-01', vs_import_month('Kuchaman', date '2024-12-01', 939900.0, 'paid',
  '{"r_m_exp": 98760.0, "fuel_exp": 220554.0, "wages_exp_driver_helper": 352693.0, "esic_pf_employee_part": 19032.0, "esic_pf_employer_part": 26050.0, "salary_exp_staff": 38180.0, "esic_pf_employee_part_2": 1485.0, "esic_pf_employer_part_2": 2035.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 98760.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-01-01', vs_import_month('Kuchaman', date '2025-01-01', 923550.0, 'paid',
  '{"r_m_exp": 191930.0, "miss_exp": 1200.0, "fuel_exp": 245838.0, "wages_exp_driver_helper": 373776.0, "esic_pf_employee_part": 23134.0, "esic_pf_employer_part": 31721.0, "salary_exp_staff": 34644.0, "esic_pf_employee_part_2": 1485.0, "esic_pf_employer_part_2": 2035.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 193130.0}, {"label": "Direct Payment to OP", "effect": "deduct", "amount": 400000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-02-01', vs_import_month('Kuchaman', date '2025-02-01', 828900.0, 'paid',
  '{"r_m_exp": 132340.0, "fuel_exp": 253351.0, "wages_exp_driver_helper": 408680.0, "esic_pf_employee_part": 24077.0, "esic_pf_employer_part": 32590.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 132340.0}, {"label": "Direct Payment to OP", "effect": "deduct", "amount": 500000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-03-01', vs_import_month('Kuchaman', date '2025-03-01', 875400.0, 'paid',
  '{"r_m_exp": 117215.0, "maint_exp_by_shyam_ji_punit": 34949.0, "fuel_exp_adj": 402701.0, "fuel_exp": 276209.0, "wages_exp_driver_helper": 428413.0, "esic_pf_employee_part": 23508.0, "esic_pf_employer_part": 31865.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 117215.0}, {"label": "Direct Payment to OP", "effect": "deduct", "amount": 100000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-04-01', vs_import_month('Kuchaman', date '2025-04-01', 901200.0, 'paid',
  '{"r_m_exp": 127290.0, "maint_exp_by_shyam_ji_punit": 16200.0, "fuel_exp_adj": 400624.0, "fuel_exp": 280967.0, "wages_exp_driver_helper": 425971.0, "esic_pf_employee_part": 22769.0, "esic_pf_employer_part": 31144.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 127290.0}, {"label": "Direct Payment to OP", "effect": "deduct", "amount": 300000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-05-01', vs_import_month('Kuchaman', date '2025-05-01', 882150.0, 'paid',
  '{"r_m_exp": 152500.0, "fuel_exp_adj": 318865.0, "fuel_exp": 308974.0, "wages_exp_driver_helper": 375882.0, "esic_pf_employee_part": 21982.0, "esic_pf_employer_part": 30087.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 152500.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-06-01', vs_import_month('Kuchaman', date '2025-06-01', 895200.0, 'paid',
  '{"r_m_exp": 164685.0, "maint_exp_by_shyam_ji_punit": 34182.0, "fuel_exp": 304321.0, "wages_exp_driver_helper": 386767.0, "esic_pf_employee_part": 23382.0, "esic_pf_employer_part": 32003.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 164685.0}, {"label": "Direct Payment to OP", "effect": "deduct", "amount": 300000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-07-01', vs_import_month('Kuchaman', date '2025-07-01', 1075500.0, 'paid',
  '{"r_m_exp": 96625.0, "maint_exp_by_shyam_ji_punit": 23810.0, "fuel_exp": 303702.0, "wages_exp_driver_helper": 389434.0, "esic_pf_employee_part": 22246.0, "esic_pf_employer_part": 30453.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 96625.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-08-01', vs_import_month('Kuchaman', date '2025-08-01', 1032750.0, 'paid',
  '{"r_m_exp": 53925.0, "fuel_exp": 326293.0, "wages_exp_driver_helper": 386189.0, "esic_pf_employee_part": 21308.0, "esic_pf_employer_part": 29167.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 53925.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-09-01', vs_import_month('Kuchaman', date '2025-09-01', 1116000.0, 'paid',
  '{"r_m_exp": 123410.0, "fuel_exp": 316983.31, "wages_exp_driver_helper": 390789.0, "esic_pf_employee_part": 22429.0, "esic_pf_employer_part": 30704.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 123410.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 13907.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-10-01', vs_import_month('Kuchaman', date '2025-10-01', 1155450.0, 'paid',
  '{"r_m_exp": 61970.0, "fuel_exp": 335952.0, "wages_exp_driver_helper": 397768.0, "esic_pf_employee_part": 22357.0, "esic_pf_employer_part": 30596.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 61970.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 19461.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-11-01', vs_import_month('Kuchaman', date '2025-11-01', 964650.0, 'approved',
  '{"r_m_exp": 176895.0, "maint_exp_by_shyam_ji_punit": 43003.0, "fuel_exp": 314731.0, "wages_exp_driver_helper": 380766.0, "esic_pf_employee_part": 23591.0, "esic_pf_employer_part": 31919.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 176895.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 9405.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2025-12-01', vs_import_month('Kuchaman', date '2025-12-01', 1063200.0, 'paid',
  '{"r_m_exp": 238931.0, "maint_exp_by_shyam_ji_punit": 5304.0, "fuel_exp": 306408.0, "wages_exp_driver_helper": 381254.0, "esic_pf_employee_part": 22447.0, "esic_pf_employer_part": 30418.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 238931.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 18093.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2026-01-01', vs_import_month('Kuchaman', date '2026-01-01', 1080750.0, 'paid',
  '{"r_m_exp": 119160.0, "maint_exp_by_shyam_ji_punit": 9654.0, "fuel_exp": 293309.0, "wages_exp_driver_helper": 392552.0, "esic_pf_employee_part": 22501.0, "esic_pf_employer_part": 30502.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 119160.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 9526.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2026-02-01', vs_import_month('Kuchaman', date '2026-02-01', 867150.0, 'paid',
  '{"r_m_exp": 178865.0, "maint_exp_by_shyam_ji_punit": 23336.0, "fuel_exp": 289712.0, "wages_exp_driver_helper": 376705.0, "esic_pf_employee_part": 21528.0, "esic_pf_employer_part": 29194.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 178865.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 6639.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2026-03-01', vs_import_month('Kuchaman', date '2026-03-01', 1016400.0, 'paid',
  '{"r_m_exp": 179278.0, "fuel_exp": 323254.0, "wages_exp_driver_helper": 398182.0, "esic_pf_employee_part": 23354.0, "esic_pf_employer_part": 31138.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 179278.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 6639.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2026-04-01', vs_import_month('Kuchaman', date '2026-04-01', 1065400.0, 'paid',
  '{"r_m_exp": 198440.0, "maint_exp_by_shyam_ji_punit": 81209.0, "fuel_exp": 327532.0, "wages_exp_driver_helper": 359907.0, "esic_pf_employee_part": 23980.0, "esic_pf_employer_part": 31852.0, "other_exp": 15153.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 198440.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 6639.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2026-05-01', vs_import_month('Kuchaman', date '2026-05-01', 928832.0, 'approved',
  '{"r_m_exp": 95530.0, "fuel_exp": 328774.0, "wages_exp_driver_helper": 380021.0, "esic_pf_employee_part": 24881.0, "esic_pf_employer_part": 33057.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 95530.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Kuchaman', date '2026-06-01', vs_import_month('Kuchaman', date '2026-06-01', 597240.0, 'approved',
  '{"r_m_exp": 26360.0, "fuel_exp": 309124.0, "wages_exp_driver_helper": 392658.0, "esic_pf_employee_part": 26060.0, "esic_pf_employer_part": 34540.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 26360.0}]'::jsonb, null);

-- ---------------------------------------------------------------- Parbatsar
--   6 months, 2026-01 to 2026-06
insert into vs_import_log(site,period,result) select 'Parbatsar', date '2026-01-01', vs_import_month('Parbatsar', date '2026-01-01', 305250.0, 'paid',
  '{"fuel_exp": 76087.0, "wages_exp_driver_helper": 98610.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Parbatsar', date '2026-02-01', vs_import_month('Parbatsar', date '2026-02-01', 312000.0, 'paid',
  '{"fuel_exp": 83201.0, "wages_exp_driver_helper": 120394.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Parbatsar', date '2026-03-01', vs_import_month('Parbatsar', date '2026-03-01', 340350.0, 'paid',
  '{"fuel_exp": 89269.0, "wages_exp_driver_helper": 121746.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Parbatsar', date '2026-04-01', vs_import_month('Parbatsar', date '2026-04-01', 308400.0, 'paid',
  '{"fuel_exp": 106216.0, "wages_exp_driver_helper": 101117.0, "esic_pf_employee_part": 6018.0, "esic_pf_employer_part": 8059.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Parbatsar', date '2026-05-01', vs_import_month('Parbatsar', date '2026-05-01', 329768.0, 'approved',
  '{"fuel_exp": 113704.0, "wages_exp_driver_helper": 111874.0, "esic_pf_employee_part": 6029.0, "esic_pf_employer_part": 8072.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Parbatsar', date '2026-06-01', vs_import_month('Parbatsar', date '2026-06-01', 291989.0, 'approved',
  '{"fuel_exp": 52590.0, "wages_exp_driver_helper": 95921.0, "esic_pf_employee_part": 5746.0, "esic_pf_employer_part": 7697.0}'::jsonb,
  '[]'::jsonb, null);

-- ---------------------------------------------------------------- Nawa
--   20 months, 2024-12 to 2026-06
insert into vs_import_log(site,period,result) select 'Nawa', date '2024-12-01', vs_import_month('Nawa', date '2024-12-01', 13500.0, 'approved',
  '{}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-01-01', vs_import_month('Nawa', date '2025-01-01', 167400.0, 'approved',
  '{"r_m_exp": 67600.0, "fuel_exp": 50000.0, "wages_exp_driver_helper": 71289.0, "esic_pf_employee_part": 4368.0, "esic_pf_employer_part": 5979.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 117600.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-02-01', vs_import_month('Nawa', date '2025-02-01', 219000.0, 'approved',
  '{"fuel_exp": 34807.0, "wages_exp_driver_helper": 99860.0, "esic_pf_employee_part": 5853.0, "esic_pf_employer_part": 8013.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-03-01', vs_import_month('Nawa', date '2025-03-01', 248400.0, 'approved',
  '{"maint_exp_by_shyam_ji_punit": 6053.0, "fuel_exp": 48229.0, "wages_exp_driver_helper": 99027.0, "esic_pf_employee_part": 6237.0, "esic_pf_employer_part": 8214.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-04-01', vs_import_month('Nawa', date '2025-04-01', 238650.0, 'approved',
  '{"r_m_exp": 5000.0, "fuel_exp": 49304.0, "wages_exp_driver_helper": 98208.0, "esic_pf_employee_part": 6078.0, "esic_pf_employer_part": 7977.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-05-01', vs_import_month('Nawa', date '2025-05-01', 231900.0, 'approved',
  '{"fuel_exp": 49962.0, "wages_exp_driver_helper": 66017.0, "esic_pf_employee_part": 4787.0, "esic_pf_employer_part": 6549.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-06-01', vs_import_month('Nawa', date '2025-06-01', 258750.0, 'approved',
  '{"maint_exp_by_shyam_ji_punit": 2500.0, "fuel_exp": 56320.0, "wages_exp_driver_helper": 76885.0, "esic_pf_employee_part": 5697.0, "esic_pf_employer_part": 7506.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-07-01', vs_import_month('Nawa', date '2025-07-01', 251100.0, 'approved',
  '{"maint_exp_by_shyam_ji_punit": 5520.0, "fuel_exp": 75754.0, "wages_exp_driver_helper": 86849.0, "esic_pf_employee_part": 4747.0, "esic_pf_employer_part": 6498.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-08-01', vs_import_month('Nawa', date '2025-08-01', 245550.0, 'approved',
  '{"r_m_exp": 2900.0, "fuel_exp": 72912.0, "wages_exp_driver_helper": 75788.0, "esic_pf_employee_part": 3699.0, "esic_pf_employer_part": 5065.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-09-01', vs_import_month('Nawa', date '2025-09-01', 196350.0, 'approved',
  '{"fuel_exp": 88091.0, "wages_exp_driver_helper": 72383.0, "esic_pf_employee_part": 3050.0, "esic_pf_employer_part": 4176.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-10-01', vs_import_month('Nawa', date '2025-10-01', 230100.0, 'approved',
  '{"fuel_exp": 86867.0, "wages_exp_driver_helper": 84876.0, "esic_pf_employee_part": 2470.0, "esic_pf_employer_part": 3382.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-11-01', vs_import_month('Nawa', date '2025-11-01', 193500.0, 'paid',
  '{"r_m_exp": 22316.0, "fuel_exp": 52980.0, "wages_exp_driver_helper": 69393.0, "esic_pf_employee_part": 2223.0, "esic_pf_employer_part": 2977.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 22316.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 20864.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2025-12-01', vs_import_month('Nawa', date '2025-12-01', 225000.0, 'approved',
  '{"r_m_exp": 700.0, "fuel_exp": 49136.0, "wages_exp_driver_helper": 85695.0, "esic_pf_employee_part": 2462.0, "esic_pf_employer_part": 3372.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 700.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 20864.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-01-01', vs_import_month('Nawa', date '2026-01-01', 234300.0, 'approved',
  '{"fuel_exp": 65182.0, "wages_exp_driver_helper": 83017.0, "esic_pf_employee_part": 1836.0, "esic_pf_employer_part": 2515.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-02-01', vs_import_month('Nawa', date '2026-02-01', 186900.0, 'approved',
  '{"fuel_exp": 58554.0, "wages_exp_driver_helper": 100880.0, "esic_pf_employee_part": 1890.0, "esic_pf_employer_part": 2589.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-03-01', vs_import_month('Nawa', date '2026-03-01', 145922.0, 'approved',
  '{"r_m_exp": 6200.0, "fuel_exp": 67696.0, "wages_exp_driver_helper": 87405.0, "esic_pf_employee_part": 1552.0, "esic_pf_employer_part": 2079.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 6200.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-04-01', vs_import_month('Nawa', date '2026-04-01', 122100.0, 'approved',
  '{"fuel_exp": 49007.0, "wages_exp_driver_helper": 49370.0, "esic_pf_employee_part": 1554.0, "esic_pf_employer_part": 2081.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-04-01', vs_import_month('Nawa', date '2026-04-01', 63783.0, 'paid',
  '{}'::jsonb,
  '[]'::jsonb, 'incoming');   -- ( From 16th April Hand over to FIROJ)
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-05-01', vs_import_month('Nawa', date '2026-05-01', 25543.0, 'approved',
  '{"fuel_exp": 15040.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Nawa', date '2026-06-01', vs_import_month('Nawa', date '2026-06-01', 78111.0, 'approved',
  '{"r_m_exp": 33000.0}'::jsonb,
  '[]'::jsonb, null);

-- ---------------------------------------------------------------- Bundi
--   5 months, 2026-02 to 2026-06
insert into vs_import_log(site,period,result) select 'Bundi', date '2026-02-01', vs_import_month('Bundi', date '2026-02-01', 664127.0, 'approved',
  '{"r_m_exp": 1800.0, "fuel_exp_loader_tractor_of_wevois": -58207.79, "fuel_exp": 209129.0, "wages_exp_driver_helper": 296036.0, "esic_pf_employee_part_by_wevois": 13979.0, "esic_pf_employer_part_by_wevois": 14108.0, "vehicle_rent_of_5_tractor": 42260.0}'::jsonb,
  '[{"label": "Add back: ESIC Pf (Employee Part)-By Wevois", "effect": "add", "amount": 13979.0}, {"label": "Add back: ESIC Pf (Employer Part)- By Wevois", "effect": "add", "amount": 14108.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Bundi', date '2026-03-01', vs_import_month('Bundi', date '2026-03-01', 830841.0, 'approved',
  '{"r_m_exp": 600.0, "fuel_exp_loader_tractor_of_wevois": -130601.46, "fuel_exp": 315084.0, "wages_exp_driver_helper": 348587.0, "esic_pf_employee_part_by_wevois": 20137.0, "esic_pf_employer_part_by_wevois": 26956.0, "vehicle_rent_of_5_tractor": 40072.0}'::jsonb,
  '[{"label": "Paid Through WeVois to OP", "effect": "deduct", "amount": 25000.0}, {"label": "Add back: ESIC Pf (Employee Part)-By Wevois", "effect": "add", "amount": 20137.0}, {"label": "Add back: ESIC Pf (Employer Part)- By Wevois", "effect": "add", "amount": 26956.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Bundi', date '2026-04-01', vs_import_month('Bundi', date '2026-04-01', 900187.0, 'approved',
  '{"fuel_exp_loader_tractor_of_wevois": -185253.5, "fuel_exp": 350156.0, "wages_exp_driver_helper": 377960.0, "esic_pf_employee_part_by_wevois": 22694.0, "esic_pf_employer_part_by_wevois": 30170.0, "vehicle_rent_of_5_tractor": 52000.0}'::jsonb,
  '[{"label": "Add back: ESIC Pf (Employee Part)-By Wevois", "effect": "add", "amount": 22694.0}, {"label": "Add back: ESIC Pf (Employer Part)- By Wevois", "effect": "add", "amount": 30170.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Bundi', date '2026-05-01', vs_import_month('Bundi', date '2026-05-01', 904438.0, 'approved',
  '{"fuel_exp_loader_tractor_of_wevois": -202308.0, "fuel_exp": 400139.0, "wages_exp_driver_helper": 397755.0, "esic_pf_employee_part_by_wevois": 21302.0, "esic_pf_employer_part_by_wevois": 28380.0}'::jsonb,
  '[{"label": "Add back: ESIC Pf (Employee Part)-By Wevois", "effect": "add", "amount": 21302.0}, {"label": "Add back: ESIC Pf (Employer Part)- By Wevois", "effect": "add", "amount": 28380.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Bundi', date '2026-06-01', vs_import_month('Bundi', date '2026-06-01', 906466.0, 'approved',
  '{"wages_exp_driver_helper": 396031.0, "esic_pf_employee_part_by_wevois": 20566.0, "esic_pf_employer_part_by_wevois": 27423.0}'::jsonb,
  '[{"label": "Add back: ESIC Pf (Employee Part)-By Wevois", "effect": "add", "amount": 20566.0}, {"label": "Add back: ESIC Pf (Employer Part)- By Wevois", "effect": "add", "amount": 27423.0}]'::jsonb, null);

-- ---------------------------------------------------------------- Vidhisa
--   4 months, 2026-04 to 2026-07
insert into vs_import_log(site,period,result) select 'Vidhisa', date '2026-04-01', vs_import_month('Vidhisa', date '2026-04-01', 470145.0, 'approved',
  '{"maint_exp_by_co": 163233.0, "fuel_exp": 412049.0, "wages_exp_driver_helper": 188800.0, "salary_exp_staff": 64308.0, "esic_pf_employee_part_2": 4835.0, "esic_pf_employer_part_2": 6479.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Vidhisa', date '2026-05-01', vs_import_month('Vidhisa', date '2026-05-01', 714331.45, 'approved',
  '{"maint_exp_by_co": 97400.0, "fuel_exp": 341627.0, "wages_exp_driver_helper": 376891.0, "salary_exp_staff": 90494.0, "esic_pf_employee_part_2": 4954.0, "esic_pf_employer_part_2": 6638.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Vidhisa', date '2026-06-01', vs_import_month('Vidhisa', date '2026-06-01', 870397.5, 'approved',
  '{"maint_exp_by_co": 30293.0, "fuel_exp": 208603.0, "wages_exp_driver_helper": 353937.0, "salary_exp_staff": 97056.0, "esic_pf_employee_part_2": 6594.0, "esic_pf_employer_part_2": 7747.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Vidhisa', date '2026-07-01', vs_import_month('Vidhisa', date '2026-07-01', 1574633.06, 'approved',
  '{}'::jsonb,
  '[]'::jsonb, null);

-- Dei: terms only in the workbook, no monthly sheet
-- Laxmangarh: terms only in the workbook, no monthly sheet
-- ---------------------------------------------------------------- Jhunjhunu
--   7 months, 2025-12 to 2026-06
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2025-12-01', vs_import_month('Jhunjhunu', date '2025-12-01', 228823.0, 'paid',
  '{"fuel_exp": 70546.0, "wages_exp_driver_helper": 78277.0}'::jsonb,
  '[{"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2026-01-01', vs_import_month('Jhunjhunu', date '2026-01-01', 773419.0, 'paid',
  '{"r_m_exp_by_kishan_ji": 853.0, "fuel_exp": 249122.0, "wages_exp_driver_helper": 324392.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.(By Kishan ji)", "effect": "add", "amount": 853.0}, {"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2026-02-01', vs_import_month('Jhunjhunu', date '2026-02-01', 1173875.0, 'paid',
  '{"r_m_exp_by_kishan_ji": 121067.0, "fuel_exp": 326495.0, "wages_exp_driver_helper": 557174.0, "esic_pf_employee_part": 2694.0, "esic_pf_employer_part": 2694.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.(By Kishan ji)", "effect": "add", "amount": 121067.0}, {"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2026-03-01', vs_import_month('Jhunjhunu', date '2026-03-01', 1351213.0, 'paid',
  '{"r_m_exp_by_kishan_ji": 66831.0, "fuel_exp": 377187.0, "wages_exp_driver_helper": 855890.0, "esic_pf_employee_part": 3068.0, "esic_pf_employer_part": 4107.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.(By Kishan ji)", "effect": "add", "amount": 66831.0}, {"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2026-04-01', vs_import_month('Jhunjhunu', date '2026-04-01', 1728130.0, 'approved',
  '{"r_m_exp_by_kishan_ji": 88243.0, "fuel_exp": 463199.0, "wages_exp_driver_helper": 1154263.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.(By Kishan ji)", "effect": "add", "amount": 88243.0}, {"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2026-05-01', vs_import_month('Jhunjhunu', date '2026-05-01', 1729758.0, 'approved',
  '{"r_m_exp_by_kishan_ji": 59448.0, "fuel_exp": 457648.0, "wages_exp_driver_helper": 1134815.0, "esic_pf_employee_part": 3733.0, "esic_pf_employer_part": 5341.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.(By Kishan ji)", "effect": "add", "amount": 59448.0}, {"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Jhunjhunu', date '2026-06-01', vs_import_month('Jhunjhunu', date '2026-06-01', 2401921.0, 'approved',
  '{"maint_exp_by_company": 41988.0, "fuel_exp": 468610.0, "wages_exp_driver_helper": 1130286.0, "esic_pf_employee_part": 7749.0, "esic_pf_employer_part": 10375.0}'::jsonb,
  '[{"label": "Add back: Maint. Exp By Company", "effect": "add", "amount": 41988.0}, {"label": "Extra Amount Per Month", "effect": "add", "amount": 50000.0}]'::jsonb, null);

-- ---------------------------------------------------------------- Chirawa
--   20 months, 2024-10 to 2026-05
insert into vs_import_log(site,period,result) select 'Chirawa', date '2024-10-01', vs_import_month('Chirawa', date '2024-10-01', 0.0, 'approved',
  '{"salary_exp_staff": 1200.0}'::jsonb,
  '[]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2024-11-01', vs_import_month('Chirawa', date '2024-11-01', 262200.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 20926.0, "print_exp": 700.0, "fuel_exp": 70545.0, "wages_exp_driver_helper": 83839.0, "salary_exp_staff": 25133.0, "esic_pf_employee_part_2": 1502.0, "esic_pf_employer_part_2": 2057.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 20926.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2024-12-01', vs_import_month('Chirawa', date '2024-12-01', 533050.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 80755.0, "maint_exp_by_shyam_ji": 10364.0, "fuel_exp": 164281.0, "wages_exp_driver_helper": 145972.0, "esic_pf_employee_part": 8136.0, "esic_pf_employer_part": 11132.0, "salary_exp_staff": 34323.0, "esic_pf_employee_part_2": 2147.0, "esic_pf_employer_part_2": 2942.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 80755.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-01-01', vs_import_month('Chirawa', date '2025-01-01', 624950.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 57585.0, "print_exp": 161.0, "water_exp": 1400.0, "fuel_exp": 155608.0, "wages_exp_driver_helper": 181597.0, "esic_pf_employee_part": 10775.0, "esic_pf_employer_part": 14755.0, "salary_exp_staff": 37497.0, "esic_pf_employee_part_2": 2430.0, "esic_pf_employer_part_2": 3330.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 57585.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-02-01', vs_import_month('Chirawa', date '2025-02-01', 544350.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 55750.0, "print_exp": 224.0, "water_exp": 900.0, "fuel_exp": 131686.0, "wages_exp_driver_helper": 202310.0, "esic_pf_employee_part": 13104.0, "esic_pf_employer_part": 17941.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 55750.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-03-01', vs_import_month('Chirawa', date '2025-03-01', 539050.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 130909.0, "maint_exp_by_shyam_ji": 3250.0, "fuel_exp": 143433.0, "wages_exp_driver_helper": 174289.0, "esic_pf_employee_part": 11194.0, "esic_pf_employer_part": 15328.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 130909.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-04-01', vs_import_month('Chirawa', date '2025-04-01', 539300.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 98470.0, "r_m_exp_paid_by_wevois": 803.0, "fuel_exp": 142763.0, "wages_exp_driver_helper": 163727.0, "esic_pf_employee_part": 10097.0, "esic_pf_employer_part": 13827.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 98470.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-05-01', vs_import_month('Chirawa', date '2025-05-01', 505900.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 100740.0, "r_m_exp_paid_by_wevois": 4225.0, "fuel_exp": 126248.0, "wages_exp_driver_helper": 149575.0, "esic_pf_employee_part": 9242.0, "esic_pf_employer_part": 12653.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 100740.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-06-01', vs_import_month('Chirawa', date '2025-06-01', 502050.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 123978.0, "maint_exp_by_shyam_ji": 43660.0, "fuel_exp": 140416.0, "wages_exp_driver_helper": 185248.0, "esic_pf_employee_part": 11394.0, "esic_pf_employer_part": 15795.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 123978.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-07-01', vs_import_month('Chirawa', date '2025-07-01', 483800.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 176518.0, "fuel_exp": 138830.0, "wages_exp_driver_helper": 171926.0, "esic_pf_employee_part": 10182.0, "esic_pf_employer_part": 13941.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 176518.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-08-01', vs_import_month('Chirawa', date '2025-08-01', 516000.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 128488.0, "fuel_exp": 141181.0, "wages_exp_driver_helper": 212365.0, "esic_pf_employee_part": 9455.0, "esic_pf_employer_part": 12949.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 128488.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-09-01', vs_import_month('Chirawa', date '2025-09-01', 513800.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 138074.0, "fuel_exp": 135962.0, "wages_exp_driver_helper": 213279.0, "esic_pf_employee_part": 11890.0, "esic_pf_employer_part": 16281.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 138074.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-10-01', vs_import_month('Chirawa', date '2025-10-01', 539200.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 153155.0, "fuel_exp": 170647.0, "wages_exp_driver_helper": 184548.0, "esic_pf_employee_part": 10039.0, "esic_pf_employer_part": 13748.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 153155.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-11-01', vs_import_month('Chirawa', date '2025-11-01', 500850.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 174080.0, "maint_exp_by_shyam_ji": 12876.0, "fuel_exp": 141754.0, "wages_exp_driver_helper": 198394.0, "esic_pf_employee_part": 9698.0, "esic_pf_employer_part": 13284.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 174080.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2025-12-01', vs_import_month('Chirawa', date '2025-12-01', 538550.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 275562.0, "fuel_exp": 136696.0, "wages_exp_driver_helper": 214264.0, "esic_pf_employee_part": 9183.0, "esic_pf_employer_part": 12534.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 275562.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2026-01-01', vs_import_month('Chirawa', date '2026-01-01', 572250.0, 'paid',
  '{"r_m_exp_paid_by_kishan_ji": 214780.0, "fuel_exp": 147282.0, "wages_exp_driver_helper": 239260.0, "esic_pf_employee_part": 9319.0, "esic_pf_employer_part": 12408.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 214780.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2026-02-01', vs_import_month('Chirawa', date '2026-02-01', 497250.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 230490.0, "fuel_exp": 128261.0, "wages_exp_driver_helper": 210573.0, "esic_pf_employee_part": 11644.0, "esic_pf_employer_part": 16144.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 230490.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2026-03-01', vs_import_month('Chirawa', date '2026-03-01', 500700.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 262332.0, "fuel_exp": 131662.0, "wages_exp_driver_helper": 232453.0, "esic_pf_employee_part": 12882.0, "esic_pf_employer_part": 17251.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 262332.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2026-04-01', vs_import_month('Chirawa', date '2026-04-01', 74750.0, 'approved',
  '{"r_m_exp_paid_by_kishan_ji": 1200.0, "fuel_exp": 56630.0, "wages_exp_driver_helper": 89782.0, "esic_pf_employee_part": 4034.0, "esic_pf_employer_part": 5537.0}'::jsonb,
  '[{"label": "Add back: R&M Exp.( Paid By Kishan ji)", "effect": "add", "amount": 1200.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Chirawa', date '2026-05-01', vs_import_month('Chirawa', date '2026-05-01', 0.0, 'approved',
  '{"fuel_exp": 16578.0, "wages_exp_driver_helper": 24047.0, "esic_pf_employee_part": 3348.0, "esic_pf_employer_part": 4618.0}'::jsonb,
  '[]'::jsonb, null);

-- ---------------------------------------------------------------- Sujalpur
--   14 months, 2025-03 to 2026-04
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-03-01', vs_import_month('Sujalpur', date '2025-03-01', 220000.0, 'approved',
  '{"fuel_exp_by_shubham_ji": 4880.0, "wages_exp_driver_helper": 19874.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 4880.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-04-01', vs_import_month('Sujalpur', date '2025-04-01', 310000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 26045.0, "fuel_exp_by_shubham_ji": 104880.0, "wages_exp_driver_helper": 113550.0, "esic_pf_employee_part_from_wevois": 1746.0, "esic_pf_employer_part": 2392.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 132671.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 9194.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-05-01', vs_import_month('Sujalpur', date '2025-05-01', 310000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 930.0, "fuel_exp_by_shubham_ji": 117238.0, "wages_exp_driver_helper": 142502.0, "esic_pf_employee_part_from_wevois": 5340.0, "esic_pf_employer_part": 7328.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 123508.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 50089.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-06-01', vs_import_month('Sujalpur', date '2025-06-01', 310000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 4115.0, "fuel_exp_by_shubham_ji": 128453.0, "wages_exp_driver_helper": 78500.0, "esic_pf_employee_part_from_wevois": 3916.0, "esic_pf_employer_part": 5362.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 136484.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 699.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-07-01', vs_import_month('Sujalpur', date '2025-07-01', 324000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 13160.0, "fuel_exp_by_shubham_ji": 113567.0, "wages_exp_driver_helper": 79127.0, "esic_pf_employee_part_from_wevois": 3279.0, "esic_pf_employer_part": 4491.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 130006.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 10498.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-08-01', vs_import_month('Sujalpur', date '2025-08-01', 324000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 20735.0, "fuel_exp_by_shubham_ji": 270113.0, "wages_exp_driver_helper": 69859.0, "esic_pf_employee_part_from_wevois": 894.0, "esic_pf_employer_part": 1223.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 291742.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 17964.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-09-01', vs_import_month('Sujalpur', date '2025-09-01', 324000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 52010.0, "fuel_exp_by_shubham_ji": 154975.0, "wages_exp_driver_helper": 80113.0, "esic_pf_employee_part_from_wevois": 1418.0, "esic_pf_employer_part": 1942.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 208403.0}, {"label": "Salary Not Processed From WeVois", "effect": "add", "amount": 30655.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-10-01', vs_import_month('Sujalpur', date '2025-10-01', 324000.0, 'approved',
  '{"r_m_exp_by_subham_ji": 46580.0, "fuel_exp_by_shubham_ji": 109221.0, "wages_exp_driver_helper": 93594.0, "esic_pf_employee_part_from_wevois": 1726.0, "esic_pf_employer_part": 2366.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 157527.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-11-01', vs_import_month('Sujalpur', date '2025-11-01', 324000.0, 'paid',
  '{"r_m_exp_by_subham_ji": 6010.0, "fuel_exp_by_shubham_ji": 116418.0, "wages_exp_driver_helper": 120401.0, "esic_pf_employee_part_from_wevois": 2162.0, "esic_pf_employer_part": 2960.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 124590.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2025-12-01', vs_import_month('Sujalpur', date '2025-12-01', 324000.0, 'paid',
  '{"r_m_exp_by_subham_ji": 5400.0, "fuel_exp_by_shubham_ji": 116880.0, "wages_exp_driver_helper": 90988.0, "esic_pf_employee_part_from_wevois": 4076.0, "esic_pf_employer_part": 4766.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 126356.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2026-01-01', vs_import_month('Sujalpur', date '2026-01-01', 270900.0, 'paid',
  '{"fuel_exp_by_shubham_ji": 110809.0, "wages_exp_driver_helper": 83289.0, "esic_pf_employee_part_from_wevois": 3841.0, "esic_pf_employer_part": 4542.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 114650.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2026-02-01', vs_import_month('Sujalpur', date '2026-02-01', 163500.0, 'paid',
  '{"r_m_exp_by_subham_ji": 1720.0, "fuel_exp_by_shubham_ji": 97872.0, "wages_exp_driver_helper": 77526.0, "esic_pf_employee_part_from_wevois": 3506.0, "esic_pf_employer_part": 4223.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 103098.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2026-03-01', vs_import_month('Sujalpur', date '2026-03-01', 194250.0, 'approved',
  '{"r_m_exp_by_subham_ji": 6545.0, "fuel_exp_by_shubham_ji": 73337.0, "wages_exp_driver_helper": 60678.0, "esic_pf_employee_part_from_wevois": 2617.0, "esic_pf_employer_part": 3044.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 82499.0}]'::jsonb, null);
insert into vs_import_log(site,period,result) select 'Sujalpur', date '2026-04-01', vs_import_month('Sujalpur', date '2026-04-01', 42900.0, 'approved',
  '{"fuel_exp_by_shubham_ji": 14758.0}'::jsonb,
  '[{"label": "Paid Through OP or Company Exp.", "effect": "add", "amount": 14758.0}]'::jsonb, null);

-- ============================================================================
-- What happened
-- ============================================================================
select result, count(*) as months from vs_import_log group by result order by count(*) desc;

select site, to_char(period,'Mon YYYY') as month, result
  from vs_import_log where result not like 'ok%' order by site, period;

select v.name as vendor, s.name as site, count(*) as months,
       to_char(min(st.period),'Mon YYYY') as earliest,
       to_char(max(st.period),'Mon YYYY') as latest,
       count(*) filter (where st.status='paid') as marked_paid,
       to_char(sum(vs_version_final(vs_current_version(st.id))),'FM999,999,999') as total_final
  from vs_statements st
  join vs_contracts c on c.id = st.contract_id
  join vs_vendors   v on v.id = c.vendor_id
  join vs_sites     s on s.id = c.site_id
 group by v.name, s.name order by s.name, v.name;

-- ------------------------------------------------------------- hand it back
-- The editor stops acting as your administrator here, so anything you type in
-- this tab afterwards is back to being nobody, which is what it should be.
select set_config('request.jwt.claim.sub', '', false),
       set_config('request.jwt.claims', '', false);

