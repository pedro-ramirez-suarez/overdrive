[out:json][timeout:180];
(
 way["building"](34.825,136.515,34.865,136.555);
 way["landuse"~"^(forest|grass|meadow|village_green)$"](34.825,136.515,34.865,136.555);
 way["natural"~"^(wood|scrub)$"](34.825,136.515,34.865,136.555);
 way["leisure"~"^(park|garden|pitch)$"](34.825,136.515,34.865,136.555);
);
out geom;
