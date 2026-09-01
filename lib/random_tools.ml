let bernoulli rng chance =
  if chance < 0.0 || chance > 1.0 || Float.is_nan chance then
    invalid_arg "bernoulli chance must lie in [0, 1]";
  Random.State.float rng 1.0 < chance

let standard_normal rng =
  (* Box-Muller is plenty here and keeps the project dependency-free. *)
  let first_uniform = max 1e-12 (Random.State.float rng 1.0) in
  let second_uniform = Random.State.float rng 1.0 in
  sqrt (-2.0 *. log first_uniform) *. cos (2.0 *. Float.pi *. second_uniform)

let seeded ~seed ~salt = Random.State.make [| seed; salt; 0x5EED |]
