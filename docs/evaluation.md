# Evaluation of Kantoi's built-in checks

Kantoi's verdict combines on-device rules, link forensics and an optional AI explanation. This page measures the part that always runs: the **built-in engine with the network and AI switched off**, so the numbers are repeatable on any machine.

## How to run it

From the `app` folder:

```sh
dart run tool/evaluate.dart                                   # synthetic Malaysian set (tuning set)
dart run tool/evaluate.dart --csv test/data/holdout_messages.csv   # held-out set
dart run tool/evaluate.dart --uci path/to/SMSSpamCollection   # UCI SMS Spam Collection
dart run tool/evaluate.dart --errors-at 18                    # list mistakes at another threshold
dart run tool/explain.dart "message text"                     # see why one message scored what it did
```

The UCI SMS Spam Collection is not bundled (this build environment cannot download it). Download it from <https://archive.ics.uci.edu/dataset/228/sms+spam+collection>, unzip it and pass the `SMSSpamCollection` file (one message per line, `ham` or `spam`, a tab, then the text). Expect lower recall there: it is 2000s UK SMS spam, which Kantoi's Malaysia-focused rules were not written for.

The test `test/branches_test.dart` runs the same evaluation and fails if precision or recall at the "Suspicious" threshold drops below the agreed floor.

## Data

Both sets are synthetic messages written for this project, modelled on common Malaysian scams and on real genuine notifications. They contain no real personal data.

| Set | File | Messages | Scam | Genuine | Languages |
| --- | --- | --- | --- | --- | --- |
| Tuning | `app/test/data/labelled_messages.csv` | 90 | 50 | 40 | English, Malay, Manglish |
| Held out | `app/test/data/holdout_messages.csv` | 32 | 18 | 14 | English, Malay, Manglish |

Scam types: parcel fee, bank phishing, fake officer (Macau), investment, job task, love, "new number" impersonation, prize, upfront-fee loan, utility bill, account takeover (OTP), government impersonation, crypto, AI prompt injection. Genuine types: bank TAC/OTP, bank notices, couriers, government, friends, family, work, merchants, security codes.

Columns: `label` (`scam` or `legit`), `lang`, `type`, `text`.

## Thresholds

A message is counted as flagged when its risk score is at or above the threshold. Kantoi's labels use 18 ("Be careful"), 40 ("Suspicious") and 65 ("Very likely a scam").

### Tuning set, before rule changes

| Threshold | Precision | Recall | F1 | TP | FP | TN | FN |
| --- | --- | --- | --- | --- | --- | --- | --- |
| >= 18 | 95.9% | 94.0% | 94.9% | 47 | 2 | 38 | 3 |
| >= 40 | 100.0% | 80.0% | 88.9% | 40 | 0 | 40 | 10 |
| >= 65 | 100.0% | 24.0% | 38.7% | 12 | 0 | 40 | 38 |

### Tuning set, after rule changes

| Threshold | Precision | Recall | F1 | Accuracy | TP | FP | TN | FN |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| >= 10 | 86.2% | 100.0% | 92.6% | 91.1% | 50 | 8 | 32 | 0 |
| >= 18 | 96.2% | 100.0% | 98.0% | 97.8% | 50 | 2 | 38 | 0 |
| >= 30 | 98.0% | 98.0% | 98.0% | 97.8% | 49 | 1 | 39 | 1 |
| >= 40 | 100.0% | 96.0% | 98.0% | 97.8% | 48 | 0 | 40 | 2 |
| >= 50 | 100.0% | 68.0% | 81.0% | 82.2% | 34 | 0 | 40 | 16 |
| >= 65 | 100.0% | 28.0% | 43.8% | 60.0% | 14 | 0 | 40 | 36 |

Confusion matrix at >= 40 ("Suspicious"):

|  | Predicted scam | Predicted genuine |
| --- | --- | --- |
| Actual scam | 48 | 2 |
| Actual genuine | 0 | 40 |

These numbers are optimistic because the rules were adjusted while looking at this set.

### Held-out set (written after tuning, never tuned on)

| Threshold | Precision | Recall | F1 | Accuracy | TP | FP | TN | FN |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| >= 10 | 84.2% | 88.9% | 86.5% | 84.4% | 16 | 3 | 11 | 2 |
| >= 18 | 93.8% | 83.3% | 88.2% | 87.5% | 15 | 1 | 13 | 3 |
| >= 30 | 100.0% | 77.8% | 87.5% | 87.5% | 14 | 0 | 14 | 4 |
| >= 40 | 100.0% | 66.7% | 80.0% | 81.3% | 12 | 0 | 14 | 6 |
| >= 50 | 100.0% | 38.9% | 56.0% | 65.6% | 7 | 0 | 14 | 11 |
| >= 65 | 0.0% | 0.0% | 0.0% | 43.8% | 0 | 0 | 14 | 18 |

Confusion matrix at >= 40:

|  | Predicted scam | Predicted genuine |
| --- | --- | --- |
| Actual scam | 12 | 6 |
| Actual genuine | 0 | 14 |

**This is the honest number to quote:** when the built-in checks say "Suspicious" or worse they were right every time, but they caught about two in three scams on their own. Counting "Be careful" as a warning, they caught five in six with one false alarm in fourteen genuine messages. The AI explanation and live link checks (both off here) add to this in the app.

## What was changed after the first run

1. **Chat links no longer count as "official".** A `wa.me` or `t.me` link is on an official WhatsApp or Telegram domain, but it opens a chat with anyone, so it was wrongly lowering the risk of job and investment scams by 18 points. `investigator.dart` now ignores the "Official website" signal for `wa.me`, `t.me`, `chat.whatsapp.com`, `api.whatsapp.com` and `m.me`.
2. **Investment pitch plus a payment request** gets a combination bonus (+8), like the existing romance plus investment bonus.
3. New or widened rules in `cues.dart`:
   - "forward the 6 digit code" (spaced digit count) now counts as asking for your code.
   - "keep our love secret" now counts as secrecy.
   - Pay a fee first to get a loan or prize (English and Malay).
   - Instant loan with no checks ("tanpa dokumen", "no CTOS", "approved in 30 minutes").
   - Friendly "wrong number" opener that turns into "can we be friends".
   - Asks you to install an app from a link, or any `.apk` link.

All existing engine tests still pass. No genuine message in either set reaches "Suspicious".

## Known misses (held-out set, score in brackets)

- [0] "Telegram security: ... Send us the login code you just received" (the word "login" between "the" and "code" is not covered).
- [0] "Kerja online hanya like video YouTube, gaji RM200 sehari" (Malay job-scam wording not covered).
- [15] A stranded-traveller love scam asking for money by Western Union.
- [24] "Simple tasks from home, earn RM150 to RM500 a day" (a range is not matched).
- [30] "AI trading robot gives 8% daily return, fully guaranteed".
- [36] A polite Pos Malaysia address-confirmation message with a fee and a look-alike link.

## Known false alarms

- Genuine JPJ and LHDN notices score "Be careful" (18 to 30) because naming an agency is an authority cue. They never reach "Suspicious".
