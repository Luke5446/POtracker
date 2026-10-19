# POtracker

A single page, `index.html`, served by GitHub Pages. The buyer opens it with
`?edit` on the address, pastes the PO_Tracker query each day and presses
**Publish for team**; everyone else opens the plain address and sees the last
published data.

## Publishing

**Publish for team** writes the plan to `data.json` in this repo, which the
viewers read, in one of two ways:

- **Straight from the page**: the editor's PC holds a GitHub token and
  Publish puts the file into the repo itself. The team sees it within a
  minute.
- **By hand**: with no token on the PC, Publish downloads `data.json` to
  upload to the repo and commit, as before. Publish falls back to this,
  saying why, if GitHub refuses the token.

To set up the token once, on the publishing PC: on GitHub, **Settings →
Developer settings → Personal access tokens → Fine-grained tokens**, either
generate a new token (name it "Tibard PO tracker", expiry one year) or edit
the token the stock planner uses and add this repo to it. Under
**Repository access** tick `POtracker`; under **Permissions → Repository
permissions** set **Contents: Read and write**. Copy the token (shown once),
then in the page with `?edit` press **Set up this PC** and paste it. The
button changes to **Token**; pressing it again with an empty box removes it.
A token that can write this repo can change anything in it, so keep it to
the one PC that publishes.

A PC that opens the editor without pasting every day takes the published
data whenever it is newer than its own paste; **Clear saved data** in
Settings forgets the PC's paste and reloads the published data.

## Container delays

The **Container delays** tab is for the sales office: the Tibard sales order
lines that cannot go out from the shelf and are waiting on a container, with
the date they can go out.

- The containers come from the stock planner's published plan
  (`Tibard-Stock-Planner/data.json` on GitHub Pages, read when the page
  opens): each live container or air freight, the day it lands at Tibard and
  what is on it. The sales orders are the production planner's published
  SOPDemand paste when that is newer than this page's paste (it is pasted
  most mornings, so the two agree), otherwise this page's own paste; the
  foot of the tab says which.
- For each code on a container, the stock on the shelf (Home + Bulk, as the
  stock planner holds it) covers the oldest promised date first, then each
  container in landing order covers what is left, the same way the
  production planner works out who covers each order.
- The new date is **one working day after the container lands** (weekends
  and England & Wales bank holidays skipped). A line whose promised date is
  already on or after that is shown as **Date OK**; one that no container
  covers is **Not on a container**, with the next container order date.
- Oliver Harvey orders for Tibard stock appear as the intercompany Tibard
  line, with the OH sales order number beneath the customer where Sage links
  them.
- **Export date changes** downloads the lines needing a new date as a CSV
  (SO number, line, code, customer, outstanding, container, promised and new
  dates); **Export all** downloads every line on the tab. Sage 200 has no
  standard import that changes promised dates on existing orders, so the file
  is a worklist for the sales office until one is set up.
