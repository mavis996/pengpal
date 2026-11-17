# PengPal prototype (static site + Supabase)

The prototype is plain HTML/CSS/JS in `docs/`. It saves each visitor's answers
(traveler type, interests, host, booking, commitment, review) to a Supabase table.
It also collects hand-matching requests: after onboarding, a "match request" screen asks for a
contact (email, WeChat or WhatsApp) and trip dates. There is no server to run or pay for.

## One-time setup

### 1. Create the database (about 3 minutes)
1. Make a free project at https://supabase.com.
2. Open **SQL Editor > New query**, paste all of `supabase/schema.sql`, click **Run**.
   **Already ran an earlier version?** Run this file again. It adds the new columns and keeps
   your existing rows.
3. Open **Project Settings > API** (or the **Connect** button) and copy the **Project URL**
   and the public **anon / publishable** key.

### 2. Point the site at it
Edit `docs/config.js` and fill in `supabaseUrl` and `supabaseKey`.
That key is meant to be public. Never use the `service_role` / secret key here.

### 3. Put it online with GitHub Pages
1. Push this repo to GitHub.
2. **Settings > Pages > Build and deployment**: Source = *Deploy from a branch*,
   Branch = `main`, folder = `/docs`. Save.
3. After a minute the site is at `https://<user>.github.io/<repo>/`.

To try it locally first: `cd docs && python3 -m http.server 8000`, then open http://localhost:8000.

## The match request screen
After onboarding the traveler sees: "We match every traveler by hand. Leave your contact and trip
dates, and we'll send you 2-3 hand-picked locals within 3 days."

- They choose Email, WeChat or WhatsApp, enter it, and give arrival and leaving dates
  (or switch on "My dates are flexible"). Everything is checked before it is sent.
- Their contact is saved only when they press **Send my request**. A half-typed contact is never sent.
- "Skip for now" goes straight to the sample hosts, so you can still measure how many people skip.
- The request is stored on the same row as their onboarding answers (type, interests, city), so you
  have what you need to pick their 2-3 locals.
- If they chose a city other than Shanghai, the screen tells them you are starting in Shanghai.

## Your matching worklist
In Supabase open **Table Editor > leads** (it is a view). It lists everyone who sent a request,
newest first, with **reply_by** (3 days after they sent it), their contact, dates, type, interests
and city. The view is private: the public key cannot read it.

To track progress, open the **sessions** table and change `lead_status` on the row
(new / contacted / matched / closed). Later saves from the visitor never overwrite it.

    -- requests still waiting for a reply, most urgent first
    select reply_by, contact_method, contact, trip_start, trip_end, interests
    from leads where lead_status = 'new' order by reply_by;

## Reading the answers
In Supabase open **Table Editor > sessions**. Use the export button for CSV.
One row per visitor, overwritten on every screen change after onboarding.
The `stage` column shows how far they got. "Restart demo" starts a new row.

Handy queries (SQL Editor):

    -- how far did people get?
    select stage, count(*) from sessions group by stage order by count(*) desc;

    -- what did people choose on the commitment screen?
    select commit_choice, count(*) from sessions group by commit_choice;

## How it is locked down
- The `sessions` table has row level security on and no policies, so the public key
  cannot read or write it directly.
- The only thing the public key can do is call `save_session()`, which checks every field
  and saves one row. Nobody can read anyone else's answers with it.
- Rows are found by a random id in the visitor's browser, so a visitor can only overwrite
  their own row unless they know someone else's id.

## Known limits
- **Free projects pause after 7 days with no activity.** Data is kept, but saves fail until
  you click Restore in the Supabase dashboard. The demo itself keeps working.
- Nothing stops someone from spamming `save_session()`. Fine for a small test.
- The contact is stored as plain text in your Supabase project. Only people with access to your
  project can read it, but treat it as personal data: decide how long you keep it and delete rows
  when you no longer need them.
- The screen says "We'll contact you only about your matches." Change that line in `docs/app.js`
  if it is not what you will do.
- The commit screen's "we'll message you" now has a contact to use, but only for visitors who sent a request.
- Free database limit is 500 MB. Each row is well under 1 KB.
