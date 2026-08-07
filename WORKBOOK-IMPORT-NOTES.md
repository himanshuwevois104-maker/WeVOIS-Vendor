# What came across from the workbook, and the 17 cells worth a second look

Every month in *Operation Partners Payment Details 9.xlsx* is now a closed settlement in the
portal, with the earned amount, each expense head, each adjustment, the total and the final
payable. 84 of the 99 months loaded. The other 15 are waiting on one thing only, which is at
the bottom of this page.

The figures were not re-derived from your row labels. They were read out of the sheet's own
formulas, column by column, because the eight sheets do not agree with each other about how
the final is built:

| Site | How that sheet builds the Final |
|---|---|
| Kuchaman | Total + Paid Through OP - Direct Payment, and from Sep 2025 + Salary Not Processed |
| Sujalpur | Total + Paid Through OP - Direct Payment + Salary Not Processed |
| Nawa | Total + Paid Through OP, and from Nov 2025 + Salary Not Processed |
| Parbatsar | Total + Paid Through OP |
| Vidhisa | Total + Paid Through OP |
| Bundi | Total + Paid Through OP + Salary Not Processed - Paid Through WeVois, plus both By-Wevois ESIC/PF rows added back |
| Chirawa | Total + R&M Exp.( Paid By Kishan ji) - there is no adjustment row on that sheet at all |
| Jhunjhunu | (Total + R&M Exp.(By Kishan ji)) + 50,000 - built in two steps |

Where the formula adds an expense head back, the portal carries it as an adjustment line named
**Add back: <that head>**, so the vendor sees the same figure with the reason written next to it
instead of an unexplained jump between Total and Final.

**88 of the 99 months reconcile to the rupee** against the Final row on your sheet. 10 have no
Final on the sheet at all and 1 disagrees with itself. Those 11, and 6 more oddities, are below.

---

## 1. Three cells where the sheet's own arithmetic slips

These are drag-fill accidents. Each one is a formula that points somewhere its neighbours do not.

**Nawa, April 2026 (the Heera Ram half of the month).** The Total cell reads
`=U3-T4-T6-...`, taking the *earned* figure from the column next to it - Firoz's 63,783 -
while subtracting its own expenses. It should read `=T3-...` and use 122,100. The sheet shows
a Total and Final of **-38,229**; earned less heads is **20,088**, a gap of 58,317. The portal
carries 20,088. If -38,229 is what Heera Ram was actually told, say so and I will set it back.

**Chirawa, December 2024 and March 2025.** Both Total cells skip row 7, *Maint. Exp By Shyam Ji*,
which every other column subtracts. December is out by 10,364 and March by 3,250. The portal
subtracts it in every month, as April 2025 onward does.

## 2. Two months where a figure is sitting in a row the Final ignores

**Kuchaman, July 2025.** *Direct Payment to OP* holds **10,00,000**, and the Final formula for
that column simply does not include it - `=O17+O18`, where every month either side is
`=N17+N18-N19`. **August 2025** is the same, with **3,93,000**.

Those two figures are 13,93,000 that either was deducted and the sheet forgot to show it, or was
never deducted at all. The portal followed the sheet and did not deduct. This is the single
largest thing on this page and worth checking against the bank before anything else.

## 3. One month that credits back a different head

**Jhunjhunu, June 2026.** The Final adds back *Maint. Exp By Company* (41,988). Every other
month adds back *R&M Exp.(By Kishan ji)*. In June, R&M is zero and Maint is 41,988, so the
figure lands in the right place either way - but the reason written against it differs, and the
vendor will see the label. Worth a word if it was a typo.

## 4. Eleven months with no Final on the sheet

These columns have an earned figure and expenses, but the Final row is empty. The portal applied
the same treatment the rest of that sheet uses, and each is listed here so you can correct any
that should read differently. Open the month, issue a revised version, and the change is recorded
with your reason like any other.

| Site | Month | Total | Portal shows | Because it added back |
|---|---|---:|---:|---|
| Nawa | 2026-04 | 63,783 | 63,783 | nothing - Total is the Final |
| Nawa | 2026-05 | 10,503 | 10,503 | nothing - Total is the Final |
| Nawa | 2026-06 | 45,111 | 45,111 | nothing - Total is the Final |
| Chirawa | 2024-10 | -1,200 | -1,200 | nothing - Total is the Final |
| Chirawa | 2024-11 | 57,498 | 78,424 | Add back: R&M Exp.( Paid By Kishan ji) |
| Chirawa | 2024-12 | 72,998 | 153,753 | Add back: R&M Exp.( Paid By Kishan ji) |
| Chirawa | 2025-01 | 159,812 | 217,397 | Add back: R&M Exp.( Paid By Kishan ji) |
| Chirawa | 2025-02 | 122,435 | 178,185 | Add back: R&M Exp.( Paid By Kishan ji) |
| Chirawa | 2025-03 | 60,647 | 191,556 | Add back: R&M Exp.( Paid By Kishan ji) |
| Chirawa | 2026-05 | -48,591 | -48,591 | nothing - Total is the Final |

Chirawa's six months from October 2024 to March 2025 are the ones to look at hardest. From April 2025 the sheet credits
Kishan ji's R&M back to him every single month; before that the Final row was never filled in.
The portal assumed the same arrangement was running. If the credit-back only started in April
2025, six months are each too high by that month's R&M figure.

## 5. Fifteen months waiting on one answer

**Parbatsar** (Jan-Jun 2026, 6 months), **Bundi** (Feb-Jun 2026, 5 months) and **Vidhisa**
(Apr-Jul 2026, 4 months) did not load, because nothing in the workbook says who runs them.
Kuchaman's sheet is headed *Heera Ram ji*, Chirawa's *Kishan Ji*, Sujalpur's *Shubham Ji* -
those three sheets name their partner. These do not.

| Site | Months | Total value at stake |
|---|---:|---:|
| Parbatsar | 6 | 675,407 |
| Bundi | 5 | 1,529,821 |
| Vidhisa | 4 | 1,167,569 |

Add the vendor in **Administration > Vendors**, assign him in **Sites & tenures** with the date
he started, then run `VS-IMPORT-HISTORY.sql` again. It skips everything already loaded and picks
up only these fifteen. Nothing else changes.

**Dei** and **Laxmangarh** carry payment terms only - no monthly columns - so there is nothing
to import for them yet.

---

## What loaded

| Vendor | Site | Months | From | To | Marked paid | Final total |
|---|---|---:|---|---|---:|---:|
| Kishan Ji | Chirawa | 20 | Oct 2024 | May 2026 | 10 | 2,483,223 |
| Kishan Ji | Jhunjhunu | 7 | Dec 2025 | Jun 2026 | 4 | 2,049,474 |
| Heera Ram ji | Kuchaman | 23 | Aug 2024 | Jun 2026 | 20 | 3,810,044 |
| Heera Ram ji | Nawa | 17 | Dec 2024 | Apr 2026 | 1 | 1,078,959 |
| Firoz | Nawa | 3 | Apr 2026 | Jun 2026 | 1 | 119,397 |
| Shubham Ji | Sujalpur | 14 | Mar 2025 | Apr 2026 | 4 | 2,730,009 |

Every one of them carries a line in its record saying it was loaded from the spreadsheet rather
than raised through the portal, so a settlement that was agreed on a phone call in 2024 can never
be mistaken for one that went through the process.

