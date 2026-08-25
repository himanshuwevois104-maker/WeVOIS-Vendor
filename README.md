# WeVois — Vendor Settlement Portal

The monthly expense settlement with each operating partner, as a record rather
than a message. Every figure, every point raised, every correction and its
reason, every approval and every payment is timestamped against a named person
and a role, and none of it can be edited afterwards.

**This repository is the vendor settlement portal only.** The WeVois Daily
Activity Tracker is a different application with a different Supabase project;
the two cannot share a folder, because a static host serves one `index.html`.

## Before the site will work

1. **Run the SQL, in this order**, each once, in the Supabase SQL Editor
   (select the whole file, then Run):

   | File | What it does |
   |---|---|
   | `VS-SETUP.sql` | the schema — tables, row-level policies, ~40 functions |
   | `VS-PATCH-1.sql` | the vendor manager can record payments; payroll/PF/ESIC file attachments; the workbook importer |
   | `VS-PATCH-2.sql` | closes a hole where a vendor could read other vendors' sites and figures |
   | `VS-PATCH-3.sql` | the administrator can edit a site and a tenure after creating them |
   | `VS-PATCH-4.sql` | the vendor manager can post the processed salary, PF and ESIC |
   | `VS-PATCH-5.sql` | points on the earned amount, a queries thread, vendor uploads, payroll top-ups |

   Each ends by printing a verification row. `VS-SETUP.sql` prints
   `13 | 16 | 21 | 0 | 0 | 0 | t`; the patches print `t` or `1` across.

2. **Optional, and mutually exclusive with each other:**
   - `VS-SEED-ALL.sql` + `VS-IMPORT-HISTORY.sql` load the ten sites, four
     vendors and 84 months out of *Operation Partners Payment Details 9.xlsx*.
     Read `WORKBOOK-IMPORT-NOTES.md` first — it lists seventeen cells in that
     workbook that do not add up.
   - `VS-RESET.sql` empties everything back to the first-run screen. Run this
     instead if you are entering your own data.

   `VS-IMPORT-HISTORY.sql` must run **after** an administrator exists, because
   it borrows that person's identity — the SQL editor is not a signed-in user.

3. **Supabase → Authentication → Providers → Email:** Confirm email **OFF**,
   sign-ups **ON**. That is safe: an account with no invitation gets no profile
   row, and with no profile every policy fails closed.

4. `supabase-config.js` already carries the project URL and the **anon public**
   key. The anon key belongs in a browser — that is its purpose. The
   `service_role` key must never go in this file; it bypasses every policy.

`GO-LIVE.md` is the full walkthrough, including deployment and troubleshooting.

## What the host serves

| File | What it is |
|---|---|
| `index.html` | the shell — loads the four scripts below |
| `styles.css` | the design system |
| `vs-payroll-read.js` | reads a PF return, an ESIC history or a bank salary file |
| `vs-core.js` | state, helpers, loading, the auth gates |
| `vs-views.js` | the shell, the role home screens, the six statement tabs |
| `vs-actions.js` | the admin console, every modal, every action, boot |
| `supabase-config.js` | project URL + anon key |
| `manifest.json` | lets people install it on a phone |
| `sw.js` | offline shell, network-first so a redeploy lands immediately |
| `check.html` | open this directly to test the connection from a browser |

All of them sit together at the root of what the host serves. No build step.
Bump `CACHE_VERSION` in `sw.js` on every deploy so installed phones pick the
new build up.

## First run

The first account to sign up becomes the **Admin** — the person who manages
people, vendors, sites and the settlement lifecycle, and who deliberately
cannot build a statement, answer a point, approve anything or move money. Make
that your office administrator, not the CEO and not the vendor manager.

## Roles

**Admin** — people, vendors, sites, tenures, booking heads, opening and
deleting settlements. **Vendor Manager** — builds the statement, posts the
processed salary and PF/ESIC, answers points, issues revisions, releases
payment. **Accounts** — posts processed salary and PF/ESIC, releases payment. **CEO** and **VP** — read everything,
write nothing. **Vendor** — sees only his own sites and only the months sent to
him; raises points, confirms what was said on a call, approves.

The database enforces all of it. Hiding a button is not security: every rule
here is a row-level policy or a check inside the function that performs the
write, proved by 330 assertions running as the `authenticated` role on
PostgreSQL 16.
