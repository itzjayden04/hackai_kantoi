/// Reference messages for the scam similarity check. Written for Kantoi from
/// the common Malaysian scam scripts (PDRM, BNM and NSRC public advisories),
/// in English, Malay, Manglish and Chinese. None are copied from the test
/// sets in test/data, so the evaluation stays honest.
///
/// Each scam entry is (scam type, text). The genuine entries are everyday
/// messages that share words with scams (bank alerts, codes, deliveries,
/// family money talk), so a scam has to look like a scam, not just mention
/// money, to score.
library;

const scamCorpus = <(String, String)>[
  // Parcel and courier fees
  ('Parcel scam', 'Your parcel could not be delivered because the address is incomplete. Update your details and pay the redelivery fee of RM2.80 here'),
  ('Parcel scam', 'Notice: your package is on hold at the warehouse. A customs charge of RM4.50 is unpaid. Pay now to avoid the item being returned to sender'),
  ('Parcel scam', 'Bungkusan anda tidak dapat dihantar kerana alamat tidak lengkap. Sila kemaskini alamat dan bayar caj RM1.90 dalam masa 12 jam'),
  ('Parcel scam', 'Final attempt: we tried to deliver your shipment today. Confirm your address and settle the small handling fee at the link before it is returned'),
  ('Parcel scam', '您的包裹因地址不完整无法派送，请在24小时内点击链接更新地址并支付RM2.50手续费'),
  // Bank phishing and account threats
  ('Bank phishing', 'Your bank account has been temporarily suspended due to suspicious activity. Verify your identity at the link to restore access'),
  ('Bank phishing', 'Dear customer, your online banking access will expire today. Reactivate now by logging in at the secure link below'),
  ('Bank phishing', 'Akaun bank anda telah disekat kerana aktiviti mencurigakan. Sila log masuk melalui pautan ini untuk mengaktifkan semula akaun anda'),
  ('Bank phishing', 'A transaction of RM2,890.00 was made from your account. If this was not you, cancel it now at the link and enter your TAC to confirm'),
  ('Bank phishing', 'Your debit card has been blocked. To unblock, update your card number, expiry and CVV within 24 hours'),
  ('Bank phishing', 'Security alert: new device login detected. Secure your account immediately by verifying your details here'),
  ('Bank phishing', 'Your e-wallet will be frozen unless you complete identity verification today. Tap the link and enter your PIN'),
  // Account takeover and code theft
  ('Account takeover', 'Hi, I accidentally sent my verification code to your number. Could you forward it to me? It is urgent'),
  ('Account takeover', 'Sorry ah wrong number key in, got 6 digit code sent to your phone, can screenshot send me back?'),
  ('Account takeover', 'This is the support team. Your account is being deactivated. Reply with the 6 digit code we sent to keep it active'),
  ('Account takeover', 'Eh tolong bagi kod 6 digit yang masuk phone you tadi, I tersilap letak nombor you'),
  ('Account takeover', 'Join the group vote for my niece, just click the link and enter the code you receive by SMS'),
  // Fake officer (Macau)
  ('Fake officer (Macau) scam', 'This is the police. Your identity card was used to open a bank account involved in money laundering. Do not tell anyone. Transfer your savings to a safe account for investigation'),
  ('Fake officer (Macau) scam', 'Saya pegawai polis. Kad pengenalan anda terlibat dalam kes pengubahan wang haram. Waran tangkap akan dikeluarkan jika anda tidak bekerjasama'),
  ('Fake officer (Macau) scam', 'This call is from the court. You have an unpaid summons and a warrant for your arrest. Press 1 to speak to an officer now'),
  ('Fake officer (Macau) scam', 'Bank Negara officer here. Your account is linked to a fraud syndicate. To clear your name, move your money to the verification account and keep this confidential'),
  ('Fake officer (Macau) scam', '这里是警察局，你的身份证涉嫌洗钱，请立即把钱转到安全账户，不要告诉任何人'),
  ('Fake officer (Macau) scam', 'LHDN: anda mempunyai tunggakan cukai dan akan disenarai hitam. Hubungi pegawai kami segera untuk penyelesaian'),
  // Investment
  ('Investment scam', 'Earn 3% daily with our AI trading robot. Guaranteed returns, capital protected, withdraw anytime. Start from RM500'),
  ('Investment scam', 'Join my VIP signal group, our mentor made members 40% profit this week. Limited slots, deposit to start'),
  ('Investment scam', 'Pelaburan patuh syariah dengan pulangan 10% sebulan dijamin. Modal serendah RM300, keuntungan masuk setiap minggu'),
  ('Investment scam', 'Bro, crypto platform ni confirm untung, I already withdraw RM8k. Just top up USDT and the system trade for you'),
  ('Investment scam', 'Your account profit is RM15,000 but to withdraw you must first pay the 20% tax and unlock fee'),
  ('Investment scam', 'Exclusive gold investment, double your money in 30 days, no risk, insider tips from our senior analyst'),
  ('Investment scam', '高回报投资，日赚5%，保本零风险，导师带单，名额有限'),
  // Job and task scams
  ('Job task scam', 'Part time job from home, just like videos and follow shops. Earn RM100 to RM500 a day, paid daily. Contact HR on WhatsApp'),
  ('Job task scam', 'Kerja sambilan mudah: like video TikTok dan dapat komisen. Gaji harian RM80 hingga RM300. Tiada pengalaman diperlukan'),
  ('Job task scam', 'Hello, I am a recruiter. We need people to rate products online to boost sales. Commission per task, prepay the merchant task to unlock higher rewards'),
  ('Job task scam', 'Congrats you are selected for our online job. Complete 3 simple tasks and get RM150 instantly. Join our Telegram group to start'),
  ('Job task scam', 'Your task account is frozen because of an error. Top up RM2,000 to restore it and withdraw your commission'),
  ('Job task scam', '兼职刷单，点赞关注即可日赚300，当天结算，加我WhatsApp了解'),
  // Love scams
  ('Love scam', 'My love, I sent you a box with gold and dollars but customs are holding it. You need to pay the clearance fee to release it'),
  ('Love scam', 'Honey I am a doctor working overseas with the UN, my camera is broken so I cannot video call. Can you help me with some money for my flight?'),
  ('Love scam', 'Sayang, I really want to come see you but my account is frozen. Please bank in RM3,000 first, I will pay you back when I arrive'),
  ('Love scam', 'Hi, sorry wrong number. But you seem nice, can we be friends? I am a businesswoman in fashion and trading'),
  // Prizes, lucky draws, government aid
  ('Prize scam', 'Congratulations! You have been selected as the winner of our anniversary lucky draw. Claim your prize by paying the delivery and insurance fee'),
  ('Prize scam', 'Tahniah! Nombor anda telah memenangi hadiah wang tunai RM10,000. Sila bayar cukai hadiah untuk menuntut'),
  ('Prize scam', 'You have unclaimed reward points that expire tonight. Redeem a free gift now, only pay shipping'),
  ('Government aid scam', 'Bantuan kerajaan RM1,000 untuk anda. Daftar segera dengan nombor akaun bank dan kata laluan di pautan ini'),
  ('Government aid scam', 'You are eligible for a government cash aid payment. Confirm your banking details at the portal below to receive it today'),
  ('Tax refund scam', 'You have a pending tax refund. Submit your bank login details to receive the refund within 24 hours'),
  // Bills, fines, utilities
  ('Bill scam', 'Your electricity supply will be cut off tomorrow due to an overdue bill. Pay immediately at the link to avoid disconnection'),
  ('Bill scam', 'Saman trafik anda belum dibayar. Bayar sekarang dengan diskaun 50% sebelum tindakan mahkamah diambil'),
  ('Bill scam', 'Your mobile line will be terminated today due to unpaid charges. Settle the outstanding amount online now'),
  // Loans and debts
  ('Loan scam', 'Pinjaman peribadi lulus dalam 1 jam tanpa dokumen dan tanpa semakan CTOS. Hanya bayar yuran pemprosesan dahulu'),
  ('Loan scam', 'Your loan of RM30,000 is approved. To release the funds, transfer the insurance and processing fee to our officer'),
  ('Loan scam', 'Need money fast? Instant cash loan, no guarantor, no salary slip. Low interest. WhatsApp us now'),
  // Friend, family, new number
  ('Impersonation scam', 'Hi it is me, this is my new number. My old phone is broken. Can you transfer RM800 to my friend account first? I pay you back tomorrow'),
  ('Impersonation scam', 'Mak, ni nombor baru adik. Phone lama rosak. Boleh tolong bank in RM500 sekarang? Urgent, nanti adik ganti balik'),
  ('Impersonation scam', 'Hello, I am in a meeting and cannot talk. Please buy Google Play cards worth RM500 and send me the codes. Keep this between us'),
  ('Impersonation scam', 'Boss here. Urgently pay this new supplier invoice to the account below before 2pm, do not call, I am travelling'),
  ('Impersonation scam', 'Bro I kena accident, tak boleh call. Tolong tf RM300 ke akaun ni dulu, nanti aku bayar balik'),
  // Rental, tickets, online shopping
  ('Online purchase scam', 'Selling concert tickets cheap, cannot go anymore. Bank in full payment first and I send the e-ticket. Many buyers waiting'),
  ('Online purchase scam', 'Room for rent, fully furnished, very cheap. I am overseas so no viewing. Pay deposit to reserve and I will post the keys'),
  ('Online purchase scam', 'Your refund for the cancelled order is ready. Log in with your online banking details at the link to receive it'),
  // Crypto recovery and charity
  ('Recovery scam', 'Were you scammed? Our licensed recovery agents can get your lost funds back within days. Pay a small service fee upfront to start'),
  ('Charity scam', 'Urgent appeal: flood victims need help. Donate to our personal account now, every ringgit counts, please share widely'),
  // Malicious apps
  ('Malicious app', 'Download our app to check your parcel status. Install the APK from this link and allow all permissions'),
  ('Malicious app', 'Klinik: untuk temujanji, sila muat turun aplikasi kami melalui pautan ini dan benarkan akses SMS'),
  // Mule recruitment
  ('Mule recruitment', 'Easy money: rent out your bank account to us, we pay you RM1,000 a month. Just share your online banking username and password'),
  ('Mule recruitment', 'Nak duit cepat? Sewa akaun bank anda kepada kami, bayaran RM500 seminggu. Hanya perlu bagi ID dan kata laluan'),
  // QR and payment links
  ('Bill scam', 'Notice of unpaid parking fine. Scan the QR code to settle now and avoid a court summons'),
];

const legitCorpus = <String>[
  'Your OTP for login is 381920. It is valid for 3 minutes. Do not share it with anyone',
  'Maybank: RM120.00 was debited from your account for a DuitNow transfer. If you did not make this, call our hotline',
  'Your parcel has been delivered and signed for. Thank you for using our service',
  'Your order has been shipped. Track it in the app under My Orders',
  'Reminder: your bill of RM65.40 is due on 15 March. Pay via the official app or online banking',
  'Your appointment is confirmed for Monday at 10am. Reply STOP to unsubscribe',
  'Payment received. Thank you, your account is now up to date',
  'Kod pengesahan anda ialah 551920. Jangan kongsi kod ini dengan sesiapa',
  'Bayaran anda sebanyak RM45.00 telah diterima. Terima kasih',
  'Pesanan anda telah dihantar dan akan tiba dalam 2 hingga 3 hari bekerja',
  'Hi bro, can you transfer me RM15 for the nasi lemak just now? I forgot my wallet',
  'Mak, nanti tolong belikan roti dan susu bila balik kerja ya',
  'Dad, I reached the hostel already. Will call you tonight after class',
  'Meeting moved to 3pm, please update the slides before then',
  'Can you send me the report by tomorrow morning? Thanks',
  'Happy birthday! Hope you have an amazing day, let us makan this weekend',
  'Rent for this month is RM900, same account as last time. Thanks!',
  'Your salary has been credited to your account',
  'Your monthly statement is now available. Log in to the official app to view it',
  'We will never ask for your PIN, password or TAC by phone or message',
  'Your car service is due next week. Book a slot through our app or call the service centre',
  'The school will be closed on Friday for the public holiday',
  'Your password was changed successfully. If this was not you, contact us through the app',
  'Thank you for your donation to the mosque building fund. May you be blessed',
  'Flight MH123 is delayed by 40 minutes. We apologise for the inconvenience',
  'Your prescription is ready for collection at the pharmacy counter',
  'You earned 50 points from your purchase today. Points are valid for 12 months',
  'Congrats on your promotion! Well deserved, drinks on me',
  'Bro tmr futsal at 9pm, bring the ball ya',
  'Sayang, I will be home late tonight, traffic jam on the highway',
  'Kak, dah transfer duit kenduri tadi, check ya',
  'The water supply will be interrupted on Sunday from 9am to 5pm for maintenance',
  'Your gym membership will renew automatically on 1 April',
  'Your claim has been approved and will be paid with your next salary',
  'Abang, boleh ambil adik dari sekolah pukul 1 nanti?',
  'Your e-invoice for October is attached. Thank you for your business',
  'Hi, I am outside your house with the delivery, please come down',
  'Can lend me your charger? Mine left at home',
  'Reminder from the clinic: please fast for 8 hours before your blood test tomorrow',
  'Your library books are due back on Thursday',
  '您的验证码是 482910，五分钟内有效，请勿泄露给他人',
  '妈，我到了，晚点打给你',
  'Your bank will be performing scheduled maintenance tonight from 1am to 4am',
  'Welcome to the team! Your first day orientation starts at 9am in the lobby',
  'Thanks for the lunch today, next one on me',
];
