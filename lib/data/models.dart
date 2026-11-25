import 'dart:math' as math;

/// A person the user has tagged, with their money and reminder details.
class Person {
  Person({
    required this.id,
    required this.name,
    required this.createdAt,
    this.thumbnailPath,
    this.sampleCount = 0,
    this.usableSampleCount = 0,
    this.lentPaise = 0,
    this.repaidPaise = 0,
    this.borrowedPaise = 0,
    this.paidBackPaise = 0,
    this.notes,
    this.reminder,
    this.isOwner = false,
  });

  /// The person who owns this phone and uses Lenzo. There is at most one.
  final bool isOwner;

  final int id;
  final String name;
  final DateTime createdAt;

  /// Path to the profile photo, or the latest face crop if there is no
  /// profile photo. May be null.
  final String? thumbnailPath;

  /// Number of saved face samples for this person.
  final int sampleCount;

  /// Samples the current recognition method can use. Photos saved by older
  /// app versions don't count; the person needs to be tagged again.
  final int usableSampleCount;

  /// Total money given to this person, in paise (1/100 rupee).
  final int lentPaise;

  /// Total money this person has returned, in paise.
  final int repaidPaise;

  /// Total money taken from this person (I owe it), in paise.
  final int borrowedPaise;

  /// Total I have paid back of what I borrowed, in paise.
  final int paidBackPaise;

  // Lending and borrowing are separate directions and are never netted
  // against each other. Each is reduced only by its own repayments.

  /// What this person still owes me.
  int get toReceivePaise => math.max(0, lentPaise - repaidPaise);

  /// What I still owe this person.
  int get toPayPaise => math.max(0, borrowedPaise - paidBackPaise);

  /// They repaid more than was lent: the records disagree.
  int get overRepaidPaise => math.max(0, repaidPaise - lentPaise);

  /// I repaid more than I borrowed: the records disagree.
  int get overPaidBackPaise => math.max(0, paidBackPaise - borrowedPaise);

  /// A repayment is larger than what it repays. Shown for review instead
  /// of quietly counting as ₹0 or "settled".
  bool get needsReview => overRepaidPaise > 0 || overPaidBackPaise > 0;

  /// Whether this person is listed under [tab] on Saved People.
  bool isIn(PeopleTab tab) => switch (tab) {
    PeopleTab.receive => toReceivePaise > 0,
    PeopleTab.pay => toPayPaise > 0,
    PeopleTab.others => toReceivePaise == 0 && toPayPaise == 0,
  };

  /// Both balances are zero and the records agree.
  bool get isSettled =>
      hasMoney && !needsReview && toReceivePaise == 0 && toPayPaise == 0;

  /// Any money recorded with this person, in either direction.
  bool get hasMoney =>
      lentPaise > 0 ||
      repaidPaise > 0 ||
      borrowedPaise > 0 ||
      paidBackPaise > 0;

  /// Private note, or null if none.
  final String? notes;

  /// Payment reminder date (local, date only), or null if none.
  final DateTime? reminder;
}

/// One saved face of a person: an embedding vector used for recognition plus
/// the face crop image it was computed from.
class FaceSample {
  FaceSample({
    required this.id,
    required this.personId,
    required this.embedding,
    required this.imagePath,
  });

  final int id;
  final int personId;
  final List<double> embedding;
  final String imagePath;
}

/// Totals across several people (the owner's view).
class MoneySummary {
  const MoneySummary({
    required this.lentPaise,
    required this.borrowedPaise,
    required this.toReceivePaise,
    required this.toPayPaise,
    required this.debtors,
    required this.creditors,
    this.needsReview = 0,
  });

  factory MoneySummary.of(Iterable<Person> people) {
    var lent = 0, borrowed = 0, receive = 0, pay = 0;
    var debtors = 0, creditors = 0, review = 0;
    for (final p in people) {
      lent += p.lentPaise;
      borrowed += p.borrowedPaise;
      receive += p.toReceivePaise;
      pay += p.toPayPaise;
      if (p.toReceivePaise > 0) debtors++;
      if (p.toPayPaise > 0) creditors++;
      if (p.needsReview) review++;
    }
    return MoneySummary(
      lentPaise: lent,
      borrowedPaise: borrowed,
      toReceivePaise: receive,
      toPayPaise: pay,
      debtors: debtors,
      creditors: creditors,
      needsReview: review,
    );
  }

  final int lentPaise, borrowedPaise, toReceivePaise, toPayPaise;

  /// People who still owe me, and people I still owe.
  final int debtors, creditors;

  /// People whose records need review (a repayment larger than its loan).
  final int needsReview;

  bool get isEmpty => lentPaise == 0 && borrowedPaise == 0;
}

/// The four kinds of money record. Lending and borrowing are separate
/// accounts; each repayment kind reduces only its own account.
enum MoneyKind {
  /// I gave them money: they owe me.
  lent('lent', 'Money Lent'),

  /// I took money from them: I owe them.
  borrowed('borrowed', 'Money Borrowed'),

  /// They returned money I lent.
  repaid('repaid', 'They Repaid'),

  /// I returned money I borrowed.
  paidBack('paid_back', 'I Repaid');

  const MoneyKind(this.code, this.label);

  /// Stored in the database.
  final String code;
  final String label;

  static MoneyKind fromCode(String code) =>
      values.firstWhere((k) => k.code == code);

  /// The account this repayment reduces, or null for lent / borrowed.
  MoneyKind? get repays => switch (this) {
    repaid => lent,
    paidBack => borrowed,
    _ => null,
  };
}

/// One dated money record with a person.
class MoneyEntry {
  const MoneyEntry({
    required this.id,
    required this.personId,
    required this.kind,
    required this.amountPaise,
    required this.at,
    this.legacy = false,
  });

  final int id;
  final int personId;
  final MoneyKind kind;
  final int amountPaise;
  final DateTime at;

  /// Carried over from the running totals older versions stored. Its date
  /// is when the contact was created, not when the money moved.
  final bool legacy;

  /// Sum of [entries] per kind.
  static Map<MoneyKind, int> totals(Iterable<MoneyEntry> entries) {
    final t = {for (final k in MoneyKind.values) k: 0};
    for (final e in entries) {
      t[e.kind] = t[e.kind]! + e.amountPaise;
    }
    return t;
  }
}

/// The Saved People tabs. To Receive and To Pay hold people with that open
/// balance (someone can be in both); Others holds everyone with neither:
/// settled contacts and people saved only for recognition or notes. Every
/// saved person is in at least one tab.
enum PeopleTab { receive, pay, others }

/// One line of a money account's history: an Add or a Less and the
/// balance after it.
class LedgerLine {
  const LedgerLine({
    required this.entry,
    required this.added,
    required this.balancePaise,
  });

  final MoneyEntry entry;

  /// True for an Add (money lent / borrowed), false for a Less (repaid).
  final bool added;

  /// What was still open after this entry (never below zero).
  final int balancePaise;
}

/// The history of [account] (lent or borrowed), newest first: its own
/// entries as Adds and the repayments of it as Lesses, each with the
/// balance it left. Entries are taken in the order they were saved.
List<LedgerLine> ledgerOf(List<MoneyEntry> entries, MoneyKind account) {
  assert(account.repays == null, 'account must be lent or borrowed');
  final mine =
      [
        for (final e in entries)
          if (e.kind == account || e.kind.repays == account) e,
      ]..sort((a, b) {
        final t = a.at.compareTo(b.at);
        return t != 0 ? t : a.id.compareTo(b.id);
      });
  var balance = 0;
  final lines = <LedgerLine>[];
  for (final e in mine) {
    final added = e.kind == account;
    balance += added ? e.amountPaise : -e.amountPaise;
    lines.add(
      LedgerLine(
        entry: e,
        added: added,
        balancePaise: balance < 0 ? 0 : balance,
      ),
    );
  }
  return lines.reversed.toList();
}
