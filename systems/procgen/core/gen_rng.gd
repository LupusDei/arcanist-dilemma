class_name GenRng
## Deterministic random streams for procedural generation.
##
## Every stage of a generator draws from its own named stream, seeded from the
## parent seed plus the stream name. Adding a stage, or drawing more numbers in
## one, never changes what any other stage produces, so a village (or dungeon)
## keeps its layout when we later add details like props or damage.


static func stream(seed_value: int, stream_name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive(seed_value, stream_name)
	return rng


static func derive(seed_value: int, stream_name: String) -> int:
	return hash("%d/%s" % [seed_value, stream_name])
