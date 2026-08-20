[out:json][timeout:180];
(
 way["building"](29.15,-81.11,29.23,-81.02);
 way["landuse"~"^(forest|grass|meadow|village_green)$"](29.15,-81.11,29.23,-81.02);
 way["natural"~"^(wood|scrub)$"](29.15,-81.11,29.23,-81.02);
 way["leisure"~"^(park|garden|pitch)$"](29.15,-81.11,29.23,-81.02);
);
out geom;
