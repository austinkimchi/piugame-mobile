# Browser extension feasibility

## Decision

Keep the extension track. Do not attempt the same feature from ordinary MyPIU page JavaScript.

A Manifest V3 extension can make cross-origin requests from its service worker when the user grants host permissions for the PIUGAME origins. A MyPIU content script can request a sync, parse returned HTML in its isolated DOM context, and submit normalized data to the same-origin MyPIU API using the user's existing MyPIU session.

## Minimal permissions

- `https://www.piugame.com/*`
- `https://phoenix.piugame.com/*`
- `https://mypiu.austin.kim/*`
- `activeTab` for a user-initiated toolbar action

The extension must not request `<all_urls>`, capture PIUGAME passwords, or export PIUGAME cookies. Users sign into PIUGAME in the browser normally; the extension reuses that browser session.

## Flow

1. The user opens MyPIU and chooses **Sync from this browser**.
2. The MyPIU content script asks the extension service worker for PIUGAME pages.
3. The service worker fetches PIUGAME with `credentials: include` under explicit host permission.
4. The content script parses the pages and posts normalized DTOs to MyPIU.
5. If PIUGAME returns a login page, the extension opens the appropriate PIUGAME sign-in page and asks the user to retry.

## Limits

- Chrome service workers are suspended when idle, so reliable high-frequency background polling is not a product promise.
- Browser cookie and site-access settings can prevent session reuse.
- Safari requires the Web Extension to be packaged in an Apple app and the user must grant website access.
- Markup changes still require extension updates.

The extension is therefore a user-initiated fast refresh for desktop web users. The native app is the preferred recurring sync client.
