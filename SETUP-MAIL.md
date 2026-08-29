# Sending the mail from your office address

The portal never sends mail itself. It writes every message it wants sent into
an outbox in the database, and a small function on Supabase picks them up and
sends them over your own mail server. That split is deliberate: sending needs a
password, and a password in a browser is a password everybody has.

If you never set this up, nothing breaks. The mail queues, you can read every
message in **Administration > Mail**, and it goes out the moment you finish
this page.

---

**Your address: `himanshu.wevois104@gmail.com`.** That is Gmail, so the settings
you need are `smtp.gmail.com` on port `465`, and the section below is the one
that applies. Everything works from a @gmail.com address; the only thing worth
knowing is that vendors will see it come from a personal Gmail rather than from
wevois.com. If you have a mailbox on your own domain, use that instead and the
mail will look like it came from the company.

## 1. Get an app password from your mail provider

Your normal mail password will not work, and should not be used. Both providers
below issue a separate password for programs.

### Google Workspace / Gmail  <- yours

1. The account must have **2-step verification** on.
   *myaccount.google.com > Security > 2-Step Verification*
2. *myaccount.google.com > Security > App passwords*
3. Create one, call it **WeVois portal**. You get 16 letters. Copy them; Google
   will not show them again.

Settings: host `smtp.gmail.com`, port `465`.

### Microsoft 365 / Outlook

1. *portal.office.com > My account > Security info > Add sign-in method >
   App password*. If it is not there, your administrator has turned it off and
   must switch on **Authenticated SMTP** for the mailbox.

Settings: host `smtp.office365.com`, port `587`.

### Anything else

Any SMTP server works. You need the host, the port, the username and the
password. Port 465 is used with implicit TLS, 587 with STARTTLS; the function
picks the right one from the port number.

---

## 2. Deploy the function

You need the Supabase CLI once. On Windows, in PowerShell:

```
npm install -g supabase
supabase login
supabase link --project-ref rooqoqtliaqycscjkfxt
supabase functions deploy send-mail --no-verify-jwt
```

The `supabase/functions/send-mail/` folder in this download is what it deploys.

## 3. Give it the password

```
supabase secrets set SMTP_HOST=smtp.gmail.com SMTP_PORT=465 ^
  SMTP_USER=himanshu.wevois104@gmail.com SMTP_PASS=the16letters
```

The 16 letters go in with no spaces, even though Google shows them in groups of
four.

Nothing here goes near the browser. These live on Supabase.

## 4. Tell the portal who the mail is from

In the app: **Administration > Mail**.

- **From address** - the same mailbox as `SMTP_USER`. Sending as an address you
  do not own is what gets mail marked as spam.
- **From name** - what people see. "WeVois Vendor Settlement" by default.
- **Portal address** - the web address of this site, so the mail can link back
  to it. Without it the mail still goes, just with no link.
- **Notifications on** - the master switch. Off means messages are still written
  down and marked *skipped*, so you can see what would have gone.

## 5. Make it send by itself

Supabase Dashboard > **Database** > **Cron** > new job, every 5 minutes:

```sql
select net.http_post(
  url     := 'https://rooqoqtliaqycscjkfxt.functions.supabase.co/send-mail',
  headers := '{"Authorization":"Bearer YOUR_ANON_KEY","Content-Type":"application/json"}'::jsonb
);
```

Until you do this, **Administration > Mail > Send the queue now** does the same
thing by hand, which is fine while you are testing.

---

## Who gets what

| When | Who | What it says |
|---|---|---|
| You share a month, or issue a revised version | that site's vendor | his site, the month, the amount, and how to raise a point |
| The same | the CEO and the VP | the site, the partner, the month and the amount, for every site |
| You ask for confirmation | the CEO and the VP | your question, and the amount if there is one |

A vendor is only ever mailed about his own sites. The CEO and the VP are mailed
about all of them, which is the difference between the two.

---

## If it does not send

Open **Administration > Mail**. Every message is listed with its state and, if
it failed, the reason the server gave.

**"SMTP is not configured yet"** - the secrets are not set, or the From address
is blank in the portal. Step 3 and step 4.

**535 / authentication failed** - the app password is wrong, or you used the
normal account password. Make a new app password.

**Connection failed / timeout** - wrong host or port. 465 and 587 are the two
that matter; try the other one.

**Mail sends but lands in spam** - the From address must be a real mailbox on a
domain you own, and it must match `SMTP_USER`. Ask whoever runs your DNS to add
an SPF record permitting your provider.

**Nothing is queued at all** - notifications are switched off in
Administration > Mail, or the CEO, VP and vendor accounts have no email
addresses on their profiles.
