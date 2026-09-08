# Making it live

Everything is built and tested. What follows is the whole path, start to finish. Budget about forty minutes for the first ten steps; the rest is your own data.

You need two accounts, both free: **supabase.com** for the database, **vercel.com** for the web address. Nothing else.

---

## Part one — the database (about 15 minutes)

### 1. Create a new Supabase project

Go to supabase.com, sign in, **New project**.

- Name: `wevois-vendor-settlement`
- Region: **South Asia (Mumbai)** — closest to your team, so the app feels quick
- Database password: generate one and keep it somewhere safe. You will not need it for this app, but you will want it one day.

It takes a couple of minutes to provision.

**This must be a new project.** Not the billing one, not the tracker one. Vendors get logins to this database, and a separate project is what makes it structurally impossible for a vendor account to reach municipal billing data. Not a policy you have to trust — a wall.

### 2. Run the schema

Left sidebar → **SQL Editor** → **New query**. Open `VS-SETUP.sql`, select the whole file, copy, paste, **Run**.

Select the *entire* file before copying. The Supabase editor will happily run only what is highlighted, and a half-built schema is worse than none. It is safe to run twice if you are unsure.

The last thing it prints is a verification row. You want exactly this:

```
head_template | adjustment_types | capability_rows | people | vendors | settlements | needs_first_admin
           13 |               16 |              21 |      0 |       0 |           0 | t
```

If you see that, the database is built.

### 3. Build the database

Supabase dashboard -> **SQL Editor** -> **New query**. Open `VS-DATABASE.sql`, select the
whole file, paste it in, press **Run**.

That is the whole step. One file, everything in it, in the right order:

- the schema - tables, row-level security, and the functions every write goes through
- file attachments, the workbook importer, the manager releasing a payment
- each vendor seeing only his own sites
- editing a site, its start and closing dates, and its tenures
- the vendor manager posting the payroll himself
- queries, vendor file uploads, points on the earned amount, payroll top-ups
- email when a month goes out, and confirmation from the CEO or the VP
- a head that credits the partner, or is recorded without being counted - on every
  head, payroll ones included. The amount of a payroll head is still Accounts',
  but what that amount does is the vendor manager's: the employee's own PF and
  ESIC share is money taken from his men rather than spent by the company, and
  some months it belongs on the sheet as a record and not as a deduction
- the security lock-down: only a signed-in person can reach anything

**It does not touch your data.** Every table is created only if it is missing and every
seed row is inserted only if it is not there. Statements already shared with vendors,
their replies, your points, payments and the audit log all stay exactly as they are. Run
it again whenever you like - on a database that is already up to date it changes nothing.

It ends by printing a health check. Every line should read **OK**, and the last few lines
count your own data back to you so you can see nothing moved.

### 3b. On the security line

The key in `supabase-config.js` is the **anon** key. It is public by design: it ships in
every browser that opens the portal. That is fine only because every function refuses a
caller with no profile.

PostgreSQL grants EXECUTE on a new function to PUBLIC automatically, so for a while that
was not quite true. `vs_queue_mail` - an internal helper that `vs_share` and the approval
functions call - had no permission check of its own, because nothing was ever supposed to
reach it from outside. Something could. A stranger holding the public key could post to
`/rest/v1/rpc/vs_queue_mail` with any address, subject and HTML, and the mail sender would
have delivered it **from your office Gmail**. That was proved by doing it; the row landed
in the outbox.

The last part of `VS-DATABASE.sql` takes the free EXECUTE away from every `vs_` function,
gives `anon` back only `vs_needs_setup`, leaves the internal helpers granted to nobody, and
puts a real check inside each of them as well. Afterwards exactly **one** function is
reachable without signing in, and the health check says so.

### 3c. Each site's working sheet

The last part of `VS-DATABASE.sql` adds the site sheets: the month totals, every
penalty with its proof, the day counts and the duty log, mirrored from the sheet
your office already keeps, with a question raisable on **any row or any column**.

Nothing writes back to Google. The sheet stays the operating tool; the portal
becomes the record of the conversation about it.

Read **SHEETS-SYNC.md** for the two steps: connect a sheet to a site, and paste
a small script into that sheet so it pushes itself to the portal every hour. No
Google service account and no new Google project are needed.

Three things worth knowing before you look at it:

- **A row is never deleted.** When a sync no longer finds a row it is marked as
  gone and kept, because a vendor may have a question hanging off it and he is
  entitled to see what he was looking at when he asked.
- **Rows are matched on their own values, not their position.** The sheet gets
  re-sorted all day; a question asked on the 1-June ₹300 penalty must still be
  on that penalty tomorrow, not on whatever slid into row 14.
- **A vendor sees only the sites he holds.** That is the same rule the rest of
  the portal runs on, enforced by the database.

### 3d. Note for later

`VS-IMPORT-HISTORY.sql` loads your whole spreadsheet history, but it cannot run yet. It
writes through the same functions the app uses, and those refuse anybody who is not a
signed-in user with the right role - the SQL editor is nobody. So it waits until the first
administrator exists. It is step 10b below.

### 4. Turn off email confirmation

**Authentication → Sign In / Providers → Email**. Set **Confirm email** to **OFF**. Leave **Allow new users to sign up** ON.

That second part looks wrong and is not. An account that signs up without an invitation gets **no profile row**, and with no profile every policy fails closed — it reads zero vendors, zero sites, zero statements, zero anything. That is tested, not hoped for. Leaving sign-up on is what lets your team and your vendors set their own passwords without you handling any of them.

### 5. Copy the two keys

**Project Settings → API**. You want:

- **Project URL** — looks like `https://abcdefgh.supabase.co`
- **anon public** key — a long string starting `eyJ...`

Open `supabase-config.js` in a text editor and paste them in place of the two `PASTE_...` lines.

The anon key belongs in a browser; that is its whole purpose. The **service_role** key on the same page must never leave that dashboard — it bypasses every policy in the system.

---

## Part two — the web address (about 10 minutes)

### 6. Put the folder online

You have a folder with these files:

```
index.html   styles.css   vs-core.js   vs-views.js   vs-actions.js
supabase-config.js   manifest.json   sw.js
```

There is no build step. It is plain files.

Go to **vercel.com**, sign in, and on the dashboard choose **Add New → Project → Deploy without Git** (on some accounts it reads **Browse all templates → Other → Deploy**). Drag the whole folder in. If you would rather use the terminal, `npx vercel --prod` from inside the folder does the same thing.

Framework preset: **Other**. Build command: leave empty. Output directory: leave empty.

You get a URL like `wevois-vendor-settlement.vercel.app`. That is the live portal.

Netlify Drop (`app.netlify.com/drop`) works exactly the same way if you prefer it — drag the folder onto the page, done.

### 7. Open it

Visit the URL. You should see a dark sign-in card reading **Create the first administrator**.

If instead it says *Not connected yet*, step 5 did not take — check `supabase-config.js` for typos and redeploy.

---

## Part three — your people and your data

### 8. Create the administrator

Fill in the name, email and a password on that first screen.

**The very first account to sign up becomes the administrator.** After that, nobody gets in without an invitation. So make this the person who should hold Admin — not you, and not the CEO. Admin manages people, vendors, sites and the settlement lifecycle, and deliberately cannot build a statement, answer a point, approve anything or move money.

### 9. Create the logins

**Administration → Users & roles → Create a login.** For each person: name, email, role, and for a
vendor login the vendor it belongs to. A password is generated for you; change it if you prefer.

The account is created there and then, and the screen shows you the address, the email and the
password to pass on. You stay signed in as yourself throughout. They change their own password
from **Change password** in the top bar once they are in.

- **Vendor Manager** — you
- **Accounts** — whoever runs payroll and the bank
- **CEO** and **VP** — observers
- **Vendor** — one per operating partner, tied to that vendor

Until you have created a login for an email address, an account signing up with it sees nothing at
all - no vendors, no sites, no statements. That is a database rule, not a hidden screen.

### 10. Assign vendors to sites

**Administration → Sites & tenures.** Each site shows who has run it and when.

For each site press **Assign a vendor**, choose the vendor, enter the vehicle count and the date the tenure started.

**Edit site** changes the name, the city and the site's own start and closing dates. **Edit** next to a tenure changes its start date, its last day and the vehicle count; **Reopen** takes an end date back off. Every one of them refuses rather than corrupts: a date that would strand an existing settlement outside its own tenure is turned away with the months named, two vendors can never overlap on one site, and a site cannot be closed while somebody is still running it. Settlements already sent to a vendor keep the covering dates he was shown.

When a site changes hands, use **Change vendor** and give the exact day — it does not have to be the 1st. Nawa is your example: Heera Ram ji until 15 April 2026, Firoz from the 16th. The outgoing tenure ends the day before automatically, and April then produces two settlements for Nawa, one per vendor, each covering only its own days.

### 10b. Load your history

Now that an administrator exists, go back to the **SQL Editor**, new query, and run
`VS-IMPORT-HISTORY.sql`.

It starts by finding your administrator and telling the database to act as that person for
the length of the script, then hands the identity back at the end - so every imported month
carries a real name in its record rather than "unknown". If you run it before creating the
administrator it stops with *"No administrator exists yet"* and imports nothing.

It finishes by printing what happened, month by month. You should see **84 ok**, and fifteen
lines saying *no vendor on Parbatsar / Bundi / Vidhisa* - those three sites have no partner
named anywhere in the workbook, so they are waiting on you. Assign a vendor to them in
step 10 and run this file again; it skips everything already loaded.

Safe to run as many times as you like. Read `WORKBOOK-IMPORT-NOTES.md` before you show any
imported month to a vendor - it lists seventeen cells in your workbook that do not add up,
including two Kuchaman months where 13,93,000 of Direct Payment sits in a row the Final line
does not count.

### 11. Run your first month

1. **Admin** → Settlements → pick the month at the top right → **Open [month] for all**. One draft appears per running contract.
2. **You or Accounts** open each one, go to the **Payroll &amp; PF/ESIC** tab, and enter the processed wages, salary, headcounts, the PF/ESIC splits and the two challan numbers. The statement cannot go out until this is done, and whoever posts it is named on the record permanently.
3. **You** open it, type what the partner earned in *Total Expenses Should Be Paid*, fill the running heads, add any adjustment lines — advances, direct payments, penalties, reimbursements, or anything you want recorded without it changing the amount — then **Save draft** and **Share with vendor**. That version freezes at that moment.
4. **The vendor** signs in, checks it, and either approves or raises a point on an exact line. If he rings you instead, use **Log a point from a call** while he is still on the phone; he gets it back to confirm.
5. **You** answer each point with a written reason, then **Issue revised statement**. The old version stays untouched beside the new one, with a list of every figure that moved and why.
6. **The vendor** approves. **You or Accounts** release the payment, in one go or in parts, each with
   its own UTR. A payment can be dated to the day the money actually left, however far back that is -
   your home screen carries an **Approved - still to pay** card listing every month still owing,
   oldest first.

**Attaching the payroll paperwork.** On any statement, the **Payroll & PF/ESIC** tab now has a files
section. Attach the payroll register, the PF ECR or the ESIC challan - Excel, PDF or a photo, up to
25 MB each - and the vendor opens them from his own copy of the statement. Removing one needs a
written reason, and both the attachment and the removal go into the permanent record.

---

## If something goes wrong

**"Not connected yet"** — `supabase-config.js` still has the placeholder text, or the file did not get deployed. Check and redeploy.

**"This account is not set up yet"** — the person signed up with an email that has no invitation. Invite that exact address and have them sign in again.

**"Accounts has not posted the payroll..."** — working as intended. Accounts posts first.

**"Your role (...) is not allowed to do that"** — also working as intended. The database refused it, not the screen.

**Something is refused with a database error that makes no sense** - most often
*"new row violates row-level security policy"*. The app and the database are deployed
separately, so a new build can be talking to a database that has not had the matching
patch run. Run **`VS-CHECK-PATCHES.sql`** in the SQL editor; it lists every patch and
whether it has actually been applied. The app now checks this itself at sign-in and
puts a red banner at the top naming any file still to run.

**"Your role (none) is not allowed to do this" while running SQL** — the SQL editor is not a signed-in user, so the write functions refuse it. `VS-IMPORT-HISTORY.sql` handles this itself by acting as your administrator, but it needs one to exist: create the first account in the app, then run the file. If you ever need to do this by hand for some other script, run `select set_config('request.jwt.claim.sub', '<your admin uuid>', false);` first, and set it back to `''` when you are done.

**A change does not appear** — the app caches itself so it opens fast on a phone. After you redeploy, edit `sw.js` and bump `CACHE_VERSION`. Installed devices pick the new build up on the next open.

**"Could not load the PDF reader"** — reading a PF, ESIC or bank file needs one library fetched from the internet the first time you use it in a session. Check the connection and try again. Everything else in the portal works offline against the cache.

---

## What is already proven

Not claims — assertions that run.

**The database: 385 checks on real PostgreSQL 16, as the `authenticated` role, zero failures.** An uninvited signup reads nothing at all. A vendor sees only his own shared statements and none of his own drafts. Another vendor cannot read, query or approve a statement that is not his. The CEO and VP can read everything and every write is refused — including a direct SQL update on their own profile row to promote themselves. The manager cannot post payroll; Accounts cannot resolve a point; the CEO, the VP and the vendor himself are all refused when they try to move money. A statement cannot be shared until payroll is posted. A shared version cannot be edited by anyone, including the admin, including by direct SQL. A decision without a written reason is refused. Payment is refused without a UTR and refused if it would exceed the approved amount. The last administrator cannot be demoted or deactivated. A deleted settlement takes its versions, points and payments with it while the audit tombstone naming who, why and the UTRs survives and cannot itself be edited. An attached file can be read by the vendor it belongs to and by nobody else - not another vendor holding the exact path, not an uninvited account - and no role, including the administrator, can write a document row by direct SQL. A vendor reads only the sites he runs or has run, only his own vendor row, only his own contracts and booking heads, and only the months that have actually been sent to him; pointed straight at another vendor's statement and version with the real identifiers, every one of the nine reader functions gives him nothing, while the owner, Accounts, the CEO and the administrator all still get the right figure.

**The app: 328 checks in a headless browser, zero JavaScript errors**, plus **38 checks on the payroll file readers run against your own July PF return, ESIC history and bank file**, driving the whole journey — first-run bootstrap, building the org, the Nawa mid-month handover producing two April settlements with the right date ranges, the payroll gate, the gross-less-heads arithmetic, a recorded-only adjustment that does not move the figure, sharing and freezing, points on both a head and an adjustment, the phone-call confirm loop, resolve and revise with the diff, approval, part payments, the observer who can touch nothing, the loud delete with its surviving tombstone, a back-dated payment entered by the vendor manager, and the whole attachment cycle: the manager attaching a payroll sheet and an ESIC challan, a 26 MB file turned away, the vendor opening both and being refused when he tries to attach or remove one, another vendor refused the exact path, and a removal that will not go through without a reason. It also checks, as a second vendor with his own login, that his screen names one site, one vendor and one contract, that the other site's name appears nowhere on it, and that staff still read everything.

---

## Still needed from you

The seed knows your sites and their heads. It does not yet know:

- **Which vendor holds Parbatsar, Bundi, Vidhisa, Dei and Laxmangarh** — your workbook does not name them. This is what is holding back the last fifteen months of history, worth about 33.7 lakh.
- **Vehicle counts** for the sites where your sheet leaves the cell blank. Kuchaman 20, Nawa 6, Chirawa 12 and Sujalpur 12 are in the file; the rest are not.
- **Your people** — name, email and role for each of the five roles.
- **Vendor login emails** — the address each operating partner will use.

You can type all of that into the Admin screens as you go. Send it to me instead and I will put it in the seed so it is there on first sign-in.
