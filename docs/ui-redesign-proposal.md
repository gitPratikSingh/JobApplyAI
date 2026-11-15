# Proposal: a simpler UI — compact lists, one detail at a time

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

- **Keep the tabs and the look.** Navigation stays a small set of tabs
  (renamed Jobs / Applications / Companies / Profile). Colors, fonts, and
  components are unchanged — this is layout, not a rebrand.
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

## The design

### Home (Jobs)

- The "brief the agent" panel collapses to a slim bar. Run progress is one
  thin status line (e.g. "Run complete — 20 matches") instead of a scrolling
  live log on the page.
- A **"Needs you"** summary strip shows exactly two queues, as counts:
  **Needs review** and **Forms to submit**. Selecting one navigates to that
  work in Applications; the home page shows the counts, not the cards.
- Search results are compact rows (see below).

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

### Previously applied

The "Previously applied" list and the seen-records behind it are existing
behavior; this redesign does not change them.

## Screens

Sample data throughout; rendered in the app's current visual scheme.

### Home — Jobs

Before any run, the home is an empty state: the brief panel is open,
both queues sit at zero, and the results area shows "No matches yet" with a
short ready-to-run checklist.

![Home — empty state before the first run: brief panel open, queues at zero, "No matches yet" with the ready-to-run checklist](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-home-empty.png)

After a run, the same home carries the results: compact rows, with one
item's detail expanded in place.

![Home — Jobs: slim run bar, Needs you counts, compact match rows with one expanded detail](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-home.png)

### Applications — status sections

![Applications: status sections with counts, compact rows, manual stage dropdown on an applied job](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-applications.png)

Clicking an application expands its detail in place. Here, one application
in "Filled — awaiting your submit" is expanded: the form-fill summary, the
two questions that still need the user — named, not just counted — and Mark
submitted as the primary action.

![Applications — one application expanded in "Filled — awaiting your submit": form-fill summary, the two named needs-you questions, Mark submitted primary](https://raw.githubusercontent.com/gitPratikSingh/JobApplyAI/docs/ui-redesign-proposal/docs/mockups/jobapplyai-redesign-mockup-applications-expanded.png)

## Non-goals

- No unified, stage-filtered single list; matches and applications stay
  separate lists in their separate tabs.
- No new backend data. In particular there is no salary anywhere in the data,
  and no match-data join is needed, because match rows and application rows
  stay separate.
- No visual identity change.
- No changes to pre-fill delivery, the never-submit rule, or hosted/local
  behavior.
