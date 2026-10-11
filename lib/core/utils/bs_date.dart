/// Bikram Sambat (Nepali) calendar for bills and the fiscal year.
///
/// Month lengths from the `nepali-date-converter` npm package (v3.4.0),
/// which follows the published Nepali calendar. Years beyond the published
/// calendar are projections: update [_months] when a new year is published.
library;

class BsDate {
  const BsDate(this.year, this.month, this.day);

  final int year;

  /// 1 = Baisakh ... 12 = Chaitra.
  final int month;
  final int day;

  static const monthNames = ['Baisakh', 'Jestha', 'Asar', 'Shrawan', 'Bhadra', 'Aswin', 'Kartik', 'Mangsir', 'Poush', 'Magh', 'Falgun', 'Chaitra'];

  static const firstYear = 2075;
  static int get lastYear => firstYear + _months.length - 1;

  /// AD date of [firstYear] Baisakh 1.
  static final _epoch = DateTime(2018, 4, 14);

  static int _daysInYear(int year) => _months[year - firstYear].fold(0, (s, d) => s + d);

  static int daysInMonth(int year, int month) => _months[year - firstYear][month - 1];

  /// Throws [RangeError] outside [firstYear]..[lastYear].
  factory BsDate.fromAd(DateTime ad) {
    var days = DateTime(ad.year, ad.month, ad.day).difference(_epoch).inDays;
    if (days < 0) throw RangeError('Before ${BsDate.firstYear} BS');
    var year = firstYear;
    while (days >= _daysInYear(year)) {
      days -= _daysInYear(year);
      year++;
      if (year > lastYear) throw RangeError('After $lastYear BS');
    }
    var month = 1;
    while (days >= daysInMonth(year, month)) {
      days -= daysInMonth(year, month);
      month++;
    }
    return BsDate(year, month, days + 1);
  }

  DateTime toAd() {
    var days = day - 1;
    for (var y = firstYear; y < year; y++) {
      days += _daysInYear(y);
    }
    for (var m = 1; m < month; m++) {
      days += daysInMonth(year, m);
    }
    return DateTime(_epoch.year, _epoch.month, _epoch.day + days);
  }

  /// Fiscal year (Shrawan 1 – Asar end) containing this date, by its
  /// starting BS year: 2082 means 2082/83.
  int get fiscalYear => month >= 4 ? year : year - 1;

  /// "2082/83".
  static String fiscalYearLabel(int startYear) => '$startYear/${(startYear + 1) % 100}';

  /// First and last AD day of fiscal year [startYear].
  static (DateTime, DateTime) fiscalYearRange(int startYear) {
    final start = BsDate(startYear, 4, 1).toAd();
    final end = BsDate(startYear + 1, 4, 1).toAd().subtract(const Duration(days: 1));
    return (start, end);
  }

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) => other is BsDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// "2082-06-25 BS".
String formatBs(DateTime ad) {
  try {
    return '${BsDate.fromAd(ad)} BS';
  } on RangeError {
    return '';
  }
}

const _months = [
  [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30], // 2075
  [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30], // 2076
  [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31], // 2077
  [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30], // 2078
  [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30], // 2079
  [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30], // 2080
  [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31], // 2081
  [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30], // 2082
  [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30], // 2083
  [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 31], // 2084
  [30, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31], // 2085
  [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30], // 2086
  [31, 31, 32, 31, 31, 31, 30, 30, 29, 30, 30, 30], // 2087
  [30, 31, 32, 32, 30, 31, 30, 30, 29, 30, 30, 30], // 2088
  [30, 32, 31, 32, 31, 30, 30, 30, 29, 30, 30, 30], // 2089
  [30, 32, 31, 32, 31, 30, 30, 30, 29, 30, 30, 30], // 2090
];
