# Kantoi email code service

Sends the 6-digit sign-up code from the Kantoi Gmail account, for free, with no password stored anywhere. It is a Google Apps Script web app that runs as that account.

## Set up (about 5 minutes, once)

1. Sign in to Google as the Kantoi sender account (kantoi.noreply@gmail.com).
2. Open https://script.google.com and create a new project named **Kantoi OTP**.
3. Replace the contents of `Code.gs` with the file in this folder.
4. In the function menu at the top choose **setupKeys** and press **Run** (allow the permissions). It creates `APP_KEY` and `PROOF_KEY` and prints `APP_KEY` in the Execution log.
5. Deploy > New deployment > type **Web app**. Execute as **Me**, Who has access **Anyone**. Deploy and allow the Gmail permission when asked.
6. Copy the web app URL (ends in `/exec`).
7. Add two GitHub repository secrets:
   - `OTP_URL`: the web app URL.
   - `OTP_APP_KEY`: the same value as `APP_KEY`.

The build passes both to the app. No Gmail password or App Password is needed; you can revoke any App Password you created.

## Limits

- A personal Gmail account can send about 100 emails a day from Apps Script.
- One code per address per minute, five per hour, five wrong tries per code, codes expire after 10 minutes.
- After a correct code the service returns a signed proof (`PROOF_KEY`) that a server (Firebase, next version) can check.

## Updating

After changing `Code.gs`, use Deploy > Manage deployments > Edit > New version, so the URL stays the same.
