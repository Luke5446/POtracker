# POtracker

A single page, `index.html`, served by GitHub Pages. The buyer opens it with
`?edit` on the address, pastes the PO_Tracker query each day and presses
**Publish for team**; everyone else opens the plain address and sees the last
published data.

## Container delays

The **Container delays** tab is for the sales office: the Tibard sales order
lines that cannot go out from the shelf and are waiting on a container, with
the date they can go out.

- The containers come from the stock planner's published plan
  (`Tibard-Stock-Planner/data.json` on GitHub Pages, read when the page
  opens): each live container or air freight, the day it lands at Tibard and
  what is on it. The sales orders are this page's own paste.
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
