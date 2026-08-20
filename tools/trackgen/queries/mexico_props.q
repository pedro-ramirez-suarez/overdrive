[out:json][timeout:180];
(
 way["building"](19.385,-99.105,19.425,-99.065);
 way["landuse"~"^(forest|grass|meadow|village_green)$"](19.385,-99.105,19.425,-99.065);
 way["natural"~"^(wood|scrub)$"](19.385,-99.105,19.425,-99.065);
 way["leisure"~"^(park|garden|pitch)$"](19.385,-99.105,19.425,-99.065);
);
out geom;
