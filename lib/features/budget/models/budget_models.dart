class BudgetInput {
  final String? id;
  final String userId;
  final String categoryId;
  final int year;
  final int month;
  final double limitAmount;
  final bool notificationsEnabled;

  const BudgetInput({
    this.id,
    required this.userId,
    required this.categoryId,
    required this.year,
    required this.month,
    required this.limitAmount,
    required this.notificationsEnabled,
  });
}

class BudgetProgress {
  final double usageRatio;
  final double remainingAmount;
  final List<int> reachedThresholds;

  const BudgetProgress._({
    required this.usageRatio,
    required this.remainingAmount,
    required this.reachedThresholds,
  });

  factory BudgetProgress.fromAmounts({
    required double limitAmount,
    required double spentAmount,
  }) {
    if (!limitAmount.isFinite || limitAmount <= 0 || !spentAmount.isFinite) {
      throw ArgumentError(
          'Budget amounts must be finite and the limit positive');
    }
    final ratio = spentAmount / limitAmount;
    return BudgetProgress._(
      usageRatio: ratio,
      remainingAmount: (limitAmount - spentAmount).clamp(0, double.infinity),
      reachedThresholds: [
        if (ratio >= 0.8) 80,
        if (ratio >= 1) 100,
      ],
    );
  }
}

class BudgetSummary {
  final String id;
  final String userId;
  final String categoryId;
  final String categoryName;
  final int year;
  final int month;
  final double limitAmount;
  final double spentAmount;
  final bool notificationsEnabled;
  final BudgetProgress progress;

  const BudgetSummary({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.categoryName,
    required this.year,
    required this.month,
    required this.limitAmount,
    required this.spentAmount,
    required this.notificationsEnabled,
    required this.progress,
  });
}
