# Proposal: a simpler UI — keep the workspace, compact the lists

Documentation only. No code changes in this PR.

## Why

The current layout makes one job live in several places at once, and the home
page grows without bound:

- A search run can return up to 20 matches, and every match renders as a full
  card — cover letter included. Twenty results become twenty stacked letters
  and a page that scrolls for screens.
- Prepared results from a run sit on the Jobs page, while the rest of the
  application lifecycle lives under Applications. The same job shows up as
  different cards in different rooms.
- Counts do not always count what is on screen: the Applications badge counts
  pending reviews, and approved cards pinned into the review queue (PR #16)
  are held in session state, so they vanish on reload.

This proposal keeps the existing structure and visual identity, and changes
only layout and hierarchy.

## Principles

- **Keep the tabs, the look — and the two-panel workspace.** Navigation stays
  a small set of tabs (renamed Jobs / Applications / Companies / Profile).
  Colors, fonts, and components are unchanged. Each main page keeps the
  app's current frame: a left rail of intent and stable context, and a right
  panel where the work happens. The redesign compacts what is *inside* the
  panels; it does not flatten pages into single-column feeds.
- **Separate the list from the detail.** Lists are compact rows; the full
  detail exists for one item at a time.
- **Sections derive from application status only.** Status and pipeline stage
  are different things and stay separate (below).
- **Counts are honest by construction.** Every section header counts exactly
  the items in that section.
- **Human language on screen.** Statuses render as labels a person would say,
  never as raw internal strings.
- **Reuse the controls that exist.** No duplicate buttons; each item keeps the
  actions it already has.

## The frame: two panels on every main page

The current home already has the right shape: a two-column workspace. The
left rail holds what the user tells the agent and who the agent is working
for — the brief, the specific-job box, the profile summary. The right panel
holds what the agent produced. That contract is what makes the page feel
calm: controls don't move, results land in one place.

The length problem was never the frame. It is what gets stacked inside the
right panel: profile summary, a raw log console, every prepared application
as a full card, then every match again as a full article. This proposal keeps
the frame and gives the panels internal structure:

- **The left rail is sticky.** It stays in reach while the right panel
  scrolls — the page scrolls the work, not the tools. The rail holds stable
  context only: profile summary, the brief, recent runs.
- **The right panel is output only.** The profile summary moves out of it
  into the rail. Run progress becomes one slim status strip at the top of
  the panel (current step + counts), with the full log behind a Details
  toggle, so the panel reads as results, not as a terminal.
- **Inside the panel, work is sectioned** by what needs the user, with slim
  rows and one expanded detail at a time (below). On narrow screens the
  existing one-column collapse still applies: rail first, then work.

## The design

### Home (Jobs)

- **Left rail:** a "You" card with the profile summary and skills; the brief;
  "Apply to a specific job"; recent runs. Before the first run the brief is
  fully open and the profile card waits on a resume. Once a run exists, the
  brief collapses to a one-line summary with an Edit button, so the rail
  stays short.
- **Right panel:** the status strip, then a segmented toggle — **Prepared**
  (the actionable queue, the default) and **All matches** — instead of two
  stacked lists that duplicate the prepared jobs. Prepared work is sectioned
  by status: **Needs review**, **Filled — ready to submit**, **Applied**,
  each header counting its own section.
- Search results under All matches are the same compact rows as everywhere
  else (below).

At scale — a broad search can match a few hundred jobs — the All matches
list never grows the page: it scrolls inside the right panel under its
pinned header and loads ten rows at a time behind a Show more control. A
summary line (total matches, top score, how many are new) plus a filter box
and a New-only chip sit above the rows, so the shape of the result set is
clear before a single row is read.

### Compact rows, detail on demand

Match results and application lists render as one-line rows:

- job title, company
- match score (on match rows) and posted date
- a human-readable status pill ("Needs review", "Applied", …)
- **one** primary action for the item's state (Review, Fill form in browser, …)

The detail — match reasons, the cover letter in the existing dark letter box,
and the item's existing actions (Approve / Save letter / Skip; after approval,
Fill form in browser / Mark submitted / Edit cover letter) — expands in place
for one item at a time.

This is the fix for the long page: 20 results are 20 rows, and the cover
letter — the thing that makes a card huge — is only ever on screen once.

### Applications

The live run / "Applications prepared" run view moves out of Jobs and into
the Applications tab, so Jobs is for finding matches and Applications holds
everything from prepared onward.

Applications is organized into sections, each header counting its own
section:

- **Needs review**
- **Approved — ready to submit**
- **Filled — awaiting your submit**
- **Applied**
- **Skipped**

Membership is a pure function of application status, so it survives reloads:

- Approving an item moves it from **Needs review** to **Approved — ready to
  submit**. (This replaces the session-only pinned-cards behavior from PR #16
  with state the user can navigate away from and come back to.)
- When a submission confirmation is detected (PR #18), the item moves to
  **Applied** on its own and leaves Forms to submit.

### Status and stage stay separate

The redesign does not merge application status with the tracker's pipeline
stage:

- Sections and queues derive only from application status.
- The pipeline stage (Reply / Screen / Interview / Offer / Rejected /
  Ghosted) remains a manual dropdown on **Applied** items, moved only by the
  user. The app cannot observe interviews, so it never infers stage progress,
  and there is no follow-up-due feature.

### Companies

Companies gets the same frame, using only what the page already does:

- **Left rail:** the add-company form (name, careers page, or job link) and
  an "At a glance" summary — how many of the tracked companies are searched
  on every run, open jobs at last search, how many the user added, how many
  need attention. These are the numbers the page already computes for its
  summary line, given a permanent home.
- **Right panel:** the filter box and the four views that already exist —
  All / Added by you / Needs attention / Turned off — as a segmented control,
  then one slim row per company: name, ATS, open-job count when the board is
  working, and a status pill in human words (Working / Board gone / Not
  responding / Not searched yet / Off). Each row keeps its existing actions:
  Turn off / Turn on, and Remove on companies the user added.

### Profile

Profile gets the same frame:

- **Left rail:** identity — name, target titles, locations — and the resume
  summary with skills. This is the same "You" card as the home rail, so the
  stable context looks identical wherever it appears. The rail also carries
  the page's existing note: uploading a resume on a run refreshes the
  profile, and edits here are kept until the next run.
- **Right panel:** the profile form, with the fields it already has, followed
  by **Application answers** and **Other saved answers** as today.
- **The answer bank gets a coverage meter.** The Application answers section
  header counts how many of the nine standard questions are answered, with a
  simple bar under it. Blanks are marked "Not answered" instead of rendering
  as empty fields, because a blank is exactly what gets flagged for the user
  on every form. The meter uses only data the page already loads; it is the
  one deliberate addition carried over from this proposal's earlier draft.

### Previously applied

The "Previously applied" list and the seen-records behind it are existing
behavior; this redesign does not change them.

## Screens

Sample data throughout; rendered in the app's current visual scheme, in the
order a user moves through the app.

### Home — before the first run

![Home — before the first run: full brief open in the left rail, profile waiting on a resume, right panel idle with the ready-to-run checklist](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-home-panels-empty.png)

### Home — Jobs

![Home — Jobs in the two-panel frame: left rail with profile, collapsed brief, specific-job box, and recent runs; right panel with status strip, Prepared / All matches toggle, and status sections with one letter expanded](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-home-panels.png)

### Home — All matches at scale

![Home — All matches at 200 results: filter box and New-only chip over a summary line, ten compact rows in the panel's own scroll area, "Showing 10 of 200" with Show more](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-home-matches.png)

### Applications — status sections

![Applications: status sections with counts, compact rows, manual stage dropdown on an applied job](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-applications.png)

Clicking an application expands its detail in place. Here, one application
in "Filled — awaiting your submit" is expanded: the form-fill summary, the
two questions that still need the user — named, not just counted — and Mark
submitted as the primary action.

![Applications — one application expanded in "Filled — awaiting your submit": form-fill summary, the two named needs-you questions, Mark submitted primary](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-applications-expanded.png)

### Companies

![Companies: add form and at-a-glance summary in the left rail; filter, view tabs, and slim company rows with status pills in the right panel](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-companies.png)

### Profile

![Profile: identity and resume summary in the left rail; profile fields, the answer bank with its coverage meter at 7 of 9, and other saved answers in the right panel](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-profile.png)

## Non-goals

- No unified, stage-filtered single list; matches and applications stay
  separate lists in their separate tabs.
- No flattening of the two-panel frame into single-column pages.
- No new backend data. In particular there is no salary anywhere in the data,
  and no match-data join is needed, because match rows and application rows
  stay separate.
- No visual identity change.
- No changes to pre-fill delivery, the never-submit rule, or hosted/local
  behavior.
