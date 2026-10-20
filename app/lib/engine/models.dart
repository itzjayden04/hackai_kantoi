/// Core data types shared by every part of the Kantoi engine.
library;

enum Source { paste, whatsappWeb, telegramWeb, screenshot, qr, chatExport, questionnaire }

enum EntityType { url, phone, bankAccount, email, cryptoWallet, amount, handle }

class Entity {
  final EntityType type;
  final String value;
  final int start;
  final int end;
  const Entity(this.type, this.value, this.start, this.end);

  Map<String, dynamic> toJson() =>
      {'type': type.name, 'value': value, 'start': start, 'end': end};
}

/// Everything Kantoi is asked to look at becomes one Artefact, so every check
/// downstream works on the same object regardless of where it came from.
class Artefact {
  final String text;
  final Source source;
  final DateTime receivedAt;
  final String? sender;
  final List<Entity> entities;
  const Artefact({
    required this.text,
    required this.source,
    required this.receivedAt,
    this.sender,
    this.entities = const [],
  });
}

enum CueCategory {
  urgency,
  authority,
  fear,
  reward,
  payment,
  secrecy,
  credentials,
  channelSwitch,
  investment,
  romance,
  impersonation,
  link,
  obfuscation,
  aiManipulation,
  legitimacy,
}

String cueLabel(CueCategory c) => switch (c) {
      CueCategory.urgency => 'Urgency',
      CueCategory.authority => 'Authority',
      CueCategory.fear => 'Fear or threat',
      CueCategory.reward => 'Too-good reward',
      CueCategory.payment => 'Payment pressure',
      CueCategory.secrecy => 'Secrecy',
      CueCategory.credentials => 'Asks for login, OTP or PIN',
      CueCategory.channelSwitch => 'Moves you to another app',
      CueCategory.investment => 'Investment or task scheme',
      CueCategory.romance => 'Fast emotional bond',
      CueCategory.impersonation => 'Impersonation',
      CueCategory.link => 'Suspicious link',
      CueCategory.obfuscation => 'Hidden or disguised text',
      CueCategory.aiManipulation => 'Tries to trick AI checkers',
      CueCategory.legitimacy => 'Sign of legitimacy',
    };

/// One piece of evidence. [weight] is positive for risk, negative for
/// legitimacy. [start]/[end] point into the artefact text when the cue is a
/// quotable span, so the UI can highlight it.
class Finding {
  final CueCategory category;
  final String title;
  final String explanation;
  final int weight;
  final int? start;
  final int? end;
  final String tool;
  const Finding({
    required this.category,
    required this.title,
    required this.explanation,
    required this.weight,
    required this.tool,
    this.start,
    this.end,
  });

  bool get isRisk => weight > 0;

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'label': cueLabel(category),
        'title': title,
        'explanation': explanation,
        'weight': weight,
        'start': start,
        'end': end,
        'tool': tool,
      };
}

enum StepStatus { running, done, skipped, failed }

/// One line of the activity log: what Kantoi did, with which tool, and what
/// left the device (if anything).
class LogStep {
  final String tool;
  final String action;
  String result;
  StepStatus status;
  final bool sentOffDevice;
  final DateTime at;
  LogStep({
    required this.tool,
    required this.action,
    this.result = '',
    this.status = StepStatus.running,
    this.sentOffDevice = false,
  }) : at = DateTime.now();

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'action': action,
        'result': result,
        'status': status.name,
        'sentOffDevice': sentOffDevice,
      };
}

enum RiskLevel { safe, caution, suspicious, danger }

String riskLabel(RiskLevel r) => switch (r) {
      RiskLevel.safe => 'Looks safe',
      RiskLevel.caution => 'Be careful',
      RiskLevel.suspicious => 'Suspicious',
      RiskLevel.danger => 'Very likely a scam',
    };

class Verdict {
  final int score; // 0-100
  final RiskLevel level;
  final int confidence; // 0-100
  final String headline;
  final String scamType;
  final String nextStep;
  final List<String> whatWouldChange;
  final List<String> notChecked;
  const Verdict({
    required this.score,
    required this.level,
    required this.confidence,
    required this.headline,
    required this.scamType,
    required this.nextStep,
    this.whatWouldChange = const [],
    this.notChecked = const [],
  });

  Map<String, dynamic> toJson() => {
        'score': score,
        'level': level.name,
        'label': riskLabel(level),
        'confidence': confidence,
        'headline': headline,
        'scamType': scamType,
        'nextStep': nextStep,
        'whatWouldChange': whatWouldChange,
        'notChecked': notChecked,
      };
}

class Investigation {
  final Artefact artefact;
  final List<Finding> findings;
  final List<LogStep> log;
  final Verdict verdict;
  final List<UrlReport> urls;
  /// Which known scam script the message follows, and how far along it is.
  final ScriptProgress? script;
  const Investigation({
    required this.artefact,
    required this.findings,
    required this.log,
    required this.verdict,
    required this.urls,
    this.script,
  });

  Map<String, dynamic> toJson() => {
        'text': artefact.text,
        'verdict': verdict.toJson(),
        'findings': findings.map((f) => f.toJson()).toList(),
        'log': log.map((s) => s.toJson()).toList(),
        'entities': artefact.entities.map((e) => e.toJson()).toList(),
        'urls': urls.map((u) => u.toJson()).toList(),
        if (script != null) 'script': script!.toJson(),
      };
}

/// Where a message sits in a known scam script, e.g. step 3 of 5 of a job
/// task scam.
class ScriptProgress {
  final String script;
  final List<String> stages;
  /// Zero-based index of the furthest stage the message reached.
  final int stage;
  final Set<int> matched;
  const ScriptProgress({required this.script, required this.stages, required this.stage, this.matched = const {}});
  Map<String, dynamic> toJson() =>
      {'script': script, 'stages': stages, 'stage': stage, 'matched': matched.toList()..sort()};
}

class UrlHop {
  final String url;
  final int? status;
  // Per-hop facts from the forensic link checks (all optional).
  final String? ip;
  final String? network;
  final String? country;
  final String? tlsIssuer;
  final String? tlsSubject;
  final DateTime? tlsValidFrom;
  final bool? tlsTrusted;
  /// How this hop was reached when it was not an HTTP redirect, e.g. "page refresh tag".
  final String? via;
  const UrlHop(this.url, this.status,
      {this.ip, this.network, this.country, this.tlsIssuer, this.tlsSubject, this.tlsValidFrom, this.tlsTrusted, this.via});
  Map<String, dynamic> toJson() => {
        'url': url,
        'status': status,
        if (ip != null) 'ip': ip,
        if (network != null) 'network': network,
        if (country != null) 'country': country,
        if (tlsIssuer != null) 'tlsIssuer': tlsIssuer,
        if (tlsSubject != null) 'tlsSubject': tlsSubject,
        if (tlsValidFrom != null) 'tlsValidFrom': tlsValidFrom!.toIso8601String(),
        if (tlsTrusted != null) 'tlsTrusted': tlsTrusted,
        if (via != null) 'via': via,
      };
}

class UrlReport {
  final String input;
  final String finalUrl;
  final String host;
  final List<UrlHop> hops;
  final int? domainAgeDays;
  final String? registrar;
  final bool official;
  final String? imitates;
  // Results of the deeper forensic link checks (all optional).
  final String? pageTitle;
  final String? screenshotUrl;
  final String? remoteVerdict;
  final String? remoteFinalUrl;
  final List<String> reputationHits;
  final bool? cloaked;
  const UrlReport({
    required this.input,
    required this.finalUrl,
    required this.host,
    required this.hops,
    this.domainAgeDays,
    this.registrar,
    this.official = false,
    this.imitates,
    this.pageTitle,
    this.screenshotUrl,
    this.remoteVerdict,
    this.remoteFinalUrl,
    this.reputationHits = const [],
    this.cloaked,
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'finalUrl': finalUrl,
        'host': host,
        'hops': hops.map((h) => h.toJson()).toList(),
        'domainAgeDays': domainAgeDays,
        'registrar': registrar,
        'official': official,
        'imitates': imitates,
        if (pageTitle != null) 'pageTitle': pageTitle,
        if (screenshotUrl != null) 'screenshotUrl': screenshotUrl,
        if (remoteVerdict != null) 'remoteVerdict': remoteVerdict,
        if (remoteFinalUrl != null) 'remoteFinalUrl': remoteFinalUrl,
        if (reputationHits.isNotEmpty) 'reputationHits': reputationHits,
        if (cloaked != null) 'cloaked': cloaked,
      };
}
