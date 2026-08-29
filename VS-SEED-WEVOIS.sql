-- VS-SEED-WEVOIS.sql
-- Sites and their real booking heads, lifted straight from
-- 'Operation Partners Payment Details 9.xlsx'. Run AFTER VS-SETUP.sql,
-- signed in as the administrator (the SQL editor runs as the owner, so this
-- inserts directly rather than through the vs_ functions).
-- Pure ASCII. Re-runnable.

do $seed$
declare sid uuid;
begin

  -- ---------------- Kuchaman ----------------
  select id into sid from vs_sites where name = 'Kuchaman';
  if sid is null then
    insert into vs_sites (name, city) values ('Kuchaman', 'Kuchaman') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 20),
    (sid, 'maint_exp_by_shyam_ji_punit', 'Maint. Exp By Shyam Ji/Punit', 'run', 'manual', 30),
    (sid, 'fuel_exp_adj', 'Fuel Exp. (Adj)', 'run', 'manual', 40),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 50),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 60),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 70),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 80),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 90),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 100),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 110),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 120),
    (sid, 'other_exp', 'Other Exp', 'run', 'manual', 130);

  -- ---------------- Parbatsar ----------------
  select id into sid from vs_sites where name = 'Parbatsar';
  if sid is null then
    insert into vs_sites (name, city) values ('Parbatsar', 'Parbatsar') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_shyam_ji_punit', 'Maint. Exp By Shyam Ji/Punit', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 120);

  -- ---------------- Nawa ----------------
  select id into sid from vs_sites where name = 'Nawa';
  if sid is null then
    insert into vs_sites (name, city) values ('Nawa', 'Nawa') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_shyam_ji_punit', 'Maint. Exp By Shyam Ji/Punit', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 120);

  -- ---------------- Bundi ----------------
  select id into sid from vs_sites where name = 'Bundi';
  if sid is null then
    insert into vs_sites (name, city) values ('Bundi', 'Bundi') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_wevois', 'Maint. Exp By Wevois', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'fuel_exp_loader_tractor_of_wevois', 'Fuel Exp (Loader & Tractor) of wevois', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part_by_wevois', 'ESIC Pf (Employee Part)-By Wevois', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part_by_wevois', 'ESIC Pf (Employer Part)- By Wevois', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'vehicle_rent_of_5_tractor', 'Vehicle Rent of 5 Tractor', 'run', 'manual', 120);

  -- ---------------- Vidhisa ----------------
  select id into sid from vs_sites where name = 'Vidhisa';
  if sid is null then
    insert into vs_sites (name, city) values ('Vidhisa', 'Vidhisa') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_co', 'Maint. Exp By Co.', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 120);

  -- Dei: terms only in the workbook, no heads yet
  if not exists (select 1 from vs_sites where name = 'Dei') then
    insert into vs_sites (name, city) values ('Dei', 'Dei');
  end if;

  -- Laxmangarh: terms only in the workbook, no heads yet
  if not exists (select 1 from vs_sites where name = 'Laxmangarh') then
    insert into vs_sites (name, city) values ('Laxmangarh', 'Laxmangarh');
  end if;

  -- ---------------- Jhunjhunu ----------------
  select id into sid from vs_sites where name = 'Jhunjhunu';
  if sid is null then
    insert into vs_sites (name, city) values ('Jhunjhunu', 'Jhunjhunu') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp_by_kishan_ji', 'R&M Exp.(By Kishan ji)', 'run', 'manual', 10),
    (sid, 'maint_exp_by_company', 'Maint. Exp By Company', 'run', 'manual', 20),
    (sid, 'parking_rent', 'Parking Rent', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110);

  -- ---------------- Chirawa ----------------
  select id into sid from vs_sites where name = 'Chirawa';
  if sid is null then
    insert into vs_sites (name, city) values ('Chirawa', 'Chirawa') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp_paid_by_kishan_ji', 'R&M Exp.( Paid By Kishan ji)', 'run', 'manual', 10),
    (sid, 'r_m_exp_paid_by_wevois', 'R&M Exp. (Paid By Wevois)', 'run', 'manual', 20),
    (sid, 'print_exp', 'Print Exp.', 'run', 'manual', 30),
    (sid, 'maint_exp_by_shyam_ji', 'Maint. Exp By Shyam Ji', 'run', 'manual', 40),
    (sid, 'water_exp', 'Water Exp', 'run', 'manual', 50),
    (sid, 'building_rent', 'Building Rent', 'run', 'manual', 60),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 70),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 80),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 90),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 100),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 110),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 120),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 130),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 140);

  -- ---------------- Sujalpur ----------------
  select id into sid from vs_sites where name = 'Sujalpur';
  if sid is null then
    insert into vs_sites (name, city) values ('Sujalpur', 'Sujalpur') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp_by_subham_ji', 'R&M Exp. ( By Subham ji)', 'run', 'manual', 10),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 20),
    (sid, 'maint_exp', 'Maint. Exp', 'run', 'manual', 30),
    (sid, 'water_exp', 'Water Exp', 'run', 'manual', 40),
    (sid, 'building_rent', 'Building Rent', 'run', 'manual', 50),
    (sid, 'fuel_exp_by_shubham_ji', 'Fuel Exp. (By Shubham ji)', 'run', 'manual', 60),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 70),
    (sid, 'esic_pf_employee_part_from_wevois', 'ESIC Pf (Employee Part) From wevois', 'esic', 'payroll', 80),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 90),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 100),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 110),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 120),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 130);

  -- vendors named in the workbook
  insert into vs_vendors (name, code, contact_name)
  select v.n, v.c, v.n from (values
    ('Heera Ram ji','OP-HRJ'), ('Kishan Ji','OP-KSJ'), ('Shubham Ji','OP-SBJ'), ('Firoz','OP-FRZ')
  ) as v(n,c) where not exists (select 1 from vs_vendors x where x.name = v.n);

end $seed$;

select s.name as site, count(h.*) as booking_heads
  from vs_sites s left join vs_heads h on h.site_id = s.id group by s.name order by s.name;
