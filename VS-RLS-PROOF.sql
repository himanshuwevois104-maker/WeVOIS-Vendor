\set ON_ERROR_STOP 0
\pset pager off
\pset footer off
\pset tuples_only on
\pset format unaligned
\pset fieldsep ' '

create table if not exists t_ids(k text primary key, v uuid);
create or replace function ID(text) returns uuid language sql stable security definer as $$ select v from t_ids where k=$1 $$;
create or replace function PUT(text, uuid) returns uuid language sql security definer as $$
  insert into t_ids values($1,$2) on conflict (k) do update set v=excluded.v returning v $$;

create table if not exists t_res(n serial, ok bool, label text, got text, want text);
select set_config('t.verbose','',false);
grant all on t_ids, t_res to public;
grant all on sequence t_res_n_seq to public;

create or replace function AS_(p_uid uuid, p_sql text) returns text
language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
  execute p_sql into r;
  return coalesce(r::text, '(null)');
exception when others then return 'REFUSED'||coalesce(current_setting('t.verbose',true),''); end $$;

create or replace function DO_(p_uid uuid, p_sql text) returns text
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
  execute p_sql;
  return 'OK';
exception when others then return 'REFUSED'||coalesce(current_setting('t.verbose',true),''); end $$;

create or replace function CK(p_label text, p_got text, p_want text) returns void
language plpgsql security definer as $$
begin
  insert into t_res(ok,label,got,want) values (p_got is not distinct from p_want, p_label, p_got, p_want);
end $$;

-- uid shortcuts
create or replace function U(text) returns uuid language sql immutable as $$
  select case $1
    when 'admin'    then '11111111-1111-1111-1111-111111111111'::uuid
    when 'manager'  then '22222222-2222-2222-2222-222222222222'::uuid
    when 'accounts' then '33333333-3333-3333-3333-333333333333'::uuid
    when 'ceo'      then '44444444-4444-4444-4444-444444444444'::uuid
    when 'vp'       then '55555555-5555-5555-5555-555555555555'::uuid
    when 'ramesh'   then '66666666-6666-6666-6666-666666666666'::uuid
    when 'dinesh'   then '77777777-7777-7777-7777-777777777777'::uuid
    when 'stranger' then '99999999-9999-9999-9999-999999999999'::uuid end $$;

-- ============================ 1. bootstrap ============================
insert into auth.users (id, email, raw_user_meta_data)
values (U('admin'),'priya@wevois.com','{"full_name":"Priya Nair"}');
select CK('first signup becomes the admin', (select role||'/'||full_name from vs_profiles), 'admin/Priya Nair');
select CK('needs_setup flips to false', vs_needs_setup()::text, 'false');

-- ============================ 2. admin builds the org =================
do $$
begin
  perform set_config('request.jwt.claim.sub', U('admin')::text, false);
  perform PUT('ramesh',   vs_add_vendor('Ramesh Transport & Co.','OP-01','Ramesh Chand','ramesh@optrans.in','98290'));
  perform PUT('mahaveer', vs_add_vendor('Mahaveer Enterprises','OP-03','Dinesh Jain','dinesh@mahaveer.in','99283'));
  perform PUT('sa', vs_add_site('Kota Zone 2','Kota'));
  perform PUT('sb', vs_add_site('Kota Zone 5','Kota'));
  perform PUT('sc', vs_add_site('Bhilwara','Bhilwara'));
  perform PUT('c1', vs_add_contract(ID('ramesh'),   ID('sa'), 20, '2025-04-01'));
  perform PUT('c2', vs_add_contract(ID('ramesh'),   ID('sb'),  9, '2025-04-01'));
  perform PUT('c3', vs_add_contract(ID('mahaveer'), ID('sc'), 11, '2025-04-01'));
  perform vs_invite('himanshu@wevois.com','Himanshu Yadav','manager',null);
  perform vs_invite('rakesh@wevois.com','Rakesh Gupta','accounts',null);
  perform vs_invite('ceo@wevois.com','Anil Bhargava','ceo',null);
  perform vs_invite('vp@wevois.com','Meera Joshi','vp',null);
  perform vs_invite('ramesh@optrans.in','Ramesh Chand','vendor', ID('ramesh'));
  perform vs_invite('dinesh@mahaveer.in','Dinesh Jain','vendor', ID('mahaveer'));
end $$;
select CK('one vendor holds two sites', (select count(*)::text from vs_contracts where vendor_id=ID('ramesh')), '2');
select CK('vendor invite with no vendor_id refused',
  AS_(U('admin'), $$ select vs_invite('bad@x.com','B','vendor',null) $$), 'REFUSED');
select CK('staff invite carrying a vendor_id refused',
  AS_(U('admin'), format($$ select vs_invite('bad2@x.com','B','accounts',%L) $$, ID('ramesh'))), 'REFUSED');

insert into auth.users (id, email) values
  (U('manager'),'himanshu@wevois.com'), (U('accounts'),'rakesh@wevois.com'),
  (U('ceo'),'ceo@wevois.com'), (U('vp'),'vp@wevois.com'),
  (U('ramesh'),'ramesh@optrans.in'), (U('dinesh'),'dinesh@mahaveer.in'),
  (U('stranger'),'stranger@nowhere.com');
select CK('six invites became profiles, plus the admin', (select count(*)::text from vs_profiles), '7');
select CK('UNINVITED signup gets no profile at all',
  (select count(*)::text from vs_profiles where id=U('stranger')), '0');

-- ============================ 3. uninvited sees nothing ===============
select CK('uninvited reads 0 vendors',   AS_(U('stranger'), $$ select count(*) from vs_vendors $$), '0');
select CK('uninvited reads 0 sites',     AS_(U('stranger'), $$ select count(*) from vs_sites $$), '0');
select CK('uninvited reads 0 contracts', AS_(U('stranger'), $$ select count(*) from vs_contracts $$), '0');
select CK('uninvited reads 0 profiles',  AS_(U('stranger'), $$ select count(*) from vs_profiles $$), '0');
select CK('uninvited reads 0 booking heads', AS_(U('stranger'), $$ select count(*) from vs_heads $$), '0');
select CK('each new site got the 13 standard heads',
  (select count(*)::text from vs_heads where site_id=ID('sa')), '13');
select CK('uninvited reads 0 audit rows',AS_(U('stranger'), $$ select count(*) from vs_audit $$), '0');

-- ============================ 4. lifecycle is admin only ==============
select CK('manager cannot open a month',  AS_(U('manager'),  $$ select vs_open_month('2026-07-01') $$), 'REFUSED');
select CK('accounts cannot open a month', AS_(U('accounts'), $$ select vs_open_month('2026-07-01') $$), 'REFUSED');
select CK('CEO cannot open a month',      AS_(U('ceo'),      $$ select vs_open_month('2026-07-01') $$), 'REFUSED');
select CK('vendor cannot open a month',   AS_(U('ramesh'),   $$ select vs_open_month('2026-07-01') $$), 'REFUSED');
select CK('admin opens July: 3 created',  AS_(U('admin'),    $$ select vs_open_month('2026-07-01') $$), '3');
select CK('opening it again creates none',AS_(U('admin'),    $$ select vs_open_month('2026-07-01') $$), '0');
select CK('every head starts at zero',    (select coalesce(sum(amount),0)::text from vs_version_lines), '0.00');
select CK('every payroll starts pending', (select count(*)::text from vs_payroll where status='pending'), '3');
do $$ begin
  perform PUT('s1', (select id from vs_statements where contract_id=ID('c1')));
  perform PUT('s2', (select id from vs_statements where contract_id=ID('c2')));
  perform PUT('s3', (select id from vs_statements where contract_id=ID('c3')));
end $$;

-- ============================ 5. payroll gate =========================
select CK('manager types the gross and the running heads', DO_(U('manager'), format(
  $$ select vs_save_draft(%L::uuid, 2500000::numeric, 'per the duty sheet'::text,
     '{"rm":184500,"misc":12300,"maint_sp":46800,"fuel_adj":22150,"print":3400,"fuel":842000,"other":27500}'::jsonb,
     '[{"label":"Paid Through OP or Company Exp.","effect":"add","amount":310000,"reference":"","note":""},
       {"label":"Direct Payment to OP","effect":"deduct","amount":450000,"reference":"","note":""},
       {"label":"Advance Paid to Vendor","effect":"deduct","amount":150000,"reference":"UTR HDFC0X99112","note":"paid 18 Jul"},
       {"label":"Reimbursement to Vendor","effect":"add","amount":8500,"reference":"","note":"tyre bill approved late"},
       {"label":"Payment Made Against This Bill","effect":"note","amount":1000000,"reference":"UTR SBI0X7781","note":"recorded, not deducted"}]'::jsonb) $$,
  ID('s1'))), 'OK');
select CK('manager cannot type into a payroll head', DO_(U('manager'),
  format($$ select vs_save_draft(%L::uuid, null::numeric, null::text, '{"wages":999999}'::jsonb, null::jsonb) $$, ID('s1'))), 'OK');
select CK('...and that head is still zero',
  (select amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('s1') and l.head_key='wages'), '0.00');
select CK('sharing before payroll is refused', DO_(U('manager'),
  format($$ select vs_share(%L) $$, ID('s1'))), 'REFUSED');
-- The manager may post the payroll now, but the challan numbers are still
-- compulsory for him exactly as they are for Accounts.
select CK('the manager posting without a TRRN is refused too', AS_(U('manager'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":1,"dh_heads":1,"dh_pf_ee":0,"dh_pf_er":0,"dh_esic_ee":0,"dh_esic_er":0,
     "stf_pay":0,"stf_heads":0,"stf_pf_ee":0,"stf_pf_er":0,"stf_esic_ee":0,"stf_esic_er":0,
     "pf_trrn":"","esic_challan":"Y","not_processed_amount":0,"not_processed_reason":""}'::jsonb) $$, ID('s1'))), 'REFUSED');
select CK('...and without a reason for salary not processed', AS_(U('manager'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":1,"dh_heads":1,"dh_pf_ee":0,"dh_pf_er":0,"dh_esic_ee":0,"dh_esic_er":0,
     "stf_pay":0,"stf_heads":0,"stf_pf_ee":0,"stf_pf_er":0,"stf_esic_ee":0,"stf_esic_er":0,
     "pf_trrn":"X","esic_challan":"Y","not_processed_amount":5000,"not_processed_reason":""}'::jsonb) $$, ID('s1'))), 'REFUSED');
select CK('...and the payroll is still pending after those refusals',
  (select status from vs_payroll where statement_id=ID('s1')), 'pending');
select CK('accounts posting without a TRRN is refused', AS_(U('accounts'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":615000,"dh_heads":34,"dh_pf_ee":38400,"dh_pf_er":43800,"dh_esic_ee":4650,"dh_esic_er":15100,
     "stf_pay":195000,"stf_heads":6,"stf_pf_ee":12180,"stf_pf_er":14100,"stf_esic_ee":1470,"stf_esic_er":4500,
     "pf_trrn":"","esic_challan":"E1","not_processed_amount":112500,"not_processed_reason":"x"}'::jsonb) $$, ID('s1'))), 'REFUSED');
select CK('accounts posts the payroll', AS_(U('accounts'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":615000,"dh_heads":34,"dh_pf_ee":38400,"dh_pf_er":43800,"dh_esic_ee":4650,"dh_esic_er":15100,
     "stf_pay":195000,"stf_heads":6,"stf_pf_ee":12180,"stf_pf_er":14100,"stf_esic_ee":1470,"stf_esic_er":4500,
     "pf_trrn":"RJRAJ2608001192991","pf_paid_on":"2026-08-05","esic_challan":"ESIC/26/08/0052210","esic_paid_on":"2026-08-05",
     "processed_on":"2026-08-01","not_processed_amount":112500,"not_processed_reason":"two supervisors on the vendor roll"}'::jsonb) $$,
  ID('s1'))), 'posted');

create or replace function LINE(k text, vno int) returns text language sql stable as $$
  select amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
   where v.statement_id=ID('s1') and v.v=vno and l.head_key=k $$;
select CK('wages derived from the posting',            LINE('wages',1),    '615000.00');
select CK('employee part = PF EE + ESIC EE',           LINE('wages_ee',1), '43050.00');
select CK('employer part = PF ER + ESIC ER',           LINE('wages_er',1), '58900.00');
select CK('staff salary derived',                      LINE('salary',1),   '195000.00');
select CK('staff employee part derived',               LINE('staff_ee',1), '13650.00');
select CK('staff employer part derived',               LINE('staff_er',1), '18600.00');
select CK('expenses WeVois paid on his behalf',
  (select vs_version_heads(vs_current_version(ID('s1')))::text), '2082850.00');
select CK('Total = what he earned LESS what we spent for him',
  (select vs_version_total(vs_current_version(ID('s1')))::text), '417150.00');
select CK('adjustments net out (+310000 -450000 -150000 +8500 +112500)',
  (select vs_version_adj_total(vs_current_version(ID('s1')))::text), '-169000.00');
select CK('final payable = total + adjustments',
  (select vs_version_final(vs_current_version(ID('s1')))::text), '248150.00');
select CK('a note line is recorded but does not move the figure',
  (select (effect||':'||amount)::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s1') and a.label='Payment Made Against This Bill'), 'note:1000000.00');
select CK('the ledger holds six lines including the payroll one',
  (select count(*)::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s1')), '6');
select CK('salary not processed is credited BACK to him',
  (select effect from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s1') and a.payroll_linked), 'add');

-- ============================ 6. share freezes ========================
select CK('manager shares it', DO_(U('manager'), format($$ select vs_share(%L) $$, ID('s1'))), 'OK');
select CK('manager cannot edit the shared version', DO_(U('manager'),
  format($$ select vs_save_draft(%L::uuid, null::numeric, null::text, '{"rm":1}'::jsonb, null::jsonb) $$, ID('s1'))), 'REFUSED');
select CK('admin cannot edit it either', DO_(U('admin'),
  format($$ select vs_save_draft(%L::uuid, null::numeric, null::text, '{"rm":1}'::jsonb, null::jsonb) $$, ID('s1'))), 'REFUSED');
select CK('a direct UPDATE on the frozen line is refused', DO_(U('manager'),
  format($$ update vs_version_lines set amount = 1 where version_id = %L $$, vs_current_version(ID('s1')))), 'REFUSED');
select CK('...and the figure is intact', LINE('rm',1), '184500.00');
select CK('a direct INSERT of a fake payment is refused', DO_(U('accounts'),
  format($$ insert into vs_payments(statement_id,amount,paid_on,utr,recorded_by) values (%L,1,'2026-08-06','X','x') $$, ID('s1'))), 'REFUSED');

-- ============================ 7. vendor isolation =====================
select CK('Ramesh sees only his own shared statement', AS_(U('ramesh'), $$ select count(*) from vs_statements $$), '1');
select CK('Ramesh sees only his own vendor row',       AS_(U('ramesh'), $$ select count(*) from vs_vendors $$), '1');
select CK('his own draft is invisible to him',
  AS_(U('ramesh'), format($$ select count(*) from vs_statements where id=%L $$, ID('s2'))), '0');
select CK('Dinesh cannot see Ramesh statement',
  AS_(U('dinesh'), format($$ select count(*) from vs_statements where id=%L $$, ID('s1'))), '0');
select CK('Dinesh cannot pull it via the json call',
  AS_(U('dinesh'), format($$ select length(vs_statement_json(%L)::text) $$, ID('s1'))), 'REFUSED');
select CK('Dinesh cannot raise a point on it',
  AS_(U('dinesh'), format($$ select vs_raise_point(%L::uuid,'head','fuel','Fuel',9::numeric,'not mine','') $$, ID('s1'))), 'REFUSED');
select CK('Dinesh cannot approve it',
  AS_(U('dinesh'), format($$ select vs_approve(%L) $$, ID('s1'))), 'REFUSED');

-- ============================ 8. observers ============================
select CK('CEO reads every statement',  AS_(U('ceo'), $$ select count(*) from vs_statements $$), '3');
select CK('CEO reads the audit log',    AS_(U('ceo'), $$ select (count(*)>0)::text from vs_audit $$), 'true');
select CK('VP reads every statement',   AS_(U('vp'),  $$ select count(*) from vs_statements $$), '3');
select CK('CEO cannot share',    AS_(U('ceo'), format($$ select vs_share(%L) $$, ID('s2'))), 'REFUSED');
select CK('CEO cannot approve',  AS_(U('ceo'), format($$ select vs_approve(%L) $$, ID('s1'))), 'REFUSED');
select CK('CEO cannot pay',      AS_(U('ceo'), format($$ select vs_record_payment(%L::uuid,1::numeric,'2026-08-06'::date,'X','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('CEO cannot post payroll', AS_(U('ceo'), format($$ select vs_post_payroll(%L::uuid,'{}'::jsonb) $$, ID('s2'))), 'REFUSED');
select CK('CEO cannot delete',   AS_(U('ceo'), format($$ select vs_delete_statement(%L,'because') $$, ID('s2'))), 'REFUSED');
select CK('CEO cannot invite',   AS_(U('ceo'), $$ select vs_invite('x@y.com','X','admin',null) $$), 'REFUSED');
select CK('CEO cannot self-promote', AS_(U('ceo'), $$ select vs_set_role(U('ceo'),'admin') $$), 'REFUSED');
select CK('CEO direct UPDATE on his own row refused', DO_(U('ceo'),
  $$ update vs_profiles set role='admin' where id='44444444-4444-4444-4444-444444444444' $$), 'REFUSED');
select CK('CEO is still just the CEO', (select role from vs_profiles where id=U('ceo')), 'ceo');
select CK('VP cannot share either', AS_(U('vp'), format($$ select vs_share(%L) $$, ID('s2'))), 'REFUSED');

-- ============================ 9. points ===============================
do $$ begin
  perform PUT('adv', (select a.id from vs_version_adj a join vs_versions v on v.id=a.version_id
                       where v.statement_id=ID('s1') and a.label='Advance Paid to Vendor'));
end $$;
select CK('a point with no note is refused',
  AS_(U('ramesh'), format($$ select vs_raise_point(%L::uuid,'head','fuel','Fuel Exp.',1::numeric,'   ','') $$, ID('s1'))), 'REFUSED');
do $do$ begin
  perform PUT('pt1', AS_(U('ramesh'), format(
    $$ select vs_raise_point(%L::uuid,'head','fuel','Fuel Exp.',868500::numeric,'Diesel rate for 22-31 July is below the pump invoices.','pump.pdf') $$,
    ID('s1')))::uuid);
  perform PUT('pt2', AS_(U('ramesh'), format(
    $$ select vs_raise_point(%L::uuid,'adjustment',%L,'Advance Paid to Vendor',100000::numeric,'Advance was 1,00,000 not 1,50,000. Check the UTR.','') $$,
    ID('s1'), ID('adv')))::uuid);
end $do$;
select CK('vendor raised a point on a booking head',
  (select target_kind from vs_points where id=ID('pt1')), 'head');
select CK('vendor raised a point on an ADJUSTMENT line',
  (select target_kind from vs_points where id=ID('pt2')), 'adjustment');
select CK('statement moved to under query', (select status from vs_statements where id=ID('s1')), 'under_query');
select CK('approval is blocked while points are open',
  AS_(U('ramesh'), format($$ select vs_approve(%L) $$, ID('s1'))), 'REFUSED');
do $do$ begin
  perform PUT('pt3', AS_(U('manager'), format(
    $$ select vs_log_call_point(%L::uuid,'head','wages','Wages Exp. (Driver / Helper)',641000::numeric,'Said 4 helpers joined 19 July.') $$,
    ID('s1')))::uuid);
end $do$;
select CK('a phone point starts as awaiting confirmation',
  (select status from vs_points where id=ID('pt3')), 'awaiting_confirm');
select CK('another firm cannot confirm it',
  AS_(U('dinesh'), format($$ select vs_confirm_call_point(%L,true) $$, ID('pt3'))), 'REFUSED');
select CK('the right vendor confirms it',
  AS_(U('ramesh'), format($$ select vs_confirm_call_point(%L,true) $$, ID('pt3'))), '');
select CK('...and it goes live, timestamped',
  (select status||'/'||(confirmed_at is not null)::text from vs_points where id=ID('pt3')), 'open/true');
select CK('a decision with no reason is refused',
  AS_(U('manager'), format($$ select vs_resolve_point(%L::uuid,'accepted',868500::numeric,'  ') $$, ID('pt1'))), 'REFUSED');
select CK('accounts cannot resolve a point',
  AS_(U('accounts'), format($$ select vs_resolve_point(%L::uuid,'accepted',868500::numeric,'ok') $$, ID('pt1'))), 'REFUSED');
select CK('manager accepts the fuel point',
  AS_(U('manager'), format($$ select vs_resolve_point(%L::uuid,'accepted',868500::numeric,'Checked against pump invoices for 22-31 July. Rate applied was stale.') $$, ID('pt1'))), '');
select CK('manager accepts the advance point',
  AS_(U('manager'), format($$ select vs_resolve_point(%L::uuid,'accepted',100000::numeric,'Bank statement shows 1,00,000 on 18 July. Our entry was wrong.') $$, ID('pt2'))), '');
select CK('manager rejects the wages point',
  AS_(U('manager'), format($$ select vs_resolve_point(%L::uuid,'rejected',null::numeric,'Attendance shows those 4 joined 1 August.') $$, ID('pt3'))), '');

-- ============================ 10. revision ============================
do $$ begin perform PUT('v1final', null); end $$;
select CK('manager issues v2', AS_(U('manager'), format($$ select vs_issue_revision(%L) $$, ID('s1'))), '2');
select CK('v1 fuel untouched', LINE('fuel',1), '842000.00');
select CK('v2 fuel carries the accepted figure', LINE('fuel',2), '868500.00');
select CK('v1 advance untouched',
  (select amount::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s1') and v.v=1 and a.label='Advance Paid to Vendor'), '150000.00');
select CK('v2 advance corrected',
  (select amount::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s1') and v.v=2 and a.label='Advance Paid to Vendor'), '100000.00');
select CK('v2 final = v1 - 26500 more spent + 50000 advance back',
  (select vs_version_final((select id from vs_versions where statement_id=ID('s1') and v=2))::text), '271650.00');
select CK('the diff lists exactly the two accepted moves',
  (select jsonb_array_length(changes)::text from vs_versions where statement_id=ID('s1') and v=2), '2');
select CK('the rejected payroll point is not in the diff',
  (select (changes::text like '%Wages%')::text from vs_versions where statement_id=ID('s1') and v=2), 'false');
select CK('rejected point is still published to the vendor',
  (select published::text from vs_points where id=ID('pt3')), 'true');

-- ============================ 11. payroll correction ==================
select CK('accounts corrects staff salary after sharing', AS_(U('accounts'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":615000,"dh_heads":34,"dh_pf_ee":38400,"dh_pf_er":43800,"dh_esic_ee":4650,"dh_esic_er":15100,
     "stf_pay":201000,"stf_heads":6,"stf_pf_ee":12180,"stf_pf_er":14100,"stf_esic_ee":1470,"stf_esic_er":4500,
     "pf_trrn":"RJRAJ2608001192991","esic_challan":"ESIC/26/08/0052210","not_processed_amount":112500,
     "not_processed_reason":"two supervisors on the vendor roll"}'::jsonb) $$, ID('s1'))), 'parked');
select CK('the shared version still shows the old salary', LINE('salary',2), '195000.00');
select CK('the correction is parked, not applied',
  (select (pending_fix is not null)::text from vs_payroll where statement_id=ID('s1')), 'true');
select CK('manager issues v3', AS_(U('manager'), format($$ select vs_issue_revision(%L) $$, ID('s1'))), '3');
select CK('v3 carries the corrected salary', LINE('salary',3), '201000.00');
select CK('the parked correction is cleared',
  (select (pending_fix is null)::text from vs_payroll where statement_id=ID('s1')), 'true');
select CK('v3 final is v2 less the 6000 extra salary',
  (select vs_version_final((select id from vs_versions where statement_id=ID('s1') and v=3))::text), '265650.00');

-- ============================ 12. approval, part payments =============
select CK('manager cannot approve on the vendor behalf',
  AS_(U('manager'), format($$ select vs_approve(%L) $$, ID('s1'))), 'REFUSED');
select CK('vendor approves, and the amount is returned',
  AS_(U('ramesh'), format($$ select vs_approve(%L) $$, ID('s1'))), '265650.00');
select CK('snapshot records status, who and which version',
  (select status||'/'||approved_by||'/v'||approved_version from vs_statements where id=ID('s1')),
  'approved/Ramesh Chand/v3');
-- The vendor manager can pay too, including a month that closed long ago.
-- Everything that actually protects the money is untouched: it must be
-- approved first, it needs a UTR, and it can never exceed what was approved.
select CK('manager can pay, and can date it to a month gone by',
  AS_(U('manager'), format($$ select vs_record_payment(%L::uuid,50000::numeric,'2026-05-04'::date,'HDFC0BACK','NEFT','paid in May, entered now') $$, ID('s1'))),
  '215650.00');
select CK('...and the payment keeps the date the money moved, not today',
  (select paid_on::text from vs_payments where statement_id=ID('s1') and utr='HDFC0BACK'), '2026-05-04');
select CK('...recorded against the manager by name',
  (select recorded_by from vs_payments where statement_id=ID('s1') and utr='HDFC0BACK'), 'Himanshu Yadav');
select CK('manager still cannot pay without a UTR',
  AS_(U('manager'), format($$ select vs_record_payment(%L::uuid,1000::numeric,'2026-08-06'::date,'','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('manager still cannot pay above the approved amount',
  AS_(U('manager'), format($$ select vs_record_payment(%L::uuid,99999999::numeric,'2026-08-06'::date,'X9','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('CEO cannot pay',
  AS_(U('ceo'), format($$ select vs_record_payment(%L::uuid,1000::numeric,'2026-08-06'::date,'X','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('VP cannot pay',
  AS_(U('vp'), format($$ select vs_record_payment(%L::uuid,1000::numeric,'2026-08-06'::date,'X','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('the vendor cannot pay himself',
  AS_(U('ramesh'), format($$ select vs_record_payment(%L::uuid,1000::numeric,'2026-08-06'::date,'X','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('payment without a UTR refused',
  AS_(U('accounts'), format($$ select vs_record_payment(%L::uuid,1000::numeric,'2026-08-06'::date,'','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('paying more than approved refused',
  AS_(U('accounts'), format($$ select vs_record_payment(%L::uuid,99999999::numeric,'2026-08-06'::date,'X1','NEFT','') $$, ID('s1'))), 'REFUSED');
select CK('first part payment leaves a balance',
  AS_(U('accounts'), format($$ select vs_record_payment(%L::uuid,100000::numeric,'2026-08-06'::date,'SBIN0X111','NEFT','first tranche') $$, ID('s1'))),
  '115650.00');
select CK('status becomes part paid', (select status from vs_statements where id=ID('s1')), 'part_paid');
select CK('second part payment clears it',
  AS_(U('accounts'), format($$ select vs_record_payment(%L::uuid,115650::numeric,'2026-08-20'::date,'SBIN0X222','NEFT','balance') $$, ID('s1'))),
  '0.00');
select CK('status becomes paid', (select status from vs_statements where id=ID('s1')), 'paid');
select CK('all three payments are on record',
  (select count(*)||':'||string_agg(utr,'+' order by utr) from vs_payments where statement_id=ID('s1')),
  '3:HDFC0BACK+SBIN0X111+SBIN0X222');
select CK('vendor can see the UTRs',
  AS_(U('ramesh'), format($$ select count(*) from vs_payments where statement_id=%L $$, ID('s1'))), '3');

-- =================== 12b. payroll / PF / ESIC files ===================
-- The vendor never gets to attach anything; he only gets to open what was
-- attached to a statement he can already see. The table itself is read-only
-- to every role, so the only way a row appears is through the function.
select CK('nobody can insert a document row directly - not even admin',
  DO_(U('admin'), format($$ insert into vs_documents (statement_id,path,filename,uploaded_by)
       values (%L,'x/y.pdf','y.pdf','me') $$, ID('s1'))), 'REFUSED');
select CK('the manager attaches the payroll sheet',
  AS_(U('manager'), format($$ select (vs_add_document(%L::uuid, %L, 'April payroll.xlsx','payroll',
       'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 20480) is not null)::text $$,
       ID('s1'), ID('s1')::text||'/a1-April payroll.xlsx')), 'true');
select CK('accounts attaches the ESIC challan',
  AS_(U('accounts'), format($$ select (vs_add_document(%L::uuid, %L, 'ESIC challan.pdf','esic',
       'application/pdf', 8100) is not null)::text $$,
       ID('s1'), ID('s1')::text||'/a2-ESIC challan.pdf')), 'true');
select CK('CEO cannot attach one',
  AS_(U('ceo'), format($$ select vs_add_document(%L::uuid,'p','f.pdf','other','',1)::text $$, ID('s1'))), 'REFUSED');
select CK('VP cannot attach one',
  AS_(U('vp'), format($$ select vs_add_document(%L::uuid,'p','f.pdf','other','',1)::text $$, ID('s1'))), 'REFUSED');
-- The vendor may attach to his OWN statement now - that is the point of it -
-- but to nobody else's, and he can take back only what he put up himself.
select CK('the vendor CAN attach to his own statement now',
  AS_(U('ramesh'), format($$ select (vs_add_document(%L::uuid, %L, 'workshop bill 4417.pdf','bill','application/pdf', 4400) is not null)::text $$,
      ID('s1'), ID('s1')::text||'/v1-workshop bill 4417.pdf')), 'true');
select CK('...and it is recorded against him by name',
  (select uploaded_by from vs_documents where filename='workshop bill 4417.pdf'), 'Ramesh Chand');
select CK('...but not to another vendor''s statement',
  AS_(U('dinesh'), format($$ select vs_add_document(%L::uuid,'p','f.pdf','other','',1)::text $$, ID('s1'))), 'REFUSED');
select CK('...and an uninvited account still cannot',
  AS_(U('stranger'), format($$ select vs_add_document(%L::uuid,'p','f.pdf','other','',1)::text $$, ID('s1'))), 'REFUSED');
select CK('a file with no name is refused',
  AS_(U('manager'), format($$ select vs_add_document(%L::uuid,'p','   ','other','',1)::text $$, ID('s1'))), 'REFUSED');
select CK('three files are on the statement',
  (select count(*)::text from vs_documents where statement_id=ID('s1')), '3');
select CK('each records who attached it',
  (select string_agg(distinct uploaded_by,'+' order by uploaded_by) from vs_documents where statement_id=ID('s1')),
  'Himanshu Yadav+Rakesh Gupta+Ramesh Chand');
select CK('and the record says so',
  (select count(*)::text from vs_events where statement_id=ID('s1')
    and title like 'Document attached%'), '3');
select CK('the vendor can read the documents on his own statement',
  AS_(U('ramesh'), format($$ select count(*) from vs_documents where statement_id=%L $$, ID('s1'))), '3');
select CK('a different vendor reads none of them',
  AS_(U('dinesh'), format($$ select count(*) from vs_documents where statement_id=%L $$, ID('s1'))), '0');
select CK('somebody with no invite reads none of them',
  AS_(U('stranger'), $$ select count(*) from vs_documents $$), '0');
select CK('CEO reads them',
  AS_(U('ceo'), format($$ select count(*) from vs_documents where statement_id=%L $$, ID('s1'))), '3');
select CK('...but the CEO cannot attach one',
  AS_(U('ceo'), format($$ select vs_add_document(%L::uuid,'p','f.pdf','other','',1)::text $$, ID('s1'))), 'REFUSED');
select CK('...nor the VP',
  AS_(U('vp'), format($$ select vs_add_document(%L::uuid,'p','f.pdf','other','',1)::text $$, ID('s1'))), 'REFUSED');
select CK('nobody can update a document row directly',
  DO_(U('admin'), $$ update vs_documents set filename='x' $$), 'REFUSED');
select CK('nobody can delete a document row directly',
  DO_(U('accounts'), $$ delete from vs_documents $$), 'REFUSED');
select CK('the vendor cannot remove a file the manager attached',
  AS_(U('ramesh'), format($$ select vs_remove_document(
       (select id from vs_documents where statement_id=%L order by uploaded_at limit 1),'x') $$, ID('s1'))), 'REFUSED');
select CK('...but he can take back his own, with a reason',
  AS_(U('ramesh'), $$ select (vs_remove_document(
       (select id from vs_documents where filename='workshop bill 4417.pdf'),
       'wrong bill, sending the right one') is not null)::text $$), 'true');
select CK('...he puts a second one up',
  AS_(U('ramesh'), format($$ select (vs_add_document(%L::uuid, %L, 'again.pdf','bill','application/pdf',10) is not null)::text $$,
      ID('s1'), ID('s1')::text||'/v2-again.pdf')), 'true');
select CK('...and removing it without a reason is refused',
  AS_(U('ramesh'), $$ select vs_remove_document(
       (select id from vs_documents where filename='again.pdf'),'  ') $$), 'REFUSED');
select CK('removing one without a reason is refused',
  AS_(U('manager'), format($$ select vs_remove_document(
       (select id from vs_documents where statement_id=%L order by uploaded_at limit 1),'   ') $$, ID('s1'))), 'REFUSED');
select CK('with a reason it comes off, and the path comes back so the file can follow',
  AS_(U('manager'), format($$ select (vs_remove_document(
       (select id from vs_documents where statement_id=%L and filename='April payroll.xlsx'),
       'wrong month attached by mistake') like %L)::text $$, ID('s1'), '%April payroll.xlsx')), 'true');
-- four went up (manager, accounts, and two from the vendor), two came off
select CK('two files left of the four that went up',
  (select count(*)::text from vs_documents where statement_id=ID('s1')), '2');
select CK('both removals are in the record forever, with their reasons',
  (select count(*)::text from vs_events
    where statement_id=ID('s1') and title like 'Document removed%'), '2');
select CK('...and the manager''s reason is one of them',
  (select (count(*)=1)::text from vs_events
    where statement_id=ID('s1') and title like 'Document removed%' and body like '%wrong month%'), 'true');
select CK('...and the vendor''s is the other',
  (select (count(*)=1)::text from vs_events
    where statement_id=ID('s1') and title like 'Document removed%' and body like '%wrong bill%'), 'true');

-- ============ 12c. a vendor sees only HIS sites and HIS months ========
-- Every reader below is SECURITY DEFINER, so row-level security does not apply
-- inside it and each one has to ask who is calling for itself. s1 is Ramesh's,
-- shared, approved and paid; s3 is Dinesh's. Dinesh is pointed straight at
-- s1 with the real ids and must come away with nothing.
do $do$ begin
  perform PUT('v1', (select id from vs_versions where statement_id=ID('s1') order by v desc limit 1));
end $do$;
select CK('the target is a real month with real money',
  (select 'v'||v||'/lines '||(select count(*) from vs_version_lines l where l.version_id=ID('v1'))
     from vs_versions where id=ID('v1')), 'v3/lines 13');

-- what the home screen actually calls
-- Ramesh runs two sites but only Kota Zone 2 has been shared with him; Kota
-- Zone 5 is still a draft and Bhilwara is Dinesh's. Before this was fixed the
-- same call handed him all three, with the other vendor's name and figures.
select CK('the list gives Ramesh only the site he has been sent',
  AS_(U('ramesh'), $$ select string_agg(distinct x->>'site_name', ', ')
       from jsonb_array_elements(vs_list_statements(null)) x $$), 'Kota Zone 2');
select CK('...one statement, not three',
  AS_(U('ramesh'), $$ select jsonb_array_length(vs_list_statements(null))::text $$), '1');
select CK('...and his own draft is not in it either',
  AS_(U('ramesh'), $$ select coalesce((select 'leaked' from jsonb_array_elements(vs_list_statements(null)) x
       where x->>'site_name'='Kota Zone 5' limit 1),'hidden') $$), 'hidden');
select CK('the list gives Dinesh nothing, his own being still a draft',
  AS_(U('dinesh'), $$ select jsonb_array_length(vs_list_statements(null))::text $$), '0');
select CK('the list never names another vendor to a vendor',
  AS_(U('ramesh'), $$ select coalesce(string_agg(distinct x->>'vendor_name', ', '),'(none)')
       from jsonb_array_elements(vs_list_statements(null)) x $$), 'Ramesh Transport & Co.');
select CK('the manager still gets all three', 
  AS_(U('manager'), $$ select jsonb_array_length(vs_list_statements(null))::text $$), '3');
select CK('the CEO still gets all three',
  AS_(U('ceo'), $$ select jsonb_array_length(vs_list_statements(null))::text $$), '3');
select CK('the admin still gets all three',
  AS_(U('admin'), $$ select jsonb_array_length(vs_list_statements(null))::text $$), '3');
select CK('an uninvited account gets an empty list',
  AS_(U('stranger'), $$ select jsonb_array_length(vs_list_statements(null))::text $$), '0');

-- the tables themselves
select CK('Ramesh reads only the two sites he runs',
  AS_(U('ramesh'), $$ select string_agg(name,', ' order by name) from vs_sites $$), 'Kota Zone 2, Kota Zone 5');
select CK('Dinesh reads only his one',
  AS_(U('dinesh'), $$ select string_agg(name,', ' order by name) from vs_sites $$), 'Bhilwara');
select CK('Ramesh reads only his own vendor row',
  AS_(U('ramesh'), $$ select string_agg(name,', ') from vs_vendors $$), 'Ramesh Transport & Co.');
select CK('Ramesh reads only his own two contracts',
  AS_(U('ramesh'), $$ select count(*) from vs_contracts $$), '2');
select CK('Ramesh reads booking heads for his sites only',
  AS_(U('ramesh'), format($$ select count(*) from vs_heads where site_id=%L $$, ID('sc'))), '0');
select CK('...and does read them for a site he runs',
  AS_(U('ramesh'), format($$ select (count(*)>0)::text from vs_heads where site_id=%L $$, ID('sa'))), 'true');

-- every SECURITY DEFINER helper, pointed at Ramesh's month by Dinesh
select CK('vs_current_version refuses another vendor',
  AS_(U('dinesh'), format($$ select coalesce(vs_current_version(%L)::text,'(nothing)') $$, ID('s1'))), '(nothing)');
select CK('vs_version_heads refuses another vendor',
  AS_(U('dinesh'), format($$ select coalesce(vs_version_heads(%L)::text,'(nothing)') $$, ID('v1'))), '(nothing)');
select CK('vs_version_total refuses another vendor',
  AS_(U('dinesh'), format($$ select coalesce(vs_version_total(%L)::text,'(nothing)') $$, ID('v1'))), '(nothing)');
select CK('vs_version_adj_total refuses another vendor',
  AS_(U('dinesh'), format($$ select coalesce(vs_version_adj_total(%L)::text,'(nothing)') $$, ID('v1'))), '(nothing)');
select CK('vs_version_final refuses another vendor',
  AS_(U('dinesh'), format($$ select coalesce(vs_version_final(%L)::text,'(nothing)') $$, ID('v1'))), '(nothing)');
select CK('vs_paid_total refuses another vendor',
  AS_(U('dinesh'), format($$ select coalesce(vs_paid_total(%L)::text,'(nothing)') $$, ID('s1'))), '(nothing)');
select CK('vs_contract_at refuses a site he does not run',
  AS_(U('dinesh'), format($$ select coalesce(vs_contract_at(%L,'2026-07-15'::date)::text,'(nothing)') $$, ID('sa'))), '(nothing)');
select CK('vs_site_history refuses a site he does not run',
  AS_(U('dinesh'), format($$ select vs_site_history(%L)::text $$, ID('sa'))), '[]');
select CK('vs_payroll_diff refuses another vendor',
  AS_(U('dinesh'), format($$ select vs_payroll_diff(%L,%L)::text $$, ID('s1'), ID('v1'))), 'REFUSED');
select CK('vs_statement_json refuses another vendor',
  AS_(U('dinesh'), format($$ select vs_statement_json(%L)::text $$, ID('s1'))), 'REFUSED');
select CK('an uninvited account is refused the same way',
  AS_(U('stranger'), format($$ select coalesce(vs_version_final(%L)::text,'(nothing)') $$, ID('v1'))), '(nothing)');

-- and none of that broke the people who are entitled to it
select CK('the owner still gets his own figure',
  AS_(U('ramesh'), format($$ select vs_version_final(%L)::text $$, ID('v1'))), '265650.00');
select CK('the owner still gets his own paid total',
  AS_(U('ramesh'), format($$ select vs_paid_total(%L)::text $$, ID('s1'))), '265650.00');
select CK('accounts still gets it',
  AS_(U('accounts'), format($$ select vs_version_final(%L)::text $$, ID('v1'))), '265650.00');
select CK('the CEO still gets it',
  AS_(U('ceo'), format($$ select vs_version_final(%L)::text $$, ID('v1'))), '265650.00');
select CK('the admin still reads the whole site history',
  AS_(U('admin'), format($$ select jsonb_array_length(vs_site_history(%L))::text $$, ID('sa'))), '1');
select CK('and the owner reads his own stretch of it',
  AS_(U('ramesh'), format($$ select jsonb_array_length(vs_site_history(%L))::text $$, ID('sa'))), '1');

-- ============================ 13. delete ==============================
select CK('manager cannot delete',  AS_(U('manager'),  format($$ select vs_delete_statement(%L,'no') $$, ID('s1'))), 'REFUSED');
select CK('accounts cannot delete', AS_(U('accounts'), format($$ select vs_delete_statement(%L,'no') $$, ID('s1'))), 'REFUSED');
select CK('vendor cannot delete',   AS_(U('ramesh'),   format($$ select vs_delete_statement(%L,'no') $$, ID('s1'))), 'REFUSED');
select CK('admin deleting with no reason is refused',
  AS_(U('admin'), format($$ select vs_delete_statement(%L,'   ') $$, ID('s1'))), 'REFUSED');
select CK('admin deletes a PAID settlement',
  AS_(U('admin'), format($$ select vs_delete_statement(%L,'raised against the wrong month') $$, ID('s1'))), '');
select CK('the statement is gone',   (select count(*)::text from vs_statements where id=ID('s1')), '0');
select CK('its points went with it', (select count(*)::text from vs_points where statement_id=ID('s1')), '0');
select CK('its payments went too',   (select count(*)::text from vs_payments where statement_id=ID('s1')), '0');
select CK('the tombstone survives',
  (select (count(*)=1)::text from vs_audit where title='Settlement DELETED'), 'true');
select CK('tombstone names who, why and the UTRs',
  (select ((actor_name='Priya Nair') and body like '%wrong month%' and body like '%SBIN0X111%'
           and body like '%status paid%')::text from vs_audit where title='Settlement DELETED'), 'true');
select CK('nobody can delete an audit row',  DO_(U('admin'), $$ delete from vs_audit $$), 'REFUSED');
select CK('nobody can edit an audit row',    DO_(U('admin'), $$ update vs_audit set body='' $$), 'REFUSED');

-- ============================ 14. guards ==============================
select CK('a contract with settlements cannot be unassigned',
  AS_(U('admin'), format($$ select vs_remove_contract(%L) $$, ID('c2'))), 'REFUSED');
select CK('a contract with none left can be',
  AS_(U('admin'), format($$ select vs_remove_contract(%L) $$, ID('c1'))), '');
select CK('the last admin cannot be demoted',
  AS_(U('admin'), $$ select vs_set_role(U('admin'),'manager') $$), 'REFUSED');
select CK('the last admin cannot be deactivated',
  AS_(U('admin'), $$ select vs_set_active(U('admin'), false) $$), 'REFUSED');
select CK('still an active admin',
  (select role||'/'||active::text from vs_profiles where id=U('admin')), 'admin/true');
select CK('a duplicate settlement for the same site and month is refused',
  AS_(U('admin'), format($$ select vs_add_statement(%L::uuid,'2026-07-01'::date) $$, ID('c3'))), 'REFUSED');
select CK('a different month is allowed',
  AS_(U('admin'), format($$ select (vs_add_statement(%L::uuid,'2026-08-01'::date) is not null) $$, ID('c3'))), 'true');
select CK('a zero-vehicle contract is refused',
  AS_(U('admin'), format($$ select vs_add_contract(%L::uuid,%L::uuid,0,'2026-09-01'::date) $$, ID('mahaveer'), ID('sa'))), 'REFUSED');

-- ============ 14b. the admin edits a site and its tenures ============
-- Until this patch a site could not be renamed at all, and a tenure's START
-- date could never be corrected - the only way out was to delete the tenure,
-- which is itself refused once a settlement exists under it. Both are editable
-- now, and every edit that would corrupt something is refused with the reason.
--
-- State on arrival: Kota Zone 2 has nothing on it, Kota Zone 5 is Ramesh's
-- (from 01 Apr 2025, open ended, 9 vehicles, one draft for July 2026), and
-- Bhilwara is Mahaveer's, open ended, with two drafts.

-- ---- renaming
select CK('a site can be renamed at last',
  AS_(U('admin'), format($$ select vs_set_site(%L,'Kota Zone Two','Kota',null,null) $$, ID('sa'))),
  'renamed from Kota Zone 2 to Kota Zone Two');
select CK('...and that is what the table holds',
  (select name||' / '||city from vs_sites where id=ID('sa')), 'Kota Zone Two / Kota');
select CK('renaming onto another site is refused',
  AS_(U('admin'), format($$ select vs_set_site(%L,'Bhilwara','',null,null) $$, ID('sa'))), 'REFUSED');
select CK('saving the same values changes nothing and says so',
  AS_(U('admin'), format($$ select vs_set_site(%L,'Kota Zone Two','Kota',null,null) $$, ID('sa'))), 'nothing changed');

-- ---- a site gets a life of its own
select CK('a site with nothing on it can be dated freely',
  AS_(U('admin'), format($$ select vs_set_site(%L,null,null,'2026-01-01'::date,null) $$, ID('sa'))),
  'started (not set) -> 01 Jan 2026');
select CK('and closed',
  AS_(U('admin'), format($$ select vs_set_site(%L,null,null,'2026-01-01'::date,'2026-06-30'::date) $$, ID('sa'))),
  'closed (still running) -> 30 Jun 2026');
select CK('it reads as closed',
  (select vs_site_status(id)||'/'||active::text from vs_sites where id=ID('sa')), 'closed/false');
select CK('a vendor cannot be assigned past the closing date',
  AS_(U('admin'), format($$ select vs_add_contract(%L,%L,5,'2026-03-01'::date,null) $$, ID('mahaveer'), ID('sa'))), 'REFUSED');
select CK('nor started before the site opens',
  AS_(U('admin'), format($$ select vs_add_contract(%L,%L,5,'2025-01-01'::date,'2026-06-30'::date) $$, ID('mahaveer'), ID('sa'))), 'REFUSED');
select CK('but inside the window it is fine',
  AS_(U('admin'), format($$ select (vs_add_contract(%L,%L,5,'2026-02-01'::date,'2026-06-30'::date) is not null)::text $$,
      ID('mahaveer'), ID('sa'))), 'true');
select CK('a month outside the site life is refused',
  AS_(U('admin'), format($$ select vs_add_statement(
      (select id from vs_contracts where site_id=%L limit 1),'2026-09-01'::date) $$, ID('sa'))), 'REFUSED');
select CK('a month inside it opens',
  AS_(U('admin'), format($$ select (vs_add_statement(
      (select id from vs_contracts where site_id=%L limit 1),'2026-03-01'::date) is not null)::text $$, ID('sa'))), 'true');
select CK('opening a whole month skips the closed site',
  AS_(U('admin'), $$ select (vs_open_month('2026-11-01') >= 0)::text $$), 'true');
select CK('...it got no November settlement',
  (select count(*)::text from vs_statements st join vs_contracts c on c.id=st.contract_id
    where c.site_id=ID('sa') and st.period='2026-11-01'), '0');
select CK('...while the sites still running did',
  (select (count(*) > 0)::text from vs_statements st join vs_contracts c on c.id=st.contract_id
    where c.site_id=ID('sb') and st.period='2026-11-01'), 'true');

-- ---- the tenure start date, which could never be touched before
select CK('a tenure start date can now be moved',
  AS_(U('admin'), format($$ select vs_set_contract(%L,null,'2025-05-01'::date,null) $$, ID('c2'))),
  'start 01 Apr 2025 -> 01 May 2025');
select CK('...but not past a settlement already raised under it',
  AS_(U('admin'), format($$ select vs_set_contract(%L,null,'2026-08-01'::date,null) $$, ID('c2'))), 'REFUSED');
select CK('...and the tenure is untouched by the refusal',
  (select to_char(from_date,'DD Mon YYYY') from vs_contracts where id=ID('c2')), '01 May 2025');
select CK('an end before the start is refused',
  AS_(U('admin'), format($$ select vs_set_contract(%L,null,'2025-05-01'::date,'2025-01-01'::date) $$, ID('c2'))), 'REFUSED');
select CK('zero vehicles is refused',
  AS_(U('admin'), format($$ select vs_set_contract(%L,0,null,null) $$, ID('c2'))), 'REFUSED');
select CK('the vehicle count moves cleanly',
  AS_(U('admin'), format($$ select vs_set_contract(%L,22,null,null) $$, ID('c2'))), 'vehicles 9 -> 22');
select CK('...and it took', (select vehicles::text from vs_contracts where id=ID('c2')), '22');
select CK('dating the site, a tenure cannot start before it',
  AS_(U('admin'), format($$ select vs_set_site(%L,null,null,'2025-05-01'::date,null) $$, ID('sb'))),
  'started (not set) -> 01 May 2025');
select CK('...so an earlier tenure start is now refused',
  AS_(U('admin'), format($$ select vs_set_contract(%L,null,'2024-01-01'::date,null) $$, ID('c2'))), 'REFUSED');
select CK('closing a site while a vendor still runs it is refused',
  AS_(U('admin'), format($$ select vs_set_site(%L,null,null,'2025-05-01'::date,'2026-12-31'::date) $$, ID('sb'))), 'REFUSED');
select CK('the same at Bhilwara',
  AS_(U('admin'), format($$ select vs_set_site(%L,null,null,null,'2026-12-31'::date) $$, ID('sc'))), 'REFUSED');

-- ---- ending, a successor, and reopening
select CK('ending a tenure',
  AS_(U('admin'), format($$ select vs_end_contract(%L,'2026-11-30'::date) $$, ID('c2'))), '');
select CK('...it now carries an end date',
  (select to_char(to_date,'DD Mon YYYY') from vs_contracts where id=ID('c2')), '30 Nov 2026');
select CK('a successor takes the site on',
  AS_(U('admin'), format($$ select (vs_add_contract(%L,%L,4,'2026-12-01'::date,null) is not null)::text $$,
      ID('mahaveer'), ID('sb'))), 'true');
select CK('the old tenure cannot now be stretched over the new one',
  AS_(U('admin'), format($$ select vs_set_contract(%L,null,null,'2026-12-31'::date) $$, ID('c2'))), 'REFUSED');
select CK('nor reopened underneath it',
  AS_(U('admin'), format($$ select vs_reopen_contract(%L) $$, ID('c2'))), 'REFUSED');
select CK('remove the successor',
  AS_(U('admin'), format($$ select vs_remove_contract(
      (select id from vs_contracts where site_id=%L and from_date='2026-12-01')) $$, ID('sb'))), '');
select CK('...now it reopens',
  AS_(U('admin'), format($$ select vs_reopen_contract(%L) $$, ID('c2'))), '');
select CK('...back to open ended',
  (select coalesce(to_char(to_date,'DD Mon YYYY'),'(open)') from vs_contracts where id=ID('c2')), '(open)');
select CK('reopening one that is already open is refused',
  AS_(U('admin'), format($$ select vs_reopen_contract(%L) $$, ID('c2'))), 'REFUSED');

-- ---- who may do any of this
select CK('the manager cannot edit a site',
  AS_(U('manager'), format($$ select vs_set_site(%L,'Hack','',null,null) $$, ID('sb'))), 'REFUSED');
select CK('the manager cannot edit a tenure',
  AS_(U('manager'), format($$ select vs_set_contract(%L,99,null,null) $$, ID('c2'))), 'REFUSED');
select CK('accounts cannot either',
  AS_(U('accounts'), format($$ select vs_set_site(%L,'Hack','',null,null) $$, ID('sb'))), 'REFUSED');
select CK('the CEO cannot reopen a tenure',
  AS_(U('ceo'), format($$ select vs_reopen_contract(%L) $$, ID('c2'))), 'REFUSED');
select CK('nor can the vendor touch his own tenure',
  AS_(U('ramesh'), format($$ select vs_set_contract(%L,99,null,null) $$, ID('c2'))), 'REFUSED');
select CK('nobody can move a site by direct SQL',
  DO_(U('admin'), $$ update vs_sites set name='Hacked' $$), 'REFUSED');
select CK('nor a tenure',
  DO_(U('admin'), $$ update vs_contracts set from_date='2020-01-01' $$), 'REFUSED');
select CK('nothing moved',
  (select (count(*)=0)::text from vs_sites where name='Hacked'), 'true');
select CK('and every change is in the audit log',
  (select (count(*) >= 6)::text from vs_audit
    where title in ('Site changed','Tenure changed','Tenure ended','Tenure reopened')), 'true');

-- ============================ 16. THE NAWA HANDOVER ===================
-- Heera Ram ji ran Nawa until 15 April 2026; Firoz took over on the 16th.
do $$ begin
  perform set_config('request.jwt.claim.sub', U('admin')::text, false);
  perform PUT('heera', vs_add_vendor('Heera Ram ji','OP-HR','Heera Ram','heera@op.in','98111'));
  perform PUT('firoz', vs_add_vendor('Firoz','OP-FZ','Firoz Khan','firoz@op.in','98222'));
  perform PUT('nawa',  vs_add_site('Nawa','Nawa'));
  perform PUT('nc1',   vs_add_contract(ID('heera'), ID('nawa'), 6, '2024-12-01'));
end $$;
select CK('a second vendor cannot overlap the same site',
  AS_(U('admin'), format($$ select vs_add_contract(%L::uuid,%L::uuid,6,'2026-01-01'::date) $$, ID('firoz'), ID('nawa'))), 'REFUSED');
select CK('the handover splits the tenure on the exact day',
  AS_(U('admin'), format($$ select (vs_change_vendor(%L::uuid,%L::uuid,6,'2026-04-16'::date) is not null) $$, ID('nawa'), ID('firoz'))), 'true');
select CK('Heera Ram ends 15 April',
  (select to_char(to_date,'YYYY-MM-DD') from vs_contracts where id=ID('nc1')), '2026-04-15');
select CK('Firoz starts 16 April',
  (select to_char(from_date,'YYYY-MM-DD') from vs_contracts where site_id=ID('nawa') and to_date is null), '2026-04-16');
select CK('opening April is allowed for every running contract',
  AS_(U('admin'), $$ select (vs_open_month('2026-04-01') > 0)::text $$), 'true');
select CK('...and Nawa alone gets TWO, one per vendor',
  (select count(*)::text from vs_statements s join vs_contracts c on c.id=s.contract_id
    where c.site_id=ID('nawa') and s.period='2026-04-01'), '2');
select CK('...one per vendor',
  (select count(distinct c.vendor_id)::text from vs_statements s join vs_contracts c on c.id=s.contract_id
    where c.site_id=ID('nawa') and s.period='2026-04-01'), '2');
select CK('the outgoing vendor is settled for 1-15 April',
  (select to_char(s.covers_from,'DD Mon')||' to '||to_char(s.covers_to,'DD Mon')
     from vs_statements s join vs_contracts c on c.id=s.contract_id
    where c.id=ID('nc1') and s.period='2026-04-01'), '01 Apr to 15 Apr');
select CK('the incoming vendor is settled for 16-30 April',
  (select to_char(s.covers_from,'DD Mon')||' to '||to_char(s.covers_to,'DD Mon')
     from vs_statements s join vs_contracts c on c.id=s.contract_id
    where c.site_id=ID('nawa') and c.to_date is null and s.period='2026-04-01'), '16 Apr to 30 Apr');
select CK('opening May gives Nawa only ONE',
  AS_(U('admin'), $$ select (vs_open_month('2026-05-01') > 0)::text $$), 'true');
select CK('...just one Nawa settlement in May',
  (select count(*)::text from vs_statements s join vs_contracts c on c.id=s.contract_id
    where c.site_id=ID('nawa') and s.period='2026-05-01'), '1');
select CK('...and it belongs to Firoz',
  (select v.name from vs_statements s join vs_contracts c on c.id=s.contract_id
     join vs_vendors v on v.id=c.vendor_id where c.site_id=ID('nawa') and s.period='2026-05-01'), 'Firoz');
select CK('March still belongs entirely to Heera Ram',
  AS_(U('admin'), format($$ select (vs_add_statement(%L::uuid,'2026-03-01'::date) is not null) $$, ID('nc1'))), 'true');
select CK('a settlement outside a tenure is refused',
  AS_(U('admin'), format($$ select vs_add_statement(%L::uuid,'2026-08-01'::date) $$, ID('nc1'))), 'REFUSED');
select CK('the site history reads as a chain of tenures',
  (select string_agg(x->>'vendor_name' || ' ' || (x->>'from_label') || '-' || (x->>'to_label'), ' | ' order by x->>'from_date')
     from jsonb_array_elements(vs_site_history(ID('nawa'))) x),
  'Heera Ram ji 01 Dec 2024-15 Apr 2026 | Firoz 16 Apr 2026-current');
select CK('heads at a new site can differ from the template',
  AS_(U('admin'), format($$ select (vs_add_head(%L::uuid,'garage_rent','Nawa Garage Rent','run','manual',140) is not null) $$, ID('nawa'))), 'true');
select CK('...and the new site now has 14 heads',
  (select count(*)::text from vs_heads where site_id=ID('nawa')), '14');

-- ============ 17. the vendor manager posts the payroll himself =========
-- Accounts used to be the only role that could, and the statement could not go
-- out until they had. The manager can satisfy that gate himself now. Built on
-- a site of its own so nothing earlier in this file depends on it.
do $do$
begin
  perform set_config('request.jwt.claim.sub', U('admin')::text, false);
  perform PUT('pv', vs_add_vendor('Payroll Test Partner','OP-77','X','x@pt.in','90000'));
  perform PUT('ps', vs_add_site('Payroll Test Site','Kota'));
  perform PUT('pc', vs_add_contract(ID('pv'), ID('ps'), 12, '2026-08-01'));
  perform PUT('pst', vs_add_statement(ID('pc'), '2026-08-01'));
end $do$;
select CK('a fresh draft starts with the payroll pending',
  (select status from vs_payroll where statement_id=ID('pst')), 'pending');
select CK('the manager cannot share it yet',
  DO_(U('manager'), format($$ select vs_share(%L) $$, ID('pst'))), 'REFUSED');
select CK('the manager posts the payroll himself', AS_(U('manager'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":220000,"dh_heads":12,"dh_pf_ee":13200,"dh_pf_er":15000,"dh_esic_ee":1650,"dh_esic_er":5200,
     "stf_pay":60000,"stf_heads":2,"stf_pf_ee":3600,"stf_pf_er":4200,"stf_esic_ee":450,"stf_esic_er":1400,
     "pf_trrn":"RJRAJ2608009999111","pf_paid_on":"2026-08-06","esic_challan":"ESIC/26/08/0099887","esic_paid_on":"2026-08-06",
     "processed_on":"2026-08-02","not_processed_amount":0,"not_processed_reason":""}'::jsonb) $$, ID('pst'))), 'posted');
select CK('...the record names the person, not the role',
  (select posted_by from vs_payroll where statement_id=ID('pst')), 'Himanshu Yadav');
select CK('...the wages head is derived from what he entered',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('pst') and l.head_key='wages'), '220000.00');
select CK('...employee part = PF EE + ESIC EE',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('pst') and l.head_key='wages_ee'), '14850.00');
select CK('...employer part = PF ER + ESIC ER',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('pst') and l.head_key='wages_er'), '20200.00');
select CK('...the timeline names him as well',
  (select (count(*)=1)::text from vs_events
    where statement_id=ID('pst') and title like 'Payroll posted%' and actor_name='Himanshu Yadav'), 'true');
select CK('...he types what the partner earned',
  DO_(U('manager'), format($$ select vs_save_draft(%L::uuid, 500000::numeric, 'twelve vehicles'::text,
      null::jsonb, null::jsonb) $$, ID('pst'))), 'OK');
select CK('...and now he can share it, which he could not a moment ago',
  DO_(U('manager'), format($$ select vs_share(%L) $$, ID('pst'))), 'OK');
select CK('accounts can still post a correction over his posting', AS_(U('accounts'), format(
  $$ select vs_post_payroll(%L::uuid,'{"dh_pay":225000,"dh_heads":12,"dh_pf_ee":13200,"dh_pf_er":15000,"dh_esic_ee":1650,"dh_esic_er":5200,
     "stf_pay":60000,"stf_heads":2,"stf_pf_ee":3600,"stf_pf_er":4200,"stf_esic_ee":450,"stf_esic_er":1400,
     "pf_trrn":"RJRAJ2608009999111","esic_challan":"ESIC/26/08/0099887","not_processed_amount":0,"not_processed_reason":""}'::jsonb) $$,
  ID('pst'))), 'parked');
select CK('...and the version the vendor was sent does not move',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('pst') and v.v=1 and l.head_key='wages'), '220000.00');
select CK('the CEO still cannot post one', AS_(U('ceo'), format(
  $$ select vs_post_payroll(%L::uuid,'{}'::jsonb) $$, ID('pst'))), 'REFUSED');
select CK('nor the VP', AS_(U('vp'), format(
  $$ select vs_post_payroll(%L::uuid,'{}'::jsonb) $$, ID('pst'))), 'REFUSED');
select CK('nor the vendor', AS_(U('ramesh'), format(
  $$ select vs_post_payroll(%L::uuid,'{}'::jsonb) $$, ID('pst'))), 'REFUSED');
select CK('nor can anybody write the payroll table directly',
  DO_(U('manager'), $$ update vs_payroll set dh_pay = 1 $$), 'REFUSED');
select CK('nor read it for a statement that is not theirs',
  AS_(U('dinesh'), format($$ select count(*) from vs_payroll where statement_id=%L $$, ID('pst'))), '0');

-- ====== 18. a point on the earned amount, and a general query ==========
-- Built on the payroll test statement from section 17, which is shared and
-- has nothing else riding on it.
select CK('the vendor questions the EARNED amount itself', AS_(U('ramesh'), format(
  $$ select (vs_raise_point(%L,'gross','','Total Expenses Should Be Paid',
       480000::numeric,'12 vehicles ran all month, this looks like 11','') is not null)::text $$,
  ID('pst'))), 'REFUSED');
-- ...refused, because pst is Payroll Test Partner's, not Ramesh's. Use the
-- right vendor: whoever holds it.
do $do$
declare uid uuid;
begin
  perform set_config('request.jwt.claim.sub', U('admin')::text, false);
  perform vs_invite('ptp@op.in','Payroll Test Contact','vendor', ID('pv'));
  insert into auth.users (id, email) values ('88888888-8888-8888-8888-888888888888','ptp@op.in')
    on conflict do nothing;
end $do$;
select CK('its own vendor has a login', (select role from vs_profiles where email='ptp@op.in'), 'vendor');

select CK('a point on the earned amount is refused without a note',
  AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select vs_raise_point(%L,'gross','','Total Expenses Should Be Paid',480000::numeric,'','')::text $$,
  ID('pst'))), 'REFUSED');
select CK('the vendor questions the earned amount', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select (vs_raise_point(%L,'gross','','Total Expenses Should Be Paid',
       480000::numeric,'12 vehicles ran all month, this reads like 11','') is not null)::text $$,
  ID('pst'))), 'true');
select CK('...the statement goes under query',
  (select status from vs_statements where id=ID('pst')), 'under_query');
select CK('the manager accepts it at a figure', AS_(U('manager'), format(
  $$ select vs_resolve_point((select id from vs_points where statement_id=%L and target_kind='gross'),
       'accepted',480000::numeric,'checked the log sheet, 12 vehicles ran') $$, ID('pst'))), '');
select CK('...and the new version carries the corrected earned amount',
  AS_(U('manager'), format($$ select vs_issue_revision(%L)::text $$, ID('pst'))), '2');
select CK('...the earned amount really moved',
  (select gross_amount::text from vs_versions where statement_id=ID('pst') and v=2), '480000.00');
select CK('...and v1 still shows what the vendor was first sent',
  (select gross_amount::text from vs_versions where statement_id=ID('pst') and v=1), '500000.00');
select CK('...the change is listed with its reason',
  (select (changes::text like '%log sheet%')::text from vs_versions where statement_id=ID('pst') and v=2), 'true');

-- ---- a general query: not about a figure, does not hold up the money
select CK('the statement is back to sent after the revision',
  (select status from vs_statements where id=ID('pst')), 'sent');
select CK('the vendor raises a general query', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select (vs_raise_query(%L,'When do the two new tippers arrive? I need to plan drivers.','') is not null)::text $$,
  ID('pst'))), 'true');
select CK('...and it does NOT put the settlement under query',
  (select status from vs_statements where id=ID('pst')), 'sent');
select CK('...a blank query is refused', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select vs_raise_query(%L,'   ','')::text $$, ID('pst'))), 'REFUSED');
select CK('...another vendor cannot raise one on it', AS_(U('ramesh'), format(
  $$ select vs_raise_query(%L,'nosy','')::text $$, ID('pst'))), 'REFUSED');
select CK('the manager answers it', AS_(U('manager'), format(
  $$ select vs_answer_query((select id from vs_points where statement_id=%L and target_kind='general'),
       'Both tippers are with RTO, expected by the 20th.') $$, ID('pst'))), '');
select CK('...it reads answered',
  (select status from vs_points where statement_id=ID('pst') and target_kind='general'), 'answered');
select CK('...with the answer on the record',
  (select decision from vs_points where statement_id=ID('pst') and target_kind='general'),
  'Both tippers are with RTO, expected by the 20th.');
select CK('an empty answer is refused', AS_(U('manager'), format(
  $$ select vs_answer_query((select id from vs_points where statement_id=%L and target_kind='general'),'  ') $$,
  ID('pst'))), 'REFUSED');
select CK('the vendor cannot answer his own query', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select vs_answer_query((select id from vs_points where statement_id=%L and target_kind='general'),'sorted') $$,
  ID('pst'))), 'REFUSED');
select CK('answering a point about a figure through this door is refused', AS_(U('manager'), format(
  $$ select vs_answer_query((select id from vs_points where statement_id=%L and target_kind='gross'),'no') $$,
  ID('pst'))), 'REFUSED');

-- ---- remarks, from either side
select CK('the vendor adds a remark', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select (vs_add_remark((select id from vs_points where statement_id=%L and target_kind='general'),
       'Thank you. Will the drivers come from your side?') is not null)::text $$, ID('pst'))), 'true');
select CK('the manager adds one back', AS_(U('manager'), format(
  $$ select (vs_add_remark((select id from vs_points where statement_id=%L and target_kind='general'),
       'No, please arrange drivers as usual.') is not null)::text $$, ID('pst'))), 'true');
select CK('...both are on the thread, in order',
  (select string_agg(by_role,'>' order by at) from vs_point_remarks rm
     join vs_points p on p.id = rm.point_id where p.statement_id=ID('pst')), 'vendor>manager');
select CK('a blank remark is refused', AS_(U('manager'), format(
  $$ select vs_add_remark((select id from vs_points where statement_id=%L and target_kind='general'),'  ') $$,
  ID('pst'))), 'REFUSED');
select CK('the CEO cannot write a remark', AS_(U('ceo'), format(
  $$ select vs_add_remark((select id from vs_points where statement_id=%L and target_kind='general'),'hello') $$,
  ID('pst'))), 'REFUSED');
select CK('the VP cannot either', AS_(U('vp'), format(
  $$ select vs_add_remark((select id from vs_points where statement_id=%L and target_kind='general'),'hello') $$,
  ID('pst'))), 'REFUSED');
select CK('another vendor cannot read the thread', AS_(U('dinesh'), format(
  $$ select count(*) from vs_point_remarks rm join vs_points p on p.id=rm.point_id
     where p.statement_id=%L $$, ID('pst'))), '0');
select CK('...but its own vendor can', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select count(*) from vs_point_remarks rm join vs_points p on p.id=rm.point_id
     where p.statement_id=%L $$, ID('pst'))), '2');
select CK('nobody can write a remark row directly',
  DO_(U('manager'), $$ insert into vs_point_remarks (point_id, body, by_name, by_role)
     values (gen_random_uuid(),'x','y','manager') $$), 'REFUSED');

-- ====== 19. salary processed late goes on as a top-up ==================
select CK('the first posting recorded itself as entry 1',
  (select count(*)::text from vs_payroll_batches where statement_id=ID('pst') and seq=1), '1');
select CK('...carrying the figures the month is posted at, correction included',
  (select dh_pay::text||'/'||dh_heads::text from vs_payroll_batches where statement_id=ID('pst') and seq=1),
  '225000.00/12');
select CK('a top-up with no challan is refused', AS_(U('manager'), format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":41200,"dh_heads":4,"pf_trrn":"","esic_challan":"E9","note":"late"}'::jsonb) $$,
  ID('pst'))), 'REFUSED');
select CK('a top-up with no reason is refused', AS_(U('manager'), format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":41200,"dh_heads":4,"pf_trrn":"T9","esic_challan":"E9","note":""}'::jsonb) $$,
  ID('pst'))), 'REFUSED');
select CK('an empty top-up is refused', AS_(U('manager'), format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":0,"stf_pay":0,"pf_trrn":"T9","esic_challan":"E9","note":"nothing"}'::jsonb) $$,
  ID('pst'))), 'REFUSED');
select CK('the four late helpers go on as entry 2', AS_(U('manager'), format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":41200,"dh_heads":4,"dh_pf_ee":2470,"dh_pf_er":2810,
     "dh_esic_ee":310,"dh_esic_er":975,"pf_trrn":"RJRAJ2608009999222","esic_challan":"ESIC/26/08/0099888",
     "note":"four helpers left off the first run, processed on the 22nd"}'::jsonb) $$, ID('pst'))), 'parked');
select CK('...the month now totals 18 persons',
  (select (dh_heads + stf_heads)::text from vs_payroll where statement_id=ID('pst')), '18');
select CK('...and the wages total is the sum of both entries',
  (select dh_pay::text from vs_payroll where statement_id=ID('pst')), '266200.00');
select CK('...the entries read as a list, oldest first',
  (select string_agg(seq::text||':'||dh_heads::text,' ' order by seq)
     from vs_payroll_batches where statement_id=ID('pst')), '1:12 2:4');
select CK('...the top-up names who posted it and why',
  (select posted_by||' - '||note from vs_payroll_batches where statement_id=ID('pst') and seq=2),
  'Himanshu Yadav - four helpers left off the first run, processed on the 22nd');
-- v2 already carries the Accounts correction from section 17, which landed
-- when that revision went out. The top-up must not move it any further.
select CK('...the version the vendor is holding does not move',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('pst') and v.v=2 and l.head_key='wages'), '225000.00');
select CK('...and it lands only when the manager issues the next version',
  AS_(U('manager'), format($$ select vs_issue_revision(%L)::text $$, ID('pst'))), '3');
select CK('...v3 carries the topped-up wages',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id=ID('pst') and v.v=3 and l.head_key='wages'), '266200.00');
select CK('...listed as a change with the reason the vendor can read',
  (select (changes::text like '%processed late%')::text from vs_versions where statement_id=ID('pst') and v=3), 'true');
select CK('the vendor cannot post a top-up', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":1,"pf_trrn":"T","esic_challan":"E","note":"x"}'::jsonb) $$,
  ID('pst'))), 'REFUSED');
select CK('nor the CEO', AS_(U('ceo'), format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":1,"pf_trrn":"T","esic_challan":"E","note":"x"}'::jsonb) $$,
  ID('pst'))), 'REFUSED');
select CK('a top-up before anything is posted is refused', AS_(U('manager'), format(
  $$ select vs_add_payroll_batch(%L::uuid,'{"dh_pay":1,"pf_trrn":"T","esic_challan":"E","note":"x"}'::jsonb) $$,
  ID('s3'))), 'REFUSED');
select CK('nobody can write a batch row directly',
  DO_(U('manager'), format($$ insert into vs_payroll_batches (statement_id,seq,posted_by)
     values (%L,9,'x') $$, ID('pst'))), 'REFUSED');
select CK('another vendor cannot read the entries', AS_(U('dinesh'), format(
  $$ select count(*) from vs_payroll_batches where statement_id=%L $$, ID('pst'))), '0');

-- ====== 20. telling people, and asking the CEO or VP ==================
-- Sharing queues mail. The CEO and VP hear about every site; a vendor hears
-- only about his own, and never about anybody else's.
select CK('sharing queued mail for that statement',
  (select (count(*) > 0)::text from vs_mail where statement_id = ID('pst')), 'true');
select CK('...the CEO and the VP are both on it',
  (select string_agg(distinct to_role,'+' order by to_role) from vs_mail
    where statement_id=ID('pst') and to_role in ('ceo','vp')), 'ceo+vp');
select CK('...and exactly one vendor - the one whose site it is',
  (select count(distinct to_email)::text from vs_mail
    where statement_id=ID('pst') and to_role='vendor'), '1');
select CK('...and that vendor is the right one',
  (select distinct to_email from vs_mail where statement_id=ID('pst') and to_role='vendor'), 'ptp@op.in');
select CK('...and NOT the other vendors',
  (select count(*)::text from vs_mail where statement_id=ID('pst') and to_role='vendor'
    and to_email in ('ramesh@optrans.in','dinesh@mahaveer.in')), '0');
select CK('the vendor mail carries the site and the amount',
  (select (subject like '%Payroll Test Site%' and body_text like '%Amount for payment%')::text
     from vs_mail where statement_id=ID('pst') and to_role='vendor' limit 1), 'true');
select CK('the leadership mail names the partner',
  (select (body_text like '%Payroll Test Partner%')::text
     from vs_mail where statement_id=ID('pst') and to_role='ceo' limit 1), 'true');
select CK('a revision queues a fresh round',
  (select (count(*) filter (where kind='revised') > 0)::text from vs_mail where statement_id=ID('pst')), 'true');
select CK('the vendor cannot read the outbox',
  AS_('88888888-8888-8888-8888-888888888888'::uuid, $$ select count(*) from vs_mail $$), '0');
select CK('nor can an uninvited account',
  AS_(U('stranger'), $$ select count(*) from vs_mail $$), '0');
select CK('the CEO can',
  AS_(U('ceo'), format($$ select (count(*) > 0)::text from vs_mail where statement_id=%L $$, ID('pst'))), 'true');
select CK('nobody can write the outbox directly',
  DO_(U('manager'), $$ update vs_mail set status='sent' $$), 'REFUSED');
select CK('switching notifications off stops new mail queueing',
  AS_(U('admin'), $$ select vs_save_mail_settings('a@b.com','WeVois','https://x','false'::bool)::text $$), '');
select CK('...a message raised now is marked skipped, not lost',
  AS_(U('admin'), format($$ select (vs_queue_mail(%L,'test','z@z.com','Z','ceo','s','t','') is not null)::text $$, ID('pst'))), 'true');
select CK('...and it reads skipped',
  (select status from vs_mail where to_email='z@z.com'), 'skipped');
select CK('switching them back on',
  AS_(U('admin'), $$ select vs_save_mail_settings('a@b.com','WeVois','https://x','true'::bool)::text $$), '');

-- ---- asking the CEO or the VP
select CK('the manager asks a plain question', AS_(U('manager'), format(
  $$ select (vs_request_approval(%L,'Can we run the Bhilwara tender at the same rate?',null,null,'') is not null)::text $$,
  ID('pst'))), 'true');
select CK('...which mails the CEO and the VP',
  (select count(*)::text from vs_mail where statement_id=ID('pst') and kind='approval'), '2');
select CK('a question with no words is refused', AS_(U('manager'), format(
  $$ select vs_request_approval(%L,'   ',null,null,'')::text $$, ID('pst'))), 'REFUSED');
select CK('an amount with no effect is refused', AS_(U('manager'), format(
  $$ select vs_request_approval(%L,'q',45000::numeric,null,'Extra tipper')::text $$, ID('pst'))), 'REFUSED');
select CK('an amount with no label is refused', AS_(U('manager'), format(
  $$ select vs_request_approval(%L,'q',45000::numeric,'add','')::text $$, ID('pst'))), 'REFUSED');
select CK('an amount of zero is refused', AS_(U('manager'), format(
  $$ select vs_request_approval(%L,'q',0::numeric,'add','x')::text $$, ID('pst'))), 'REFUSED');
select CK('the CEO cannot raise a request - somebody has to ask him', AS_(U('ceo'), format(
  $$ select vs_request_approval(%L,'let me authorise myself',50000::numeric,'add','x')::text $$, ID('pst'))), 'REFUSED');
select CK('nor can the vendor', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select vs_request_approval(%L,'pay me more',50000::numeric,'add','x')::text $$, ID('pst'))), 'REFUSED');
select CK('nor Accounts', AS_(U('accounts'), format(
  $$ select vs_request_approval(%L,'q',null,null,'')::text $$, ID('pst'))), 'REFUSED');

select CK('the manager cannot answer his own request', AS_(U('manager'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at limit 1),
       true,'approving myself') $$, ID('pst'))), 'REFUSED');
select CK('the vendor cannot answer it either', AS_('88888888-8888-8888-8888-888888888888'::uuid, format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at limit 1),
       true,'yes') $$, ID('pst'))), 'REFUSED');
select CK('declining with no reason is refused', AS_(U('ceo'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at limit 1),
       false,'  ') $$, ID('pst'))), 'REFUSED');
select CK('the CEO answers the plain question', AS_(U('ceo'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at limit 1),
       true,'Yes, same rate.') $$, ID('pst'))), 'approved');
select CK('...it is recorded against him',
  (select decided_by||'/'||decided_role||'/'||status from vs_approvals
    where statement_id=ID('pst') order by asked_at limit 1), 'Anil Bhargava/ceo/approved');
select CK('...and answering it twice is refused', AS_(U('ceo'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at limit 1),
       true,'again') $$, ID('pst'))), 'REFUSED');
select CK('...a plain question changes no figure',
  (select count(*)::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('pst') and a.label='Extra tipper hire'), '0');

-- ---- an amount, on a statement the vendor is already holding
select CK('the manager proposes an amount', AS_(U('manager'), format(
  $$ select (vs_request_approval(%L,'Two extra tippers on the 14th, hired on Anil''''s word',
       45000::numeric,'add','Extra tipper hire') is not null)::text $$, ID('pst'))), 'true');
select CK('the VP approves it', AS_(U('vp'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L and amount is not null
       order by asked_at desc limit 1), true,'Confirmed, I authorised it.') $$, ID('pst'))),
  'approved, lands on the next version');
select CK('...the version the vendor holds does not move',
  (select count(*)::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('pst') and v.v=3 and a.label='Extra tipper hire'), '0');
select CK('...and it lands when the manager issues the next one',
  AS_(U('manager'), format($$ select vs_issue_revision(%L)::text $$, ID('pst'))), '4');
select CK('...as a line on v4',
  (select a.effect||' '||a.amount::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('pst') and v.v=4 and a.label='Extra tipper hire'), 'add 45000.00');
select CK('...with the approver named in the reason',
  (select (a.note like '%Approved by Meera Joshi%')::text from vs_version_adj a
     join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('pst') and v.v=4 and a.label='Extra tipper hire'), 'true');
select CK('...listed as a change the vendor can read',
  (select (changes::text like '%Extra tipper hire%')::text from vs_versions
    where statement_id=ID('pst') and v=4), 'true');
select CK('...and it is not applied a second time',
  AS_(U('manager'), format($$ select vs_issue_revision(%L)::text $$, ID('pst'))), 'REFUSED');

-- ---- an amount on a draft goes straight on
select CK('a request on a draft', AS_(U('manager'), format(
  $$ select (vs_request_approval(%L,'Diesel rate revision',12000::numeric,'deduct','Fuel rate correction') is not null)::text $$,
  ID('s3'))), 'true');
select CK('...approved on a draft, it applies at once', AS_(U('ceo'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at desc limit 1),
       true,'Agreed.') $$, ID('s3'))), 'approved and applied');
select CK('...the line is on the draft now',
  (select a.effect||' '||a.amount::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s3') and a.label='Fuel rate correction'), 'deduct 12000.00');
select CK('a declined request writes no line', AS_(U('manager'), format(
  $$ select (vs_request_approval(%L,'Write off the shortfall',80000::numeric,'add','Shortfall write off') is not null)::text $$,
  ID('s3'))), 'true');
select CK('...the CEO declines it', AS_(U('ceo'), format(
  $$ select vs_decide_approval((select id from vs_approvals where statement_id=%L order by asked_at desc limit 1),
       false,'No. Recover it from the security deposit.') $$, ID('s3'))), 'declined');
select CK('...and nothing was written',
  (select count(*)::text from vs_version_adj a join vs_versions v on v.id=a.version_id
    where v.statement_id=ID('s3') and a.label='Shortfall write off'), '0');
select CK('...but the refusal and its reason are on the record',
  (select (count(*)=1)::text from vs_events where statement_id=ID('s3')
    and title like 'Declined by%' and body like '%security deposit%'), 'true');

-- ---- the observers are still observers
select CK('the CEO still cannot share a statement',
  DO_(U('ceo'), format($$ select vs_share(%L) $$, ID('s3'))), 'REFUSED');
select CK('...nor edit a draft', DO_(U('ceo'), format(
  $$ select vs_save_draft(%L::uuid, 1::numeric, null::text, null::jsonb, null::jsonb) $$, ID('s3'))), 'REFUSED');
select CK('...nor post a payroll', AS_(U('ceo'), format(
  $$ select vs_post_payroll(%L::uuid,'{}'::jsonb) $$, ID('s3'))), 'REFUSED');
select CK('...nor release a payment', AS_(U('ceo'), format(
  $$ select vs_record_payment(%L::uuid,1::numeric,'2026-08-06'::date,'X','NEFT','') $$, ID('pst'))), 'REFUSED');
select CK('...nor resolve a point on a figure', AS_(U('ceo'), format(
  $$ select vs_resolve_point((select id from vs_points where statement_id=%L limit 1),'accepted',1::numeric,'x') $$,
  ID('pst'))), 'REFUSED');
select CK('...nor write an approval row by hand',
  DO_(U('ceo'), $$ update vs_approvals set amount = 999999 $$), 'REFUSED');
select CK('...nor promote himself',
  DO_(U('ceo'), $$ update vs_profiles set role='admin' where id = auth.uid() $$), 'REFUSED');
select CK('the vendor cannot see what WeVois asked its own leadership',
  AS_('88888888-8888-8888-8888-888888888888'::uuid, $$ select count(*) from vs_approvals $$), '0');

-- ====== 18. a head can credit him, or be recorded without counting =====
-- Until now every booking head was a deduction: money WeVois had spent for the
-- partner, taken off what we pay. The sheet does not always work that way. A
-- head can be a credit, and some rows are there only because they happened -
-- a payment already recorded - and must not be counted a second time.
-- Built on its own site so nothing above depends on it.
do $do$
begin
  perform set_config('request.jwt.claim.sub', U('admin')::text, false);
  perform PUT('ev', vs_add_vendor('Effect Test Partner','OP-88','Y','y@et.in','90111'));
  perform PUT('es', vs_add_site('Effect Test Site','Bundi'));
  perform PUT('ec', vs_add_contract(ID('ev'), ID('es'), 10, '2026-06-01'));
  perform PUT('est', vs_add_statement(ID('ec'), '2026-06-01'));
  perform vs_invite('etp@op.in','Effect Test Owner','vendor', ID('ev'));
end $do$;
insert into auth.users (id, email) values
  ('a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8','etp@op.in') on conflict do nothing;

-- ---- nothing that already exists moved
select CK('every line in this whole database still reduces the payment',
  (select (count(*) filter (where effect <> 'deduct'))::text from vs_version_lines), '0');
select CK('a fresh month starts every head reducing the payment',
  (select (count(*) filter (where l.effect='deduct') = count(*))::text
     from vs_version_lines l join vs_versions v on v.id=l.version_id
    where v.statement_id = ID('est')), 'true');

-- ---- the manager fills three heads and chooses what each one does
select CK('the manager types the earned amount and three running heads',
  DO_(U('manager'), format($$ select vs_save_draft(%L::uuid, 400000::numeric, 'ten vehicles'::text,
    '{"rm":50000,"misc":30000,"print":20000}'::jsonb, null::jsonb) $$, ID('est'))), 'OK');
select CK('...all three reduce the payment to start with',
  (select vs_version_heads(vs_current_version(ID('est')))::text), '100000.00');
select CK('...so the Total is what he earned less what we spent',
  (select vs_version_total(vs_current_version(ID('est')))::text), '300000.00');

select CK('he marks one head as crediting the partner instead',
  DO_(U('manager'), format($$ select vs_save_draft(%L::uuid, null::numeric, null::text,
    null::jsonb, null::jsonb, '{"misc":"add"}'::jsonb) $$, ID('est'))), 'OK');
select CK('...the net taken off drops by that head twice over',
  (select vs_version_heads(vs_current_version(ID('est')))::text), '40000.00');
select CK('...and the Total rises by the same 60,000',
  (select vs_version_total(vs_current_version(ID('est')))::text), '360000.00');
select CK('...the row is still on the statement with its own figure',
  (select l.amount::text||'/'||l.effect from vs_version_lines l
     join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and l.head_key = 'misc'), '30000.00/add');

select CK('he marks another as recorded only',
  DO_(U('manager'), format($$ select vs_save_draft(%L::uuid, null::numeric, null::text,
    null::jsonb, null::jsonb, '{"print":"note"}'::jsonb) $$, ID('est'))), 'OK');
select CK('...a recorded-only head does not move the figure at all',
  (select vs_version_heads(vs_current_version(ID('est')))::text), '20000.00');
select CK('...the Total moves by exactly the 20,000 no longer taken off',
  (select vs_version_total(vs_current_version(ID('est')))::text), '380000.00');
select CK('...but the row and its amount are still there to be read',
  (select l.amount::text||'/'||l.effect from vs_version_lines l
     join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and l.head_key = 'print'), '20000.00/note');

-- ---- what WeVois actually spent is now a different number from the net
select CK('company spend counts only what reduces the payment',
  (select vs_version_spend(vs_current_version(ID('est')))::text), '50000.00');
select CK('...and the net taken off is not the same figure',
  (select (vs_version_spend(vs_current_version(ID('est')))
        <> vs_version_heads(vs_current_version(ID('est'))))::text), 'true');

-- ---- the refusals
select CK('a made-up effect is refused', DO_(U('manager'), format(
  $$ select vs_save_draft(%L::uuid, null::numeric, null::text, null::jsonb, null::jsonb,
     '{"rm":"whatever"}'::jsonb) $$, ID('est'))), 'REFUSED');
select CK('...and the head it names is untouched',
  (select l.effect from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and l.head_key = 'rm'), 'deduct');
select CK('a vendor cannot choose what a head does', DO_('a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8'::uuid,
  format($$ select vs_save_draft(%L::uuid, null::numeric, null::text, null::jsonb, null::jsonb,
     '{"rm":"add"}'::jsonb) $$, ID('est'))), 'REFUSED');
select CK('the CEO cannot either', DO_(U('ceo'), format(
  $$ select vs_save_draft(%L::uuid, null::numeric, null::text, null::jsonb, null::jsonb,
     '{"rm":"add"}'::jsonb) $$, ID('est'))), 'REFUSED');
select CK('a payroll head keeps reducing the payment whatever is asked of it',
  DO_(U('manager'), format($$ select vs_save_draft(%L::uuid, null::numeric, null::text,
     null::jsonb, null::jsonb, '{"wages":"add"}'::jsonb) $$, ID('est'))), 'OK');
select CK('...it did not move',
  (select l.effect from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and l.head_key = 'wages'), 'deduct');

-- ---- a shared version is frozen, effects included
do $do$
begin
  perform set_config('request.jwt.claim.sub', U('manager')::text, false);
  perform vs_post_payroll(ID('est'), '{"dh_pay":0,"dh_heads":0,"dh_pf_ee":0,"dh_pf_er":0,"dh_esic_ee":0,"dh_esic_er":0,
    "stf_pay":0,"stf_heads":0,"stf_pf_ee":0,"stf_pf_er":0,"stf_esic_ee":0,"stf_esic_er":0,
    "pf_trrn":"RJRAJ2606000000001","esic_challan":"ESIC/26/06/0000001","not_processed_amount":0,"not_processed_reason":""}'::jsonb);
  perform vs_share(ID('est'));
end $do$;
select CK('once shared, the effect is frozen with the figures', DO_(U('manager'), format(
  $$ select vs_save_draft(%L::uuid, null::numeric, null::text, null::jsonb, null::jsonb,
     '{"rm":"note"}'::jsonb) $$, ID('est'))), 'REFUSED');
select CK('...the vendor is still holding what he was sent',
  (select l.effect from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and l.head_key = 'misc' and v.v = 1), 'add');

-- ---- a revision inherits the choice it corrects
do $do$
declare pid uuid;
begin
  perform set_config('request.jwt.claim.sub', 'a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8'::uuid::text, false);
  perform PUT('ept', vs_raise_point(ID('est'),'head','rm','R&M Exp.', 45000, 'R and M was 45,000, not 50,000', ''));
  perform set_config('request.jwt.claim.sub', U('manager')::text, false);
  select id into pid from vs_points where statement_id = ID('est') order by raised_at desc limit 1;
  perform vs_resolve_point(pid, 'accepted', 45000, 'Bill checked, he is right');
  perform vs_issue_revision(ID('est'));
end $do$;
select CK('the revision carries every effect forward untouched',
  (select string_agg(l.head_key||':'||l.effect, ',' order by l.head_key)
     from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and v.v = 2 and l.head_key in ('misc','print','rm')),
  'misc:add,print:note,rm:deduct');
select CK('...and the corrected figure is on the credited head''s neighbour',
  (select l.amount::text from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est') and v.v = 2 and l.head_key = 'rm'), '45000.00');
select CK('...v2 Total = 400000 - 45000 + 30000, print recorded only',
  (select vs_version_total(vs_current_version(ID('est')))::text), '385000.00');

-- ---- the site's standing choice, set once by the administrator
select CK('the admin sets this site''s Misc head to credit the partner by default',
  DO_(U('admin'), format($$ select vs_set_head(
    (select id from vs_heads where site_id = %L and key = 'misc'), null::text, null::int, null::bool, 'add') $$,
    ID('es'))), 'OK');
select CK('...a payroll head cannot be set to anything else', DO_(U('admin'), format(
  $$ select vs_set_head((select id from vs_heads where site_id = %L and key = 'wages'),
     null::text, null::int, null::bool, 'add') $$, ID('es'))), 'REFUSED');
select CK('...a nonsense value is refused too', DO_(U('admin'), format(
  $$ select vs_set_head((select id from vs_heads where site_id = %L and key = 'misc'),
     null::text, null::int, null::bool, 'sideways') $$, ID('es'))), 'REFUSED');
select CK('...and the vendor manager cannot set the site default',
  DO_(U('manager'), format($$ select vs_set_head(
    (select id from vs_heads where site_id = %L and key = 'print'), null::text, null::int, null::bool, 'note') $$,
    ID('es'))), 'REFUSED');
do $do$
begin
  perform set_config('request.jwt.claim.sub', U('admin')::text, false);
  perform PUT('est2', vs_add_statement(ID('ec'), '2026-07-01'));
end $do$;
select CK('next month opens with the standing choice already made',
  (select l.effect from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est2') and l.head_key = 'misc'), 'add');
select CK('...and every other head still reduces the payment',
  (select (count(*) filter (where l.effect <> 'deduct'))::text
     from vs_version_lines l join vs_versions v on v.id = l.version_id
    where v.statement_id = ID('est2')), '1');
select CK('the audit log says what was changed and to what',
  (select (count(*) > 0)::text from vs_audit
    where title = 'Booking head changed' and body like '%credits him%'), 'true');

-- ---- the app is handed both numbers and the per-line choice
select CK('the payload carries the effect on every line',
  AS_(U('manager'), format($$ select (jsonb_array_length(
    (vs_statement_json(%L::uuid) -> 'versions' -> -1 -> 'lines')) =
    (select count(*) from jsonb_array_elements(vs_statement_json(%L::uuid) -> 'versions' -> -1 -> 'lines') e
      where e ? 'effect'))::text $$, ID('est'), ID('est'))), 'true');
select CK('...and the spend, separate from the net taken off',
  AS_(U('manager'), format($$ select ((vs_statement_json(%L::uuid) -> 'versions' -> -1 ->> 'spend_total')::numeric
    <> (vs_statement_json(%L::uuid) -> 'versions' -> -1 ->> 'heads_total')::numeric)::text $$,
    ID('est'), ID('est'))), 'true');
select CK('a vendor from another site is still shown nothing here',
  AS_(U('ramesh'), format($$ select vs_statement_json(%L) $$, ID('est'))), 'REFUSED');

-- ============================ report ==================================
\pset tuples_only off
\pset format aligned
select case when ok then 'PASS' else 'FAIL' end as result, label,
       case when ok then '' else 'got ['||coalesce(got,'null')||'] want ['||coalesce(want,'null')||']' end as detail
from t_res order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from t_res;
