# One 'Next' button for orders
Status: done

Replace the separate Mark confirmed/preparing/ready/out-for-delivery buttons with one primary "Next: <status>" button. Keep every status.

Use `nextOrderStatus` (the employee dashboard already uses it).

## Notes
- Order detail and the employee dashboard already showed one advancing button, labelled "Mark <status>". Both now use a shared `NextOrderButton` (in `order_detail_screen.dart`), labelled "Next: <status>".
- The delivered step still opens Deliver & Collect. Cancel, assignment and the delivery-staff "Deliver" button are unchanged. No domain or use-case changes.
