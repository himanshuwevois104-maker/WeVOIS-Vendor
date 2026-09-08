# WeVois — Vendor Settlement Portal

The monthly expense settlement with each operating partner, as a record rather
than a message. Every figure, every point raised, every correction and its
reason, every approval and every payment is timestamped against a named person
and a role, and none of it can be edited afterwards.

**This repository is the vendor settlement portal only.** The WeVois Daily
Activity Tracker is a different application with a different Supabase project;
the two cannot share a folder, because a static host serves one `index.html`.

## Before the site will work

1. **Run the SQL.** Supabase → SQL Editor → New query → open `VS-DATABASE.sql`,
   select the whole file, paste, **Run**. That is the whole step: one file,
   everything in it, in the right order — schema, row-level policies, the ~75
   functions every write goes through, vendor isolation, file attachments,
   queries, payroll top-ups, email, CEO/VP confirmation, the head effect, and
   the security lock-down.

   **It does not touch your data.** Every table is created only if it is
   missing and every seed row only if it is not there. Statements already
   shared with vendors, their replies, your points, payments and the audit log
   stay exactly as they are. Run it again whenever you like — on a database
   already up to date it changes nothing.

   It ends by printing a health check. Every line should read **OK**, and the
   last few count your own data back to you so you can see nothing moved.

2. **Optional.** `VS-IMPORT-HISTORY.sql` loads the sites, vendors and 84 months
   out of *Operation Partners Payment Details 9.xlsx*. Read
   `WORKBOOK-IMPORT-NOTES.md` first — it lists seventeen cells in that workbook
   that do not add up. It must run **after** an administrator exists, because it
   borrows that person's identity; the SQL editor is not a signed-in user.

3. **Supabase → Authentication → Providers → Email:** Confirm email **OFF**,
   sign-ups **ON**. That is safe: an account with no invitation gets no profile
   row, and with no profile every policy fails closed.

## About the key in this repository

`supabase-config.js` carries the project URL and the **anon public** key, and
this repository is public, so anybody can read both. That is by design — the
anon key is what a browser uses, and it is meant to be seen.

It is only safe because of the last part of `VS-DATABASE.sql`. PostgreSQL
grants EXECUTE on a new function to PUBLIC automatically, which for a while
meant every `vs_` function was reachable by anyone holding that key. Most
refused anyway, because they start by checking the caller's role — but
`vs_queue_mail`, an internal helper with no check of its own, did not. Anyone
could have posted to `/rest/v1/rpc/vs_queue_mail` and had the mail sender
deliver their subject and their HTML **from the office Gmail account**.

`VS-DATABASE.sql` takes that free EXECUTE away, gives `anon` back only
`vs_needs_setup`, leaves the internal helpers granted to nobody, and puts a real
check inside each of them as well. Afterwards exactly **one** function is
reachable without signing in, and the health check says so.

So: **run the file before this repository is of any use to anybody but you**,
and never put the `service_role` key in `supabase-config.js` — that one bypasses
every policy and no patch can save you from it.

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
write, proved by 385 assertions running as the `authenticated` role on
PostgreSQL 16.
