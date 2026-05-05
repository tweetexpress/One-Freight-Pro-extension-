# ONE Freight Pro TODO

## Shared Ledger

- Add Supabase as the shared email/load ledger backend.
- Store every email log entry from all installed machines in one database.
- Include user or machine name, timestamp, mode, template, offer amount, and full Copy Load fields.
- Add sync status in the extension so dispatchers can see whether a log was saved locally only or synced to Supabase.
- Keep local Edge storage as an offline backup queue, then sync pending entries when online.

## Truck Routing, Miles, And Tolls

- Evaluate HERE Routing API for truck-safe routing.
- Support truck dimensions/weight where possible.
- Pull accurate route miles and deadhead miles from the API.
- Add toll estimate to the ONE Freight Pro calculator as a cost input.
- Keep Google Maps as a fallback/open-map link.
- Do not store paid API keys directly in the browser extension; use a small backend/API proxy.

## Calculator And Driver Pay Presets

- Add customizable driver pay preset groups by pay mode.
- Flat pay presets: allow user-defined amounts such as `$300`, `$325`, `$350`.
- Per-mile presets: allow user-defined CPM values such as `$0.55/mi`, `$0.60/mi`, `$0.65/mi`.
- Daily pay presets: allow user-defined daily rates and default driver-day counts.
- Percent pay presets: allow user-defined percentages for revenue share.
- Show only the presets that match the selected driver pay mode.
- Store presets locally at first, then sync them across machines with Supabase when the shared settings backend is added.
- Keep manual entry available even when presets exist.

## Gmail API Sending

- Add Gmail API as the long-term replacement for the Outlook desktop helper.
- Use one configured business sender account for ONE Freight Pro.
- Support fast draft creation first, then true background send for Money Mode.
- Set up Google OAuth consent, Gmail API credentials, and the minimum required Gmail scopes.
- Keep email template, subject, body, recipient, and load-log behavior consistent with the current Outlook workflow.
- Add a provider setting: Outlook Desktop, Gmail Web Compose, or Gmail API.
- Avoid storing Google client secrets directly in the browser extension; use a backend/API proxy if needed.

## Preferred Broker Routing

- Sync preferred broker rules across machines with Supabase once the shared ledger backend exists.
- Add optional Google Chat routing for brokers who prefer chat over email.
- Add a future "preferred contact by lane" option for brokerages where the best contact changes by region or customer.

## Rate Confirmation Analyzer

- Add a Gmail-based rate confirmation workflow after Gmail API is connected.
- Detect rate confirmation emails and attachments from the configured dispatch inbox.
- Parse common PDF/email fields: load number, broker, route, rate, miles, pickup date, delivery date, addresses, and notes.
- Store analyzed rate confirmations in the shared Supabase ledger.
- Add a dashboard/table view with filters for load number, broker, and address.
- Link analyzed rate confirmations back to saved/opened loads when origin, destination, broker, or reference ID match.
- Keep this separate from booking outreach templates; it is a post-booking document tracking feature.
