type summary = {
  mean : float;
  standard_deviation : float;
  p05 : float;
  median : float;
  p95 : float;
  standard_error : float;
}

val mean : float array -> float
val variance : float array -> float
val standard_deviation : float array -> float
val quantile : float -> float array -> float
val summarise : float array -> summary
val mean_int : int array -> float
