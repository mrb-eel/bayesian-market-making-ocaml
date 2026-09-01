type summary = {
  mean : float;
  standard_deviation : float;
  p05 : float;
  median : float;
  p95 : float;
  standard_error : float;
}

let require_non_empty values =
  if Array.length values = 0 then invalid_arg "statistic requires at least one observation"

let mean values =
  require_non_empty values;
  Array.fold_left ( +. ) 0.0 values /. float_of_int (Array.length values)

let variance values =
  require_non_empty values;
  if Array.length values = 1 then 0.0
  else
    let sample_mean = mean values in
    let squared_gap =
      Array.fold_left
        (fun running_total observation ->
          running_total +. ((observation -. sample_mean) ** 2.0))
        0.0 values
    in
    squared_gap /. float_of_int (Array.length values - 1)

let standard_deviation values = sqrt (variance values)

let quantile probability values =
  require_non_empty values;
  if probability < 0.0 || probability > 1.0 || Float.is_nan probability then
    invalid_arg "quantile probability must lie in [0, 1]";
  let sorted = Array.copy values in
  Array.sort Float.compare sorted;
  let scaled_index = probability *. float_of_int (Array.length sorted - 1) in
  let lower_slot = int_of_float (floor scaled_index) in
  let upper_slot = int_of_float (ceil scaled_index) in
  if lower_slot = upper_slot then sorted.(lower_slot)
  else
    let upper_weight = scaled_index -. float_of_int lower_slot in
    (sorted.(lower_slot) *. (1.0 -. upper_weight))
    +. (sorted.(upper_slot) *. upper_weight)

let summarise values =
  let sample_mean = mean values in
  let sample_sd = standard_deviation values in
  {
    mean = sample_mean;
    standard_deviation = sample_sd;
    p05 = quantile 0.05 values;
    median = quantile 0.50 values;
    p95 = quantile 0.95 values;
    standard_error = sample_sd /. sqrt (float_of_int (Array.length values));
  }

let mean_int values =
  if Array.length values = 0 then invalid_arg "mean_int requires observations";
  Array.fold_left (fun total observation -> total + observation) 0 values
  |> float_of_int
  |> fun total -> total /. float_of_int (Array.length values)
