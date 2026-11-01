# Evaluation of Kantoi's built-in checks

Kantoi's verdict combines on-device rules, link forensics and an optional AI explanation. This page measures the part that always runs: the **built-in engine with the network and AI switched off**, so the numbers are repeatable on any machine.

## How to run it

From the `app` folder:

```sh
flutter test test/eval_report_test.dart    # prints the tables below for all three sets
```

The engine loads its data through Flutter, so the older `dart run tool/evaluate.dart` scripts cannot start on their own (they stop with "dart:ui is not available"). The test above runs the same evaluation inside the Flutter test runner.

To score the UCI SMS Spam Collection, download it from <https://archive.ics.uci.edu/dataset/228/sms+spam+collection> and call `parseUciSms` and `evaluate` from `lib/engine/evaluation.dart` in a test the same way. Expect lower recall there: it is 2000s UK SMS spam, which Kantoi's Malaysia-focused rules were not written for.

The test `test/branches_test.dart` runs the same evaluation and fails if precision or recall at the "Suspicious" threshold drops below the agreed floor.

The scam similarity thresholds are set with `python tool/sim_calibrate.py test/data/labelled_messages.csv test/data/holdout_messages.csv`. The script refuses the v2 set.

## Data

All sets are synthetic messages written for this project, modelled on common Malaysian scams and on real genuine notifications. They contain no real personal data.

| Set | File | Messages | Scam | Genuine | Languages |
| --- | --- | --- | --- | --- | --- |
| Tuning | `app/test/data/labelled_messages.csv` | 90 | 50 | 40 | English, Malay, Manglish |
| Held out (v1) | `app/test/data/holdout_messages.csv` | 32 | 18 | 14 | English, Malay, Manglish |
| Held out (v2) | `app/test/data/holdout_v2_messages.csv` | 44 | 24 | 20 | English, Malay, Manglish |

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

**This was the honest number at the time (see the November 2026 update below for the current one):** when the built-in checks say "Suspicious" or worse they were right every time, but they caught about two in three scams on their own. Counting "Be careful" as a warning, they caught five in six with one false alarm in fourteen genuine messages. The AI explanation and live link checks (both off here) add to this in the app.

## November 2026 update: wording, similarity, page reading, community

### What changed

1. **Scam similarity** (`lib/engine/forensics/scam_similarity.dart`). The wording is compared with 67 scam and 45 genuine reference messages (`scam_corpus.dart`, written for Kantoi, none copied from the test sets) using character 3 to 5 grams, TF-IDF and cosine similarity. It counts only when the nearest scam is at least 25% similar and at least 15 points closer than the nearest genuine message. On the tuning set and held-out v1 together, 44 of 68 scams pass and 0 of 54 genuine messages do (the closest genuine message is 11.9 points closer to a scam, under the 15-point margin). Weight 8 to 22, new category "Matches known scam wording".
2. **Spaced-out letters.** "O T P" or "b.a.n.k" is read as one word before the rules run, and flagged as disguised spelling.
3. **New wording rules** in `cues_extra.dart`: trading robots; "x% a day" returns; task-job pay ranges ("RM150 to RM500 a day") and same-day pay; paid to like videos or review; Western Union and MoneyGram; pay a fee first; asks for your online banking ID and password; renting out your bank account (money mule); a code "sent to your phone" with a request to send it; threats to cut off an account or service; reward points expiring today with a redeem link.
4. **Landing page reading** (`landing_page.dart`, live link checks only, so not measured here): scripts that post to a Telegram bot, Discord webhook or form service; logos loaded straight from a real bank's site; blocked right-click or scrambled script; countdown timers; cleaner visible text (comments removed, entities decoded).
5. **Community reports** (`lib/engine/community/community.dart`, needs Firebase and an account, so not measured here): reports from other users on the same website, number, account, wallet or email, scored with recency weights and a three-reporter minimum.

### Held-out v2: before and after (the number to quote)

`holdout_v2_messages.csv` was written **before** any of these changes and was never used to set a rule or threshold. One caveat: it was written by the same author as the rules, so it is less independent than data collected from real users.

| Threshold | Before: precision | Before: recall | After: precision | After: recall |
| --- | --- | --- | --- | --- |
| >= 18 ("Be careful") | 88.9% | 100.0% | 88.9% | 100.0% |
| >= 30 | 88.5% | 95.8% | 88.9% | 100.0% |
| >= 40 ("Suspicious") | 95.2% | 83.3% | 96.0% | **100.0%** |
| >= 50 | 100.0% | 58.3% | 100.0% | 95.8% |
| >= 65 ("Very likely a scam") | 100.0% | 25.0% | 100.0% | 45.8% |

Confusion matrix at >= 40:

|  | Before: scam | Before: genuine | After: scam | After: genuine |
| --- | --- | --- | --- | --- |
| Actual scam (24) | 20 | 4 | 24 | 0 |
| Actual genuine (20) | 1 | 19 | 1 | 19 |

Scams missed before and caught after: renting out your bank account (mule recruitment), "a 6-digit code got sent to your phone" (e-wallet takeover), a concert ticket sale paid by bank transfer, and a crypto "recovery team" with an upfront fee. The one false alarm is the same before and after: a friend asking "can tf me RM20 for the mamak, I pay you back tmr" (score 48). A small money request from a friend reads like the hijacked-account script; a known contact list would fix it, and the app's live chat check already knows who the sender is.

### Tuning set and held-out v1 after the update

These two sets are no longer clean tests: the update was written knowing their misses (the v1 job scams with pay ranges and "like video" wording, now caught). They are shown only to confirm nothing got worse.

| Set | Threshold | Before: precision / recall | After: precision / recall |
| --- | --- | --- | --- |
| Tuning (90) | >= 40 | 100.0% / 98.0% | 100.0% / 100.0% |
| Tuning (90) | >= 65 | 100.0% / 42.0% | 100.0% / 54.0% |
| Held out v1 (32) | >= 40 | 100.0% / 88.9% | 100.0% / 100.0% |
| Held out v1 (32) | >= 65 | 100.0% / 22.2% | 100.0% / 38.9% |

No genuine message in the tuning set or v1 reaches "Suspicious", before or after.

## Earlier history

The sections below record the first evaluation and the first round of changes. The "before" columns above are the code as of v1.1.0, which already included those changes.

### What was changed after the first run

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

### Known misses at the time (held-out v1, score in brackets, all fixed since)

- [0] "Telegram security: ... Send us the login code you just received" (the word "login" between "the" and "code" is not covered).
- [0] "Kerja online hanya like video YouTube, gaji RM200 sehari" (Malay job-scam wording not covered).
- [15] A stranded-traveller love scam asking for money by Western Union.
- [24] "Simple tasks from home, earn RM150 to RM500 a day" (a range is not matched).
- [30] "AI trading robot gives 8% daily return, fully guaranteed".
- [36] A polite Pos Malaysia address-confirmation message with a fee and a look-alike link.

## Known false alarms (current)

- Genuine JPJ and LHDN notices score "Be careful" (18 to 30) because naming an agency is an authority cue. They never reach "Suspicious".
- A friend asking for a small transfer with "I pay you back tmr" (held-out v2) reaches "Suspicious" (48).
