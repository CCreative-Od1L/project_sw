/// The outcome of an operation with an explicitly modelled business failure.
sealed class Result<T, F> {
  /// Creates a result.
  const Result();

  /// Whether this result represents a successful operation.
  bool get isSuccess;
}

/// A successful [Result] containing [value].
final class Success<T, F> extends Result<T, F> {
  /// Creates a successful result.
  const Success(this.value);

  /// The successful operation value.
  final T value;

  @override
  bool get isSuccess => true;
}

/// A business failure [Result] containing [failure].
final class Failure<T, F> extends Result<T, F> {
  /// Creates a failed result.
  const Failure(this.failure);

  /// The stable, use-case-specific business failure.
  final F failure;

  @override
  bool get isSuccess => false;
}
