/// Official numbers for scam victims. Every number here was checked on the
/// bank's or the government's own website (October 2026); the source is next
/// to each entry. Banks whose number could not be confirmed are left out on
/// purpose: a wrong number in an emergency is worse than none.
library;

class Hotline {
  final String bank;
  final String short;
  final String label;
  final String number;

  /// Opening hours as the source states them, or null when it says none.
  final String? hours;
  const Hotline(this.bank, this.short, this.label, this.number, {this.hours});

  /// Digits only, for a tel: link.
  String get dial => number.replaceAll(RegExp(r'[^0-9+]'), '');
}

// https://www.malaysia.gov.my/en/topics/nsrc-997-hotline ("Daily (24 hours)")
// https://support.tngdigital.com.my/hc/en-my/articles/360057510174 ("24 hours, Monday to Sunday (including public holidays)")
const nsrcNumber = '997';
const nsrcHours = 'Open 24 hours, every day';

const bankHotlines = [
  // https://www.maybank2u.com.my/maybank2u/malaysia/en/personal/about_us/contact_us.page
  // "Maybank's Fraud Hotline (24 hours a day): +603 5891 4744"
  Hotline('Maybank', 'MB', 'Fraud Hotline', '03-5891 4744', hours: '24 hours'),
  // https://www.rhbgroup.com/-/media/Files/others/highlights/announcements/H20250925-2.pdf
  // "RHB's 24/7 Hotline 03-9206 8118"
  Hotline('RHB', 'RHB', '24/7 Hotline', '03-9206 8118', hours: '24 hours'),
  // https://www.hlb.com.my/en/business-banking/connect-biz/report-a-scam-fraud.html
  // "HLB Contact Centre, 24 hours Daily: 03-7626 8899"
  Hotline('Hong Leong Bank', 'HLB', 'Contact Centre (scam reports)', '03-7626 8899', hours: '24 hours'),
  // https://www.pbebank.com/en/digital-banking/pbe-online-banking/faq/pbe-online-banking/how-to-report-fraud/
  // "How to Report Fraud: Case Management 03-2177 3555" (no hours given)
  Hotline('Public Bank', 'PBB', 'Fraud case management', '03-2177 3555'),
  // https://www.ambank.com.my/announcements/2026/revision-to-ambank-contact-centre-operating-hours
  // "+603 2178 8888 (General)"; "24/7 access to our Contact Centre to report ... suspected fraudulent/scam incident"
  Hotline('AmBank', 'AM', 'Contact Centre (scam reports 24/7)', '03-2178 8888', hours: '24 hours for scam reports'),
  // https://www.bsn.com.my/page/call-us
  // "Contact Centre, Report Fraud and Scam: +603 - 2613 1900", 8am-10pm, automated fraud line after 10pm
  Hotline('BSN', 'BSN', 'Contact Centre (fraud and scam)', '03-2613 1900', hours: '8am to 10pm, automated line after'),
  // https://bankislam.com/?p=18328 (Scam Alert: "please call us immediately at 603-2690 0900")
  Hotline('Bank Islam', 'BI', 'Contact Centre', '03-2690 0900'),
];
